import 'dart:convert';
import 'dart:io';

import 'package:omni_voice_call/models/agent.dart';
import 'package:omni_voice_call/models/chat.dart';
import 'package:omni_voice_call/services/agent_store.dart';
import 'package:omni_voice_call/services/chat_controller.dart';
import 'package:omni_voice_call/services/chat_store.dart';
import 'package:omni_voice_call/services/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_test.dart' show FakeLlm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late SettingsStore settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('agents');
    settings = SettingsStore();
    await settings.load();
  });
  tearDown(() => dir.delete(recursive: true));

  test('four agents with distinct ids, names and suggestions', () {
    expect(agents.map((a) => a.id), ['mita', 'shongket', 'onnesha', 'rongon']);
    expect(agents.every((a) => a.suggestions.length == 3), isTrue);
    expect(agentById('nope').id, defaultAgentId);
  });

  test('chat sends the agent and its context, shows tools, applies '
      'actions', () async {
    final store = ChatStore(directory: () async => dir);
    await store.load();
    final ag = AgentStore();
    ag.memory.add(
      MemoryItem(id: 'm1', text: 'shared', agent: 'mita', shared: true),
    );
    ag.memory.add(MemoryItem(id: 'm2', text: 'mine', agent: 'shongket'));
    ag.memory.add(MemoryItem(id: 'm3', text: 'not mine', agent: 'rongon'));
    final llm = FakeLlm(settings)
      ..events = [
        {
          'type': 'tool',
          'phase': 'start',
          'id': 'c1',
          'name': 'web_search',
          'detail': 'flutter',
        },
        {
          'type': 'tool',
          'phase': 'done',
          'id': 'c1',
          'name': 'web_search',
          'ok': true,
        },
        {
          'type': 'action',
          'action': 'note_save',
          'id': 'n1',
          'title': 'Code',
          'content': 'print(1)',
          'agent': 'shongket',
        },
        {
          'type': 'action',
          'action': 'memory_add',
          'id': 'm9',
          'text': 'Uses Flutter',
          'shared': false,
          'agent': 'shongket',
        },
      ];
    final chat = ChatController(
      store: store,
      settings: settings,
      llm: llm,
      titleLlm: llm,
      agents: ag,
    );
    chat.newChatWith('shongket');
    expect(chat.agent.id, 'shongket');
    await chat.send('help');
    expect(llm.askedAgent.single, 'shongket');
    final ctx = llm.askedContext.single!;
    final mem = (ctx['memory'] as List).map((m) => (m as Map)['text']).toList();
    expect(mem, ['shared', 'mine']);
    expect(
      ctx['now'],
      matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:00[+-]\d\d:\d\d')),
    );
    final reply = chat.messages.last;
    expect(reply.tools.single.name, 'web_search');
    expect(reply.tools.single.done, isTrue);
    expect(reply.tools.single.ok, isTrue);
    expect(ag.notes.single.title, 'Code');
    expect(ag.memory.last.text, 'Uses Flutter');
    expect(chat.current!.agent, 'shongket');

    // The agent and the tool steps are saved with the chat.
    final back = Conversation.fromJson(
      jsonDecode(jsonEncode(chat.current!.toJson())) as Map<String, dynamic>,
    );
    expect(back.agent, 'shongket');
    expect(back.messages.last.tools.single.detail, 'flutter');
  });

  test('reminders ring once, routines move to their next time', () async {
    var now = DateTime(2026, 11, 13, 7, 59); // Friday
    final ag = AgentStore(
      clock: () => now,
      clientFactory: () => MockClient((_) async => http.Response('{}', 500)),
    );
    ag.apply({
      'action': 'reminder_add',
      'id': 'r1',
      'text': 'Water',
      'at': DateTime(2026, 11, 13, 8).toIso8601String(),
      'repeat': 'none',
      'agent': 'mita',
    });
    ag.apply({
      'action': 'reminder_add',
      'id': 'r2',
      'text': 'Office',
      'at': DateTime(2026, 11, 13, 8).toIso8601String(),
      'repeat': 'weekdays',
      'agent': 'mita',
    });
    await ag.tick();
    expect(ag.ringing, isEmpty);
    now = DateTime(2026, 11, 13, 8, 0, 20);
    await ag.tick();
    expect(ag.ringing.map((r) => r.reminder.text), ['Water', 'Office']);
    expect(ag.reminders.first.done, isTrue);
    // Friday and Saturday are the weekend: next work day is Sunday.
    expect(ag.reminders.last.at, DateTime(2026, 11, 15, 8));
    ag.ringing.clear();
    await ag.tick();
    expect(ag.ringing, isEmpty);
  });

  test('background tasks: started, followed until done', () async {
    final calls = <String>[];
    var polls = 0;
    final ag = AgentStore(
      clientFactory: () => MockClient((req) async {
        calls.add(req.url.path);
        if (req.url.path == '/v1/tasks') {
          final b = jsonDecode(req.body) as Map;
          expect(b['agent'], 'onnesha');
          expect(b['context'], isA<Map>());
          return http.Response(
            jsonEncode({
              'task': {'id': 't0123456789ab', 'token': 'tok', 'title': 'R'},
            }),
            200,
          );
        }
        polls++;
        final b = jsonDecode(req.body) as Map;
        expect((b['tasks'] as List).single, {
          'id': 't0123456789ab',
          'token': 'tok',
        });
        return http.Response(
          jsonEncode({
            'tasks': [
              {
                'id': 't0123456789ab',
                'status': polls == 1 ? 'running' : 'done',
                'steps': [
                  {'tool': 'web_search', 'detail': 'x'},
                ],
                'result': polls == 1 ? '' : '# Report',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final t = await ag.startTask(
      agent: 'onnesha',
      title: 'R',
      goal: 'Research',
    );
    expect(t.active, isTrue);
    await ag.pollTasks();
    expect(t.status, 'running');
    expect(t.steps.single, 'web_search|x');
    await ag.pollTasks();
    expect(t.status, 'done');
    expect(t.result, '# Report');
    expect(ag.justFinished.single, t);
    expect(ag.unseenTasks, 1);
    ag.markSeen(t);
    expect(ag.unseenTasks, 0);
  });

  test('agent data survives a restart', () async {
    final ag = AgentStore()..agentId = 'rongon';
    ag.addMemory('Likes poems', 'rongon');
    ag.saveSkill(title: 'Poem', text: '4 lines', agent: 'rongon');
    ag.saveNote(title: 'N', content: 'C', agent: 'rongon');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final again = AgentStore();
    await again.load();
    expect(again.agentId, 'rongon');
    expect(again.memory.single.text, 'Likes poems');
    expect(again.skills.single.title, 'Poem');
    expect(again.notes.single.content, 'C');
    final ctx = again.contextFor('rongon');
    expect((ctx['skills'] as List).length, 1);
    expect((again.contextFor('mita')['skills'] as List), isEmpty);
  });
}
