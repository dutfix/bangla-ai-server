import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/l10n.dart';

/// Speech-to-text using the phone's built-in recognizer (Google on Android,
/// Apple on iOS) through the speech_to_text plugin. Free, no API key, and
/// works offline on many phones once the offline language pack is installed.
/// Listens in Bangla (bn-BD) by default.
class SpeechListener {
  final _stt = SpeechToText();
  bool _ready = false;
  List<String>? _localeIds;
  Completer<String>? _turn;
  String _lastWords = '';

  /// Live transcript while the user talks.
  void Function(String words)? onPartial;

  /// Microphone loudness while listening, from 0 (quiet) to 1 (loud).
  void Function(double level)? onLevel;

  /// Asks for the microphone permission on first use.
  Future<bool> init() async {
    if (_ready) return true;
    _ready = await _stt.initialize(onStatus: _onStatus, onError: _onError);
    return _ready;
  }

  /// Listens for one thing the user says. Returns '' if they said nothing.
  /// It ends on its own after a short pause in speech.
  Future<String> listenOnce({
    String? localeId,
    void Function(String words)? onWords,
    Duration pauseFor = const Duration(seconds: 2),
  }) async {
    if (!await init()) {
      throw Exception(L10n.current.speechUnavailable);
    }
    final locale = await _bestLocale(localeId ?? 'bn_BD');
    await _stt.cancel();
    _lastWords = '';
    final turn = Completer<String>();
    _turn = turn;
    await _stt.listen(
      onSoundLevelChange: (db) {
        // Android reports roughly -2..10 dB, iOS -50..0; map both to 0..1.
        final v = db < -10 ? (db + 50) / 50 : (db + 2) / 12;
        onLevel?.call(v.clamp(0.0, 1.0).toDouble());
      },
      onResult: (r) {
        _lastWords = r.recognizedWords;
        (onWords ?? onPartial)?.call(_lastWords);
        if (r.finalResult) _finish(_lastWords);
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 60),
        pauseFor: pauseFor,
        localeId: locale,
      ),
    );
    // Safety net in case the plugin never reports the end.
    return turn.future.timeout(
      const Duration(seconds: 70),
      onTimeout: () => _lastWords,
    );
  }

  /// The phone's own id for [wanted] (e.g. bn_BD or bn-BD), else another
  /// locale of the same language (bn_IN), else [wanted] itself: Google's
  /// recognizer often handles Bangla even when it is not listed.
  Future<String> _bestLocale(String wanted) async {
    try {
      _localeIds ??= (await _stt.locales()).map((l) => l.localeId).toList();
    } catch (_) {
      _localeIds = const [];
    }
    String norm(String id) => id.replaceAll('-', '_').toLowerCase();
    final ids = _localeIds!;
    final exact = ids.where((id) => norm(id) == norm(wanted));
    if (exact.isNotEmpty) return exact.first;
    final lang = norm(wanted).split('_').first;
    final same = ids.where((id) => norm(id).split('_').first == lang);
    if (same.isNotEmpty) return same.first;
    return wanted;
  }

  Future<void> stop() async {
    _finish('');
    await _stt.cancel();
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus) _finish(_lastWords);
  }

  void _onError(SpeechRecognitionError e) {
    // "no match" / "speech timeout" just mean the user said nothing.
    _finish(_lastWords);
  }

  void _finish(String words) {
    final t = _turn;
    _turn = null;
    if (t != null && !t.isCompleted) t.complete(words.trim());
  }
}
