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

  Future<void> _removeDevice(BuildContext context, PcDevice device) async {
    final confirmed = await confirmAction(
      context,
      title: 'حذف الجهاز',
      message: 'هل تريد حذف ${device.name} من تطبيق الهاتف؟',
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
    if (state == _ConnectionUiState.online) return Icons.wifi_tethering;
    return Icons.wifi_off;
  }

  Color _colorFor(BuildContext context, PcDevice device) {
    final state = _stateFor(device);
    if (state == _ConnectionUiState.checking) {
      return Theme.of(context).colorScheme.primary;
    }
    if (state == _ConnectionUiState.online) return Colors.green;
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DeviceRepository>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأجهزة المرتبطة'),
        actions: [
          IconButton(
            tooltip: 'الإعدادات',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PairingScreen(userId: widget.userId)),
        ),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('ربط جهاز'),
      ),
      body: StreamBuilder<List<PcDevice>>(
        stream: repo.watchDevices(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final devices = snapshot.data ?? const <PcDevice>[];
          if (devices.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 92),
              children: const [
                _DevicesHeader(deviceCount: 0),
                SizedBox(height: 42),
                EmptyState(
                  icon: Icons.devices_other,
                  title: 'لا توجد أجهزة مرتبطة بعد',
                  subtitle: 'اضغط زر ربط جهاز وامسح QR من تطبيق الكمبيوتر.',
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 92),
            itemCount: devices.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _DevicesHeader(deviceCount: devices.length);
              }
              final deviceIndex = index - 1;
              final device = devices[deviceIndex];
              final isChecking =
                  _stateFor(device) == _ConnectionUiState.checking;
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: .94, end: 1),
                duration: Duration(milliseconds: 220 + deviceIndex * 35),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value.clamp(0, 1),
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 18),
                    child: child,
                  ),
                ),
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DeviceDetailsScreen(
                            userId: widget.userId, device: device),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.computer_rounded,
                                    size: 30),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      device.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                        '${device.os} • App ${device.appVersion}'),
                                  ],
                                ),
                              ),
                              StatusChip(
                                label: _labelFor(device),
                                icon: _iconFor(device),
                                color: _colorFor(context, device),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'خيارات الجهاز',
                                onSelected: (value) {
                                  if (value == 'delete') {
                                    _removeDevice(context, device);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('حذف الجهاز'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (_messages[device.id] != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _messages[device.id]!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Wrap(
                            runSpacing: 8,
                            spacing: 8,
                            children: [
                              StatusChip(
                                label:
                                    'WiFi: ${device.wifiStatus ?? 'غير معروف'}',
                                icon: Icons.wifi,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              StatusChip(
                                label:
                                    'Bluetooth: ${device.bluetoothStatus ?? 'غير معروف'}',
                                icon: Icons.bluetooth,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              StatusChip(
                                label: 'الصوت: ${device.volume}%',
                                icon: device.isMuted
                                    ? Icons.volume_off
                                    : Icons.volume_up,
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                            ],
                          ),
                          if (device.lastSeenAt != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              'آخر ظهور: ${AppFormatters.dateTime(device.lastSeenAt!)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: isChecking
                                      ? null
                                      : () => _checkConnection(context, device),
                                  icon: isChecking
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.refresh),
                                  label: Text(isChecking
                                      ? 'جاري التحقق...'
                                      : 'تحقق من الاتصال'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DeviceDetailsScreen(
                                          userId: widget.userId,
                                          device: device),
                                    ),
                                  ),
                                  icon: const Icon(
                                      Icons.dashboard_customize_outlined),
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
            },
          );
        },
      ),
    );
  }
}

class _DevicesHeader extends StatelessWidget {
  const _DevicesHeader({required this.deviceCount});

  final int deviceCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: .12)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.security_outlined, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KIOM Control',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  deviceCount == 0
                      ? 'اربط أول كمبيوتر لبدء التحكم.'
                      : '$deviceCount جهاز جاهز للمتابعة والتحكم.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
