import 'package:intl/intl.dart';

/// Shared display formatters used across the Craft UI (mirrors the mockup's
/// `fmtBytes` / `fmtDate` / `relTime`).

String fmtBytes(int? n) {
  if (n == null) return '0 B';
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  return '${(n / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String fmtDate(DateTime? d) {
  if (d == null) return '—';
  return DateFormat('MMM d, y').format(d.toLocal());
}

String relTime(DateTime? d) {
  if (d == null) return '—';
  final diff = DateTime.now().difference(d);
  final days = diff.inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 30) return '${days}d ago';
  if (days < 365) return '${(days / 30).floor()}mo ago';
  return '${(days / 365).floor()}y ago';
}

/// Time-of-day greeting for the Library header.
String greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}
