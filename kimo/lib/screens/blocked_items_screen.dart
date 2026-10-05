import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_formatters.dart';
import '../core/app_icon_registry.dart';
import '../core/command_type.dart';
import '../models/blocked_item.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';

class BlockedItemsScreen extends StatelessWidget {
  const BlockedItemsScreen({
    super.key,
    required this.userId,
    required this.device,
  });

  final String userId;
  final PcDevice device;

  Future<void> _allow(
    BuildContext context,
    BlockedItem item, {
    Duration? duration,
  }) async {
    final label = item.label.isEmpty ? item.target : item.label;
    final confirmed = await confirmAction(
      context,
      title: duration == null ? 'رفع المنع' : 'سماح مؤقت',
      message: duration == null
          ? 'هل تريد رفع المنع عن $label؟'
          : 'هل تريد السماح لـ $label لمدة ${duration.inMinutes} دقيقة؟',
      danger: duration == null,
      confirmLabel: duration == null ? 'رفع المنع' : 'سماح',
    );
    if (!confirmed || !context.mounted) return;

    await context.read<DeviceRepository>().sendCommand(
      userId: userId,
      deviceId: device.id,
      type: item.type == 'site'
          ? CommandType.allowWebsite
          : CommandType.allowApplication,
      payload: {
        'target': item.target,
        if (item.type == 'site') 'domain': item.target,
        if (item.type != 'site') 'appName': item.label,
        if (item.appPath.isNotEmpty) 'appPath': item.appPath,
        if (duration != null) 'durationSeconds': duration.inSeconds,
      },
    );
    if (context.mounted) {
      showAppSnack(
        context,
        duration == null
            ? 'تم إرسال أمر رفع المنع.'
            : 'تم إرسال السماح المؤقت.',
      );
    }
  }

  Future<void> _blockWebsite(BuildContext context) async {
    final controller = TextEditingController();
    final passwordController = TextEditingController();
    var lockType = 'blocked';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('منع موقع'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'الرابط أو الدومين',
                  hintText: 'youtube.com',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: lockType,
                decoration: const InputDecoration(
                  labelText: 'نوع المنع',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'blocked', child: Text('منع كامل')),
                  DropdownMenuItem(
                    value: 'password',
                    child: Text('كلمة مرور / سماح مؤقت'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => lockType = value ?? lockType),
              ),
              if (lockType == 'password') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'domain': controller.text.trim(),
                'lockType': lockType,
                'password': passwordController.text.trim(),
              }),
              child: const Text('منع'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    passwordController.dispose();
    final domain = result?['domain'] ?? '';
    if (domain.isEmpty || !context.mounted) return;

    final confirmed = await confirmAction(
      context,
      title: 'تأكيد منع الموقع',
      message: 'سيتم منع فتح $domain على ${device.name}.',
      danger: true,
      confirmLabel: 'منع',
    );
    if (!confirmed || !context.mounted) return;

    await context.read<DeviceRepository>().sendCommand(
      userId: userId,
      deviceId: device.id,
      type: CommandType.blockWebsite,
      payload: {
        'target': domain,
        'domain': domain,
        'lockType': result?['lockType'] ?? 'blocked',
        if ((result?['password'] ?? '').isNotEmpty)
          'password': result!['password'],
      },
    );
    if (context.mounted) showAppSnack(context, 'تم إرسال أمر منع الموقع.');
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DeviceRepository>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('الممنوعات'),
        actions: [
          IconButton(
            tooltip: 'منع موقع',
            onPressed: () => _blockWebsite(context),
            icon: const Icon(Icons.public_off_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _blockWebsite(context),
        icon: const Icon(Icons.public_off_outlined),
        label: const Text('منع موقع'),
      ),
      body: StreamBuilder<List<BlockedItem>>(
        stream: repo.watchBlockedItems(device.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.verified_user_outlined,
              title: 'لا توجد تطبيقات أو مواقع ممنوعة',
              subtitle: 'يمكن منع تطبيق من صفحة التطبيقات أو منع موقع من هنا.',
            );
          }
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: ListView.builder(
              key: ValueKey(items.length),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 92),
              itemCount: items.length,
              itemBuilder: (context, index) => _BlockedItemCard(
                item: items[index],
                onAllow: () => _allow(context, items[index]),
                onAllowThirty: () => _allow(
                  context,
                  items[index],
                  duration: const Duration(minutes: 30),
                ),
                onAllowTwoHours: () => _allow(
                  context,
                  items[index],
                  duration: const Duration(hours: 2),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BlockedItemCard extends StatelessWidget {
  const _BlockedItemCard({
    required this.item,
    required this.onAllow,
    required this.onAllowThirty,
    required this.onAllowTwoHours,
  });

  final BlockedItem item;
  final VoidCallback onAllow;
  final VoidCallback onAllowThirty;
  final VoidCallback onAllowTwoHours;

  @override
  Widget build(BuildContext context) {
    final match = AppIconRegistry.matchText('${item.label} ${item.target}');
    final color = item.type == 'site'
        ? Theme.of(context).colorScheme.tertiary
        : match.color;
    final title = item.label.isEmpty ? item.target : item.label;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: item.type == 'site'
                      ? Icon(Icons.public_off_outlined, color: color)
                      : match.assetPath == null
                          ? Icon(match.icon, color: color)
                          : Padding(
                              padding: const EdgeInsets.all(8),
                              child: Image.asset(
                                match.assetPath!,
                                errorBuilder: (_, __, ___) =>
                                    Icon(match.icon, color: color),
                              ),
                            ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.type == 'site' ? item.target : item.appPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Chip(
                  avatar: Icon(
                    item.type == 'site'
                        ? Icons.language_outlined
                        : Icons.apps_outlined,
                    size: 18,
                  ),
                  label: Text(item.type == 'site' ? 'موقع' : 'تطبيق'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.isTemporarilyAllowed && item.allowedUntil != null
                  ? 'مسموح مؤقتاً حتى ${AppFormatters.dateTime(item.allowedUntil!)}'
                  : 'ممنوع منذ ${AppFormatters.dateTime(item.createdAt)}'
                      '${item.type == 'site' && item.lockType == 'password' ? ' • كلمة مرور/سماح مؤقت' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onAllow,
                    icon: const Icon(Icons.lock_open_outlined),
                    label: const Text('رفع المنع'),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<VoidCallback>(
                  tooltip: 'سماح لمدة',
                  onSelected: (callback) => callback(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: onAllowThirty,
                      child: const Text('سماح 30 دقيقة'),
                    ),
                    PopupMenuItem(
                      value: onAllowTwoHours,
                      child: const Text('سماح ساعتين'),
                    ),
                  ],
                  child: IgnorePointer(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.timer_outlined),
                      label: const Text('سماح لمدة'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
