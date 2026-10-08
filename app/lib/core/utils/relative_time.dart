import 'package:intl/intl.dart';

/// "just now", "5m ago", "3h ago", "2d ago", then a short date.
String relativeTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 30) return '${d.inDays}d ago';
  final sameYear = t.year == n.year;
  return DateFormat(sameYear ? 'MMM d' : 'MMM d, y').format(t.toLocal());
}

String fullTimestamp(DateTime t) => DateFormat('EEE, MMM d y · HH:mm').format(t.toLocal());
