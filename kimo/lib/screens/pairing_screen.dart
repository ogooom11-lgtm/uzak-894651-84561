import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../repositories/device_repository.dart';
import '../widgets/app_snack.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, required this.userId});

  final String userId;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _manualController = TextEditingController(
    text:
        '{"deviceId":"pc_new_001","pairingToken":"demo_token","expiresAt":"2099-01-01T00:00:00.000"}',
  );
  bool _scanned = false;

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _pair(String payload) async {
    if (_scanned) return;
    setState(() => _scanned = true);
    try {
      await context.read<DeviceRepository>().pairDeviceByQrPayload(
            userId: widget.userId,
            qrPayload: payload,
          );
      if (!mounted) return;
      showAppSnack(context, 'تم ربط الجهاز بنجاح.');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanned = false);
      showAppSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ربط جهاز عبر QR')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 320,
              child: MobileScanner(
                onDetect: (capture) {
                  if (capture.barcodes.isEmpty) return;
                  final raw = capture.barcodes.first.rawValue;
                  if (raw != null && raw.isNotEmpty) _pair(raw);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ربط يدوي للتجربة',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _manualController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'محتوى QR بصيغة JSON',
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => _pair(_manualController.text.trim()),
                    icon: const Icon(Icons.link),
                    label: const Text('ربط يدوي'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'في تطبيق Windows سيظهر QR مؤقت يحتوي deviceId و pairingToken و expiresAt و securityKey. هذا التطبيق يقرأ الرمز ويربط الجهاز بحساب المستخدم.',
            style: TextStyle(height: 1.6),
          ),
        ],
      ),
    );
  }
}
