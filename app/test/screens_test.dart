import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_voice_call/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_voice_call/models/chat.dart';
import 'package:omni_voice_call/services/chat_store.dart';
import 'package:omni_voice_call/theme/app_theme.dart';
import 'package:omni_voice_call/widgets/composer.dart';
import 'package:omni_voice_call/widgets/message_tile.dart';
import 'package:omni_voice_call/widgets/sidebar.dart';
import 'package:omni_voice_call/widgets/voice_orb.dart';

Widget _app(Brightness b, Widget child) => MaterialApp(
  theme: buildTheme(b),
  locale: const Locale('en'),
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('chat pieces lay out on a small phone in both themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 720 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // Never loaded, so nothing is written to disk.
    final store = ChatStore(directory: () async => Directory.systemTemp);
    final c = store.create()
      ..title = 'A very long chat title that will need to be cut short'
      ..messages.add(ChatMessage(role: Role.user, text: 'Hi'));
    store.changed(c, now: true);

    final input = TextEditingController(text: 'Draft');
    addTearDown(input.dispose);

    for (final b in Brightness.values) {
      await tester.pumpWidget(
        _app(
          b,
          Column(
            children: [
              SizedBox(
                height: 360,
                width: 300,
                child: ChatSidebar(
                  store: store,
                  currentId: c.id,
                  onNewChat: () {},
                  onOpen: (_) {},
                  onDeleted: (_) {},
                  onSettings: () {},
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    MessageTile(
                      message: ChatMessage(
                        role: Role.user,
                        text: 'Tell me a joke',
                        viaVoice: true,
                      ),
                      streaming: false,
                      isLastReply: false,
                      reading: false,
                      busy: false,
                      onRegenerate: () {},
                      onEdit: (_) {},
                      onSpeak: () {},
                    ),
                    MessageTile(
                      message: ChatMessage(
                        role: Role.assistant,
                        text: 'Here is `code`:\n\n```python\nprint(1)\n```',
                        model: 'auto',
                      ),
                      streaming: false,
                      isLastReply: false,
                      reading: false,
                      busy: false,
                      onRegenerate: () {},
                      onEdit: (_) {},
                      onSpeak: () {},
                    ),
                    MessageTile(
                      message: ChatMessage(
                        role: Role.assistant,
                        error: 'Server said 401: bad key',
                      ),
                      streaming: false,
                      isLastReply: true,
                      reading: false,
                      busy: false,
                      onRegenerate: () {},
                      onEdit: (_) {},
                      onSpeak: () {},
                    ),
                    Composer(
                      controller: input,
                      generating: false,
                      onSend: (_) {},
                      onStop: () {},
                      onVoiceCall: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('New chat'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Voice call'), findsOneWidget);
    }
  });

  testWidgets('voice orb renders every state', (tester) async {
    for (final st in OrbState.values) {
      await tester.pumpWidget(
        _app(
          Brightness.dark,
          Center(
            child: ActionOrb(
              state: st,
              onTap: () {},
              clock: '01:05',
              hint: 'speak now',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(
      _app(
        Brightness.light,
        const Waveform(level: 0.7, color: Color(0xFFDA2F2F)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
