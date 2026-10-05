import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/pc_device.dart';

class LocalLinkedDevicesStore {
  LocalLinkedDevicesStore({SharedPreferences? preferences})
      : _preferences = preferences;

  SharedPreferences? _preferences;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Future<SharedPreferences> get _prefs async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  String _key(String userId) => 'linked_devices_v1_$userId';

  Future<List<PcDevice>> loadDevices(String userId) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_key(userId));
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .map((map) {
            final id = map['id']?.toString() ?? '';
            return PcDevice.fromMap(id, map);
          })
          .where((device) => device.id.isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (_) {
      return const [];
    }
  }

  Stream<List<PcDevice>> watchDevices(String userId) async* {
    yield await loadDevices(userId);
    await for (final _ in _changes.stream) {
      yield await loadDevices(userId);
    }
  }

  Future<void> upsertDevice(String userId, PcDevice device) async {
    final devices = await loadDevices(userId);
    final byId = <String, PcDevice>{
      for (final item in devices) item.id: item,
      device.id: device,
    };
    await saveDevices(userId, byId.values.toList());
  }

  Future<void> saveDevices(String userId, List<PcDevice> devices) async {
    final prefs = await _prefs;
    final sorted = List<PcDevice>.from(devices)
      ..sort((a, b) => a.name.compareTo(b.name));
    final encoded = jsonEncode(sorted.map(_toLocalJson).toList());
    final key = _key(userId);
    if (prefs.getString(key) == encoded) return;
    await prefs.setString(key, encoded);
    _changes.add(null);
  }

  Future<void> removeDevice(String userId, String deviceId) async {
    final devices = await loadDevices(userId);
    await saveDevices(
      userId,
      devices.where((device) => device.id != deviceId).toList(),
    );
  }

  Map<String, dynamic> _toLocalJson(PcDevice device) {
    return {
      'id': device.id,
      'name': device.name,
      'os': device.os,
      'appVersion': device.appVersion,
      'createdAt': device.createdAt.toIso8601String(),
      'linkedUserIds': device.linkedUserIds,
      'lastCheckResponse': device.lastCheckResponse,
      'lastSeenAt': device.lastSeenAt?.toIso8601String(),
      'wifiStatus': device.wifiStatus,
      'bluetoothStatus': device.bluetoothStatus,
      'volume': device.volume,
      'isMuted': device.isMuted,
    };
  }
}
