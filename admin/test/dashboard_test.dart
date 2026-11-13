import 'dart:convert';
import 'dart:io';

import 'package:bangla_ai_admin/api.dart';
import 'package:bangla_ai_admin/screens/dashboard_screen.dart';
import 'package:bangla_ai_admin/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fake server with the admin endpoints the dashboard uses.
class FakeServer {
  final calls = <String>[];
  Map<String, dynamic>? lastSave;
  Map<String, dynamic>? lastSample;
  Map<String, dynamic> cfg = {
    'enabled': true,
    'disabledMessage': 'বন্ধ',
    'baseUrl': 'https://omni.example.com/v1',
    'apiKeySet': true,
    'apiKeyHint': '••••abcd',
    'models': ['auto', 'auto/fast'],
    'defaultModel': 'auto',
    'systemPrompt': '',
    'stylePrompt': 'Talk like a sharp, laid-back friend.',
    'callPrompt': 'This is a live voice call.',
    'voiceName': 'bn-bd-x-ban-network',
    'voiceLocale': 'bn-BD',
    'speed': 1.0,
    'pitch': 1.0,
    'voiceEnabled': false,
    'voiceProvider': 'device',
    'voiceProviders': [],
    'callModel': '',
    'callModelInUse': 'auto/fast',
    'callMaxTokens': 160,
    'callPauseMs': 900,
    'callHistory': 10,
    'callOfflineVoice': true,
    'ttsDailyChars': 200000,
  };

  static const types = [
    {
      'type': 'azure',
      'label': 'Microsoft Azure Speech',
      'note': 'Microsoft neural voices, including Bangla.',
      'fields': [
        {
          'key': 'region',
          'label': 'Region',
          'hint': 'eastus',
          'required': true,
        },
        {
          'key': 'apiKey',
          'label': 'Speech key',
          'secret': true,
          'required': true,
        },
        {
          'key': 'voice',
          'label': 'Voice',
          'hint': 'bn-BD-NabanitaNeural',
          'required': true,
          'suggestions': ['bn-BD-NabanitaNeural', 'bn-BD-PradeepNeural'],
        },
      ],
    },
    {
      'type': 'google',
      'label': 'Google Cloud Text-to-Speech',
      'note': 'Google Cloud voices.',
      'fields': [
        {'key': 'apiKey', 'label': 'API key', 'secret': true, 'required': true},
        {'key': 'voice', 'label': 'Voice', 'required': true},
      ],
    },
  ];

  Map<String, dynamic> stats() {
    final series = [
      for (var i = 0; i < 30; i++)
        {
          'day': '2026-10-${(15 + i).clamp(1, 31).toString().padLeft(2, '0')}',
          'chats': (i * 7) % 23,
          'callTurns': i % 5,
          'failures': i % 9 == 0 ? 1 : 0,
          'devices': (i * 3) % 11,
        },
    ];
    return {
      'stats': {
        'timezone': 'Asia/Dhaka',
        'today': {
          'chats': 42,
          'callTurns': 6,
          'messages': 48,
          'failures': 1,
          'tts': 0,
          'ttsChars': 0,
          'activeDevices': 9,
          'newDevices': 2,
          'chatReplyMs': 3400,
          'callReplyMs': 2100,
          'models': {'auto': 30, 'auto/fast': 18},
          'voices': {},
          'errorKinds': {'chat:timeout': 1},
        },
        'week': {
          'chats': 1234,
          'callTurns': 56,
          'messages': 1290,
          'failures': 3,
          'tts': 0,
          'ttsChars': 0,
          'activeDevices': 37,
          'newDevices': 12,
          'chatReplyMs': 3600,
          'callReplyMs': 2300,
          'models': {'auto': 900, 'auto/fast': 390},
          'voices': {},
          'errorKinds': {'chat:timeout': 2, 'chat:key': 1},
        },
        'month': {'chats': 4000, 'messages': 4100, 'activeDevices': 80},
        'series': series,
        'totalDevices': 120,
        'recent': {'chatReplyMs': 3300, 'callReplyMs': 2000, 'ttsMs': null},
        'recentErrors': [
          {
            'at': '2026-11-13T08:00:00Z',
            'where': 'chat',
            'message': 'OmniRoute took longer than 120 seconds.',
          },
        ],
        'since': '2026-10-15',
        'uptimeSeconds': 5400,
      },
      'version': '1.2.0',
      'storeOk': true,
      'emailReady': true,
      'ready': true,
    };
  }

