import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// Shared display formatters used across the Craft UI (mirrors the mockup's
/// `fmtBytes` / `fmtDate` / `relTime`).
///
/// User-facing words (relative-time units, greetings) are pulled from
/// [AppLocalizations]; numeric/byte/date formatting stays locale-neutral here.

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

String relTime(AppLocalizations l10n, DateTime? d) {
  if (d == null) return '—';
  final diff = DateTime.now().difference(d);
  final days = diff.inDays;
  if (days <= 0) return l10n.relativeToday;
  if (days == 1) return l10n.relativeYesterday;
  if (days < 30) return l10n.relativeDaysAgo(days);
  if (days < 365) return l10n.relativeMonthsAgo((days / 30).floor());
  return l10n.relativeYearsAgo((days / 365).floor());
}

/// Time-of-day greeting for the Library header.
String greeting(AppLocalizations l10n) {
  final h = DateTime.now().hour;
  if (h < 12) return l10n.greetingMorning;
  if (h < 18) return l10n.greetingAfternoon;
  return l10n.greetingEvening;
}

/// Capitalize the first letter — used for tag / collection display names.
String titleCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
