import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_formatters.dart';
import '../core/command_type.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/action_tile.dart';
import '../widgets/app_snack.dart';
import '../widgets/status_chip.dart';
import 'blocked_items_screen.dart';
import 'bluetooth_screen.dart';
import 'clipboard_history_screen.dart';
import 'file_manager_screen.dart';
import 'health_screen.dart';
import 'install_requests_screen.dart';
import 'installed_apps_screen.dart';
import 'live_screen_screen.dart';
import 'logs_screen.dart';
import 'open_apps_screen.dart';
import 'modes_screen.dart';
import 'notifications_screen.dart';
import 'operation_messages_screen.dart';
import 'permission_requests_screen.dart';
import 'power_screen.dart';
import 'protection_screen.dart';
import 'remote_input_screen.dart';
import 'scheduler_screen.dart';
import 'screenshots_screen.dart';
import 'settings_screen.dart';
import 'smart_insights_screen.dart';
import 'telegram_setup_screen.dart';
import 'volume_screen.dart';
import 'wifi_screen.dart';

class DeviceDetailsScreen extends StatelessWidget {
  const DeviceDetailsScreen({
    super.key,
    required this.userId,
    required this.device,
  });

  final String userId;
  final PcDevice device;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DeviceRepository>();
    return StreamBuilder<List<PcDevice>>(
      stream: repo.watchDevices(userId),
      initialData: [device],
      builder: (context, snapshot) {
        final devices = snapshot.data ?? [device];
        final currentDevice = devices.firstWhere(
          (d) => d.id == device.id,
          orElse: () => device,
        );
        return _DeviceDetailsView(
          userId: userId,
          device: currentDevice,
        );
      },
    );
  }
}

class _DeviceDetailsView extends StatefulWidget {
  const _DeviceDetailsView({
    required this.userId,
    required this.device,
  });

  final String userId;
  final PcDevice device;

  @override
  State<_DeviceDetailsView> createState() => _DeviceDetailsViewState();
}

class _DeviceDetailsViewState extends State<_DeviceDetailsView> {
  String _selectedCategory = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, String>> _categories = [
    {'id': 'all', 'label': '🌟 الكل', 'desc': 'كافة أدوات التحكم والمراقبة'},
    {'id': 'controls', 'label': '⚡ التحكم والماوس', 'desc': 'لوحة اللمس، الصوت، الطاقة والشاشة'},
    {'id': 'security', 'label': '🛡️ الأمان والأوضاع', 'desc': 'الأوضاع الذكية، الحظر وقفل المسارات'},
    {'id': 'files', 'label': '📁 الملفات والبرامج', 'desc': 'الملفات، البرامج المفتوحة والحافظة'},
    {'id': 'network', 'label': '📶 الشبكة والاتصال', 'desc': 'الواي فاي، البلوتوث وتيليجرام'},
    {'id': 'logs', 'label': '📈 السجلات والتحليلات', 'desc': 'الأنشطة، التحليلات والإشعارات'},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _sendCommand(
    CommandType type,
    String doneMessage, {
    Map<String, dynamic> payload = const {},
  }) async {
    await context.read<DeviceRepository>().sendCommand(
          userId: widget.userId,
          deviceId: widget.device.id,
          type: type,
          payload: payload,
        );
    if (mounted) showAppSnack(context, doneMessage);
  }

  Future<void> _checkConnection() async {
    showAppSnack(context, 'جاري فحص الاتصال مع ${widget.device.name}...');
    final repo = context.read<DeviceRepository>();
    try {
      final commandId = await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.checkConnection,
      );
      final response = await repo.waitForCommandResponse(
        deviceId: widget.device.id,
        commandId: commandId,
        timeout: const Duration(seconds: 8),
      );
      if (!mounted) return;
      if (response != null && response.success) {
        showAppSnack(context, 'الكمبيوتر متصل ويعمل بنجاح (Online).');
      } else {
        showAppSnack(context, 'تم إرسال الفحص، والكمبيوتر قيد الاستجابة.');
      }
    } catch (e) {
      if (mounted) showAppSnack(context, 'تعذر فحص الاتصال: $e', error: true);
    }
  }

