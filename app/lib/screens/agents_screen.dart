import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/agent.dart';
import '../services/agent_store.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';
import '../widgets/agent_widgets.dart';
import '../widgets/components.dart';
import '../widgets/markdown_view.dart';

/// Everything the agents keep for the user, per agent: memory, notes,
/// reminders and routines, background tasks and skills.
class AgentsScreen extends StatefulWidget {
  const AgentsScreen({
    super.key,
    required this.store,
    this.initialTab = 0,
    this.onChatWith,
  });
  final AgentStore store;
  final int initialTab;

  /// Opens a new chat with an agent.
  final ValueChanged<String>? onChatWith;

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: 5,
    vsync: this,
    initialIndex: widget.initialTab,
  );

  /// null: all agents.
  String? _agent;

  AgentStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
    store.pollTasks();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool _mine(String agent) => _agent == null || agent == _agent;

  String get _addAgent => _agent ?? store.agentId;

  @override
  Widget build(BuildContext context) {
    final w = AgentText.of(context);
    final s = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(w.myAgents),
        leading: IconButton(
          key: const ValueKey('hub-back'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const HeroIcon(HeroIcons.arrowLeft),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: w.memory),
            Tab(text: w.notes),
            Tab(text: w.reminders),
            Tab(text: w.tasks),
            Tab(text: w.skills),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 2
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('hub-add'),
              onPressed: _add,
              backgroundColor: s.primary,
              foregroundColor: s.onPrimary,
              icon: const HeroIcon(HeroIcons.plus),
              label: Text(_tabs.index == 3 ? w.newTask : w.add),
            ),
      body: Column(
        children: [
          _agentFilter(w),
          Expanded(
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) => TabBarView(
                controller: _tabs,
                children: [
                  _memory(w),
                  _notes(w),
                  _reminders(w),
                  _tasks(w),
                  _skills(w),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _agentFilter(AgentText w) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final agent = _agent == null ? null : agentById(_agent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              ChoiceChip(
                label: Text(w.all),
                selected: _agent == null,
                onSelected: (_) => setState(() => _agent = null),
              ),
              for (final a in agents) ...[
                const SizedBox(width: Space.sm),
                ChoiceChip(
                  avatar: AgentAvatar(agent: a, size: 22),
                  label: Text(a.nameFor(w.en)),
                  selected: _agent == a.id,
                  onSelected: (_) => setState(() => _agent = a.id),
                ),
              ],
            ],
          ),
        ),
        if (agent != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${agent.roleFor(w.en)} · ${agent.blurbFor(w.en)}',
                    style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                  ),
                ),
                if (widget.onChatWith != null)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onChatWith!(agent.id);
                    },
                    icon: const HeroIcon(
                      HeroIcons.chatBubbleLeftRight,
                      size: 18,
                    ),
                    label: Text(w.t('কথা বলুন', 'Chat')),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _list(List<Widget> rows, Widget empty, {Widget? header}) {
    if (rows.isEmpty) {
      return ListView(children: [?header, empty]);
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [?header, ...rows],
    );
  }

  Widget _agentLine(String agent, String text) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final a = agentById(agent);
    return Row(
      children: [
        AgentAvatar(agent: a, size: 16),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text.isEmpty ? a.nameFor(AgentText.of(context).en) : text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.labelSmall?.copyWith(color: s.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  String _when(DateTime d) {
    final ml = MaterialLocalizations.of(context);
    return '${ml.formatMediumDate(d)}, ${ml.formatTimeOfDay(TimeOfDay.fromDateTime(d))}';
  }

  Widget _deleteButton(AgentText w, VoidCallback onPressed) => IconButton(
    tooltip: w.delete,
    icon: const HeroIcon(HeroIcons.trash, size: 20),
    onPressed: onPressed,
  );

  // ---------------------------------------------------------------- memory

  Widget _memory(AgentText w) {
    final items = store.memory.where((m) => _mine(m.agent) || (m.shared)).toList().reversed;
    return _list(
      [
        for (final m in items)
          ListTile(
            key: ValueKey(m.id),
            leading: const HeroIcon(HeroIcons.lightBulb),
            title: Text(m.text),
            subtitle: _agentLine(
              m.agent,
              m.shared
                  ? '${agentById(m.agent).nameFor(w.en)} · ${w.shared}'
                  : '',
            ),
            trailing: _deleteButton(w, () => store.removeMemory(m.id)),
          ),
      ],
      EmptyState(
        icon: HeroIcons.lightBulb,
        title: w.noMemory,
        sub: w.noMemorySub,
      ),
    );
  }

  // ---------------------------------------------------------------- notes

  Widget _notes(AgentText w) {
    final items = store.notes.where((n) => _mine(n.agent)).toList()
      ..sort((a, b) => b.updated.compareTo(a.updated));
    return _list(
      [
        for (final n in items)
          ListTile(
            key: ValueKey(n.id),
            leading: const HeroIcon(HeroIcons.documentText),
            title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: _agentLine(n.agent, _when(n.updated)),
            onTap: () => _openNote(n),
          ),
      ],
      EmptyState(
        icon: HeroIcons.documentText,
        title: w.noNotes,
        sub: w.noNotesSub,
      ),
    );
  }

  void _openNote(NoteItem n) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteScreen(store: store, note: n),
      ),
    );
  }

  // ---------------------------------------------------------------- reminders

  Widget _reminders(AgentText w) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final items = store.reminders.where((r) => _mine(r.agent) && !r.done).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    return _list(
      [
        for (final r in items)
          ListTile(
            key: ValueKey(r.id),
            leading: HeroIcon(
              r.task.isNotEmpty ? HeroIcons.bolt : HeroIcons.clock,
            ),
            title: Text(r.text),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_when(r.at)} · ${w.repeat(r.repeat.name)}'),
                if (r.task.isNotEmpty)
                  Text(
                    r.task,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: s.primary),
                  ),
                _agentLine(r.agent, ''),
              ],
            ),
            isThreeLine: true,
            trailing: _deleteButton(w, () => store.removeReminder(r.id)),
          ),
      ],
      EmptyState(
        icon: HeroIcons.clock,
        title: w.noReminders,
        sub: w.noRemindersSub,
      ),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Text(
          w.remindersNote,
          style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- tasks

  Widget _tasks(AgentText w) {
    final s = Theme.of(context).colorScheme;
    final items = store.tasks.where((t) => _mine(t.agent)).toList();
    return RefreshIndicator(
      onRefresh: store.pollTasks,
      child: _list(
        [
          for (final t in items)
            ListTile(
              key: ValueKey(t.id),
              leading: t.active
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: s.primary,
                      ),
                    )
                  : HeroIcon(
                      t.status == 'done'
                          ? HeroIcons.checkCircle
                          : HeroIcons.xCircle,
                      color: t.status == 'done' ? s.primary : s.error,
                    ),
              title: Text(
                t.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: !t.seen && t.status == 'done'
                    ? const TextStyle(fontWeight: FontWeight.w700)
                    : null,
              ),
              subtitle: _agentLine(
                t.agent,
                '${agentById(t.agent).nameFor(w.en)} · ${w.status(t.status)} · ${_when(t.created)}',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TaskScreen(store: store, task: t),
                ),
              ),
            ),
        ],
        EmptyState(
          icon: HeroIcons.bolt,
          title: w.noTasks,
          sub: w.noTasksSub,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- skills

  Widget _skills(AgentText w) {
    final items = store.skills.where((k) => _mine(k.agent)).toList();
    return _list(
      [
        for (final k in items)
          ListTile(
            key: ValueKey(k.id),
            leading: const HeroIcon(HeroIcons.sparkles),
            title: Text(k.title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                _agentLine(k.agent, ''),
              ],
            ),
            onTap: () => _editSkill(k),
            trailing: _deleteButton(w, () => store.removeSkill(k.id)),
          ),
      ],
      EmptyState(
        icon: HeroIcons.sparkles,
        title: w.noSkills,
        sub: w.noSkillsSub,
      ),
    );
  }

  // ---------------------------------------------------------------- adding

  Future<void> _add() async {
    final w = AgentText.of(context);
    switch (_tabs.index) {
      case 0:
        final r = await _form(
          title: w.newMemory,
          fields: [w.newMemory],
          multiline: false,
        );
        if (r != null) store.addMemory(r[0], _addAgent, shared: _agent == null);
      case 1:
        final r = await _form(title: w.newNote, fields: [w.title, w.notes]);
        if (r != null && r[0].trim().isNotEmpty) {
          store.saveNote(title: r[0].trim(), content: r[1], agent: _addAgent);
        }
      case 3:
        await _newTask();
      case 4:
        await _editSkill(null);
    }
  }

  Future<void> _editSkill(SkillItem? k) async {
    final w = AgentText.of(context);
    final r = await _form(
      title: k == null ? w.newSkill : w.edit,
      fields: [w.title, w.skillText],
      initial: k == null ? null : [k.title, k.text],
    );
    if (r == null || r[0].trim().isEmpty || r[1].trim().isEmpty) return;
    store.saveSkill(
      id: k?.id,
      title: r[0].trim(),
      text: r[1].trim(),
      agent: k?.agent ?? _addAgent,
    );
  }

  Future<void> _newTask() async {
    final w = AgentText.of(context);
    final r = await _form(
      title: '${w.newTask} · ${agentById(_addAgent).nameFor(w.en)}',
      fields: [w.title, w.taskGoal],
      confirm: w.start,
    );
    if (r == null || r[1].trim().isEmpty || !mounted) return;
    try {
      await store.startTask(
        agent: _addAgent,
        title: r[0].trim().isEmpty ? r[1].trim() : r[0].trim(),
        goal: r[1].trim(),
      );
    } catch (e) {
      if (mounted) showSnack(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// A small form: one or two text fields. Resolves the values, or null.
  Future<List<String>?> _form({
    required String title,
    required List<String> fields,
    List<String>? initial,
    bool multiline = true,
    String? confirm,
  }) {
    final w = AgentText.of(context);
    final controllers = [
      for (var i = 0; i < fields.length; i++)
        TextEditingController(text: initial?[i] ?? ''),
    ];
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < fields.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.ml),
                    child: TextField(
                      controller: controllers[i],
                      autofocus: i == 0,
                      minLines: multiline && i == fields.length - 1 && fields.length > 1 ? 4 : 1,
                      maxLines: multiline && i == fields.length - 1 && fields.length > 1 ? 10 : 2,
                      decoration: InputDecoration(labelText: fields[i]),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(w.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, [for (final c in controllers) c.text]),
            child: Text(confirm ?? w.save),
          ),
        ],
      ),
    );
  }
}

