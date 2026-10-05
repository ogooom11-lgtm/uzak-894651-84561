import '../core/command_type.dart';
import '../core/date_mapper.dart';

class RemoteCommand {
  const RemoteCommand({
    required this.id,
    required this.deviceId,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.payload,
    this.executeAt,
    this.createdBy,
  });

  final String id;
  final String deviceId;
  final CommandType type;
  final String status;
  final DateTime createdAt;
  final DateTime? executeAt;
  final String? createdBy;
  final Map<String, dynamic> payload;

  factory RemoteCommand.fromMap(String id, Map<String, dynamic> map) {
    return RemoteCommand(
      id: id,
      deviceId: (map['deviceId'] ?? '').toString(),
      type: CommandTypeX.fromWireName((map['type'] ?? '').toString()),
      status: (map['status'] ?? 'pending').toString(),
      createdAt: dateFromAny(map['createdAt']),
      executeAt:
          map['executeAt'] == null ? null : dateFromAny(map['executeAt']),
      createdBy: map['createdBy']?.toString(),
      payload: Map<String, dynamic>.from(map['payload'] ?? const {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'type': type.wireName,
      'status': status,
      'createdAt': dateToFirestore(createdAt),
      'executeAt': nullableDateToFirestore(executeAt),
      'createdBy': createdBy,
      'payload': payload,
    };
  }
}
