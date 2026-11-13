import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_voice_call/app_services.dart';
import 'package:omni_voice_call/models/chat.dart';
import 'package:omni_voice_call/services/call_controller.dart';
import 'package:omni_voice_call/services/chat_controller.dart';
import 'package:omni_voice_call/services/chat_store.dart';
import 'package:omni_voice_call/services/listener.dart';
import 'package:omni_voice_call/services/llm_client.dart';
import 'package:omni_voice_call/services/read_aloud.dart';
import 'package:omni_voice_call/services/settings_store.dart';
import 'package:omni_voice_call/services/speaker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What [FakeLlm] answers, and how fast.
String streamedReply = FakeLlm.reply;
Duration chunkDelay = const Duration(milliseconds: 20);

/// Answers with a Markdown reply, a few words at a time.
class FakeLlm extends LlmClient {
  FakeLlm(super.settings);
  bool cancelled = false;

  static const reply =
      'অবশ্যই! **প্রধান কথা**:\n\n1. প্রথম\n2. দ্বিতীয়\n\n'
      '```python\nprint("হ্যালো")\n```\n\n| ক | খ |\n|---|---|\n| ১ | ২ |\n';

  @override
  Stream<String> streamChat(
    List<Map<String, String>> messages, {
    String? model,
    void Function()? onWaking,
  }) async* {
    cancelled = false;
    for (final word in streamedReply.split(' ')) {
      await Future<void>.delayed(chunkDelay);
      if (cancelled) return;
      yield '$word ';
    }
  }

  @override
  Future<String> complete(
    List<Map<String, String>> messages, {
    String? model,
    Duration timeout = const Duration(seconds: 30),
  }) async => 'পরীক্ষার শিরোনাম';

  @override
  void cancel() => cancelled = true;
}

class FakeCall extends CallController {
  FakeCall({
    required super.settings,
    required super.speaker,
    required super.listener,
    required super.sink,
  });
  bool live = false;

  @override
  bool get inCall => live;

  @override
  Future<void> start() async {
    live = true;
    state = CallState.listening;
    // ignore: invalid_use_of_protected_member
    notifyListeners();
  }

  @override
  Future<void> hangUp() async {
    live = false;
    state = CallState.idle;
    // ignore: invalid_use_of_protected_member
    notifyListeners();
  }

  @override
  Future<void> interrupt() async {}
}

Future<AppServices> rig() async {
  SharedPreferences.setMockInitialValues({'voiceSetupPrompted': true});
  final settings = SettingsStore(
    clientFactory: () => MockClient(
      (_) async => http.Response(
        '{"enabled":true,"models":["auto","auto/fast"],'
        '"defaultModel":"auto","ready":true}',
        200,
      ),
    ),
  );
  await settings.load();
  final store = ChatStore(directory: () async => Directory.systemTemp);
  final now = DateTime.now();
  for (var i = 0; i < 30; i++) {
    final c = store.create()
      ..title = 'পুরনো চ্যাট নম্বর $i, একটু লম্বা শিরোনাম যাতে কাটা পড়ে'
      ..titled = true
      ..updated = now.subtract(Duration(days: i * 2, minutes: i));
    c.messages
      ..add(ChatMessage(role: Role.user, text: 'প্রশ্ন $i'))
      ..add(ChatMessage(role: Role.assistant, text: 'উত্তর $i'));
  }
  final speaker = Speaker();
  final listener = SpeechListener();
  final chat = ChatController(
    store: store,
    settings: settings,
    llm: FakeLlm(settings),
    titleLlm: FakeLlm(settings),
  );
  return AppServices(
    settings: settings,
    speaker: speaker,
    listener: listener,
    chats: store,
    chat: chat,
    call: FakeCall(
      settings: settings,
      speaker: speaker,
      listener: listener,
      sink: chat,
    ),
    readAloud: ReadAloud(settings, speaker),
  );
}

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final e = const bool.fromEnvironment("RAW") ? null : tester.takeException();
  if (e is FlutterError) fail(e.toStringDeep());
  expect(e, isNull);
  expect(find.byType(ErrorWidget), findsNothing);
}

