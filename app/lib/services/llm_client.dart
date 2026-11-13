import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import 'backend.dart';
import 'settings_store.dart';

class LlmException implements Exception {
  LlmException(this.message, {this.waking = false});
  final String message;

  /// The server was asleep; the message says it is waking up.
  final bool waking;
  @override
  String toString() => message;
}

/// Sends chats to the Bangla AI server (POST /v1/chat), which adds the
/// OmniRoute key and the admin's system prompt and streams the reply back.
class LlmClient {
  LlmClient(this.settings, {http.Client Function()? clientFactory})
    : _newClient = clientFactory ?? http.Client.new;
  final SettingsStore settings;
  final http.Client Function() _newClient;
  http.Client? _active;

  static final _url = Backend.uri('/v1/chat');
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (settings.deviceId.isNotEmpty) 'X-Device': settings.deviceId,
  };

  /// Streams the answer chunk by chunk (Server-Sent Events). Falls back to a
  /// normal response if the server does not stream.
  Stream<String> streamChat(
    List<Map<String, String>> messages, {
    String? model,
    void Function()? onWaking,
    bool call = false,
  }) async* {
    _checkEnabled();
    final client = _newClient();
    _active = client;
    try {
      final res = await _send(
        client,
        messages,
        model,
        true,
        onWaking,
        call: call,
      );
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        throw _error(res.statusCode, body);
      }
      final type = res.headers['content-type'] ?? '';
      if (!type.contains('text/event-stream')) {
        final body = await res.stream.bytesToString();
        yield _contentOf(jsonDecode(body));
        return;
      }
      final lines = res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data == '[DONE]') break;
        dynamic json;
        try {
          json = jsonDecode(data);
        } catch (_) {
          continue; // Keep-alive or non-JSON lines.
        }
        if (json is! Map) continue;
        final err = json['error'];
        if (err != null) {
          throw LlmException(err is Map ? '${err['message'] ?? err}' : '$err');
        }
        final choices = json['choices'];
        if (choices is List && choices.isNotEmpty) {
          final delta = choices.first['delta'];
          final c = delta is Map ? delta['content'] : null;
          if (c is String && c.isNotEmpty) yield c;
        }
      }
    } on LlmException {
      rethrow;
    } catch (e) {
      if (!identical(_active, client)) return; // Cancelled.
      if (isNetworkError(e)) throw LlmException(L10n.current.serverUnreachable);
      rethrow;
    } finally {
      client.close();
      if (identical(_active, client)) _active = null;
    }
  }

  /// Sends the request. If the server is asleep (no answer in a few seconds,
  /// or Render's 502/503 while it starts), calls [onWaking], waits for it to
  /// wake and sends once more.
  Future<http.StreamedResponse> _send(
    http.Client client,
    List<Map<String, String>> messages,
    String? model,
    bool stream,
    void Function()? onWaking, {
    bool call = false,
  }) async {
    // A call turn: the server picks a fast model, keeps replies short and
    // adds the call style.
    http.Request build() => http.Request('POST', _url)
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'model': model ?? settings.model,
        'messages': messages,
        'stream': stream,
        if (call) 'call': true,
      });
    if (!settings.serverAwake) {
      final ok = await wakeServer(onWaiting: onWaking);
      if (!ok) throw LlmException(L10n.current.serverUnreachable);
      settings.markServerAwake();
    }
    http.StreamedResponse res;
    try {
      res = await client.send(build()).timeout(Backend.wakeTimeout);
    } on TimeoutException {
      throw LlmException(L10n.current.timeoutError);
    }
    if (res.statusCode == 502 ||
        res.statusCode == 504 ||
        (res.statusCode == 503 && !_isOurs(res))) {
      // Render's own page while the instance restarts: wake and retry once.
      await res.stream.drain<void>();
      onWaking?.call();
      if (!await wakeServer()) {
        throw LlmException(L10n.current.serverUnreachable);
      }
      res = await client.send(build()).timeout(Backend.wakeTimeout);
    }
    settings.markServerAwake();
    return res;
  }

  static bool _isOurs(http.StreamedResponse res) =>
      (res.headers['content-type'] ?? '').contains('application/json');

  void _checkEnabled() {
    final r = settings.remote;
    if (!r.enabled) {
      throw LlmException(
        r.disabledMessage.isNotEmpty
            ? r.disabledMessage
            : L10n.current.appDisabled,
      );
    }
  }

  /// One normal (non-streamed) answer, used for chat titles.
  Future<String> complete(
    List<Map<String, String>> messages, {
    String? model,
    Duration timeout = Backend.wakeTimeout,
  }) async {
    final client = _newClient();
    try {
      final res = await _send(
        client,
        messages,
        model,
        false,
        null,
      ).timeout(timeout);
      final body = await res.stream.bytesToString();
      if (res.statusCode != 200) throw _error(res.statusCode, body);
      return _contentOf(jsonDecode(body));
    } finally {
      client.close();
    }
  }

  /// Stops the answer that is streaming right now (used for interrupting).
  void cancel() {
    _active?.close();
    _active = null;
  }

  static String _contentOf(dynamic json) {
    final choices = json is Map ? json['choices'] : null;
    if (choices is List && choices.isNotEmpty) {
      final msg = choices.first['message'];
      final content = msg is Map ? msg['content'] : null;
      if (content is String) return content;
    }
    throw LlmException(L10n.current.unexpectedResponse);
  }

  LlmException _error(int code, String body) {
    var detail = body;
    String? errCode;
    try {
      final j = jsonDecode(body);
      final err = j is Map ? j['error'] : null;
      if (err is Map) errCode = err['code'] as String?;
      detail = err is Map
          ? '${err['message'] ?? err}'
          : (err?.toString() ?? body);
    } catch (_) {}
    if (detail.length > 200) detail = '${detail.substring(0, 200)}...';
    final t = L10n.current;
    if (errCode == 'disabled') {
      settings.remoteDisabled(detail);
      return LlmException(detail.isNotEmpty ? detail : t.appDisabled);
    }
    return LlmException(switch (code) {
      503 => t.serverNotReady,
      429 => t.tooManyRequests,
      _ => t.aiRequestFailed(code, detail),
    });
  }
}
