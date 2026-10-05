import '../core/date_mapper.dart';

class InstalledApp {
  const InstalledApp({
    required this.id,
    required this.name,
    this.publisher = '',
    this.version = '',
    this.installDate = '',
    this.installLocation = '',
    this.iconKey = '',
    this.lastSeenAt,
  });

  final String id;
  final String name;
  final String publisher;
  final String version;
  final String installDate;
  final String installLocation;
  final String iconKey;
  final DateTime? lastSeenAt;

  factory InstalledApp.fromMap(String id, Map<String, dynamic> map) {
    return InstalledApp(
      id: id,
      name: (map['name'] ?? map['displayName'] ?? 'Application').toString(),
      publisher: (map['publisher'] ?? '').toString(),
      version: (map['version'] ?? '').toString(),
      installDate: (map['installDate'] ?? '').toString(),
      installLocation: (map['installLocation'] ?? '').toString(),
      iconKey: (map['iconKey'] ?? map['name'] ?? '').toString(),
      lastSeenAt:
          map['lastSeenAt'] == null ? null : dateFromAny(map['lastSeenAt']),
    );
  }
}
