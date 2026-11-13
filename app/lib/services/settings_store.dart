import 'dart:math';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../models/voice.dart';
import 'backend.dart';

/// The config the admin sets on the server (GET /v1/config). The OmniRoute
/// key never comes to the app.
class RemoteConfig {
  const RemoteConfig({
    this.enabled = true,
    this.disabledMessage = '',
    this.models = const ['auto', 'auto/fast'],
    this.defaultModel = 'auto',
    this.voiceName = '',
    this.voiceLocale = 'bn-BD',
    this.speed = 1.0,
    this.pitch = 1.0,
    this.voiceEnabled = false,
    this.voiceMode = 'off',
    this.callPauseMs = 900,
    this.callHistory = 10,
    this.callOfflineVoice = true,
    this.ready = true,
    this.updatedAt = '',
  });

  final bool enabled;
  final String disabledMessage;
  final List<String> models;
  final String defaultModel;

  /// The admin's default voice (a Google voice id), or empty for the best
  /// Bangla voice on the phone.
  final String voiceName;
  final String voiceLocale;
  final double speed;
  final double pitch;

  /// Voice calls and read-aloud are on. Off until the admin turns them on.
  final bool voiceEnabled;

  /// 'off', 'device' (the phone's own voice) or 'server' (the admin's cloud
  /// voice, played from the server's /v1/tts).
  final String voiceMode;

  /// Silence that ends the user's turn in a call, in milliseconds.
  final int callPauseMs;

  /// Messages of the conversation sent with each call turn.
  final int callHistory;

  /// In calls, use the offline twin of a network phone voice (starts faster).
  final bool callOfflineVoice;

  /// The server has an OmniRoute address and key.
  final bool ready;
  final String updatedAt;

  factory RemoteConfig.fromJson(Map<String, dynamic> j) {
    double dbl(Object? v, double d) => v is num ? v.toDouble() : d;
    final models =
        (j['models'] as List?)
            ?.whereType<String>()
            .where((m) => m.trim().isNotEmpty)
            .toList() ??
        const ['auto'];
    return RemoteConfig(
      enabled: j['enabled'] != false,
      disabledMessage: '${j['disabledMessage'] ?? ''}',
      models: models.isEmpty ? const ['auto'] : models,
      defaultModel:
          '${j['defaultModel'] ?? (models.isEmpty ? 'auto' : models.first)}',
      voiceName: '${j['voiceName'] ?? ''}',
      voiceLocale: '${j['voiceLocale'] ?? 'bn-BD'}',
      speed: dbl(j['speed'], 1.0).clamp(0.25, 2.5),
      pitch: dbl(j['pitch'], 1.0).clamp(0.5, 2.0),
      voiceEnabled: j['voiceEnabled'] == true,
      voiceMode: j['voiceEnabled'] == true
          ? (j['voiceMode'] == 'server' ? 'server' : 'device')
          : 'off',
      callPauseMs: (dbl(j['callPauseMs'], 900).round()).clamp(400, 3000),
      callHistory: (dbl(j['callHistory'], 10).round()).clamp(2, 40),
      callOfflineVoice: j['callOfflineVoice'] != false,
      ready: j['ready'] != false,
      updatedAt: '${j['updatedAt'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'disabledMessage': disabledMessage,
    'models': models,
    'defaultModel': defaultModel,
    'voiceName': voiceName,
    'voiceLocale': voiceLocale,
    'speed': speed,
    'pitch': pitch,
    'voiceEnabled': voiceEnabled,
    'voiceMode': voiceMode,
    'callPauseMs': callPauseMs,
    'callHistory': callHistory,
    'callOfflineVoice': callOfflineVoice,
    'ready': ready,
    'updatedAt': updatedAt,
  };

  RemoteConfig copyWith({bool? enabled, String? disabledMessage}) =>
      RemoteConfig(
        enabled: enabled ?? this.enabled,
        disabledMessage: disabledMessage ?? this.disabledMessage,
        models: models,
        defaultModel: defaultModel,
        voiceName: voiceName,
        voiceLocale: voiceLocale,
        speed: speed,
        pitch: pitch,
        voiceEnabled: voiceEnabled,
        voiceMode: voiceMode,
        callPauseMs: callPauseMs,
        callHistory: callHistory,
        callOfflineVoice: callOfflineVoice,
        ready: ready,
        updatedAt: updatedAt,
      );
}

/// Where the server config stands, for the chat screen's banner.
enum ServerState { unknown, waking, online, offline }

/// The user's own choices (language, theme, model) plus the admin's config
/// from the server, cached so the app starts offline. Everything about voice
/// (on or off, which voice, speed, pitch, provider) comes from the admin.
class SettingsStore extends ChangeNotifier {
  SettingsStore({http.Client Function()? clientFactory})
    : _newClient = clientFactory ?? http.Client.new;

