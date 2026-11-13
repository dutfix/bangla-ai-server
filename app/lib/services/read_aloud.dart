import 'package:flutter/foundation.dart';

import 'cloud_voice.dart';
import 'settings_store.dart';
import 'speaker.dart';
import 'text_utils.dart';

/// Reads one chat message aloud with the admin's voice.
class ReadAloud extends ChangeNotifier {
  ReadAloud(this.settings, this.speaker, {CloudVoice? cloud})
    : cloud = cloud ?? CloudVoice();
  final SettingsStore settings;
  final Speaker speaker;
  final CloudVoice cloud;

  /// The message being read, or preparing to be read.
  String? messageId;
  bool preparing = false;
  int _run = 0;

  bool isReading(String id) => messageId == id;

  /// Starts reading [text] with the admin's voice (phone or cloud).
  Future<void> read(String id, String text) async {
    await stop();
    final run = ++_run;
    messageId = id;
    preparing = true;
    notifyListeners();
    Object? failure;
    speaker.onError = (e) => failure = e;
    try {
      await speaker.prepare(
        settings.voice,
        settings.speed,
        settings.pitch,
        cloud: settings.cloudVoice
            ? (cloud..deviceId = settings.deviceId).speak
            : null,
      );
      if (run != _run) return;
      preparing = false;
      notifyListeners();
      final splitter = SentenceSplitter();
      final sentences = [...splitter.add('$text\n'), splitter.flush()];
      for (final s in sentences) {
        final clean = cleanForSpeech(s);
        if (clean.isNotEmpty) speaker.enqueue(clean);
      }
      await speaker.waitUntilDone();
      final f = failure;
      if (f != null && run == _run) {
        throw Exception('$f');
      }
    } finally {
      if (run == _run) {
        messageId = null;
        preparing = false;
        notifyListeners();
      }
    }
  }

  Future<void> stop() async {
    if (messageId == null) return;
    _run++;
    messageId = null;
    preparing = false;
    notifyListeners();
    await speaker.stop();
  }
}
