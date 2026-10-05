import '../core/date_mapper.dart';

class DeviceNotification {
  const DeviceNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    this.severity = 'info',
    this.read = false,
    this.payload = const {},
  });

  final String id;
  final String title;
  final String message;
  final String type;
  final String severity;
  final bool read;
  final DateTime createdAt;
  final Map<String, dynamic> payload;

  factory DeviceNotification.fromMap(String id, Map<String, dynamic> map) {
    final payload = map['payload'];
    return DeviceNotification(
      id: id,
      title: (map['title'] ?? 'تنبيه').toString(),
      message: (map['message'] ?? '').toString(),
      type: (map['type'] ?? 'info').toString(),
      severity: (map['severity'] ?? 'info').toString(),
      read: map['read'] == true,
      createdAt: dateFromAny(map['createdAt'] ?? map['updatedAt']),
      payload: payload is Map ? Map<String, dynamic>.from(payload) : const {},
    );
  }
}