  Future<void> _sendMessageToComputer() async {
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('رسالة منبثقة لشاشة الكمبيوتر'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'نص الرسالة',
            hintText: 'اكتب التنبيه أو الرسالة التي ستظهر للمستخدم...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            icon: const Icon(Icons.send_rounded),
            label: const Text('إظهار على الشاشة'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (message == null || message.isEmpty || !mounted) return;
    await _sendCommand(
      CommandType.windowsToast,
      'تم إرسال الرسالة إلى شاشة الكمبيوتر.',
      payload: {'title': 'تنبيه من تطبيق التحكم', 'message': message},
    );
  }

  Future<void> _speakTextOnComputer() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('نطق صوتي على سماعات الكمبيوتر'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'اكتب العبارة للنطق',
            hintText: 'مثال: يرجى حفظ الملفات أو انتهت مهلة الاستخدام',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            icon: const Icon(Icons.record_voice_over_rounded),
            label: const Text('نطق الآن'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty || !mounted) return;
    await _sendCommand(
      CommandType.textToSpeech,
      'تم إرسال أمر النطق الصوتي للكمبيوتر.',
      payload: {'text': text},
    );
  }

  Future<void> _stopAgentOnComputer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إيقاف تطبيق الكمبيوتر عن بُعد'),
        content: const Text(
          'هل أنت متأكد من رغبتك في إغلاق تطبيق عميل التحكم على الكمبيوتر؟\n\n'
          '⚠️ سيتوقف العميل عن استقبال الأوامر حتى يتم إعادة تشغيل الكمبيوتر أو فتح التطبيق يدوياً.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إيقاف وإغلاق الآن'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _sendCommand(
      CommandType.checkConnection,
      'تم إرسال أمر إيقاف وإغلاق تطبيق الكمبيوتر بنجاح.',
      payload: {'action': 'exit_agent'},
    );
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final device = widget.device;
    final userId = widget.userId;
    final online = device.lastCheckResponse?.toLowerCase() == 'online' || device.isRecentlyOnline;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(device.name),
        actions: [
          IconButton(
            tooltip: 'فحص الاتصال',
            onPressed: _checkConnection,
            icon: const Icon(Icons.bolt_rounded),
          ),
          IconButton(
            tooltip: 'إعداد Telegram',
            onPressed: () => _open(
              TelegramSetupScreen(
                userId: userId,
                deviceId: device.id,
                device: device,
              ),
            ),
            icon: Icon(
              Icons.send_rounded,
              color: device.isTelegramLinked ? const Color(0xFF38BDF8) : null,
            ),
          ),
          IconButton(
            tooltip: 'الإعدادات العامة',
            onPressed: () => _open(const SettingsScreen()),
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              cs.primary.withValues(alpha: .14),
              cs.tertiary.withValues(alpha: .08),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 100, 16, 32),
          children: [
            // 1. Device Hero Card
            _DeviceHero(device: device, online: online),

            const SizedBox(height: 14),

            // 2. Trackpad & Mouse Hero Banner
            _TrackpadHeroCard(
              device: device,
              onTap: () => _open(RemoteInputScreen(device: device)),
            ),

            const SizedBox(height: 14),

            // 3. Live Screen Mirror Hero Banner
            _LiveScreenHeroCard(
              device: device,
              onTap: () => _open(LiveScreenScreen(device: device)),
            ),

            const SizedBox(height: 14),

            // 4. Custom Smart Modes Hero Banner
            _CustomModesHeroCard(
              device: device,
              onTap: () => _open(ModesScreen(userId: userId, device: device)),
            ),

            const SizedBox(height: 16),

            // 4. Smart Search Bar with Clear Button
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '🔍 ابحث عن أي أداة أو أمر أو إعداد...',
                isDense: true,
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
            ),

            const SizedBox(height: 14),

            // 5. Category Selector Tabs
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.map((cat) {
                  final isSelected = _selectedCategory == cat['id'] && _searchQuery.isEmpty;
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(cat['label']!),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() {
                          _selectedCategory = cat['id']!;
                          _searchQuery = '';
                          _searchController.clear();
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 16),

            // 6. Categorized Action Lists
            ..._buildCategorizedSections(cs),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCategorizedSections(ColorScheme cs) {
    final list = <Widget>[];

    // Helper method to check if an item matches search query or category
    bool shouldShow(String category, String title, String subtitle) {
      if (_searchQuery.isNotEmpty) {
        return title.toLowerCase().contains(_searchQuery) || subtitle.toLowerCase().contains(_searchQuery);
      }
      return _selectedCategory == 'all' || _selectedCategory == category;
    }

    // SECTION 1: Controls & Input
    final controlsItems = [
      _ActionData(
        title: 'بث وعرض شاشة الكمبيوتر مباشرة (Live Screen)',
        subtitle: 'مشاهدة شاشة الكمبيوتر في الوقت الفعلي مع النقر والتفاعل باللمس عبر Wi-Fi',
        icon: Icons.tv_rounded,
        onTap: () => _open(LiveScreenScreen(device: widget.device)),
      ),
      _ActionData(
        title: 'لوحة اللمس ولوحة المفاتيح (Trackpad)',
        subtitle: 'تحكم فوري بالماوس، لوحة اللمس، الأزرار والكتابة بدون إنترنت عبر Wi-Fi',
        icon: Icons.mouse_rounded,
        onTap: () => _open(RemoteInputScreen(device: widget.device)),
      ),
      _ActionData(
        title: 'التقاط صورة الشاشة (Screenshot)',
        subtitle: 'تصوير شاشة الكمبيوتر فورياً وتحديث المعاينة في التطبيق',
        icon: Icons.screenshot_monitor_rounded,
        onTap: () => _sendCommand(CommandType.requestScreenshot, 'تم إرسال طلب لقطة الشاشة مباشرة.'),
      ),
      _ActionData(
        title: 'فحص صحة ومواصفات الجهاز',
        subtitle: 'عرض استهلاك المعالج، الذاكرة، الأقراص، والعتاد الفعلي',
        icon: Icons.monitor_heart_rounded,
        onTap: () => _open(HealthScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'إرسال رسالة منبثقة للشاشة',
        subtitle: 'عرض تنبيه أو إشعار Toast مباشرة على سطح مكتب الكمبيوتر',
        icon: Icons.chat_bubble_rounded,
        onTap: _sendMessageToComputer,
      ),
      _ActionData(
        title: 'نطق صوتي عبر مكبرات الصوت',
        subtitle: 'قراءة ونطق أي عبارة بالصوت عبر سماعات الكمبيوتر بوضوح',
        icon: Icons.record_voice_over_rounded,
        onTap: _speakTextOnComputer,
      ),
      _ActionData(
        title: 'التحكم بمستوى الصوت',
        subtitle: 'رفع، خفض، كتم، أو تحديد نسبة الصوت الدقيقة للكمبيوتر',
        icon: Icons.volume_up_rounded,
        onTap: () => _open(VolumeScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'خيارات الطاقة والقفل',
        subtitle: 'إغلاق، إعادة تشغيل، قفل الشاشة، أو وضع السكون المؤقت',
        icon: Icons.power_settings_new_rounded,
        danger: true,
        onTap: () => _open(PowerScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'إيقاف تطبيق الكمبيوتر عن بُعد',
        subtitle: 'إغلاق وإنهاء عملية تطبيق العميل الشغال على الكمبيوتر فوراً',
        icon: Icons.stop_circle_rounded,
        danger: true,
        onTap: _stopAgentOnComputer,
      ),
    ].where((e) => shouldShow('controls', e.title, e.subtitle)).toList();

    if (controlsItems.isNotEmpty) {
      list.add(const _SectionTitle(
        title: '⚡ التحكم المباشر، الماوس والطاقة',
        subtitle: 'أدوات الاستجابة الفورية، تحريك الماوس، الشاشة ومستوى الصوت.',
      ));
      for (final item in controlsItems) {
        list.add(ActionTile(
          title: item.title,
          subtitle: item.subtitle,
          icon: item.icon,
          danger: item.danger,
          onTap: item.onTap,
        ));
      }
      list.add(const SizedBox(height: 16));
    }

    // SECTION 2: Security & Modes
    final securityItems = [
      _ActionData(
        title: 'الأوضاع الذكية والمخصصة',
        subtitle: 'إنشاء وتخصيص أوضاع ذكية (حظر ألعاب، تقييد صوت، دراسة، أطفال)',
        icon: Icons.auto_awesome_rounded,
        onTap: () => _open(ModesScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'وضع الطوارئ الشامل ⚡',
        subtitle: 'قفل الشاشة فوراً + لقطة شاشة + تنبيه عاجل مع قطع الاتصال',
        icon: Icons.emergency_rounded,
        danger: true,
        onTap: () => _sendCommand(CommandType.emergencyMode, 'تم تفعيل وضع الطوارئ مباشرة.'),
      ),
      _ActionData(
        title: 'التطبيقات والمواقع الممنوعة',
        subtitle: 'إدارة قوائم حظر البرامج والمواقع ومنع الوصول بدون إذن',
        icon: Icons.block_rounded,
        onTap: () => _open(BlockedItemsScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'حماية وقفل المسارات والملفات',
        subtitle: 'قفل مجلدات وملفات حساسة بكلمة مرور أو باشتراط إذن الهاتف',
        icon: Icons.folder_copy_rounded,
        onTap: () => _open(ProtectionScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'مراقبة ومنع تثبيت البرامج',
        subtitle: 'مراقبة تثبيت البرامج الجديدة والموافقة عليها أو منعها',
        icon: Icons.install_desktop_rounded,
        onTap: () => _open(InstallRequestsScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'طلبات الإذن والموافقات',
        subtitle: 'موافقات فتح المسارات أو قواعد الحماية المعلقة من الكمبيوتر',
        icon: Icons.verified_user_rounded,
        onTap: () => _open(PermissionRequestsScreen(userId: widget.userId, device: widget.device)),
      ),
    ].where((e) => shouldShow('security', e.title, e.subtitle)).toList();

    if (securityItems.isNotEmpty) {
      list.add(const _SectionTitle(
        title: '🛡️ الأمان، الأوضاع والحماية الذكية',
        subtitle: 'إنشاء الأوضاع الذكية، حظر البرامج والمواقع وقفل الملفات الحساسة.',
      ));
      for (final item in securityItems) {
        list.add(ActionTile(
          title: item.title,
          subtitle: item.subtitle,
          icon: item.icon,
          danger: item.danger,
          onTap: item.onTap,
        ));
      }
      list.add(const SizedBox(height: 16));
    }

    // SECTION 3: Files & Apps
    final filesItems = [
      _ActionData(
        title: 'مدير الملفات الشامل',
        subtitle: 'تصفح، فتح، تحميل، سحب أو حذف الملفات والمستندات من الهاتف',
        icon: Icons.folder_open_rounded,
        onTap: () => _open(FileManagerScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'التطبيقات والنوافذ المفتوحة',
        subtitle: 'عرض وإغلاق البرامج والنوافذ والتبويبات النشطة بضغطة واحدة',
        icon: Icons.apps_rounded,
        onTap: () => _open(OpenAppsScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'البرامج المثبتة على الكمبيوتر',
        subtitle: 'عرض كافة البرامج المثبتة وإصداراتها ومصادرها',
        icon: Icons.inventory_2_rounded,
        onTap: () => _open(InstalledAppsScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'سجل الحافظة الذكي (Clipboard)',
        subtitle: 'سجل كامل لعمليات النسخ (Ctrl+C) مع المسار والتطبيق المصدر',
        icon: Icons.history_edu_rounded,
        onTap: () => _open(ClipboardHistoryScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'معرض لقطات الشاشة',
        subtitle: 'استعراض وتحميل صور الشاشة الملتقطة سابقاً من الكمبيوتر',
        icon: Icons.photo_library_rounded,
        onTap: () => _open(ScreenshotsScreen(userId: widget.userId, device: widget.device)),
      ),
    ].where((e) => shouldShow('files', e.title, e.subtitle)).toList();

    if (filesItems.isNotEmpty) {
      list.add(const _SectionTitle(
        title: '📁 إدارة الملفات، البرامج والحافظة',
        subtitle: 'تصفح الملفات، مراقبة البرامج النشطة، وسجل الحافظة الذكي.',
      ));
      for (final item in filesItems) {
        list.add(ActionTile(
          title: item.title,
          subtitle: item.subtitle,
          icon: item.icon,
          danger: item.danger,
          onTap: item.onTap,
        ));
      }
      list.add(const SizedBox(height: 16));
    }

    // SECTION 4: Network & Peripherals
    final networkItems = [
      _ActionData(
        title: 'شبكة WiFi والإنترنت',
        subtitle: 'تشغيل/إيقاف الواي فاي أو تعطيل الإنترنت ومحولات الشبكة',
        icon: Icons.wifi_rounded,
        onTap: () => _open(WifiScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'البلوتوث (Bluetooth)',
        subtitle: 'تشغيل/إيقاف البلوتوث وإرسال واستقبال الملفات اللاسلكية',
        icon: Icons.bluetooth_rounded,
        onTap: () => _open(BluetoothScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'جدولة الأوامر والمهام',
        subtitle: 'جدولة تنفيذ أوامر لاحقاً بتاريخ ووقت محددين بدقة',
        icon: Icons.event_available_rounded,
        onTap: () => _open(SchedulerScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'إعدادات ربط Telegram',
        subtitle: widget.device.isTelegramLinked
            ? 'مربوط حالياً (${widget.device.telegramChatId}) • اضغط لتعديل الإعدادات'
            : 'ربط البوت والمجموعة للتحكم عن بُعد بدون إنترنت محلي',
        icon: Icons.send_rounded,
        onTap: () => _open(TelegramSetupScreen(
          userId: widget.userId,
          deviceId: widget.device.id,
          device: widget.device,
        )),
      ),
    ].where((e) => shouldShow('network', e.title, e.subtitle)).toList();

    if (networkItems.isNotEmpty) {
      list.add(const _SectionTitle(
        title: '📶 الشبكة، الاتصال والجدولة',
        subtitle: 'الواي فاي، البلوتوث، جدولة الأوامر وتكامل تيليجرام.',
      ));
      for (final item in networkItems) {
        list.add(ActionTile(
          title: item.title,
          subtitle: item.subtitle,
          icon: item.icon,
          danger: item.danger,
          onTap: item.onTap,
        ));
      }
      list.add(const SizedBox(height: 16));
    }

    // SECTION 5: Logs & Insights
    final logsItems = [
      _ActionData(
        title: 'سجل الأنشطة والعمليات (Logs)',
        subtitle: 'استعراض السجلات بحسب نوع الحدث أو الفترة الزمنية',
        icon: Icons.receipt_long_rounded,
        onTap: () => _open(LogsScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'التحليلات الذكية والملخص',
        subtitle: 'ملخصات وتحليلات ذكية لاستخدام الجهاز والبرامج والأمان',
        icon: Icons.insights_rounded,
        onTap: () => _open(SmartInsightsScreen(userId: widget.userId, device: widget.device)),
      ),
      _ActionData(
        title: 'مركز الإشعارات والتنبيهات',
        subtitle: 'تنبيهات فورية داخل التطبيق للأحداث والأوامر المنجزة',
        icon: Icons.notifications_active_rounded,
        onTap: () => _open(NotificationsScreen(device: widget.device)),
      ),
      _ActionData(
        title: 'رسائل وردود العمليات',
        subtitle: 'سجل نجاح وفشل الأوامر والردود المنفذة على الكمبيوتر',
        icon: Icons.mark_chat_read_rounded,
        onTap: () => _open(OperationMessagesScreen(userId: widget.userId, device: widget.device)),
      ),
    ].where((e) => shouldShow('logs', e.title, e.subtitle)).toList();

    if (logsItems.isNotEmpty) {
      list.add(const _SectionTitle(
        title: '📈 السجلات، التحليلات والمراقبة',
        subtitle: 'سجلات العمليات، التحليلات الذكية والتنبيهات الفورية.',
      ));
      for (final item in logsItems) {
        list.add(ActionTile(
          title: item.title,
          subtitle: item.subtitle,
          icon: item.icon,
          danger: item.danger,
          onTap: item.onTap,
        ));
      }
      list.add(const SizedBox(height: 16));
    }

    if (list.isEmpty && _searchQuery.isNotEmpty) {
      list.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 10),
            Text('لا توجد أدوات مطابقة لـ "$_searchQuery"', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('جرب البحث بكلمة أخرى مثل: صوت، ماوس، حظر، ملف، قفل', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ));
    }

    return list;
  }
}

class _ActionData {
  _ActionData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
}

class _DeviceHero extends StatelessWidget {
  const _DeviceHero({required this.device, required this.online});

  final PcDevice device;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [cs.primary, cs.tertiary],
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: .22),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: .20)),
                ),
                child: const Icon(Icons.computer_rounded, color: Colors.white, size: 38),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${device.os} • ${device.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusChip(
                label: online ? 'متصل الآن' : 'غير متصل',
                icon: online ? Icons.bolt_rounded : Icons.wifi_off_rounded,
                color: Colors.white,
              ),
              if (device.isLanOnline)
                StatusChip(
                  label: 'Wi-Fi مباشر (${device.lanPingMs ?? 2}ms)',
                  icon: Icons.network_check_rounded,
                  color: const Color(0xFF6EE7B7),
                ),
              StatusChip(
                label: device.isMuted ? 'مكتوم' : 'الصوت ${device.volume}%',
                icon: device.isMuted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                color: Colors.white,
              ),
              StatusChip(
                label: device.wifiStatus ?? 'WiFi مجهول',
                icon: Icons.wifi_rounded,
                color: Colors.white,
              ),
              StatusChip(
                label: device.isTelegramLinked ? 'Telegram مربوط' : 'Telegram غير مربوط',
                icon: Icons.send_rounded,
                color: Colors.white,
              ),
              if (device.activeMode != null && device.activeMode!.isNotEmpty)
                StatusChip(
                  label: 'وضع: ${device.activeMode}',
                  icon: Icons.auto_awesome_rounded,
                  color: Colors.white,
                ),
            ],
          ),
          if (device.lastSeenAt != null) ...[
            const SizedBox(height: 12),
            Text(
              'آخر ظهور: ${AppFormatters.dateTime(device.lastSeenAt!)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrackpadHeroCard extends StatelessWidget {
  const _TrackpadHeroCard({required this.device, required this.onTap});

  final PcDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLan = device.isLanOnline;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF065F46),
                Color(0xFF047857),
              ],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40059669),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.mouse_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'لوحة اللمس والكيبورد (Trackpad)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isLan ? const Color(0xFF10B981) : Colors.white24,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isLan ? 'Wi-Fi ⚡' : 'محلي',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'تحكم فوري بالماوس، لوحة اللمس، الأزرار، والكتابة بدون إنترنت',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white70,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveScreenHeroCard extends StatelessWidget {
  const _LiveScreenHeroCard({required this.device, required this.onTap});

  final PcDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLan = device.isLanOnline;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0284C7),
                Color(0xFF0369A1),
              ],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x400284C7),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.tv_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'بث شاشة الكمبيوتر (Live Mirror)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isLan ? const Color(0xFF10B981) : Colors.white24,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isLan ? 'مباشر ⚡' : 'محلي',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'مشاهدة شاشة الكمبيوتر بالوقت الفعلي مع إمكانية النقر والتحكم باللمس',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white70,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomModesHeroCard extends StatelessWidget {
  const _CustomModesHeroCard({required this.device, required this.onTap});

  final PcDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF4C1D95),
                Color(0xFF6D28D9),
              ],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x407C3AED),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الأوضاع الذكية والمخصصة',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'إنشاء وتطبيق أوضاع مخصصة لحظر البرامج والمواقع وقفل الصوت بضغطة واحدة',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white70,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
