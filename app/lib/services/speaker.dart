import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/voice.dart';

/// What is missing for good Bangla speech on this phone.
enum VoiceSetup {
  /// Google's engine and its Bangla voice data are installed.
  ready,

  /// Speech Services by Google is not installed (or disabled).
  noGoogleEngine,

  /// Google's engine is there but its Bangla voice data is not.
  noBanglaData,
}

/// Speaks with the phone's own engine through flutter_tts.
///
/// On Android it always uses Speech Services by Google
/// (com.google.android.tts) when that is installed, even when another engine
/// such as Samsung's is the phone's default, and speaks Bangla: the chosen
/// voice, else bn-BD, else bn-IN. Sentences are queued so the AI starts
/// talking after its first sentence.
///
/// When the admin set up a cloud voice, [prepare] gets a function that
/// fetches each sentence's audio from the server. Every sentence's audio is
/// fetched as soon as it is queued, so the next one is ready while the
/// current one plays. A sentence whose audio fails is spoken by the phone.
class Speaker extends ChangeNotifier {
  Speaker({FlutterTts? tts, AudioPlayer Function()? player})
    : _tts = tts ?? FlutterTts(),
      _newPlayer = player ?? AudioPlayer.new;

  static const googleEngine = 'com.google.android.tts';

  final FlutterTts _tts;
  Future<void>? _init;

  /// True when the Google engine is installed and in use.
  bool usingGoogle = false;
  VoiceSetup setup = VoiceSetup.ready;

  /// The Bangla voices the engine reports, best first.
  List<VoiceOption> voices = const [];

  final AudioPlayer Function() _newPlayer;
  AudioPlayer? _player;
  Future<Uint8List> Function(String text)? _cloud;
  Completer<void>? _clip;

  final _queue = Queue<_Line>();
  bool _playing = false;
  int _epoch = 0;
  Completer<void>? _idle;

  /// Called when speaking fails (the run goes on with the next sentence).
  void Function(Object error)? onError;

  bool get isBusy => _playing || _queue.isNotEmpty;

  static bool get _android => !kIsWeb && Platform.isAndroid;

  /// Picks the Google engine and reads its Bangla voices. Safe to call often.
  Future<void> init() => _init ??= _doInit();

  Future<void> _doInit() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      if (_android) {
        final engines =
            ((await _tts.getEngines) as List?)?.map((e) => '$e').toList() ??
            const <String>[];
        usingGoogle = engines.contains(googleEngine);
        if (usingGoogle) {
          final current = '${await _tts.getDefaultEngine ?? ''}';
          if (current != googleEngine) await _tts.setEngine(googleEngine);
          // setEngine restarts the engine; give it a moment to bind.
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
      await refresh();
    } catch (_) {
      _init = null; // Try again next time.
    }
  }

  /// Reads the engine's Bangla voices again (for example after the user
  /// installed Google's Bangla voice data) and updates [setup].
  Future<void> refresh() async {
    final raw = ((await _tts.getVoices) as List?) ?? const [];
    final list = <VoiceOption>[];
    for (final m in raw.whereType<Map<dynamic, dynamic>>()) {
      final v = VoiceOption.fromEngine(m);
      if (v != null && !VoiceOption.notInstalled(m)) list.add(v);
    }
    list.sort(compareBanglaVoices);
    voices = list;
    var installed = list.any((v) => !v.network);
    if (_android && !installed) {
      for (final l in ['bn-BD', 'bn-IN']) {
        try {
          if (await _tts.isLanguageInstalled(l) == true) installed = true;
        } catch (_) {}
      }
    }
    setup = _android && !usingGoogle
        ? VoiceSetup.noGoogleEngine
        : (installed || (!_android && list.isNotEmpty))
        ? VoiceSetup.ready
        : VoiceSetup.noBanglaData;
    notifyListeners();
  }

  /// The voice to use when the user has not picked one: the first Bangladesh
  /// voice that works offline, else the first Bangla voice.
  VoiceOption? get defaultVoice => voices.isEmpty ? null : voices.first;

