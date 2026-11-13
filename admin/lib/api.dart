import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// The server address built into the app. Change it on the sign-in screen,
/// or at build time with --dart-define=BACKEND_URL=https://...
const defaultBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'https://bangla-ai-server-1a46.onrender.com',
);

/// What kind of problem a request ran into, so the sign-in screen can tell
/// a wrong code apart from a server that is asleep or out of reach.
enum ApiErrorKind {
  wrongCode,
  expiredCode,
  tooManyTries,
  tooSoon,
  invalidEmail,
  rateLimited,
  waking,
  unreachable,
  timeout,
  other,
}

class ApiException implements Exception {
  ApiException(
    this.message, {
    this.status = 0,
    this.kind = ApiErrorKind.other,
    this.retryAfter = 0,
    this.triesLeft,
  });
  final String message;
  final int status;
  final ApiErrorKind kind;

  /// Seconds to wait before asking for another code (tooSoon).
  final int retryAfter;

  /// Wrong tries left on the current code (wrongCode).
  final int? triesLeft;
  bool get signedOut => status == 401;
  @override
  String toString() => message;
}

/// The admin's view of the server config. The API key is never sent back:
/// only whether one is set and its last four characters.
class AdminConfig {
  AdminConfig(this.json);
  final Map<String, dynamic> json;

  bool get enabled => json['enabled'] != false;
  String get disabledMessage => '${json['disabledMessage'] ?? ''}';
  String get baseUrl => '${json['baseUrl'] ?? ''}';
  bool get apiKeySet => json['apiKeySet'] == true;
  String get apiKeyHint => '${json['apiKeyHint'] ?? ''}';
  List<String> get models =>
      (json['models'] as List?)?.whereType<String>().toList() ?? const ['auto'];
  String get defaultModel => '${json['defaultModel'] ?? 'auto'}';
  String get systemPrompt => '${json['systemPrompt'] ?? ''}';
  String get voiceName => '${json['voiceName'] ?? ''}';
  String get voiceLocale => '${json['voiceLocale'] ?? 'bn-BD'}';
  double get speed => (json['speed'] as num?)?.toDouble() ?? 1.0;
  double get pitch => (json['pitch'] as num?)?.toDouble() ?? 1.0;
  String get updatedAt => '${json['updatedAt'] ?? ''}';

  // How the AI talks.
  String get stylePrompt => '${json['stylePrompt'] ?? ''}';
  String get callPrompt => '${json['callPrompt'] ?? ''}';

