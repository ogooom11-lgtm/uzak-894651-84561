import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../repositories/device_repository.dart';
import '../services/lan_discovery_service.dart';
import '../widgets/app_snack.dart';
import 'telegram_setup_screen.dart';

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
  bool _isManualScanning = false;

  @override
  void initState() {
    super.initState();
    unawaited(LanDiscoveryService.instance.start());
    unawaited(LanDiscoveryService.instance.scanLocalSubnet());
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _pair(String payload) async {
    if (_scanned) return;
    setState(() => _scanned = true);
    try {
      final decoded = jsonDecode(payload);
      final data = decoded is Map ? decoded.cast<String, dynamic>() : null;
      final deviceId = (data?['deviceId'] ?? '').toString();
      final deviceName =
          (data?['name'] ?? data?['deviceName'] ?? deviceId).toString();

      await context.read<DeviceRepository>().pairDeviceByQrPayload(
            userId: widget.userId,
            qrPayload: payload,
          );
      if (!mounted) return;
      showAppSnack(context, 'تم ربط الجهاز بنجاح ⚡');
      if (deviceId.isEmpty) {
        Navigator.pop(context);
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TelegramSetupScreen(
            userId: widget.userId,
            deviceId: deviceId,
            deviceName: deviceName,
            afterPairing: true,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanned = false);
      showAppSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _pairFromLanDevice(LanDeviceInfo dev) async {
    final payload = jsonEncode({
      'deviceId': dev.deviceId,
      'deviceName': dev.deviceName,
      'ip': dev.ip,
      'httpPort': dev.httpPort,
      'pairingToken': 'lan_auto_${dev.deviceId}',
      'expiresAt': '2099-12-31T23:59:59.000',
    });
    await _pair(payload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ربط جهاز جديد'),
        actions: [
          IconButton(
            icon: _isManualScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find),
            tooltip: 'فحص الشبكة المحلية الآن',
            onPressed: _isManualScanning
                ? null
                : () async {
                    setState(() => _isManualScanning = true);
                    showAppSnack(context, 'جاري فحص شبكة Wi-Fi بحثاً عن أجهزة كمبيوتر...');
                    await LanDiscoveryService.instance.scanLocalSubnet();
                    if (mounted) {
                      setState(() => _isManualScanning = false);
                      showAppSnack(context, 'اكتمل فحص الشبكة المحلية.');
                    }
                  },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Auto-Discovered Wi-Fi Devices Banner
          StreamBuilder<Map<String, LanDeviceInfo>>(
            stream: LanDiscoveryService.instance.stream,
            initialData: LanDiscoveryService.instance.discovered,
            builder: (context, snapshot) {
              final devices = snapshot.data?.values.toList() ?? [];
              if (devices.isEmpty) {
                return Card(
                  color: Colors.blue.withAlpha(20),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'جاري البحث التلقائي عن أجهزة الكمبيوتر على نفس شبكة Wi-Fi...',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Card(
                color: Colors.green.withAlpha(25),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bolt, color: Colors.green, size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'أجهزة مكتشفة تلقائياً على شبكة Wi-Fi (${devices.length})',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: Colors.green.shade800,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...devices.map((dev) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.computer, color: Colors.green),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dev.deviceName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                        ),
                                      ),
                                      Text(
                                        'IP: ${dev.ip}  •  ${dev.os}',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.green.shade100,
                                    foregroundColor: Colors.green.shade900,
                                  ),
                                  onPressed: () => _pairFromLanDevice(dev),
                                  icon: const Icon(Icons.link, size: 18),
                                  label: const Text('ربط فوري'),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          Text(
            'أو امسح كود QR من شاشة الكمبيوتر:',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 280,
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
        ],
      ),
    );
  }
}
