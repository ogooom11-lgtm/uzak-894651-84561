import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class FileManagerService {
  final p.Context _paths = p.Context(style: p.Style.windows);

  Future<Map<String, dynamic>> listPath(String requestedPath) async {
    final resolved = _resolveSpecialPath(requestedPath);
    if (resolved == 'roots') {
      return {
        'path': 'roots',
        'parentPath': null,
        'items': await _listRoots(),
      };
    }

    final type = await FileSystemEntity.type(resolved);
    if (type == FileSystemEntityType.notFound) {
      throw StateError('المسار غير موجود: $resolved');
    }
    if (type != FileSystemEntityType.directory) {
      return {
        'path': resolved,
        'parentPath': _parentOf(resolved),
        'items': [await _entityToMap(File(resolved))],
      };
    }

    final dir = Directory(resolved);
    final items = <Map<String, dynamic>>[];
    await for (final entity in dir.list(followLinks: false)) {
      try {
        items.add(await _entityToMap(entity));
      } catch (_) {
        // بعض ملفات النظام قد ترفض القراءة؛ نتجاوزها حتى لا تفشل القائمة كلها.
      }
    }

    items.sort((a, b) {
      final aDir = a['type'] == 'directory';
      final bDir = b['type'] == 'directory';
      if (aDir != bDir) return aDir ? -1 : 1;
      return a['name']
          .toString()
          .toLowerCase()
          .compareTo(b['name'].toString().toLowerCase());
    });

    return {
      'path': resolved,
      'parentPath': _parentOf(resolved),
      'items': items,
    };
  }

  Future<Map<String, dynamic>> openPath(String path) async {
    final resolved = _resolveSpecialPath(path);
    final result = await Process.run('explorer.exe', [resolved]);
    return {
      'path': resolved,
      'exitCode': result.exitCode,
      'stdout': result.stdout.toString(),
      'stderr': result.stderr.toString(),
    };
  }

  Future<Map<String, dynamic>> renamePath(String path, String newName) async {
    final resolved = _resolveSpecialPath(path);
    if (newName.trim().isEmpty ||
        newName.contains(r'\') ||
        newName.contains('/')) {
      throw StateError('اسم جديد غير صالح');
    }
    final destination = _paths.join(_paths.dirname(resolved), newName.trim());
    await _renameEntity(resolved, destination);
    return {'from': resolved, 'to': destination};
  }

  Future<Map<String, dynamic>> copyPath(
      String path, String destinationDirectory) async {
    final source = _resolveSpecialPath(path);
    final destinationRoot = _resolveSpecialPath(destinationDirectory);
    final type = await FileSystemEntity.type(source);
    if (type == FileSystemEntityType.directory) {
      final destination = _paths.join(destinationRoot, _paths.basename(source));
      await _copyDirectory(Directory(source), Directory(destination));
      return {'from': source, 'to': destination};
    }
    if (type == FileSystemEntityType.file) {
      final destination = _paths.join(destinationRoot, _paths.basename(source));
      await File(source).copy(destination);
      return {'from': source, 'to': destination};
    }
    throw StateError('لا يمكن نسخ هذا النوع من المسارات');
  }

  Future<Map<String, dynamic>> movePath(
      String path, String destinationDirectory) async {
    final source = _resolveSpecialPath(path);
    final destination = _paths.join(
        _resolveSpecialPath(destinationDirectory), _paths.basename(source));
    await _renameEntity(source, destination);
    return {'from': source, 'to': destination};
  }

  Future<Map<String, dynamic>> deletePath(String path,
      {bool permanent = false}) async {
    final resolved = _resolveSpecialPath(path);
    if (permanent) {
      final type = await FileSystemEntity.type(resolved);
      if (type == FileSystemEntityType.directory) {
        await Directory(resolved).delete(recursive: true);
      } else if (type == FileSystemEntityType.file ||
          type == FileSystemEntityType.link) {
        await File(resolved).delete();
      } else {
        throw StateError('المسار غير موجود: $resolved');
      }
      return {'path': resolved, 'permanent': true};
    }

    final script = r'''
$Path = $args[0]
Add-Type -AssemblyName Microsoft.VisualBasic
if (Test-Path -LiteralPath $Path -PathType Container) {
  [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
    $Path,
    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
  )
} elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
  [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
    $Path,
    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
  )
} else {
  throw "Path not found: $Path"
}
''';
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
        resolved
      ],
    );
    if (result.exitCode != 0) {
      throw StateError(
          'تعذر النقل إلى سلة المحذوفات: ${result.stderr}${result.stdout}');
    }
    return {'path': resolved, 'permanent': false};
  }

  Future<Map<String, dynamic>> setHidden(String path, bool hidden) async {
    final resolved = _resolveSpecialPath(path);
    final args = [hidden ? '+h' : '-h', resolved];
    final result = await Process.run('attrib.exe', args);
    if (result.exitCode != 0) {
      throw StateError(
          'تعذر تغيير حالة الإخفاء: ${result.stderr}${result.stdout}');
    }
    return {'path': resolved, 'hidden': hidden};
  }

  Future<List<Map<String, dynamic>>> _listRoots() async {
    final result = await Process.run('wmic.exe',
        ['logicaldisk', 'get', 'name,volumename,drivetype', '/format:csv']);
    final roots = <Map<String, dynamic>>[];
    if (result.exitCode == 0) {
      for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
        final parts = line.split(',');
        if (parts.length < 4 || parts[1] == 'DriveType') continue;
        final drive = parts[2].trim();
        final volume = parts[3].trim();
        if (drive.isEmpty) continue;
        roots.add(_driveMap(drive, volume));
      }
    }
    if (roots.isNotEmpty) return roots;
    return _listRootsWithPowerShell();
  }

  Future<List<Map<String, dynamic>>> _listRootsWithPowerShell() async {
    final script = r'''
$drives = Get-PSDrive -PSProvider FileSystem | ForEach-Object {
  [PSCustomObject]@{
    Name = $_.Name
    Root = $_.Root
    Description = $_.Description
  }
}
$drives | ConvertTo-Json -Compress -Depth 3
''';
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0 || result.stdout.toString().trim().isEmpty) {
      return [];
    }
    final decoded = _decodeJsonList(result.stdout.toString());
    return decoded
        .map((item) {
          final root = (item['Root'] ?? '').toString().trim();
          final label = (item['Description'] ?? '').toString().trim();
          if (root.isEmpty) return null;
          return _driveMap(root.replaceAll(r'\', ''), label);
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> _decodeJsonList(String text) {
    try {
      final decoded = jsonDecode(text.trim());
      final list = decoded is List ? decoded : [decoded];
      return list
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _driveMap(String drive, String volume) {
    final normalized = drive.endsWith(':') ? drive : drive.replaceAll(r'\', '');
    return {
      'name': volume.isEmpty ? normalized : '$volume ($normalized)',
      'path': '$normalized\\',
      'type': 'drive',
      'iconKey': 'drive',
      'modifiedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> _entityToMap(FileSystemEntity entity) async {
    final stat = await entity.stat();
    final type = stat.type == FileSystemEntityType.directory
        ? 'directory'
        : stat.type == FileSystemEntityType.link
            ? 'link'
            : 'file';
    final name = _paths.basename(entity.path);
    final extension = type == 'file'
        ? _paths.extension(name).replaceFirst('.', '').toLowerCase()
        : '';
    return {
      'name': name,
      'path': entity.path,
      'type': type,
      'extension': extension,
      'size': stat.size,
      'modifiedAt': stat.modified.toIso8601String(),
      'isHidden': name.startsWith('.') || await _isHidden(entity.path),
      'iconKey': _iconKey(type, extension, name),
    };
  }

  Future<bool> _isHidden(String path) async {
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      r"(Get-Item -LiteralPath $args[0] -Force).Attributes.ToString()",
      path,
    ]);
    return result.stdout.toString().toLowerCase().contains('hidden');
  }

  String _iconKey(String type, String extension, String name) {
    if (type == 'directory') return 'folder';
    if (extension.isNotEmpty) return extension;
    final lower = name.toLowerCase();
    if (lower.endsWith('.exe')) return 'exe';
    return 'file';
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!await destination.exists()) await destination.create(recursive: true);
    await for (final entity
        in source.list(recursive: false, followLinks: false)) {
      final name = _paths.basename(entity.path);
      final target = _paths.join(destination.path, name);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        await entity.copy(target);
      }
    }
  }

  Future<void> _renameEntity(String source, String destination) async {
    final type = await FileSystemEntity.type(source);
    if (type == FileSystemEntityType.directory) {
      await Directory(source).rename(destination);
    } else if (type == FileSystemEntityType.file) {
      await File(source).rename(destination);
    } else if (type == FileSystemEntityType.link) {
      await Link(source).rename(destination);
    } else {
      throw StateError('المسار غير موجود: $source');
    }
  }

  String _resolveSpecialPath(String value) {
    final text = value.trim();
    if (text.isEmpty || text == 'roots') return 'roots';

    final userProfile =
        Platform.environment['USERPROFILE'] ?? Directory.current.path;
    switch (text.toLowerCase()) {
      case 'desktop':
        return '$userProfile\\Desktop';
      case 'downloads':
        return '$userProfile\\Downloads';
      case 'documents':
        return '$userProfile\\Documents';
      case 'pictures':
        return '$userProfile\\Pictures';
      case 'home':
        return userProfile;
      default:
        return text.replaceAll('/', r'\');
    }
  }

  String? _parentOf(String path) {
    final root = _paths.rootPrefix(path);
    final parent = _paths.dirname(path);
    if (parent == path || path == root) return 'roots';
    return parent;
  }
}
