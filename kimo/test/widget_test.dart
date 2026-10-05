import 'package:flutter_test/flutter_test.dart';
import 'package:win_remote_mobile/core/command_type.dart';
import 'package:win_remote_mobile/models/remote_file_item.dart';

void main() {
  test('file commands keep stable wire names', () {
    expect(CommandType.browsePath.wireName, 'browse_path');
    expect(CommandType.openPath.wireName, 'open_path');
    expect(CommandType.deletePath.arabicTitle, 'حذف');
  });

  test('remote file listing parses payload items', () {
    final listing = RemoteFileListing.fromPayload({
      'path': r'C:\Users\Demo\Desktop',
      'parentPath': r'C:\Users\Demo',
      'items': [
        {
          'name': 'report.pdf',
          'path': r'C:\Users\Demo\Desktop\report.pdf',
          'type': 'file',
          'extension': 'pdf',
          'size': 42,
          'modifiedAt': '2026-05-17T08:00:00.000',
        }
      ],
    });

    expect(listing.items.single.name, 'report.pdf');
    expect(listing.items.single.isDirectory, isFalse);
  });
}
