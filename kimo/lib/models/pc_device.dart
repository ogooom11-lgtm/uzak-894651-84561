import '../core/date_mapper.dart';

class PcDevice {
  const PcDevice({
    required this.id,
    required this.name,
    required this.os,
    required this.appVersion,
    required this.createdAt,
    required this.linkedUserIds,
    this.lastCheckResponse,
    this.lastSeenAt,
    this.wifiStatus,
    this.bluetoothStatus,
    this.volume = 0,
    this.isMuted = false,
  });

  final String id;
  final String name;
  final String os;
  final String appVersion;
  final DateTime createdAt;
  final List<String> linkedUserIds;
  final String? lastCheckResponse;
  final DateTime? lastSeenAt;
  final String? wifiStatus;
  final String? bluetoothStatus;
  final int volume;
  final bool isMuted;

  bool get isRecentlyOnline {
    if (lastSeenAt == null) return false;
    return DateTime.now().difference(lastSeenAt!).inSeconds <= 30;
  }

  factory PcDevice.fromMap(String id, Map<String, dynamic> map) {
    return PcDevice(
      id: id,
      name: (map['name'] ?? map['computerName'] ?? 'جهاز غير معروف').toString(),
      os: (map['os'] ?? 'Windows').toString(),
      appVersion: (map['appVersion'] ?? '1.0.0').toString(),
      createdAt: dateFromAny(map['createdAt']),
      linkedUserIds: List<String>.from(map['linkedUserIds'] ?? const []),
      lastCheckResponse: map['lastCheckResponse']?.toString(),
      lastSeenAt:
          map['lastSeenAt'] == null ? null : dateFromAny(map['lastSeenAt']),
      wifiStatus: map['wifiStatus']?.toString(),
      bluetoothStatus: map['bluetoothStatus']?.toString(),
      volume: int.tryParse('${map['volume'] ?? 0}') ?? 0,
      isMuted: map['isMuted'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'os': os,
      'appVersion': appVersion,
      'createdAt': dateToFirestore(createdAt),
      'linkedUserIds': linkedUserIds,
      'lastCheckResponse': lastCheckResponse,
      'lastSeenAt': nullableDateToFirestore(lastSeenAt),
      'wifiStatus': wifiStatus,
      'bluetoothStatus': bluetoothStatus,
      'volume': volume,
      'isMuted': isMuted,
    };
  }
}
