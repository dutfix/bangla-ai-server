import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_voice_call/app_services.dart';
import 'package:omni_voice_call/l10n/l10n.dart';
import 'package:omni_voice_call/main.dart';
import 'package:omni_voice_call/models/chat.dart';
import 'package:omni_voice_call/screens/settings_screen.dart';
import 'package:omni_voice_call/screens/voice_mode_screen.dart';
import 'package:omni_voice_call/widgets/composer.dart';
import 'package:omni_voice_call/widgets/message_tile.dart';

import 'support/rig.dart';

/// A long Bangla conversation with every kind of block a reply can have.
Conversation longChat(AppServices sv) {
  final c = sv.chats.create()
    ..title = 'খুব লম্বা একটি চ্যাটের শিরোনাম যা হেডারে কখনোই পুরোটা আঁটবে না কারণ এটি অনেক বড়'
    ..titled = true;
  const reply =
      '## বাংলাদেশের ইতিহাস সম্পর্কে একটি দীর্ঘ শিরোনাম যা মোড়াতে হবে\n\n'
      'একটি লম্বা অনুচ্ছেদ যেখানে অনেক শব্দ আছে এবং যা ছোট ফোনে কয়েক লাইনে মোড়াতে হবে। '
      'averyveryverylongunbrokenwordthatcouldoverflowanarrowscreen_and_more '
      '`inline_code_that_is_quite_long_too()` এবং [একটি লিংক](https://example.com)।\n\n'
      '- প্রথম বিন্দু যা বেশ লম্বা এবং মোড়ানো দরকার\n'
      '- দ্বিতীয় বিন্দু\n  - ভেতরের বিন্দু\n\n'
      '> একটি উদ্ধৃতি যা বেশ লম্বা এবং কয়েক লাইন জুড়ে থাকবে\n\n'
      '```dart\nvoid main() { print("একটি খুব লম্বা লাইন যা পাশে স্ক্রল করবে কারণ এটি অনেক বড়"); }\n```\n\n'
      '| নাম | বিবরণ | আরও একটি কলাম | শেষ কলাম |\n|---|---|---|---|\n'
      '| ক | একটি লম্বা বিবরণ যা টেবিলকে চওড়া করে | ১২৩৪৫ | শেষ |\n';
  for (var i = 0; i < 12; i++) {
    c.messages
      ..add(
        ChatMessage(
          role: Role.user,
          text:
              'একটি লম্বা প্রশ্ন নম্বর $i যা বাবলের ভেতরে কয়েক লাইনে মোড়াতে হবে',
          viaVoice: i == 3,
        ),
      )
      ..add(
        ChatMessage(
          role: Role.assistant,
          text: reply,
          viaVoice: i == 3,
          stopped: i == 5,
          error: i == 7
              ? 'সার্ভারে পৌঁছানো যাচ্ছে না। ইন্টারনেট সংযোগ দেখুন।'
              : null,
        ),
      );
  }
  return c;
}

class Device {
  const Device(this.name, this.w, this.h, {this.dpr = 2.75, this.inset = 24});
  final String name;
  final double w, h, dpr, inset;
}

const devices = [
  Device('fold cover 280x653', 280, 653),
  Device('small phone 320x568', 320, 568, dpr: 2),
  Device('phone 360x780', 360, 780),
  Device('large phone 430x932', 430, 932),
  Device('phone landscape 780x360', 780, 360, inset: 0),
  Device('split screen 412x430', 412, 430, inset: 0),
  Device('foldable inner 673x841', 673, 841, dpr: 2.5),
  Device('tablet 800x1280', 800, 1280, dpr: 2),
  Device('tablet landscape 1280x800', 1280, 800, dpr: 2),
];

const shotDir = String.fromEnvironment('SHOTS');

