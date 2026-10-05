import '../core/date_mapper.dart';

class BlockedItem {
  const BlockedItem({
    required this.id,
    required this.type,
    required this.target,
    required this.createdAt,
    this.label = '',
    this.appPath = '',
    this.lockType = 'blocked',
    this.allowedUntil,
  });

  final String id;
  final String type;
  final String target;
  final String label;
  final String appPath;
  final String lockType;
  final DateTime createdAt;
  final DateTime? allowedUntil;

  bool get isTemporarilyAllowed =>
      allowedUntil != null && allowedUntil!.isAfter(DateTime.now());

  factory BlockedItem.fromMap(String id, Map<String, dynamic> map) {
    return BlockedItem(
      id: id,
      type: (map['type'] ?? 'app').toString(),
      target: (map['target'] ?? '').toString(),
      label: (map['label'] ?? map['appName'] ?? map['domain'] ?? '').toString(),
      appPath: (map['appPath'] ?? '').toString(),
      lockType: (map['lockType'] ?? 'blocked').toString(),
      createdAt: dateFromAny(map['createdAt']),
      allowedUntil:
          map['allowedUntil'] == null ? null : dateFromAny(map['allowedUntil']),
    );
  }
}
