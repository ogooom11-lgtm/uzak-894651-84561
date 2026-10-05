import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/command_type.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';

class SchedulerScreen extends StatefulWidget {
  const SchedulerScreen({super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  @override
  State<SchedulerScreen> createState() => _SchedulerScreenState();
}

class _SchedulerScreenState extends State<SchedulerScreen> {
  _ScheduledAction _selected = _scheduledActions.first;
  String _presetMode = 'study';
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.fromDateTime(
    DateTime.now().add(const Duration(minutes: 15)),
  );
  bool _sending = false;

  DateTime get _executeAt => DateTime(
        _date.year,
        _date.month,
        _date.day,
        _time.hour,
        _time.minute,
      );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
      initialDate: _date.isBefore(now) ? now : _date,
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null) return;
    setState(() => _time = picked);
  }

  Future<void> _schedule() async {
    final executeAt = _executeAt;
    if (executeAt.isBefore(DateTime.now().add(const Duration(seconds: 20)))) {
      showAppSnack(context, 'اختر وقتاً بعد 20 ثانية على الأقل.', error: true);
      return;
    }

    setState(() => _sending = true);
    try {
      final payload = <String, dynamic>{..._selected.payload};
      if (_selected.type == CommandType.applyPresetMode) {
        payload['mode'] = _presetMode;
      }
      final repo = context.read<DeviceRepository>();
      final commandId = await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: _selected.type,
        payload: payload,
        executeAt: executeAt,
      );
      if (mounted) {
        showAppSnack(
          context,
          'تمت جدولة ${_selected.title} في ${MaterialLocalizations.of(context).formatShortDate(executeAt)} ${_time.format(context)}',
          actionLabel: 'إلغاء',
          onAction: () async {
            await repo.cancelCommand(
              deviceId: widget.device.id,
              commandId: commandId,
            );
            if (context.mounted) showAppSnack(context, 'تم إلغاء الأمر المجدول.');
          },
        );
      }
    } catch (e) {
      if (mounted) showAppSnack(context, 'تعذر الجدولة: $e', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('جدولة الأوامر')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.event_available_rounded, color: Colors.white, size: 42),
                SizedBox(height: 12),
                Text(
                  'جدولة ذكية',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'اختر الأمر والوقت، وسيبقى Pending حتى يحين موعد التنفيذ على الكمبيوتر.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<_ScheduledAction>(
                    value: _selected,
                    decoration: const InputDecoration(
                      labelText: 'الأمر',
                      prefixIcon: Icon(Icons.bolt_rounded),
                    ),
                    items: [
                      for (final action in _scheduledActions)
                        DropdownMenuItem(
                          value: action,
                          child: Text(action.title),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _selected = value);
                    },
                  ),
                  if (_selected.type == CommandType.applyPresetMode) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _presetMode,
                      decoration: const InputDecoration(
                        labelText: 'الوضع',
                        prefixIcon: Icon(Icons.auto_awesome_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'study', child: Text('الدراسة')),
                        DropdownMenuItem(value: 'work', child: Text('العمل')),
                        DropdownMenuItem(value: 'kids', child: Text('الأطفال')),
                        DropdownMenuItem(
                          value: 'protection',
                          child: Text('الحماية القصوى'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _presetMode = value);
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.calendar_month_rounded),
                          label: Text(
                            MaterialLocalizations.of(context)
                                .formatShortDate(_date),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickTime,
                          icon: const Icon(Icons.schedule_rounded),
                          label: Text(_time.format(context)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _sending ? null : _schedule,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_time_extension_rounded),
                    label: Text(_sending ? 'جاري الجدولة...' : 'جدولة الأمر'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'ملاحظة: أوامر الإغلاق وإيقاف الإنترنت ستنفذ مباشرة عند الموعد المختار بدون تأكيد إضافي.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _ScheduledAction {
  const _ScheduledAction(this.title, this.type, [this.payload = const {}]);

  final String title;
  final CommandType type;
  final Map<String, dynamic> payload;
}

const _scheduledActions = [
  _ScheduledAction('لقطة شاشة', CommandType.requestScreenshot),
  _ScheduledAction('فحص الاتصال', CommandType.checkConnection),
  _ScheduledAction('قفل الشاشة', CommandType.lockScreen),
  _ScheduledAction('وضع جاهز', CommandType.applyPresetMode),
  _ScheduledAction('وضع الطوارئ', CommandType.emergencyMode),
  _ScheduledAction('تشغيل وضع الخصوصية', CommandType.privacyMode, {'enabled': true}),
  _ScheduledAction('إيقاف وضع الخصوصية', CommandType.privacyMode, {'enabled': false}),
  _ScheduledAction('تشغيل WiFi', CommandType.wifiOn),
  _ScheduledAction('فصل WiFi', CommandType.wifiOff),
  _ScheduledAction('تشغيل الإنترنت', CommandType.internetOn),
  _ScheduledAction('إيقاف الإنترنت نهائياً', CommandType.internetOffPermanent),
  _ScheduledAction('إغلاق الكمبيوتر', CommandType.shutdownPc),
  _ScheduledAction('إعادة تشغيل الكمبيوتر', CommandType.restartPc),
];
