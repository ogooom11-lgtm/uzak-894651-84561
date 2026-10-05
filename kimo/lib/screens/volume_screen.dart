import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/command_type.dart';
import '../models/pc_device.dart';
import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';

class VolumeScreen extends StatefulWidget {
  const VolumeScreen({super.key, required this.userId, required this.device});

  final String userId;
  final PcDevice device;

  @override
  State<VolumeScreen> createState() => _VolumeScreenState();
}

class _VolumeScreenState extends State<VolumeScreen> {
  late double _volume = widget.device.volume.clamp(0, 100).toDouble();

  Future<void> _send(CommandType type,
      [Map<String, dynamic> payload = const {}]) async {
    await context.read<DeviceRepository>().sendCommand(
          userId: widget.userId,
          deviceId: widget.device.id,
          type: type,
          payload: payload,
        );
    if (mounted) showAppSnack(context, 'تم إرسال الأمر: ${type.arabicTitle}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الصوت')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                      widget.device.isMuted
                          ? Icons.volume_off
                          : Icons.volume_up,
                      size: 58),
                  const SizedBox(height: 12),
                  Text('${_volume.round()}%',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 34, fontWeight: FontWeight.w900)),
                  Slider(
                    value: _volume,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '${_volume.round()}%',
                    onChanged: (value) => setState(() => _volume = value),
                    onChangeEnd: (value) =>
                        _send(CommandType.setVolume, {'volume': value.round()}),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _send(CommandType.volumeDown),
                          icon: const Icon(Icons.remove),
                          label: const Text('خفض'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _send(CommandType.volumeUp),
                          icon: const Icon(Icons.add),
                          label: const Text('رفع'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _send(CommandType.muteVolume),
                          icon: const Icon(Icons.volume_off),
                          label: const Text('كتم'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _send(CommandType.unmuteVolume),
                          icon: const Icon(Icons.volume_up),
                          label: const Text('إلغاء الكتم'),
                        ),
                      ),
                    ],
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
