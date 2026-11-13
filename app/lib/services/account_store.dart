import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'backend.dart';
import 'url_cleanup.dart';

/// The signed-in person, as the server describes them.
@immutable
class Account {
  const Account({
    required this.id,
    required this.email,
    required this.emailVerified,
    required this.name,
    required this.avatarUrl,
    required this.hasPassword,
    required this.google,
  });

  final String id;
  final String email;
  final bool emailVerified;
  final String name;
  final String? avatarUrl;
  final bool hasPassword;
  final bool google;

  /// The picture's full address, or null when there is none.
  String? get avatar => avatarUrl == null
      ? null
      : (avatarUrl!.startsWith('http')
            ? avatarUrl
            : '${Backend.url}$avatarUrl');

  String get initial {
    final n = name.trim().isNotEmpty ? name.trim() : email;
    if (n.isEmpty) return '?';
    final r = n.runes.first;
    return String.fromCharCode(r).toUpperCase();
  }

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    id: '${j['id'] ?? ''}',
    email: '${j['email'] ?? ''}',
    emailVerified: j['emailVerified'] == true,
    name: '${j['name'] ?? ''}',
    avatarUrl: j['avatarUrl'] is String ? j['avatarUrl'] as String : null,
    hasPassword: j['hasPassword'] == true,
    google: j['google'] == true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'emailVerified': emailVerified,
    'name': name,
    'avatarUrl': avatarUrl,
    'hasPassword': hasPassword,
    'google': google,
  };
}

/// An error from the accounts server. [code] is the server's machine code
/// (wrong_login, email_taken...), or 'network' / 'timeout' / 'unknown'.
class AccountException implements Exception {
  AccountException(
    this.code,
    this.serverMessage, {
    this.retryAfter,
    this.triesLeft,
  });
  final String code;
  final String serverMessage;
  final int? retryAfter;
  final int? triesLeft;
  @override
  String toString() => '$code: $serverMessage';
}

/// Sign-up, sign-in (email or Google), the profile and sign-out.
///
/// The session token lives in this device's storage and goes with every
/// request to the server ([Backend.authToken]), so chat and voice know who
/// is asking when the admin requires accounts.
class AccountStore extends ChangeNotifier {
  AccountStore(this._prefs, {http.Client Function()? clientFactory})
    : _client = clientFactory ?? http.Client.new;

  final http.Client Function() _client;

  static const _kToken = 'account_token_v1';
  static const _kUser = 'account_user_v1';
  static const _kSeen = 'account_intro_seen_v1';
  static const _timeout = Duration(seconds: 25);

  final SharedPreferences _prefs;
  Account? _user;
  StreamSubscription<Uri>? _links;

  /// A Google sign-in that came back to the app and still needs finishing.
  /// The UI shows a spinner while it is set.
  bool googleBusy = false;

  /// Set when a Google sign-in comes back with an error; the UI shows it once.
  String? pendingError;

  /// True right after Google created a new account (the UI greets them).
  bool justCreated = false;

  Account? get user => _user;
  bool get signedIn => _user != null && Backend.authToken.isNotEmpty;

  /// Whether this device already saw the sign-in page once.
  bool get introSeen => _prefs.getBool(_kSeen) ?? false;
  set introSeen(bool v) => _prefs.setBool(_kSeen, v);

  static Future<AccountStore> load({
    http.Client Function()? clientFactory,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final s = AccountStore(prefs, clientFactory: clientFactory);
    Backend.authToken = prefs.getString(_kToken) ?? '';
    final cached = prefs.getString(_kUser);
    if (Backend.authToken.isNotEmpty && cached != null) {
      try {
        s._user = Account.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      } catch (_) {}
    }
    Backend.onSignedOut = s._expired;
    return s;
  }

  /// Finishes a Google sign-in that came back to the page (web) or the app
  /// (Android), then checks the saved session with the server.
  Future<void> start() async {
    if (kIsWeb) {
      await _handleReturn(Uri.base, fromWeb: true);
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final links = AppLinks();
        final first = await links.getInitialLink();
        if (first != null) await _handleReturn(first);
        _links = links.uriLinkStream.listen((u) => _handleReturn(u));
      } catch (_) {}
    }
    if (signedIn) unawaited(refresh());
  }

