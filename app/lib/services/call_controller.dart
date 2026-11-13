import 'dart:async';

import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';
import '../models/chat.dart';
import 'backend.dart';
import 'chat_controller.dart';
import 'cloud_voice.dart';
import 'listener.dart';
import 'llm_client.dart';
import 'settings_store.dart';
import 'speaker.dart';
import 'text_utils.dart';

enum CallState { idle, connecting, listening, thinking, speaking, error }

/// The hands-free call loop: listen -> ask the AI -> speak -> listen again.
class CallController extends ChangeNotifier {
  CallController({
    required this.settings,
    required this.speaker,
    required this.listener,
    required this.sink,
    LlmClient? llm,
    CloudVoice? cloud,
    Future<bool> Function()? wake,
  }) : llm = llm ?? LlmClient(settings),
       cloud = cloud ?? CloudVoice(),
       _wake = wake ?? (() => wakeServer(total: const Duration(seconds: 60)));

  final SettingsStore settings;
  final Speaker speaker;
  final SpeechListener listener;
  final LlmClient llm;

  /// The admin's cloud voice, when voice mode is 'server'.
  final CloudVoice cloud;
  final Future<bool> Function() _wake;

  /// The open chat: call turns are written there as they happen.
  final CallSink sink;

  CallState state = CallState.idle;
  String partial = '';
  String? error;

  /// The last thing the user said and the reply, for the voice screen.
  String lastHeard = '';
  ChatMessage? lastReply;
  Duration elapsed = Duration.zero;

  /// Microphone loudness (0..1) while listening.
  double level = 0;

  /// The mic level as it changes, many times a second. Separate from
  /// [notifyListeners] so the voice screen does not rebuild for each level.
  final levels = ValueNotifier<double>(0);

  bool _active = false;
  int _turnId = 0;
  Timer? _timer;

  bool get inCall => _active;

  Future<void> start() async {
    if (_active) return;
    if (!settings.isConfigured) {
      _setError(L10n.current.needApiKey);
      return;
    }
    if (!settings.voiceEnabled) {
      _setError(L10n.current.voiceOff);
      return;
    }
    _active = true;
    error = null;
    lastHeard = '';
    lastReply = null;
    elapsed = Duration.zero;
    speaker.onError = (e) =>
        _setError(L10n.current.voiceError('$e'), keepGoing: true);
    listener.onLevel = (v) {
      level = v;
      levels.value = v;
    };
    _set(CallState.connecting);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed += const Duration(seconds: 1);
      notifyListeners();
    });
    // Wake a sleeping server while the user says their first words.
    unawaited(_wake().catchError((_) => false));
    try {
      // The voice and the microphone get ready side by side.
      final micReady = listener.init();
      await speaker.init();
      final voice = settings.remote.callOfflineVoice
          ? speaker.offlineTwin(settings.voice)
          : settings.voice;
      await speaker.prepare(
        voice,
        settings.speed,
        settings.pitch,
        cloud: settings.cloudVoice
            ? (cloud..deviceId = settings.deviceId).speak
            : null,
      );
      if (!await micReady) {
        throw Exception(L10n.current.micPermission);
      }
    } catch (e) {
      await hangUp();
      _setError(e.toString().replaceFirst('Exception: ', ''));
      return;
    }
    unawaited(_loop());
  }

  Future<void> _loop() async {
    while (_active) {
      final turn = ++_turnId;
      partial = '';
      _set(CallState.listening);
      String heard;
      try {
        heard = await listener.listenOnce(
          localeId: settings.speechLocale,
          pauseFor: Duration(milliseconds: settings.remote.callPauseMs),
          onWords: (words) {
            partial = words;
            notifyListeners();
          },
        );
      } catch (e) {
        await hangUp();
        _setError(e.toString().replaceFirst('Exception: ', ''));
        return;
      }
      if (!_active || turn != _turnId) return;
      if (heard.isEmpty) continue; // Silence: just keep listening.
      await _answer(heard, turn);
      // An interrupt starts a fresh loop, so this one bows out.
      if (!_active || turn != _turnId) return;
    }
  }

  Future<void> _answer(String heard, int turn) async {
    sink.callUserTurn(heard);
    lastHeard = heard;
    partial = '';
    error = null;
    _set(CallState.thinking);

    final messages = sink.historyForModel(limit: settings.remote.callHistory);
    final reply = sink.callBeginReply();
    lastReply = reply;
    _reply = reply;
    final splitter = SentenceSplitter();
    void speak(String sentence) {
      final clean = cleanForSpeech(sentence);
      if (clean.isEmpty) return;
      speaker.enqueue(clean);
      if (state == CallState.thinking) _set(CallState.speaking);
    }

    try {
      await for (final chunk in llm.streamChat(
        messages,
        call: true,
        agent: sink.agentId,
        context: sink.agentContext(),
        onEvent: (e) => sink.callAgentEvent(e, reply),
      )) {
        if (!_active || turn != _turnId) return;
        reply.text += chunk;
        sink.callReplyChanged(reply);
        notifyListeners();
        splitter.add(chunk).forEach(speak);
      }
      if (!_active || turn != _turnId) return;
      speak(splitter.flush());
      _reply = null;
      sink.callEndReply(reply);
      await speaker.waitUntilDone();
    } catch (e) {
      if (!_active || turn != _turnId) return; // Interrupted on purpose.
      final msg = e.toString().replaceFirst('Exception: ', '');
      _reply = null;
      sink.callEndReply(reply, error: msg);
      lastReply = null;
      _setError(msg, keepGoing: true);
    }
  }

  /// The reply still streaming, so an interrupt or hang-up can close it.
  ChatMessage? _reply;

  void _closeReply() {
    final r = _reply;
    _reply = null;
    if (r != null) sink.callEndReply(r, interrupted: true);
  }

  /// Cuts the AI off mid-answer and goes straight back to listening.
  Future<void> interrupt() async {
    if (!_active) return;
    if (state != CallState.thinking && state != CallState.speaking) return;
    _turnId++;
    _closeReply();
    llm.cancel();
    await speaker.stop();
    unawaited(_loop());
  }

  Future<void> hangUp() async {
    _active = false;
    _turnId++;
    _closeReply();
    _timer?.cancel();
    _timer = null;
    llm.cancel();
    listener.onLevel = null;
    level = 0;
    levels.value = 0;
    await listener.stop();
    await speaker.stop();
    cloud.close();
    _set(CallState.idle);
  }

  void _set(CallState s) {
    state = s;
    notifyListeners();
  }

  void _setError(String message, {bool keepGoing = false}) {
    error = message;
    if (!keepGoing) state = CallState.error;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    levels.dispose();
    super.dispose();
  }
}
