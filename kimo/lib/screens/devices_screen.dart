import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_formatters.dart';
import '../core/command_type.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_chip.dart';
import 'device_details_screen.dart';
import 'pairing_screen.dart';
import 'settings_screen.dart';

enum _ConnectionUiState { checking, online, offline }

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.userId});

  final String userId;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final Map<String, _ConnectionUiState> _states = {};
  final Map<String, String> _messages = {};
  final Set<String> _checkingIds = {};
  String _query = '';

  Future<void> _checkConnection(BuildContext context, PcDevice device) async {
    if (_checkingIds.contains(device.id)) return;

    final repo = context.read<DeviceRepository>();
    setState(() {
      _states[device.id] = _ConnectionUiState.checking;
      _messages[device.id] = 'جاري التحقق...';
      _checkingIds.add(device.id);
    });

    try {
      final commandId = await repo.sendCommand(
        userId: widget.userId,
        deviceId: device.id,
        type: CommandType.checkConnection,
        payload: {'timeoutSeconds': 10},
      );

      if (context.mounted) {
        showAppSnack(context, 'جاري التحقق من اتصال ${device.name}...');
      }

      final response = await repo.waitForCommandResponse(
        deviceId: device.id,
        commandId: commandId,
        timeout: const Duration(seconds: 10),
      );

      if (!mounted) return;
      setState(() {
        _checkingIds.remove(device.id);
        if (response == null) {
          _states[device.id] = _ConnectionUiState.offline;
          _messages[device.id] = 'لم يرد الكمبيوتر خلال 10 ثوانٍ';
        } else if (response.success) {
          _states[device.id] = _ConnectionUiState.online;
          _messages[device.id] =
              response.message.isEmpty ? 'Online' : response.message;
        } else {
          _states[device.id] = _ConnectionUiState.offline;
          _messages[device.id] = response.message.isEmpty
              ? 'فشل التحقق من الاتصال'
              : response.message;
        }
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _checkingIds.remove(device.id);
        _states[device.id] = _ConnectionUiState.offline;
        _messages[device.id] = 'لم يرد الكمبيوتر خلال 10 ثوانٍ';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkingIds.remove(device.id);
        _states[device.id] = _ConnectionUiState.offline;
        _messages[device.id] = 'تعذر إرسال أمر التحقق: $e';
      });
    }
  }

  Future<void> _quickCommand(
    BuildContext context,
    PcDevice device,
    CommandType type,
    String message,
  ) async {
    await context.read<DeviceRepository>().sendCommand(
          userId: widget.userId,
          deviceId: device.id,
          type: type,
        );
    if (context.mounted) showAppSnack(context, message);
  }

  Future<void> _removeDevice(BuildContext context, PcDevice device) async {
    final confirmed = await confirmAction(
      context,
      title: 'حذف الجهاز',
      message: 'سيتم حذف ${device.name} من تطبيق الهاتف.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!confirmed || !context.mounted) return;
    await context.read<DeviceRepository>().removeDevice(
          userId: widget.userId,
          deviceId: device.id,
        );
    if (context.mounted) showAppSnack(context, 'تم حذف الجهاز من القائمة.');
  }

  _ConnectionUiState _stateFor(PcDevice device) {
    final local = _states[device.id];
    if (local != null) return local;
    final online = device.lastCheckResponse?.toLowerCase() == 'online' ||
        device.isRecentlyOnline;
    return online ? _ConnectionUiState.online : _ConnectionUiState.offline;
  }

  String _labelFor(PcDevice device) {
    final state = _stateFor(device);
    if (state == _ConnectionUiState.checking) return 'جاري التحقق';
    if (state == _ConnectionUiState.online) return 'متصل';
    return 'غير متصل';
  }

  IconData _iconFor(PcDevice device) {
    final state = _stateFor(device);
    if (state == _ConnectionUiState.checking) return Icons.sync;
    if (state == _ConnectionUiState.online) return Icons.bolt_rounded;
    return Icons.wifi_off_rounded;
  }

  Color _colorFor(BuildContext context, PcDevice device) {
    final state = _stateFor(device);
    if (state == _ConnectionUiState.checking) {
      return Theme.of(context).colorScheme.primary;
    }
    if (state == _ConnectionUiState.online) return const Color(0xFF16A34A);
    return const Color(0xFFF97316);
  }

  void _openDevice(PcDevice device) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeviceDetailsScreen(userId: widget.userId, device: device),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DeviceRepository>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('KIOM Control'),
        actions: [
          IconButton.filledTonal(
            tooltip: 'الإعدادات',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PairingScreen(userId: widget.userId)),
        ),
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('ربط جهاز'),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              cs.primary.withValues(alpha: .16),
              cs.secondary.withValues(alpha: .08),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: StreamBuilder<List<PcDevice>>(
          stream: repo.watchDevices(widget.userId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final devices = snapshot.data ?? const <PcDevice>[];
            final query = _query.trim().toLowerCase();
            final filtered = query.isEmpty
                ? devices
                : devices.where((device) {
                    return device.name.toLowerCase().contains(query) ||
                        device.id.toLowerCase().contains(query) ||
                        device.os.toLowerCase().contains(query);
                  }).toList();
            final onlineCount = devices
                .where((device) => _stateFor(device) == _ConnectionUiState.online)
                .length;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 100, 16, 110),
              children: [
                _DashboardHeader(
                  deviceCount: devices.length,
                  onlineCount: onlineCount,
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'ابحث عن جهاز أو معرف...',
                  ),
                ),
                const SizedBox(height: 12),
                if (devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 28),
                    child: EmptyState(
                      icon: Icons.devices_other_rounded,
                      title: 'لا توجد أجهزة مرتبطة بعد',
                      subtitle: 'اضغط زر ربط جهاز وامسح QR من تطبيق الكمبيوتر.',
                    ),
                  )
                else if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 28),
                    child: EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'لا توجد نتائج',
                      subtitle: 'جرّب اسم جهاز أو معرف آخر.',
                    ),
                  )
                else
                  for (var i = 0; i < filtered.length; i++)
                    _DeviceCard(
                      index: i,
                      device: filtered[i],
                      label: _labelFor(filtered[i]),
                      icon: _iconFor(filtered[i]),
                      color: _colorFor(context, filtered[i]),
                      message: _messages[filtered[i].id],
                      checking:
                          _stateFor(filtered[i]) == _ConnectionUiState.checking,
                      onOpen: () => _openDevice(filtered[i]),
                      onRefresh: () => _checkConnection(context, filtered[i]),
                      onScreenshot: () => _quickCommand(
                        context,
                        filtered[i],
                        CommandType.requestScreenshot,
                        'تم إرسال طلب لقطة الشاشة مباشرة.',
                      ),
                      onQr: () => _quickCommand(
                        context,
                        filtered[i],
                        CommandType.showPairingQr,
                        'تم طلب إظهار رمز الربط.',
                      ),
                      onDelete: () => _removeDevice(context, filtered[i]),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.deviceCount, required this.onlineCount});

  final int deviceCount;
  final int onlineCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [cs.primary, cs.tertiary],
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: .24),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.security_rounded,
                    color: Colors.white, size: 31),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'لوحة التحكم الذكية',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'أوامر مباشرة، واجهة أسرع، وضغطات أقل.',
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _HeaderMetric(
                label: 'الأجهزة',
                value: deviceCount.toString(),
                icon: Icons.computer_rounded,
              ),
              const SizedBox(width: 10),
              _HeaderMetric(
                label: 'متصل',
                value: onlineCount.toString(),
                icon: Icons.bolt_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: .16)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 21),
            const SizedBox(width: 9),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.index,
    required this.device,
    required this.label,
    required this.icon,
    required this.color,
    required this.checking,
    required this.onOpen,
    required this.onRefresh,
    required this.onScreenshot,
    required this.onQr,
    required this.onDelete,
    this.message,
  });

  final int index;
  final PcDevice device;
  final String label;
  final IconData icon;
  final Color color;
  final bool checking;
  final String? message;
  final VoidCallback onOpen;
  final VoidCallback onRefresh;
  final VoidCallback onScreenshot;
  final VoidCallback onQr;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .95, end: 1),
      duration: Duration(milliseconds: 220 + index * 45),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 22),
          child: child,
        ),
      ),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            cs.primary.withValues(alpha: .18),
                            cs.secondary.withValues(alpha: .12),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(Icons.computer_rounded,
                          size: 31, color: cs.primary),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${device.os} • App ${device.appVersion}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    StatusChip(label: label, icon: icon, color: color),
                    PopupMenuButton<String>(
                      tooltip: 'خيارات الجهاز',
                      onSelected: (value) {
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('حذف من الهاتف'),
                        ),
                      ],
                    ),
                  ],
                ),
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    message!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
                const SizedBox(height: 15),
                Wrap(
                  runSpacing: 8,
                  spacing: 8,
                  children: [
                    StatusChip(
                      label: 'WiFi: ${device.wifiStatus ?? 'غير معروف'}',
                      icon: Icons.wifi_rounded,
                      color: cs.primary,
                    ),
                    StatusChip(
                      label: 'Bluetooth: ${device.bluetoothStatus ?? 'غير معروف'}',
                      icon: Icons.bluetooth_rounded,
                      color: cs.secondary,
                    ),
                    StatusChip(
                      label: 'الصوت: ${device.volume}%',
                      icon: device.isMuted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: cs.tertiary,
                    ),
                  ],
                ),
                if (device.lastSeenAt != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'آخر ظهور: ${AppFormatters.dateTime(device.lastSeenAt!)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    _MiniActionButton(
                      label: checking ? 'يتحقق...' : 'فحص',
                      icon: checking ? Icons.sync_rounded : Icons.radar_rounded,
                      onTap: checking ? null : onRefresh,
                    ),
                    const SizedBox(width: 8),
                    _MiniActionButton(
                      label: 'لقطة',
                      icon: Icons.screenshot_monitor_rounded,
                      onTap: onScreenshot,
                    ),
                    const SizedBox(width: 8),
                    _MiniActionButton(
                      label: 'QR',
                      icon: Icons.qr_code_2_rounded,
                      onTap: onQr,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onOpen,
                        icon: const Icon(Icons.dashboard_customize_rounded),
                        label: const Text('التحكم'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }
}
