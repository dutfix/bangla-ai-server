import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;

import 'app_localizations.dart';

export 'app_localizations.dart';

/// The app's localization delegates: the app's own strings plus the
/// Material, Cupertino and Widgets strings from package:material_ui, which
/// is where this app's widgets come from.
///
/// Listed here on purpose, not taken from the generated
/// `AppLocalizations.localizationsDelegates`: every `flutter build` and
/// `flutter pub get` regenerates that file (pubspec `generate: true`) with
/// the flutter_localizations delegates, which give material_ui widgets no
/// Material strings. In Bangla that made the message box, the chat history
/// drawer and the menu throw in release builds (v1.0.1).
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

/// The app's languages. Bangla is the default; English is an option.
abstract final class AppLanguage {
  static const bangla = 'bn';
  static const english = 'en';
  static const defaultCode = bangla;
  static const codes = [bangla, english];

  /// The phone speech recognizer locale for each language.
  static String speechLocale(String code) =>
      code == english ? 'en_US' : 'bn_BD';

  /// The instruction added to every chat and call so the AI answers in the
  /// app language. Written in that language too, which models follow best.
  static String replyInstruction(String code) => code == english
      ? 'Always reply in English unless the user asks for another language.'
      : 'সবসময় বাংলায় উত্তর দাও (বাংলা লিপিতে), ব্যবহারকারী ইংরেজি বা অন্য '
            'ভাষায় লিখলেও, যদি না তিনি স্পষ্টভাবে অন্য ভাষায় উত্তর চান। '
            'Always respond in Bangla (Bengali script) unless the user '
            'explicitly asks for another language.';

  /// Native name, shown in the language picker.
  static String nativeName(String code) =>
      code == english ? 'English' : 'বাংলা';
}

/// Strings for code that has no BuildContext (services, controllers).
/// Follows the language picked in Settings.
abstract final class L10n {
  static String _code = AppLanguage.defaultCode;
  static String get code => _code;
  static set code(String value) => _code = AppLanguage.codes.contains(value)
      ? value
      : AppLanguage.defaultCode;

  static AppLocalizations get current => lookupAppLocalizations(Locale(_code));
}

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Writes Western digits as Bangla digits (০-৯) when the language is Bangla.
String localDigits(String text, [String? code]) {
  if ((code ?? L10n.code) != AppLanguage.bangla) return text;
  const bn = '০১২৩৪৫৬৭৮৯';
  return text.replaceAllMapped(
    RegExp('[0-9]'),
    (m) => bn[m[0]!.codeUnitAt(0) - 48],
  );
}

/// A chat's title, or "New chat" in the app language while it has none.
String chatTitle(String title, AppLocalizations l10n) =>
    title.trim().isEmpty ? l10n.newChat : title;
