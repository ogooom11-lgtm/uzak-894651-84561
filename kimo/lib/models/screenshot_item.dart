import '../core/date_mapper.dart';

class ScreenshotItem {
  const ScreenshotItem({
    required this.id,
    required this.deviceId,
    required this.imageUrl,
    required this.createdAt,
    this.storagePath,
  });

  final String id;
  final String deviceId;
  final String imageUrl;
  final String? storagePath;
  final DateTime createdAt;

  factory ScreenshotItem.fromMap(String id, Map<String, dynamic> map) {
    return ScreenshotItem(
      id: id,
      deviceId: (map['deviceId'] ?? '').toString(),
      imageUrl: (map['imageUrl'] ?? '').toString(),
      storagePath: map['storagePath']?.toString(),
      createdAt: dateFromAny(map['createdAt']),
    );
  }
}
