import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/command_type.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/action_tile.dart';
import '../widgets/app_snack.dart';
import '../widgets/confirm_dialog.dart';
import 'blocked_items_screen.dart';
import 'bluetooth_screen.dart';
import 'file_manager_screen.dart';
import 'install_requests_screen.dart';
import 'installed_apps_screen.dart';
import 'logs_screen.dart';
import 'open_apps_screen.dart';
import 'operation_messages_screen.dart';
import 'permission_requests_screen.dart';
import 'power_screen.dart';
import 'protection_screen.dart';
import 'screenshots_screen.dart';
import 'volume_screen.dart';
import 'wifi_screen.dart';

class DeviceDetailsScreen extends StatelessWidget {
  const DeviceDetailsScreen(
      {super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  Future<void> _requestScreenshot(BuildContext context) async {
    final confirmed = await confirmAction(
      context,
      title: 'طلب لقطة شاشة',
      message: 'هل تريد طلب لقطة شاشة حالية من ${device.name}؟',
    );
    if (!confirmed || !context.mounted) return;
    await context.read<DeviceRepository>().sendCommand(
          userId: userId,
          deviceId: device.id,
          type: CommandType.requestScreenshot,
        );
    if (context.mounted) showAppSnack(context, 'تم إرسال طلب لقطة الشاشة.');
  }

  Future<void> _sendSimpleCommand(
    BuildContext context,
    CommandType type,
    String doneMessage,
    String confirmMessage,
  ) async {
    final confirmed = await confirmAction(
      context,
      title: type.arabicTitle,
      message: confirmMessage,
    );
    if (!confirmed || !context.mounted) return;
    await context.read<DeviceRepository>().sendCommand(
          userId: userId,
          deviceId: device.id,
          type: type,
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
            icon: const Icon(Icons.send_outlined),
            label: const Text('إرسال'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (message == null || message.isEmpty || !context.mounted) return;
    await context.read<DeviceRepository>().sendCommand(
      userId: userId,
      deviceId: device.id,
      type: CommandType.showMessage,
      payload: {'message': message, 'title': 'KIOM'},
    );
    if (context.mounted) {
      showAppSnack(context, 'تم إرسال الرسالة للكمبيوتر.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      ActionTile(
        title: 'إظهار رمز الربط',
        subtitle: 'يفتح QR على الكمبيوتر للربط أو إعادة الربط',
        icon: Icons.qr_code_2_outlined,
        onTap: () => _sendSimpleCommand(
          context,
          CommandType.showPairingQr,
          'تم طلب إظهار رمز الربط على الكمبيوتر.',
          'هل تريد إرسال أمر إظهار رمز الربط إلى ${device.name}؟',
        ),
      ),
      ActionTile(
        title: 'أذونات الكمبيوتر',
        subtitle: 'يفتح شاشة الأذونات على الكمبيوتر للموافقة عليها',
        icon: Icons.admin_panel_settings_outlined,
        onTap: () => _sendSimpleCommand(
          context,
          CommandType.showPermissionCenter,
          'تم طلب فتح شاشة الأذونات على الكمبيوتر.',
          'هل تريد إرسال أمر فتح شاشة الأذونات إلى ${device.name}؟',
        ),
      ),
      ActionTile(
        title: 'إرسال رسالة',
        subtitle: 'يعرض تنبيه نصي على شاشة الكمبيوتر',
        icon: Icons.chat_bubble_outline,
        onTap: () => _sendMessageToComputer(context),
      ),
      ActionTile(
        title: 'رسائل العمليات',
        subtitle: 'نجاح وفشل الأوامر والردود القادمة من الكمبيوتر',
        icon: Icons.mark_chat_read_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  OperationMessagesScreen(userId: userId, device: device)),
        ),
      ),
      ActionTile(
        title: 'إدارة الملفات',
        subtitle: 'تصفح سطح المكتب والمسارات وتنفيذ فتح/نسخ/نقل/حذف',
        icon: Icons.folder_open_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  FileManagerScreen(userId: userId, device: device)),
        ),
      ),
      ActionTile(
        title: 'التطبيقات المفتوحة',
        subtitle: 'عرض وإغلاق التطبيقات الحالية',
        icon: Icons.apps_rounded,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => OpenAppsScreen(userId: userId, device: device)),
        ),
      ),
      ActionTile(
        title: 'التطبيقات والمواقع الممنوعة',
        subtitle: 'رفع المنع أو السماح المؤقت أو منع موقع جديد',
        icon: Icons.block_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  BlockedItemsScreen(userId: userId, device: device)),
        ),
      ),
      ActionTile(
        title: 'حماية المسارات',
        subtitle: 'إضافة قواعد حماية للملفات والمجلدات',
        icon: Icons.folder_copy_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ProtectionScreen(userId: userId, device: device)),
        ),
      ),
      ActionTile(
        title: 'طلبات الإذن',
        subtitle: 'فتح مسار أو تشغيل تطبيق محظور',
        icon: Icons.verified_user_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  PermissionRequestsScreen(userId: userId, device: device)),
        ),
      ),
      ActionTile(
        title: 'التطبيقات المثبتة',
        subtitle: 'عرض البرامج المثبتة وآخر تغييرات التثبيت',
        icon: Icons.inventory_2_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  InstalledAppsScreen(userId: userId, device: device)),
        ),
      ),
      ActionTile(
        title: 'منع التثبيت',
        subtitle: 'طلبات تثبيت البرامج الجديدة',
        icon: Icons.install_desktop_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  InstallRequestsScreen(userId: userId, device: device)),
        ),
      ),
      ActionTile(
        title: 'WiFi',
        subtitle: 'تشغيل أو إيقاف WiFi',
        icon: Icons.wifi,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => WifiScreen(userId: userId, device: device)),
        ),
      ),
      ActionTile(
        title: 'Bluetooth',
        subtitle: 'تشغيل أو إيقاف Bluetooth',
        icon: Icons.bluetooth,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => BluetoothScreen(userId: userId, device: device)),
        ),
      ),
      ActionTile(
        title: 'الصوت',
        subtitle: 'رفع وخفض وكتم وتحديد مستوى الصوت',
        icon: Icons.volume_up_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => VolumeScreen(userId: userId, device: device)),
        ),
      ),
      ActionTile(
        title: 'الطاقة',
        subtitle: 'إغلاق، إعادة تشغيل، قفل شاشة، تسجيل خروج',
        icon: Icons.power_settings_new,
        danger: true,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PowerScreen(userId: userId, device: device)),
        ),
      ),
      ActionTile(
        title: 'لقطات الشاشة',
        subtitle: 'طلب وعرض صورة الشاشة',
        icon: Icons.screenshot_monitor_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  ScreenshotsScreen(userId: userId, device: device)),
        ),
      ),
      ActionTile(
        title: 'السجلات',
        subtitle: 'طلب سجلات الجهاز حسب الفترة والنوع',
        icon: Icons.receipt_long_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => LogsScreen(userId: userId, device: device)),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(device.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const CircleAvatar(radius: 28, child: Icon(Icons.computer)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(device.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text('${device.os} • ${device.id}'),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'طلب لقطة شاشة',
                    onPressed: () => _requestScreenshot(context),
                    icon: const Icon(Icons.photo_camera_outlined),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...items,
        ],
      ),
    );
  }
}
