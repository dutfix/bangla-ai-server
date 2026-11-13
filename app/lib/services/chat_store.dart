import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat.dart';

/// A search hit in the chat history.
class ChatSearchHit {
  ChatSearchHit(this.conversation, this.snippet);
  final Conversation conversation;

  /// The matching bit of a message, or null when only the title matched.
  final String? snippet;
}

/// Saved chats, kept in one JSON file in the app's private storage. In the
/// web version they are kept in the browser's local storage instead.
class ChatStore extends ChangeNotifier {
  ChatStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;
  final List<Conversation> _all = [];
  File? _file;
  Timer? _saveTimer;

  /// Above this many characters, saved chats are read and written in a
  /// background isolate.
  static const _bigFile = 200 * 1024;

  /// Newest first.
  List<Conversation> get conversations {
    final list = _all.where((c) => c.messages.isNotEmpty).toList()
      ..sort((a, b) => b.updated.compareTo(a.updated));
    return list;
  }

  Conversation? byId(String id) {
    for (final c in _all) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The browser storage key for saved chats (web only).
  static const _webKey = 'chats_v1';
  SharedPreferences? _webPrefs;

  Future<void> load() async {
    if (kIsWeb) {
      try {
        _webPrefs = await SharedPreferences.getInstance();
        final text = _webPrefs!.getString(_webKey);
        if (text != null && text.isNotEmpty) _readAll(jsonDecode(text));
      } catch (e) {
        debugPrint('Could not read saved chats: $e');
      }
      notifyListeners();
      return;
    }
    final dir = await _directory();
    await dir.create(recursive: true);
    _file = File('${dir.path}/chats.json');
    try {
      if (await _file!.exists()) {
        final text = await _file!.readAsString();
        _lastSize = text.length;
        // A long history is decoded off the UI thread, so start-up does not
        // freeze while it loads.
        final data = text.length > _bigFile
            ? await Isolate.run(() => jsonDecode(text))
            : jsonDecode(text);
        _readAll(data);
      }
    } catch (e) {
      debugPrint('Could not read saved chats: $e');
    }
    notifyListeners();
  }

  void _readAll(Object? data) {
    if (data is Map && data['conversations'] is List) {
      _all
        ..clear()
        ..addAll(
          (data['conversations'] as List).whereType<Map>().map(
            (m) => Conversation.fromJson(m.cast<String, dynamic>()),
          ),
        );
    }
  }

  Conversation create() {
    final c = Conversation();
    _all.add(c);
    return c;
  }

  /// Call after changing a conversation. [touch] moves it to the top.
  void changed(Conversation c, {bool touch = true, bool now = false}) {
    if (touch) c.updated = DateTime.now();
    notifyListeners();
    _scheduleSave(now: now);
  }

  void rename(Conversation c, String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    c
      ..title = t
      ..titled = true;
    changed(c, touch: false, now: true);
  }

  void delete(Conversation c) {
    _all.removeWhere((x) => x.id == c.id);
    notifyListeners();
    _scheduleSave(now: true);
  }

  void deleteAll() {
    _all.clear();
    notifyListeners();
    _scheduleSave(now: true);
  }

  /// Matches titles and message text, case-insensitively.
  List<ChatSearchHit> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return conversations.map((c) => ChatSearchHit(c, null)).toList();
    }
    final hits = <ChatSearchHit>[];
    for (final c in conversations) {
      if (c.title.toLowerCase().contains(q)) {
        hits.add(ChatSearchHit(c, null));
        continue;
      }
      for (final m in c.messages) {
        final i = m.text.toLowerCase().indexOf(q);
        if (i >= 0) {
          hits.add(ChatSearchHit(c, snippetAround(m.text, i, q.length)));
          break;
        }
      }
    }
    return hits;
  }

  static String snippetAround(String text, int index, int length) {
    final start = (index - 30).clamp(0, text.length);
    final end = (index + length + 50).clamp(0, text.length);
    final s = text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ').trim();
    return '${start > 0 ? '...' : ''}$s${end < text.length ? '...' : ''}';
  }

  void _scheduleSave({bool now = false}) {
    _saveTimer?.cancel();
    if (now) {
      unawaited(flush());
    } else {
      _saveTimer = Timer(const Duration(milliseconds: 600), flush);
    }
  }

  Future<void>? _writing;
  int _lastSize = 0;

  /// Writes to disk now (atomically: temp file, then rename).
  Future<void> flush() async {
    _saveTimer?.cancel();
    if (kIsWeb) {
      final prefs = _webPrefs;
      if (prefs == null) return;
      try {
        await prefs.setString(_webKey, jsonEncode(_payload()));
      } catch (e) {
        debugPrint('Could not save chats: $e');
      }
      return;
    }
    final file = _file;
    if (file == null) return;
    while (_writing != null) {
      await _writing;
    }
    final data = _payload();
    final json = _lastSize > _bigFile
        ? await Isolate.run(() => jsonEncode(data))
        : jsonEncode(data);
    _lastSize = json.length;
    final done = Completer<void>();
    _writing = done.future;
    try {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('Could not save chats: $e');
    } finally {
      _writing = null;
      done.complete();
    }
  }

  Map<String, Object> _payload() => {
    'version': 1,
    'conversations': _all
        .where((c) => c.messages.isNotEmpty)
        .map((c) => c.toJson())
        .toList(),
  };

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
