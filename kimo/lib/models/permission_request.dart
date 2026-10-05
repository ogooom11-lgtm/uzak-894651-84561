import '../core/date_mapper.dart';

class PermissionRequest {
  const PermissionRequest({
    required this.id,
    required this.deviceId,
    required this.type,
    required this.title,
    required this.targetPath,
    required this.status,
    required this.createdAt,
    this.details,
  });

  final String id;
  final String deviceId;
  final String type;
  final String title;
  final String targetPath;
  final String status;
  final DateTime createdAt;
  final String? details;

  factory PermissionRequest.fromMap(String id, Map<String, dynamic> map) {
    return PermissionRequest(
      id: id,
      deviceId: (map['deviceId'] ?? '').toString(),
      type: (map['type'] ?? 'path_access').toString(),
      title: (map['title'] ?? 'طلب إذن').toString(),
      targetPath: (map['targetPath'] ?? map['path'] ?? '').toString(),
      status: (map['status'] ?? 'pending').toString(),
      createdAt: dateFromAny(map['createdAt']),
      details: map['details']?.toString(),
    );
  }
}
