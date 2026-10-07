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
import 'file_manager_screen.dart';
import 'health_screen.dart';
import 'install_requests_screen.dart';
import 'installed_apps_screen.dart';
import 'logs_screen.dart';
import 'open_apps_screen.dart';
import 'modes_screen.dart';
import 'notifications_screen.dart';
import 'operation_messages_screen.dart';
import 'permission_requests_screen.dart';
import 'power_screen.dart';
import 'protection_screen.dart';
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

class _DeviceDetailsView extends StatelessWidget {
  const _DeviceDetailsView({
    required this.userId,
    required this.device,
  });

  final String userId;
  final PcDevice device;

  Future<void> _sendCommand(
    BuildContext context,
    CommandType type,
    String doneMessage, {
    Map<String, dynamic> payload = const {},
  }) async {
    await context.read<DeviceRepository>().sendCommand(
          userId: userId,
          deviceId: device.id,
          type: type,
          payload: payload,
        );
    if (context.mounted) showAppSnack(context, doneMessage);
  }

  Future<void> _checkConnection(BuildContext context) async {
    showAppSnack(context, 'جاري فحص الاتصال مع ${device.name}...');
    final repo = context.read<DeviceRepository>();
    try {
      final commandId = await repo.sendCommand(
        userId: userId,
        deviceId: device.id,
        type: CommandType.checkConnection,
      );
      final response = await repo.waitForCommandResponse(
        deviceId: device.id,
        commandId: commandId,
        timeout: const Duration(seconds: 8),
      );
      if (!context.mounted) return;
      if (response != null && response.success) {
        showAppSnack(context, 'الكمبيوتر متصل ويعمل بنجاح (Online).');
      } else {
        showAppSnack(context, 'تم إرسال الفحص، والكمبيوتر قيد الاستجابة.');
      }
    } catch (e) {
      if (context.mounted) showAppSnack(context, 'تعذر فحص الاتصال: $e', error: true);
    }
  }

