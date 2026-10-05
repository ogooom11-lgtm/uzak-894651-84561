import 'package:intl/intl.dart';

class AppFormatters {
  static final DateFormat _dateTime = DateFormat('yyyy/MM/dd - HH:mm');
  static final DateFormat _time = DateFormat('HH:mm:ss');

  static String dateTime(DateTime value) => _dateTime.format(value);
  static String time(DateTime value) => _time.format(value);

  static String durationFrom(DateTime start) {
    final diff = DateTime.now().difference(start);
    if (diff.inMinutes < 1) return 'منذ لحظات';
    if (diff.inHours < 1) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inDays < 1) return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  static String fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(gb < 10 ? 1 : 0)} GB';
  }
}
