class PcDevice {
  final String id;
  final String name;
  final String os;
  final String windowsUser;
  final String appVersion;
  final DateTime firstRegisteredAt;

  const PcDevice({
    required this.id,
    required this.name,
    required this.os,
    required this.windowsUser,
    required this.appVersion,
    required this.firstRegisteredAt,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'os': os,
        'windowsUser': windowsUser,
        'appVersion': appVersion,
        'firstRegisteredAt': firstRegisteredAt.toIso8601String(),
        'status': 'registered',
        'lastCheckResponse': 'لم يتم الفحص بعد',
        'wifiStatus': 'unknown',
        'bluetoothStatus': 'unknown',
        'volume': 50,
        'isMuted': false,
      };

  factory PcDevice.fromMap(String id, Map<String, dynamic> map) {
    return PcDevice(
      id: id,
      name: (map['name'] ?? 'Unknown-PC').toString(),
      os: (map['os'] ?? 'Windows').toString(),
      windowsUser: (map['windowsUser'] ?? '').toString(),
      appVersion: (map['appVersion'] ?? '0.1.0').toString(),
      firstRegisteredAt:
          DateTime.tryParse((map['firstRegisteredAt'] ?? '').toString()) ??
              DateTime.now(),
    );
  }
}