  @override
  void dispose() {
    _links?.cancel();
    if (Backend.onSignedOut == _expired) Backend.onSignedOut = null;
    super.dispose();
  }

  Future<void> _handleReturn(Uri u, {bool fromWeb = false}) async {
    final ticket = u.queryParameters['auth_ticket'];
    final error = u.queryParameters['auth_error'];
    if (ticket == null && error == null) return;
    if (fromWeb) removeAuthParamsFromAddress();
    if (error != null) {
      pendingError = error;
      notifyListeners();
      return;
    }
    googleBusy = true;
    notifyListeners();
    try {
      final j = await _post('/v1/auth/google/exchange', {'ticket': ticket});
      justCreated = j['isNew'] == true;
      await _signedIn(j);
    } on AccountException catch (e) {
      pendingError = e.code == 'network' || e.code == 'timeout'
          ? e.code
          : 'google_failed';
    } finally {
      googleBusy = false;
      notifyListeners();
    }
  }

  /// Re-reads the profile; signs out locally when the server ended the session.
  Future<void> refresh() async {
    try {
      final j = await _get('/v1/me');
      _setUser(Account.fromJson(j['user'] as Map<String, dynamic>));
    } on AccountException catch (e) {
      if (e.code == 'signed_out') await _clear();
    }
  }

  // ------------------------------------------------------------ email