  http.Client client() => MockClient((req) async {
    calls.add('${req.method} ${req.url.path}');
    final json = {'Content-Type': 'application/json; charset=utf-8'};
    http.Response ok(Object body) =>
        http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: json);
    switch ('${req.method} ${req.url.path}') {
      case 'GET /health':
        return ok({'ok': true});
      case 'GET /admin/config':
        return ok({'config': cfg, 'storeOk': true});
      case 'PUT /admin/config':
        lastSave = jsonDecode(req.body) as Map<String, dynamic>;
        cfg = {
          ...cfg,
          ...lastSave!,
          'voiceProviders': [
            for (final p in (lastSave!['voiceProviders'] as List? ?? const []))
              {
                ...(Map<String, dynamic>.from(p as Map)..remove('apiKey')),
                'apiKeySet': true,
                'apiKeyHint': '••••9999',
              },
          ],
        }..remove('apiKey');
        return ok({'config': cfg, 'storeOk': true});
      case 'GET /admin/stats':
        return ok(stats());
      case 'GET /admin/voice-types':
        return ok({'types': types});
      case 'POST /admin/tts-test':
        lastSample = jsonDecode(req.body) as Map<String, dynamic>;
        return ok({
          'ok': false,
          'error': 'Azure Speech rejected the key (401).',
        });
      case 'POST /admin/try-chat':
        return ok({
          'ok': true,
          'reply': 'আরে, মন খারাপ? চলো একটু হাঁটতে যাই।',
          'ms': 2100,
          'model': 'auto',
        });
      case 'GET /admin/defaults':
        return ok({
          'stylePrompt': 'DEFAULT STYLE',
          'callPrompt': 'DEFAULT CALL',
        });
    }
    return http.Response('{}', 404, headers: json);
  });
}

Future<void> loadFonts() async {
  for (final (family, file) in [
    ('DM Sans', 'assets/fonts/DMSans.ttf'),
    ('Noto Sans Bengali', 'assets/fonts/NotoSansBengali.ttf'),
    ('Anton', 'assets/fonts/Anton-Regular.ttf'),
  ]) {
    final loader = FontLoader(family)
      ..addFont(
        Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
      );
    await loader.load();
  }
}

