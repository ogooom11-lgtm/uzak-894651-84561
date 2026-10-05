import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/app_formatters.dart';
import '../core/command_type.dart';
import '../models/path_rule.dart';
import '../models/pc_device.dart';
import '../models/remote_file_item.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';

class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen(
      {super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  RemoteFileListing? _listing;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load('roots');
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await context.read<DeviceRepository>().browsePath(
            userId: widget.userId,
            deviceId: widget.device.id,
            path: path,
          );
      if (!mounted) return;
      setState(() => _listing = listing);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runAction(
    CommandType type,
    RemoteFileItem item, {
    Map<String, dynamic> payload = const {},
    bool danger = false,
    bool reload = true,
  }) async {
    if (danger) {
      final ok = await confirmAction(
        context,
        title: type.arabicTitle,
        message: 'تنفيذ الأمر على:\n${item.path}',
        danger: true,
        confirmLabel: 'تنفيذ',
      );
      if (!ok || !mounted) return;
    }
    final response = await context.read<DeviceRepository>().runFileCommand(
          userId: widget.userId,
          deviceId: widget.device.id,
          type: type,
          path: item.path,
          payload: payload,
        );
    if (!mounted) return;
    showAppSnack(context, response?.message ?? 'تم إرسال الأمر.');
    if (reload && _listing != null) unawaitedLoad(_listing!.path);
  }

  void unawaitedLoad(String path) {
    Future<void>.delayed(const Duration(milliseconds: 400), () => _load(path));
  }

  Future<String?> _askText(String title, String label,
      {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('متابعة')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return null;
    return result;
  }

  Future<String?> _pickDestination(String title) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DestinationPickerSheet(
        title: title,
        userId: widget.userId,
        deviceId: widget.device.id,
      ),
    );
  }

  Future<void> _protectPath(RemoteFileItem item) async {
    final now = DateTime.now();
    await context.read<DeviceRepository>().savePathRule(
          userId: widget.userId,
          deviceId: widget.device.id,
          rule: PathRule(
            id: const Uuid().v4(),
            path: item.path,
            lockType: 'permissionRequired',
            blockOpen: true,
            blockDelete: true,
            blockCopy: true,
            blockMove: true,
            blockRename: true,
            blockModify: true,
            permissionEveryTime: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
    if (mounted) showAppSnack(context, 'تم إرسال قاعدة حماية للمسار.');
  }

  Future<void> _showActions(RemoteFileItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            ListTile(
              leading: Icon(_iconFor(item)),
              title:
                  Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle:
                  Text(item.path, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const Divider(),
            _ActionRow(
              icon: Icons.open_in_new,
              label: item.isDirectory ? 'الدخول للمسار' : 'فتح على الكمبيوتر',
              onTap: () {
                Navigator.pop(context);
                item.isDirectory
                    ? _load(item.path)
                    : _runAction(CommandType.openPath, item, reload: false);
              },
            ),
            if (!item.isDirectory)
              _ActionRow(
                icon: Icons.bluetooth_searching,
                label: 'إرسال عبر Bluetooth',
                onTap: () {
                  Navigator.pop(context);
                  _runAction(CommandType.sendBluetoothFile, item,
                      payload: {'path': item.path}, reload: false);
                },
              ),
            _ActionRow(
              icon: Icons.drive_file_rename_outline,
              label: 'إعادة تسمية',
              onTap: () async {
                Navigator.pop(context);
                final name = await _askText('إعادة تسمية', 'الاسم الجديد',
                    initial: item.name);
                if (name != null) {
                  await _runAction(CommandType.renamePath, item,
                      payload: {'newName': name});
                }
              },
            ),
            _ActionRow(
              icon: Icons.copy_all_outlined,
              label: 'نسخ إلى...',
              onTap: () async {
                Navigator.pop(context);
                final destination = await _pickDestination('اختيار مكان النسخ');
                if (destination != null) {
                  await _runAction(CommandType.copyPath, item,
                      payload: {'destination': destination});
                }
              },
            ),
            _ActionRow(
              icon: Icons.drive_file_move_outline,
              label: 'نقل إلى...',
              onTap: () async {
                Navigator.pop(context);
                final destination = await _pickDestination('اختيار مكان النقل');
                if (destination != null) {
                  await _runAction(CommandType.movePath, item,
                      payload: {'destination': destination}, danger: true);
                }
              },
            ),
            _ActionRow(
              icon: item.isHidden
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              label: item.isHidden ? 'إظهار' : 'إخفاء',
              onTap: () {
                Navigator.pop(context);
                _runAction(
                    item.isHidden
                        ? CommandType.unhidePath
                        : CommandType.hidePath,
                    item);
              },
            ),
            _ActionRow(
              icon: Icons.lock_outline,
              label: 'قفل المسار وطلب إذن من الهاتف',
              onTap: () {
                Navigator.pop(context);
                _protectPath(item);
              },
            ),
            const Divider(),
            _ActionRow(
              icon: Icons.delete_outline,
              label: 'نقل إلى سلة المحذوفات',
              danger: true,
              onTap: () {
                Navigator.pop(context);
                _runAction(CommandType.deletePath, item, danger: true);
              },
            ),
            _ActionRow(
              icon: Icons.delete_forever_outlined,
              label: 'حذف نهائي',
              danger: true,
              onTap: () {
                Navigator.pop(context);
                _runAction(CommandType.deletePath, item,
                    payload: {'permanent': true}, danger: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الملفات'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed:
                listing == null || _loading ? null : () => _load(listing.path),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _PathHeader(
            path: listing?.path ?? 'roots',
            parentPath: listing?.parentPath,
            loading: _loading,
            onOpen: _load,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (listing?.truncated == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('تم عرض جزء من الملفات فقط'),
                  subtitle: Text(
                    'للحفاظ على سرعة الكمبيوتر تم إظهار أول ${listing?.limit ?? listing?.items.length} عنصر.',
                  ),
                ),
              ),
            ),
          Expanded(
            child: _loading && listing == null
                ? const Center(child: CircularProgressIndicator())
                : listing == null || listing.items.isEmpty
                    ? const EmptyState(
                        icon: Icons.folder_off_outlined,
                        title: 'لا توجد ملفات',
                        subtitle: 'اختر مساراً أو اضغط تحديث.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: listing.items.length,
                        itemBuilder: (context, index) {
                          final item = listing.items[index];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                child: Icon(_iconFor(item)),
                              ),
                              title: Text(item.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                item.isDirectory
                                    ? item.path
                                    : '${item.extension.toUpperCase()} • ${AppFormatters.fileSize(item.size)} • ${AppFormatters.dateTime(item.modifiedAt)}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.more_vert),
                              onTap: () => item.isDirectory
                                  ? _load(item.path)
                                  : _showActions(item),
                              onLongPress: () => _showActions(item),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(RemoteFileItem item) {
    if (item.isDrive) return Icons.storage;
    if (item.isDirectory) return Icons.folder_rounded;
    switch (item.extension) {
      case 'exe':
        return Icons.apps;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
        return Icons.image_outlined;
      case 'mp4':
      case 'mkv':
      case 'avi':
        return Icons.movie_outlined;
      case 'mp3':
      case 'wav':
        return Icons.music_note;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}

class _DestinationPickerSheet extends StatefulWidget {
  const _DestinationPickerSheet({
    required this.title,
    required this.userId,
    required this.deviceId,
  });

  final String title;
  final String userId;
  final String deviceId;

  @override
  State<_DestinationPickerSheet> createState() =>
      _DestinationPickerSheetState();
}

class _DestinationPickerSheetState extends State<_DestinationPickerSheet> {
  RemoteFileListing? _listing;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load('roots');
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await context.read<DeviceRepository>().browsePath(
            userId: widget.userId,
            deviceId: widget.deviceId,
            path: path,
          );
      if (!mounted) return;
      setState(() => _listing = listing);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;
    final directories =
        listing?.items.where((item) => item.isDirectory).toList() ??
            const <RemoteFileItem>[];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            _PathHeader(
              path: listing?.path ?? 'roots',
              parentPath: listing?.parentPath,
              loading: _loading,
              onOpen: _load,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: _loading && listing == null
                  ? const Center(child: CircularProgressIndicator())
                  : directories.isEmpty
                      ? const EmptyState(
                          icon: Icons.folder_off_outlined,
                          title: 'لا توجد مجلدات هنا',
                          subtitle: 'ارجع أو اختر المجلد الحالي.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          itemCount: directories.length,
                          itemBuilder: (context, index) {
                            final item = directories[index];
                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  item.isDrive
                                      ? Icons.storage
                                      : Icons.folder_rounded,
                                ),
                                title: Text(item.name),
                                subtitle: Text(
                                  item.path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () => _load(item.path),
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: listing == null || listing.path == 'roots'
                      ? null
                      : () => Navigator.pop(context, listing.path),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('اختيار هذا المجلد'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PathHeader extends StatelessWidget {
  const _PathHeader({
    required this.path,
    required this.parentPath,
    required this.loading,
    required this.onOpen,
  });

  final String path;
  final String? parentPath;
  final bool loading;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'رجوع',
                  onPressed: parentPath == null || loading
                      ? null
                      : () => onOpen(parentPath!),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SelectableText(
                    path == 'roots' ? 'الأقراص' : path,
                    maxLines: 2,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (loading)
                  const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                    label: const Text('الأقراص'),
                    avatar: const Icon(Icons.storage),
                    onPressed: () => onOpen('roots')),
                ActionChip(
                    label: const Text('سطح المكتب'),
                    avatar: const Icon(Icons.desktop_windows),
                    onPressed: () => onOpen('desktop')),
                ActionChip(
                    label: const Text('التنزيلات'),
                    avatar: const Icon(Icons.download),
                    onPressed: () => onOpen('downloads')),
                ActionChip(
                    label: const Text('المستندات'),
                    avatar: const Icon(Icons.description),
                    onPressed: () => onOpen('documents')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Theme.of(context).colorScheme.error : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }
}
