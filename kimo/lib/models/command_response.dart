import '../core/date_mapper.dart';

class CommandResponse {
  const CommandResponse({
    required this.id,
    required this.commandId,
    required this.success,
    required this.message,
    required this.createdAt,
    this.phase,
    this.commandType,
    this.deviceId,
    this.payload = const {},
  });

  final String id;
  final String commandId;
  final bool success;
  final String message;
  final DateTime createdAt;
  final String? phase;
  final String? commandType;
  final String? deviceId;
  final Map<String, dynamic> payload;

  bool get isReceivedPhase => phase == 'received' || phase == 'ack';
  bool get isFinalPhase =>
      phase == null || phase == 'final' || phase == 'done' || phase == 'error';

  factory CommandResponse.fromMap(String id, Map<String, dynamic> map) {
    final rawPayload = map['payload'];
    return CommandResponse(
      id: id,
      commandId: (map['commandId'] ?? map['commandID'] ?? '').toString(),
      success: map['success'] == true,
      message:
          (map['message'] ?? map['resultMessage'] ?? map['ackMessage'] ?? '')
              .toString(),
      createdAt: dateFromAny(
          map['createdAt'] ?? map['answeredAt'] ?? map['updatedAt']),
      phase: map['phase']?.toString(),
      commandType: (map['type'] ?? map['commandType'])?.toString(),
      deviceId: map['deviceId']?.toString(),
      payload:
          rawPayload is Map ? Map<String, dynamic>.from(rawPayload) : const {},
    );
  }
}