/// Mocks the platform channels the app touches; returns what was copied.
List<String> mockPlatform() {
  final clipboard = <String>[];
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(
    const MethodChannel('flutter_tts'),
    (c) async => c.method == 'getVoices' ? <Object>[] : 1,
  );
  m.setMockMethodCallHandler(
    const MethodChannel('plugin.csdcorp.com/speech_to_text'),
    (c) async => false,
  );
  m.setMockMethodCallHandler(SystemChannels.platform, (c) async {
    if (c.method == 'Clipboard.setData') {
      clipboard.add((c.arguments as Map)['text'] as String);
    }
    return null;
  });
  return clipboard;
}

/// Loads the app's real fonts, so text is measured as on a phone (the test
/// font draws every letter as a square and hides Bangla wrapping issues).
Future<void> loadFonts() async {
  Future<void> font(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final file = File('assets/fonts/$f');
      if (!file.existsSync()) continue;
      l.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await l.load();
  }

  final fonts = Directory('assets/fonts')
      .listSync()
      .map((e) => e.uri.pathSegments.last)
      .toList();
  await font('DM Sans', ['DMSans.ttf']);
  await font('Noto Sans Bengali', ['NotoSansBengali.ttf']);
  await font('Hind Siliguri', [
    for (final f in fonts)
      if (f.startsWith('HindSiliguri')) f,
  ]);
  await font('Anton', ['Anton-Regular.ttf']);
  await font('DM Mono', [
    for (final f in fonts)
      if (f.startsWith('DMMono')) f,
  ]);
}

/// Saves the current screen as a PNG under [dir] when [dir] is set.
Future<void> shot(WidgetTester tester, String dir, String name) async {
  if (dir.isEmpty) return;
  final root = tester.binding.renderViews.first;
  final layer = root.debugLayer! as OffsetLayer;
  final size = root.size;
  await tester.runAsync(() async {
    // The root layer already scales by the device pixel ratio, so its
    // content is in physical pixels.
    final img = await layer.toImage(
      Offset.zero & (size * tester.view.devicePixelRatio),
    );
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$dir/$name.png')..parent.createSync(recursive: true);
    f.writeAsBytesSync(data!.buffer.asUint8List());
  });
  File('$dir/$name.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert(auditText(root.child!)),
  );
}

/// Every visible line of text with its box, whether it was cut short, and
/// whether it reaches past the screen.
List<Map<String, Object?>> auditText(RenderBox root) {
  final out = <Map<String, Object?>>[];
  void visit(RenderObject o) {
    if (o is RenderParagraph && o.attached && o.hasSize) {
      final text = o.text.toPlainText();
      if (text.trim().isNotEmpty) {
        var r = MatrixUtils.transformRect(
          o.getTransformTo(root),
          Offset.zero & o.size,
        );
        // Only the part that is painted: cut by every clip above it (a
        // scrolled list, a bar on top).
        final whole = r;
        RenderObject child = o;
        for (var p = o.parent; p != null; p = p.parent) {
          final clip = p.describeApproximatePaintClip(child);
          if (clip != null) {
            r = r.intersect(
              MatrixUtils.transformRect(p.getTransformTo(root), clip),
            );
          }
          child = p;
          if (identical(p, root)) break;
        }
        if (r.width <= 0 || r.height <= 0) {
          o.visitChildren(visit);
          return;
        }
        final hit = BoxHitTestResult();
        root.hitTest(hit, position: r.center);
        final ancestors = <RenderObject>{};
        for (RenderObject? x = o; x != null; x = x.parent) {
          ancestors.add(x);
        }
        final visible = hit.path
            .map((e) => e.target)
            .whereType<RenderObject>()
            .take(3)
            .any(ancestors.contains);
        out.add({
          'text': text.length > 60 ? text.substring(0, 60) : text,
          'visible': visible,
          'rect': [r.left, r.top, r.width, r.height],
          'cut': o.didExceedMaxLines,
          'offscreen': whole.left < -0.5 || whole.right > root.size.width + 0.5,
          'clipped': r != whole,
        });
      }
    }
    o.visitChildren(visit);
  }

  visit(root);
  return out;
}
