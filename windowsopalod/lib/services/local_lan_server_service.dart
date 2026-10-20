import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/agent_config.dart';
import '../services/command_executor_service.dart';
import '../services/native_input_service.dart';
import '../utils/json_file_store.dart';

class LocalLanServerService {
  LocalLanServerService({
    required this.deviceId,
    required this.deviceName,
    required this.config,
    required this.store,
    required this.executor,
    this.httpPort = 42424,
    this.udpPort = 42425,
  });

  final String deviceId;
  final String deviceName;
  final AgentConfig config;
  final JsonFileStore store;
  final CommandExecutorService executor;
  final int httpPort;
  final int udpPort;

  HttpServer? _httpServer;
  RawDatagramSocket? _udpSocket;
  Timer? _beaconTimer;
  bool _running = false;

  final Set<WebSocket> _activeWebSockets = <WebSocket>{};
  String? _localIpAddress;

  Future<void> start() async {
    if (_running) return;
    _running = true;

    await _determineLocalIp();
    await _startHttpAndWebSocketServer();
    await _startUdpDiscovery();

    stdout.writeln('Local LAN Server started on http://$_localIpAddress:$httpPort (UDP Discovery on $udpPort)');
  }

  Future<void> _determineLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254')) {
            _localIpAddress = addr.address;
            return;
          }
        }
      }
    } catch (_) {}
    _localIpAddress ??= '0.0.0.0';
  }

  Future<void> _startHttpAndWebSocketServer() async {
    try {
      _httpServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        httpPort,
        shared: true,
      );

      _httpServer!.listen(_handleHttpRequest, onError: (e) {
        stderr.writeln('LocalLanServer HTTP Error: $e');
      });
    } catch (e) {
      stderr.writeln('Failed to bind Local LAN HTTP Server on port $httpPort: $e');
    }
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    // Add CORS headers for web/mobile cross-origin requests
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    // WebSocket Upgrade Handler for Trackpad / Input
    if (path == '/ws' || path == '/ws/input') {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        try {
          final socket = await WebSocketTransformer.upgrade(request);
          _handleWebSocketClient(socket);
        } catch (e) {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        }
        return;
      }
    }

    try {
      if (path == '/' || path == '/api/ping') {
        await _respondJson(request, {
          'status': 'ok',
          'mode': 'lan_direct',
          'deviceId': deviceId,
          'deviceName': deviceName,
          'ip': _localIpAddress,
          'httpPort': httpPort,
          'udpPort': udpPort,
          'os': Platform.operatingSystem,
          'osVersion': Platform.operatingSystemVersion,
          'timestamp': DateTime.now().toIso8601String(),
        });
      } else if (path == '/api/status') {
        final state = store.get<Map<String, dynamic>>('device_state') ?? {};
        await _respondJson(request, {
          'status': 'ok',
          'deviceId': deviceId,
          'deviceName': deviceName,
          'ip': _localIpAddress,
          'state': state,
          'timestamp': DateTime.now().toIso8601String(),
        });
      } else if (path == '/api/command' && request.method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final body = (jsonDecode(bodyStr) as Map?)?.cast<String, dynamic>() ?? {};
        final cmdType = (body['type'] ?? body['command'] ?? '').toString();
        final payload = (body['payload'] as Map?)?.cast<String, dynamic>() ?? {};

        if (cmdType.isEmpty) {
          await _respondJson(request, {
            'success': false,
            'message': 'Command type missing',
          }, statusCode: HttpStatus.badRequest);
          return;
        }

        final result = await executor.executeTelegramCommand(
          type: cmdType,
          payload: payload,
        );

        await _respondJson(request, {
          'success': result.success,
          'message': result.message,
          'payload': result.payload,
          'executedAt': DateTime.now().toIso8601String(),
        });
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await _respondJson(request, {'error': 'Endpoint not found'});
      }
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      await _respondJson(request, {'error': e.toString()});
    }
  }

  Future<void> _respondJson(
    HttpRequest request,
    Map<String, dynamic> data, {
    int statusCode = HttpStatus.ok,
  }) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    final jsonStr = jsonEncode(data);
    request.response.write(jsonStr);
    await request.response.close();
  }

  void _handleWebSocketClient(WebSocket socket) {
    _activeWebSockets.add(socket);

    socket.listen(
      (data) {
        _handleWebSocketMessage(socket, data);
      },
      onDone: () {
        _activeWebSockets.remove(socket);
      },
      onError: (e) {
        _activeWebSockets.remove(socket);
      },
    );

    // Send initial welcome & handshake
    socket.add(jsonEncode({
      'action': 'handshake_ack',
      'deviceId': deviceId,
      'deviceName': deviceName,
      'status': 'connected',
    }));
  }

  void _handleWebSocketMessage(WebSocket socket, dynamic rawData) {
    try {
      Map<String, dynamic> msg;
      if (rawData is String) {
        msg = (jsonDecode(rawData) as Map).cast<String, dynamic>();
      } else if (rawData is List<int>) {
        final decoded = utf8.decode(rawData);
        msg = (jsonDecode(decoded) as Map).cast<String, dynamic>();
      } else {
        return;
      }

      final action = (msg['action'] ?? '').toString();
      final input = NativeInputService.instance;

      switch (action) {
        case 'mouse_move':
          final dx = (msg['dx'] as num?)?.toDouble() ?? 0.0;
          final dy = (msg['dy'] as num?)?.toDouble() ?? 0.0;
          final sensitivity = (msg['sensitivity'] as num?)?.toDouble() ?? 1.0;
          input.moveMouseRelative(dx, dy, sensitivity: sensitivity);
          break;

        case 'mouse_pos':
          final x = (msg['x'] as num?)?.toInt() ?? 0;
          final y = (msg['y'] as num?)?.toInt() ?? 0;
          input.moveMouseAbsolute(x, y);
          break;

        case 'mouse_click':
          final button = (msg['button'] ?? 'left').toString().toLowerCase();
          final isDouble = msg['double'] == true;
          if (isDouble) {
            input.doubleClick();
          } else if (button == 'right') {
            input.rightClick();
          } else if (button == 'middle') {
            input.middleClick();
          } else {
            input.leftClick();
          }
          break;

        case 'mouse_down':
          final button = (msg['button'] ?? 'left').toString();
          input.mouseDown(button);
          break;

        case 'mouse_up':
          final button = (msg['button'] ?? 'left').toString();
          input.mouseUp(button);
          break;

        case 'mouse_scroll':
          final dy = (msg['dy'] as num?)?.toInt() ?? 0;
          final dx = (msg['dx'] as num?)?.toInt() ?? 0;
          input.scrollWheel(dy, dx: dx);
          break;

        case 'key_press':
          final key = (msg['key'] ?? '').toString();
          if (key.isNotEmpty) {
            input.pressKey(key);
          }
          break;

        case 'key_combo':
          final rawKeys = msg['keys'] as List?;
          if (rawKeys != null && rawKeys.isNotEmpty) {
            final keys = rawKeys.map((k) => k.toString()).toList();
            input.pressKeyCombo(keys);
          }
          break;

        case 'key_type':
          final text = (msg['text'] ?? '').toString();
          if (text.isNotEmpty) {
            input.typeText(text);
          }
          break;

        case 'ping':
          final clientTime = msg['time'];
          socket.add(jsonEncode({
            'action': 'pong',
            'clientTime': clientTime,
            'serverTime': DateTime.now().millisecondsSinceEpoch,
          }));
          break;

        case 'command':
          final cmdId = (msg['id'] ?? '').toString();
          final cmdType = (msg['type'] ?? '').toString();
          final payload = (msg['payload'] as Map?)?.cast<String, dynamic>() ?? {};
          if (cmdType.isNotEmpty) {
            unawaited(() async {
              final result = await executor.executeTelegramCommand(
                type: cmdType,
                payload: payload,
              );
              socket.add(jsonEncode({
                'action': 'command_result',
                'id': cmdId,
                'type': cmdType,
                'success': result.success,
                'message': result.message,
                'payload': result.payload,
              }));
            }());
          }
          break;
      }
    } catch (e) {
      stderr.writeln('Local WebSocket message handling error: $e');
    }
  }

  Future<void> _startUdpDiscovery() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpPort,
        reuseAddress: true,
        reusePort: false,
      );
      _udpSocket!.broadcastEnabled = true;

      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram != null) {
            _handleUdpDatagram(datagram);
          }
        }
      });

      // Send periodic beacon every 3 seconds
      _beaconTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _broadcastUdpBeacon();
      });
      _broadcastUdpBeacon();
    } catch (e) {
      stderr.writeln('UDP Discovery startup error: $e');
    }
  }

  void _broadcastUdpBeacon() {
    if (_udpSocket == null) return;
    try {
      final beacon = jsonEncode({
        'type': 'KIOM_LAN_BEACON',
        'deviceId': deviceId,
        'deviceName': deviceName,
        'ip': _localIpAddress,
        'httpPort': httpPort,
        'udpPort': udpPort,
        'os': Platform.operatingSystem,
        'timestamp': DateTime.now().toIso8601String(),
      });
      final bytes = utf8.encode(beacon);
      _udpSocket!.send(bytes, InternetAddress('255.255.255.255'), udpPort);
    } catch (_) {}
  }

  void _handleUdpDatagram(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data).trim();
      if (message.contains('KIOM_DISCOVER') || message.contains('KIOM_PROBE')) {
        // Send immediate direct response to requester
        final response = jsonEncode({
          'type': 'KIOM_DISCOVER_RESPONSE',
          'deviceId': deviceId,
          'deviceName': deviceName,
          'ip': _localIpAddress,
          'httpPort': httpPort,
          'udpPort': udpPort,
          'os': Platform.operatingSystem,
          'timestamp': DateTime.now().toIso8601String(),
        });
        final bytes = utf8.encode(response);
        _udpSocket?.send(bytes, datagram.address, datagram.port);
      }
    } catch (_) {}
  }

  void stop() {
    _running = false;
    _beaconTimer?.cancel();
    _beaconTimer = null;
    for (final ws in _activeWebSockets) {
      try {
        ws.close();
      } catch (_) {}
    }
    _activeWebSockets.clear();
    _httpServer?.close(force: true);
    _httpServer = null;
    _udpSocket?.close();
    _udpSocket = null;
  }
}
