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

  bool get isFirebaseConfigured =>
      config.projectId.trim().isNotEmpty && config.apiKey.trim().isNotEmpty;

  static const Duration _httpTimeout = Duration(seconds: 15);

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
    if (!isFirebaseConfigured) return false;
    try {
      final response = await _get(_uri(path), headers: await _headers());
      if (response.statusCode == 200) return true;
      if (response.statusCode == 404) return false;
    } catch (_) {}
    return false;
  }

  Future<void> setDocument(String path, Map<String, dynamic> data) async {
    if (!isFirebaseConfigured) return;
    try {
      final maskQuery = data.keys
          .map((k) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent(k)}')
          .join('&');
      final baseUrl = _uri(path).toString();
      final sep = baseUrl.contains('?') ? '&' : '?';
      final url = maskQuery.isEmpty ? baseUrl : '$baseUrl$sep$maskQuery';

      await _patch(
        Uri.parse(url),
        headers: await _headers(jsonBody: true),
        body: jsonEncode({'fields': _toFields(data)}),
      );
    } catch (_) {}
  }

  Future<void> createDocumentWithId(
    String collectionPath,
    String documentId,
    Map<String, dynamic> data,
  ) async {
    if (!isFirebaseConfigured) return;
    try {
      final uri = _uri(collectionPath, {'documentId': documentId});
      final response = await _post(
        uri,
        headers: await _headers(jsonBody: true),
        body: jsonEncode({'fields': _toFields(data)}),
      );

      if (response.statusCode == 409) {
        await setDocument('$collectionPath/$documentId', data);
      }
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> listDocuments(
      String collectionPath) async {
    if (!isFirebaseConfigured) return [];
    try {
      final response =
          await _get(_uri(collectionPath), headers: await _headers());
      if (response.statusCode == 404) return [];
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return [];
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = (decoded['documents'] as List?) ?? const [];
      return docs
          .whereType<Map>()
          .map((doc) => _flattenDocument(doc.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteDocument(String path) async {
    if (!isFirebaseConfigured) return;
    try {
      await _delete(_uri(path), headers: await _headers());
    } catch (_) {}
  }

  Future<void> registerDevice({
    required String deviceId,
    required String name,
    required String os,
    required String windowsUser,
    required String appVersion,
  }) async {
    final now = DateTime.now().toIso8601String();
    await setDocument('devices/$deviceId', {
      'name': name,
      'os': os,
      'windowsUser': windowsUser,
      'appVersion': appVersion,
      'linkedUserIds': [config.demoUserId],
      'createdAt': now,
      'updatedAt': now,
      'lastAgentStartedAt': now,
      'lastSeenAt': now,
    });
  }

  Future<void> updateHeartbeat(String deviceId) async {
    await setDocument('devices/$deviceId', {
      'lastSeenAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> syncOpenApps(String deviceId, List<OpenAppInfo> apps) async {
    if (!isFirebaseConfigured) return;
    final now = DateTime.now().toIso8601String();
    for (final app in apps) {
      await createDocumentWithId(
        'open_apps/$deviceId/items',
        app.processId.toString(),
        {
          'processId': app.processId.toString(),
          'appName': app.appName,
          'appPath': app.appPath,
          'openedAt': now,
          'status': 'running',
          'windowTitle': app.windowTitle,
          'pageTitle': app.pageTitle,
          'url': app.url,
          'siteName': app.siteName,
          'browserName': app.browserName,
          'updatedAt': now,
        },
      );
    }
  }

  Future<void> syncBlockedItems(
    String deviceId,
    List<Map<String, dynamic>> items,
  ) async {
    if (!isFirebaseConfigured) return;
    for (final item in items) {
      final id = _safeDocumentId(
          (item['id'] ?? item['target'] ?? item['domain'] ?? '').toString());
      await setDocument('blocked_items/$deviceId/items/$id', {
        ...item,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> syncInstalledApps(
    String deviceId,
    List<Map<String, dynamic>> apps,
  ) async {
    if (!isFirebaseConfigured) return;
    for (final app in apps) {
      final name = (app['name'] ?? app['displayName'] ?? '').toString();
      if (name.trim().isEmpty) continue;
      final docId = _safeDocumentId(name);
      await setDocument('installed_apps/$deviceId/items/$docId', {
        ...app,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
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
      'expiresAt': expiresAt.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
      'used': false,
    });
  }

  Future<List<RemoteCommand>> listenCommands(String deviceId) async {
    final docs = await listDocuments('commands/$deviceId/items');
    final commands = <RemoteCommand>[];

    for (final map in docs) {
      final status = (map['status'] ?? 'pending').toString().toLowerCase();
      if (status != 'pending') continue;

      final id = map['id']?.toString() ?? '';
      final type = map['type']?.toString() ?? '';
      final payloadRaw = map['payload'];
      final payload = payloadRaw is Map
          ? Map<String, dynamic>.from(payloadRaw)
          : <String, dynamic>{};
      final createdAt =
          DateTime.tryParse((map['createdAt'] ?? '').toString()) ??
              DateTime.now();
      final executeAtRaw = map['executeAt'];
      final executeAt = executeAtRaw == null
          ? null
          : DateTime.tryParse(executeAtRaw.toString());

      commands.add(RemoteCommand(
        id: id,
        type: type,
        payload: payload,
        createdAt: createdAt,
        executeAt: executeAt,
      ));
    }

    return commands;
  }

  Future<void> markCommandReceived(String deviceId, String commandId) async {
    await setDocument('commands/$deviceId/items/$commandId', {
      'status': 'received',
      'receivedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> markCommandDone(
    String deviceId,
    String commandId, {
    required bool success,
    required String resultMessage,
    Map<String, dynamic>? resultPayload,
  }) async {
    await setDocument('commands/$deviceId/items/$commandId', {
      'status': success ? 'done' : 'error',
      'success': success,
      'resultMessage': resultMessage,
      if (resultPayload != null) 'payload': resultPayload,
      'finishedAt': DateTime.now().toIso8601String(),
    });

    await createDocumentWithId(
      'command_results/$deviceId/items',
      commandId,
      {
        'commandId': commandId,
        'success': success,
        'message': resultMessage,
        'phase': 'final',
        if (resultPayload != null) 'payload': resultPayload,
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> createNotification({
    required String deviceId,
    required String title,
    required String message,
    required String type,
    String severity = 'info',
    Map<String, dynamic>? payload,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await createDocumentWithId('notifications/$deviceId/items', id, {
      'title': title,
      'message': message,
      'type': type,
      'severity': severity,
      'read': false,
      if (payload != null) 'payload': payload,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> createPermissionRequest({
    required String id,
    required String deviceId,
    required String ruleId,
    required String path,
    required String openedPath,
  }) async {
    final createdAt = DateTime.now().toIso8601String();
    await createDocumentWithId('permission_requests/$deviceId/items', id, {
      'id': id,
      'deviceId': deviceId,
      'ruleId': ruleId,
      'path': path,
      'openedPath': openedPath,
      'type': 'open_path',
      'status': 'pending',
      'createdAt': createdAt,
    });
    try {
      await createNotification(
        deviceId: deviceId,
        title: 'طلب إذن جديد',
        message: 'يوجد طلب فتح مسار محمي: $openedPath',
        type: 'permission_request',
        severity: 'warning',
        payload: {
          'requestId': id,
          'path': path,
          'openedPath': openedPath,
          'ruleId': ruleId,
        },
      );
    } catch (_) {}
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

  Map<String, dynamic> _flattenDocument(Map<String, dynamic> doc) {
    final name = (doc['name'] ?? '').toString();
    final id = name.split('/').last;
    final fields = (doc['fields'] as Map?)?.cast<String, dynamic>() ?? const {};
    return {
      'id': id,
      ..._fromFields(fields),
    };
  }

  bool _looksLikeIsoDate(String value) {
    return RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}').hasMatch(value);
  }

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) {
    return http.get(uri, headers: headers).timeout(_httpTimeout);
  }

  Future<http.Response> _post(Uri uri,
      {Map<String, String>? headers, Object? body}) {
    return http.post(uri, headers: headers, body: body).timeout(_httpTimeout);
  }

  Future<http.Response> _patch(Uri uri,
      {Map<String, String>? headers, Object? body}) {
    return http.patch(uri, headers: headers, body: body).timeout(_httpTimeout);
  }

  Future<http.Response> _delete(Uri uri, {Map<String, String>? headers}) {
    return http.delete(uri, headers: headers).timeout(_httpTimeout);
  }

  Future<Map<String, String>> _headers({bool jsonBody = false}) async {
    final map = <String, String>{};
    if (jsonBody) map['Content-Type'] = 'application/json';
    final token = await _getToken();
    if (token != null && token.isNotEmpty) {
      map['Authorization'] = 'Bearer $token';
    }
    return map;
  }

  Future<String?> _getToken() async {
    if (_anonymousAuthUnavailable || config.apiKey.isEmpty) return null;
    await _loadCachedAuth();

    if (_idToken != null &&
        _tokenExpiresAt != null &&
        _tokenExpiresAt!.isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
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

    final response = await _post(
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

    final response = await _post(
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
