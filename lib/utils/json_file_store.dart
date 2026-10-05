import 'dart:convert';
import 'dart:io';

class JsonFileStore {
  final Directory dir;
  final File file;
  Map<String, dynamic> _data = <String, dynamic>{};

  JsonFileStore._(this.dir, this.file);

  static Future<JsonFileStore> open() async {
    final appData = Platform.environment['APPDATA'] ?? Directory.current.path;
    final dir = Directory('$appData\\KiomPcAgent');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}\\local_store.json');
    final store = JsonFileStore._(dir, file);
    await store._load();
    return store;
  }

  Future<void> _load() async {
    if (!await file.exists()) {
      _data = {
        'createdAt': DateTime.now().toIso8601String(),
        'device': null,
        'pathRules': <dynamic>[],
        'commandHistory': <dynamic>[],
        'scheduledCommands': <dynamic>[],
        'logs': <dynamic>[],
      };
      await save();
      return;
    }
    try {
      _data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      _data = <String, dynamic>{};
    }
  }

  Future<void> save() async {
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(_data));
  }

  T? get<T>(String key) => _data[key] as T?;

  Future<void> set(String key, dynamic value) async {
    _data[key] = value;
    await save();
  }

  List<dynamic> list(String key) {
    final v = _data[key];
    if (v is List) return v;
    _data[key] = <dynamic>[];
    return _data[key] as List<dynamic>;
  }

  Future<void> appendLog(String type, String message,
      [Map<String, dynamic>? extra]) async {
    final logs = list('logs');
    logs.add({
      'type': type,
      'message': message,
      'extra': extra ?? <String, dynamic>{},
      'createdAt': DateTime.now().toIso8601String(),
    });
    if (logs.length > 2000) {
      logs.removeRange(0, logs.length - 2000);
    }
    await save();
  }
}