void main() {
  late FakeServer server;

  setUpAll(loadFonts);

  setUp(() {
    server = FakeServer();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'adminToken': 't'});
    AdminApi.testClient = server.client();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (c) async => c.method == 'getVoices'
              ? [
                  {'name': 'bn-bd-x-ban-network', 'locale': 'bn-BD'},
                  {'name': 'bn-bd-x-ban-local', 'locale': 'bn-BD'},
                ]
              : 1,
        );
  });

  Future<void> size(WidgetTester tester, double w, double h) async {
    tester.view.physicalSize = Size(w * 2.625, h * 2.625);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  Future<void> open(
    WidgetTester tester, {
    Brightness b = Brightness.light,
  }) async {
    final api = await AdminApi.create();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(b),
        home: DashboardScreen(api: api),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  final shots = Platform.environment['SHOTS'] == '1';
  Future<void> shot(WidgetTester tester, String name) async {
    if (!shots) return;
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$name.png'),
    );
  }

  testWidgets('phone: nav bar with four tabs; overview shows the numbers', (
    tester,
  ) async {
    await size(tester, 360, 800);
    await open(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    for (final l in ['Overview', 'AI', 'Voice', 'Settings']) {
      expect(
        find.descendant(of: find.byType(NavigationBar), matching: find.text(l)),
        findsOneWidget,
      );
    }
    expect(server.calls, contains('GET /admin/stats'));
    // 7 days by default.
    expect(find.text('1,290'), findsOneWidget); // messages
    expect(find.text('37'), findsOneWidget); // active phones
    expect(find.text('3.6 s'), findsOneWidget); // reply start
    expect(find.text('Voice: '), findsOneWidget);
    await shot(tester, 'phone_overview');
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('48'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1400));
    await tester.pumpAndSettle();
    await shot(tester, 'phone_overview_charts');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'voice tab: off by default; turning it on and adding Microsoft saves both',
    (tester) async {
      await size(tester, 360, 800);
      await open(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Voice'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Off: no call button'), findsOneWidget);
      await shot(tester, 'phone_voice');
      expect(find.text('Unsaved changes'), findsNothing);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(
        find.textContaining('On: users see the call button'),
        findsOneWidget,
      );
      await shot(tester, 'phone_voice_on');

      await tester.scrollUntilVisible(
        find.text('Add a voice provider'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a voice provider'));
      await tester.pumpAndSettle();
      expect(find.text('Microsoft Azure Speech'), findsOneWidget);
      expect(find.text('Google Cloud Text-to-Speech'), findsOneWidget);
      await tester.tap(find.text('Microsoft Azure Speech'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Microsoft Azure Speech'), findsWidgets);
      expect(find.widgetWithText(TextField, 'Region'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Region'),
        'eastus',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Speech key'),
        'secret-key-1',
      );
      await tester.tap(find.text('bn-BD-PradeepNeural'));
      await tester.pumpAndSettle();
      await shot(tester, 'phone_provider');
      await tester.ensureVisible(find.text('Hear a sample'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hear a sample'));
      await tester.pumpAndSettle();
      expect(server.lastSample!['provider']['voice'], 'bn-BD-PradeepNeural');
      expect(find.text('Azure Speech rejected the key (401).'), findsOneWidget);
      await tester.ensureVisible(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Back on the Voice tab: the provider is listed; pick it.
      expect(find.text('Microsoft Azure Speech'), findsOneWidget);
      await tester.ensureVisible(find.text('Microsoft Azure Speech'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Microsoft Azure Speech'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save for all users'));
      await tester.pumpAndSettle();
      final saved = server.lastSave!;
      expect(saved['voiceEnabled'], isTrue);
      final p = (saved['voiceProviders'] as List).single as Map;
      expect(p['type'], 'azure');
      expect(p['region'], 'eastus');
      expect(p['apiKey'], 'secret-key-1');
      expect(p['voice'], 'bn-BD-PradeepNeural');
      expect(saved['voiceProvider'], p['id']);
      expect(find.text('Unsaved changes'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'AI tab: try the style before saving; put back the starting styles',
    (tester) async {
      await size(tester, 412, 900);
      await open(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('AI'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Conversation style'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Ask'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();
      expect(find.text('আরে, মন খারাপ? চলো একটু হাঁটতে যাই।'), findsOneWidget);
      await shot(tester, 'phone_ai_try');
      await tester.scrollUntilVisible(
        find.text('Put back the starting styles'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Put back the starting styles'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.text('Save for all users'));
      await tester.pumpAndSettle();
      expect(server.lastSave!['stylePrompt'], 'DEFAULT STYLE');
      expect(server.lastSave!['callPrompt'], 'DEFAULT CALL');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unsaved changes survive moving between tabs', (tester) async {
    await size(tester, 360, 800);
    await open(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Overview'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsNothing);
    await shot(tester, 'phone_settings_after');
  });

  for (final (w, h) in [(320.0, 640.0), (1024.0, 768.0), (1280.0, 800.0)]) {
    testWidgets(
      'fits at ${w.toInt()}x${h.toInt()}; side rail on wide screens',
      (tester) async {
        await size(tester, w, h);
        await open(tester, b: w > 1000 ? Brightness.dark : Brightness.light);
        expect(
          find.byType(w >= 720 ? NavigationRail : NavigationBar),
          findsOneWidget,
        );
        await shot(tester, 'size_${w.toInt()}_overview');
        for (final tab in ['AI', 'Voice', 'Settings']) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: tab);
          await shot(tester, 'size_${w.toInt()}_${tab.toLowerCase()}');
        }
      },
    );
  }
}
