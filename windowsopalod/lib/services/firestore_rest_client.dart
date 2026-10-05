import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/agent_config.dart';
import '../models/open_app_info.dart';
import '../models/remote_command.dart';
import '../utils/json_file_store.dart';

class FirestoreRestClient {
  final AgentConfig config;
  final JsonFileStore? store;

  FirestoreRestClient(this.config, {this.store});

  String? _idToken;
  String? _refreshToken;
  DateTime? _tokenExpiresAt;
  bool _anonymousAuthUnavailable = false;

  String get _base =>
      'https://firestore.googleapis.com/v1/projects/${config.projectId}/databases/${Uri.encodeComponent(config.databaseId)}/documents';

  Uri _uri(String path, [Map<String, String>? query]) {
    final q = <String, String>{};
    if (config.apiKey.isNotEmpty) q['key'] = config.apiKey;
    if (query != null) q.addAll(query);
    return Uri.parse('$_base/$path')
        .replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<bool> documentExists(String path) async {
    final response = await http.get(_uri(path), headers: await _headers());
    if (response.statusCode == 200) return true;
    if (response.statusCode == 404) return false;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Firestore documentExists failed ${response.statusCode}: ${response.body}');
    }
    return false;
  }

  Future<void> setDocument(String path, Map<String, dynamic> data) async {
    final maskQuery = data.keys
        .map((k) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent(k)}')
        .join('&');
    final baseUrl = _uri(path).toString();
    final sep = baseUrl.contains('?') ? '&' : '?';
    final url = maskQuery.isEmpty ? baseUrl : '$baseUrl$sep$maskQuery';

    final response = await http.patch(
      Uri.parse(url),
      headers: await _headers(jsonBody: true),
      body: jsonEncode({'fields': _toFields(data)}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Firestore setDocument failed ${response.statusCode}: ${response.body}');
    }
  }

  Future<void> createDocumentWithId(
    String collectionPath,
    String documentId,
    Map<String, dynamic> data,
  ) async {
    final uri = _uri(collectionPath, {'documentId': documentId});
    final response = await http.post(
      uri,
      headers: await _headers(jsonBody: true),
      body: jsonEncode({'fields': _toFields(data)}),
    );

    if (response.statusCode == 409) {
      await setDocument('$collectionPath/$documentId', data);
      return;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Firestore createDocument failed ${response.statusCode}: ${response.body}');
    }
  }

  Future<List<Map<String, dynamic>>> listDocuments(
      String collectionPath) async {
    final response =
        await http.get(_uri(collectionPath), headers: await _headers());
    if (response.statusCode == 404) return [];
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Firestore listDocuments failed ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final docs = (decoded['documents'] as List?) ?? const [];

    return docs.map((doc) {
      final map = doc as Map<String, dynamic>;
      final name = (map['name'] ?? '').toString();
      final id = name.split('/').last;
      return {
        'id': id,
        ..._fromFields(
            (map['fields'] as Map?)?.cast<String, dynamic>() ?? const {}),
      };
    }).toList();
  }

  Future<void> deleteDocument(String path) async {
    final response = await http.delete(_uri(path), headers: await _headers());
    if (response.statusCode == 404) return;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Firestore deleteDocument failed ${response.statusCode}: ${response.body}');
    }
  }