  Future<void> _sendMessageToComputer(BuildContext context) async {
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('رسالة للكمبيوتر'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'اكتب الرسالة',
            hintText: 'سيتم عرضها فوراً على شاشة الكمبيوتر',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            icon: const Icon(Icons.send_rounded),
            label: const Text('إرسال'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (message == null || message.isEmpty || !context.mounted) return;
    await _sendCommand(
      context,
      CommandType.showMessage,
      'تم إرسال الرسالة للكمبيوتر مباشرة.',
      payload: {'message': message, 'title': 'KIOM Control'},
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final online = device.lastCheckResponse?.toLowerCase() == 'online' ||
        device.isRecentlyOnline;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(device.name),
        actions: [
          IconButton(
            tooltip: 'فحص الاتصال',
            onPressed: () => _checkConnection(context),
            icon: const Icon(Icons.bolt_rounded),
          ),
          IconButton(
            tooltip: 'إعداد Telegram',
            onPressed: () => _open(
              context,
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
            onPressed: () => _open(context, const SettingsScreen()),
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
            _DeviceHero(device: device, online: online),
            const SizedBox(height: 14),
            _DirectModeBanner(deviceName: device.name),
            const SizedBox(height: 14),
            _QuickActionsGrid(
              actions: [
                _QuickAction(
                  title: 'لقطة شاشة',
                  icon: Icons.screenshot_monitor_rounded,
                  color: cs.primary,
                  onTap: () => _sendCommand(
                    context,
                    CommandType.requestScreenshot,
                    'تم إرسال طلب لقطة الشاشة مباشرة.',
                  ),
                ),
                _QuickAction(
                  title: 'طوارئ ⚡',
                  icon: Icons.emergency_rounded,
                  color: cs.error,
                  onTap: () => _sendCommand(
                    context,
                    CommandType.emergencyMode,
                    'تم تفعيل وضع الطوارئ مباشرة.',
                  ),
                ),
                _QuickAction(
                  title: 'قفل الشاشة',
                  icon: Icons.lock_rounded,
                  color: const Color(0xFFE11D48),
                  onTap: () => _sendCommand(
                    context,
                    CommandType.lockScreen,
                    'تم إرسال أمر قفل الشاشة فوراً.',
                  ),
                ),
                _QuickAction(
                  title: 'تراجع ↩️',
                  icon: Icons.undo_rounded,
                  color: const Color(0xFF7C3AED),
                  onTap: () => _sendCommand(
                    context,
                    CommandType.undoLastCommand,
                    'تم إرسال طلب التراجع عن آخر أمر.',
                  ),
                ),
                _QuickAction(
                  title: 'صحة الجهاز',
                  icon: Icons.monitor_heart_rounded,
                  color: const Color(0xFF06B6D4),
                  onTap: () => _open(
                    context,
                    HealthScreen(userId: userId, device: device),
                  ),
                ),
                _QuickAction(
                  title: 'رسالة للشاشة',
                  icon: Icons.chat_bubble_rounded,
                  color: const Color(0xFF16A34A),
                  onTap: () => _sendMessageToComputer(context),
                ),
                _QuickAction(
                  title: 'الأوضاع الذكية',
                  icon: Icons.auto_awesome_rounded,
                  color: const Color(0xFFF59E0B),
                  onTap: () => _open(
                    context,
                    ModesScreen(userId: userId, device: device),
                  ),
                ),
                _QuickAction(
                  title: 'رمز الربط QR',
                  icon: Icons.qr_code_2_rounded,
                  color: cs.secondary,
                  onTap: () => _sendCommand(
                    context,
                    CommandType.showPairingQr,
                    'تم طلب إظهار رمز الربط على الكمبيوتر.',
                  ),
                ),
                _QuickAction(
                  title: 'الأذونات بالـ PC',
                  icon: Icons.admin_panel_settings_rounded,
                  color: cs.tertiary,
                  onTap: () => _sendCommand(
                    context,
                    CommandType.showPermissionCenter,
                    'تم طلب فتح شاشة الأذونات على الكمبيوتر.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SectionTitle(
              title: 'الاستخدام اليومي وإدارة الملفات',
              subtitle: 'أكثر الأدوات المطلوبة للوصول السريع إلى الكمبيوتر.',
            ),
            ActionTile(
              title: 'إدارة الملفات',
              subtitle: 'تصفح، فتح، نسخ، نقل، إخفاء أو حذف الملفات من الهاتف',
              icon: Icons.folder_open_rounded,
              onTap: () => _open(
                context,
                FileManagerScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'التطبيقات المفتوحة',
              subtitle: 'عرض وإغلاق البرامج والنوافذ الحالية بضغطة واحدة',
              icon: Icons.apps_rounded,
              onTap: () => _open(
                context,
                OpenAppsScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'التطبيقات والمواقع الممنوعة',
              subtitle: 'إدارة قوائم المنع والسماح المؤقت بدون تعقيد',
              icon: Icons.block_rounded,
              onTap: () => _open(
                context,
                BlockedItemsScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'حماية المسارات',
              subtitle: 'قواعد حماية للملفات والمجلدات الحساسة بكلمة مرور أو إذن',
              icon: Icons.folder_copy_rounded,
              onTap: () => _open(
                context,
                ProtectionScreen(userId: userId, device: device),
              ),
            ),
            const SizedBox(height: 20),
            _SectionTitle(
              title: 'الاتصال والشبكة والتحكم',
              subtitle: 'الشبكة، البلوتوث، الصوت، الطاقة والجدولة.',
            ),
            ActionTile(
              title: 'جدولة الأوامر',
              subtitle: 'نفّذ أوامر لاحقاً بتاريخ ووقت محددين تلقائياً',
              icon: Icons.event_available_rounded,
              onTap: () => _open(
                context,
                SchedulerScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'WiFi والإنترنت',
              subtitle: 'تشغيل/إيقاف WiFi أو تعطيل الإنترنت بالكامل',
              icon: Icons.wifi_rounded,
              onTap: () => _open(
                context,
                WifiScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'Bluetooth',
              subtitle: 'تشغيل/إيقاف البلوتوث وإرسال واستقبال الملفات',
              icon: Icons.bluetooth_rounded,
              onTap: () => _open(
                context,
                BluetoothScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'الصوت',
              subtitle: 'رفع، خفض، كتم أو تحديد نسبة الصوت الدقيقة',
              icon: Icons.volume_up_rounded,
              onTap: () => _open(
                context,
                VolumeScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'الطاقة والقفل',
              subtitle: 'إغلاق، إعادة تشغيل، قفل الشاشة، تسجيل الخروج أو القفل المؤقت',
              icon: Icons.power_settings_new_rounded,
              danger: true,
              onTap: () => _open(
                context,
                PowerScreen(userId: userId, device: device),
              ),
            ),
            const SizedBox(height: 20),
            _SectionTitle(
              title: 'المراقبة والأمان والتكامل',
              subtitle: 'ربط Telegram، السجلات، الإشعارات وطلبات التثبيت.',
            ),
            ActionTile(
              title: 'ربط Telegram',
              subtitle: device.isTelegramLinked
                  ? 'مربوط حالياً (${device.telegramChatId}) • اضغط لتعديل الإعدادات'
                  : 'افتح البوت واكتب Chat ID ليصل للكمبيوتر فوراً',
              icon: Icons.send_rounded,
              onTap: () => _open(
                context,
                TelegramSetupScreen(
                  userId: userId,
                  deviceId: device.id,
                  device: device,
                ),
              ),
            ),
            ActionTile(
              title: 'رسائل العمليات',
              subtitle: 'سجل نجاح وفشل الأوامر والردود القادمة من الكمبيوتر',
              icon: Icons.mark_chat_read_rounded,
              onTap: () => _open(
                context,
                OperationMessagesScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'مركز الإشعارات',
              subtitle: 'تنبيهات فورية داخل التطبيق للأوامر والأحداث المهمة',
              icon: Icons.notifications_active_rounded,
              onTap: () => _open(
                context,
                NotificationsScreen(device: device),
              ),
            ),
            ActionTile(
              title: 'السجلات الذكية',
              subtitle: 'ملخصات وتحليلات تلقائية للأحداث والأوامر والتطبيقات',
              icon: Icons.insights_rounded,
              onTap: () => _open(
                context,
                SmartInsightsScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'لقطات الشاشة',
              subtitle: 'طلب وعرض صور الشاشة المحفوظة من الكمبيوتر',
              icon: Icons.photo_library_rounded,
              onTap: () => _open(
                context,
                ScreenshotsScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'السجلات',
              subtitle: 'طلب السجلات حسب الفترة الزمنية ونوع الحدث',
              icon: Icons.receipt_long_rounded,
              onTap: () => _open(
                context,
                LogsScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'طلبات الإذن',
              subtitle: 'موافقات فتح المسارات أو قواعد الحماية المعلقة',
              icon: Icons.verified_user_rounded,
              onTap: () => _open(
                context,
                PermissionRequestsScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'منع التثبيت',
              subtitle: 'طلبات ومراقبة تثبيت البرامج الجديدة على الكمبيوتر',
              icon: Icons.install_desktop_rounded,
              onTap: () => _open(
                context,
                InstallRequestsScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'التطبيقات المثبتة',
              subtitle: 'عرض البرامج المثبتة على الكمبيوتر وتواريخ تثبيتها',
              icon: Icons.inventory_2_rounded,
              onTap: () => _open(
                context,
                InstalledAppsScreen(userId: userId, device: device),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
              if (device.isEmergency)
                const StatusChip(
                  label: 'طوارئ مفعّل',
                  icon: Icons.emergency_rounded,
                  color: Colors.white,
                ),
              if (device.isPrivacy)
                const StatusChip(
                  label: 'الخصوصية مفعّلة',
                  icon: Icons.visibility_off_rounded,
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

class _DirectModeBanner extends StatelessWidget {
  const _DirectModeBanner({required this.deviceName});

  final String deviceName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.secondary.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.secondary.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          Icon(Icons.touch_app_rounded, color: cs.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'وضع الضغط المباشر مفعّل: الأوامر تُرسل إلى $deviceName فوراً وبدون نافذة تأكيد.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({required this.actions});

  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.1,
      ),
      itemBuilder: (context, index) => actions[index],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).cardTheme.color ??
        Theme.of(context).colorScheme.surface;
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.w900),
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
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
