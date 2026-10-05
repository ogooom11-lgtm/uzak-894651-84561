import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_formatters.dart';
import '../core/command_type.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';
import '../widgets/empty_state.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  bool _loading = false;
  Map<String, dynamic>? _health;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHealth();
  }

  Future<void> _loadHealth() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<DeviceRepository>();
      final commandId = await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.systemHealth,
      );
      final response = await repo.waitForCommandResponse(
        deviceId: widget.device.id,
        commandId: commandId,
        timeout: const Duration(seconds: 25),
      );
      if (!mounted) return;
      if (response == null) {
        setState(() => _error = 'لم يصل رد من الكمبيوتر.');
      } else if (!response.success) {
        setState(() => _error = response.message);
      } else {
        setState(() => _health = response.payload);
        showAppSnack(context, 'تم تحديث صحة الجهاز.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final health = _health;
    return Scaffold(
      appBar: AppBar(
        title: const Text('صحة الجهاز'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _loadHealth,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && health == null
          ? const Center(child: CircularProgressIndicator())
          : health == null
              ? EmptyState(
                  icon: Icons.monitor_heart_rounded,
                  title: 'لا توجد بيانات بعد',
                  subtitle: _error ?? 'اضغط تحديث لجلب حالة الكمبيوتر.',
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    _HealthHeader(health: health),
                    const SizedBox(height: 12),
                    _MetricGrid(health: health),
                    const SizedBox(height: 12),
                    _DisksCard(disks: (health['disks'] as List?) ?? const []),
                  ],
                ),
    );
  }
}

class _HealthHeader extends StatelessWidget {
  const _HealthHeader({required this.health});

  final Map<String, dynamic> health;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.monitor_heart_rounded, color: Colors.white, size: 42),
          const SizedBox(height: 12),
          Text(
            (health['computerName'] ?? 'Windows PC').toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${health['os'] ?? 'Windows'} • المستخدم: ${health['windowsUser'] ?? ''}',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.health});

  final Map<String, dynamic> health;

  @override
  Widget build(BuildContext context) {
    final memory = (health['memory'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final battery = (health['battery'] as Map?)?.cast<String, dynamic>();
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.45,
      children: [
        _MetricCard(
          title: 'CPU',
          value: '${health['cpuLoadPercent'] ?? 0}%',
          icon: Icons.memory_rounded,
        ),
        _MetricCard(
          title: 'RAM',
          value: '${memory['usedPercent'] ?? 0}%',
          subtitle: _memorySubtitle(memory),
          icon: Icons.developer_board_rounded,
        ),
        _MetricCard(
          title: 'البطارية',
          value: battery == null ? 'غير متاحة' : '${battery['percent'] ?? 0}%',
          icon: Icons.battery_charging_full_rounded,
        ),
        _MetricCard(
          title: 'مدة التشغيل',
          value: _uptime(health['uptimeMinutes']),
          icon: Icons.timer_rounded,
        ),
      ],
    );
  }

  String _memorySubtitle(Map<String, dynamic> memory) {
    final used = int.tryParse('${memory['usedBytes'] ?? 0}') ?? 0;
    final total = int.tryParse('${memory['totalBytes'] ?? 0}') ?? 0;
    if (total <= 0) return '';
    return '${AppFormatters.fileSize(used)} / ${AppFormatters.fileSize(total)}';
  }

  String _uptime(dynamic value) {
    final minutes = int.tryParse('$value') ?? 0;
    if (minutes < 60) return '$minutes د';
    return '${(minutes / 60).floor()} س ${minutes % 60} د';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    this.subtitle,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: cs.primary),
            const Spacer(),
            Text(title, style: TextStyle(color: cs.onSurfaceVariant)),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _DisksCard extends StatelessWidget {
  const _DisksCard({required this.disks});

  final List<dynamic> disks;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'التخزين',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            for (final disk in disks.whereType<Map>()) _DiskRow(disk: disk),
            if (disks.isEmpty)
              const Text('لا توجد بيانات تخزين متاحة حالياً.'),
          ],
        ),
      ),
    );
  }
}

class _DiskRow extends StatelessWidget {
  const _DiskRow({required this.disk});

  final Map disk;

  @override
  Widget build(BuildContext context) {
    final total = int.tryParse('${disk['totalBytes'] ?? 0}') ?? 0;
    final free = int.tryParse('${disk['freeBytes'] ?? 0}') ?? 0;
    final used = total - free;
    final percent = total <= 0 ? 0.0 : used / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${disk['name'] ?? ''} ${disk['label'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text('${(percent * 100).round()}%'),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: percent.clamp(0, 1).toDouble()),
          const SizedBox(height: 4),
          Text(
            '${AppFormatters.fileSize(used)} مستخدم من ${AppFormatters.fileSize(total)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
