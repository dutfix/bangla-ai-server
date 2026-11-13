import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../api.dart';

/// The admin's unsaved changes, shared by every tab, so moving between tabs
/// keeps them. One Save sends them all.
class Editor extends ChangeNotifier {
  Editor(this.api);
  final AdminApi api;

  AdminConfig? cfg;
  bool storeOk = true;
  bool saving = false;

  // Text fields.
  final baseUrl = TextEditingController();
  final apiKey = TextEditingController();
  final disabledMessage = TextEditingController();
  final systemPrompt = TextEditingController();
  final stylePrompt = TextEditingController();
  final callPrompt = TextEditingController();

  // Everything else.
  bool enabled = true;
  List<String> models = [];
  String defaultModel = 'auto';
  String voiceName = '';
  String voiceLocale = 'bn-BD';
  double speed = 1.0;
  double pitch = 1.0;
  bool voiceEnabled = false;
  String voiceProvider = 'device';

  /// Cloud voices. A typed key sits in 'apiKey' until saved; 'clearApiKey'
  /// removes the saved one.
  List<Map<String, dynamic>> providers = [];
  String callModel = '';
  int callMaxTokens = 160;
  int callPauseMs = 900;
  int callHistory = 10;
  bool callOfflineVoice = true;
  int ttsDailyChars = 200000;

  String _baseline = '';

  List<TextEditingController> get _fields => [
    baseUrl,
    apiKey,
    disabledMessage,
    systemPrompt,
    stylePrompt,
    callPrompt,
  ];

  void _listen() {
    for (final c in _fields) {
      c.addListener(notifyListeners);
    }
  }

  bool _listening = false;

  void apply(AdminConfig c, {bool? stored}) {
    if (!_listening) {
      _listen();
      _listening = true;
    }
    cfg = c;
    if (stored != null) storeOk = stored;
    baseUrl.text = c.baseUrl;
    apiKey.clear();
    disabledMessage.text = c.disabledMessage;
    systemPrompt.text = c.systemPrompt;
    stylePrompt.text = c.stylePrompt;
    callPrompt.text = c.callPrompt;
    enabled = c.enabled;
    models = [...c.models];
    defaultModel = c.defaultModel;
    voiceName = c.voiceName;
    voiceLocale = c.voiceLocale;
    speed = c.speed.clamp(0.5, 2.0);
    pitch = c.pitch.clamp(0.5, 2.0);
    voiceEnabled = c.voiceEnabled;
    voiceProvider = c.voiceProvider;
    providers = [
      for (final p in c.voiceProviders)
        {
          for (final e in p.entries)
            if (e.key != 'apiKeySet' && e.key != 'apiKeyHint') e.key: e.value,
        },
    ];
    callModel = c.callModel;
    callMaxTokens = c.callMaxTokens;
    callPauseMs = c.callPauseMs;
    callHistory = c.callHistory;
    callOfflineVoice = c.callOfflineVoice;
    ttsDailyChars = c.ttsDailyChars;
    _baseline = jsonEncode(patch());
    notifyListeners();
  }

  /// Everything the server takes, as it stands now.
  Map<String, dynamic> patch() => {
    'enabled': enabled,
    'disabledMessage': disabledMessage.text,
    'baseUrl': baseUrl.text.trim(),
    if (apiKey.text.trim().isNotEmpty) 'apiKey': apiKey.text.trim(),
    'models': models,
    'defaultModel': defaultModel,
    'systemPrompt': systemPrompt.text,
    'stylePrompt': stylePrompt.text,
    'callPrompt': callPrompt.text,
    'voiceName': voiceName,
    'voiceLocale': voiceLocale,
    'speed': double.parse(speed.toStringAsFixed(2)),
    'pitch': double.parse(pitch.toStringAsFixed(2)),
    'voiceEnabled': voiceEnabled,
    'voiceProvider': voiceProvider,
    'voiceProviders': providers,
    'callModel': callModel,
    'callMaxTokens': callMaxTokens,
    'callPauseMs': callPauseMs,
    'callHistory': callHistory,
    'callOfflineVoice': callOfflineVoice,
    'ttsDailyChars': ttsDailyChars,
  };

  bool get dirty => cfg != null && jsonEncode(patch()) != _baseline;

  /// Puts the saved values back.
  void discard() {
    if (cfg != null) apply(cfg!);
  }

  /// Calls [f] and tells the tabs something changed.
  void edit(VoidCallback f) {
    f();
    notifyListeners();
  }

  String? problem() {
    final url = baseUrl.text.trim();
    if (url.isNotEmpty && !RegExp(r'^https?://').hasMatch(url)) {
      return 'The OmniRoute address starts with https://';
    }
    if (models.isEmpty) return 'Add at least one model.';
    return null;
  }

  /// Saves; returns the message to show.
  Future<String> save() async {
    final p = problem();
    if (p != null) return p;
    saving = true;
    notifyListeners();
    try {
      final r = await api.save(patch());
      apply(r.config, stored: r.stored);
      return r.stored
          ? 'Saved. Users get it the next time they open the app.'
          : 'Saved until the server restarts: the database is not reachable.';
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  /// A saved provider's masked key ('••••abcd'), or ''.
  String savedKeyHint(String id) {
    for (final p in cfg?.voiceProviders ?? const <Map<String, dynamic>>[]) {
      if (p['id'] == id && p['apiKeySet'] == true) return '${p['apiKeyHint']}';
    }
    return '';
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    super.dispose();
  }
}
