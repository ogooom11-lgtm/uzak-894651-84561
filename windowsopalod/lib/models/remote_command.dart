class RemoteCommand {
  final String id;
  final String type;
  final String status;
  final Map<String, dynamic> payload;
  final String createdBy;

  /// وقت إنشاء الأمر في Firebase.
  /// يستخدمه تطبيق الكمبيوتر لتجاهل الأوامر القديمة.
  final DateTime? createdAt;

  /// وقت التنفيذ المطلوب. إذا كان في المستقبل يبقى الأمر Pending حتى يحين وقته.
  final DateTime? executeAt;

  const RemoteCommand({
    required this.id,
    required this.type,
    required this.status,
    required this.payload,
    required this.createdBy,
    this.createdAt,
    this.executeAt,
  });
}
