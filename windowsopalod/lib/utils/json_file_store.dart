import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Compatibility wrapper around the agent local database.
///
/// Older services still call this class `JsonFileStore`, but the backing store is
/// now SQLite (`kiom_agent.db`) instead of one large JSON file. The public API is
/// intentionally kept the same (`get`, `set`, `list`, `save`) so the rest of the
/// agent can migrate safely without a risky rewrite.
class JsonFileStore {
  final Directory dir;

  /// Legacy JSON path kept for one-time migration and for older helper scripts
  /// that may still inspect this location. New writes go to [databaseFile].
  final File file;
  final File databaseFile;
  final Database _db;

  Map<String, dynamic> _data = <String, dynamic>{};
  Future<void> _saveQueue = Future<void>.value();

  static bool _sqliteInitialized = false;

  JsonFileStore._(this.dir, this.file, this.databaseFile, this._db);

  static Future<JsonFileStore> open() async {
    final appData = Platform.environment['APPDATA'] ?? Directory.current.path;
    final dir = Directory('$appData\\KiomPcAgent');
    if (!await dir.exists()) await dir.create(recursive: true);

    if (!_sqliteInitialized) {
      sqfliteFfiInit();
      _sqliteInitialized = true;
    }

    final legacyFile = File('${dir.path}\\local_store.json');
    final databaseFile = File(p.join(dir.path, 'kiom_agent.db'));
    final db = await databaseFactoryFfi.openDatabase(
      databaseFile.path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: _createSchema,
        onOpen: (db) async => _createSchema(db, 1),
      ),
    );

