import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_voice_call/main.dart';
import 'package:omni_voice_call/widgets/composer.dart';

import 'support/rig.dart';

/// The keyboard must stay up while the user types, even when it makes the
/// screen so short that the chat switches to its cramped layout. On the web
/// (Chrome on Android) the whole page shrinks when the keyboard opens, so
/// the view itself gets shorter; on phones the keyboard is a bottom inset.
void main() {
  setUpAll(() async {
    mockPlatform();
    await loadFonts();
  });

  Future<void> typeThroughResize(
    WidgetTester tester, {
    required Size start,
    required List<Size> sizes,
    bool asInset = false,
    bool withChat = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = start;
    addTearDown(tester.view.reset);
    final sv = await rig(voice: false);
    await tester.pumpWidget(OmniVoiceApp(services: sv));
    await settle(tester);
    if (withChat) {
      sv.chat.open(sv.chats.conversations.first);
      await settle(tester);
    }

    Finder inComposer(Type t) =>
        find.descendant(of: find.byType(Composer), matching: find.byType(t));
    await tester.tap(inComposer(TextField));
    await settle(tester, 3);
    final editable = inComposer(EditableText);
    final state = tester.state<EditableTextState>(editable);
    expect(state.widget.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    final hideCalls = <MethodCall>[];
    tester.testTextInput.log.clear();

    for (final s in sizes) {
      if (asInset) {
        tester.view.viewInsets = FakeViewPadding(
          bottom: start.height - s.height,
        );
      } else {
        tester.view.physicalSize = s;
      }
      await settle(tester, 2);
    }
    hideCalls.addAll(
      tester.testTextInput.log.where(
        (c) =>
            c.method == 'TextInput.hide' || c.method == 'TextInput.clearClient',
      ),
    );

    // Same text field, still focused, keyboard never asked to close.
    expect(identical(tester.state<EditableTextState>(editable), state), isTrue);
    expect(state.widget.focusNode.hasFocus, isTrue);
    expect(hideCalls, isEmpty);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.enterText(inComposer(TextField), 'আমি টাইপ করছি');
    await settle(tester, 2);
    expect(find.text('আমি টাইপ করছি'), findsOneWidget);
  }

  testWidgets('web phone: page shrinks for the keyboard', (tester) async {
    await typeThroughResize(
      tester,
      start: const Size(412, 860),
      sizes: const [
        Size(412, 700),
        Size(412, 520),
        Size(412, 430),
        Size(412, 300),
      ],
    );
  });

  testWidgets('web phone with a chat open', (tester) async {
    await typeThroughResize(
      tester,
      start: const Size(390, 780),
      sizes: const [Size(390, 440)],
      withChat: true,
    );
  });

  testWidgets('phone app: keyboard as a bottom inset', (tester) async {
    await typeThroughResize(
      tester,
      start: const Size(412, 860),
      sizes: const [Size(412, 430)],
      asInset: true,
    );
  });

  testWidgets('web tablet: page gets too short for the side list', (
    tester,
  ) async {
    await typeThroughResize(
      tester,
      start: const Size(800, 900),
      sizes: const [Size(800, 600), Size(800, 420)],
    );
  });
}
