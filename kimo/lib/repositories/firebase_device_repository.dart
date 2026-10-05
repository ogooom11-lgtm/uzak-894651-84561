import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../core/command_type.dart';
import '../core/date_mapper.dart';
import '../models/blocked_item.dart';
import '../models/command_response.dart';
import '../models/install_request.dart';
import '../models/installed_app.dart';
import '../models/log_entry.dart';
import '../models/open_app.dart';
import '../models/path_rule.dart';
import '../models/pc_device.dart';
import '../models/permission_request.dart';
import '../models/remote_file_item.dart';
import '../models/screenshot_item.dart';
import '../services/firebase_paths.dart';
import '../services/local_linked_devices_store.dart';
import 'device_repository.dart';

class FirebaseDeviceRepository implements DeviceRepository {
  FirebaseDeviceRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    LocalLinkedDevicesStore? localStore,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _localStore = localStore ?? LocalLinkedDevicesStore();

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final LocalLinkedDevicesStore _localStore;
  final _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> _items(
      String root, String deviceId) {
    return _db.collection(root).doc(deviceId).collection(FirebasePaths.items);
  }

  @override
  Stream<List<PcDevice>> watchDevices(String userId) {
    final controller = StreamController<List<PcDevice>>();
    StreamSubscription<List<PcDevice>>? localSubscription;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? cloudSubscription;

    List<PcDevice> cachedDevices = const [];

    List<PcDevice> sortDevices(Iterable<PcDevice> devices) {
      return List<PcDevice>.from(devices)
        ..sort((a, b) => a.name.compareTo(b.name));
    }

    void emitCached() {
      if (!controller.isClosed) controller.add(sortDevices(cachedDevices));
    }

    localSubscription = _localStore.watchDevices(userId).listen((localDevices) {
      cachedDevices = sortDevices(localDevices);
      emitCached();

      cloudSubscription?.cancel();
      cloudSubscription = null;

      if (cachedDevices.isEmpty) return;

      cloudSubscription = _db
          .collection(FirebasePaths.devices)
          .where('linkedUserIds', arrayContains: userId)
          .snapshots()
          .listen((snapshot) {
        final localIds = cachedDevices.map((device) => device.id).toSet();
        final mergedById = <String, PcDevice>{
          for (final device in cachedDevices) device.id: device,
        };

        for (final doc in snapshot.docs) {
          if (!localIds.contains(doc.id)) continue;
          mergedById[doc.id] = PcDevice.fromMap(doc.id, doc.data());
        }

        final merged = sortDevices(mergedById.values);
        cachedDevices = merged;
        if (!controller.isClosed) controller.add(merged);
        unawaited(_localStore.saveDevices(userId, merged));
      }, onError: (_) {
        emitCached();
      });
    }, onError: controller.addError);

    controller.onCancel = () async {
      await localSubscription?.cancel();
      await cloudSubscription?.cancel();
    };

    return controller.stream;
  }

  @override
  Stream<List<OpenApp>> watchOpenApps(String deviceId) {
    return _items(FirebasePaths.openApps, deviceId).snapshots().map((snapshot) {
      final apps = snapshot.docs
          .map((doc) => OpenApp.fromMap(doc.id, doc.data()))
          .toList();
      apps.sort((a, b) => b.openedAt.compareTo(a.openedAt));
      return apps;
    });
  }

  @override
  Stream<List<PathRule>> watchPathRules(String deviceId) {
    return _items(FirebasePaths.pathRules, deviceId)
        .snapshots()
        .map((snapshot) {
      final rules = snapshot.docs
          .map((doc) => PathRule.fromMap(doc.id, doc.data()))
          .toList();
      rules.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return rules;
    });
  }

