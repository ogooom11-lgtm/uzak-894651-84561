import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_formatters.dart';
import '../core/command_type.dart';
import '../models/pc_device.dart';
import '../models/screenshot_item.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';

class ScreenshotsScreen extends StatelessWidget {
  const ScreenshotsScreen(
      {super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  Future<void> _request(BuildContext context) async {
    final ok = await confirmAction(
      context,
      title: 'طلب لقطة شاشة',
      message: 'هل تريد التقاط شاشة ${device.name} وإرسالها إلى Telegram؟',
    );
    if (!ok || !context.mounted) return;
    await context.read<DeviceRepository>().sendCommand(
          userId: userId,
          deviceId: device.id,
          type: CommandType.requestScreenshot,
        );
    if (context.mounted) showAppSnack(context, 'تم إرسال طلب لقطة شاشة.');
  }

  Future<void> _delete(BuildContext context, ScreenshotItem item) async {
    final ok = await confirmAction(
      context,
      title: 'حذف لقطة الشاشة',
      message: 'هل تريد حذف هذه الصورة من Firebase؟',
      danger: true,
      confirmLabel: 'حذف',
    );
    if (!ok || !context.mounted) return;
    await context
        .read<DeviceRepository>()
        .deleteScreenshot(deviceId: device.id, screenshot: item);
    if (context.mounted) showAppSnack(context, 'تم حذف الصورة.');
  }

  bool _isHttpImage(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DeviceRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('لقطات الشاشة')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _request(context),
        icon: const Icon(Icons.screenshot_monitor_outlined),
        label: const Text('طلب الآن'),
      ),
      body: StreamBuilder<List<ScreenshotItem>>(
        stream: repo.watchScreenshots(device.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.image_not_supported_outlined,
              title: 'لا توجد لقطات شاشة',
              subtitle:
                  'اضغط طلب الآن وسيقوم الكمبيوتر برفع الصورة عند توفر الاتصال.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 92),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _isHttpImage(item.imageUrl)
                          ? Image.network(
                              item.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child:
                                    Icon(Icons.broken_image_outlined, size: 48),
                              ),
                            )
                          : Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.send_outlined, size: 50),
                                    SizedBox(height: 10),
                                    Text('تم إرسال اللقطة إلى Telegram'),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'الوقت: ${AppFormatters.dateTime(item.createdAt)}'
                              '${_isHttpImage(item.imageUrl) ? '' : '\nالمسار المحلي: ${item.storagePath ?? item.imageUrl}'}',
                            ),
                          ),
                          IconButton(
                            tooltip: 'حذف',
                            onPressed: () => _delete(context, item),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
