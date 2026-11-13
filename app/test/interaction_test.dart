import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_voice_call/l10n/l10n.dart';
import 'package:omni_voice_call/main.dart';
import 'package:omni_voice_call/screens/settings_screen.dart';
import 'package:omni_voice_call/screens/voice_mode_screen.dart';
import 'package:omni_voice_call/widgets/composer.dart';
import 'package:omni_voice_call/widgets/message_tile.dart';
import 'package:omni_voice_call/widgets/sidebar.dart';

import 'support/rig.dart';

void main() {
  late List<String> clipboard;
  setUpAll(() async {
    clipboard = mockPlatform();
    await loadFonts();
  });

  // A typical phone (Pixel 7 size) with a status bar and gesture bar, set to
  // Bangla, in both themes and at normal and large font sizes.
  for (final b in Brightness.values) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('every control works in Bangla (${b.name}, text x$scale)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(412 * 2.625, 915 * 2.625);
        tester.view.devicePixelRatio = 2.625;
        tester.view.padding = const FakeViewPadding(top: 63, bottom: 63);
        tester.view.viewPadding = const FakeViewPadding(top: 63, bottom: 63);
        tester.platformDispatcher.platformBrightnessTestValue = b;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);

        final sv = await rig();
        final bn = lookupAppLocalizations(const Locale('bn'));
        await tester.pumpWidget(OmniVoiceApp(services: sv));
        await settle(tester);

        // Material strings exist for Bangla (their absence broke the
        // drawer, popup menus and the message box in v1.0.1).
        final ctx = tester.element(find.byType(Composer));
        expect(Localizations.localeOf(ctx), const Locale('bn'));
        expect(MaterialLocalizations.of(ctx), isNotNull);

        // Menu button opens the chat history drawer.
        await tester.tap(find.byTooltip(bn.chats).first);
        await settle(tester);
        expect(find.byType(ChatSidebar), findsOneWidget);

        // Search filters, then clears.
        await tester.enterText(
          find.descendant(
            of: find.byType(ChatSidebar),
            matching: find.byType(EditableText),
          ),
          'নম্বর 7',
        );
        await settle(tester);
        expect(find.textContaining('নম্বর 7'), findsWidgets);
        await tester.enterText(
          find.descendant(
            of: find.byType(ChatSidebar),
            matching: find.byType(EditableText),
          ),
          '',
        );
        await settle(tester);

        // The ... menu on a chat: rename.
        await tester.tap(find.byTooltip(bn.chatOptions).first);
        await settle(tester);
        await tester.tap(find.text(bn.rename).last);
        await settle(tester);
        await tester.enterText(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(EditableText),
          ),
          'নতুন নাম',
        );
        await tester.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text(bn.rename),
          ),
        );
        await settle(tester);
        expect(find.text('নতুন নাম'), findsWidgets);

        // Long-press menu: delete (confirm).
        final before = sv.chats.conversations.length;
        await tester.longPress(find.text('নতুন নাম').first);
        await settle(tester);
        await tester.tap(find.text(bn.delete).last);
        await settle(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text(bn.delete),
          ),
        );
        await settle(tester);
        expect(sv.chats.conversations.length, before - 1);

        // The drawer list scrolls to the oldest chats.
        await tester.fling(
          find
              .descendant(
                of: find.byType(ChatSidebar),
                matching: find.byType(Scrollable),
              )
              .first,
          const Offset(0, -3000),
          3000,
        );
        await settle(tester);

        // Voice settings live in the admin app now: no Voices link.
        expect(find.text(bn.voices), findsNothing);

        // Settings: theme, model sheet, back.
        await tester.tap(find.byTooltip(bn.chats).first);
        await settle(tester);
        await tester.tap(find.text(bn.settings));
        await settle(tester);
        expect(find.byType(SettingsScreen), findsOneWidget);
        await tester.tap(find.text(bn.model).first);
        await settle(tester);
        await tester.tapAt(const Offset(200, 120));
        await settle(tester);
        await tester.tap(find.byTooltip(bn.back).last);
        await settle(tester);

        // Open a chat from the drawer.
        await tester.tap(find.byTooltip(bn.chats).first);
        await settle(tester);
        final first = sv.chats.conversations.first;
        await tester.tap(find.text(first.title).first);
        await settle(tester);
        expect(find.byType(Drawer), findsNothing);
        expect(sv.chat.current, same(first));

        // New chat from the top bar.
        await tester.tap(find.byTooltip(bn.newChat).first);
        await settle(tester);
        expect(sv.chat.current, isNull);

        // A suggestion chip fills the box.
        await tester.ensureVisible(find.text(bn.suggestExplain));
        await settle(tester);
        await tester.tap(find.text(bn.suggestExplain));
        await settle(tester);
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byType(Composer),
                  matching: find.byType(EditableText),
                ),
              )
              .controller
              .text,
          bn.suggestExplainPrompt,
        );

        // Model picker in the header.
        await tester.tap(find.text(bn.appName.toUpperCase()).first);
        await settle(tester);
        expect(find.text(bn.model), findsWidgets);
        await tester.tap(find.text(modelLabelFor('auto/fast', bn)).last);
        await settle(tester);
        expect(sv.settings.model, 'auto/fast');

        // Send, watch it stream, and stop.
        await tester.enterText(
          find.descendant(
            of: find.byType(Composer),
            matching: find.byType(EditableText),
          ),
          'হ্যালো',
        );
        await tester.pump();
        await tester.tap(find.byTooltip(bn.send));
        await tester.pump(const Duration(milliseconds: 70));
        expect(sv.chat.generating, isTrue);
        await tester.tap(find.byTooltip(bn.stopGenerating));
        await settle(tester);
        expect(sv.chat.generating, isFalse);

        // Regenerate runs a full reply this time.
        await tester.tap(find.byTooltip(bn.regenerate).first);
        await settle(tester, 30);
        expect(sv.chat.generating, isFalse);
        expect(sv.chat.messages.last.text.trim(), FakeLlm.reply.trim());
        expect(find.byType(MessageTile), findsNWidgets(2));

        // Copy the reply and the code block.
        clipboard.clear();
        await tester.tap(find.byTooltip(bn.copy).last);
        await settle(tester);
        expect(clipboard, isNotEmpty);
        await tester.tap(find.text(bn.copy).first);
        await settle(tester, 25);
        expect(clipboard.last.trim(), 'print("হ্যালো")');

        // Read aloud and stop reading.
        await tester.tap(find.byTooltip(bn.readAloud).first);
        await settle(tester);

        // Edit and resend the user message.
        await tester.tap(find.byTooltip(bn.editAndResend).first);
        await settle(tester);
        await tester.enterText(
          find.descendant(
            of: find.byType(MessageTile),
            matching: find.byType(TextField),
          ),
          'আবার বলো',
        );
        await tester.tap(find.text(bn.send).last);
        await settle(tester, 30);
        expect(sv.chat.messages.first.text, 'আবার বলো');
        expect(sv.chat.messages.last.text.trim(), FakeLlm.reply.trim());

        // Voice call from the composer button, then hang up.
        await tester.tap(find.byTooltip(bn.startVoiceCall).first);
        await settle(tester);
        expect(find.byType(VoiceModeScreen), findsOneWidget);
        await tester.tap(find.text(bn.hangUp));
        await settle(tester);
        expect(find.byType(VoiceModeScreen), findsNothing);

        // Swiping from the edge opens the drawer too.
        await tester.dragFrom(const Offset(5, 400), const Offset(300, 0));
        await settle(tester);
        expect(find.byType(ChatSidebar), findsOneWidget);
        await tester.tapAt(const Offset(400, 400));
        await settle(tester);
        expect(find.byType(Drawer), findsNothing);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }
}

String modelLabelFor(String id, AppLocalizations l) =>
    id == 'auto/fast' ? l.modelFast : l.modelAuto;
