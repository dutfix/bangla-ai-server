import 'dart:async';

import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';
import '../models/chat.dart';
import 'chat_store.dart';
import 'llm_client.dart';
import 'settings_store.dart';

/// What the voice call needs from the chat: the history to send and a place
/// to write each turn, so call turns show up in the transcript.
abstract class CallSink {
  List<Map<String, String>> historyForModel({int limit});
  void callUserTurn(String text);
  ChatMessage callBeginReply();
  void callReplyChanged(ChatMessage reply);
  void callEndReply(ChatMessage reply, {bool interrupted, String? error});
}

/// Runs the text chat: sending, streaming, stop, regenerate, edit & resend
/// and auto-titles. Owns which conversation is open.
class ChatController extends ChangeNotifier implements CallSink {
  ChatController({
    required this.store,
    required this.settings,
    LlmClient? llm,
    LlmClient? titleLlm,
  }) : llm = llm ?? LlmClient(settings),
       titleLlm = titleLlm ?? LlmClient(settings);

  final ChatStore store;
  final SettingsStore settings;
  final LlmClient llm;
  final LlmClient titleLlm;

  Conversation? _current;
  Conversation? get current => _current;
  List<ChatMessage> get messages => _current?.messages ?? const [];

  /// The reply being streamed right now, if any.
  ChatMessage? streaming;
  bool get generating => streaming != null;
  int _gen = 0;

  /// Last error that is not tied to a message (e.g. no API key).
  String? notice;

  /// Ticks while the last reply grows (typed or spoken). Only the tile of
  /// that reply listens, so the rest of the chat screen does not rebuild on
  /// every chunk. At most one tick per [_tickEvery]; [notifyListeners] is
  /// kept for changes to the list itself.
  Listenable get replyTicks => _ticks;
  final _ticks = _Ticks();
  static const _tickEvery = Duration(milliseconds: 40);
  Timer? _tickTimer;

  void _tick() {
    _tickTimer ??= Timer(_tickEvery, () {
      _tickTimer = null;
      _ticks.ping();
    });
  }