  Future<void> registerDevice({
    required String deviceId,
    required String name,
    required String os,
    required String windowsUser,
    required String appVersion,
  }) async {
    await setDocument('devices/$deviceId', {
      'name': name,
      'os': os,
      'windowsUser': windowsUser,
      'appVersion': appVersion,
      'status': 'registered',
      'linkedUserIds': [config.demoUserId],
      'lastCheckResponse': 'لم يتم الفحص بعد',
      'volume': 50,
      'isMuted': false,
      'registeredAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> createPairingToken({
    required String token,
    required String deviceId,
    required String securityKey,
    required DateTime expiresAt,
  }) async {
    await createDocumentWithId('pairing_tokens', token, {
      'deviceId': deviceId,
      'securityKey': securityKey,
      'used': false,
      'createdAt': DateTime.now().toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
    });
  }

  Future<void> syncOpenApps(String deviceId, List<OpenAppInfo> apps) async {
    final collection = 'open_apps/$deviceId/items';
    final existing = await listDocuments(collection);
    final currentIds = apps.map((e) => e.processId.toString()).toSet();

    for (final doc in existing) {
      final id = doc['id'].toString();
      if (!currentIds.contains(id)) {
        await deleteDocument('$collection/$id');
      }
    }

    for (final app in apps) {
      await createDocumentWithId(
          collection, app.processId.toString(), app.toMap());
    }
  }

  Future<void> writeRequestedLogs(
      String deviceId, List<Map<String, dynamic>> logs) async {
    final collection = 'requested_logs/$deviceId/items';
    final now = DateTime.now().millisecondsSinceEpoch;

    for (var i = 0; i < logs.length; i++) {
      final log = logs[i];
      final createdAt =
          (log['createdAt'] ?? DateTime.now().toIso8601String()).toString();
      final extra = (log['extra'] is Map)
          ? (log['extra'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      await createDocumentWithId(collection, 'log_${now}_$i', {
        'type': (log['type'] ?? 'general').toString(),
        'message': (log['message'] ?? '').toString(),
        'target': (log['target'] ?? extra['path'] ?? extra['appName'] ?? '')
            .toString(),
        'payload': extra,
        'createdAt': createdAt,
      });
    }
  }

  Future<void> syncInstalledApps(
      String deviceId, List<Map<String, dynamic>> apps) async {
    final collection = 'installed_apps/$deviceId/items';
    final existing = await listDocuments(collection);
    final currentIds = apps.map((e) => e['id'].toString()).toSet();

    for (final doc in existing) {
      final id = doc['id'].toString();
      if (!currentIds.contains(id)) {
        await deleteDocument('$collection/$id');
      }
    }

    for (final app in apps) {
      await createDocumentWithId(collection, app['id'].toString(), app);
    }
  }

  Future<void> syncBlockedItems(
      String deviceId, List<Map<String, dynamic>> items) async {
    final collection = 'blocked_items/$deviceId/items';
    final existing = await listDocuments(collection);
    final currentIds = items.map((e) => e['id'].toString()).toSet();

    for (final doc in existing) {
      final id = doc['id'].toString();
      if (!currentIds.contains(id)) {
        await deleteDocument('$collection/$id');
      }
    }

    for (final item in items) {
      await createDocumentWithId(collection, item['id'].toString(), item);
    }
  }

  Future<void> createScreenshot({
    required String deviceId,
    required String imageUrl,
    required String storagePath,
    required Map<String, dynamic> payload,
  }) async {
    final id = 'shot_${DateTime.now().millisecondsSinceEpoch}';
    await createDocumentWithId('screenshots/$deviceId/items', id, {
      'deviceId': deviceId,
      'imageUrl': imageUrl,
      'storagePath': storagePath,
      'payload': payload,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> createInstallChange({
    required String deviceId,
    required String appName,
    required String changeType,
    required Map<String, dynamic> payload,
  }) async {
    final id =
        'install_${DateTime.now().millisecondsSinceEpoch}_${_safeDocumentId(appName)}';
    await createDocumentWithId('install_requests/$deviceId/items', id, {
      'deviceId': deviceId,
      'fileName': appName,
      'filePath': (payload['installLocation'] ?? '').toString(),
      'status': 'pending',
      'type': changeType,
      'details': payload,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<List<RemoteCommand>> getPendingCommands(String deviceId) async {
    final docs = await listDocuments('commands/$deviceId/items');
    return docs.where((d) => (d['status'] ?? 'pending') == 'pending').map((d) {
      return RemoteCommand(
        id: d['id'].toString(),
        type: (d['type'] ?? '').toString(),
        status: (d['status'] ?? 'pending').toString(),
        payload: (d['payload'] is Map)
            ? (d['payload'] as Map).cast<String, dynamic>()
            : <String, dynamic>{},
        createdBy: (d['createdBy'] ?? '').toString(),
        createdAt: DateTime.tryParse((d['createdAt'] ?? '').toString()),
      );
    }).toList();
  }

  /// تأكيد فوري أن الكمبيوتر استلم الأمر. هذا يحل خطأ markCommandReceived غير موجود.
  Future<void> markCommandReceived(
    String deviceId,
    String commandId, {
    required String type,
    required String message,
  }) async {
    await setDocument('commands/$deviceId/items/$commandId', {
      'status': 'processing',
      'receivedAt': DateTime.now().toIso8601String(),
      'acknowledgedAt': DateTime.now().toIso8601String(),
      'ackMessage': message,
      'resultMessage': message,
      'agentState': 'received',
      'type': type,
    });
  }

  Future<void> markCommandExecuted(
    String deviceId,
    String commandId, {
    required bool success,
    required String message,
  }) async {
    await setDocument('commands/$deviceId/items/$commandId', {
      'status': success ? 'executed' : 'failed',
      'executedAt': DateTime.now().toIso8601String(),
      'resultMessage': message,
      'agentState': success ? 'done' : 'error',
    });

    if (config.deleteCommandsAfterExecution) {
      await deleteDocument('commands/$deviceId/items/$commandId');
    }
  }

  /// يقبل 6 أو 7 معاملات حتى لا يظهر خطأ: Too many positional arguments.
  Future<void> writeResponse(
    String deviceId,
    String commandId,
    String type,
    bool success,
    String message, [
    Map<String, dynamic>? payload,
    String phase = 'final',
  ]) async {
    await createDocumentWithId(
      'responses/$deviceId/items',
      '${commandId}_${phase}_${DateTime.now().millisecondsSinceEpoch}',
      {
        'commandId': commandId,
        'type': type,
        'phase': phase,
        'success': success,
        'message': message,
        'payload': payload ?? <String, dynamic>{},
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> createPermissionRequest({
    required String deviceId,
    required String path,
    required String openedPath,
    required String ruleId,
  }) async {
    final id = 'perm_${DateTime.now().millisecondsSinceEpoch}';
    await createDocumentWithId('permission_requests/$deviceId/items', id, {
      'deviceId': deviceId,
      'ruleId': ruleId,
      'path': path,
      'openedPath': openedPath,
      'type': 'open_path',
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  String _safeDocumentId(String value) {
    final safe = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
    return safe.isEmpty
        ? 'item'
        : safe.substring(0, safe.length > 60 ? 60 : safe.length);
  }

  Map<String, dynamic> _toFields(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key, _toValue(value)));
  }

  Map<String, dynamic> _toValue(dynamic value) {
    if (value == null) return {'nullValue': null};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': value.toString()};
    if (value is double) return {'doubleValue': value};
    if (value is num) return {'doubleValue': value.toDouble()};
    if (value is DateTime) {
      return {'timestampValue': value.toUtc().toIso8601String()};
    }
    if (value is List) {
      return {
        'arrayValue': {'values': value.map(_toValue).toList()}
      };
    }
    if (value is Map) {
      return {
        'mapValue': {'fields': _toFields(value.cast<String, dynamic>())}
      };
    }

    final s = value.toString();
    if (_looksLikeIsoDate(s)) {
      final parsed = DateTime.tryParse(s);
      if (parsed != null) {
        return {'timestampValue': parsed.toUtc().toIso8601String()};
      }
    }
    return {'stringValue': s};
  }

  Map<String, dynamic> _fromFields(Map<String, dynamic> fields) {
    return fields.map((key, value) =>
        MapEntry(key, _fromValue(value as Map<String, dynamic>)));
  }

  dynamic _fromValue(Map<String, dynamic> value) {
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('integerValue')) {
      return int.tryParse(value['integerValue'].toString()) ?? 0;
    }
    if (value.containsKey('doubleValue')) {
      return (value['doubleValue'] as num).toDouble();
    }
    if (value.containsKey('booleanValue')) return value['booleanValue'] == true;
    if (value.containsKey('timestampValue')) return value['timestampValue'];
    if (value.containsKey('nullValue')) return null;

    if (value.containsKey('arrayValue')) {
      final array = (value['arrayValue'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final values = (array['values'] as List?) ?? const [];
      return values
          .map((e) => _fromValue((e as Map).cast<String, dynamic>()))
          .toList();
    }

    if (value.containsKey('mapValue')) {
      final mapValue = (value['mapValue'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final fields = (mapValue['fields'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return _fromFields(fields);
    }

    return null;
  }

  bool _looksLikeIsoDate(String value) {
    if (value.length < 16) return false;
    return DateTime.tryParse(value) != null;
  }

  Future<Map<String, String>> _headers({bool jsonBody = false}) async {
    final headers = <String, String>{};
    if (jsonBody) headers['Content-Type'] = 'application/json';

    final token = await _getIdToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<String?> _getIdToken() async {
    if (_anonymousAuthUnavailable || config.apiKey.trim().isEmpty) return null;

    await _loadCachedAuth();
    final now = DateTime.now();
    if (_idToken != null &&
        _tokenExpiresAt != null &&
        _tokenExpiresAt!.isAfter(now.add(const Duration(minutes: 5)))) {
      return _idToken;
    }

    try {
      if (_refreshToken != null && _refreshToken!.isNotEmpty) {
        await _refreshAnonymousAuth();
      } else {
        await _signInAnonymously();
      }
    } catch (e) {
      _anonymousAuthUnavailable = true;
      await store?.appendLog(
        'firebase_anonymous_auth_error',
        e.toString(),
        {'hint': 'Enable Anonymous sign-in in Firebase Authentication.'},
      );
      return null;
    }

    return _idToken;
  }

  Future<void> _loadCachedAuth() async {
    if (_idToken != null || store == null) return;
    final raw = store!.get<Map<String, dynamic>>('firebaseAnonymousAuth');
    if (raw == null) return;
    _idToken = raw['idToken']?.toString();
    _refreshToken = raw['refreshToken']?.toString();
    _tokenExpiresAt = DateTime.tryParse((raw['expiresAt'] ?? '').toString());
  }

  Future<void> _signInAnonymously() async {
    final uri = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp',
    ).replace(queryParameters: {'key': config.apiKey});

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'returnSecureToken': true}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Firebase anonymous sign-in failed ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveAuthResponse(decoded);
  }

  Future<void> _refreshAnonymousAuth() async {
    final uri = Uri.parse('https://securetoken.googleapis.com/v1/token')
        .replace(queryParameters: {'key': config.apiKey});

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: Uri(queryParameters: {
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken ?? '',
      }).query,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _idToken = null;
      _refreshToken = null;
      _tokenExpiresAt = null;
      await _signInAnonymously();
      return;
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveAuthResponse({
      'idToken': decoded['id_token'],
      'refreshToken': decoded['refresh_token'],
      'expiresIn': decoded['expires_in'],
    });
  }

  Future<void> _saveAuthResponse(Map<String, dynamic> decoded) async {
    _idToken = decoded['idToken']?.toString();
    _refreshToken = decoded['refreshToken']?.toString();
    final expiresIn = int.tryParse((decoded['expiresIn'] ?? '3600').toString());
    _tokenExpiresAt = DateTime.now().add(Duration(seconds: expiresIn ?? 3600));

    await store?.set('firebaseAnonymousAuth', {
      'idToken': _idToken,
      'refreshToken': _refreshToken,
      'expiresAt': _tokenExpiresAt?.toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }
}
