import 'services/agent_store.dart';
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
    AgentStore? agents,
  }) : agents = agents ?? chat.agents ?? AgentStore();

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

  /// The four agents' memory, notes, reminders, skills and tasks.
  final AgentStore agents;

  static Future<AppServices> create() async {
    final settings = SettingsStore();
    final chats = ChatStore();
    final agents = AgentStore(runsTimers: true);
    // All read from disk; none needs the others.
    await Future.wait([settings.load(), chats.load(), agents.load()]);
    agents.deviceId = settings.deviceId;
    final speaker = Speaker();
    final listener = SpeechListener();
    final chat = ChatController(
      store: chats,
      settings: settings,
      agents: agents,
    );
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
      agents: agents,
    );
  }
}