  void _flushTicks() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _ticks.ping();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _ticks.dispose();
    super.dispose();
  }

  void newChat() {
    stop();
    _current = null;
    notice = null;
    notifyListeners();
  }

  void open(Conversation c) {
    if (identical(c, _current)) return;
    stop();
    _current = c;
    notice = null;
    notifyListeners();
  }

  /// Called when a conversation was deleted from the history.
  void forget(Conversation c) {
    if (_current?.id == c.id) newChat();
  }

  Conversation _ensureConversation() {
    return _current ??= store.create();
  }

  /// Sends a new user message and streams the reply.
  Future<void> send(String text) async {
    final t = text.trim();
    if (t.isEmpty || generating) return;
    if (!settings.isConfigured) {
      notice = L10n.current.needApiKey;
      notifyListeners();
      return;
    }
    notice = null;
    final c = _ensureConversation();
    c.messages.add(ChatMessage(role: Role.user, text: t));
    if (!c.titled && c.messages.length == 1) c.title = provisionalTitle(t);
    store.changed(c);
    await _reply(c);
  }

  /// Throws away [reply] (and anything after it) and asks again.
  Future<void> regenerate(ChatMessage reply) async {
    final c = _current;
    if (c == null) return;
    stop();
    final i = c.messages.indexWhere((m) => m.id == reply.id);
    if (i < 0) return;
    c.messages.removeRange(i, c.messages.length);
    store.changed(c);
    await _reply(c);
  }

  /// Replaces a user message with [text], drops everything after it and
  /// asks again.
  Future<void> editAndResend(ChatMessage message, String text) async {
    final c = _current;
    final t = text.trim();
    if (c == null || t.isEmpty) return;
    stop();
    final i = c.messages.indexWhere((m) => m.id == message.id);
    if (i < 0) return;
    c.messages.removeRange(i, c.messages.length);
    c.messages.add(ChatMessage(role: Role.user, text: t));
    if (i == 0 && !c.titled) c.title = provisionalTitle(t);
    store.changed(c);
    await _reply(c);
  }

  /// Stops the reply that is streaming.
  void stop() {
    final s = streaming;
    if (s == null) return;
    _gen++;
    llm.cancel();
    s.stopped = true;
    streaming = null;
    final c = _current;
    if (c != null) store.changed(c, touch: false);
    _flushTicks();
    notifyListeners();
  }

  Future<void> _reply(Conversation c) async {
    if (!settings.isConfigured) {
      notice = L10n.current.needApiKey;
      notifyListeners();
      return;
    }
    final gen = ++_gen;
    final history = _history(c.messages);
    final reply = ChatMessage(role: Role.assistant, model: settings.model);
    c.messages.add(reply);
    streaming = reply;
    notifyListeners();
    try {
      await for (final chunk in llm.streamChat([
        ..._systemMessages(call: false),
        ...history,
      ])) {
        if (gen != _gen) return;
        final first = reply.text.isEmpty;
        reply.text += chunk;
        // The first words replace the typing dots and show the actions
        // area, so the list itself changes once; after that only the tile.
        first ? notifyListeners() : _tick();
      }
      if (gen != _gen) return;
      if (reply.text.trim().isEmpty) {
        reply.error = L10n.current.emptyReply;
      }
    } catch (e) {
      if (gen != _gen) return; // Stopped on purpose.
      reply.error = e.toString().replaceFirst('Exception: ', '');
    }
    streaming = null;
    store.changed(c);
    _flushTicks();
    notifyListeners();
    if (reply.error == null) unawaited(_autoTitle(c));
  }

  /// The reply-language rule (Bangla by default), merged with the call
  /// style in calls and the user's optional system prompt.
  List<Map<String, String>> _systemMessages({required bool call}) => [
    {'role': 'system', 'content': settings.systemMessage(call: call)},
  ];

  /// The messages to send: failed replies are left out, and so is a user
  /// message whose reply failed (it is still the last one).
  static List<Map<String, String>> _history(
    List<ChatMessage> messages, {
    int limit = 40,
  }) {
    final out = <Map<String, String>>[];
    for (final m in messages) {
      if (m.error != null || (m.text.trim().isEmpty && !m.isUser)) continue;
      final role = m.isUser ? 'user' : 'assistant';
      final text = m.stopped && !m.isUser ? '${m.text} ...' : m.text;
      if (out.isNotEmpty && out.last['role'] == role) {
        // Two in a row (after a failed reply): merge so roles alternate.
        out.last['content'] = '${out.last['content']}\n\n$text';
      } else {
        out.add({'role': role, 'content': text});
      }
    }
    return out.length > limit ? out.sublist(out.length - limit) : out;
  }

  @visibleForTesting
  static List<Map<String, String>> historyOf(List<ChatMessage> m) =>
      _history(m);

  /// How the AI is asked for a chat title: in Bangla by default.
  static String titleInstruction(String language) =>
      language == AppLanguage.english
      ? 'You write short titles for chats. Reply with only the title: '
            '2 to 6 words, no quotes, no punctuation at the end, in English.'
      : 'তুমি চ্যাটের ছোট শিরোনাম লেখো। শুধু শিরোনামটি লেখো: ২ থেকে ৬ '
            'শব্দ, বাংলায় (বাংলা লিপিতে), কোনো উদ্ধৃতিচিহ্ন বা শেষে '
            'যতিচিহ্ন ছাড়া। Write only the title, in Bangla script.';

  Future<void> _autoTitle(Conversation c) async {
    if (c.titled) return;
    final firstUser = c.messages.where((m) => m.isUser).firstOrNull;
    final firstReply = c.messages
        .where((m) => !m.isUser && m.error == null && m.text.isNotEmpty)
        .firstOrNull;
    if (firstUser == null || firstReply == null) return;
    c.titled = true; // Only try once per chat.
    try {
      String clip(String s) => s.length > 1200 ? s.substring(0, 1200) : s;
      final raw = await titleLlm.complete([
        {'role': 'system', 'content': titleInstruction(settings.language)},
        {
          'role': 'user',
          'content':
              'User: ${clip(firstUser.text)}\n\n'
              'Assistant: ${clip(firstReply.text)}\n\n'
              '${settings.language == AppLanguage.english ? 'Title' : 'শিরোনাম'}:',
        },
      ], timeout: const Duration(seconds: 30));
      final t = cleanTitle(raw);
      if (t.isNotEmpty && store.byId(c.id) != null) {
        c.title = t;
        store.changed(c, touch: false);
        notifyListeners();
      }
    } catch (_) {
      // Keep the first-words title.
    }
  }

  // ---- CallSink: voice-call turns go into the open chat. ----

  @override
  List<Map<String, String>> historyForModel({int limit = 20}) => [
    ..._systemMessages(call: true),
    ..._history(messages, limit: limit),
  ];

  @override
  void callUserTurn(String text) {
    stop();
    final c = _ensureConversation();
    c.messages.add(ChatMessage(role: Role.user, text: text, viaVoice: true));
    if (!c.titled && c.messages.length == 1) c.title = provisionalTitle(text);
    store.changed(c);
    notifyListeners();
  }

  @override
  ChatMessage callBeginReply() {
    final c = _ensureConversation();
    final m = ChatMessage(
      role: Role.assistant,
      viaVoice: true,
      model: settings.model,
    );
    c.messages.add(m);
    notifyListeners();
    return m;
  }

  @override
  void callReplyChanged(ChatMessage reply) => _tick();

  @override
  void callEndReply(
    ChatMessage reply, {
    bool interrupted = false,
    String? error,
  }) {
    final c = _current;
    if (c == null) return;
    if (error != null) {
      reply.error = error;
    } else if (interrupted) {
      if (reply.text.trim().isEmpty) {
        c.messages.remove(reply);
      } else {
        reply.stopped = true;
      }
    }
    store.changed(c);
    _flushTicks();
    notifyListeners();
    if (error == null && !interrupted) unawaited(_autoTitle(c));
  }
}

class _Ticks extends ChangeNotifier {
  void ping() => notifyListeners();
}
