import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent.dart';
import '../models/chat.dart' show newId;
import 'backend.dart';

/// A fact an agent remembers about the user.
class MemoryItem {
  MemoryItem({
    required this.id,
    required this.text,
    required this.agent,
    this.shared = false,
    DateTime? at,
  }) : at = at ?? DateTime.now();
  final String id;
  String text;
  final String agent;

  /// Every agent sees it (name, city), not just the one that saved it.
  bool shared;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'agent': agent,
    'shared': shared,
    'at': at.millisecondsSinceEpoch,
  };
  factory MemoryItem.fromJson(Map<String, dynamic> j) => MemoryItem(
    id: j['id'] as String,
    text: j['text'] as String? ?? '',
    agent: j['agent'] as String? ?? defaultAgentId,
    shared: j['shared'] == true,
    at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0),
  );
}

/// A note or file an agent (or the user) saved.
class NoteItem {
  NoteItem({
    required this.id,
    required this.title,
    required this.content,
    required this.agent,
    DateTime? created,
    DateTime? updated,
  }) : created = created ?? DateTime.now(),
       updated = updated ?? DateTime.now();
  final String id;
  String title;
  String content;
  final String agent;
  final DateTime created;
  DateTime updated;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'agent': agent,
    'created': created.millisecondsSinceEpoch,
    'updated': updated.millisecondsSinceEpoch,
  };
  factory NoteItem.fromJson(Map<String, dynamic> j) => NoteItem(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    content: j['content'] as String? ?? '',
    agent: j['agent'] as String? ?? defaultAgentId,
    created: DateTime.fromMillisecondsSinceEpoch(j['created'] as int? ?? 0),
    updated: DateTime.fromMillisecondsSinceEpoch(j['updated'] as int? ?? 0),
  );
}

enum Repeat { none, daily, weekdays, weekly }

/// A reminder, or a routine when it repeats. With [task] set, the agent
/// also does that work as a background task when it is due.
class ReminderItem {
  ReminderItem({
    required this.id,
    required this.text,
    required this.at,
    required this.agent,
    this.repeat = Repeat.none,
    this.task = '',
    this.done = false,
  });
  final String id;
  String text;

  /// The next time it rings.
  DateTime at;
  final String agent;
  Repeat repeat;
  String task;

  /// A one-off reminder that already rang.
  bool done;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'at': at.millisecondsSinceEpoch,
    'agent': agent,
    'repeat': repeat.name,
    if (task.isNotEmpty) 'task': task,
    if (done) 'done': true,
  };
  factory ReminderItem.fromJson(Map<String, dynamic> j) => ReminderItem(
    id: j['id'] as String,
    text: j['text'] as String? ?? '',
    at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0),
    agent: j['agent'] as String? ?? defaultAgentId,
    repeat: Repeat.values.firstWhere(
      (r) => r.name == j['repeat'],
      orElse: () => Repeat.none,
    ),
    task: j['task'] as String? ?? '',
    done: j['done'] == true,
  );

  /// The next time after [from]. Work days are Sunday to Thursday, the
  /// work week in Bangladesh.
  DateTime nextAfter(DateTime from) {
    var t = at;
    Duration step = switch (repeat) {
      Repeat.weekly => const Duration(days: 7),
      _ => const Duration(days: 1),
    };
    while (!t.isAfter(from)) {
      t = DateTime(t.year, t.month, t.day + step.inDays, t.hour, t.minute);
    }
    if (repeat == Repeat.weekdays) {
      while (t.weekday == DateTime.friday || t.weekday == DateTime.saturday) {
        t = DateTime(t.year, t.month, t.day + 1, t.hour, t.minute);
      }
    }
    return t;
  }
}

/// A skill the user taught an agent.
class SkillItem {
  SkillItem({
    required this.id,
    required this.title,
    required this.text,
    required this.agent,
  });
  final String id;
  String title;
  String text;
  final String agent;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'text': text,
    'agent': agent,
  };
  factory SkillItem.fromJson(Map<String, dynamic> j) => SkillItem(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    text: j['text'] as String? ?? '',
    agent: j['agent'] as String? ?? defaultAgentId,
  );
}

