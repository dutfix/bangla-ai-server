import 'package:flutter/widgets.dart';

/// The few shared texts the copied components use. The admin app is in
/// English.
class AdminStrings {
  const AdminStrings();
  String get back => 'Back';
  String get clear => 'Clear';
  String get cancel => 'Cancel';
}

extension AdminL10n on BuildContext {
  AdminStrings get l10n => const AdminStrings();
}
