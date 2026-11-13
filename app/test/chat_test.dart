import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_voice_call/l10n/app_localizations.dart';
import 'package:omni_voice_call/models/chat.dart';
import 'package:omni_voice_call/services/chat_controller.dart';
import 'package:omni_voice_call/services/chat_store.dart';
import 'package:omni_voice_call/services/llm_client.dart';
import 'package:omni_voice_call/services/settings_store.dart';
import 'package:omni_voice_call/widgets/sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Streams canned words and records what it was asked.
class FakeLlm extends LlmClient {
  FakeLlm(super.settings, {this.words = const ['Hello', ' there', '.']});
  final List<String> words;
  final asked = <List<Map<String, String>>>[];
  final askedAgent = <String?>[];
  final askedContext = <Map<String, Object?>?>[];

  /// Agent events sent before the words.
  List<Map<String, Object?>> events = const [];
  Completer<void>? gate;
  bool cancelled = false;

  @override
  Stream<String> streamChat(
    List<Map<String, String>> messages, {
    String? model,
    void Function()? onWaking,
    bool call = false,
    String? agent,
    Map<String, Object?>? context,
    void Function(Map<String, Object?> event)? onEvent,
  }) async* {
    asked.add(messages);
    askedAgent.add(agent);
    askedContext.add(context);
    for (final e in events) {
      onEvent?.call(e);
    }
    for (final w in words) {
      if (gate != null) await gate!.future;
      if (cancelled) return;
      yield w;
    }
  }

  @override
  Future<String> complete(
    List<Map<String, String>> messages, {
    String? model,
    Duration timeout = const Duration(seconds: 120),
  }) async => '"Friendly Greeting."';

