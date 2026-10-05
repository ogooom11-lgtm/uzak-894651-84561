import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_icon_registry.dart';
import '../core/command_type.dart';
import '../models/installed_app.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';
import '../widgets/empty_state.dart';

class InstalledAppsScreen extends StatefulWidget {
  const InstalledAppsScreen(
      {super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  @override
  State<InstalledAppsScreen> createState() => _InstalledAppsScreenState();
}

class _InstalledAppsScreenState extends State<InstalledAppsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DeviceRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('التطبيقات المثبتة')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'بحث عن تطبيق',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<InstalledApp>>(
              stream: repo.watchInstalledApps(widget.device.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final apps = snapshot.data!.where((app) {
                  if (_query.isEmpty) return true;
                  return '${app.name} ${app.publisher} ${app.version}'
                      .toLowerCase()
                      .contains(_query);
                }).toList();
                if (apps.isEmpty) {
                  return const EmptyState(
                    icon: Icons.install_desktop_outlined,
                    title: 'لا توجد تطبيقات',
                    subtitle:
                        'عند مزامنة الكمبيوتر ستظهر قائمة التطبيقات المثبتة هنا.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: apps.length,
                  itemBuilder: (context, index) => _InstalledAppCard(
                    userId: widget.userId,
                    device: widget.device,
                    app: apps[index],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InstalledAppCard extends StatelessWidget {
  const _InstalledAppCard({
    required this.userId,
    required this.device,
    required this.app,
  });

  final String userId;
  final PcDevice device;
  final InstalledApp app;

  Future<void> _send(BuildContext context, CommandType type) async {
    await context.read<DeviceRepository>().sendCommand(
      userId: userId,
      deviceId: device.id,
      type: type,
      payload: {
        'target': app.name,
        'appName': app.name,
        'appPath': app.installLocation,
      },
    );
    if (context.mounted) {
      showAppSnack(context, 'تم إرسال الأمر: ${type.arabicTitle}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = AppIconRegistry.matchText(
        '${app.iconKey} ${app.name} ${app.publisher}');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: match.color.withValues(alpha: .12),
              ),
              alignment: Alignment.center,
              child: match.assetPath == null
                  ? Icon(match.icon, color: match.color)
                  : Padding(
                      padding: const EdgeInsets.all(7),
                      child: Image.asset(
                        match.assetPath!,
                        errorBuilder: (_, __, ___) =>
                            Icon(match.icon, color: match.color),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  if (app.publisher.isNotEmpty)
                    Text(app.publisher,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (app.version.isNotEmpty)
                    Text('الإصدار: ${app.version}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (app.installLocation.isNotEmpty)
                    Text(
                      app.installLocation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            PopupMenuButton<CommandType>(
              onSelected: (type) => _send(context, type),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: CommandType.blockApplication,
                  child: Text('منع التطبيق'),
                ),
                PopupMenuItem(
                  value: CommandType.allowApplication,
                  child: Text('إلغاء المنع'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