  @override
  Stream<List<PermissionRequest>> watchPermissionRequests(String deviceId) {
    // لا نستخدم where + orderBy هنا حتى لا تتوقف الصفحة بسبب Index مفقود في Firestore.
    return _items(FirebasePaths.permissionRequests, deviceId)
        .snapshots()
        .map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => PermissionRequest.fromMap(doc.id, doc.data()))
          .where((item) => item.status == 'pending')
          .toList();
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return requests;
    });
  }

  @override
  Stream<List<InstallRequest>> watchInstallRequests(String deviceId) {
    // لا نستخدم where + orderBy هنا حتى لا تتوقف الصفحة بسبب Index مفقود في Firestore.
    return _items(FirebasePaths.installRequests, deviceId)
        .snapshots()
        .map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => InstallRequest.fromMap(doc.id, doc.data()))
          .where((item) => item.status == 'pending')
          .toList();
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return requests;
    });
  }

  @override
  Stream<List<InstalledApp>> watchInstalledApps(String deviceId) {
    return _items(FirebasePaths.installedApps, deviceId)
        .snapshots()
        .map((snapshot) {
      final apps = snapshot.docs
          .map((doc) => InstalledApp.fromMap(doc.id, doc.data()))
          .toList();
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return apps;
    });
  }

  @override
  Stream<List<BlockedItem>> watchBlockedItems(String deviceId) {
    return _items(FirebasePaths.blockedItems, deviceId)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs
          .map((doc) => BlockedItem.fromMap(doc.id, doc.data()))
          .toList();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    });
  }

  @override
  Stream<List<ScreenshotItem>> watchScreenshots(String deviceId) {
    return _items(FirebasePaths.screenshots, deviceId)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs
          .map((doc) => ScreenshotItem.fromMap(doc.id, doc.data()))
          .toList();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    });
  }

  @override
  Stream<List<LogEntry>> watchRequestedLogs(String deviceId) {
    return _items(FirebasePaths.requestedLogs, deviceId)
        .limit(300)
        .snapshots()
        .map((snapshot) {
      final logs = snapshot.docs
          .map((doc) => LogEntry.fromMap(doc.id, doc.data()))
          .toList();
      logs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return logs;
    });
  }

  @override
  Stream<List<CommandResponse>> watchCommandResponses(String deviceId) {
    return _items(FirebasePaths.responses, deviceId)
        .limit(500)
        .snapshots()
        .map((snapshot) {
      final responses = snapshot.docs
          .map((doc) => CommandResponse.fromMap(doc.id, doc.data()))
          .toList();
      responses.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return responses;
    });
  }

  @override
  Future<void> pairDeviceByQrPayload({
    required String userId,
    required String qrPayload,
  }) async {
    final data = jsonDecode(qrPayload) as Map<String, dynamic>;
    final deviceId = data['deviceId']?.toString();
    final token = data['pairingToken']?.toString();
    final expiresAt = data['expiresAt'];

    if (deviceId == null || token == null) {
      throw Exception('رمز QR غير صالح: deviceId أو pairingToken مفقود.');
    }

    final expiry = dateFromAny(expiresAt, fallback: DateTime.now());
    if (expiry.isBefore(DateTime.now())) {
      throw Exception('انتهت صلاحية رمز الربط. اطلب رمز QR جديد من الكمبيوتر.');
    }

    Map<String, dynamic> tokenData = const {};
    try {
      final tokenDoc =
          await _db.collection(FirebasePaths.pairingTokens).doc(token).get();
      if (tokenDoc.exists) {
        tokenData = tokenDoc.data() ?? const {};
        if (tokenData['deviceId']?.toString() != deviceId) {
          throw Exception('رمز الربط لا يطابق هذا الجهاز.');
        }
      }
    } catch (_) {
      final uploaded = data['pairingTokenUploaded'] == true;
      if (uploaded) rethrow;
    }

    Map<String, dynamic> deviceData = <String, dynamic>{};
    try {
      await _db.collection(FirebasePaths.devices).doc(deviceId).set({
        'name': data['name'] ?? data['computerName'] ?? deviceId,
        'os': data['os'] ?? 'Windows',
        'appVersion': data['appVersion'] ?? '1.0.0',
        'linkedUserIds': FieldValue.arrayUnion([userId]),
        'lastPairedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _db
          .collection(FirebasePaths.users)
          .doc(userId)
          .collection(FirebasePaths.devices)
          .doc(deviceId)
          .set({
        'deviceId': deviceId,
        'pairedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final deviceDoc =
          await _db.collection(FirebasePaths.devices).doc(deviceId).get();
      deviceData = deviceDoc.data() ?? <String, dynamic>{};
    } catch (_) {
      deviceData = <String, dynamic>{};
    }

    final linkedUserIds = {
      ...((deviceData['linkedUserIds'] as List?) ?? const <dynamic>[])
          .map((value) => value.toString()),
      userId,
    }.toList();
    final device = PcDevice.fromMap(deviceId, {
      ...deviceData,
      'name': deviceData['name'] ??
          data['name'] ??
          data['computerName'] ??
          deviceId,
      'os': deviceData['os'] ?? data['os'] ?? 'Windows',
      'appVersion': deviceData['appVersion'] ?? data['appVersion'] ?? '1.0.0',
      'linkedUserIds': linkedUserIds,
    });
    await _localStore.upsertDevice(userId, device);
  }

  @override
  Future<void> removeDevice({
    required String userId,
    required String deviceId,
  }) async {
    await _localStore.removeDevice(userId, deviceId);
    try {
      await _db.collection(FirebasePaths.devices).doc(deviceId).set({
        'linkedUserIds': FieldValue.arrayRemove([userId]),
        'unlinkedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _db
          .collection(FirebasePaths.users)
          .doc(userId)
          .collection(FirebasePaths.devices)
          .doc(deviceId)
          .delete();
    } catch (_) {}
  }

  @override
  Future<String> sendCommand({
    required String userId,
    required String deviceId,
    required CommandType type,
    Map<String, dynamic> payload = const {},
    DateTime? executeAt,
  }) async {
    final id = _uuid.v4();
    await _items(FirebasePaths.commands, deviceId).doc(id).set({
      'deviceId': deviceId,
      'type': type.wireName,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'executeAt': executeAt == null ? null : Timestamp.fromDate(executeAt),
      'createdBy': userId,
      'payload': payload,
    });
    return id;
  }

  @override
  Future<CommandResponse?> waitForCommandResponse({
    required String deviceId,
    required String commandId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      return await _items(FirebasePaths.responses, deviceId)
          .where('commandId', isEqualTo: commandId)
          .snapshots()
          .map((snapshot) {
            final responses = snapshot.docs
                .map((doc) => CommandResponse.fromMap(doc.id, doc.data()))
                .toList();
            responses.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            for (final response in responses) {
              if (response.phase == 'final' ||
                  response.phase == 'done' ||
                  response.phase == 'error') {
                return response;
              }
            }
            for (final response in responses) {
              if (!response.isReceivedPhase) return response;
            }
            return null;
          })
          .firstWhere((response) => response != null)
          .timeout(timeout);
    } on TimeoutException {
      return null;
    }
  }

  @override
  Future<RemoteFileListing> browsePath({
    required String userId,
    required String deviceId,
    required String path,
  }) async {
    final commandId = await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: CommandType.browsePath,
      payload: {'path': path},
    );
    final response = await waitForCommandResponse(
      deviceId: deviceId,
      commandId: commandId,
      timeout: const Duration(seconds: 20),
    );
    if (response == null) {
      throw Exception('لم يصل رد من الكمبيوتر خلال المهلة.');
    }
    if (!response.success) {
      throw Exception(response.message);
    }
    return RemoteFileListing.fromPayload(response.payload);
  }

  @override
  Future<CommandResponse?> runFileCommand({
    required String userId,
    required String deviceId,
    required CommandType type,
    required String path,
    Map<String, dynamic> payload = const {},
  }) async {
    final commandId = await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: type,
      payload: {'path': path, ...payload},
    );
    return waitForCommandResponse(
      deviceId: deviceId,
      commandId: commandId,
      timeout: const Duration(seconds: 25),
    );
  }

  @override
  Future<void> savePathRule({
    required String userId,
    required String deviceId,
    required PathRule rule,
  }) async {
    await _items(FirebasePaths.pathRules, deviceId)
        .doc(rule.id)
        .set(rule.toMap());
    await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: CommandType.addPathRule,
      payload: {'ruleId': rule.id, ...rule.toMap()},
    );
  }

  @override
  Future<void> removePathRule({
    required String userId,
    required String deviceId,
    required String ruleId,
  }) async {
    await _items(FirebasePaths.pathRules, deviceId).doc(ruleId).delete();
    await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: CommandType.removePathRule,
      payload: {'ruleId': ruleId},
    );
  }

  @override
  Future<void> answerPermission({
    required String userId,
    required String deviceId,
    required String requestId,
    required bool approve,
    Duration? duration,
    bool always = false,
  }) async {
    await _items(FirebasePaths.permissionRequests, deviceId)
        .doc(requestId)
        .set({
      'status': approve ? 'approved' : 'rejected',
      'answeredAt': FieldValue.serverTimestamp(),
      'answeredBy': userId,
      'durationSeconds': duration?.inSeconds,
      'always': always,
    }, SetOptions(merge: true));

    await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: approve
          ? CommandType.approvePermission
          : CommandType.rejectPermission,
      payload: {
        'requestId': requestId,
        'durationSeconds': duration?.inSeconds,
        'always': always,
      },
    );
  }

  @override
  Future<void> answerInstall({
    required String userId,
    required String deviceId,
    required String requestId,
    required bool approve,
    Duration? duration,
    bool always = false,
  }) async {
    await _items(FirebasePaths.installRequests, deviceId).doc(requestId).set({
      'status': approve ? 'approved' : 'rejected',
      'answeredAt': FieldValue.serverTimestamp(),
      'answeredBy': userId,
      'durationSeconds': duration?.inSeconds,
      'always': always,
    }, SetOptions(merge: true));

    await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: approve ? CommandType.approveInstall : CommandType.rejectInstall,
      payload: {
        'requestId': requestId,
        'durationSeconds': duration?.inSeconds,
        'always': always,
      },
    );
  }

  @override
  Future<void> deleteScreenshot({
    required String deviceId,
    required ScreenshotItem screenshot,
  }) async {
    await _items(FirebasePaths.screenshots, deviceId)
        .doc(screenshot.id)
        .delete();
    final storagePath = screenshot.storagePath ?? '';
    final looksLikeFirebaseStorage = storagePath.isNotEmpty &&
        !storagePath.contains(r':\') &&
        !storagePath.startsWith('file:') &&
        !storagePath.startsWith('google_drive/') &&
        !storagePath.startsWith(r'\\');
    if (looksLikeFirebaseStorage) {
      await _storage.ref(storagePath).delete();
    }
  }

  @override
  Future<void> clearRequestedLogs(String deviceId) async {
    final snap =
        await _items(FirebasePaths.requestedLogs, deviceId).limit(500).get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  @override
  Future<void> clearCommandResponses(String deviceId) async {
    QuerySnapshot<Map<String, dynamic>> snap;
    do {
      snap = await _items(FirebasePaths.responses, deviceId).limit(500).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } while (snap.docs.length == 500);
  }
}
