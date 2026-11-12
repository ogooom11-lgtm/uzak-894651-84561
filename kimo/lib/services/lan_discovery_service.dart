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
    this.state = const {},
  });

  final String deviceId;
  final String deviceName;
  final String ip;
  final int httpPort;
  final int udpPort;
  final String os;
  final DateTime lastSeenAt;
  final int? pingMs;
  final Map<String, dynamic> state;

  bool get isFresh =>
      DateTime.now().difference(lastSeenAt).inSeconds <= 15;

  LanDeviceInfo copyWith({
    String? deviceId,
    String? deviceName,
    String? ip,
    int? httpPort,
    int? udpPort,
    String? os,
    DateTime? lastSeenAt,
    int? pingMs,
    Map<String, dynamic>? state,
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
      state: state ?? this.state,
    );
  }
}

class LanDiscoveryService {
  LanDiscoveryService._();

  static final LanDiscoveryService instance = LanDiscoveryService._();

  RawDatagramSocket? _udpSocket;
  Timer? _probeTimer;
  Timer? _subnetScanTimer;
  Timer? _cleanupTimer;
  bool _running = false;
  bool _isScanningSubnet = false;

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

    _probeTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      sendDiscoveryProbe();
    });
    sendDiscoveryProbe();

    // Fast subnet scan immediately upon startup and periodically every 25 seconds
    _subnetScanTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(scanLocalSubnet());
    });
    unawaited(scanLocalSubnet());

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

  /// Concurrently scan the current local Wi-Fi /24 subnet (e.g. 192.168.1.1 - 254)
  /// This guarantees immediate auto-discovery even when Wi-Fi router blocks UDP broadcast/multicast.
  Future<List<LanDeviceInfo>> scanLocalSubnet() async {
    if (_isScanningSubnet) return _discovered.values.toList();
    _isScanningSubnet = true;

    final found = <LanDeviceInfo>[];
    try {
      final subnets = await _getLocalSubnetPrefixes();
      for (final prefix in subnets) {
        // Probe in parallel batches of 25
        const batchSize = 25;
        for (int i = 1; i <= 254; i += batchSize) {
          final tasks = <Future<LanDeviceInfo?>>[];
          final end = (i + batchSize - 1).clamp(1, 254);
          for (int ipSuffix = i; ipSuffix <= end; ipSuffix++) {
            final targetIp = '$prefix$ipSuffix';
            tasks.add(probeSpecificIp(targetIp, timeoutMs: 650));
          }
          final results = await Future.wait(tasks);
          for (final dev in results) {
            if (dev != null) found.add(dev);
          }
        }
      }
    } catch (_) {} finally {
      _isScanningSubnet = false;
    }
    return found;
  }

  Future<List<String>> _getLocalSubnetPrefixes() async {
    final prefixes = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback &&
              !addr.address.startsWith('127.') &&
              !addr.address.startsWith('169.254.')) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}.');
            }
          }
        }
      }
    } catch (_) {}

    // Fallback to common subnets if network interface enumeration is restricted
    if (prefixes.isEmpty) {
      prefixes.addAll(['192.168.1.', '192.168.0.', '192.168.2.']);
    }
    return prefixes.toList();
  }

  /// Manually probe or check a device IP (e.g. from subnet scan or manual input)
  Future<LanDeviceInfo?> probeSpecificIp(
    String ip, {
    int port = 42424,
    int timeoutMs = 1200,
  }) async {
    final client = HttpClient()..connectionTimeout = Duration(milliseconds: timeoutMs);
    final sw = Stopwatch()..start();
    try {
      final req = await client.getUrl(Uri.parse('http://$ip:$port/api/ping'));
      final resp = await req.close().timeout(Duration(milliseconds: timeoutMs));
      sw.stop();

      if (resp.statusCode == 200) {
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
            pingMs: sw.elapsedMilliseconds,
          );
          _discovered[deviceId] = info;
          _streamController.add(Map.unmodifiable(_discovered));
          return info;
        }
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
      final isStale = now.difference(val.lastSeenAt).inSeconds > 30;
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
    _subnetScanTimer?.cancel();
    _cleanupTimer?.cancel();
    _udpSocket?.close();
    _udpSocket = null;
  }
}
