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
    this.lanIp,
    this.lanPort = 42424,
    this.isLanOnline = false,
    this.lanPingMs,
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
  final String? lanIp;
  final int lanPort;
  final bool isLanOnline;
  final int? lanPingMs;

  bool get isTelegramLinked =>
      telegramChatId != null && telegramChatId!.trim().isNotEmpty;

  bool get isRecentlyOnline {
    if (isLanOnline) return true;
    if (lastSeenAt == null) return false;
    return DateTime.now().difference(lastSeenAt!).inSeconds <= 30;
  }

  PcDevice copyWith({
    String? id,
    String? name,
    String? os,
    String? appVersion,
    DateTime? createdAt,
    List<String>? linkedUserIds,
    String? lastCheckResponse,
    DateTime? lastSeenAt,
    String? wifiStatus,
    String? bluetoothStatus,
    int? volume,
    bool? isMuted,
    String? telegramChatId,
    String? telegramBotUsername,
    DateTime? telegramLinkedAt,
    String? activeMode,
    bool? isEmergency,
    bool? isPrivacy,
    int? totalInstalledApps,
    int? totalOpenApps,
    String? lanIp,
    int? lanPort,
    bool? isLanOnline,
    int? lanPingMs,
  }) {
    return PcDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      os: os ?? this.os,
      appVersion: appVersion ?? this.appVersion,
      createdAt: createdAt ?? this.createdAt,
      linkedUserIds: linkedUserIds ?? this.linkedUserIds,
      lastCheckResponse: lastCheckResponse ?? this.lastCheckResponse,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      wifiStatus: wifiStatus ?? this.wifiStatus,
      bluetoothStatus: bluetoothStatus ?? this.bluetoothStatus,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      telegramChatId: telegramChatId ?? this.telegramChatId,
      telegramBotUsername: telegramBotUsername ?? this.telegramBotUsername,
      telegramLinkedAt: telegramLinkedAt ?? this.telegramLinkedAt,
      activeMode: activeMode ?? this.activeMode,
      isEmergency: isEmergency ?? this.isEmergency,
      isPrivacy: isPrivacy ?? this.isPrivacy,
      totalInstalledApps: totalInstalledApps ?? this.totalInstalledApps,
      totalOpenApps: totalOpenApps ?? this.totalOpenApps,
      lanIp: lanIp ?? this.lanIp,
      lanPort: lanPort ?? this.lanPort,
      isLanOnline: isLanOnline ?? this.isLanOnline,
      lanPingMs: lanPingMs ?? this.lanPingMs,
    );
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
      lanIp: map['lanIp']?.toString(),
      lanPort: int.tryParse('${map['lanPort'] ?? 42424}') ?? 42424,
      isLanOnline: map['isLanOnline'] == true,
      lanPingMs: int.tryParse('${map['lanPingMs'] ?? ''}'),
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
      if (lanIp != null) 'lanIp': lanIp,
      'lanPort': lanPort,
      'isLanOnline': isLanOnline,
      if (lanPingMs != null) 'lanPingMs': lanPingMs,
    };
  }
}