/// One note: read it, copy it, edit it or delete it.
class NoteScreen extends StatefulWidget {
  const NoteScreen({super.key, required this.store, required this.note});
  final AgentStore store;
  final NoteItem note;

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  bool _editing = false;
  late final _title = TextEditingController(text: widget.note.title);
  late final _body = TextEditingController(text: widget.note.content);

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = AgentText.of(context);
    final n = widget.note;
    return Scaffold(
      appBar: AppBar(
        title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const HeroIcon(HeroIcons.arrowLeft),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (_editing)
            IconButton(
              tooltip: w.save,
              icon: const HeroIcon(HeroIcons.check),
              onPressed: () {
                widget.store.saveNote(
                  id: n.id,
                  title: _title.text.trim().isEmpty ? n.title : _title.text.trim(),
                  content: _body.text,
                  agent: n.agent,
                );
                setState(() => _editing = false);
              },
            )
          else ...[
            IconButton(
              tooltip: w.copy,
              icon: const HeroIcon(HeroIcons.clipboardDocument),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: n.content));
                if (context.mounted) showSnack(context, w.copied);
              },
            ),
            IconButton(
              tooltip: w.edit,
              icon: const HeroIcon(HeroIcons.pencil),
              onPressed: () => setState(() => _editing = true),
            ),
            IconButton(
              tooltip: w.delete,
              icon: const HeroIcon(HeroIcons.trash),
              onPressed: () {
                widget.store.removeNote(n.id);
                Navigator.of(context).pop();
              },
            ),
          ],
        ],
      ),
      body: _editing
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _title,
                  decoration: InputDecoration(labelText: w.title),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _body,
                  minLines: 12,
                  maxLines: null,
                  decoration: InputDecoration(labelText: w.notes),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [MarkdownView(data: n.content)],
            ),
    );
  }
}

