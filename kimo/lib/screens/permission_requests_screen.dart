import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_formatters.dart';
import '../models/pc_device.dart';
import '../models/permission_request.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';
import '../widgets/empty_state.dart';

class PermissionRequestsScreen extends StatelessWidget {
  const PermissionRequestsScreen(
      {super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  Future<void> _answer(
    BuildContext context,
    PermissionRequest request,
    bool approve, {
    Duration? duration,
    bool always = false,
  }) async {
    await context.read<DeviceRepository>().answerPermission(
          userId: userId,
          deviceId: device.id,
          requestId: request.id,
          approve: approve,
          duration: duration,
          always: always,
        );
    if (context.mounted) {
      showAppSnack(context,
          approve ? 'تمت الموافقة وإرسال الأمر.' : 'تم الرفض وإرسال الأمر.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DeviceRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('طلبات الإذن')),
      body: StreamBuilder<List<PermissionRequest>>(
        stream: repo.watchPermissionRequests(device.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final requests = snapshot.data!;
          if (requests.isEmpty) {
            return const EmptyState(
              icon: Icons.verified_user_outlined,
              title: 'لا توجد طلبات إذن حالياً',
              subtitle:
                  'ستظهر هنا طلبات فتح المسارات أو تشغيل التطبيقات المحظورة.',
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
                      Text(request.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text('المسار: ${request.targetPath}'),
                      if (request.details != null) Text(request.details!),
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
                            icon: const Icon(Icons.close),
                            label: const Text('رفض'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _answer(context, request, true),
                            icon: const Icon(Icons.check),
                            label: const Text('السماح مرة واحدة'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _answer(context, request, true,
                                duration: const Duration(minutes: 10)),
                            icon: const Icon(Icons.timer),
                            label: const Text('10 دقائق'),
                          ),
                          FilledButton.icon(
                            onPressed: () => _answer(context, request, true,
                                duration: const Duration(hours: 1)),
                            icon: const Icon(Icons.lock_open),
                            label: const Text('ساعة'),
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