    final store = JsonFileStore._(dir, legacyFile, databaseFile, db);
    await store._load();
    return store;
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS app_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,
  message TEXT NOT NULL,
  extra TEXT NOT NULL,
  created_at TEXT NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_logs_created_at ON logs(created_at)',
    );
    await db.execute('''
CREATE TABLE IF NOT EXISTS command_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  command_id TEXT,
  type TEXT,
  success INTEGER,
  message TEXT,
  payload TEXT,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS clipboard_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id TEXT UNIQUE,
  type TEXT NOT NULL,
  content TEXT NOT NULL,
  char_count INTEGER,
  source_app TEXT,
  source_app_name TEXT,
  source_title TEXT,
  source_path TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_clipboard_history_created_at ON clipboard_history(created_at);
''');
  }

  Future<void> _load() async {
    final rows = await _db.query('app_state');
    _data = <String, dynamic>{};
    for (final row in rows) {
      final key = row['key']?.toString();
      final value = row['value']?.toString();
      if (key == null || value == null) continue;
      try {
        _data[key] = jsonDecode(value);
      } catch (_) {
        _data[key] = value;
      }
    }

    if (_data.isEmpty && await file.exists()) {
      await _migrateLegacyJsonFile();
    }

    _ensureDefaults();
    await _loadLogsFromTableIfNeeded();
    await save();
  }

  Future<void> _migrateLegacyJsonFile() async {
    try {
      _data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final logs = (_data['logs'] as List?) ?? const [];
      if (logs.isNotEmpty) {
        final batch = _db.batch();
        for (final entry in logs.whereType<Map>()) {
          final map = entry.cast<String, dynamic>();
          batch.insert('logs', {
            'type': (map['type'] ?? 'general').toString(),
            'message': (map['message'] ?? '').toString(),
            'extra': jsonEncode(map['extra'] ?? <String, dynamic>{}),
            'created_at': (map['createdAt'] ?? DateTime.now().toIso8601String())
                .toString(),
          });
        }
        await batch.commit(noResult: true);
      }
    } catch (_) {
      _data = <String, dynamic>{};
    }
  }

  void _ensureDefaults() {
    _data.putIfAbsent('createdAt', () => DateTime.now().toIso8601String());
    _data.putIfAbsent('device', () => null);
    _data.putIfAbsent('pathRules', () => <dynamic>[]);
    _data.putIfAbsent('commandHistory', () => <dynamic>[]);
    _data.putIfAbsent('undoStack', () => <dynamic>[]);
    _data.putIfAbsent('scheduledCommands', () => <dynamic>[]);
    _data.putIfAbsent('logs', () => <dynamic>[]);
  }

  Future<void> _loadLogsFromTableIfNeeded() async {
    final logs = _data['logs'];
    if (logs is List && logs.isNotEmpty) return;

    final rows = await _db.query(
      'logs',
      orderBy: 'id DESC',
      limit: 2000,
    );
    if (rows.isEmpty) return;

    _data['logs'] = rows.reversed.map((row) {
      Map<String, dynamic> extra = <String, dynamic>{};
      try {
        final decoded = jsonDecode(row['extra']?.toString() ?? '{}');
        if (decoded is Map) extra = decoded.cast<String, dynamic>();
      } catch (_) {}
      return {
        'type': row['type']?.toString() ?? 'general',
        'message': row['message']?.toString() ?? '',
        'extra': extra,
        'createdAt': row['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      };
    }).toList();
  }

  Future<void> save() {
    final snapshot = jsonDecode(
      jsonEncode(_data),
    ) as Map<String, dynamic>;
    _saveQueue = _saveQueue.catchError((_) {}).then((_) async {
      final now = DateTime.now().toIso8601String();
      await _db.transaction((txn) async {
        for (final entry in snapshot.entries) {
          await txn.insert(
            'app_state',
            {
              'key': entry.key,
              'value': jsonEncode(entry.value),
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    });
    return _saveQueue;
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
    final createdAt = DateTime.now().toIso8601String();
    final safeExtra = extra ?? <String, dynamic>{};
    await _db.insert('logs', {
      'type': type,
      'message': message,
      'extra': jsonEncode(safeExtra),
      'created_at': createdAt,
    });
    await _db.delete(
      'logs',
      where: 'id NOT IN (SELECT id FROM logs ORDER BY id DESC LIMIT 2000)',
    );

    final logs = list('logs');
    logs.add({
      'type': type,
      'message': message,
      'extra': safeExtra,
      'createdAt': createdAt,
    });
    if (logs.length > 2000) {
      logs.removeRange(0, logs.length - 2000);
    }
    await save();
  }

  Future<List<Map<String, dynamic>>> queryLogs({
    String? type,
    DateTime? from,
    DateTime? to,
    String? search,
    int limit = 50,
  }) async {
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (type != null && type.isNotEmpty && type != 'all') {
      whereClauses.add('type = ?');
      whereArgs.add(type);
    }

    if (from != null) {
      whereClauses.add('created_at >= ?');
      whereArgs.add(from.toIso8601String());
    }

    if (to != null) {
      whereClauses.add('created_at <= ?');
      whereArgs.add(to.toIso8601String());
    }

    if (search != null && search.trim().isNotEmpty) {
      whereClauses.add('(message LIKE ? OR extra LIKE ?)');
      final term = '%${search.trim()}%';
      whereArgs.add(term);
      whereArgs.add(term);
    }

    final where = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final rows = await _db.query(
      'logs',
      where: where,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'id DESC',
      limit: limit,
    );

    return rows.map((row) {
      Map<String, dynamic> extra = <String, dynamic>{};
      try {
        final decoded = jsonDecode(row['extra']?.toString() ?? '{}');
        if (decoded is Map) extra = decoded.cast<String, dynamic>();
      } catch (_) {}
      return {
        'id': row['id'],
        'type': row['type']?.toString() ?? 'general',
        'message': row['message']?.toString() ?? '',
        'extra': extra,
        'createdAt': row['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      };
    }).toList();
  }

  Future<void> appendClipboardEntry({
    required String itemId,
    required String type,
    required String content,
    int? charCount,
    String? sourceApp,
    String? sourceAppName,
    String? sourceTitle,
    String? sourcePath,
  }) async {
    final createdAt = DateTime.now().toIso8601String();
    await _db.insert(
      'clipboard_history',
      {
        'item_id': itemId,
        'type': type,
        'content': content,
        'char_count': charCount ?? content.length,
        'source_app': sourceApp ?? '',
        'source_app_name': sourceAppName ?? '',
        'source_title': sourceTitle ?? '',
        'source_path': sourcePath ?? '',
        'created_at': createdAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _db.delete(
      'clipboard_history',
      where: 'id NOT IN (SELECT id FROM clipboard_history ORDER BY id DESC LIMIT 500)',
    );
  }

  Future<List<Map<String, dynamic>>> queryClipboardHistory({
    int limit = 50,
    String? query,
  }) async {
    String? where;
    List<dynamic>? whereArgs;

    if (query != null && query.trim().isNotEmpty) {
      where = '(content LIKE ? OR source_app LIKE ? OR source_title LIKE ? OR source_path LIKE ?)';
      final term = '%${query.trim()}%';
      whereArgs = [term, term, term, term];
    }

    final rows = await _db.query(
      'clipboard_history',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'id DESC',
      limit: limit,
    );

    return rows.map((row) {
      return {
        'id': row['item_id']?.toString() ?? row['id'].toString(),
        'type': row['type']?.toString() ?? 'text',
        'content': row['content']?.toString() ?? '',
        'charCount': row['char_count'] as int? ?? 0,
        'sourceApp': row['source_app']?.toString() ?? '',
        'sourceAppName': row['source_app_name']?.toString() ?? '',
        'sourceTitle': row['source_title']?.toString() ?? '',
        'sourcePath': row['source_path']?.toString() ?? '',
        'createdAt': row['created_at']?.toString() ?? '',
      };
    }).toList();
  }

  Future<void> clearClipboardHistory() async {
    await _db.delete('clipboard_history');
  }
}
