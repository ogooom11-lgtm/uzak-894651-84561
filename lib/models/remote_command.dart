class RemoteCommand {
  final String id;
  final String type;
  final String status;
  final Map<String, dynamic> payload;
  final String createdBy;

  /// وقت إنشاء الأمر في Firebase.
  /// يستخدمه تطبيق الكمبيوتر لتجاهل الأوامر القديمة.
  final DateTime? createdAt;

  const RemoteCommand({
    required this.id,
    required this.type,
    required this.status,
    required this.payload,
    required this.createdBy,
    this.createdAt,
  });
}
