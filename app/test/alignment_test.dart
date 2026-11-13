// Where each message sits: the user's own messages on the right, the AI's
// replies on the left, in the chat and on the call screen, on small and large
// phones, in landscape, in Bangla and English, light and dark, and with the
// system font at twice its normal size.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_voice_call/app_services.dart';
import 'package:omni_voice_call/l10n/l10n.dart';
import 'package:omni_voice_call/main.dart';
import 'package:omni_voice_call/models/chat.dart';
import 'package:omni_voice_call/screens/settings_screen.dart';
import 'package:omni_voice_call/screens/voice_mode_screen.dart';
import 'package:omni_voice_call/services/call_controller.dart';

import 'support/rig.dart';

const shortUser = 'হাই';
const shortReply = 'হ্যালো!';
const longUser =
    'আমাকে বাংলাদেশের মুক্তিযুদ্ধের প্রধান ঘটনাগুলো সংক্ষেপে বুঝিয়ে বলো, আর '
    'কোন কোন বই পড়লে ভালো হবে সেটাও জানাও। Please answer in simple words.';
const longReply =
    'অবশ্যই। ১৯৭১ সালের ২৬ মার্চ স্বাধীনতার ঘোষণা দেওয়া হয়, আর ১৬ ডিসেম্বর '
    'বিজয় আসে। Victory Day is the sixteenth of December, after nine months.';
const shortUserEn = 'Hi';
const shortReplyEn = 'Hello there!';

class Screen {
  const Screen(this.name, this.width, this.height);
  final String name;
  final double width;
  final double height;
}

const screens = [
  Screen('small phone', 360, 740),
  Screen('large phone', 430, 932),
  Screen('phone landscape', 915, 412),
  Screen('tablet', 800, 1280),
];

