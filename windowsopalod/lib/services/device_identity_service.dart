import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../config/agent_config.dart';
import '../utils/json_file_store.dart';

class DeviceIdentityService {
  final JsonFileStore store;
  final AgentConfig config;
  DeviceIdentityService(this.store, this.config);

  Future<Map<String, dynamic>> getOrCreateDevice() async {
    final existing = store.get<Map<String, dynamic>>('device');
    if (existing != null && existing['deviceId'] != null) return existing;

    final name = Platform.localHostname;
    final user =
        Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? '';
    final os = 'Windows ${Platform.operatingSystemVersion}';
    final raw = await _stableDeviceSeed(name: name, user: user);
    final short = sha1.convert(utf8.encode(raw)).toString().substring(0, 10);
    final device = {
      'deviceId': 'pc_$short',
      'name': name,
      'os': os,
      'windowsUser': user,
      'appVersion': config.appVersion,
      'firstRegisteredAt': DateTime.now().toIso8601String(),
    };
    await store.set('device', device);
    return device;
  }

  Future<Map<String, dynamic>> createPairingPayload() async {
    final device = await getOrCreateDevice();
    final token =
        'token_${const Uuid().v4().replaceAll('-', '').substring(0, 18)}';
    final securityKey = const Uuid().v4().replaceAll('-', '');
    final expiresAt = DateTime.now().add(const Duration(minutes: 10));
    final payload = {
      'deviceId': device['deviceId'],
      'pairingToken': token,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'securityKey': securityKey,
      'name': device['name'],
      'os': device['os'],
      'appVersion': device['appVersion'],
    };
    final file = File('${store.dir.path}\\pairing_payload.json');
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    await store.set('lastPairingPayload', payload);
    return payload;
  }

  Future<String> _stableDeviceSeed({
    required String name,
    required String user,
  }) async {
    final machineGuid = await _readWindowsMachineGuid();
    return [
      'kiom_pc_agent_v2',
      name.trim().toLowerCase(),
      user.trim().toLowerCase(),
      machineGuid.trim().toLowerCase(),
    ].where((part) => part.isNotEmpty).join('|');
  }

  Future<String> _readWindowsMachineGuid() async {
    if (!Platform.isWindows) return '';
    try {
      final result = await Process.run(
        'reg.exe',
        [
          'query',
          r'HKLM\SOFTWARE\Microsoft\Cryptography',
          '/v',
          'MachineGuid',
        ],
        runInShell: false,
      );
      if (result.exitCode != 0) return '';
      final match = RegExp(r'MachineGuid\s+REG_SZ\s+(.+)', caseSensitive: false)
          .firstMatch(result.stdout.toString());
      return match?.group(1)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }
}
