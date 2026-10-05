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
import 'smart_insights_screen.dart';
import 'volume_screen.dart';
import 'wifi_screen.dart';

class DeviceDetailsScreen extends StatelessWidget {
  const DeviceDetailsScreen(
      {super.key, required this.userId, required this.device});

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
      payload: {'message': message, 'title': 'KIOM'},
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
      appBar: AppBar(title: Text(device.name)),
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
          padding: const EdgeInsets.fromLTRB(16, 100, 16, 28),
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
                  title: 'رمز الربط',
                  icon: Icons.qr_code_2_rounded,
                  color: cs.secondary,
                  onTap: () => _sendCommand(
                    context,
                    CommandType.showPairingQr,
                    'تم طلب إظهار رمز الربط على الكمبيوتر.',
                  ),
                ),
                _QuickAction(
                  title: 'الأذونات',
                  icon: Icons.admin_panel_settings_rounded,
                  color: cs.tertiary,
                  onTap: () => _sendCommand(
                    context,
                    CommandType.showPermissionCenter,
                    'تم طلب فتح شاشة الأذونات على الكمبيوتر.',
                  ),
                ),
                _QuickAction(
                  title: 'رسالة',
                  icon: Icons.chat_bubble_rounded,
                  color: const Color(0xFF16A34A),
                  onTap: () => _sendMessageToComputer(context),
                ),
                _QuickAction(
                  title: 'الأوضاع',
                  icon: Icons.auto_awesome_rounded,
                  color: const Color(0xFFF59E0B),
                  onTap: () => _open(
                    context,
                    ModesScreen(userId: userId, device: device),
                  ),
                ),
                _QuickAction(
                  title: 'الصحة',
                  icon: Icons.monitor_heart_rounded,
                  color: const Color(0xFF06B6D4),
                  onTap: () => _open(
                    context,
                    HealthScreen(userId: userId, device: device),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SectionTitle(
              title: 'الاستخدام اليومي',
              subtitle: 'أكثر الأدوات المطلوبة للوصول السريع.',
            ),
            ActionTile(
              title: 'إدارة الملفات',
              subtitle: 'تصفح، فتح، نسخ، نقل، إخفاء أو حذف من الهاتف',
              icon: Icons.folder_open_rounded,
              onTap: () => _open(
                context,
                FileManagerScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'التطبيقات المفتوحة',
              subtitle: 'عرض وإغلاق التطبيقات الحالية بضغطة واحدة',
              icon: Icons.apps_rounded,
              onTap: () => _open(
                context,
                OpenAppsScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'التطبيقات والمواقع الممنوعة',
              subtitle: 'إدارة المنع والسماح المؤقت بدون قوائم معقدة',
              icon: Icons.block_rounded,
              onTap: () => _open(
                context,
                BlockedItemsScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'حماية المسارات',
              subtitle: 'قواعد حماية للملفات والمجلدات الحساسة',
              icon: Icons.folder_copy_rounded,
              onTap: () => _open(
                context,
                ProtectionScreen(userId: userId, device: device),
              ),
            ),
            const SizedBox(height: 18),
            _SectionTitle(
              title: 'الاتصال والتحكم',
              subtitle: 'الشبكة، البلوتوث، الصوت والطاقة.',
            ),
            ActionTile(
              title: 'جدولة الأوامر',
              subtitle: 'نفّذ أوامر لاحقاً بتاريخ ووقت تختاره',
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
              subtitle: 'تشغيل/إيقاف البلوتوث وإرسال/استقبال الملفات',
              icon: Icons.bluetooth_rounded,
              onTap: () => _open(
                context,
                BluetoothScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'الصوت',
              subtitle: 'رفع، خفض، كتم أو تحديد نسبة الصوت',
              icon: Icons.volume_up_rounded,
              onTap: () => _open(
                context,
                VolumeScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'الطاقة والقفل',
              subtitle: 'إغلاق، إعادة تشغيل، قفل الشاشة أو جدولة الأوامر',
              icon: Icons.power_settings_new_rounded,
              danger: true,
              onTap: () => _open(
                context,
                PowerScreen(userId: userId, device: device),
              ),
            ),
            const SizedBox(height: 18),
            _SectionTitle(
              title: 'المراقبة والطلبات',
              subtitle: 'ردود الأوامر والسجلات والطلبات الواردة.',
            ),
            ActionTile(
              title: 'رسائل العمليات',
              subtitle: 'نجاح وفشل الأوامر والردود القادمة من الكمبيوتر',
              icon: Icons.mark_chat_read_rounded,
              onTap: () => _open(
                context,
                OperationMessagesScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'الإشعارات',
              subtitle: 'تنبيهات فورية داخل التطبيق للأوامر والأحداث المهمة',
              icon: Icons.notifications_active_rounded,
              onTap: () => _open(
                context,
                NotificationsScreen(device: device),
              ),
            ),
            ActionTile(
              title: 'السجلات الذكية',
              subtitle: 'ملخصات تلقائية للأحداث والأوامر والتطبيقات والمواقع',
              icon: Icons.insights_rounded,
              onTap: () => _open(
                context,
                SmartInsightsScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'لقطات الشاشة',
              subtitle: 'طلب وعرض صور الشاشة المحفوظة',
              icon: Icons.photo_library_rounded,
              onTap: () => _open(
                context,
                ScreenshotsScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'السجلات',
              subtitle: 'طلب السجلات حسب الفترة والنوع',
              icon: Icons.receipt_long_rounded,
              onTap: () => _open(
                context,
                LogsScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'طلبات الإذن',
              subtitle: 'موافقات فتح المسارات أو قواعد الحماية',
              icon: Icons.verified_user_rounded,
              onTap: () => _open(
                context,
                PermissionRequestsScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'منع التثبيت',
              subtitle: 'طلبات تثبيت البرامج الجديدة',
              icon: Icons.install_desktop_rounded,
              onTap: () => _open(
                context,
                InstallRequestsScreen(userId: userId, device: device),
              ),
            ),
            ActionTile(
              title: 'التطبيقات المثبتة',
              subtitle: 'عرض البرامج المثبتة وآخر تغييرات التثبيت',
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
                  color: Colors.white.withValues(alpha: .17),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: .16)),
                ),
                child: const Icon(Icons.computer_rounded,
                    color: Colors.white, size: 38),
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
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      device.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
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
                label: online ? 'متصل' : 'غير متصل',
                icon: online ? Icons.bolt_rounded : Icons.wifi_off_rounded,
                color: Colors.white,
              ),
              StatusChip(
                label: 'الصوت ${device.volume}%',
                icon: device.isMuted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                color: Colors.white,
              ),
              StatusChip(
                label: device.wifiStatus ?? 'WiFi غير معروف',
                icon: Icons.wifi_rounded,
                color: Colors.white,
              ),
            ],
          ),
          if (device.lastSeenAt != null) ...[
            const SizedBox(height: 12),
            Text(
              'آخر ظهور: ${AppFormatters.dateTime(device.lastSeenAt!)}',
              style: const TextStyle(color: Colors.white70),
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
              'وضع الضغط المباشر مفعّل: الأوامر تُرسل إلى $deviceName بدون نافذة تأكيد.',
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
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.65,
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
    final surface = Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface;
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
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
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
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