/// A background task running (or done) on the server. Only this device
/// holds its [token], so only it can read the result.
class TaskItem {
  TaskItem({
    required this.id,
    required this.token,
    required this.title,
    required this.agent,
    this.goal = '',
    this.status = 'queued',
    this.result = '',
    this.error = '',
    List<String>? steps,
    DateTime? created,
    this.finished,
    this.seen = false,
  }) : steps = steps ?? [],
       created = created ?? DateTime.now();
  final String id;
  final String token;
  final String title;
  final String agent;
  final String goal;

  /// queued, running, done, failed, cancelled or missing.
  String status;
  String result;
  String error;
  List<String> steps;
  final DateTime created;
  DateTime? finished;

  /// The user opened the result.
  bool seen;

  bool get active => status == 'queued' || status == 'running';

  Map<String, dynamic> toJson() => {
    'id': id,
    'token': token,
    'title': title,
    'agent': agent,
    'goal': goal,
    'status': status,
    'result': result,
    'error': error,
    'steps': steps,
    'created': created.millisecondsSinceEpoch,
    'finished': ?finished?.millisecondsSinceEpoch,
    'seen': seen,
  };
  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(
    id: j['id'] as String,
    token: j['token'] as String? ?? '',
    title: j['title'] as String? ?? '',
    agent: j['agent'] as String? ?? defaultAgentId,
    goal: j['goal'] as String? ?? '',
    status: j['status'] as String? ?? 'queued',
    result: j['result'] as String? ?? '',
    error: j['error'] as String? ?? '',
    steps: (j['steps'] as List? ?? []).whereType<String>().toList(),
    created: DateTime.fromMillisecondsSinceEpoch(j['created'] as int? ?? 0),
    finished: j['finished'] is int
        ? DateTime.fromMillisecondsSinceEpoch(j['finished'] as int)
        : null,
    seen: j['seen'] == true,
  );
}

/// A reminder that is ringing now.
class Ringing {
  Ringing(this.reminder, {this.taskId});
  final ReminderItem reminder;

  /// The background task it started, if it has one.
  final String? taskId;
}

/// Everything the agents keep for this user, saved on the device: memory,
/// notes, reminders and routines, skills and background tasks. It applies
/// the actions the agents send, builds the context sent with each message,
/// rings reminders and follows background tasks.
class AgentStore extends ChangeNotifier {
  AgentStore({
    http.Client Function()? clientFactory,
    this.deviceId = '',
    DateTime Function()? clock,
    this.runsTimers = false,
  }) : _newClient = clientFactory ?? http.Client.new,
       _clock = clock ?? DateTime.now;

  final http.Client Function() _newClient;
  final DateTime Function() _clock;
  String deviceId;

  /// Rings reminders on a timer. Off in widget tests, which forbid timers
  /// that outlive them; the app turns it on.
  final bool runsTimers;

  static const _key = 'agents_v1';

  String _agent = defaultAgentId;
  final List<MemoryItem> memory = [];
  final List<NoteItem> notes = [];
  final List<ReminderItem> reminders = [];
  final List<SkillItem> skills = [];
  final List<TaskItem> tasks = [];

  /// Reminders ringing now; the screen shows them and calls [dismiss].
  final List<Ringing> ringing = [];

  /// Tasks that just finished; the screen tells the user once.
  final List<TaskItem> justFinished = [];

  Timer? _ticker;
  Timer? _saveTimer;
  bool _polling = false;
  DateTime _lastPoll = DateTime.fromMillisecondsSinceEpoch(0);