  @override
  void cancel() => cancelled = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late SettingsStore settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('chats');
    settings = SettingsStore();
    await settings.load();
    await settings.setLanguage('en');
  });

  tearDown(() => dir.delete(recursive: true));

  ChatController controller(ChatStore store, FakeLlm llm) =>
      ChatController(store: store, settings: settings, llm: llm, titleLlm: llm);

  test('send streams a reply, auto-titles and saves to disk', () async {
    final store = ChatStore(directory: () async => dir);
    await store.load();
    final llm = FakeLlm(settings);
    final chat = controller(store, llm);

    await chat.send('Say hi to me please');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(chat.messages.map((m) => m.text), [
      'Say hi to me please',
      'Hello there.',
    ]);
    expect(chat.current!.title, 'Friendly Greeting');
    expect(llm.asked.single.last, {
      'role': 'user',
      'content': 'Say hi to me please',
    });

    await store.flush();
    final again = ChatStore(directory: () async => dir);
    await again.load();
    expect(again.conversations.single.messages.length, 2);
    expect(again.conversations.single.title, 'Friendly Greeting');
  });

  test('the app sends its language rule; the server adds the styles', () async {
    final store = ChatStore(directory: () async => dir);
    await store.load();
    final llm = FakeLlm(settings);
    final chat = controller(store, llm);

    await chat.send('Hi');
    expect(llm.asked.single.first['role'], 'system');
    expect(llm.asked.single.first['content'], contains('English'));
    expect(llm.asked.single.first['content'], isNot(contains('voice call')));

    await settings.setLanguage('bn');
    final call = chat.historyForModel();
    expect(call.first['role'], 'system');
    // The call style and the conversation style are the admin's, added by
    // the server; the app only says which language to answer in.
    expect(call.first['content'], isNot(contains('voice call')));
    expect(call.first['content'], contains('Bangla'));
  });

  test('stop keeps the partial reply and marks it stopped', () async {
    final store = ChatStore(directory: () async => dir);
    await store.load();
    final llm = FakeLlm(settings)..gate = Completer<void>();
    final chat = controller(store, llm);

    final sending = chat.send('Long answer please');
    await Future<void>.delayed(Duration.zero);
    expect(chat.generating, isTrue);
    chat.stop();
    llm.gate!.complete();
    await sending;

    expect(chat.generating, isFalse);
    expect(chat.messages.last.stopped, isTrue);
    expect(llm.cancelled, isTrue);
  });

  test('regenerate and edit-and-resend replace what came after', () async {
    final store = ChatStore(directory: () async => dir);
    await store.load();
    final llm = FakeLlm(settings);
    final chat = controller(store, llm);

    await chat.send('First');
    await chat.send('Second');
    expect(chat.messages.length, 4);

    await chat.regenerate(chat.messages.last);
    expect(chat.messages.length, 4);
    expect(llm.asked.length, 3);

    await chat.editAndResend(chat.messages[0], 'First, edited');
    expect(chat.messages.map((m) => m.text), ['First, edited', 'Hello there.']);
  });

  test('voice call turns are written into the open chat', () async {
    final store = ChatStore(directory: () async => dir);
    await store.load();
    final chat = controller(store, FakeLlm(settings));

    chat.callUserTurn('What time is it');
    final reply = chat.callBeginReply()..text = 'It is noon.';
    chat.callEndReply(reply);
    final cut = chat.callBeginReply();
    chat.callEndReply(cut, interrupted: true); // Empty: dropped.

    expect(chat.messages.length, 2);
    expect(chat.messages.every((m) => m.viaVoice), isTrue);
    expect(store.conversations.single.title, 'What time is it');
  });

  test('history skips failed replies and keeps roles alternating', () {
    final h = ChatController.historyOf([
      ChatMessage(role: Role.user, text: 'a'),
      ChatMessage(role: Role.assistant, error: 'boom'),
      ChatMessage(role: Role.user, text: 'b'),
    ]);
    expect(h, [
      {'role': 'user', 'content': 'a\n\nb'},
    ]);
  });

  test('search, rename and delete', () async {
    final store = ChatStore(directory: () async => dir);
    await store.load();
    final c = store.create()
      ..messages.add(
        ChatMessage(role: Role.user, text: 'Plan a trip to Sylhet'),
      )
      ..title = 'Trip';
    store.changed(c);

    expect(store.search('sylhet').single.snippet, contains('Sylhet'));
    expect(store.search('trip').single.snippet, isNull);
    expect(store.search('paris'), isEmpty);

    store.rename(c, 'Sylhet weekend');
    expect(store.conversations.single.title, 'Sylhet weekend');
    store.delete(c);
    expect(store.conversations, isEmpty);
  });

  test('titles', () {
    expect(
      provisionalTitle('  how   do I bake bread at home today ok '),
      'how do I bake bread at...',
    );
    expect(cleanTitle('Title: "Baking Bread."\nextra'), 'Baking Bread');
  });

  test(
    'models come from the server; a pick the server drops falls back',
    () async {
      expect(settings.models, ['auto', 'auto/fast']);
      expect(settings.model, 'auto');
      await settings.setModel('auto/fast');
      expect(settings.model, 'auto/fast');
      settings.remote = RemoteConfig.fromJson({
        'models': ['gpt-x', 'auto'],
        'defaultModel': 'gpt-x',
      });
      expect(settings.model, 'gpt-x');
      expect(RemoteConfig.fromJson({'models': []}).models, ['auto']);
    },
  );

  test(
    'voice, speed and pitch are the admin\'s; voice is off unless turned on',
    () async {
      settings.remote = RemoteConfig.fromJson({
        'voiceName': 'bn-bd-x-ban-local',
        'voiceLocale': 'bn-BD',
        'speed': 1.3,
        'pitch': 0.8,
        'enabled': false,
        'disabledMessage': 'Paused',
      });
      expect(settings.voice!.name, 'bn-bd-x-ban-local');
      expect(settings.speed, 1.3);
      expect(settings.pitch, 0.8);
      expect(settings.isConfigured, isFalse);
      // Voice is the admin's: off unless the server turns it on.
      expect(settings.voiceEnabled, isFalse);
      expect(settings.cloudVoice, isFalse);
    },
  );

  test('sidebar groups chats by day', () {
    final l = lookupAppLocalizations(const Locale('en'));
    final now = DateTime(2026, 11, 12, 22);
    expect(sidebarGroupOf(DateTime(2026, 11, 12, 1), now, l), 'Today');
    expect(sidebarGroupOf(DateTime(2026, 11, 11, 23), now, l), 'Yesterday');
    expect(sidebarGroupOf(DateTime(2026, 11, 8), now, l), 'Previous 7 days');
    expect(sidebarGroupOf(DateTime(2026, 10, 20), now, l), 'Previous 30 days');
    expect(sidebarGroupOf(DateTime(2026, 3, 2), now, l), 'March');
    expect(sidebarGroupOf(DateTime(2025, 3, 2), now, l), '2025');
  });
}
