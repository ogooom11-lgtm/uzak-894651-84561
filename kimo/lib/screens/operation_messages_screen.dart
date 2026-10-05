import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_formatters.dart';
import '../models/command_response.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';

class OperationMessagesScreen extends StatelessWidget {
  const OperationMessagesScreen(
      {super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  Future<void> _clear(BuildContext context) async {
    final ok = await confirmAction(
      context,
      title: 'حذف سجل رسائل العمليات',
      message:
          'هل تريد حذف كل رسائل نجاح وفشل العمليات من Firebase لهذا الجهاز؟',
      danger: true,
      confirmLabel: 'حذف السجل',
    );
    if (!ok || !context.mounted) return;
    await context.read<DeviceRepository>().clearCommandResponses(device.id);
    if (context.mounted) showAppSnack(context, 'تم حذف سجل رسائل العمليات.');
  }

  IconData _icon(CommandResponse response) {
    if (response.isReceivedPhase) return Icons.mark_email_read_outlined;
    return response.success ? Icons.check_circle : Icons.error_outline;
  }

  Color _color(BuildContext context, CommandResponse response) {
    if (response.isReceivedPhase) return Theme.of(context).colorScheme.primary;
    return response.success ? Colors.green : Colors.red;
  }

  String _phaseLabel(CommandResponse response) {
    if (response.isReceivedPhase) return 'استلام الأمر';
    if (response.success) return 'نجاح التنفيذ';
    return 'فشل التنفيذ';
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DeviceRepository>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('رسائل العمليات'),
        actions: [
          IconButton(
            tooltip: 'حذف السجل',
            onPressed: () => _clear(context),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: StreamBuilder<List<CommandResponse>>(
        stream: repo.watchCommandResponses(device.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final responses = snapshot.data!;
          if (responses.isEmpty) {
            return const EmptyState(
              icon: Icons.mark_chat_read_outlined,
              title: 'لا توجد رسائل عمليات',
              subtitle:
                  'عند تنفيذ الأوامر سيظهر هنا الاستلام والنجاح أو سبب الفشل.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: responses.length,
            itemBuilder: (context, index) {
              final response = responses[index];
              final color = _color(context, response);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: color.withValues(alpha: .12),
                            child: Icon(_icon(response), color: color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _phaseLabel(response),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                    AppFormatters.dateTime(response.createdAt)),
                              ],
                            ),
                          ),
                          if ((response.commandType ?? '').isNotEmpty)
                            Chip(label: Text(response.commandType!)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(response.message.isEmpty
                          ? 'لا توجد رسالة'
                          : response.message),
                      const SizedBox(height: 8),
                      Text(
                        'Command ID: ${response.commandId}',
                        style: Theme.of(context).textTheme.bodySmall,
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
