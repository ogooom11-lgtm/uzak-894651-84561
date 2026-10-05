import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_formatters.dart';
import '../models/install_request.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';
import '../widgets/empty_state.dart';

class InstallRequestsScreen extends StatelessWidget {
  const InstallRequestsScreen(
      {super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  Future<void> _answer(
    BuildContext context,
    InstallRequest request,
    bool approve, {
    Duration? duration,
    bool always = false,
  }) async {
    await context.read<DeviceRepository>().answerInstall(
          userId: userId,
          deviceId: device.id,
          requestId: request.id,
          approve: approve,
          duration: duration,
          always: always,
        );
    if (context.mounted) {
      showAppSnack(
          context, approve ? 'تم السماح بالتثبيت.' : 'تم رفض التثبيت.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DeviceRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('منع التثبيت')),
      body: StreamBuilder<List<InstallRequest>>(
        stream: repo.watchInstallRequests(device.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final requests = snapshot.data!;
          if (requests.isEmpty) {
            return const EmptyState(
              icon: Icons.install_desktop_outlined,
              title: 'لا توجد طلبات تثبيت',
              subtitle: 'عند محاولة تثبيت ملف جديد سيظهر الطلب هنا.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(request.fileName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(request.filePath),
                      const SizedBox(height: 6),
                      Text(
                          'الوقت: ${AppFormatters.dateTime(request.createdAt)}'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _answer(context, request, false),
                            icon: const Icon(Icons.block),
                            label: const Text('رفض'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _answer(context, request, true),
                            icon: const Icon(Icons.check),
                            label: const Text('السماح مرة واحدة'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _answer(context, request, true,
                                duration: const Duration(minutes: 30)),
                            icon: const Icon(Icons.timer),
                            label: const Text('30 دقيقة'),
                          ),
                          FilledButton.icon(
                            onPressed: () =>
                                _answer(context, request, true, always: true),
                            icon: const Icon(Icons.verified),
                            label: const Text('السماح دائماً'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
