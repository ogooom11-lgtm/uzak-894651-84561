import 'package:crypto/crypto.dart';
import 'dart:convert';

class PathRule {
  final String id;
  final String path;
  final String lockType; // blocked, password, permissionRequired, readOnly
  final String? passwordHash;
  final bool blockOpen;
  final bool blockDelete;
  final bool blockCopy;
  final bool blockMove;
  final bool blockRename;
  final bool blockModify;
  final bool readOnly;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PathRule({
    required this.id,
    required this.path,
    required this.lockType,
    this.passwordHash,
    this.blockOpen = true,
    this.blockDelete = false,
    this.blockCopy = false,
    this.blockMove = false,
    this.blockRename = false,
    this.blockModify = false,
    this.readOnly = false,
    required this.createdAt,
    required this.updatedAt,
  });

  bool verifyPassword(String password) {
    if (passwordHash == null || passwordHash!.isEmpty) return false;
    return hashPassword(password) == passwordHash;
  }

  static String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'lockType': lockType,
        'passwordHash': passwordHash,
        'blockOpen': blockOpen,
        'blockDelete': blockDelete,
        'blockCopy': blockCopy,
        'blockMove': blockMove,
        'blockRename': blockRename,
        'blockModify': blockModify,
        'readOnly': readOnly,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory PathRule.fromJson(Map<String, dynamic> json) {
    return PathRule(
      id: (json['id'] ?? DateTime.now().microsecondsSinceEpoch.toString())
          .toString(),
      path: (json['path'] ?? '').toString(),
      lockType: (json['lockType'] ?? 'blocked').toString(),
      passwordHash: json['passwordHash']?.toString(),
      blockOpen: json['blockOpen'] == true,
      blockDelete: json['blockDelete'] == true,
      blockCopy: json['blockCopy'] == true,
      blockMove: json['blockMove'] == true,
      blockRename: json['blockRename'] == true,
      blockModify: json['blockModify'] == true,
      readOnly: json['readOnly'] == true,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  PathRule copyWith({
    String? id,
    String? path,
    String? lockType,
    String? passwordHash,
    bool? blockOpen,
    bool? blockDelete,
    bool? blockCopy,
    bool? blockMove,
    bool? blockRename,
    bool? blockModify,
    bool? readOnly,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PathRule(
      id: id ?? this.id,
      path: path ?? this.path,
      lockType: lockType ?? this.lockType,
      passwordHash: passwordHash ?? this.passwordHash,
      blockOpen: blockOpen ?? this.blockOpen,
      blockDelete: blockDelete ?? this.blockDelete,
      blockCopy: blockCopy ?? this.blockCopy,
      blockMove: blockMove ?? this.blockMove,
      blockRename: blockRename ?? this.blockRename,
      blockModify: blockModify ?? this.blockModify,
      readOnly: readOnly ?? this.readOnly,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