  final http.Client Function() _newClient;
  late SharedPreferences _prefs;

  /// Bumped when a new version changes defaults that should reach people who
  /// already use the app. 1 = Bangla AI: Bangla language, server config.
  /// 2 = voice settings moved to the admin: drop the user's voice overrides.
  static const _defaultsVersion = 2;

  /// The admin's config: the cached copy until the server answers.
  RemoteConfig remote = const RemoteConfig();
  ServerState serverState = ServerState.unknown;
  bool _awake = false;

  /// The server answered recently, so a request needs no wake-up wait.
  bool get serverAwake => _awake;
  void markServerAwake() {
    _awake = true;
    if (serverState != ServerState.online) {
      serverState = ServerState.online;
      notifyListeners();
    }
  }

  ThemeMode themeMode = ThemeMode.system;

  /// App language: 'bn' (default) or 'en'. Also sets the AI reply language
  /// and the speech recognizer locale.
  String language = AppLanguage.defaultCode;

  /// Whether the one-time "install Bangla voice" prompt was shown.
  bool voiceSetupPrompted = false;

  /// The admin's phone voice, or null for the best Bangla voice on the phone.
  VoiceOption? get voice => remote.voiceName.isEmpty
      ? null
      : VoiceOption(name: remote.voiceName, locale: remote.voiceLocale);
  double get speed => remote.speed;
  double get pitch => remote.pitch;

  /// Voice calls and read-aloud are available (the admin turned voice on).
  /// Always off in the web version: browsers have no dependable Bangla
  /// speech, so the call button and read-aloud stay hidden there.
  bool get voiceEnabled => !kIsWeb && remote.voiceEnabled;

  /// The admin's cloud voice speaks (audio from the server), not the phone.
  bool get cloudVoice => remote.voiceMode == 'server';

  /// The user's model pick from the admin's list. Null = the admin's default.
  String? _model;

  /// The admin's models, offered in the model picker.
  List<String> get models => remote.models;

  /// The model for new replies: the user's pick while the admin still offers
  /// it, else the admin's default.
  String get model => (_model != null && remote.models.contains(_model))
      ? _model!
      : remote.defaultModel;

  Future<void> setModel(String m) async {
    _model = m == remote.defaultModel ? null : m;
    if (_model == null) {
      await _prefs.remove('userModel');
    } else {
      await _prefs.setString('userModel', m);
    }
    notifyListeners();
  }

  /// Chats can be sent (the admin has not switched the app off).
  bool get isConfigured => remote.enabled;

  /// Phone speech recognizer locale, e.g. bn_BD.
  String get speechLocale => AppLanguage.speechLocale(language);

  /// The app's system line: the reply-language rule. The server puts the
  /// admin's prompt, the conversation style and, in calls, the call style
  /// before it.
  String systemMessage() => AppLanguage.replyInstruction(language);

