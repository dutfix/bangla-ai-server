import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// The Bangla AI server on Render. It keeps the OmniRoute key, serves the
/// app config and passes chats on. Set at build time with
/// --dart-define=BACKEND_URL=https://... to use another server.
abstract final class Backend {
  static const url = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://bangla-ai-server-1a46.onrender.com',
  );

  /// A free Render service sleeps when idle and needs up to about a minute
  /// to wake, so the first request may wait this long.
  static const wakeTimeout = Duration(seconds: 90);

  static Uri uri(String path) => Uri.parse('$url$path');
}

/// The server is asleep or unreachable.
class BackendUnavailable implements Exception {
  BackendUnavailable({this.waking = false});

  /// True when the server looks like it is waking up (a timeout, or Render's
  /// 502/503 while the instance starts).
  final bool waking;
}

/// True for errors that mean "no internet or server asleep".
bool isNetworkError(Object e) =>
    e is SocketException ||
    e is TimeoutException ||
    e is HandshakeException ||
    e is http.ClientException ||
    e is BackendUnavailable;

/// Wakes the server: GET /health, retried until it answers or [total] runs
/// out. [onWaiting] fires once the first try is slow, so the UI can show
/// "server is waking up".
Future<bool> wakeServer({
  Duration total = Backend.wakeTimeout,
  void Function()? onWaiting,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final end = DateTime.now().add(total);
  var notified = false;
  final slow = Timer(const Duration(seconds: 3), () {
    notified = true;
    onWaiting?.call();
  });
  try {
    while (DateTime.now().isBefore(end)) {
      try {
        final left = end.difference(DateTime.now());
        final res = await c
            .get(Backend.uri('/health'))
            .timeout(
              left < const Duration(seconds: 70)
                  ? left
                  : const Duration(seconds: 70),
            );
        if (res.statusCode == 200) return true;
      } catch (_) {}
      if (!notified) {
        notified = true;
        onWaiting?.call();
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    return false;
  } finally {
    slow.cancel();
    if (client == null) c.close();
  }
}

/// Decodes a JSON body as UTF-8.
Map<String, dynamic> decodeJson(http.Response res) {
  final j = jsonDecode(utf8.decode(res.bodyBytes));
  return j is Map<String, dynamic> ? j : <String, dynamic>{};
}
