// ignore_for_file: invalid_use_of_visible_for_testing_member
// Renders every screen of the app with the real fonts and saves PNG
// screenshots, for checking the UI by eye. Not part of `flutter test`.
//
//   flutter test test_screens --dart-define=SHOTS=/path/to/dir

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
import 'package:omni_voice_call/l10n/l10n.dart';
import 'package:omni_voice_call/main.dart';
import 'package:omni_voice_call/models/chat.dart';
import 'package:omni_voice_call/services/call_controller.dart';
import 'package:omni_voice_call/services/chat_controller.dart';
import 'package:omni_voice_call/services/chat_store.dart';
import 'package:omni_voice_call/services/listener.dart';
import 'package:omni_voice_call/services/read_aloud.dart';
import 'package:omni_voice_call/services/settings_store.dart';
import 'package:omni_voice_call/services/speaker.dart';
import 'package:omni_voice_call/screens/settings_screen.dart';
import 'package:omni_voice_call/screens/voice_mode_screen.dart';
import 'package:omni_voice_call/screens/voices_screen.dart';
import 'package:omni_voice_call/widgets/composer.dart';
import 'package:omni_voice_call/widgets/model_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const outDir = String.fromEnvironment('SHOTS', defaultValue: '/tmp/shots');
const phone = Size(412, 915);
const dpr = 2.0;

class FakeCall extends CallController {
  FakeCall({
    required super.settings,
    required super.speaker,
    required super.listener,
    required super.sink,
  });
  CallState fakeState = CallState.speaking;
  bool fakeInCall = true;

  @override
  bool get inCall => fakeInCall;

  @override
  Future<void> start() async {
    state = fakeState;
    // ignore: invalid_use_of_protected_member
    notifyListeners();
  }

  @override
  Future<void> hangUp() async {}

  @override
  Future<void> interrupt() async {}
}

Future<void> loadFonts() async {
  Future<void> font(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(
        Future.value(
          ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()),
        ),
      );
    }
    await l.load();
  }

  await font('DM Sans', ['DMSans.ttf']);
  await font('Noto Sans Bengali', ['NotoSansBengali.ttf']);
  if (File('assets/fonts/HindSiliguri-Regular.ttf').existsSync()) {
    await font('Hind Siliguri', [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
        if (File('assets/fonts/HindSiliguri-$w.ttf').existsSync())
          'HindSiliguri-$w.ttf',
    ]);
  }
  await font('Anton', ['Anton-Regular.ttf']);
  await font('DM Mono', ['DMMono-Regular.ttf', 'DMMono-Medium.ttf']);
  // Material icons (used by a few built-in widgets).
  final mi = File(
    '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (mi.existsSync()) {
    final l = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(mi.readAsBytesSync())));
    await l.load();
  }
}

const longBn =
    'বাংলাদেশের মুক্তিযুদ্ধ ১৯৭১ সালে সংঘটিত হয়। এই যুদ্ধে লক্ষ লক্ষ মানুষ '
    'প্রাণ দিয়েছেন, এবং ১৬ ডিসেম্বর বিজয় অর্জিত হয়। আমাকে সংক্ষেপে এর '
    'প্রধান ঘটনাগুলো বুঝিয়ে বলো, আর কোন কোন বই পড়লে ভালো হবে সেটাও জানাও।';

const replyBn = '''অবশ্যই! মুক্তিযুদ্ধের **প্রধান ঘটনাগুলো** সংক্ষেপে:

## গুরুত্বপূর্ণ তারিখ

1. **৭ মার্চ ১৯৭১**: বঙ্গবন্ধুর ঐতিহাসিক ভাষণ, রেসকোর্স ময়দানে।
2. **২৫ মার্চ**: অপারেশন সার্চলাইট শুরু হয়।
3. **২৬ মার্চ**: স্বাধীনতার ঘোষণা।
4. **১৬ ডিসেম্বর**: বিজয় দিবস।

- মুজিবনগর সরকার গঠিত হয় ১৭ এপ্রিল।
- প্রায় এক কোটি মানুষ শরণার্থী হন।

> "এবারের সংগ্রাম আমাদের মুক্তির সংগ্রাম।"

পড়ার জন্য: *একাত্তরের দিনগুলি* (জাহানারা ইমাম)। একটি `Python` উদাহরণ:

```python
years = {"বিজয়": 1971, "ভাষা আন্দোলন": 1952}
for name, year in years.items():
    print(f"{name}: {year}")
```

| ঘটনা | তারিখ |
|---|---|
| ভাষণ | ৭ মার্চ |
| বিজয় | ১৬ ডিসেম্বর |
''';

