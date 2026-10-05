import '../core/date_mapper.dart';

class InstallRequest {
  const InstallRequest({
    required this.id,
    required this.deviceId,
    required this.fileName,
    required this.filePath,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String deviceId;
  final String fileName;
  final String filePath;
  final String status;
  final DateTime createdAt;

  factory InstallRequest.fromMap(String id, Map<String, dynamic> map) {
    return InstallRequest(
      id: id,
      deviceId: (map['deviceId'] ?? '').toString(),
      fileName: (map['fileName'] ?? 'setup.exe').toString(),
      filePath: (map['filePath'] ?? '').toString(),
      status: (map['status'] ?? 'pending').toString(),
      createdAt: dateFromAny(map['createdAt']),
    );
  }
}