void main() {
  setUpAll(() async {
    mockPlatform();
    await loadFonts();
  });

  for (final d in devices) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('lays out on ${d.name} at text x$scale', (tester) async {
        final tag = '${d.name.split(' ').last}_x$scale';
        tester.view.physicalSize = Size(d.w * d.dpr, d.h * d.dpr);
        tester.view.devicePixelRatio = d.dpr;
        final pad = FakeViewPadding(
          top: d.inset * d.dpr,
          bottom: d.inset * d.dpr,
        );
        tester.view.padding = pad;
        tester.view.viewPadding = pad;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);

        final sv = await rig();
        final bn = lookupAppLocalizations(const Locale('bn'));
        await tester.pumpWidget(OmniVoiceApp(services: sv));
        await settle(tester);
        await shot(tester, shotDir, '1_empty_$tag');

        // Empty chat, then with the keyboard up.
        tester.view.viewInsets = FakeViewPadding(bottom: d.h * 0.42 * d.dpr);
        await settle(tester, 4);
        expect(find.byType(Composer), findsOneWidget);
        await shot(tester, shotDir, '2_empty_keyboard_$tag');
        tester.view.resetViewInsets();
        await settle(tester, 4);

        // A long conversation: top, scrolled through, keyboard up.
        final c = longChat(sv);
        sv.chat.open(c);
        await settle(tester);
        expect(find.byType(MessageTile), findsWidgets);
        await shot(tester, shotDir, '3_chat_$tag');
        await tester.fling(
          find.byType(Scrollable).first,
          const Offset(0, 2500),
          4000,
        );
        await settle(tester);
        await shot(tester, shotDir, '4_chat_scrolled_$tag');
        tester.view.viewInsets = FakeViewPadding(bottom: d.h * 0.42 * d.dpr);
        await settle(tester, 4);
        await shot(tester, shotDir, '5_chat_keyboard_$tag');
        tester.view.resetViewInsets();
        await settle(tester, 4);

        // Editing a message.
        await tester.fling(
          find.byType(Scrollable).first,
          const Offset(0, -9000),
          6000,
        );
        await settle(tester);
        final edit = find.byTooltip(bn.editAndResend);
        if (edit.evaluate().isNotEmpty) {
          await tester.tap(edit.first, warnIfMissed: false);
          await settle(tester);
        }

        // A reply streaming in.
        sv.chat.newChat();
        await settle(tester, 2);
        await tester.enterText(
          find.descendant(
            of: find.byType(Composer),
            matching: find.byType(EditableText),
          ),
          'হ্যালো',
        );
        await tester.pump();
        await tester.tap(find.byTooltip(bn.send), warnIfMissed: false);
        await settle(tester, 30);
        await shot(tester, shotDir, '6_reply_$tag');

        // The drawer (phones) or the side panel (tablets).
        final menu = find.byTooltip(bn.chats);
        if (menu.evaluate().isNotEmpty) {
          await tester.tap(menu.first);
          await settle(tester);
          await shot(tester, shotDir, '7_drawer_$tag');
          Navigator.of(tester.element(find.byType(Drawer))).pop();
          await settle(tester);
        }

        // Settings, scrolled to the end.
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        nav.push(
          MaterialPageRoute<void>(builder: (_) => SettingsScreen(services: sv)),
        );
        await settle(tester);
        await shot(tester, shotDir, '8_settings_$tag');
        await tester.fling(
          find.byType(Scrollable).last,
          const Offset(0, -6000),
          6000,
        );
        await settle(tester);
        nav.pop();
        await settle(tester);

        // Voice mode, in a call with captions and an error card.
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => VoiceModeScreen(services: sv),
          ),
        );
        await settle(tester);
        sv.call.lastHeard = 'আমি একটি লম্বা প্রশ্ন জিজ্ঞাসা করছি যা ক্যাপশনে কয়েক লাইন জুড়ে থাকবে';
        sv.call.error =
            'মাইক্রোফোন ব্যবহারের অনুমতি দরকার। সেটিংসে গিয়ে অনুমতি দিন।';
        sv.call.levels.value = 0.5;
        await settle(tester);
        await shot(tester, shotDir, '10_voice_mode_$tag');
        nav.pop();
        await settle(tester);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }
}
