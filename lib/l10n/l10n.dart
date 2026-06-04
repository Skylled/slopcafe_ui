import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// Ergonomic access to the generated [AppLocalizations] from any [BuildContext].
///
/// All user-facing copy lives in `lib/l10n/app_en.arb`; this lets call sites
/// read it as `context.l10n.someString` instead of
/// `AppLocalizations.of(context).someString`.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