const userEn =
    'Can you write a short English summary too, with a very long URL like https://example.com/a/really/long/path/that/keeps/going/and/going?query=1';

const replyEn =
    'Sure. Bangladesh became independent in **1971** after a nine-month war. '
    'Victory Day is 16 December. Use `flutter run` to try the app.';

List<Map<String, String>> fakeVoices = [
  {'name': 'bn-bd-x-ban-local', 'locale': 'bn-BD', 'quality': '400'},
  {'name': 'bn-bd-x-ban-network', 'locale': 'bn-BD', 'quality': '400'},
  {'name': 'bn-in-x-bnf-local', 'locale': 'bn-IN', 'quality': '400'},
  {'name': 'bn-in-x-bin-network', 'locale': 'bn-IN', 'quality': '400'},
];

class Rig {
  late AppServices sv;
  late FakeCall call;
}

Future<Rig> makeRig(
  String lang,
  ThemeMode mode, {
  bool withChats = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'defaultsVersion': 1,
    'language': lang,
    'themeMode': mode.name,
    'voiceSetupPrompted': true,
  });
  final settings = SettingsStore(
    clientFactory: () => MockClient(
      (r) async => http.Response(
        '{"enabled":true,"models":["auto","auto/fast","gemini-2.5-pro"],"defaultModel":"auto","ready":true}',
        200,
      ),
    ),
  );
  await settings.load();
  final store = ChatStore(directory: () async => Directory.systemTemp);
  final speaker = Speaker();
  final listener = SpeechListener();
  final chat = ChatController(store: store, settings: settings);
  final call = FakeCall(
    settings: settings,
    speaker: speaker,
    listener: listener,
    sink: chat,
  );
  final rig = Rig()
    ..call = call
    ..sv = AppServices(
      settings: settings,
      speaker: speaker,
      listener: listener,
      chats: store,
      chat: chat,
      call: call,
      readAloud: ReadAloud(settings, speaker),
    );
  if (withChats) {
    final now = DateTime.now();
    final titles = lang == 'bn'
        ? [
            'মুক্তিযুদ্ধের প্রধান ঘটনা',
            'ঢাকায় সেরা বিরিয়ানি কোথায় পাওয়া যায় তার একটি লম্বা তালিকা',
            'Flutter অ্যাপে বাংলা ফন্ট',
            'রান্নার রেসিপি: ইলিশ ভাপা',
            'Python code review',
            'ভ্রমণ পরিকল্পনা: কক্সবাজার',
          ]
        : [
            'Liberation war key events',
            'Where to find the best biryani in Dhaka, a long list',
            'Bangla fonts in Flutter',
            'Recipe: steamed hilsa',
            'Python code review',
            'Trip plan: Cox\'s Bazar',
          ];
    final ages = [0, 0, 1, 3, 9, 40];
    for (var i = 0; i < titles.length; i++) {
      final c = store.create()
        ..title = titles[i]
        ..titled = true
        ..updated = now.subtract(Duration(days: ages[i], minutes: i));
      c.messages.add(ChatMessage(role: Role.user, text: titles[i]));
    }
  }
  return rig;
}

final _shotKey = GlobalKey();

Widget wrap(Widget app) => RepaintBoundary(key: _shotKey, child: app);

Future<void> shot(WidgetTester tester, String name, {Finder? top}) async {
  final boundary =
      _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: dpr);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$outDir/$name.png');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(data!.buffer.asUint8List());
  });
  audit(name, boundary, top == null ? null : tester.renderObject(top.first));
}

