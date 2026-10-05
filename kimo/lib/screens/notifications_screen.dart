import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_formatters.dart';
import '../models/device_notification.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/empty_state.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.device});

  final PcDevice device;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DeviceRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: StreamBuilder<List<DeviceNotification>>(
        stream: repo.watchNotifications(device.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'لا توجد إشعارات بعد',
              subtitle: 'ستظهر هنا تنبيهات الأوامر وطلبات الإذن والأحداث المهمة فور وصولها.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _NotificationTile(
                item: item,
                onTap: () => repo.markNotificationRead(
                  deviceId: device.id,
                  notificationId: item.id,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final DeviceNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(context, item.severity);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(_iconFor(item.type), color: color),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: item.read ? FontWeight.w700 : FontWeight.w900,
                ),
              ),
            ),
            if (!item.read)
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(item.message, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              AppFormatters.dateTime(item.createdAt),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Color _severityColor(BuildContext context, String severity) {
    final cs = Theme.of(context).colorScheme;
    switch (severity) {
      case 'success':
        return const Color(0xFF16A34A);
      case 'warning':
        return const Color(0xFFF59E0B);
      case 'error':
        return cs.error;
      default:
        return cs.primary;
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'permission_request':
        return Icons.verified_user_rounded;
      case 'command_done':
        return Icons.task_alt_rounded;
      case 'command_failed':
        return Icons.error_rounded;
      case 'install_request':
        return Icons.install_desktop_rounded;
      case 'privacy_mode':
        return Icons.visibility_off_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }
}