  /// The offline version of a network voice (bn-bd-x-ban-network ->
  /// bn-bd-x-ban-local) when the phone has it: it starts speaking without a
  /// trip to Google's servers for every sentence.
  VoiceOption? offlineTwin(VoiceOption? voice) {
    final v = voice ?? defaultVoice;
    // The admin's saved voice carries only a name and a locale.
    if (v == null || !(v.network || v.name.contains('-network'))) return voice;
    final twinName = v.name.replaceAll('-network', '-local');
    for (final o in voices) {
      if (!o.network && o.name == twinName) return o;
    }
    for (final o in voices) {
      if (!o.network && o.locale.toLowerCase() == v.locale.toLowerCase()) {
        return o;
      }
    }
    return voice;
  }

  /// Sets the voice, speed (1.0 = normal) and pitch (1.0 = normal), and
  /// whether sentences come from the admin's cloud voice ([cloud] fetches a
  /// sentence's audio) or the phone's engine (null).
  Future<void> prepare(
    VoiceOption? voice,
    double speed,
    double pitch, {
    Future<Uint8List> Function(String text)? cloud,
  }) async {
    _cloud = cloud;
    await init();
    final v = (voice != null && voices.contains(voice)) ? voice : defaultVoice;
    var set = false;
    if (v != null) {
      try {
        await _tts.setVoice({'name': v.name, 'locale': v.locale});
        set = true;
      } catch (_) {}
    }
    if (!set) {
      for (final l in ['bn-BD', 'bn-IN']) {
        try {
          if (await _tts.setLanguage(l) == 1) break;
        } catch (_) {}
      }
    }
    // flutter_tts: 0.5 is the engine's normal rate.
    await _tts.setSpeechRate((speed * 0.5).clamp(0.1, 1.0));
    await _tts.setPitch(pitch.clamp(0.5, 2.0));
  }

  void enqueue(String text) {
    if (text.trim().isEmpty) return;
    final cloud = _cloud;
    _queue.add(
      _Line(
        text,
        cloud == null
            ? null
            : cloud(text).then<Uint8List?>(
                (b) => b.isEmpty ? null : b,
                onError: (Object e) {
                  onCloudError?.call(e);
                  return null;
                },
              ),
      ),
    );
    _idle ??= Completer<void>();
    if (!_playing) unawaited(_pump(_epoch));
  }

  Future<void> _pump(int epoch) async {
    _playing = true;
    try {
      while (_queue.isNotEmpty && epoch == _epoch) {
        final line = _queue.removeFirst();
        try {
          final audio = line.audio == null ? null : await line.audio;
          if (epoch != _epoch) break;
          if (audio != null) {
            await _play(audio);
          } else {
            await _tts.speak(line.text);
          }
        } catch (e) {
          if (epoch == _epoch) onError?.call(e);
        }
      }
    } finally {
      if (epoch == _epoch) {
        _playing = false;
        _idle?.complete();
        _idle = null;
      }
    }
  }

  /// Called when the cloud voice fails for a sentence (the phone speaks it).
  void Function(Object error)? onCloudError;

  Future<void> _play(Uint8List audio) async {
    final p = _player ??= _newPlayer();
    final done = Completer<void>();
    _clip = done;
    final sub = p.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    try {
      await p.play(BytesSource(audio, mimeType: 'audio/mpeg'));
      await done.future.timeout(const Duration(seconds: 90), onTimeout: () {});
    } finally {
      await sub.cancel();
      if (identical(_clip, done)) _clip = null;
    }
  }

  /// Resolves once everything queued has been spoken (or [stop] was called).
  Future<void> waitUntilDone() async {
    final idle = _idle;
    if (idle != null) await idle.future;
  }

  /// Stops speaking at once and drops anything queued.
  Future<void> stop() async {
    _epoch++;
    _queue.clear();
    _playing = false;
    _idle?.complete();
    _idle = null;
    final clip = _clip;
    _clip = null;
    if (clip != null && !clip.isCompleted) clip.complete();
    try {
      await _player?.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Speaks [sample] in [voice] at the given speed and pitch.
  Future<void> test(
    VoiceOption voice,
    String sample, {
    required double speed,
    required double pitch,
  }) async {
    await stop();
    await prepare(voice, speed, pitch);
    enqueue(sample);
    await waitUntilDone();
  }
}

/// One queued sentence, with its cloud audio on the way (null: the phone
/// speaks it; a null result: the cloud failed and the phone speaks it).
class _Line {
  _Line(this.text, this.audio);
  final String text;
  final Future<Uint8List?>? audio;
}
