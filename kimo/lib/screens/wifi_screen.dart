import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/command_type.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';
import '../widgets/confirm_dialog.dart';

class WifiScreen extends StatelessWidget {
  const WifiScreen({super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  Future<void> _send(BuildContext context, CommandType type) async {
    if (type == CommandType.internetOffPermanent) {
      final ok = await confirmAction(
        context,
        title: 'إيقاف الإنترنت نهائياً',
        message:
            'هذا سيعطل كروت الشبكة على الكمبيوتر وقد يقطع اتصالك به حتى تعيد تشغيل الإنترنت أو تعيد تشغيل الجهاز. هل تريد المتابعة؟',
        danger: true,
        confirmLabel: 'إيقاف نهائي',
      );
      if (!ok || !context.mounted) return;
    }
    await context.read<DeviceRepository>().sendCommand(
          userId: userId,
          deviceId: device.id,
          type: type,
        );
    if (context.mounted) {
      showAppSnack(context, 'تم إرسال الأمر: ${type.arabicTitle}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة WiFi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.wifi, size: 48),
                  const SizedBox(height: 12),
                  Text('الحالة الحالية: ${device.wifiStatus ?? 'غير معروفة'}',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _send(context, CommandType.wifiOn),
                    icon: const Icon(Icons.wifi),
                    label: const Text('تشغيل WiFi'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _send(context, CommandType.wifiOff),
                    icon: const Icon(Icons.wifi_off),
                    label: const Text('فصل اتصال WiFi الحالي'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _send(context, CommandType.checkConnection),
                    icon: const Icon(Icons.refresh),
                    label: const Text('تحديث الحالة'),
                  ),
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _send(context, CommandType.internetOn),
                    icon: const Icon(Icons.settings_ethernet),
                    label: const Text('تشغيل الإنترنت'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () =>
                        _send(context, CommandType.internetOffPermanent),
                    icon: const Icon(Icons.portable_wifi_off),
                    label: const Text('إيقاف الإنترنت نهائياً'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
