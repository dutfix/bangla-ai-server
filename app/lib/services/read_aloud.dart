import 'package:flutter/foundation.dart';

import 'settings_store.dart';
import 'speaker.dart';
import 'text_utils.dart';

/// Reads one chat message aloud with the chosen call voice.
class ReadAloud extends ChangeNotifier {
  ReadAloud(this.settings, this.speaker);
  final SettingsStore settings;
  final Speaker speaker;

  /// The message being read, or preparing to be read.
  String? messageId;
  bool preparing = false;
  int _run = 0;

  bool isReading(String id) => messageId == id;

  /// Starts reading [text] with the chosen Google Bangla voice.
  Future<void> read(String id, String text) async {
    await stop();
    final run = ++_run;
    messageId = id;
    preparing = true;
    notifyListeners();
    Object? failure;
    speaker.onError = (e) => failure = e;
    try {
      await speaker.prepare(settings.voice, settings.speed, settings.pitch);
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
