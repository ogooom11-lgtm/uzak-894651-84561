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
    this.telegramChatId,
    this.telegramBotUsername,
    this.telegramLinkedAt,
    this.activeMode,
    this.isEmergency = false,
    this.isPrivacy = false,
    this.totalInstalledApps = 0,
    this.totalOpenApps = 0,
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
  final String? telegramChatId;
  final String? telegramBotUsername;
  final DateTime? telegramLinkedAt;
  final String? activeMode;
  final bool isEmergency;
  final bool isPrivacy;
  final int totalInstalledApps;
  final int totalOpenApps;

  bool get isTelegramLinked =>
      telegramChatId != null && telegramChatId!.trim().isNotEmpty;

  bool get isRecentlyOnline {
    if (lastSeenAt == null) return false;
    return DateTime.now().difference(lastSeenAt!).inSeconds <= 30;
  }

  factory PcDevice.fromMap(String id, Map<String, dynamic> map) {
    final rawLinked = map['linkedUserIds'];
    final linkedUserIds = rawLinked is Iterable
        ? rawLinked.map((e) => e.toString()).toList()
        : const <String>[];

    return PcDevice(
      id: id,
      name: (map['name'] ?? map['computerName'] ?? 'جهاز غير معروف').toString(),
      os: (map['os'] ?? 'Windows').toString(),
      appVersion: (map['appVersion'] ?? '1.0.0').toString(),
      createdAt: dateFromAny(map['createdAt']),
      linkedUserIds: linkedUserIds,
      lastCheckResponse: map['lastCheckResponse']?.toString(),
      lastSeenAt:
          map['lastSeenAt'] == null ? null : dateFromAny(map['lastSeenAt']),
      wifiStatus: map['wifiStatus']?.toString(),
      bluetoothStatus: map['bluetoothStatus']?.toString(),
      volume: int.tryParse('${map['volume'] ?? 0}') ?? 0,
      isMuted: map['isMuted'] == true,
      telegramChatId: map['telegramChatId']?.toString(),
      telegramBotUsername: map['telegramBotUsername']?.toString(),
      telegramLinkedAt: map['telegramLinkedAt'] == null
          ? null
          : dateFromAny(map['telegramLinkedAt']),
      activeMode: map['activeMode']?.toString(),
      isEmergency: map['isEmergency'] == true || map['emergency'] == true,
      isPrivacy: map['isPrivacy'] == true || map['privacy'] == true,
      totalInstalledApps: int.tryParse('${map['totalInstalledApps'] ?? 0}') ?? 0,
      totalOpenApps: int.tryParse('${map['totalOpenApps'] ?? 0}') ?? 0,
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
      'telegramChatId': telegramChatId,
      'telegramBotUsername': telegramBotUsername,
      'telegramLinkedAt': nullableDateToFirestore(telegramLinkedAt),
      'activeMode': activeMode,
      'isEmergency': isEmergency,
      'isPrivacy': isPrivacy,
      'totalInstalledApps': totalInstalledApps,
      'totalOpenApps': totalOpenApps,
    };
  }
}
