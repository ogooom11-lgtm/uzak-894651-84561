import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_formatters.dart';
import '../core/app_icon_registry.dart';
import '../core/command_type.dart';
import '../models/open_app.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_open_icon.dart';
import '../widgets/app_snack.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';

class OpenAppsScreen extends StatelessWidget {
  const OpenAppsScreen({super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  Future<void> _closeApp(BuildContext context, OpenApp app) async {
    final ok = await confirmAction(
      context,
      title: 'إغلاق تطبيق أو صفحة',
      message: 'هل تريد إغلاق ${app.title} على ${device.name}؟',
      danger: true,
      confirmLabel: 'إغلاق',
    );
    if (!ok || !context.mounted) return;
    await context.read<DeviceRepository>().sendCommand(
      userId: userId,
      deviceId: device.id,
      type: CommandType.closeApplication,
      payload: {
        'processId': app.processId,
        'target': app.appName,
        'appPath': app.appPath,
        'openAppId': app.id,
        'windowTitle': app.windowTitle,
        'pageTitle': app.pageTitle,
        'url': app.url,
      },
    );
    if (context.mounted) {
      showAppSnack(context, 'تم إرسال أمر إغلاق ${app.title}');
    }
  }

  Future<void> _closeAfter(
      BuildContext context, OpenApp app, int minutes) async {
    await context.read<DeviceRepository>().sendCommand(
          userId: userId,
          deviceId: device.id,
          type: CommandType.closeApplicationAfterDelay,
          payload: {
            'processId': app.processId,
            'target': app.appName,
            'delayMinutes': minutes,
            'appPath': app.appPath,
            'openAppId': app.id,
            'windowTitle': app.windowTitle,
            'pageTitle': app.pageTitle,
            'url': app.url,
          },
          executeAt: DateTime.now().add(Duration(minutes: minutes)),
        );
    if (context.mounted) {
      showAppSnack(context, 'سيتم إغلاق ${app.title} بعد $minutes دقائق');
    }
  }

  Future<void> _blockApp(BuildContext context, OpenApp app) async {
    final ok = await confirmAction(
      context,
      title: 'منع تطبيق',
      message:
          'سيتم إغلاق ${app.appName} الآن وكلما فُتح لاحقاً على ${device.name}.',
      danger: true,
      confirmLabel: 'منع',
    );
    if (!ok || !context.mounted) return;
    await context.read<DeviceRepository>().sendCommand(
      userId: userId,
      deviceId: device.id,
      type: CommandType.blockApplication,
      payload: {
        'target': app.appName,
        'appName': app.appName,
        'appPath': app.appPath,
        'processId': app.processId,
      },
    );
    if (context.mounted) {
      showAppSnack(context, 'تم إرسال أمر منع ${app.appName}');
    }
  }

  Future<void> _allowApp(BuildContext context, OpenApp app) async {
    await context.read<DeviceRepository>().sendCommand(
      userId: userId,
      deviceId: device.id,
      type: CommandType.allowApplication,
      payload: {
        'target': app.appName,
        'appName': app.appName,
        'appPath': app.appPath,
      },
    );
    if (context.mounted) {
      showAppSnack(context, 'تم إرسال أمر السماح لـ ${app.appName}');
    }
  }

  Future<void> _blockWebsite(BuildContext context, OpenApp app) async {
    final target = (app.url ?? app.siteName ?? app.pageTitle ?? '').trim();
    if (target.isEmpty) {
      showAppSnack(context, 'لا يوجد رابط واضح لهذه الصفحة.');
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'منع موقع',
      message: 'سيتم منع فتح هذا الموقع على ${device.name}:\n$target',
      danger: true,
      confirmLabel: 'منع',
    );
    if (!ok || !context.mounted) return;
    await context.read<DeviceRepository>().sendCommand(
      userId: userId,
      deviceId: device.id,
      type: CommandType.blockWebsite,
      payload: {
        'target': target,
        'domain': target,
        'pageTitle': app.pageTitle,
        'url': app.url,
      },
    );
    if (context.mounted) showAppSnack(context, 'تم إرسال أمر منع الموقع.');
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DeviceRepository>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('التطبيقات والصفحات المفتوحة'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(34),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'يدعم أكثر من ${AppIconRegistry.knownIconCount} أيقونة محلية، ومع صفحات المتصفح يعرض أيقونة الموقع من الرابط.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<OpenApp>>(
        stream: repo.watchOpenApps(device.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final apps = snapshot.data!;
          if (apps.isEmpty) {
            return const EmptyState(
              icon: Icons.apps_outage,
              title: 'لا توجد تطبيقات مفتوحة',
              subtitle:
                  'قد تكون البيانات غير محدثة إذا كان الكمبيوتر غير متصل.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: apps.length,
            itemBuilder: (context, index) {
              final app = apps[index];
              final match = AppIconRegistry.match(app);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          OpenAppIconAvatar(app: app, match: match),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  app.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  app.isBrowserItem
                                      ? '${app.browserName ?? app.appName} • ${app.siteName ?? match.label}'
                                      : app.appName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<int>(
                            onSelected: (minutes) =>
                                _closeAfter(context, app, minutes),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 5, child: Text('إغلاق بعد 5 دقائق')),
                              PopupMenuItem(
                                  value: 10, child: Text('إغلاق بعد 10 دقائق')),
                              PopupMenuItem(
                                  value: 30, child: Text('إغلاق بعد 30 دقيقة')),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(label: Text('PID: ${app.processId}')),
                          Chip(
                              label: Text(
                                  AppFormatters.durationFrom(app.openedAt))),
                          Chip(label: Text(app.status)),
                          if (app.isBrowserItem)
                            const Chip(label: Text('صفحة متصفح')),
                        ],
                      ),
                      if (app.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SelectableText(
                          app.subtitle,
                          maxLines: 3,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if ((app.windowTitle ?? '').isNotEmpty &&
                          app.windowTitle != app.title) ...[
                        const SizedBox(height: 8),
                        Text(
                          'عنوان النافذة: ${app.windowTitle}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (app.lastUpdated != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'آخر تحديث: ${AppFormatters.dateTime(app.lastUpdated!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _closeApp(context, app),
                          icon: const Icon(Icons.close),
                          label: Text(app.isBrowserItem
                              ? 'إغلاق هذه الصفحة/العملية'
                              : 'إغلاق التطبيق الآن'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _blockApp(context, app),
                              icon: const Icon(Icons.block),
                              label: const Text('منع التطبيق'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _allowApp(context, app),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('إلغاء المنع'),
                            ),
                          ),
                        ],
                      ),
                      if (app.isBrowserItem) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _blockWebsite(context, app),
                            icon: const Icon(Icons.public_off_outlined),
                            label: const Text('منع هذا الموقع'),
                          ),
                        ),
                      ],
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
