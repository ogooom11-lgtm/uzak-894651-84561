import 'dart:convert';

class CustomSmartMode {
  const CustomSmartMode({
    required this.id,
    required this.name,
    this.description = '',
    this.iconName = 'shield',
    this.colorHex = '0xFF3B82F6',
    this.maxVolume = 100,
    this.forceMute = false,
    this.lockVolume = false,
    this.blockedApps = const [],
    this.killBlockedAppsOnActivate = true,
    this.blockedSites = const [],
    this.blockedPaths = const [],
    this.disableInternet = false,
    this.disableBluetooth = false,
    this.disableWifi = false,
    this.blockInstallations = false,
    this.enablePrivacyMode = false,
    this.lockScreenAfterMinutes = 0,
    this.durationMinutes = 0, // 0 = permanent until manual deactivate
    this.isActive = false,
    this.activatedAt,
    this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final String iconName;
  final String colorHex;

  // Audio Rules
  final int maxVolume; // 0 to 100
  final bool forceMute;
  final bool lockVolume;

  // App & Site Restrictions
  final List<String> blockedApps;
  final bool killBlockedAppsOnActivate;
  final List<String> blockedSites;
  final List<String> blockedPaths;

  // Network & Peripherals
  final bool disableInternet;
  final bool disableBluetooth;
  final bool disableWifi;

  // Security & Productivity
  final bool blockInstallations;
  final bool enablePrivacyMode;
  final int lockScreenAfterMinutes;

  // Timer
  final int durationMinutes;
  final bool isActive;
  final DateTime? activatedAt;
  final DateTime? createdAt;

  CustomSmartMode copyWith({
    String? id,
    String? name,
    String? description,
    String? iconName,
    String? colorHex,
    int? maxVolume,
    bool? forceMute,
    bool? lockVolume,
    List<String>? blockedApps,
    bool? killBlockedAppsOnActivate,
    List<String>? blockedSites,
    List<String>? blockedPaths,
    bool? disableInternet,
    bool? disableBluetooth,
    bool? disableWifi,
    bool? blockInstallations,
    bool? enablePrivacyMode,
    int? lockScreenAfterMinutes,
    int? durationMinutes,
    bool? isActive,
    DateTime? activatedAt,
    DateTime? createdAt,
  }) {
    return CustomSmartMode(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      iconName: iconName ?? this.iconName,
      colorHex: colorHex ?? this.colorHex,
      maxVolume: maxVolume ?? this.maxVolume,
      forceMute: forceMute ?? this.forceMute,
      lockVolume: lockVolume ?? this.lockVolume,
      blockedApps: blockedApps ?? this.blockedApps,
      killBlockedAppsOnActivate: killBlockedAppsOnActivate ?? this.killBlockedAppsOnActivate,
      blockedSites: blockedSites ?? this.blockedSites,
      blockedPaths: blockedPaths ?? this.blockedPaths,
      disableInternet: disableInternet ?? this.disableInternet,
      disableBluetooth: disableBluetooth ?? this.disableBluetooth,
      disableWifi: disableWifi ?? this.disableWifi,
      blockInstallations: blockInstallations ?? this.blockInstallations,
      enablePrivacyMode: enablePrivacyMode ?? this.enablePrivacyMode,
      lockScreenAfterMinutes: lockScreenAfterMinutes ?? this.lockScreenAfterMinutes,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      isActive: isActive ?? this.isActive,
      activatedAt: activatedAt ?? this.activatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'iconName': iconName,
      'colorHex': colorHex,
      'maxVolume': maxVolume,
      'forceMute': forceMute,
      'lockVolume': lockVolume,
      'blockedApps': blockedApps,
      'killBlockedAppsOnActivate': killBlockedAppsOnActivate,
      'blockedSites': blockedSites,
      'blockedPaths': blockedPaths,
      'disableInternet': disableInternet,
      'disableBluetooth': disableBluetooth,
      'disableWifi': disableWifi,
      'blockInstallations': blockInstallations,
      'enablePrivacyMode': enablePrivacyMode,
      'lockScreenAfterMinutes': lockScreenAfterMinutes,
      'durationMinutes': durationMinutes,
      'isActive': isActive,
      if (activatedAt != null) 'activatedAt': activatedAt!.toIso8601String(),
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }

  factory CustomSmartMode.fromMap(Map<String, dynamic> map) {
    return CustomSmartMode(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? 'وضع مخصص').toString(),
      description: (map['description'] ?? '').toString(),
      iconName: (map['iconName'] ?? 'shield').toString(),
      colorHex: (map['colorHex'] ?? '0xFF3B82F6').toString(),
      maxVolume: (map['maxVolume'] as num?)?.toInt() ?? 100,
      forceMute: map['forceMute'] == true,
      lockVolume: map['lockVolume'] == true,
      blockedApps: (map['blockedApps'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      killBlockedAppsOnActivate: map['killBlockedAppsOnActivate'] != false,
      blockedSites: (map['blockedSites'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      blockedPaths: (map['blockedPaths'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      disableInternet: map['disableInternet'] == true,
      disableBluetooth: map['disableBluetooth'] == true,
      disableWifi: map['disableWifi'] == true,
      blockInstallations: map['blockInstallations'] == true,
      enablePrivacyMode: map['enablePrivacyMode'] == true,
      lockScreenAfterMinutes: (map['lockScreenAfterMinutes'] as num?)?.toInt() ?? 0,
      durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? 0,
      isActive: map['isActive'] == true,
      activatedAt: map['activatedAt'] != null ? DateTime.tryParse(map['activatedAt'].toString()) : null,
      createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt'].toString()) : null,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory CustomSmartMode.fromJson(String source) => CustomSmartMode.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
