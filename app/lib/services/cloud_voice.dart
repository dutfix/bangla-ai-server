import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'backend.dart';

/// The admin's cloud voice (Microsoft, Google, ElevenLabs...): the server
/// turns one sentence into MP3 audio (POST /v1/tts). The provider and its key
/// stay on the server; the app only sends text and plays what comes back.
class CloudVoice {
  CloudVoice({http.Client Function()? clientFactory, this.deviceId = ''})
    : _newClient = clientFactory ?? http.Client.new;

  final http.Client Function() _newClient;

  /// The install id, for the admin's usage counts (see SettingsStore).
  String deviceId;
  http.Client? _client;

  /// One kept-alive connection for a whole call, so each sentence skips the
  /// connection setup.
  http.Client get _c => _client ??= _newClient();

  Future<Uint8List> speak(String text) async {
    final res = await _c
        .post(
          Backend.uri('/v1/tts'),
          headers: {
            'Content-Type': 'application/json',
            if (deviceId.isNotEmpty) 'X-Device': deviceId,
          },
          body: jsonEncode({'text': text}),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) {
      var msg = 'voice ${res.statusCode}';
      try {
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        final e = j is Map ? j['error'] : null;
        if (e is Map && e['message'] != null) msg = '${e['message']}';
      } catch (_) {}
      throw Exception(msg);
    }
    return res.bodyBytes;
  }

  void close() {
    _client?.close();
    _client = null;
  }
}
