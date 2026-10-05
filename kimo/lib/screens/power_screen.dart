import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/command_type.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/action_tile.dart';
import '../widgets/app_snack.dart';
import '../widgets/confirm_dialog.dart';

class PowerScreen extends StatelessWidget {
  const PowerScreen({super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  Future<void> _send(
    BuildContext context,
    CommandType type, {
    Map<String, dynamic> payload = const {},
    DateTime? executeAt,
    bool danger = true,
  }) async {
    final ok = await confirmAction(
      context,
      title: type.arabicTitle,
      message: 'هل أنت متأكد من تنفيذ الأمر على ${device.name}؟',
      danger: danger,
      confirmLabel: 'تنفيذ',
    );
    if (!ok || !context.mounted) return;
    await context.read<DeviceRepository>().sendCommand(
          userId: userId,
          deviceId: device.id,
          type: type,
          payload: payload,
          executeAt: executeAt,
        );
    if (context.mounted) {
      showAppSnack(context, 'تم إرسال الأمر: ${type.arabicTitle}');
    }
  }

  Future<void> _schedule(BuildContext context, CommandType type) async {
    final controller = TextEditingController(text: '10');
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(type.arabicTitle),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'بعد كم دقيقة؟',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text) ?? 10),
            child: const Text('جدولة'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (minutes == null || !context.mounted) return;
    await _send(
      context,
      type,
      payload: {'delayMinutes': minutes},
      executeAt: DateTime.now().add(Duration(minutes: minutes)),
    );
  }

  Future<void> _lockMinutes(BuildContext context, CommandType type) async {
    final controller = TextEditingController(text: '30');
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(type.arabicTitle),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'كم دقيقة؟',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text) ?? 30),
            child: const Text('تنفيذ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (minutes == null || !context.mounted) return;
    await _send(
      context,
      type,
      payload: {'minutes': minutes, 'delayMinutes': minutes},
      executeAt: type == CommandType.lockAfterDelay
          ? DateTime.now().add(Duration(minutes: minutes))
          : null,
      danger: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الطاقة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ActionTile(
            title: 'إغلاق الكمبيوتر',
            subtitle: 'إرسال أمر shutdown_pc',
            icon: Icons.power_settings_new,
            danger: true,
            onTap: () => _send(context, CommandType.shutdownPc),
          ),
          ActionTile(
            title: 'إعادة التشغيل',
            subtitle: 'إرسال أمر restart_pc',
            icon: Icons.restart_alt,
            danger: true,
            onTap: () => _send(context, CommandType.restartPc),
          ),
          ActionTile(
            title: 'قفل الشاشة',
            subtitle: 'إرسال أمر lock_screen',
            icon: Icons.lock_outline,
            onTap: () => _send(context, CommandType.lockScreen, danger: false),
          ),
          ActionTile(
            title: 'قفل لمدة محددة',
            subtitle:
                'يقفل الآن ويعيد القفل إذا حاول أحد فتحه قبل انتهاء المدة',
            icon: Icons.lock_clock_outlined,
            onTap: () => _lockMinutes(context, CommandType.lockForDuration),
          ),
          ActionTile(
            title: 'فتح مؤقت ثم قفل',
            subtitle: 'اترك الجهاز متاحاً لمدة محددة ثم اقفله تلقائياً',
            icon: Icons.timer_outlined,
            onTap: () => _lockMinutes(context, CommandType.lockAfterDelay),
          ),
          ActionTile(
            title: 'إيقاف إعادة القفل',
            subtitle: 'يلغي القفل المؤقت ولا يفتح Windows تلقائياً',
            icon: Icons.lock_open_outlined,
            onTap: () =>
                _send(context, CommandType.clearTimedLock, danger: false),
          ),
          ActionTile(
            title: 'إلغاء قفل مجدول',
            subtitle: 'إلغاء أمر قفل تم تحديده لوقت لاحق',
            icon: Icons.event_busy_outlined,
            onTap: () =>
                _send(context, CommandType.cancelScheduledLock, danger: false),
          ),
          ActionTile(
            title: 'تسجيل الخروج',
            subtitle: 'إرسال أمر logout_user',
            icon: Icons.logout,
            danger: true,
            onTap: () => _send(context, CommandType.logoutUser),
          ),
          ActionTile(
            title: 'إغلاق بعد مدة',
            subtitle: 'جدولة إغلاق الكمبيوتر بعد دقائق محددة',
            icon: Icons.timer_off_outlined,
            danger: true,
            onTap: () => _schedule(context, CommandType.shutdownAfterDelay),
          ),
          ActionTile(
            title: 'إعادة تشغيل بعد مدة',
            subtitle: 'جدولة إعادة التشغيل بعد دقائق محددة',
            icon: Icons.timer_outlined,
            danger: true,
            onTap: () => _schedule(context, CommandType.restartAfterDelay),
          ),
          ActionTile(
            title: 'إلغاء أمر طاقة مجدول',
            subtitle: 'إلغاء آخر أمر إغلاق/إعادة تشغيل مجدول',
            icon: Icons.cancel_schedule_send_outlined,
            onTap: () => _send(context, CommandType.cancelScheduledPowerCommand,
                danger: false),
          ),
        ],
      ),
    );
  }
}
