import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/command_type.dart';
import '../models/command_response.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({
    super.key,
    required this.userId,
    required this.device,
  });

  final String userId;
  final PcDevice device;

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  final _savePathController =
      TextEditingController(text: r'C:\Users\Public\Downloads');
  final _filePathController = TextEditingController();
  final List<Map<String, dynamic>> _devices = [];
  String? _selectedDeviceName;
  bool _busy = false;

  @override
  void dispose() {
    _savePathController.dispose();
    _filePathController.dispose();
    super.dispose();
  }

  Future<CommandResponse?> _sendAndWait(
    CommandType type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      final repo = context.read<DeviceRepository>();
      final commandId = await repo.sendCommand(
        userId: widget.userId,
        deviceId: widget.device.id,
        type: type,
        payload: payload,
      );
      if (mounted) showAppSnack(context, 'تم إرسال الأمر: ${type.arabicTitle}');
      final response = await repo.waitForCommandResponse(
        deviceId: widget.device.id,
        commandId: commandId,
        timeout: timeout,
      );
      if (mounted && response != null) {
        showAppSnack(context, response.message, error: !response.success);
      }
      if (mounted && response == null) {
        showAppSnack(context, 'لم يصل رد من الكمبيوتر ضمن المهلة.',
            error: true);
      }
      return response;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(CommandType type) async {
    await _sendAndWait(type);
  }

  Future<void> _loadDevices() async {
    final response = await _sendAndWait(CommandType.listBluetoothDevices);
    final rawDevices = response?.payload['devices'];
    if (!mounted || rawDevices is! List) return;
    setState(() {
      _devices
        ..clear()
        ..addAll(rawDevices
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>()));
      _selectedDeviceName ??= _devices.isEmpty
          ? null
          : (_devices.first['FriendlyName'] ?? _devices.first['name'])
              ?.toString();
    });
  }

  Future<void> _openReceive() async {
    await _sendAndWait(
      CommandType.openBluetoothReceive,
      payload: {'savePath': _savePathController.text.trim()},
    );
  }

  Future<void> _sendFile() async {
    final path = _filePathController.text.trim();
    if (path.isEmpty) {
      showAppSnack(context, 'اختر أو اكتب مسار الملف أولاً.', error: true);
      return;
    }
    await _sendAndWait(
      CommandType.sendBluetoothFile,
      payload: {
        'path': path,
        if (_selectedDeviceName != null) 'deviceName': _selectedDeviceName,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة Bluetooth')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.bluetooth, size: 48, color: cs.primary),
                  const SizedBox(height: 12),
                  Text(
                    'الحالة الحالية: ${widget.device.bluetoothStatus ?? 'غير معروفة'}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed:
                        _busy ? null : () => _toggle(CommandType.bluetoothOn),
                    icon: const Icon(Icons.bluetooth),
                    label: const Text('تشغيل Bluetooth'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed:
                        _busy ? null : () => _toggle(CommandType.bluetoothOff),
                    icon: const Icon(Icons.bluetooth_disabled),
                    label: const Text('إيقاف Bluetooth'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'أجهزة Bluetooth',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _loadDevices,
                    icon: const Icon(Icons.refresh),
                    label: const Text('تحديث الأجهزة'),
                  ),
                  if (_devices.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _devices.map((device) {
                        final name =
                            (device['FriendlyName'] ?? device['name'] ?? '')
                                .toString();
                        final selected = name == _selectedDeviceName;
                        return ChoiceChip(
                          selected: selected,
                          label: Text(name.isEmpty ? 'Bluetooth' : name),
                          onSelected: (_) =>
                              setState(() => _selectedDeviceName = name),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'تلقي ملف',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _savePathController,
                    decoration: const InputDecoration(
                      labelText: 'مسار حفظ الملفات على الكمبيوتر',
                      prefixIcon: Icon(Icons.folder_open_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _openReceive,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('فتح تلقي ملف على الكمبيوتر'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'إرسال ملف',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _filePathController,
                    decoration: const InputDecoration(
                      labelText: 'مسار الملف على الكمبيوتر',
                      prefixIcon: Icon(Icons.insert_drive_file_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_selectedDeviceName != null)
                    Text('الجهاز المختار: $_selectedDeviceName'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _sendFile,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('فتح إرسال Bluetooth'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
