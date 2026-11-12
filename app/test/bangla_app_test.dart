import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_voice_call/app_services.dart';
import 'package:omni_voice_call/l10n/l10n.dart';
import 'package:omni_voice_call/main.dart';
import 'package:omni_voice_call/services/call_controller.dart';
import 'package:omni_voice_call/services/chat_controller.dart';
import 'package:omni_voice_call/services/chat_store.dart';
import 'package:omni_voice_call/services/listener.dart';
import 'package:omni_voice_call/services/read_aloud.dart';
import 'package:omni_voice_call/services/settings_store.dart';
import 'package:omni_voice_call/services/speaker.dart';
import 'package:omni_voice_call/widgets/composer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The whole app as a fresh install opens it: Bangla, no chats yet, and
/// the server asleep. This is the case that used to show a grey box
/// instead of the chat screen, because no Material strings were loaded
/// for Bangla and the message box threw while building.
Future<AppServices> _freshInstall(http.Client Function() client) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsStore(clientFactory: client);
  await settings.load();
  final store = ChatStore(directory: () async => Directory.systemTemp);
  final speaker = Speaker();
  final listener = SpeechListener();
  final chat = ChatController(store: store, settings: settings);
  return AppServices(
    settings: settings,
    speaker: speaker,
    listener: listener,
    chats: store,
    chat: chat,
    call: CallController(
      settings: settings,
      speaker: speaker,
      listener: listener,
      sink: chat,
    ),
    readAloud: ReadAloud(settings, speaker),
  );
}

void main() {
  setUpAll(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (c) async => null,
    );
    m.setMockMethodCallHandler(
      const MethodChannel('plugin.csdcorp.com/speech_to_text'),
      (c) async => false,
    );
  });

  for (final b in Brightness.values) {
    testWidgets('fresh Bangla install with the server asleep (${b.name})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.platformBrightnessTestValue = b;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      // The server answers 503 twice while Render wakes it up, then the
      // admin's config.
      var calls = 0;
      final sv = await _freshInstall(
        () => MockClient((_) async {
          calls++;
          if (calls <= 2) return http.Response('asleep', 503);
          return http.Response(
            '{"enabled":true,"models":["auto"],"defaultModel":"auto","ready":true}',
            200,
          );
        }),
      );
      expect(sv.settings.language, 'bn');

      await tester.pumpWidget(OmniVoiceApp(services: sv));
      await tester.pump();
      expect(tester.takeException(), isNull);

      final bn = lookupAppLocalizations(const Locale('bn'));
      // Empty state, message box and header are all there.
      expect(find.text(bn.appName.toUpperCase()), findsWidgets);
      expect(find.byType(Composer), findsOneWidget);
      expect(find.text(bn.messageHint), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);
      // No raw model id in the header.
      expect(find.text('AUTO'), findsNothing);

      // After a few seconds the "waking up" banner shows, still no errors.
      await tester.pump(const Duration(seconds: 5));
      expect(sv.settings.serverState, ServerState.waking);
      expect(
        find.textContaining(bn.serverWaking.split('।').first),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // The message box takes Bangla text.
      await tester.enterText(find.byType(EditableText), 'হ্যালো');
      await tester.pump();
      expect(find.text('হ্যালো'), findsOneWidget);

      // The drawer opens.
      await tester.tap(find.byTooltip(bn.chats).first);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(Drawer), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Once awake, the banner goes and the chat screen is unchanged.
      Navigator.of(tester.element(find.byType(Drawer))).pop();
      await tester.pump(const Duration(seconds: 10));
      expect(sv.settings.serverState, ServerState.online);
      expect(find.byType(Composer), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The offline state renders too.
      sv.settings.serverState = ServerState.offline;
      await sv.settings.setThemeMode(ThemeMode.system);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(bn.serverOffline), findsOneWidget);
      expect(find.byType(Composer), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  }
}