/// Writes every visible text run with its box, colour, and whether it was
/// cut off, so contrast and clipping can be checked against the PNG.
void audit(String name, RenderObject screen, [RenderObject? only]) {
  final root = screen;
  final out = <Map<String, Object?>>[];
  void visit(RenderObject o) {
    if (o is RenderParagraph && o.attached && o.hasSize) {
      final text = o.text.toPlainText();
      if (text.trim().isNotEmpty) {
        final m = o.getTransformTo(root);
        final r = MatrixUtils.transformRect(m, Offset.zero & o.size);
        Color? color;
        double? size;
        double? height;
        o.text.visitChildren((span) {
          final st = span.style;
          color ??= st?.color;
          size ??= st?.fontSize;
          height ??= st?.height;
          return color == null;
        });
        // Visible when a hit test at its centre reaches it or one of its
        // ancestors (a route or a scrim on top absorbs the hit first).
        final centre = r.center;
        final hit = BoxHitTestResult();
        (root as RenderBox).hitTest(hit, position: centre);
        // The deepest hits come first; the text is visible when one of the
        // first few is the text itself or one of its ancestors.
        final firsts = hit.path
            .map((e) => e.target)
            .whereType<RenderObject>()
            .take(3)
            .toList();
        final ancestors = <RenderObject>{};
        for (RenderObject? x = o; x != null; x = x.parent) {
          ancestors.add(x);
        }
        final visible = firsts.any(ancestors.contains);
        out.add({
          'visible': visible,
          'text': text.length > 80 ? text.substring(0, 80) : text,
          'rect': [r.left, r.top, r.width, r.height],
          'color': color?.toARGB32(),
          'size': size,
          'height': height,
          'cut': o.didExceedMaxLines,
          'maxLines': o.maxLines,
          'clip': o.debugHasOverflowShader,
        });
      }
    }
    o.visitChildren(visit);
  }

  visit(only ?? root);
  File('$outDir/$name.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
}

void setPhone(WidgetTester tester, {double keyboard = 0}) {
  tester.view.physicalSize = phone * dpr;
  tester.view.devicePixelRatio = dpr;
  tester.view.padding = const FakeViewPadding(top: 24 * dpr, bottom: 16 * dpr);
  tester.view.viewPadding = const FakeViewPadding(
    top: 24 * dpr,
    bottom: 16 * dpr,
  );
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard * dpr);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> precache(WidgetTester tester) async {
  await tester.runAsync(() async {
    final ctx = _shotKey.currentContext!;
    await precacheImage(const AssetImage('assets/branding/logo.png'), ctx);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadFonts();
    if (const bool.fromEnvironment('BEFORE')) {
      // Paint widget errors the way a release build does: a plain grey box.
      RenderErrorBox.backgroundColor = const Color(0xF0C0C0C0);
      ErrorWidget.builder = (d) => ErrorWidget.withDetails(message: '');
      FlutterError.onError = (_) {};
    }
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
      c,
    ) async {
      if (c.method == 'getVoices') return fakeVoices;
      if (c.method == 'getEngines') return <String>[];
      return 1;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugin.csdcorp.com/speech_to_text'),
      (c) async => false,
    );
  });

  for (final lang in ['bn', 'en']) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      final tag = '${lang}_${mode.name}';
      if (lang == 'en' && mode == ThemeMode.dark) continue;

      testWidgets('screens $tag', (tester) async {
        setPhone(tester);
        addTearDown(tester.view.reset);
        final rig = await makeRig(lang, mode);
        final sv = rig.sv;
        await tester.pumpWidget(wrap(OmniVoiceApp(services: sv)));
        await precache(tester);
        await settle(tester);
        await shot(tester, '01_empty_$tag');

        // Waking banner.
        sv.settings.serverState = ServerState.waking;
        await sv.settings.setThemeMode(mode);
        await settle(tester);
        await shot(tester, '08_waking_$tag');
        sv.settings.serverState = ServerState.offline;
        await sv.settings.setThemeMode(mode);
        await settle(tester);
        await shot(tester, '09_offline_$tag');
        sv.settings.serverState = ServerState.online;
        await sv.settings.setThemeMode(mode);

        // A chat with long messages.
        final c = sv.chats.conversations.first;
        c.messages
          ..clear()
          ..addAll([
            ChatMessage(role: Role.user, text: lang == 'bn' ? longBn : userEn),
            ChatMessage(
              role: Role.assistant,
              text: lang == 'bn' ? replyBn : replyEn,
              model: 'auto',
            ),
            ChatMessage(role: Role.user, text: 'ধন্যবাদ!', viaVoice: true),
            ChatMessage(
              role: Role.assistant,
              text: '',
              error: lang == 'bn'
                  ? 'সার্ভারে পৌঁছানো যায়নি। ইন্টারনেট সংযোগ দেখে আবার চেষ্টা করুন।'
                  : 'Could not reach the server. Check your connection and try again.',
            ),
          ]);
        sv.chat.open(c);
        await settle(tester);
        await shot(tester, '03_chat_bottom_$tag');
        // Scroll to the top of the chat.
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 2400));
        await settle(tester);
        await shot(tester, '02_chat_top_$tag');
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
        await settle(tester);
        await shot(tester, '02b_chat_mid_$tag');

        // Drawer.
        final menu = find.byTooltip(
          lang == 'bn'
              ? lookupAppLocalizations(const Locale('bn')).chats
              : 'Chats',
        );
        await tester.tap(menu.first);
        await settle(tester);
        await shot(tester, '04_drawer_$tag', top: find.byType(Drawer));
        await tester.tapAt(const Offset(400, 400));
        await settle(tester);

        // Model sheet.
        final ctx = _shotKey.currentContext!;
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        showModelSheet(
          tester.element(find.byType(Scaffold).first),
          sv.settings,
        );
        await settle(tester);
        await shot(tester, '10_models_$tag', top: find.byType(BottomSheet));
        nav.pop();
        await settle(tester);

        // Composer with the keyboard open on a new chat.
        sv.chat.newChat();
        await settle(tester);
        setPhone(tester, keyboard: 320);
        await tester.enterText(
          find.descendant(
            of: find.byType(Composer),
            matching: find.byType(EditableText),
          ),
          lang == 'bn'
              ? 'আমাকে একটি ছোট কবিতা লিখে দাও বাংলাদেশের বর্ষাকাল নিয়ে, যেখানে নদী আর কদম ফুলের কথা থাকবে।'
              : 'Write me a short poem about the monsoon in Bangladesh, with rivers and kadam flowers.',
        );
        await settle(tester);
        await shot(tester, '05_keyboard_$tag');
        setPhone(tester);
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(tester);
        expect(ctx.mounted, isTrue);

        // Voice mode.
        rig.call
          ..fakeState = CallState.speaking
          ..lastHeard = lang == 'bn'
              ? 'আজ ঢাকার আবহাওয়া কেমন থাকবে?'
              : 'What is the weather in Dhaka today?'
          ..lastReply = ChatMessage(
            role: Role.assistant,
            text: lang == 'bn'
                ? 'আজ ঢাকায় আংশিক মেঘলা আকাশ, তাপমাত্রা প্রায় ২৮ ডিগ্রি সেলসিয়াস থাকতে পারে। বিকেলে হালকা বৃষ্টির সম্ভাবনা আছে।'
                : 'Partly cloudy in Dhaka today, around 28 degrees, with a chance of light rain in the afternoon.',
          )
          ..elapsed = const Duration(minutes: 1, seconds: 24);
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => VoiceModeScreen(services: sv),
          ),
        );
        await settle(tester);
        await shot(
          tester,
          '06_voice_speaking_$tag',
          top: find.byType(VoiceModeScreen),
        );
        rig.call
          ..state = CallState.listening
          ..partial = lang == 'bn' ? 'আগামীকাল কি বৃষ্টি' : 'Will it rain'
          ..level = 0.6;
        await sv.settings.setThemeMode(mode);
        await settle(tester);
        await shot(
          tester,
          '06b_voice_listening_$tag',
          top: find.byType(VoiceModeScreen),
        );
        nav.pop();
        await settle(tester);

        // Settings and voices.
        nav.push(
          MaterialPageRoute<void>(builder: (_) => SettingsScreen(services: sv)),
        );
        await settle(tester);
        await shot(
          tester,
          '07_settings_$tag',
          top: find.byType(SettingsScreen),
        );
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -900));
        await settle(tester);
        await shot(
          tester,
          '07b_settings_end_$tag',
          top: find.byType(SettingsScreen),
        );
        nav.pop();
        await settle(tester);
        nav.push(
          MaterialPageRoute<void>(builder: (_) => VoicesScreen(services: sv)),
        );
        await settle(tester);
        await shot(tester, '11_voices_$tag', top: find.byType(VoicesScreen));
        nav.pop();
        await settle(tester);

        // Disabled by the admin.
        sv.settings.remoteDisabled(
          lang == 'bn'
              ? 'রক্ষণাবেক্ষণের জন্য অ্যাপটি কিছুক্ষণ বন্ধ আছে।'
              : 'The app is paused for maintenance.',
        );
        await settle(tester);
        await shot(tester, '12_disabled_$tag');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }
}