  /// Creates the account and signs in. Returns whether a code was emailed.
  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final j = await _post('/v1/auth/signup', {
      'name': name,
      'email': email,
      'password': password,
    });
    justCreated = true;
    await _signedIn(j);
    return j['verificationSent'] == true;
  }

  Future<void> signIn({required String email, required String password}) async {
    final j = await _post('/v1/auth/login', {
      'email': email,
      'password': password,
    });
    justCreated = false;
    await _signedIn(j);
  }

  /// Emails a reset code (the server answers the same for any address).
  Future<void> forgotPassword(String email) =>
      _post('/v1/auth/password/forgot', {'email': email});

  /// Sets a new password with the emailed code, and signs in.
  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    final j = await _post('/v1/auth/password/reset', {
      'email': email,
      'code': code,
      'password': password,
    });
    await _signedIn(j);
  }

  /// Returns whether an email went out.
  Future<bool> sendVerification() async {
    final j = await _post('/v1/auth/verify/send', {});
    if (j['user'] is Map) {
      _setUser(Account.fromJson(j['user'] as Map<String, dynamic>));
    }
    return j['sent'] == true;
  }

  Future<void> verifyEmail(String code) async {
    final j = await _post('/v1/auth/verify', {'code': code});
    _setUser(Account.fromJson(j['user'] as Map<String, dynamic>));
  }

  Future<void> changePassword({
    String? current,
    required String password,
  }) async {
    final j = await _post('/v1/auth/password/change', {
      'current': current ?? '',
      'password': password,
    });
    await _signedIn(j);
  }

  // ------------------------------------------------------------ Google

  /// Opens Google's sign-in. On the web the page goes to Google and comes
  /// back; on Android it opens in the browser and returns to the app.
  Future<bool> startGoogle({String? emailHint}) async {
    final params = <String, String>{
      if (!kIsWeb) 'app': 'android',
      if (emailHint != null && emailHint.trim().isNotEmpty)
        'email': emailHint.trim(),
    };
    final uri = Uri.parse('${Backend.url}/auth/google/start')
        .replace(queryParameters: params.isEmpty ? null : params);
    return launchUrl(
      uri,
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
      webOnlyWindowName: '_self',
    );
  }

  // ------------------------------------------------------------ profile

  Future<void> updateName(String name) async {
    final r = await _send('PUT', '/v1/me', {'name': name});
    _setUser(Account.fromJson(r['user'] as Map<String, dynamic>));
  }

  /// Crops the picture to a square, makes it 320 px and a small JPEG, and
  /// uploads it.
  Future<void> uploadAvatar(Uint8List bytes) async {
    final jpeg = await compute(squareJpeg, bytes);
    if (jpeg == null) throw AccountException('invalid_image', '');
    final j = await _post('/v1/me/avatar', {'image': base64Encode(jpeg)});
    _setUser(Account.fromJson(j['user'] as Map<String, dynamic>));
  }

  Future<void> removeAvatar() async {
    final j = await _post('/v1/me/avatar/remove', {});
    _setUser(Account.fromJson(j['user'] as Map<String, dynamic>));
  }

  Future<void> signOut() async {
    final token = Backend.authToken;
    await _clear();
    if (token.isEmpty) return;
    try {
      final c = _client();
      await c
          .post(
            Uri.parse('${Backend.url}/v1/auth/logout'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10))
          .whenComplete(c.close);
    } catch (_) {}
  }

  // ------------------------------------------------------------ plumbing

  Future<void> _signedIn(Map<String, dynamic> j) async {
    final token = '${j['token'] ?? ''}';
    if (token.isEmpty) throw AccountException('unknown', '');
    Backend.authToken = token;
    await _prefs.setString(_kToken, token);
    introSeen = true;
    _setUser(Account.fromJson(j['user'] as Map<String, dynamic>));
  }

  void _setUser(Account u) {
    _user = u;
    _prefs.setString(_kUser, jsonEncode(u.toJson()));
    notifyListeners();
  }

  Future<void> _clear() async {
    Backend.authToken = '';
    _user = null;
    await _prefs.remove(_kToken);
    await _prefs.remove(_kUser);
    notifyListeners();
  }

  /// The server said this session is no longer valid (chat got a 401).
  void _expired() {
    if (_user != null || Backend.authToken.isNotEmpty) unawaited(_clear());
  }

  Future<Map<String, dynamic>> _get(String path) => _send('GET', path, null);
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) =>
      _send('POST', path, body);

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    final uri = Uri.parse('${Backend.url}$path');
    final headers = <String, String>{
      if (body != null) 'Content-Type': 'application/json',
      if (Backend.authToken.isNotEmpty)
        'Authorization': 'Bearer ${Backend.authToken}',
    };
    http.Response r;
    final client = _client();
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      r = await http.Response.fromStream(
        await client.send(req).timeout(_timeout),
      ).timeout(_timeout);
    } on TimeoutException {
      throw AccountException('timeout', '');
    } catch (_) {
      throw AccountException('network', '');
    } finally {
      client.close();
    }
    Map<String, dynamic> j = {};
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map<String, dynamic>) j = d;
    } catch (_) {}
    if (r.statusCode >= 200 && r.statusCode < 300) return j;
    final e = j['error'] is Map ? j['error'] as Map : const {};
    var code = '${e['code'] ?? ''}';
    if (code.isEmpty) {
      code = switch (r.statusCode) {
        401 => 'signed_out',
        429 => 'too_soon',
        413 => 'image_too_large',
        502 || 503 || 504 => 'unavailable',
        _ => 'unknown',
      };
    }
    throw AccountException(
      code,
      '${e['message'] ?? ''}',
      retryAfter: (e['retryAfter'] as num?)?.toInt(),
      triesLeft: (e['triesLeft'] as num?)?.toInt(),
    );
  }
}

/// Square, 320 px, JPEG: a few tens of KB. Null when it is not a picture.
Uint8List? squareJpeg(Uint8List bytes) {
  final src = img.decodeImage(bytes);
  if (src == null) return null;
  final upright = img.bakeOrientation(src);
  final side = upright.width < upright.height ? upright.width : upright.height;
  final square = img.copyCrop(
    upright,
    x: (upright.width - side) ~/ 2,
    y: (upright.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final small = side > 320
      ? img.copyResize(
          square,
          width: 320,
          height: 320,
          interpolation: img.Interpolation.average,
        )
      : square;
  var q = 86;
  var out = img.encodeJpg(small, quality: q);
  while (out.length > 150 * 1024 && q > 40) {
    q -= 12;
    out = img.encodeJpg(small, quality: q);
  }
  return out;
}
