import 'dart:math';

enum Role { user, assistant }

// 0x7fffffff, not 1 << 32: on the web that shift is 0 and nextInt throws.
final _rand = Random();

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${_rand.nextInt(0x7fffffff).toRadixString(36)}';

/// One tool an agent used while writing a reply: a web search, a page it
/// read, a note it saved. Shown above the reply.
class ToolStep {
  ToolStep({
    required this.id,
    required this.name,
    this.detail = '',
    this.done = false,
    this.ok = true,
  });

  final String id;
  final String name;
  final String detail;
  bool done;
  bool ok;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (detail.isNotEmpty) 'detail': detail,
    'done': done,
    'ok': ok,
  };

  factory ToolStep.fromJson(Map<String, dynamic> j) => ToolStep(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    detail: j['detail'] as String? ?? '',
    // A step saved while running never finished.
    done: true,
    ok: j['ok'] != false && j['done'] == true,
  );
}

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
    List<ToolStep>? tools,
  }) : id = id ?? newId(),
       at = at ?? DateTime.now(),
       tools = tools ?? [];

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

  /// Tools the agent used for this reply, in order.
  final List<ToolStep> tools;

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
    if (tools.isNotEmpty) 'tools': tools.map((t) => t.toJson()).toList(),
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
    tools: (j['tools'] as List? ?? [])
        .whereType<Map>()
        .map((t) => ToolStep.fromJson(t.cast<String, dynamic>()))
        .toList(),
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
    this.agent,
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

  /// The agent this chat is with (an id from agents.dart). Chats from
  /// before agents have none and open with the default agent.
  String? agent;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'created': created.millisecondsSinceEpoch,
    'updated': updated.millisecondsSinceEpoch,
    'titled': titled,
    'agent': ?agent,
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
    agent: j['agent'] as String?,
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
