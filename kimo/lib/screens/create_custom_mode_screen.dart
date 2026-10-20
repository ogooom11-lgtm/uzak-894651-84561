import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/custom_smart_mode.dart';
import '../services/custom_modes_store.dart';
import '../widgets/app_snack.dart';

class CreateCustomModeScreen extends StatefulWidget {
  const CreateCustomModeScreen({
    super.key,
    this.initialMode,
  });

  final CustomSmartMode? initialMode;

  @override
  State<CreateCustomModeScreen> createState() => _CreateCustomModeScreenState();
}

class _CreateCustomModeScreenState extends State<CreateCustomModeScreen> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  final TextEditingController _appInputController = TextEditingController();
  final TextEditingController _siteInputController = TextEditingController();

  String _selectedIcon = 'shield';
  String _selectedColor = '0xFF3B82F6';

  // Audio Rules
  bool _capVolume = false;
  int _maxVolume = 50;
  bool _forceMute = false;
  bool _lockVolume = false;

  // App & Site Restrictions
  List<String> _blockedApps = [];
  bool _killBlockedApps = true;
  List<String> _blockedSites = [];

  // Network & Connections
  bool _disableInternet = false;
  bool _disableWifi = false;
  bool _disableBluetooth = false;

  // Security
  bool _blockInstallations = false;
  bool _enablePrivacyMode = false;

  // Duration
  int _durationMinutes = 0; // 0 = permanent

  final List<Map<String, dynamic>> _iconOptions = [
    {'name': 'shield', 'icon': Icons.shield_rounded, 'label': 'حماية'},
    {'name': 'school', 'icon': Icons.school_rounded, 'label': 'دراسة'},
    {'name': 'work', 'icon': Icons.work_rounded, 'label': 'عمل'},
    {'name': 'child_care', 'icon': Icons.child_care_rounded, 'label': 'أطفال'},
    {'name': 'games', 'icon': Icons.sports_esports_rounded, 'label': 'ألعاب'},
    {'name': 'volume_off', 'icon': Icons.volume_off_rounded, 'label': 'صامت'},
    {'name': 'bedtime', 'icon': Icons.bedtime_rounded, 'label': 'نوم'},
    {'name': 'lock', 'icon': Icons.lock_rounded, 'label': 'قفل'},
    {'name': 'bolt', 'icon': Icons.bolt_rounded, 'label': 'طوارئ'},
    {'name': 'auto_awesome', 'icon': Icons.auto_awesome_rounded, 'label': 'ذكي'},
  ];

  final List<Map<String, String>> _colorOptions = [
    {'hex': '0xFF3B82F6', 'name': 'أزرق'},
    {'hex': '0xFF10B981', 'name': 'أخضر'},
    {'hex': '0xFF8B5CF6', 'name': 'بنفسجي'},
    {'hex': '0xFFF59E0B', 'name': 'كهرماني'},
    {'hex': '0xFFEF4444', 'name': 'أحمر'},
    {'hex': '0xFF06B6D4', 'name': 'سماوي'},
    {'hex': '0xFFEC4899', 'name': 'وردي'},
    {'hex': '0xFF64748B', 'name': 'رمادي'},
  ];

  @override
  void initState() {
    super.initState();
    final mode = widget.initialMode;
    if (mode != null) {
      _nameController = TextEditingController(text: mode.name);
      _descController = TextEditingController(text: mode.description);
      _selectedIcon = mode.iconName;
      _selectedColor = mode.colorHex;
      _capVolume = mode.maxVolume < 100 || mode.lockVolume;
      _maxVolume = mode.maxVolume;
      _forceMute = mode.forceMute;
      _lockVolume = mode.lockVolume;
      _blockedApps = List.from(mode.blockedApps);
      _killBlockedApps = mode.killBlockedAppsOnActivate;
      _blockedSites = List.from(mode.blockedSites);
      _disableInternet = mode.disableInternet;
      _disableWifi = mode.disableWifi;
      _disableBluetooth = mode.disableBluetooth;
      _blockInstallations = mode.blockInstallations;
      _enablePrivacyMode = mode.enablePrivacyMode;
      _durationMinutes = mode.durationMinutes;
    } else {
      _nameController = TextEditingController();
      _descController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _appInputController.dispose();
    _siteInputController.dispose();
    super.dispose();
  }

  void _addBlockedApp(String app) {
    var clean = app.trim().toLowerCase();
    if (clean.isEmpty) return;
    if (!clean.endsWith('.exe') && !clean.contains('.')) clean = '$clean.exe';
    if (!_blockedApps.contains(clean)) {
      setState(() => _blockedApps.add(clean));
    }
    _appInputController.clear();
  }

  void _addBlockedSite(String site) {
    var clean = site.trim().toLowerCase().replaceAll('https://', '').replaceAll('http://', '').replaceAll('/', '');
    if (clean.isEmpty) return;
    if (!_blockedSites.contains(clean)) {
      setState(() => _blockedSites.add(clean));
    }
    _siteInputController.clear();
  }

  void _addSocialMediaPack() {
    final pack = ['youtube.com', 'tiktok.com', 'facebook.com', 'instagram.com', 'twitter.com', 'reddit.com', 'twitch.tv'];
    setState(() {
      for (final s in pack) {
        if (!_blockedSites.contains(s)) _blockedSites.add(s);
      }
    });
    showAppSnack(context, 'تمت إضافة باقة مواقع التواصل الاجتماعي.');
  }

  void _addGamingPack() {
    final sites = ['discord.com', 'twitch.tv', 'roblox.com', 'epicgames.com', 'steampowered.com'];
    final apps = ['discord.exe', 'steam.exe', 'epicgameslauncher.exe', 'epicgames.exe', 'robloxplayerbeta.exe'];
    setState(() {
      for (final s in sites) {
        if (!_blockedSites.contains(s)) _blockedSites.add(s);
      }
      for (final a in apps) {
        if (!_blockedApps.contains(a)) _blockedApps.add(a);
      }
    });
    showAppSnack(context, 'تمت إضافة باقة الألعاب وتطبيقات الدردشة.');
  }

  Future<void> _saveMode() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showAppSnack(context, 'يرجى كتابة اسم للوضع الذكي أولاً.', error: true);
      return;
    }

    final mode = CustomSmartMode(
      id: widget.initialMode?.id ?? const Uuid().v4(),
      name: name,
      description: _descController.text.trim(),
      iconName: _selectedIcon,
      colorHex: _selectedColor,
      maxVolume: _forceMute ? 0 : (_capVolume ? _maxVolume : 100),
      forceMute: _forceMute,
      lockVolume: _lockVolume || _capVolume,
      blockedApps: _blockedApps,
      killBlockedAppsOnActivate: _killBlockedApps,
      blockedSites: _blockedSites,
      disableInternet: _disableInternet,
      disableWifi: _disableWifi,
      disableBluetooth: _disableBluetooth,
      blockInstallations: _blockInstallations,
      enablePrivacyMode: _enablePrivacyMode,
      durationMinutes: _durationMinutes,
      createdAt: widget.initialMode?.createdAt ?? DateTime.now(),
    );

    await CustomModesStore.instance.saveMode(mode);
    if (mounted) {
      showAppSnack(context, 'تم حفظ الوضع الذكي "$name" بنجاح ✅');
      Navigator.pop(context, mode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colorVal = Color(int.parse(_selectedColor));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialMode == null ? 'إنشاء وضع ذكي مخصص' : 'تعديل الوضع الذكي'),
        actions: [
          TextButton.icon(
            onPressed: _saveMode,
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('حفظ الوضع', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // 1. Basic Info Card (Name, Desc, Icon, Color)
          _buildCard(
            title: '🏷️ معلومات وهوية الوضع',
            subtitle: 'اختر اسماً مميزاً وأيقونة ولوناً لتمييز الوضع في القائمة.',
            cs: cs,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم الوضع الذكي *',
                    hintText: 'مثال: وضع المذاكرة الصارمة أو وقت نوم الأطفال',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: 'وصف الوضع (اختياري)',
                    hintText: 'شرح مختصر لما يفعله هذا الوضع على الكمبيوتر...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                const Text('الأيقونة المعبرة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _iconOptions.map((opt) {
                      final isSelected = _selectedIcon == opt['name'];
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          avatar: Icon(opt['icon'] as IconData, size: 18),
                          label: Text(opt['label'] as String),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _selectedIcon = opt['name'] as String),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('اللون المميز:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _colorOptions.map((opt) {
                      final c = Color(int.parse(opt['hex']!));
                      final isSelected = _selectedColor == opt['hex'];
                      return GestureDetector(
                        onTap: () => setState(() => _selectedColor = opt['hex']!),
                        child: Container(
                          margin: const EdgeInsets.only(left: 10),
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: [
                              if (isSelected)
                                BoxShadow(
                                  color: c.withValues(alpha: 0.5),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                            ],
                          ),
                          child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2. Audio Control Rules
          _buildCard(
            title: '🔊 قواعد الصوت والمستوى',
            subtitle: 'التحكم التلقائي في مستوى صوت الكمبيوتر ومنع إزعاجه.',
            cs: cs,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('كتم صوت الكمبيوتر بالكامل (Force Mute)'),
                  subtitle: const Text('كتم تام لمكبرات الصوت فور تفعيل هذا الوضع'),
                  value: _forceMute,
                  onChanged: (val) => setState(() => _forceMute = val),
                ),
                if (!_forceMute) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('تحديد سقف أقصى للصوت (Max Volume Cap)'),
                    subtitle: Text('منع رفع الصوت فوق $_maxVolume% أثناء تفعيل الوضع'),
                    value: _capVolume,
                    onChanged: (val) => setState(() => _capVolume = val),
                  ),
                  if (_capVolume)
                    Slider(
                      value: _maxVolume.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '$_maxVolume%',
                      onChanged: (val) => setState(() => _maxVolume = val.round()),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('قفل وتثبيت الصوت (Lock Volume)'),
                    subtitle: const Text('إعادة ضبط الصوت تلقائياً إذا حاول أي شخص رفعه'),
                    value: _lockVolume,
                    onChanged: (val) => setState(() => _lockVolume = val),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 3. Application Blocking
          _buildCard(
            title: '🖥️ حظر التطبيقات والبرامج',
            subtitle: 'حدد البرامج التي ترغب بمنع فتحها وإغلاقها تلقائياً.',
            cs: cs,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _appInputController,
                        decoration: const InputDecoration(
                          hintText: 'اكتب اسم البرنامج (مثال: game.exe أو discord)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (val) => _addBlockedApp(val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _addBlockedApp(_appInputController.text),
                      child: const Text('إضافة +'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Quick suggested apps
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ActionChip(label: const Text('+ Discord'), onPressed: () => _addBlockedApp('discord.exe')),
                    ActionChip(label: const Text('+ Steam'), onPressed: () => _addBlockedApp('steam.exe')),
                    ActionChip(label: const Text('+ Telegram'), onPressed: () => _addBlockedApp('telegram.exe')),
                    ActionChip(label: const Text('+ Spotify'), onPressed: () => _addBlockedApp('spotify.exe')),
                    ActionChip(label: const Text('+ Chrome'), onPressed: () => _addBlockedApp('chrome.exe')),
                  ],
                ),
                if (_blockedApps.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('البرامج الممنوعة في هذا الوضع:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _blockedApps.map((app) {
                      return Chip(
                        avatar: const Icon(Icons.block_rounded, size: 16, color: Colors.red),
                        label: Text(app, style: const TextStyle(fontSize: 12)),
                        onDeleted: () => setState(() => _blockedApps.remove(app)),
                      );
                    }).toList(),
                  ),
                ],
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إغلاق البرامج الممنوعة المفتوحة فوراً'),
                  subtitle: const Text('إنهاء عمليات هذه البرامج مباشرة عند تفعيل الوضع'),
                  value: _killBlockedApps,
                  onChanged: (val) => setState(() => _killBlockedApps = val),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 4. Website Blocking
          _buildCard(
            title: '🌐 حظر المواقع والإنترنت',
            subtitle: 'حظر مواقع التواصل أو الألعاب مع توسيع التوابع تلقائياً.',
            cs: cs,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _siteInputController,
                        decoration: const InputDecoration(
                          hintText: 'اكتب النطاق (مثال: youtube.com أو tiktok.com)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (val) => _addBlockedSite(val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _addBlockedSite(_siteInputController.text),
                      child: const Text('حظر +'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Quick Bundles
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.people_alt_rounded, size: 14),
                      label: const Text('باقة التواصل الاجتماعي'),
                      onPressed: _addSocialMediaPack,
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.sports_esports_rounded, size: 14),
                      label: const Text('باقة الألعاب والدردشة'),
                      onPressed: _addGamingPack,
                    ),
                  ],
                ),
                if (_blockedSites.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('المواقع الممنوعة في هذا الوضع:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _blockedSites.map((site) {
                      return Chip(
                        avatar: const Icon(Icons.public_off_rounded, size: 16, color: Colors.orange),
                        label: Text(site, style: const TextStyle(fontSize: 12)),
                        onDeleted: () => setState(() => _blockedSites.remove(site)),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 5. Network & Connections
          _buildCard(
            title: '🔌 الشبكة والاتصالات',
            subtitle: 'خيارات قطع أو تعطيل المحولات والشبكات اللاسلكية.',
            cs: cs,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('قطع الإنترنت بالكامل (Disable Internet)'),
                  subtitle: const Text('تعطيل كرت الشبكة تماماً أثناء تفعيل الوضع'),
                  value: _disableInternet,
                  onChanged: (val) => setState(() => _disableInternet = val),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إيقاف الـ Wi-Fi (Disable Wi-Fi)'),
                  subtitle: const Text('إيقاف محول الواي فاي اللاسلكي'),
                  value: _disableWifi,
                  onChanged: (val) => setState(() => _disableWifi = val),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إيقاف البلوتوث (Disable Bluetooth)'),
                  subtitle: const Text('إيقاف محول البلوتوث لمنع تبادل الملفات'),
                  value: _disableBluetooth,
                  onChanged: (val) => setState(() => _disableBluetooth = val),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 6. Security & Productivity
          _buildCard(
            title: '🛡️ الأمان والإنتاجية',
            subtitle: 'منع التثبيت والخصوصية أثناء تفعيل الوضع.',
            cs: cs,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('منع تثبيت البرامج الجديدة (Block Installers)'),
                  subtitle: const Text('إغلاق وحظر أي ملف Setup أو Installer يحاول التشغيل'),
                  value: _blockInstallations,
                  onChanged: (val) => setState(() => _blockInstallations = val),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تفعيل وضع الخصوصية (Privacy Mode)'),
                  subtitle: const Text('إيقاف التقاط لقطات الشاشة أو تصفح الملفات مؤقتاً'),
                  value: _enablePrivacyMode,
                  onChanged: (val) => setState(() => _enablePrivacyMode = val),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 7. Duration / Timer
          _buildCard(
            title: '⏱️ مدة تفعيل الوضع (Timer)',
            subtitle: 'اختر ما إذا كان الوضع سيعمل لمهلة زمنية ثم يُلغى تلقائياً.',
            cs: cs,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('دائم حتى الإلغاء اليدوي'),
                      selected: _durationMinutes == 0,
                      onSelected: (_) => setState(() => _durationMinutes = 0),
                    ),
                    ChoiceChip(
                      label: const Text('⏳ 15 دقيقة'),
                      selected: _durationMinutes == 15,
                      onSelected: (_) => setState(() => _durationMinutes = 15),
                    ),
                    ChoiceChip(
                      label: const Text('⏳ 30 دقيقة'),
                      selected: _durationMinutes == 30,
                      onSelected: (_) => setState(() => _durationMinutes = 30),
                    ),
                    ChoiceChip(
                      label: const Text('⏳ ساعة واحدة'),
                      selected: _durationMinutes == 60,
                      onSelected: (_) => setState(() => _durationMinutes = 60),
                    ),
                    ChoiceChip(
                      label: const Text('⏳ ساعتان'),
                      selected: _durationMinutes == 120,
                      onSelected: (_) => setState(() => _durationMinutes = 120),
                    ),
                    ChoiceChip(
                      label: const Text('⏳ 4 ساعات'),
                      selected: _durationMinutes == 240,
                      onSelected: (_) => setState(() => _durationMinutes = 240),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: colorVal,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.save_rounded, size: 22),
            label: const Text('حفظ الوضع الذكي المخصص 💾', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: _saveMode,
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required String subtitle,
    required Widget child,
    required ColorScheme cs,
  }) {
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 3),
            Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
