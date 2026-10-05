import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/command_type.dart';
import '../models/command_response.dart';
import '../models/log_entry.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';
import '../widgets/empty_state.dart';

class SmartInsightsScreen extends StatelessWidget {
  const SmartInsightsScreen({super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  Future<void> _requestTodayLogs(BuildContext context) async {
    final now = DateTime.now();
    await context.read<DeviceRepository>().sendCommand(
          userId: userId,
          deviceId: device.id,
          type: CommandType.requestLogs,
          payload: {
            'logType': 'all',
            'from': DateTime(now.year, now.month, now.day).toIso8601String(),
            'to': now.toIso8601String(),
          },
        );
    if (context.mounted) showAppSnack(context, 'تم طلب سجلات اليوم للتحليل.');
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DeviceRepository>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('السجلات الذكية'),
        actions: [
          IconButton(
            tooltip: 'طلب سجلات اليوم',
            onPressed: () => _requestTodayLogs(context),
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: StreamBuilder<List<LogEntry>>(
        stream: repo.watchRequestedLogs(device.id),
        builder: (context, logSnapshot) {
          return StreamBuilder<List<CommandResponse>>(
            stream: repo.watchCommandResponses(device.id),
            builder: (context, responseSnapshot) {
              final logs = logSnapshot.data ?? const <LogEntry>[];
              final responses = responseSnapshot.data ?? const <CommandResponse>[];
              if (logs.isEmpty && responses.isEmpty) {
                return EmptyState(
                  icon: Icons.insights_rounded,
                  title: 'لا توجد بيانات تحليل بعد',
                  subtitle: 'اضغط زر التحميل لجلب سجلات اليوم ثم سترى ملخصاً ذكياً.',
                );
              }
              final insights = _buildInsights(logs, responses);
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SummaryHeader(insights: insights),
                  const SizedBox(height: 12),
                  _InsightCard(
                    title: 'أكثر أنواع الأحداث',
                    icon: Icons.category_rounded,
                    rows: insights.topTypes,
                  ),
                  _InsightCard(
                    title: 'أكثر التطبيقات ظهوراً',
                    icon: Icons.apps_rounded,
                    rows: insights.topApps,
                    emptyText: 'لا توجد تطبيقات واضحة في السجلات الحالية.',
                  ),
                  _InsightCard(
                    title: 'أكثر المواقع ظهوراً',
                    icon: Icons.language_rounded,
                    rows: insights.topSites,
                    emptyText: 'لا توجد مواقع واضحة في السجلات الحالية.',
                  ),
                  _InsightCard(
                    title: 'الأوامر الأخيرة',
                    icon: Icons.send_rounded,
                    rows: insights.commandRows,
                    emptyText: 'لا توجد ردود أوامر بعد.',
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Insights {
  const _Insights({
    required this.totalLogs,
    required this.errorCount,
    required this.commandCount,
    required this.successCommands,
    required this.topTypes,
    required this.topApps,
    required this.topSites,
    required this.commandRows,
  });

  final int totalLogs;
  final int errorCount;
  final int commandCount;
  final int successCommands;
  final List<_InsightRow> topTypes;
  final List<_InsightRow> topApps;
  final List<_InsightRow> topSites;
  final List<_InsightRow> commandRows;
}

_Insights _buildInsights(List<LogEntry> logs, List<CommandResponse> responses) {
  final typeCounts = <String, int>{};
  final appCounts = <String, int>{};
  final siteCounts = <String, int>{};
  var errors = 0;

  for (final log in logs) {
    typeCounts.update(log.type, (value) => value + 1, ifAbsent: () => 1);
    if (log.type.contains('error') || log.message.contains('خطأ')) errors++;
    final app = _appFromLog(log);
    if (app != null) appCounts.update(app, (value) => value + 1, ifAbsent: () => 1);
    final site = _siteFromLog(log);
    if (site != null) siteCounts.update(site, (value) => value + 1, ifAbsent: () => 1);
  }

  final finalResponses = responses.where((r) => r.isFinalPhase).toList();
  return _Insights(
    totalLogs: logs.length,
    errorCount: errors,
    commandCount: finalResponses.length,
    successCommands: finalResponses.where((r) => r.success).length,
    topTypes: _topRows(typeCounts),
    topApps: _topRows(appCounts),
    topSites: _topRows(siteCounts),
    commandRows: finalResponses.take(8).map((response) {
      return _InsightRow(
        response.commandType ?? 'command',
        response.success ? 'نجح' : 'فشل: ${response.message}',
        response.success ? Icons.check_circle_rounded : Icons.error_rounded,
        response.success ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
      );
    }).toList(),
  );
}

List<_InsightRow> _topRows(Map<String, int> counts) {
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries.take(8).map((entry) {
    return _InsightRow(
      entry.key,
      '${entry.value} مرة',
      Icons.circle_rounded,
      const Color(0xFF2563EB),
    );
  }).toList();
}

String? _appFromLog(LogEntry log) {
  final values = [
    log.payload['appName'],
    log.payload['processName'],
    log.payload['target'],
    log.target,
  ];
  for (final value in values) {
    final text = (value ?? '').toString().trim();
    if (text.toLowerCase().endsWith('.exe')) return text;
  }
  return null;
}

String? _siteFromLog(LogEntry log) {
  final values = [log.payload['domain'], log.payload['url'], log.payload['siteName'], log.target];
  for (final value in values) {
    var text = (value ?? '').toString().trim();
    if (text.startsWith('http://') || text.startsWith('https://')) {
      text = Uri.tryParse(text)?.host ?? text;
    }
    if (text.contains('.') && !text.contains(r':\')) return text;
  }
  return null;
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.insights});

  final _Insights insights;

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
          const Icon(Icons.insights_rounded, color: Colors.white, size: 42),
          const SizedBox(height: 12),
          const Text(
            'ملخص ذكي',
            style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill('السجلات ${insights.totalLogs}'),
              _Pill('الأخطاء ${insights.errorCount}'),
              _Pill('الأوامر ${insights.successCommands}/${insights.commandCount}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.icon,
    required this.rows,
    this.emptyText = 'لا توجد بيانات كافية.',
  });

  final String title;
  final IconData icon;
  final List<_InsightRow> rows;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              Text(emptyText)
            else
              for (final row in rows)
                ListTile(
                  dense: true,
                  leading: Icon(row.icon, color: row.color),
                  title: Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(row.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
          ],
        ),
      ),
    );
  }
}

class _InsightRow {
  const _InsightRow(this.title, this.subtitle, this.icon, this.color);

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}
