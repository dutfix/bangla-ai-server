import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_voice_call/l10n/l10n.dart';
import 'package:omni_voice_call/main.dart';
import 'package:omni_voice_call/models/chat.dart';

import 'support/rig.dart';

void main() {
  setUpAll(() async {
    mockPlatform();
    await loadFonts();
  });

  Future<void> phone(WidgetTester tester, {double width = 412}) async {
    tester.view.physicalSize = Size(width * 2.625, 915 * 2.625);
    tester.view.devicePixelRatio = 2.625;
    tester.view.padding = const FakeViewPadding(top: 63, bottom: 63);
    tester.view.viewPadding = const FakeViewPadding(top: 63, bottom: 63);
    addTearDown(tester.view.reset);
  }

  testWidgets('voice off: no call button, no call card, no read aloud', (
    tester,
  ) async {
    await phone(tester);
    final sv = await rig(voice: false);
    final bn = lookupAppLocalizations(const Locale('bn'));
    await tester.pumpWidget(OmniVoiceApp(services: sv));
    await settle(tester);
    expect(find.byTooltip(bn.startVoiceCall), findsNothing);
    expect(find.text(bn.startVoiceCallSub), findsNothing);

    sv.chat.open(sv.chats.conversations.first);
    await settle(tester);
    expect(find.text('উত্তর 0'), findsOneWidget);
    expect(find.byTooltip(bn.readAloud), findsNothing);
    expect(find.byTooltip(bn.copy), findsWidgets);
    // The empty box shows a dimmed send button, not a call button.
    expect(find.byTooltip(bn.send), findsOneWidget);
    expect(find.byTooltip(bn.startVoiceCall), findsNothing);
  });

  testWidgets('voice on: the call button and read aloud are back', (
    tester,
  ) async {
    await phone(tester);
    final sv = await rig();
    final bn = lookupAppLocalizations(const Locale('bn'));
    await tester.pumpWidget(OmniVoiceApp(services: sv));
    await settle(tester);
    expect(find.byTooltip(bn.startVoiceCall), findsWidgets);
    sv.chat.open(sv.chats.conversations.first);
    await settle(tester);
    expect(find.byTooltip(bn.readAloud), findsWidgets);
  });

  for (final width in [360.0, 412.0, 900.0, 1280.0]) {
    testWidgets('user messages sit on the right, replies on the left '
        '(${width.toInt()} wide)', (tester) async {
      await phone(tester, width: width);
      final sv = await rig();
      await tester.pumpWidget(OmniVoiceApp(services: sv));
      await settle(tester);
      final c = sv.chats.conversations.first;
      c.messages
        ..clear()
        ..add(ChatMessage(role: Role.user, text: 'হাই'))
        ..add(ChatMessage(role: Role.assistant, text: 'হ্যালো!'));
      sv.chat.open(c);
      await settle(tester);

      final list = tester.getRect(
        find.ancestor(of: find.text('হাই'), matching: find.byType(ListView)),
      );
      final user = tester.getRect(find.text('হাই'));
      final reply = tester.getRect(find.text('হ্যালো!'));
      final column = list.width.clamp(0, 760.0);
      final colLeft = list.left + (list.width - column) / 2;
      final colRight = colLeft + column;
      // Short user text: right edge near the column's right edge.
      expect(colRight - user.right, lessThan(48), reason: '$user in $list');
      expect(user.left, greaterThan(list.center.dx));
      // Short reply: starts near the column's left edge.
      expect(reply.left - colLeft, lessThan(64), reason: '$reply in $list');
      expect(reply.right, lessThan(list.center.dx + 40));
    });
  }
}
