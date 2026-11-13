import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_voice_call/models/voice.dart';
import 'package:omni_voice_call/services/llm_client.dart';
import 'package:omni_voice_call/services/settings_store.dart';
import 'package:omni_voice_call/services/speaker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final spoken = <String>[];

  setUp(() {
    spoken.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
          c,
        ) async {
          if (c.method == 'getVoices') {
            return [
              {'name': 'bn-bd-x-ban-network', 'locale': 'bn-BD'},
              {'name': 'bn-bd-x-ban-local', 'locale': 'bn-BD'},
              {'name': 'bn-in-x-bnf-network', 'locale': 'bn-IN'},
            ];
          }
          if (c.method == 'speak') spoken.add('${c.arguments}');
          return 1;
        });
  });

  test('remote voice settings: off unless the admin turns voice on', () {
    final off = RemoteConfig.fromJson({'voiceMode': 'server'});
    expect(off.voiceEnabled, isFalse);
    expect(off.voiceMode, 'off');
    expect(off.callPauseMs, 900);
    final cloud = RemoteConfig.fromJson({
      'voiceEnabled': true,
      'voiceMode': 'server',
      'callPauseMs': 700,
      'callHistory': 6,
      'callOfflineVoice': false,
    });
    expect(cloud.voiceMode, 'server');
    expect(cloud.callPauseMs, 700);
    expect(cloud.callHistory, 6);
    expect(cloud.callOfflineVoice, isFalse);
    expect(RemoteConfig.fromJson(cloud.toJson()).voiceMode, 'server');
    expect(
      RemoteConfig.fromJson({'voiceEnabled': true, 'voiceMode': 'x'}).voiceMode,
      'device',
    );
  });

  test('old voice overrides are dropped when the app updates', () async {
    SharedPreferences.setMockInitialValues({
      'defaultsVersion': 1,
      'voiceName': 'bn-in-x-bnf-network',
      'voiceLocale': 'bn-IN',
      'userSpeed': 1.8,
    });
    final s = SettingsStore();
    await s.load();
    s.remote = RemoteConfig.fromJson({'speed': 1.1});
    expect(s.speed, 1.1);
    expect(s.voice, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('voiceName'), isNull);
    expect(prefs.getInt('defaultsVersion'), 2);
  });

  test('call turns ask the server for the call settings', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsStore();
    await settings.load();
    settings.markServerAwake();
    final bodies = <Map<String, dynamic>>[];
    final headers = <Map<String, String>>[];
    final llm = LlmClient(
      settings,
      clientFactory: () => MockClient.streaming((req, body) async {
        headers.add(req.headers);
        bodies.add(
          jsonDecode(utf8.decode(await body.toBytes())) as Map<String, dynamic>,
        );
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"হাই"}}]}\n\ndata: [DONE]\n\n',
            ),
          ),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );
    final msgs = [
      {'role': 'user', 'content': 'হ্যালো'},
    ];
    expect(await llm.streamChat(msgs, call: true).join(), 'হাই');
    expect(await llm.streamChat(msgs).join(), 'হাই');
    expect(bodies[0]['call'], isTrue);
    expect(settings.deviceId, hasLength(24));
    expect(headers.first['x-device'], settings.deviceId);
    expect(bodies[1].containsKey('call'), isFalse);
  });

  test('a network voice uses its offline twin in calls', () async {
    final sp = Speaker();
    await sp.init();
    const net = VoiceOption(name: 'bn-bd-x-ban-network', locale: 'bn-BD');
    expect(sp.offlineTwin(net)!.name, 'bn-bd-x-ban-local');
    const local = VoiceOption(name: 'bn-bd-x-ban-local', locale: 'bn-BD');
    expect(sp.offlineTwin(local), local);
    // No offline bn-IN voice on this phone: keep the network one.
    const india = VoiceOption(name: 'bn-in-x-bnf-network', locale: 'bn-IN');
    expect(sp.offlineTwin(india), india);
  });

  test('cloud voice: every sentence is fetched at once; a failed one is '
      'spoken by the phone', () async {
    final sp = Speaker();
    final asked = <String>[];
    final gates = <String, Completer<Uint8List>>{};
    await sp.prepare(
      null,
      1,
      1,
      cloud: (text) {
        asked.add(text);
        return (gates[text] = Completer<Uint8List>()).future;
      },
    );
    Object? cloudError;
    sp.onCloudError = (e) => cloudError = e;
    sp.enqueue('প্রথম বাক্য।');
    sp.enqueue('দ্বিতীয় বাক্য।');
    sp.enqueue('তৃতীয় বাক্য।');
    await Future<void>.delayed(Duration.zero);
    // All three are on their way before the first one is played.
    expect(asked, ['প্রথম বাক্য।', 'দ্বিতীয় বাক্য।', 'তৃতীয় বাক্য।']);
    for (final g in gates.values) {
      g.completeError(Exception('voice 502'));
    }
    await sp.waitUntilDone();
    expect(spoken, ['প্রথম বাক্য।', 'দ্বিতীয় বাক্য।', 'তৃতীয় বাক্য।']);
    expect('$cloudError', contains('voice 502'));
  });
}
