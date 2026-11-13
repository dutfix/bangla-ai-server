import 'services/call_controller.dart';
import 'services/chat_controller.dart';
import 'services/chat_store.dart';
import 'services/listener.dart';
import 'services/read_aloud.dart';
import 'services/settings_store.dart';
import 'services/speaker.dart';

/// The app's long-lived objects, created once at startup.
class AppServices {
  /// Wires up given objects (used by tests and screenshot runs).
  AppServices({
    required this.settings,
    required this.speaker,
    required this.listener,
    required this.chats,
    required this.chat,
    required this.call,
    required this.readAloud,
  });

  final SettingsStore settings;

  /// Speaks with the admin's voice: the phone's Bangla voice or the
  /// admin's cloud voice.
  final Speaker speaker;

  /// The phone's speech recognizer, used by voice calls.
  final SpeechListener listener;
  final ChatStore chats;
  final ChatController chat;
  final CallController call;
  final ReadAloud readAloud;

  static Future<AppServices> create() async {
    final settings = SettingsStore();
    final chats = ChatStore();
    // Both read from disk; neither needs the other.
    await Future.wait([settings.load(), chats.load()]);
    final speaker = Speaker();
    final listener = SpeechListener();
    final chat = ChatController(store: chats, settings: settings);
    return AppServices(
      settings: settings,
      speaker: speaker,
      listener: listener,
      chats: chats,
      chat: chat,
      call: CallController(
        settings: settings,
        speaker: speaker,
        listener: listener,
        sink: chat,
      ),
      readAloud: ReadAloud(settings, speaker),
    );
  }
}