  /// A random id for this install, so the admin's overview can count
  /// phones. Not tied to the person or the phone; the server stores only a
  /// salted hash of it.
  String deviceId = '';

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    deviceId = _prefs.getString('deviceId') ?? '';
    if (deviceId.isEmpty) {
      final r = Random.secure();
      deviceId = List.generate(
        24,
        (_) => '0123456789abcdef'[r.nextInt(16)],
      ).join();
      await _prefs.setString('deviceId', deviceId);
    }
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == _prefs.getString('themeMode'),
      orElse: () => ThemeMode.system,
    );
    language = _prefs.getString('language') ?? AppLanguage.defaultCode;
    if (!AppLanguage.codes.contains(language)) {
      language = AppLanguage.defaultCode;
    }
    L10n.code = language;
    voiceSetupPrompted = _prefs.getBool('voiceSetupPrompted') ?? false;
    _model = _prefs.getString('userModel');
    final cached = _prefs.getString('remoteConfig');
    if (cached != null) {
      try {
        remote = RemoteConfig.fromJson(
          jsonDecode(cached) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    // Upgrading from Omni: switch once to Bangla and drop the old
    // connection settings, which now live on the server.
    final had = _prefs.getInt('defaultsVersion') ?? 0;
    if (had < 1) {
      final upgrading = _prefs.getKeys().isNotEmpty;
      for (final old in [
        'voice', 'foundVoices', 'baseUrl', 'model', 'models', //
        'systemPrompt', 'speed',
      ]) {
        await _prefs.remove(old);
      }
      if (upgrading) {
        language = AppLanguage.bangla;
        L10n.code = language;
        await _prefs.setString('language', language);
      }
    }
    if (had < 2) {
      // The voice, speed and pitch are the admin's now.
      for (final old in [
        'voiceName',
        'voiceLocale',
        'userSpeed',
        'userPitch',
      ]) {
        await _prefs.remove(old);
      }
    }
    if (had < _defaultsVersion) {
      await _prefs.setInt('defaultsVersion', _defaultsVersion);
    }
  }

  Future<void>? _refreshing;

  /// Fetches the admin's config. While the server wakes up (a free Render
  /// service can take about a minute) the state is [ServerState.waking] and
  /// the cached config stays in use.
  Future<void> refreshRemote() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    final client = _newClient();
    final slow = Timer(const Duration(seconds: 4), () {
      if (serverState != ServerState.online) {
        serverState = ServerState.waking;
        notifyListeners();
      }
    });
    try {
      final end = DateTime.now().add(Backend.wakeTimeout);
      while (true) {
        try {
          final res = await client
              .get(Backend.uri('/v1/config'))
              .timeout(const Duration(seconds: 70));
          if (res.statusCode == 200) {
            remote = RemoteConfig.fromJson(decodeJson(res));
            await _prefs.setString('remoteConfig', jsonEncode(remote.toJson()));
            _awake = true;
            serverState = ServerState.online;
            notifyListeners();
            return;
          }
        } catch (_) {}
        if (DateTime.now().isAfter(end)) break;
        if (serverState != ServerState.waking) {
          serverState = ServerState.waking;
          notifyListeners();
        }
        await Future<void>.delayed(const Duration(seconds: 4));
      }
      serverState = ServerState.offline;
      notifyListeners();
    } finally {
      slow.cancel();
      client.close();
    }
  }

  /// The server said the app is switched off.
  void remoteDisabled(String message) {
    remote = remote.copyWith(enabled: false, disabledMessage: message);
    unawaited(_prefs.setString('remoteConfig', jsonEncode(remote.toJson())));
    notifyListeners();
  }

  /// Switches the app language (texts, AI replies, speech recognition).
  Future<void> setLanguage(String code) async {
    if (!AppLanguage.codes.contains(code)) return;
    language = code;
    L10n.code = code;
    await _prefs.setString('language', code);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await _prefs.setString('themeMode', m.name);
    notifyListeners();
  }

  Future<void> markVoiceSetupPrompted() async {
    voiceSetupPrompted = true;
    await _prefs.setBool('voiceSetupPrompted', true);
  }
}