  // Voice.
  bool get voiceEnabled => json['voiceEnabled'] == true;
  String get voiceProvider => '${json['voiceProvider'] ?? 'device'}';
  List<Map<String, dynamic>> get voiceProviders =>
      ((json['voiceProviders'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
  String get callModel => '${json['callModel'] ?? ''}';
  String get callModelInUse => '${json['callModelInUse'] ?? ''}';
  int get callMaxTokens => (json['callMaxTokens'] as num?)?.toInt() ?? 160;
  int get callPauseMs => (json['callPauseMs'] as num?)?.toInt() ?? 900;
  int get callHistory => (json['callHistory'] as num?)?.toInt() ?? 10;
  bool get callOfflineVoice => json['callOfflineVoice'] != false;
  int get ttsDailyChars => (json['ttsDailyChars'] as num?)?.toInt() ?? 200000;
}

/// A kind of cloud voice the server can use (Microsoft Azure, Google...),
/// with the fields its form needs. The server owns this list, so a new
/// provider shows up here without an app update.
class VoiceType {
  VoiceType(this.json);
  final Map<String, dynamic> json;
  String get type => '${json['type']}';
  String get label => '${json['label'] ?? type}';
  String get note => '${json['note'] ?? ''}';
  List<VoiceField> get fields => ((json['fields'] as List?) ?? const [])
      .whereType<Map>()
      .map((m) => VoiceField(Map<String, dynamic>.from(m)))
      .toList();
}

class VoiceField {
  VoiceField(this.json);
  final Map<String, dynamic> json;
  String get key => '${json['key']}';
  String get label => '${json['label'] ?? key}';
  String get hint => '${json['hint'] ?? ''}';
  bool get secret => json['secret'] == true;
  bool get required => json['required'] == true;
  bool get url => json['url'] == true;
  List<String> get suggestions =>
      ((json['suggestions'] as List?) ?? const []).whereType<String>().toList();
}

class VoiceSample {
  VoiceSample({required this.ok, this.error = '', this.ms = 0, this.audio});
  final bool ok;
  final String error;
  final int ms;
  final Uint8List? audio;
}

/// Usage numbers from the server (counted per day, no message text).
class Stats {
  Stats(this.json, this.server);
  final Map<String, dynamic> json;

  /// Server facts: version, store, email, OmniRoute ready.
  final Map<String, dynamic> server;

  Map<String, dynamic> period(String key) =>
      Map<String, dynamic>.from((json[key] as Map?) ?? const {});
  List<Map<String, dynamic>> get series =>
      ((json['series'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
  List<Map<String, dynamic>> get recentErrors =>
      ((json['recentErrors'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
  Map<String, dynamic> get recent =>
      Map<String, dynamic>.from((json['recent'] as Map?) ?? const {});
  int get totalDevices => (json['totalDevices'] as num?)?.toInt() ?? 0;
  int get uptimeSeconds => (json['uptimeSeconds'] as num?)?.toInt() ?? 0;
  String get since => '${json['since'] ?? ''}';
  String get timezone => '${json['timezone'] ?? ''}';
}

class SaveResult {
  SaveResult(this.config, {required this.stored});
  final AdminConfig config;

  /// False when the server kept the change in memory only (database down).
  final bool stored;
}

class TestResult {
  TestResult({required this.ok, this.reply = '', this.error = '', this.ms = 0});
  final bool ok;
  final String reply;
  final String error;
  final int ms;
}

/// Talks to the Bangla AI server's admin endpoints.
class AdminApi {
  AdminApi._(this._prefs);

  static Future<AdminApi> create() async =>
      AdminApi._(await SharedPreferences.getInstance())
        .._token = await _secure.read(key: 'adminToken');

  static const _secure = FlutterSecureStorage();
  final SharedPreferences _prefs;

  /// Tests put a fake HTTP client here.
  static http.Client? testClient;
  String? _token;

  /// A free Render server sleeps when idle and takes up to about a minute
  /// to wake.
  static const _timeout = Duration(seconds: 90);

  String get baseUrl => _prefs.getString('backendUrl') ?? defaultBackendUrl;
  bool get signedIn => _token != null;

  /// The email used at the last sign-in, to prefill the field.
  String get lastEmail => _prefs.getString('adminEmail') ?? '';

  Future<void> setBaseUrl(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.isEmpty || clean == defaultBackendUrl) {
      await _prefs.remove('backendUrl');
    } else {
      await _prefs.setString('backendUrl', clean);
    }
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  /// GET /health until it answers or [total] runs out. [onWaiting] fires once
  /// the server is slow, so the UI can say it is waking up.
  Future<bool> wake({
    void Function()? onWaiting,
    Duration total = _timeout,
  }) async {
    final end = DateTime.now().add(total);
    final slow = Timer(const Duration(seconds: 3), () => onWaiting?.call());
    try {
      while (DateTime.now().isBefore(end)) {
        try {
          final r =
              await (testClient?.get(_uri('/health')) ??
                      http.get(_uri('/health')))
                  .timeout(const Duration(seconds: 70));
          if (r.statusCode == 200) return true;
        } catch (_) {}
        onWaiting?.call();
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      return false;
    } finally {
      slow.cancel();
    }
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Object? body,
  }) async {
    final req = http.Request(method, _uri(path))
      ..headers.addAll(_headers)
      ..body = body == null ? '' : jsonEncode(body);
    http.Response res;
    try {
      res = await http.Response.fromStream(
        await (testClient?.send(req) ?? req.send()).timeout(_timeout),
      );
    } on TimeoutException {
      throw ApiException(
        'The server took too long to answer. It may still be waking up: try again in a minute.',
        kind: ApiErrorKind.timeout,
      );
    } on SocketException {
      throw ApiException(
        "Can't reach the server. Check your internet connection.",
        kind: ApiErrorKind.unreachable,
      );
    } on http.ClientException {
      throw ApiException(
        "Can't reach the server. Check your internet connection.",
        kind: ApiErrorKind.unreachable,
      );
    }
    Map<String, dynamic> j = {};
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      if (d is Map<String, dynamic>) j = d;
    } catch (_) {}
    if (res.statusCode >= 200 && res.statusCode < 300) return j;
    final err = j['error'];
    final msg = err is Map ? '${err['message'] ?? ''}' : '';
    final code = err is Map ? '${err['code'] ?? ''}' : '';
    final isSignIn =
        path.startsWith('/admin/request-code') ||
        path.startsWith('/admin/verify-code');
    if (res.statusCode == 401 && !isSignIn) await signOut();
    // Render answers 502/503/504 with its own page (not our JSON) while a
    // sleeping free server starts.
    if ([502, 503, 504].contains(res.statusCode) && msg.isEmpty) {
      throw ApiException(
        'The server is waking up. Wait a minute and try again.',
        status: res.statusCode,
        kind: ApiErrorKind.waking,
      );
    }
    final kind = switch (code) {
      'wrong_code' || 'invalid_code' => ApiErrorKind.wrongCode,
      'expired_code' => ApiErrorKind.expiredCode,
      'too_many_tries' => ApiErrorKind.tooManyTries,
      'too_soon' => ApiErrorKind.tooSoon,
      'invalid_email' => ApiErrorKind.invalidEmail,
      _ =>
        res.statusCode == 429 ? ApiErrorKind.rateLimited : ApiErrorKind.other,
    };
    if (kind != ApiErrorKind.other) {
      throw ApiException(
        msg.isNotEmpty ? msg : 'Too many tries. Wait a little and try again.',
        status: res.statusCode,
        kind: kind,
        retryAfter: err is Map
            ? ((err['retryAfter'] as num?)?.toInt() ?? 0)
            : 0,
        triesLeft: err is Map ? (err['triesLeft'] as num?)?.toInt() : null,
      );
    }
    throw ApiException(
      msg.isNotEmpty ? msg : 'Server error ${res.statusCode}.',
      status: res.statusCode,
    );
  }

  /// Asks the server to email a 6-digit code. The answer is the same
  /// whether or not the email is the admin's. Returns the seconds to wait
  /// before another code can be asked for.
  Future<int> requestCode(String email) async {
    final clean = email.trim().toLowerCase();
    final j = await _call(
      'POST',
      '/admin/request-code',
      body: {'email': clean},
    );
    await _prefs.setString('adminEmail', clean);
    return (j['resendAfterSeconds'] as num?)?.toInt() ?? 60;
  }

  /// Exchanges the emailed code for a token that lasts 30 days.
  Future<void> verifyCode(String email, String code) async {
    final j = await _call(
      'POST',
      '/admin/verify-code',
      body: {
        'email': email.trim().toLowerCase(),
        'code': code.replaceAll(RegExp(r'\D'), ''),
      },
    );
    _token = '${j['token']}';
    await _secure.write(key: 'adminToken', value: _token);
  }

  Future<void> signOut() async {
    _token = null;
    await _secure.delete(key: 'adminToken');
  }

  Future<(AdminConfig, bool)> getConfig() async {
    final j = await _call('GET', '/admin/config');
    return (
      AdminConfig(Map<String, dynamic>.from(j['config'] as Map)),
      j['storeOk'] != false,
    );
  }

  /// Saves the given fields. An empty apiKey keeps the stored key.
  Future<SaveResult> save(Map<String, dynamic> patch) async {
    try {
      final j = await _call('PUT', '/admin/config', body: patch);
      return SaveResult(
        AdminConfig(Map<String, dynamic>.from(j['config'] as Map)),
        stored: j['storeOk'] != false,
      );
    } on ApiException catch (e) {
      if (e.status == 503 && e.message.startsWith('Saved in memory')) {
        final (cfg, _) = await getConfig();
        return SaveResult(cfg, stored: false);
      }
      rethrow;
    }
  }

  /// Sends one tiny message to OmniRoute with the draft values (empty fields
  /// use the stored ones).
  Future<TestResult> test(Map<String, dynamic> draft) async {
    final j = await _call('POST', '/admin/test', body: draft);
    return TestResult(
      ok: j['ok'] == true,
      reply: '${j['reply'] ?? ''}',
      error: '${j['error'] ?? ''}',
      ms: (j['ms'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Stats> stats({int days = 30}) async {
    final j = await _call('GET', '/admin/stats?days=$days');
    final server = Map<String, dynamic>.from(j)..remove('stats');
    return Stats(Map<String, dynamic>.from(j['stats'] as Map), server);
  }

  Future<List<VoiceType>> voiceTypes() async {
    final j = await _call('GET', '/admin/voice-types');
    return ((j['types'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => VoiceType(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// The server's starting conversation and call styles.
  Future<(String, String)> defaults() async {
    final j = await _call('GET', '/admin/defaults');
    return ('${j['stylePrompt'] ?? ''}', '${j['callPrompt'] ?? ''}');
  }

  /// Has the server speak a short Bangla line with [provider] (unsaved
  /// values; an empty key uses the saved one).
  Future<VoiceSample> voiceSample(
    Map<String, dynamic> provider, {
    String? text,
  }) async {
    final j = await _call(
      'POST',
      '/admin/tts-test',
      body: {'provider': provider, 'text': ?text},
    );
    final b64 = j['audio'];
    return VoiceSample(
      ok: j['ok'] == true,
      error: '${j['error'] ?? ''}',
      ms: (j['ms'] as num?)?.toInt() ?? 0,
      audio: b64 is String ? base64Decode(b64) : null,
    );
  }

  /// The reply the app would get to [text] with the unsaved [draft].
  Future<TestResult> tryChat(
    String text, {
    bool call = false,
    Map<String, dynamic> draft = const {},
  }) async {
    final j = await _call(
      'POST',
      '/admin/try-chat',
      body: {'text': text, 'call': call, 'draft': draft},
    );
    return TestResult(
      ok: j['ok'] == true,
      reply: '${j['reply'] ?? ''}',
      error: '${j['error'] ?? ''}',
      ms: (j['ms'] as num?)?.toInt() ?? 0,
    );
  }
}
