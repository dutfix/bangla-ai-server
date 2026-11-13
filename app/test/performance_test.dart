import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_voice_call/l10n/l10n.dart';
import 'package:omni_voice_call/main.dart';
import 'package:omni_voice_call/models/chat.dart';
import 'package:omni_voice_call/widgets/composer.dart';
import 'package:omni_voice_call/widgets/markdown_view.dart';

import 'support/rig.dart';

const _para =
    'একটি লম্বা অনুচ্ছেদ যেখানে অনেক শব্দ আছে এবং **গাঢ়** এবং `কোড` আছে। ';

/// A long reply: paragraphs, a list, code and a table, repeated.
String longReply(int sections) {
  final b = StringBuffer();
  for (var i = 0; i < sections; i++) {
    b
      ..write('## অংশ $i\n\n')
      ..write('${_para * 4}\n\n')
      ..write('- প্রথম $i\n- দ্বিতীয় $i\n\n')
      ..write(
        '```dart\nfor (var i = 0; i < $i; i++) {\n  print(i);\n}\n```\n\n',
      )
      ..write('| ক | খ |\n|---|---|\n| $i | ${i * 2} |\n\n');
  }
  return b.toString();
}

void main() {
  setUpAll(mockPlatform);

  test('the split of a streaming reply joins back to the same text', () {
    final text = longReply(6);
    for (var n = 1; n <= text.length; n += 7) {
      final parts = splitSettledBlocks(text.substring(0, n));
      expect(parts.join('\n\n').trim(), text.substring(0, n).trim());
    }
    // Code fences with blank lines inside stay one block.
    const fenced = 'a\n\n```\nx\n\ny\n```\n\nb\n\nc';
    expect(splitSettledBlocks(fenced), ['a', '```\nx\n\ny\n```', 'b', 'c']);
    // A list that goes on after a blank line is not cut.
    expect(splitSettledBlocks('- a\n\n- b\n\nc\n\nd'), [
      '- a\n\n- b',
      'c',
      'd',
    ]);
  });

  testWidgets('streaming a long reply rebuilds only that reply', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final sv = await rig();
    final bn = lookupAppLocalizations(const Locale('bn'));
    // An old chat with 80 long messages above the new reply.
    final c = sv.chats.create()
      ..title = 'long'
      ..titled = true;
    for (var i = 0; i < 40; i++) {
      c.messages
        ..add(ChatMessage(role: Role.user, text: 'প্রশ্ন $i'))
        ..add(ChatMessage(role: Role.assistant, text: longReply(2)));
    }
    await tester.pumpWidget(OmniVoiceApp(services: sv));
    await settle(tester);
    sv.chat.open(c);
    await settle(tester);

    // Count how often the screen around the list rebuilds while a reply
    // streams in: the composer stands in for "everything but the reply".
    var composerBuilds = 0;
    final composer = find.byType(Composer);
    final before = tester.widget<Composer>(composer);

    streamedReply = longReply(5);
    chunkDelay = const Duration(milliseconds: 16);
    addTearDown(() {
      streamedReply = FakeLlm.reply;
      chunkDelay = const Duration(milliseconds: 20);
    });
    await tester.enterText(
      find.descendant(of: composer, matching: find.byType(EditableText)),
      'লম্বা উত্তর দাও',
    );
    await tester.pump();
    await tester.tap(find.byTooltip(bn.send));
    await tester.pump();

    final frames = <int>[];
    var last = before;
    for (var i = 0; i < 400 && sv.chat.generating; i++) {
      final sw = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      frames.add(sw.elapsedMicroseconds);
      final now = tester.widget<Composer>(composer);
      if (!identical(now, last)) composerBuilds++;
      last = now;
    }
    await settle(tester, 20);
    expect(sv.chat.generating, isFalse);

    frames.sort();
    final p50 = frames[frames.length ~/ 2] / 1000;
    final p95 = frames[(frames.length * 0.95).floor()] / 1000;
    // ignore: avoid_print
    print(
      'streaming frames: p50 ${p50.toStringAsFixed(1)} ms, '
      'p95 ${p95.toStringAsFixed(1)} ms; screen rebuilds: $composerBuilds',
    );
    // The reply arrives in hundreds of chunks; the screen rebuilds only
    // when the reply starts and ends, not per chunk.
    expect(composerBuilds, lessThan(6));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('scrolling a long chat', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final sv = await rig();
    final c = sv.chats.create()
      ..title = 'long'
      ..titled = true;
    for (var i = 0; i < 40; i++) {
      c.messages
        ..add(ChatMessage(role: Role.user, text: 'প্রশ্ন $i'))
        ..add(ChatMessage(role: Role.assistant, text: longReply(2)));
    }
    await tester.pumpWidget(OmniVoiceApp(services: sv));
    await settle(tester);
    sv.chat.open(c);
    await settle(tester);
    final frames = <int>[];
    final list = find.byType(Scrollable).first;
    for (var k = 0; k < 2; k++) {
      final g = await tester.startGesture(tester.getCenter(list));
      for (var i = 0; i < 120; i++) {
        final sw = Stopwatch()..start();
        await g.moveBy(Offset(0, k == 0 ? 40 : -40));
        await tester.pump(const Duration(milliseconds: 16));
        frames.add(sw.elapsedMicroseconds);
      }
      await g.up();
      await settle(tester);
    }
    frames.sort();
    final p50 = frames[frames.length ~/ 2] / 1000;
    final p95 = frames[(frames.length * 0.95).floor()] / 1000;
    // ignore: avoid_print
    print(
      'scrolling frames: p50 ${p50.toStringAsFixed(1)} ms, '
      'p95 ${p95.toStringAsFixed(1)} ms',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