void main() {
  setUpAll(() async {
    mockPlatform();
    await loadFonts();
  });

  Future<void> size(WidgetTester tester, Screen sc, double textScale) async {
    const dpr = 2.625;
    tester.view.physicalSize = Size(sc.width * dpr, sc.height * dpr);
    tester.view.devicePixelRatio = dpr;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Finder bubbleOf(Finder text) => find
      .ancestor(
        of: text,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).color != null,
        ),
      )
      .first;

  Future<AppServices> open(
    WidgetTester tester, {
    required String lang,
    required ThemeMode mode,
    required List<ChatMessage> messages,
  }) async {
    final sv = await rig();
    await sv.settings.setLanguage(lang);
    await sv.settings.setThemeMode(mode);
    await tester.pumpWidget(OmniVoiceApp(services: sv));
    await settle(tester);
    final c = sv.chats.conversations.first;
    c.messages
      ..clear()
      ..addAll(messages);
    sv.chat.open(c);
    await settle(tester);
    return sv;
  }

  for (final sc in screens) {
    for (final textScale in [1.0, 2.0]) {
      for (final (lang, mode) in [
        ('bn', ThemeMode.light),
        ('bn', ThemeMode.dark),
        ('en', ThemeMode.light),
      ]) {
        final tag =
            '${sc.name} ${sc.width.toInt()}x${sc.height.toInt()}, '
            'text x$textScale, $lang ${mode.name}';

        testWidgets('chat: yours right, replies left ($tag)', (tester) async {
          await size(tester, sc, textScale);
          final su = lang == 'bn' ? shortUser : shortUserEn;
          final sr = lang == 'bn' ? shortReply : shortReplyEn;
          await open(
            tester,
            lang: lang,
            mode: mode,
            messages: [
              ChatMessage(role: Role.user, text: longUser),
              ChatMessage(role: Role.assistant, text: longReply),
              ChatMessage(role: Role.user, text: su, viaVoice: true),
              ChatMessage(role: Role.assistant, text: sr),
            ],
          );

          final listFinder = find.byWidget(
            tester.widget(
              find.ancestor(of: find.text(su), matching: find.byType(ListView)),
            ),
          );
          final list = tester.getRect(listFinder);
          final column = list.width.clamp(0, 760.0);
          final colLeft = list.left + (list.width - column) / 2;
          final colRight = colLeft + column;
          final inner = column - 2 * 18; // the list's side padding

          // Short message: a small bubble flush with the right edge.
          final shortBubble = tester.getRect(bubbleOf(find.text(su)));
          expect(
            (colRight - 18 - shortBubble.right).abs(),
            lessThan(1),
            reason: 'short bubble $shortBubble, column $colLeft-$colRight',
          );
          expect(shortBubble.left, greaterThan(colLeft + column / 2));
          // Its text starts at the bubble's own left padding.
          final shortText = tester.getRect(find.text(su));
          expect((shortText.left - shortBubble.left - 16).abs(), lessThan(1));

          // Short reply: starts at the left edge.
          final r = tester.getRect(find.text(sr));
          expect((r.left - (colLeft + 18)).abs(), lessThan(2), reason: '$r');
          expect(r.right, lessThan(colLeft + column / 2 + 40));

          // The "voice call" tag of a spoken message sits on its side too.
          final l10n = lookupAppLocalizations(Locale(lang));
          final tagRect = tester.getRect(find.text(l10n.voiceCall).first);
          expect((colRight - 18 - tagRect.right).abs(), lessThan(1));

          // Long message: flush right, at most 80% wide, wrapped inside.
          final longFinder = find.text(longUser);
          await tester.dragUntilVisible(
            longFinder,
            listFinder,
            const Offset(0, 250),
          );
          await settle(tester);
          final longBubble = tester.getRect(bubbleOf(longFinder));
          expect((colRight - 18 - longBubble.right).abs(), lessThan(1));
          expect(longBubble.width, lessThanOrEqualTo(inner * 0.8 + 0.5));
          expect(longBubble.width, greaterThan(inner * 0.7));
          final longText = tester.getRect(longFinder);
          expect((longText.left - longBubble.left - 16).abs(), lessThan(1));
          expect(longText.right, lessThanOrEqualTo(longBubble.right - 15));

          // Long reply: starts at the left edge too.
          final longR = find.textContaining('\u09e7\u09ef\u09ed\u09e7');
          await tester.dragUntilVisible(
            longR,
            listFinder,
            const Offset(0, -150),
          );
          await settle(tester);
          final lr = tester.getRect(longR.first);
          expect((lr.left - (colLeft + 18)).abs(), lessThan(2), reason: '$lr');

          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 3));
        });
      }

      testWidgets('call screen: yours right, reply left '
          '(${sc.name}, text x$textScale)', (tester) async {
        await size(tester, sc, textScale);
        final sv = await open(
          tester,
          lang: 'bn',
          mode: ThemeMode.light,
          messages: [ChatMessage(role: Role.user, text: shortUser)],
        );
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => VoiceModeScreen(services: sv),
          ),
        );
        await settle(tester);
        sv.call.state = CallState.speaking;
        sv.call.lastHeard = 'আবহাওয়া?';
        sv.call.lastReply = ChatMessage(
          role: Role.assistant,
          text: 'আজ রোদ থাকবে।',
        );
        sv.call.levels.value = 0.4;
        // ignore: invalid_use_of_protected_member
        sv.call.notifyListeners();
        await settle(tester);

        final you = find.byKey(const ValueKey('caption-you'));
        final reply = find.byKey(const ValueKey('caption-reply'));
        await tester.ensureVisible(you);
        await settle(tester);
        final y = tester.getRect(you);
        final area = tester.getRect(find.byKey(const ValueKey('captions')));
        await tester.ensureVisible(reply);
        await settle(tester);
        final r = tester.getRect(reply);
        // Your words hug the right side, the reply the left: not the middle.
        expect(y.center.dx, greaterThan(r.center.dx), reason: '$y vs $r');
        expect(r.right, lessThan(y.right));
        expect(y.left, greaterThan(r.left));
        expect((area.right - 16 - y.right).abs(), lessThan(1), reason: '$y');
        expect((r.left - area.left - 16).abs(), lessThan(1), reason: '$r');
        expect(y.center.dx, greaterThan(area.center.dx));
        expect(r.center.dx, lessThan(area.center.dx));
        nav.pop();
        await settle(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }

  testWidgets('settings text and chips start on the left', (tester) async {
    await size(tester, screens[1], 1.0);
    final sv = await open(
      tester,
      lang: 'bn',
      mode: ThemeMode.light,
      messages: [ChatMessage(role: Role.user, text: shortUser)],
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(
      MaterialPageRoute<void>(builder: (_) => SettingsScreen(services: sv)),
    );
    await settle(tester);
    final l10n = lookupAppLocalizations(const Locale('bn'));
    final title = tester.getRect(find.text(l10n.language).first);
    final sub = tester.getRect(find.text(l10n.languageSub));
    final chip = tester.getRect(find.text('বাংলা').first);
    expect((sub.left - title.left).abs(), lessThan(1), reason: '$sub');
    expect(chip.left, lessThan(80), reason: '$chip');
    nav.pop();
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
