import '../core/date_mapper.dart';

class RemoteFileListing {
  const RemoteFileListing({
    required this.path,
    required this.items,
    this.parentPath,
  });

  final String path;
  final String? parentPath;
  final List<RemoteFileItem> items;

  factory RemoteFileListing.fromPayload(Map<String, dynamic> payload) {
    final source = payload['items'] == null && payload['payload'] is Map
        ? Map<String, dynamic>.from(payload['payload'] as Map)
        : payload;
    final itemsRaw = source['items'];
    final items = itemsRaw is List
        ? itemsRaw
            .whereType<Map>()
            .map((item) => RemoteFileItem.fromMap(item.cast<String, dynamic>()))
            .toList()
        : <RemoteFileItem>[];
    return RemoteFileListing(
      path: (source['path'] ?? 'roots').toString(),
      parentPath: source['parentPath']?.toString(),
      items: items,
    );
  }
}

class RemoteFileItem {
  const RemoteFileItem({
    required this.name,
    required this.path,
    required this.type,
    required this.modifiedAt,
    this.extension = '',
    this.size = 0,
    this.isHidden = false,
    this.iconKey = 'file',
  });

  final String name;
  final String path;
  final String type;
  final String extension;
  final int size;
  final DateTime modifiedAt;
  final bool isHidden;
  final String iconKey;

  bool get isDirectory => type == 'directory' || type == 'drive';
  bool get isDrive => type == 'drive';

  factory RemoteFileItem.fromMap(Map<String, dynamic> map) {
    return RemoteFileItem(
      name: (map['name'] ?? '').toString(),
      path: (map['path'] ?? '').toString(),
      type: (map['type'] ?? 'file').toString(),
      extension: (map['extension'] ?? '').toString(),
      size: int.tryParse('${map['size'] ?? 0}') ?? 0,
      modifiedAt: dateFromAny(map['modifiedAt']),
      isHidden: map['isHidden'] == true,
      iconKey: (map['iconKey'] ?? 'file').toString(),
    );
  }
}
