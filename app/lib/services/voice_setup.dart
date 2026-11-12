import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'speaker.dart';

/// Opens the screen that fixes a missing voice in one tap.
abstract final class VoiceSetupFix {
  static const _store = 'market://details?id=${Speaker.googleEngine}';
  static const _storeWeb =
      'https://play.google.com/store/apps/details?id=${Speaker.googleEngine}';

  /// noGoogleEngine: the Play Store page for Speech Services by Google.
  /// noBanglaData: Google's "install voice data" screen, else the phone's
  /// text-to-speech settings. Returns false when nothing could be opened.
  static Future<bool> open(VoiceSetup setup) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    if (setup == VoiceSetup.noGoogleEngine) return _openStore();
    for (final intent in [
      const AndroidIntent(
        action: 'android.speech.tts.engine.INSTALL_TTS_DATA',
        package: Speaker.googleEngine,
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      ),
      const AndroidIntent(
        action: 'com.android.settings.TTS_SETTINGS',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      ),
    ]) {
      try {
        if (await intent.canResolveActivity() ?? false) {
          await intent.launch();
          return true;
        }
      } catch (_) {}
    }
    return _openStore();
  }

  static Future<bool> _openStore() async {
    try {
      if (await launchUrl(
        Uri.parse(_store),
        mode: LaunchMode.externalApplication,
      )) {
        return true;
      }
    } catch (_) {}
    try {
      return await launchUrl(
        Uri.parse(_storeWeb),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