  /// The agent chosen for new chats.
  String get agentId => _agent;
  set agentId(String id) {
    if (id == _agent || !agents.any((a) => a.id == id)) return;
    _agent = id;
    _save();
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) _read(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Agent data could not be read: $e');
    }
  }

  void _read(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) => (j[k] as List? ?? [])
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    _agent = agentById(j['agent'] as String?).id;
    memory
      ..clear()
      ..addAll(list('memory').map(MemoryItem.fromJson));
    notes
      ..clear()
      ..addAll(list('notes').map(NoteItem.fromJson));
    reminders
      ..clear()
      ..addAll(list('reminders').map(ReminderItem.fromJson));
    skills
      ..clear()
      ..addAll(list('skills').map(SkillItem.fromJson));
    tasks
      ..clear()
      ..addAll(list('tasks').map(TaskItem.fromJson));
  }

  Map<String, dynamic> toJson() => {
    'agent': _agent,
    'memory': memory.map((m) => m.toJson()).toList(),
    'notes': notes.map((m) => m.toJson()).toList(),
    'reminders': reminders.map((m) => m.toJson()).toList(),
    'skills': skills.map((m) => m.toJson()).toList(),
    'tasks': tasks.map((m) => m.toJson()).toList(),
  };

  void _save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_key, jsonEncode(toJson()));
      } catch (e) {
        debugPrint('Agent data could not be saved: $e');
      }
    });
  }

  void _changed() {
    _save();
    notifyListeners();
  }

  /// Starts ringing reminders and following tasks. Call once at startup.
  void start() {
    if (!runsTimers) return;
    _ticker ??= Timer.periodic(const Duration(seconds: 15), (_) => tick());
    unawaited(tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _saveTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- actions

  /// Applies an action an agent sent in its reply. Returns true when it
  /// changed something.
  bool apply(Map<String, Object?> e) {
    String s(String k) => (e[k] as String?) ?? '';
    final agent = agentById(s('agent')).id;
    final id = s('id');
    if (id.isEmpty) return false;
    switch (s('action')) {
      case 'memory_add':
        memory.removeWhere((m) => m.id == id);
        memory.add(
          MemoryItem(
            id: id,
            text: s('text'),
            agent: agent,
            shared: e['shared'] == true,
          ),
        );
        if (memory.length > 200) memory.removeAt(0);
      case 'memory_remove':
        memory.removeWhere((m) => m.id == id);
      case 'note_save':
        final old = notes.where((n) => n.id == id).firstOrNull;
        if (old != null) {
          old
            ..title = s('title')
            ..content = s('content')
            ..updated = _clock();
        } else {
          notes.add(
            NoteItem(
              id: id,
              title: s('title'),
              content: s('content'),
              agent: agent,
            ),
          );
        }
      case 'note_delete':
        notes.removeWhere((n) => n.id == id);
      case 'reminder_add':
        final at = DateTime.tryParse(s('at'))?.toLocal();
        if (at == null) return false;
        reminders.add(
          ReminderItem(
            id: id,
            text: s('text'),
            at: at,
            agent: agent,
            repeat: Repeat.values.firstWhere(
              (r) => r.name == s('repeat'),
              orElse: () => Repeat.none,
            ),
            task: s('task'),
          ),
        );
      case 'reminder_remove':
        reminders.removeWhere((r) => r.id == id);
      case 'skill_save':
        final old = skills.where((k) => k.id == id).firstOrNull;
        if (old != null) {
          old
            ..title = s('title')
            ..text = s('text');
        } else {
          skills.add(
            SkillItem(id: id, title: s('title'), text: s('text'), agent: agent),
          );
        }
      case 'skill_remove':
        skills.removeWhere((k) => k.id == id);
      case 'task_started':
        if (tasks.any((t) => t.id == id)) return false;
        tasks.insert(
          0,
          TaskItem(
            id: id,
            token: s('token'),
            title: s('title'),
            goal: s('goal'),
            agent: agent,
          ),
        );
        _trimTasks();
        _lastPoll = DateTime.fromMillisecondsSinceEpoch(0);
      default:
        return false;
    }
    _changed();
    return true;
  }

  void _trimTasks() {
    while (tasks.length > 50) {
      tasks.removeLast();
    }
  }

  // ---------------------------------------------------------------- editing

  void removeMemory(String id) {
    memory.removeWhere((m) => m.id == id);
    _changed();
  }

  void addMemory(String text, String agent, {bool shared = true}) {
    final t = text.trim();
    if (t.isEmpty) return;
    memory.add(
      MemoryItem(id: 'm${newId()}', text: t, agent: agent, shared: shared),
    );
    _changed();
  }

  void clearMemory(String? agent) {
    memory.removeWhere((m) => agent == null || m.agent == agent);
    _changed();
  }

  NoteItem saveNote({
    String? id,
    required String title,
    required String content,
    required String agent,
  }) {
    final old = id == null ? null : notes.where((n) => n.id == id).firstOrNull;
    if (old != null) {
      old
        ..title = title
        ..content = content
        ..updated = _clock();
      _changed();
      return old;
    }
    final n = NoteItem(
      id: 'n${newId()}',
      title: title,
      content: content,
      agent: agent,
    );
    notes.add(n);
    _changed();
    return n;
  }

  void removeNote(String id) {
    notes.removeWhere((n) => n.id == id);
    _changed();
  }

  void removeReminder(String id) {
    reminders.removeWhere((r) => r.id == id);
    _changed();
  }

  void saveSkill({
    String? id,
    required String title,
    required String text,
    required String agent,
  }) {
    final old = id == null ? null : skills.where((k) => k.id == id).firstOrNull;
    if (old != null) {
      old
        ..title = title
        ..text = text;
    } else {
      skills.add(
        SkillItem(id: 's${newId()}', title: title, text: text, agent: agent),
      );
    }
    _changed();
  }

  void removeSkill(String id) {
    skills.removeWhere((k) => k.id == id);
    _changed();
  }

  void removeTask(String id) {
    tasks.removeWhere((t) => t.id == id);
    _changed();
  }

  void markSeen(TaskItem t) {
    if (t.seen) return;
    t.seen = true;
    _changed();
  }

  int get unseenTasks =>
      tasks.where((t) => !t.seen && t.status == 'done').length;

  // ---------------------------------------------------------------- context

  /// The user's local time with its UTC offset, e.g.
  /// "2026-11-13T18:30:00+06:00 (Friday)".
  String localNow() {
    final n = _clock();
    final off = n.timeZoneOffset;
    String two(int v) => v.abs().toString().padLeft(2, '0');
    final sign = off.isNegative ? '-' : '+';
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return '${n.year}-${two(n.month)}-${two(n.day)}T${two(n.hour)}:'
        '${two(n.minute)}:00$sign${two(off.inHours)}:'
        '${two(off.inMinutes % 60)} (${days[n.weekday - 1]})';
  }

  /// What an agent knows about the user, sent with each message.
  Map<String, Object?> contextFor(String agent, {String name = ''}) {
    String iso(DateTime t) => t.toIso8601String();
    final recentNotes = [...notes]
      ..sort((a, b) => b.updated.compareTo(a.updated));
    return {
      if (name.isNotEmpty) 'name': name,
      'now': localNow(),
      'memory': memory
          .where((m) => m.shared || m.agent == agent)
          .map((m) => {'id': m.id, 'text': m.text, 'shared': m.shared})
          .toList(),
      'skills': skills
          .where((k) => k.agent == agent)
          .map((k) => {'id': k.id, 'title': k.title, 'text': k.text})
          .toList(),
      'notes': recentNotes
          .take(20)
          .map(
            (n) => {
              'id': n.id,
              'title': n.title,
              'text': n.content.length > 1200
                  ? n.content.substring(0, 1200)
                  : n.content,
            },
          )
          .toList(),
      'reminders': reminders
          .where((r) => !r.done)
          .take(30)
          .map(
            (r) => {
              'id': r.id,
              'text': r.text,
              'at': iso(r.at),
              'repeat': r.repeat.name,
              'task': r.task,
            },
          )
          .toList(),
      'tasks': tasks
          .take(10)
          .map(
            (t) => {
              'id': t.id,
              'title': t.title,
              'status': t.status,
              'result': t.result.length > 600
                  ? t.result.substring(0, 600)
                  : t.result,
            },
          )
          .toList(),
    };
  }

  // ---------------------------------------------------------------- reminders

  /// Rings what is due and follows running tasks. Runs every 15 seconds.
  Future<void> tick() async {
    final now = _clock();
    var changed = false;
    for (final r in reminders.where((r) => !r.done).toList()) {
      if (r.at.isAfter(now)) continue;
      String? taskId;
      if (r.task.isNotEmpty) {
        taskId = await _startFromReminder(r);
      }
      ringing.add(Ringing(r, taskId: taskId));
      if (r.repeat == Repeat.none) {
        r.done = true;
      } else {
        r.at = r.nextAfter(now);
      }
      changed = true;
    }
    // One-off reminders that rang over a week ago are tidied away.
    final before = reminders.length;
    reminders.removeWhere(
      (r) => r.done && now.difference(r.at) > const Duration(days: 7),
    );
    if (changed || reminders.length != before) _changed();
    if (tasks.any((t) => t.active) &&
        now.difference(_lastPoll) > const Duration(seconds: 8)) {
      await pollTasks();
    }
  }

  void dismiss(Ringing r) {
    ringing.remove(r);
    notifyListeners();
  }

  Future<String?> _startFromReminder(ReminderItem r) async {
    try {
      final t = await startTask(agent: r.agent, title: r.text, goal: r.task);
      return t.id;
    } catch (e) {
      debugPrint('Routine task could not start: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------- tasks

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (deviceId.isNotEmpty) 'X-Device': deviceId,
  };

  /// Starts a background task on the server.
  Future<TaskItem> startTask({
    required String agent,
    required String title,
    required String goal,
  }) async {
    final client = _newClient();
    try {
      final res = await client
          .post(
            Backend.uri('/v1/tasks'),
            headers: _headers,
            body: jsonEncode({
              'agent': agent,
              'title': title,
              'goal': goal,
              'context': contextFor(agent),
            }),
          )
          .timeout(Backend.wakeTimeout);
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode != 200) {
        final err = j is Map ? j['error'] : null;
        throw Exception(err is Map ? err['message'] : 'HTTP ${res.statusCode}');
      }
      final t = (j as Map)['task'] as Map;
      final item = TaskItem(
        id: t['id'] as String,
        token: t['token'] as String,
        title: t['title'] as String? ?? title,
        goal: goal,
        agent: agent,
      );
      tasks.insert(0, item);
      _trimTasks();
      _lastPoll = DateTime.fromMillisecondsSinceEpoch(0);
      _changed();
      return item;
    } finally {
      client.close();
    }
  }

  /// Asks the server how the running tasks are doing.
  Future<void> pollTasks() async {
    if (_polling) return;
    final active = tasks.where((t) => t.active).toList();
    if (active.isEmpty) return;
    _polling = true;
    _lastPoll = _clock();
    final client = _newClient();
    try {
      final res = await client
          .post(
            Backend.uri('/v1/tasks/status'),
            headers: _headers,
            body: jsonEncode({
              'tasks': [
                for (final t in active) {'id': t.id, 'token': t.token},
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return;
      final list = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['tasks'];
      var changed = false;
      for (final j in (list as List).whereType<Map>()) {
        final t = active.where((x) => x.id == j['id']).firstOrNull;
        if (t == null) continue;
        final status = j['status'] as String? ?? t.status;
        final steps = (j['steps'] as List? ?? [])
            .whereType<Map>()
            .map((s) => '${s['tool']}|${s['detail'] ?? ''}')
            .toList();
        if (status != t.status || steps.length != t.steps.length) {
          changed = true;
        }
        t
          ..status = status
          ..result = j['result'] as String? ?? t.result
          ..error = j['error'] as String? ?? t.error
          ..steps = steps.isEmpty ? t.steps : steps;
        if (!t.active) {
          t.finished = _clock();
          justFinished.add(t);
        }
      }
      if (changed) _changed();
    } catch (e) {
      debugPrint('Task status failed: $e');
    } finally {
      client.close();
      _polling = false;
    }
  }

  Future<void> cancelTask(TaskItem t) async {
    final client = _newClient();
    try {
      await client
          .post(
            Backend.uri('/v1/tasks/${t.id}/cancel'),
            headers: _headers,
            body: jsonEncode({'token': t.token}),
          )
          .timeout(const Duration(seconds: 30));
      t.status = 'cancelled';
      _changed();
    } finally {
      client.close();
    }
  }
}
