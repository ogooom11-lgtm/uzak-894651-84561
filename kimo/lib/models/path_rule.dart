import '../core/date_mapper.dart';

class PathRule {
  const PathRule({
    required this.id,
    required this.path,
    required this.lockType,
    required this.createdAt,
    required this.updatedAt,
    this.blockOpen = false,
    this.blockDelete = false,
    this.blockCopy = false,
    this.blockMove = false,
    this.blockRename = false,
    this.blockModify = false,
    this.readOnly = false,
    this.permissionEveryTime = false,
    this.lockMinutes,
    this.password,
  });

  final String id;
  final String path;
  final String lockType;
  final bool blockOpen;
  final bool blockDelete;
  final bool blockCopy;
  final bool blockMove;
  final bool blockRename;
  final bool blockModify;
  final bool readOnly;
  final bool permissionEveryTime;
  final int? lockMinutes;
  final String? password;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory PathRule.fromMap(String id, Map<String, dynamic> map) {
    return PathRule(
      id: id,
      path: (map['path'] ?? '').toString(),
      lockType: (map['lockType'] ?? 'permissionRequired').toString(),
      blockOpen: map['blockOpen'] == true,
      blockDelete: map['blockDelete'] == true,
      blockCopy: map['blockCopy'] == true,
      blockMove: map['blockMove'] == true,
      blockRename: map['blockRename'] == true,
      blockModify: map['blockModify'] == true,
      readOnly: map['readOnly'] == true,
      permissionEveryTime: map['permissionEveryTime'] == true,
      lockMinutes: map['lockMinutes'] == null
          ? null
          : int.tryParse('${map['lockMinutes']}'),
      password: map['password']?.toString(),
      createdAt: dateFromAny(map['createdAt']),
      updatedAt: dateFromAny(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'lockType': lockType,
      'blockOpen': blockOpen,
      'blockDelete': blockDelete,
      'blockCopy': blockCopy,
      'blockMove': blockMove,
      'blockRename': blockRename,
      'blockModify': blockModify,
      'readOnly': readOnly,
      'permissionEveryTime': permissionEveryTime,
      'lockMinutes': lockMinutes,
      if (password != null && password!.isNotEmpty) 'password': password,
      'createdAt': dateToFirestore(createdAt),
      'updatedAt': dateToFirestore(updatedAt),
    };
  }
}
