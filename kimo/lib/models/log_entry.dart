import '../core/date_mapper.dart';

class LogEntry {
  const LogEntry({
    required this.id,
    required this.type,
    required this.message,
    required this.createdAt,
    this.target,
    this.payload = const {},
  });

  final String id;
  final String type;
  final String message;
  final String? target;
  final DateTime createdAt;
  final Map<String, dynamic> payload;

  factory LogEntry.fromMap(String id, Map<String, dynamic> map) {
    return LogEntry(
      id: id,
      type: (map['type'] ?? 'general').toString(),
      message: (map['message'] ?? '').toString(),
      target: map['target']?.toString(),
      createdAt: dateFromAny(map['createdAt']),
      payload: Map<String, dynamic>.from(map['payload'] ?? const {}),
    );
  }
}
