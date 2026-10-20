import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LanDeviceInfo {
  const LanDeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.ip,
    this.httpPort = 42424,
    this.udpPort = 42425,
    this.os = 'Windows',
    required this.lastSeenAt,
    this.pingMs,
  });

  final String deviceId;
  final String deviceName;
  final String ip;
  final int httpPort;
  final int udpPort;
  final String os;
  final DateTime lastSeenAt;
  final int? pingMs;

  bool get isFresh =>
      DateTime.now().difference(lastSeenAt).inSeconds <= 12;

  LanDeviceInfo copyWith({
    String? deviceId,
    String? deviceName,
    String? ip,
    int? httpPort,
    int? udpPort,
    String? os,
    DateTime? lastSeenAt,
    int? pingMs,
  }) {
    return LanDeviceInfo(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      ip: ip ?? this.ip,
      httpPort: httpPort ?? this.httpPort,
      udpPort: udpPort ?? this.udpPort,
      os: os ?? this.os,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      pingMs: pingMs ?? this.pingMs,
    );
  }
}

class LanDiscoveryService {
  LanDiscoveryService._();

  static final LanDiscoveryService instance = LanDiscoveryService._();

  RawDatagramSocket? _udpSocket;
  Timer? _probeTimer;
  Timer? _cleanupTimer;
  bool _running = false;

  final Map<String, LanDeviceInfo> _discovered = {};
  final StreamController<Map<String, LanDeviceInfo>> _streamController =
      StreamController<Map<String, LanDeviceInfo>>.broadcast();

  Stream<Map<String, LanDeviceInfo>> get stream => _streamController.stream;
  Map<String, LanDeviceInfo> get discovered => Map.unmodifiable(_discovered);

  LanDeviceInfo? getDevice(String deviceId) => _discovered[deviceId];

  Future<void> start() async {
    if (_running) return;
    _running = true;

    await _initUdpListener();

    _probeTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      sendDiscoveryProbe();
    });
    sendDiscoveryProbe();

    _cleanupTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _pruneStaleDevices();
    });
  }

  Future<void> _initUdpListener() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0, // Bind to ephemeral port
        reuseAddress: true,
      );
      _udpSocket!.broadcastEnabled = true;

      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram != null) {
            _handleDatagram(datagram);
          }
        }
      });
    } catch (_) {}
  }

  void _handleDatagram(Datagram datagram) {
    try {
      final text = utf8.decode(datagram.data).trim();
      final map = (jsonDecode(text) as Map).cast<String, dynamic>();

      final type = (map['type'] ?? '').toString();
      if (type == 'KIOM_LAN_BEACON' || type == 'KIOM_DISCOVER_RESPONSE') {
        final deviceId = (map['deviceId'] ?? '').toString();
        final deviceName = (map['deviceName'] ?? 'Windows PC').toString();
        final reportedIp = (map['ip'] ?? '').toString();
        final ip = reportedIp.isNotEmpty && reportedIp != '0.0.0.0'
            ? reportedIp
            : datagram.address.address;
        final httpPort = (map['httpPort'] as num?)?.toInt() ?? 42424;
        final udpPort = (map['udpPort'] as num?)?.toInt() ?? 42425;
        final os = (map['os'] ?? 'Windows').toString();

        if (deviceId.isNotEmpty) {
          final info = LanDeviceInfo(
            deviceId: deviceId,
            deviceName: deviceName,
            ip: ip,
            httpPort: httpPort,
            udpPort: udpPort,
            os: os,
            lastSeenAt: DateTime.now(),
          );
          _discovered[deviceId] = info;
          _streamController.add(Map.unmodifiable(_discovered));
        }
      }
    } catch (_) {}
  }

  void sendDiscoveryProbe() {
    if (_udpSocket == null) return;
    try {
      final probe = jsonEncode({
        'type': 'KIOM_DISCOVER',
        'timestamp': DateTime.now().toIso8601String(),
      });
      final bytes = utf8.encode(probe);
      _udpSocket!.send(bytes, InternetAddress('255.255.255.255'), 42425);
    } catch (_) {}
  }

  /// Manually add or check a device IP (e.g. from manual IP input)
  Future<LanDeviceInfo?> probeSpecificIp(String ip, {int port = 42424}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(Uri.parse('http://$ip:$port/api/ping'));
      final resp = await req.close().timeout(const Duration(seconds: 2));
      final bodyStr = await utf8.decodeStream(resp);
      final json = (jsonDecode(bodyStr) as Map).cast<String, dynamic>();

      final deviceId = (json['deviceId'] ?? '').toString();
      final deviceName = (json['deviceName'] ?? 'Windows PC').toString();

      if (deviceId.isNotEmpty) {
        final info = LanDeviceInfo(
          deviceId: deviceId,
          deviceName: deviceName,
          ip: ip,
          httpPort: port,
          os: (json['os'] ?? 'Windows').toString(),
          lastSeenAt: DateTime.now(),
        );
        _discovered[deviceId] = info;
        _streamController.add(Map.unmodifiable(_discovered));
        return info;
      }
    } catch (_) {} finally {
      client.close();
    }
    return null;
  }

  void _pruneStaleDevices() {
    final now = DateTime.now();
    var changed = false;
    _discovered.removeWhere((key, val) {
      final isStale = now.difference(val.lastSeenAt).inSeconds > 25;
      if (isStale) changed = true;
      return isStale;
    });
    if (changed) {
      _streamController.add(Map.unmodifiable(_discovered));
    }
  }

  void stop() {
    _running = false;
    _probeTimer?.cancel();
    _cleanupTimer?.cancel();
    _udpSocket?.close();
    _udpSocket = null;
  }
}
