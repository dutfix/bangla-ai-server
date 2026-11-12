import 'dart:math';

enum Role { user, assistant }

final _rand = Random();

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${_rand.nextInt(1 << 32).toRadixString(36)}';

/// One message in a conversation.
class ChatMessage {
  ChatMessage({
    String? id,
    required this.role,
    this.text = '',
    DateTime? at,
    this.viaVoice = false,
    this.error,
    this.stopped = false,
    this.model,
  }) : id = id ?? newId(),
       at = at ?? DateTime.now();

  final String id;
  final Role role;
  String text;
  final DateTime at;

  /// Said or heard during a voice call.
  bool viaVoice;

  /// Why the reply failed, if it did.
  String? error;

  /// The user stopped or interrupted this reply.
  bool stopped;

  /// The model that wrote this reply.
  String? model;

  bool get isUser => role == Role.user;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'text': text,
    'at': at.millisecondsSinceEpoch,
    if (viaVoice) 'voice': true,
    if (error != null) 'error': error,
    if (stopped) 'stopped': true,
    if (model != null) 'model': model,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j['id'] as String?,
    role: j['role'] == 'user' ? Role.user : Role.assistant,
    text: j['text'] as String? ?? '',
    at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0),
    viaVoice: j['voice'] == true,
    error: j['error'] as String?,
    stopped: j['stopped'] == true,
    model: j['model'] as String?,
  );
}

/// A saved chat.
class Conversation {
  Conversation({
    String? id,
    this.title = '',
    DateTime? created,
    DateTime? updated,
    List<ChatMessage>? messages,
    this.titled = false,
  }) : id = id ?? newId(),
       created = created ?? DateTime.now(),
       updated = updated ?? DateTime.now(),
       messages = messages ?? [];

  final String id;
  String title;
  final DateTime created;
  DateTime updated;
  final List<ChatMessage> messages;

  /// The title was set by the AI or the user (not just the first words).
  bool titled;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'created': created.millisecondsSinceEpoch,
    'updated': updated.millisecondsSinceEpoch,
    'titled': titled,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
    id: j['id'] as String?,
    // Old versions stored the English placeholder.
    title: switch (j['title']) {
      'New chat' || null => '',
      final String t => t,
      _ => '',
    },
    created: DateTime.fromMillisecondsSinceEpoch(j['created'] as int? ?? 0),
    updated: DateTime.fromMillisecondsSinceEpoch(j['updated'] as int? ?? 0),
    titled: j['titled'] == true,
    messages: (j['messages'] as List? ?? [])
        .whereType<Map>()
        .map((m) => ChatMessage.fromJson(m.cast<String, dynamic>()))
        .toList(),
  );
}

/// A quick title from the first words of the first message.
String provisionalTitle(String text) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.isEmpty) return '';
  final words = clean.split(' ');
  var t = words.take(6).join(' ');
  if (t.length > 40) {
    t = '${t.substring(0, 40).trimRight()}...';
  } else if (words.length > 6) {
    t = '$t...';
  }
  return t;
}

/// Cleans up a title the AI wrote: one line, no quotes or trailing dot.
String cleanTitle(String raw) {
  var t = raw.trim().split('\n').first.trim();
  t = t.replaceFirst(
    RegExp(r'^(title|chat title|শিরোনাম)\s*[:：]\s*', caseSensitive: false),
    '',
  );
  t = t.replaceAll(RegExp(r'''^[\s"'*#`“”‘’]+|[\s"'*#`.।“”‘’]+$'''), '');
  if (t.length > 60) t = '${t.substring(0, 57).trimRight()}...';
  return t;
}
