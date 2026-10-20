import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum LanConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class LanDeviceClient {
  LanDeviceClient({
    required this.host,
    this.port = 42424,
  });

  final String host;
  final int port;

  WebSocket? _socket;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _disposed = false;

  final StreamController<LanConnectionState> _stateController =
      StreamController<LanConnectionState>.broadcast();
  final StreamController<int> _latencyController =
      StreamController<int>.broadcast();
  final StreamController<Map<String, dynamic>> _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();

  final Map<String, Completer<Map<String, dynamic>>> _pendingCommands = {};

  LanConnectionState _currentState = LanConnectionState.disconnected;

  Stream<LanConnectionState> get stateStream => _stateController.stream;
  Stream<int> get latencyStream => _latencyController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messagesController.stream;
  LanConnectionState get state => _currentState;
  bool get isConnected => _currentState == LanConnectionState.connected;

  String get baseUrl => 'http://$host:$port';
  String get wsUrl => 'ws://$host:$port/ws';

  Future<void> connect() async {
    if (_disposed || _currentState == LanConnectionState.connected) return;
    _setState(LanConnectionState.connecting);

    try {
      final uri = Uri.parse(wsUrl);
      _socket = await WebSocket.connect(
        uri.toString(),
      ).timeout(const Duration(seconds: 4));

      _setState(LanConnectionState.connected);

      _socket!.listen(
        _handleMessage,
        onDone: _handleDisconnect,
        onError: (e) => _handleDisconnect(),
      );

      _startPingLoop();
    } catch (e) {
      _setState(LanConnectionState.disconnected);
    }
  }

  void _setState(LanConnectionState state) {
    if (_currentState != state) {
      _currentState = state;
      _stateController.add(state);
    }
  }

  void _startPingLoop() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      ping();
    });
    ping();
  }

  void _handleMessage(dynamic raw) {
    try {
      Map<String, dynamic> data;
      if (raw is String) {
        data = (jsonDecode(raw) as Map).cast<String, dynamic>();
      } else if (raw is List<int>) {
        data = (jsonDecode(utf8.decode(raw)) as Map).cast<String, dynamic>();
      } else {
        return;
      }

      final action = (data['action'] ?? '').toString();

      if (action == 'pong') {
        final clientTime = data['clientTime'];
        if (clientTime is num) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final rtt = now - clientTime.toInt();
          if (rtt >= 0 && rtt < 5000) {
            _latencyController.add(rtt);
          }
        }
      } else if (action == 'command_result') {
        final id = (data['id'] ?? '').toString();
        if (id.isNotEmpty && _pendingCommands.containsKey(id)) {
          _pendingCommands.remove(id)?.complete(data);
        }
      }

      _messagesController.add(data);
    } catch (_) {}
  }

  void _handleDisconnect() {
    _socket = null;
    _pingTimer?.cancel();
    _setState(LanConnectionState.disconnected);

    if (!_disposed) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        if (!_disposed && _currentState != LanConnectionState.connected) {
          connect();
        }
      });
    }
  }

  void sendRaw(Map<String, dynamic> data) {
    if (_socket != null && _socket!.readyState == WebSocket.open) {
      try {
        _socket!.add(jsonEncode(data));
      } catch (_) {}
    }
  }

  void ping() {
    sendRaw({
      'action': 'ping',
      'time': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // Mouse Actions
  void sendMouseMove(double dx, double dy, {double sensitivity = 1.0}) {
    sendRaw({
      'action': 'mouse_move',
      'dx': dx,
      'dy': dy,
      'sensitivity': sensitivity,
    });
  }

  void sendMouseClick(String button, {bool isDouble = false}) {
    sendRaw({
      'action': 'mouse_click',
      'button': button,
      'double': isDouble,
    });
  }

  void sendMouseDown(String button) {
    sendRaw({
      'action': 'mouse_down',
      'button': button,
    });
  }

  void sendMouseUp(String button) {
    sendRaw({
      'action': 'mouse_up',
      'button': button,
    });
  }

  void sendMouseScroll(int dy, {int dx = 0}) {
    sendRaw({
      'action': 'mouse_scroll',
      'dy': dy,
      'dx': dx,
    });
  }

  // Keyboard Actions
  void sendKeyPress(String key) {
    sendRaw({
      'action': 'key_press',
      'key': key,
    });
  }

  void sendKeyCombo(List<String> keys) {
    sendRaw({
      'action': 'key_combo',
      'keys': keys,
    });
  }

  void sendKeyType(String text) {
    sendRaw({
      'action': 'key_type',
      'text': text,
    });
  }

  // Direct High-Speed Command Execution (WebSocket first, HTTP fallback)
  Future<Map<String, dynamic>> sendCommand(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final cmdId = 'cmd_${DateTime.now().millisecondsSinceEpoch}';

    if (isConnected && _socket != null) {
      final completer = Completer<Map<String, dynamic>>();
      _pendingCommands[cmdId] = completer;

      sendRaw({
        'action': 'command',
        'id': cmdId,
        'type': type,
        'payload': payload,
      });

      try {
        final result = await completer.future.timeout(timeout);
        return result;
      } catch (_) {
        _pendingCommands.remove(cmdId);
      }
    }

    // HTTP POST fallback
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client.postUrl(Uri.parse('$baseUrl/api/command'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'type': type,
        'payload': payload,
      }));
      final resp = await req.close().timeout(timeout);
      final bodyStr = await utf8.decodeStream(resp);
      final json = (jsonDecode(bodyStr) as Map?)?.cast<String, dynamic>() ?? {};
      return json;
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>?> checkPing() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/api/ping'));
      final resp = await req.close().timeout(const Duration(seconds: 2));
      final bodyStr = await utf8.decodeStream(resp);
      return (jsonDecode(bodyStr) as Map?)?.cast<String, dynamic>();
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  void dispose() {
    _disposed = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    for (final completer in _pendingCommands.values) {
      if (!completer.isCompleted) {
        completer.completeError('Client disposed');
      }
    }
    _pendingCommands.clear();
    try {
      _socket?.close();
    } catch (_) {}
    _stateController.close();
    _latencyController.close();
    _messagesController.close();
  }
}
