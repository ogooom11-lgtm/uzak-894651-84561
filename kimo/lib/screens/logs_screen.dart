import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/app_formatters.dart';
import '../core/command_type.dart';
import '../models/log_entry.dart';
import '../models/path_rule.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String _type = 'all';
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();

  Future<void> _pickDateTime({required bool start}) async {
    final now = DateTime.now();
    final current = start ? _from : _to;
    final date = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 1)),
      initialDate: current,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (start) {
        _from = picked;
        if (_from.isAfter(_to)) _to = _from.add(const Duration(hours: 1));
      } else {
        _to = picked;
        if (_to.isBefore(_from)) {
          _from = _to.subtract(const Duration(hours: 1));
        }
      }
    });
  }

  Future<void> _requestLogs() async {
    await context.read<DeviceRepository>().sendCommand(
      userId: widget.userId,
      deviceId: widget.device.id,
      type: CommandType.requestLogs,
      payload: {
        'logType': _type,
        'from': _from.toIso8601String(),
        'to': _to.toIso8601String(),
      },
    );
    if (mounted) showAppSnack(context, 'تم إرسال طلب السجلات.');
  }

  Future<void> _clearLogs() async {
    final ok = await confirmAction(
      context,
      title: 'حذف السجلات من السحابة',
      message:
          'سيتم حذف النتائج المطلوبة من Firebase فقط، وليس السجلات المحلية داخل الكمبيوتر.',
      danger: true,
      confirmLabel: 'حذف',
    );
    if (!ok || !mounted) return;
    await context.read<DeviceRepository>().clearRequestedLogs(widget.device.id);
    if (mounted) showAppSnack(context, 'تم حذف سجلات السحابة.');
  }

  String? _pathFromLog(LogEntry log) {
    final candidates = [
      log.target,
      log.payload['path'],
      log.payload['openedPath'],
      log.payload['filePath'],
      log.payload['appPath'],
      log.payload['from'],
      log.payload['to'],
    ];
    for (final value in candidates) {
      final text = (value ?? '').toString().trim();
      if (text.contains(r':\') || text.startsWith(r'\\')) return text;
    }
    return null;
  }

  String? _appFromLog(LogEntry log) {
    final candidates = [
      log.payload['appName'],
      log.payload['processName'],
      log.payload['target'],
      log.target,
    ];
    for (final value in candidates) {
      final text = (value ?? '').toString().trim();
      if (text.toLowerCase().endsWith('.exe') ||
          text.toLowerCase().contains('chrome') ||
          text.toLowerCase().contains('edge')) {
        return text;
      }
    }
    return null;
  }

  String? _siteFromLog(LogEntry log) {
    final candidates = [
      log.payload['domain'],
      log.payload['url'],
      log.payload['siteName'],
      log.target,
    ];
    for (final value in candidates) {
      var text = (value ?? '').toString().trim();
      if (text.startsWith('http://') || text.startsWith('https://')) {
        text = Uri.tryParse(text)?.host ?? text;
      }
      if (text.contains('.') && !text.contains(r':\')) return text;
    }
    return null;
  }

  Future<void> _sendLogCommand(
    CommandType type,
    Map<String, dynamic> payload,
    String message,
  ) async {
    await context.read<DeviceRepository>().sendCommand(
          userId: widget.userId,
          deviceId: widget.device.id,
          type: type,
          payload: payload,
        );
    if (mounted) showAppSnack(context, message);
  }

  Future<void> _blockPathFromLog(LogEntry log) async {
    final path = _pathFromLog(log);
    if (path == null) return;
    final ok = await confirmAction(
      context,
      title: 'منع فتح المسار',
      message: 'سيتم منع فتح هذا المسار على ${widget.device.name}:\n$path',
      danger: true,
      confirmLabel: 'منع',
    );
    if (!ok || !mounted) return;
    final now = DateTime.now();
    await context.read<DeviceRepository>().savePathRule(
          userId: widget.userId,
          deviceId: widget.device.id,
          rule: PathRule(
            id: const Uuid().v4(),
            path: path,
            lockType: 'blocked',
            blockOpen: true,
            blockDelete: true,
            blockCopy: true,
            blockMove: true,
            blockRename: true,
            blockModify: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
    if (mounted) showAppSnack(context, 'تم إرسال قاعدة منع فتح المسار.');
  }

  void _showLogDetails(LogEntry log) {
    final path = _pathFromLog(log);
    final app = _appFromLog(log);
    final site = _siteFromLog(log);
    final payload = _prettyPayload(log.payload);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  log.message,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                _DetailLine(label: 'النوع', value: log.type),
                _DetailLine(
                  label: 'الوقت',
                  value: AppFormatters.dateTime(log.createdAt),
                ),
                if ((log.target ?? '').isNotEmpty)
                  _DetailLine(label: 'الهدف', value: log.target!),
                if (path != null) _DetailLine(label: 'المسار', value: path),
                const SizedBox(height: 12),
                SelectableText(
                  payload,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (path != null || app != null || site != null) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (path != null)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _sendLogCommand(
                              CommandType.openPath,
                              {'path': path},
                              'تم إرسال أمر فتح المسار.',
                            );
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('فتح المسار'),
                        ),
                      if (path != null)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _blockPathFromLog(log);
                          },
                          icon: const Icon(Icons.block_outlined),
                          label: const Text('منع المسار'),
                        ),
                      if (app != null)
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _sendLogCommand(
                              CommandType.blockApplication,
                              {'target': app, 'appName': app},
                              'تم إرسال أمر منع التطبيق.',
                            );
                          },
                          icon: const Icon(Icons.app_blocking_outlined),
                          label: const Text('منع التطبيق'),
                        ),
                      if (app != null)
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _sendLogCommand(
                              CommandType.closeApplicationAfterDelay,
                              {'target': app, 'delayMinutes': 30},
                              'تمت جدولة إغلاق التطبيق بعد 30 دقيقة.',
                            );
                          },
                          icon: const Icon(Icons.schedule_outlined),
                          label: const Text('جدولة إغلاق'),
                        ),
                      if (site != null)
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _sendLogCommand(
                              CommandType.blockWebsite,
                              {'domain': site, 'target': site},
                              'تم إرسال أمر منع الموقع.',
                            );
                          },
                          icon: const Icon(Icons.public_off_outlined),
                          label: const Text('منع الموقع'),
                        ),
                      if (site != null)
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _sendLogCommand(
                              CommandType.allowWebsite,
                              {
                                'domain': site,
                                'target': site,
                                'durationSeconds': 1800,
                              },
                              'تم إرسال سماح للموقع لمدة 30 دقيقة.',
                            );
                          },
                          icon: const Icon(Icons.lock_open_outlined),
                          label: const Text('سماح 30 د'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _prettyPayload(Map<String, dynamic> payload) {
    if (payload.isEmpty) return 'لا توجد بيانات إضافية.';
    try {
      return const JsonEncoder.withIndent('  ').convert(payload);
    } catch (_) {
      return payload.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DeviceRepository>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('السجلات'),
        actions: [
          IconButton(
              onPressed: _clearLogs,
              icon: const Icon(Icons.delete_sweep_outlined)),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _type,
                    decoration: const InputDecoration(
                        labelText: 'نوع السجل', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('كل السجلات')),
                      DropdownMenuItem(
                          value: 'file_opened',
                          child: Text('الملفات المفتوحة')),
                      DropdownMenuItem(
                          value: 'app_activity',
                          child: Text('التطبيقات المفتوحة')),
                      DropdownMenuItem(
                          value: 'path_activity',
                          child: Text('المسارات المفتوحة')),
                      DropdownMenuItem(
                          value: 'file_deleted',
                          child: Text('الملفات المحذوفة')),
                      DropdownMenuItem(
                          value: 'protected_path_attempt',
                          child: Text('محاولات فتح مسارات مقفلة')),
                      DropdownMenuItem(
                          value: 'install_attempt',
                          child: Text('محاولات التثبيت')),
                      DropdownMenuItem(
                          value: 'command', child: Text('أوامر الهاتف')),
                      DropdownMenuItem(
                          value: 'error', child: Text('أخطاء التطبيق')),
                    ],
                    onChanged: (value) =>
                        setState(() => _type = value ?? 'all'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDateTime(start: true),
                          icon: const Icon(Icons.access_time),
                          label: Text('من ${AppFormatters.dateTime(_from)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDateTime(start: false),
                          icon: const Icon(Icons.event_available_outlined),
                          label: Text('إلى ${AppFormatters.dateTime(_to)}'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _requestLogs,
                        icon: const Icon(Icons.download),
                        label: const Text('طلب'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<LogEntry>>(
              stream: repo.watchRequestedLogs(widget.device.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final logs = snapshot.data!;
                if (logs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'لا توجد نتائج سجلات',
                    subtitle: 'اختر النوع والفترة ثم اضغط طلب.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                            child: Icon(Icons.article_outlined)),
                        title: Text(log.message),
                        subtitle: Text(
                            '${log.type} • ${log.target ?? ''}\n${AppFormatters.dateTime(log.createdAt)}'),
                        isThreeLine: true,
                        onTap: () => _showLogDetails(log),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
