import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/path_rule.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';

class ProtectionScreen extends StatelessWidget {
  const ProtectionScreen(
      {super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  Future<void> _openRuleForm(BuildContext context, {PathRule? existing}) async {
    final rule = await showModalBottomSheet<PathRule>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PathRuleForm(existing: existing),
    );
    if (rule == null || !context.mounted) return;
    await context.read<DeviceRepository>().savePathRule(
          userId: userId,
          deviceId: device.id,
          rule: rule,
        );
    if (context.mounted) {
      showAppSnack(
          context,
          existing == null
              ? 'تم إرسال قاعدة الحماية إلى الكمبيوتر.'
              : 'تم تعديل القاعدة وإرسالها إلى الكمبيوتر.');
    }
  }

  Future<void> _deleteRule(BuildContext context, PathRule rule) async {
    final ok = await confirmAction(
      context,
      title: 'حذف قاعدة الحماية',
      message: 'هل تريد حذف قاعدة حماية المسار: ${rule.path}؟',
      danger: true,
      confirmLabel: 'حذف',
    );
    if (!ok || !context.mounted) return;
    await context.read<DeviceRepository>().removePathRule(
          userId: userId,
          deviceId: device.id,
          ruleId: rule.id,
        );
    if (context.mounted) showAppSnack(context, 'تم حذف القاعدة وإرسال الأمر.');
  }

  String _lockLabel(String value) {
    switch (value) {
      case 'blocked':
      case 'full_lock':
        return 'قفل كامل / منع الفتح';
      case 'password':
        return 'كلمة مرور';
      case 'permissionRequired':
      case 'permission_required':
        return 'طلب إذن من الهاتف';
      case 'read_only':
        return 'قراءة فقط';
      default:
        return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DeviceRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('حماية المسارات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openRuleForm(context),
        icon: const Icon(Icons.add),
        label: const Text('إضافة مسار'),
      ),
      body: StreamBuilder<List<PathRule>>(
        stream: repo.watchPathRules(device.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rules = snapshot.data!;
          if (rules.isEmpty) {
            return const EmptyState(
              icon: Icons.folder_off_outlined,
              title: 'لا توجد قواعد حماية',
              subtitle: 'أضف مساراً وحدد صلاحيات الحماية المطلوبة.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 92),
            itemCount: rules.length,
            itemBuilder: (context, index) {
              final rule = rules[index];
              final permissions = [
                _lockLabel(rule.lockType),
                if (rule.blockOpen) 'منع الفتح',
                if (rule.blockDelete) 'منع الحذف',
                if (rule.blockCopy) 'منع النسخ',
                if (rule.blockMove) 'منع القص',
                if (rule.blockRename) 'منع إعادة التسمية',
                if (rule.blockModify) 'منع التعديل',
                if (rule.readOnly) 'قراءة فقط',
                if (rule.permissionEveryTime) 'طلب إذن كل مرة',
              ];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      ListTile(
                        leading:
                            const CircleAvatar(child: Icon(Icons.lock_outline)),
                        title: Text(rule.path,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(permissions.join(' • ')),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _openRuleForm(context, existing: rule),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('تعديل'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _deleteRule(context, rule),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('حذف'),
                            ),
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

class _PathRuleForm extends StatefulWidget {
  const _PathRuleForm({this.existing});

  final PathRule? existing;

  @override
  State<_PathRuleForm> createState() => _PathRuleFormState();
}

class _PathRuleFormState extends State<_PathRuleForm> {
  late final TextEditingController _pathController;
  late final TextEditingController _passwordController;
  late String _lockType;
  late bool _blockOpen;
  late bool _blockDelete;
  late bool _blockCopy;
  late bool _blockMove;
  late bool _blockRename;
  late bool _blockModify;
  late bool _readOnly;
  late bool _permissionEveryTime;

  @override
  void initState() {
    super.initState();
    final rule = widget.existing;
    _pathController = TextEditingController(text: rule?.path ?? r'D:\Private');
    _passwordController = TextEditingController(text: rule?.password ?? '');
    _lockType = _normalizeLockType(rule?.lockType ?? 'permissionRequired');
    _blockOpen = rule?.blockOpen ?? true;
    _blockDelete = rule?.blockDelete ?? true;
    _blockCopy = rule?.blockCopy ?? true;
    _blockMove = rule?.blockMove ?? true;
    _blockRename = rule?.blockRename ?? true;
    _blockModify = rule?.blockModify ?? true;
    _readOnly = rule?.readOnly ?? false;
    _permissionEveryTime = rule?.permissionEveryTime ?? true;
  }

  String _normalizeLockType(String value) {
    if (value == 'permission_required') return 'permissionRequired';
    if (value == 'full_lock') return 'blocked';
    return value;
  }

  @override
  void dispose() {
    _pathController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _save() {
    final path = _pathController.text.trim();
    if (path.isEmpty) return;
    final now = DateTime.now();
    final existing = widget.existing;
    Navigator.pop(
      context,
      PathRule(
        id: existing?.id ?? const Uuid().v4(),
        path: path,
        lockType: _lockType,
        blockOpen: _blockOpen,
        blockDelete: _blockDelete,
        blockCopy: _blockCopy,
        blockMove: _blockMove,
        blockRename: _blockRename,
        blockModify: _blockModify,
        readOnly: _readOnly,
        permissionEveryTime: _permissionEveryTime,
        password:
            _lockType == 'password' ? _passwordController.text.trim() : null,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEdit ? 'تعديل قاعدة حماية' : 'إضافة قاعدة حماية',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _pathController,
                decoration: const InputDecoration(
                  labelText: 'المسار',
                  hintText: r'D:\Private',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _lockType,
                decoration: const InputDecoration(
                    labelText: 'نوع القفل', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(
                      value: 'permissionRequired',
                      child: Text('طلب إذن من الهاتف')),
                  DropdownMenuItem(value: 'password', child: Text('كلمة مرور')),
                  DropdownMenuItem(
                      value: 'blocked', child: Text('قفل كامل / منع الفتح')),
                  DropdownMenuItem(
                      value: 'read_only', child: Text('قراءة فقط')),
                ],
                onChanged: (value) =>
                    setState(() => _lockType = value ?? _lockType),
              ),
              if (_lockType == 'password') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _SwitchRow(
                  title: 'منع الفتح',
                  value: _blockOpen,
                  onChanged: (v) => setState(() => _blockOpen = v)),
              _SwitchRow(
                  title: 'منع الحذف',
                  value: _blockDelete,
                  onChanged: (v) => setState(() => _blockDelete = v)),
              _SwitchRow(
                  title: 'منع النسخ',
                  value: _blockCopy,
                  onChanged: (v) => setState(() => _blockCopy = v)),
              _SwitchRow(
                  title: 'منع القص/النقل',
                  value: _blockMove,
                  onChanged: (v) => setState(() => _blockMove = v)),
              _SwitchRow(
                  title: 'منع إعادة التسمية',
                  value: _blockRename,
                  onChanged: (v) => setState(() => _blockRename = v)),
              _SwitchRow(
                  title: 'منع التعديل',
                  value: _blockModify,
                  onChanged: (v) => setState(() => _blockModify = v)),
              _SwitchRow(
                  title: 'قراءة فقط',
                  value: _readOnly,
                  onChanged: (v) => setState(() => _readOnly = v)),
              _SwitchRow(
                  title: 'طلب إذن كل مرة',
                  value: _permissionEveryTime,
                  onChanged: (v) => setState(() => _permissionEveryTime = v)),
              const SizedBox(height: 12),
              FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: Text(isEdit ? 'حفظ التعديل' : 'حفظ القاعدة')),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow(
      {required this.title, required this.value, required this.onChanged});

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text(title),
    );
  }
}
