import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/custom_smart_mode.dart';

class CustomModesStore {
  CustomModesStore._();

  static final CustomModesStore instance = CustomModesStore._();

  static const String _key = 'kiom_custom_smart_modes';

  static final List<CustomSmartMode> _defaultPresets = [
    const CustomSmartMode(
      id: 'preset_study_focus',
      name: 'وضع المذاكرة والتركيز العالي',
      description: 'كتم صوت التنبيهات، خفض الصوت لـ 30%، وحظر الألعاب ومواقع التواصل الاجتماعي.',
      iconName: 'school',
      colorHex: '0xFF3B82F6',
      maxVolume: 30,
      lockVolume: true,
      blockedApps: ['discord.exe', 'steam.exe', 'epicgames.exe', 'telegram.exe', 'spotify.exe'],
      killBlockedAppsOnActivate: true,
      blockedSites: ['youtube.com', 'tiktok.com', 'facebook.com', 'instagram.com', 'twitter.com', 'reddit.com', 'twitch.tv'],
      blockInstallations: true,
    ),
    const CustomSmartMode(
      id: 'preset_kids_safety',
      name: 'وضع الأطفال والإنترنت الآمن',
      description: 'حظر الألعاب والتطبيقات الحساسة ومنع رفع الصوت فوق 40% ومنع تثبيت البرامج.',
      iconName: 'child_care',
      colorHex: '0xFF10B981',
      maxVolume: 40,
      lockVolume: true,
      blockedApps: ['cmd.exe', 'powershell.exe', 'regedit.exe', 'taskmgr.exe', 'steam.exe'],
      killBlockedAppsOnActivate: true,
      blockedSites: ['discord.com', 'reddit.com', 'omegle.com', 'tiktok.com'],
      blockInstallations: true,
    ),
    const CustomSmartMode(
      id: 'preset_silent_meeting',
      name: 'وضع الاجتماعات والهدوء التام',
      description: 'كتم صوت الكمبيوتر بالكامل ومنع أي أصوات أو تشغيل وسائط مفاجئة.',
      iconName: 'volume_off',
      colorHex: '0xFF8B5CF6',
      maxVolume: 0,
      forceMute: true,
      lockVolume: true,
      enablePrivacyMode: true,
    ),
    const CustomSmartMode(
      id: 'preset_strict_lockdown',
      name: 'وضع الحماية الشاملة وقطع الاتصال',
      description: 'قطع الإنترنت بالكامل، حظر كافة المشتتات، وقفل ومنع تثبيت البرامج.',
      iconName: 'shield',
      colorHex: '0xFFEF4444',
      disableInternet: true,
      blockInstallations: true,
      enablePrivacyMode: true,
    ),
  ];

  Future<List<CustomSmartMode>> loadModes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) {
      await saveAll(_defaultPresets);
      return _defaultPresets;
    }
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => CustomSmartMode.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return _defaultPresets;
    }
  }

  Future<void> saveAll(List<CustomSmartMode> modes) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(modes.map((e) => e.toMap()).toList());
    await prefs.setString(_key, raw);
  }

  Future<void> saveMode(CustomSmartMode mode) async {
    final list = await loadModes();
    final index = list.indexWhere((m) => m.id == mode.id);
    if (index >= 0) {
      list[index] = mode;
    } else {
      list.add(mode);
    }
    await saveAll(list);
  }

  Future<void> deleteMode(String modeId) async {
    final list = await loadModes();
    list.removeWhere((m) => m.id == modeId);
    await saveAll(list);
  }

  Future<void> setActiveMode(String? modeId) async {
    final list = await loadModes();
    final updated = list.map((m) {
      if (m.id == modeId) {
        return m.copyWith(isActive: true, activatedAt: DateTime.now());
      }
      return m.copyWith(isActive: false, activatedAt: null);
    }).toList();
    await saveAll(updated);
  }

  Future<CustomSmartMode?> getActiveMode() async {
    final list = await loadModes();
    try {
      return list.firstWhere((m) => m.isActive);
    } catch (_) {
      return null;
    }
  }
}