/// One background task: what it did, and its result.
class TaskScreen extends StatefulWidget {
  const TaskScreen({super.key, required this.store, required this.task});
  final AgentStore store;
  final TaskItem task;

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  @override
  void initState() {
    super.initState();
    widget.store.markSeen(widget.task);
  }

  @override
  Widget build(BuildContext context) {
    final w = AgentText.of(context);
    final s = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final t = widget.task;
        if (t.status == 'done') widget.store.markSeen(t);
        return Scaffold(
          appBar: AppBar(
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const HeroIcon(HeroIcons.arrowLeft),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            actions: [
              if (t.active)
                TextButton(
                  onPressed: () => widget.store.cancelTask(t),
                  child: Text(w.stopTask),
                ),
              if (t.result.isNotEmpty) ...[
                IconButton(
                  tooltip: w.copy,
                  icon: const HeroIcon(HeroIcons.clipboardDocument),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: t.result));
                    if (context.mounted) showSnack(context, w.copied);
                  },
                ),
                IconButton(
                  tooltip: w.saveAsNote,
                  icon: const HeroIcon(HeroIcons.documentText),
                  onPressed: () {
                    widget.store.saveNote(
                      title: t.title,
                      content: t.result,
                      agent: t.agent,
                    );
                    showSnack(context, w.savedAsNote);
                  },
                ),
              ],
              if (!t.active)
                IconButton(
                  tooltip: w.delete,
                  icon: const HeroIcon(HeroIcons.trash),
                  onPressed: () {
                    widget.store.removeTask(t.id);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: widget.store.pollTasks,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                Row(
                  children: [
                    AgentAvatar(agent: agentById(t.agent), size: 24),
                    const SizedBox(width: 8),
                    Text(
                      '${agentById(t.agent).nameFor(w.en)} · ${w.status(t.status)}',
                      style: tt.labelLarge,
                    ),
                    if (t.active) ...[
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: s.primary,
                        ),
                      ),
                    ],
                  ],
                ),
                if (t.goal.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    t.goal,
                    style: tt.bodyMedium?.copyWith(color: s.onSurfaceVariant),
                  ),
                ],
                if (t.steps.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(w.steps, style: tt.titleSmall),
                  const SizedBox(height: 4),
                  for (final step in t.steps)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          HeroIcon(
                            toolIcon(step.split('|').first),
                            size: 15,
                            color: s.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${w.tool(step.split('|').first, true)}: ${step.split('|').skip(1).join('|')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.labelMedium?.copyWith(
                                color: s.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (t.error.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(t.error, style: tt.bodyMedium?.copyWith(color: s.error)),
                ],
                if (t.result.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(w.result, style: tt.titleSmall),
                  const SizedBox(height: 8),
                  MarkdownView(data: t.result),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
