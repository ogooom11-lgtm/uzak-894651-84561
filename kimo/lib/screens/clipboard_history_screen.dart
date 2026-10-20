import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/command_type.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../services/lan_device_client.dart';
import '../services/lan_discovery_service.dart';
import '../widgets/app_snack.dart';
import '../widgets/empty_state.dart';

class ClipboardHistoryScreen extends StatefulWidget {
  const ClipboardHistoryScreen({
    super.key,
    required this.userId,
    required this.device,
  });

  final String userId;
  final PcDevice device;

  @override
  State<ClipboardHistoryScreen> createState() => _ClipboardHistoryScreenState();
}

class _ClipboardHistoryScreenState extends State<ClipboardHistoryScreen> {
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);

    // 1. Try direct LAN first
    final lanInfo = LanDiscoveryService.instance.getDevice(widget.device.id);
    if (lanInfo != null && lanInfo.isFresh) {
      try {
        final client = LanDeviceClient(host: lanInfo.ip, port: lanInfo.httpPort);
        final res = await client.sendCommand('get_clipboard_history', payload: {'query': _searchQuery});
        if (res['payload'] is Map && res['payload']['items'] is List) {
          final list = (res['payload']['items'] as List).cast<Map<String, dynamic>>();
          setState(() {
            _items = list;
            _loading = false;
          });
          client.dispose();
          return;
        }
        client.dispose();
      } catch (_) {}
    }

    // 2. Fallback via DeviceRepository
    try {
      final repo = context.read<DeviceRepository>();
      final cmdId = await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: CommandType.getClipboard,
        payload: {'query': _searchQuery, 'action': 'history'},
      );

      final resp = await repo.waitForCommandResponse(
        deviceId: widget.device.id,
        commandId: cmdId,
        timeout: const Duration(seconds: 8),
      );

      if (resp != null && resp.payload['items'] is List) {
        final list = (resp.payload['items'] as List).cast<Map<String, dynamic>>();
        setState(() {
          _items = list;
          _loading = false;
        });
        return;
      }
    } catch (_) {}

    setState(() => _loading = false);
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح سجل الحافظة'),
        content: const Text('هل أنت متأكد من رغبتك في مسح كافة عناصر سجل الحافظة المسجلة من الكمبيوتر؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مسح الكل')),
        ],
      ),
    );

    if (confirmed != true) return;

    final repo = context.read<DeviceRepository>();
    await repo.sendCommand(
      userId: widget.userId,
      deviceId: widget.device.id,
      type: CommandType.checkConnection,
      payload: {'action': 'clear_clipboard_history'},
    );

    setState(() => _items = []);
    if (mounted) showAppSnack(context, 'تم مسح سجل الحافظة بالكامل.');
  }

  void _copyToPhone(String text) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    showAppSnack(context, 'تم نسخ النص إلى حافظة الهاتف 📋');
  }

  Future<void> _setPcClipboard(String text) async {
    final repo = context.read<DeviceRepository>();
    await repo.sendCommand(
      userId: widget.userId,
      deviceId: widget.device.id,
      type: CommandType.setClipboard,
      payload: {'text': text},
    );
    if (mounted) showAppSnack(context, 'تم تعيين النص في حافظة الكمبيوتر 💻');
  }

  IconData _appIcon(String appName) {
    final lower = appName.toLowerCase();
    if (lower.contains('chrome') || lower.contains('edge') || lower.contains('browser') || lower.contains('brave') || lower.contains('firefox')) {
      return Icons.public_rounded;
    } else if (lower.contains('word') || lower.contains('winword') || lower.contains('doc')) {
      return Icons.description_rounded;
    } else if (lower.contains('excel') || lower.contains('calc') || lower.contains('sheet')) {
      return Icons.table_chart_rounded;
    } else if (lower.contains('notepad') || lower.contains('code') || lower.contains('text')) {
      return Icons.edit_note_rounded;
    } else if (lower.contains('explorer') || lower.contains('folder')) {
      return Icons.folder_rounded;
    }
    return Icons.content_paste_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الحافظة الذكي (Clipboard)'),
        actions: [
          IconButton(
            tooltip: 'تحديث السجل',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadHistory,
          ),
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'مسح السجل',
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: _clearHistory,
            ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'بحث في محتوى الحافظة أو اسم التطبيق...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          setState(() => _searchQuery = '');
                          _loadHistory();
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) {
                _searchQuery = val;
              },
              onSubmitted: (_) => _loadHistory(),
            ),
          ),

          // Main Content List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const EmptyState(
                        title: 'لا يوجد عناصر مسجلة في الحافظة',
                        subtitle: 'أي عملية نسخ (Ctrl+C) تتم في الكمبيوتر سيتم تسجيلها وحفظ مسارها وتطبيقها تلقائياً هنا.',
                        icon: Icons.history_edu_rounded,
                      )
                    : RefreshIndicator(
                        onRefresh: _loadHistory,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _items.length,
                          itemBuilder: (ctx, idx) {
                            final item = _items[idx];
                            final content = (item['content'] ?? '').toString();
                            final sourceApp = (item['sourceApp'] ?? '').toString();
                            final sourceAppName = (item['sourceAppName'] ?? sourceApp).toString();
                            final sourceTitle = (item['sourceTitle'] ?? '').toString();
                            final sourcePath = (item['sourcePath'] ?? '').toString();
                            final createdAt = (item['createdAt'] ?? '').toString();

                            String timeDisplay = '';
                            if (createdAt.isNotEmpty) {
                              final dt = DateTime.tryParse(createdAt);
                              if (dt != null) {
                                timeDisplay = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
                              }
                            }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header: App name, Icon, and Timestamp
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: cs.primaryContainer,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            _appIcon(sourceApp.isNotEmpty ? sourceApp : sourceAppName),
                                            size: 18,
                                            color: cs.onPrimaryContainer,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                sourceAppName.isNotEmpty ? sourceAppName : (sourceApp.isNotEmpty ? sourceApp : 'تطبيق غير محدد'),
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (sourceTitle.isNotEmpty)
                                                Text(
                                                  sourceTitle,
                                                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (timeDisplay.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: cs.surfaceContainerHighest,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              timeDisplay,
                                              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                                            ),
                                          ),
                                      ],
                                    ),

                                    // Source Path if present
                                    if (sourcePath.isNotEmpty && sourcePath != sourceApp) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.place_outlined, size: 13, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                sourcePath,
                                                style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],

                                    const SizedBox(height: 8),

                                    // Content Text Box
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: cs.surface,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                                      ),
                                      child: SelectableText(
                                        content,
                                        style: const TextStyle(fontSize: 12.5),
                                        maxLines: 6,
                                      ),
                                    ),

                                    const SizedBox(height: 8),

                                    // Bottom Action Buttons
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(Icons.copy_rounded, size: 15),
                                          label: const Text('نسخ للهاتف', style: TextStyle(fontSize: 11)),
                                          onPressed: () => _copyToPhone(content),
                                        ),
                                        const SizedBox(width: 4),
                                        FilledButton.tonalIcon(
                                          icon: const Icon(Icons.send_to_mobile_rounded, size: 15),
                                          label: const Text('تعيين بالكمبيوتر', style: TextStyle(fontSize: 11)),
                                          onPressed: () => _setPcClipboard(content),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
