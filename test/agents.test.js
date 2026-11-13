'use strict';

// The four agents: the tool loop, device actions, background tasks, and the
// guards (private addresses, the calculator, unknown agents, task tokens).

const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bangla-agents-'));
process.env.CONFIG_FILE = path.join(dir, 'config.json');
process.env.TOOLS_ALLOW_PRIVATE = '1';
process.env.OMNIROUTE_API_KEY = 'sk-agent-test';
process.env.MODELS = 'auto';
delete process.env.DATABASE_URL;

// A fake model. It looks at the last message and the tools it was given:
// the script below decides which tool it calls, then it answers in text.
const seen = [];
let script = [];
let taskScript = [];
const fake = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    const b = JSON.parse(body);
    seen.push(b);
    const isTask = /running as a background task/.test(b.messages[0].content);
    const step = (isTask ? taskScript : script).shift() || { text: 'ঠিক আছে।' };
    if (step.status) {
      res.writeHead(step.status);
      return res.end(step.body || '{}');
    }
    res.writeHead(200, { 'Content-Type': 'text/event-stream' });
    if (step.call) {
      const args = JSON.stringify(step.args);
      // Arguments arrive in two pieces, as real streams do.
      res.write(`data: ${JSON.stringify({ choices: [{ delta: { tool_calls: [{ index: 0, id: 'c1', type: 'function', function: { name: step.call, arguments: args.slice(0, 5) } }] } }] })}\n\n`);
      res.write(`data: ${JSON.stringify({ choices: [{ delta: { tool_calls: [{ index: 0, function: { arguments: args.slice(5) } }] }, finish_reason: 'tool_calls' }] })}\n\n`);
      return res.end('data: [DONE]\n\n');
    }
    for (const part of [step.text.slice(0, 3), step.text.slice(3)]) {
      res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: part } }] })}\n\n`);
    }
    res.end('data: [DONE]\n\n');
  });
});

// A fake web page for read_webpage.
const site = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end('<html><head><title>Test Page</title><script>evil()</script></head><body><nav>menu</nav><p>ঢাকা &amp; চট্টগ্রাম</p><p>Second line</p></body></html>');
});

let base;
let server;
test.before(async () => {
  await new Promise((r) => fake.listen(0, r));
  await new Promise((r) => site.listen(0, r));
  process.env.OMNIROUTE_BASE_URL = `http://127.0.0.1:${fake.address().port}/v1`;
  const { start } = require('../server.js');
  server = await start({ port: 0 });
  base = `http://127.0.0.1:${server.address().port}`;
});
test.after(() => {
  server.close();
  fake.close();
  site.close();
});

const post = (p, body) =>
  fetch(base + p, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

/** Sends a chat and reads the stream: text, events, errors. */
async function chat(body) {
  const r = await post('/v1/chat', { stream: true, ...body });
  assert.equal(r.status, 200, await r.clone().text());
  const raw = await r.text();
  let text = '';
  const events = [];
  const errors = [];
  for (const line of raw.split('\n')) {
    if (!line.startsWith('data: ') || line === 'data: [DONE]') continue;
    const j = JSON.parse(line.slice(6));
    if (j.bangla_event) events.push(j.bangla_event);
    else if (j.error) errors.push(j.error.message);
    else text += j.choices[0].delta.content || '';
  }
  return { text, events, errors, raw };
}

const ctx = {
  name: 'দারায়',
  now: '2026-11-13T18:30:00+06:00',
  memory: [{ id: 'mold1', text: 'প্রিয় রঙ সবুজ', shared: true }],
  notes: [{ id: 'nold1', title: 'Old', text: 'x' }],
  reminders: [],
  skills: [{ id: 'sold1', title: 'Daily plan', text: 'Ask for 3 priorities' }],
  tasks: [],
};

test('lists four agents without their prompts', async () => {
  const r = await (await fetch(`${base}/v1/agents`)).json();
  assert.equal(r.agents.length, 4);
  assert.deepEqual(r.agents.map((a) => a.id), ['mita', 'shongket', 'onnesha', 'rongon']);
  assert.ok(r.agents.every((a) => a.name && a.role && !('persona' in a)));
});

test('unknown agent is refused', async () => {
  const r = await post('/v1/chat', { agent: 'nope', messages: [{ role: 'user', content: 'hi' }] });
  assert.equal(r.status, 400);
});

test('plain reply streams, prompt has persona, memory, skills and tools', async () => {
  seen.length = 0;
  script = [{ text: 'হ্যালো দারায়!' }];
  const r = await chat({ agent: 'shongket', context: ctx, messages: [{ role: 'user', content: 'হাই' }] });
  assert.equal(r.text, 'হ্যালো দারায়!');
  const sys = seen[0].messages[0].content;
  assert.match(sys, /Shongket/);
  assert.match(sys, /software engineer/);
  assert.match(sys, /\[mold1\] প্রিয় রঙ সবুজ/);
  assert.match(sys, /Daily plan/);
  assert.match(sys, /2026-11-13T18:30:00\+06:00/);
  assert.match(sys, /never say you ran, tested/);
  const names = seen[0].tools.map((t) => t.function.name);
  for (const n of ['web_search', 'read_webpage', 'remember', 'save_note', 'set_reminder', 'save_skill', 'start_background_task']) {
    assert.ok(names.includes(n), n);
  }
});

test('server tool: calculate, result goes back to the model', async () => {
  seen.length = 0;
  script = [{ call: 'calculate', args: { expression: '২৫*(৩+৪)' } }, { text: '১৭৫।' }];
  const r = await chat({ agent: 'mita', context: ctx, messages: [{ role: 'user', content: '25*(3+4)?' }] });
  assert.equal(r.text, '১৭৫।');
  assert.deepEqual(r.events.map((e) => `${e.type}:${e.phase}`), ['tool:start', 'tool:done']);
  assert.equal(r.events[1].ok, true);
  const toolMsg = seen[1].messages.find((m) => m.role === 'tool');
  assert.equal(JSON.parse(toolMsg.content).result, 175);
  const asst = seen[1].messages.find((m) => m.tool_calls);
  assert.equal(asst.tool_calls[0].function.name, 'calculate');
});

test('server tool: read_webpage strips scripts and menus', async () => {
  seen.length = 0;
  script = [{ call: 'read_webpage', args: { url: `http://127.0.0.1:${site.address().port}/a` } }, { text: 'ok' }];
  await chat({ agent: 'onnesha', context: ctx, messages: [{ role: 'user', content: 'read' }] });
  const res = JSON.parse(seen[1].messages.find((m) => m.role === 'tool').content);
  assert.equal(res.title, 'Test Page');
  assert.match(res.text, /ঢাকা & চট্টগ্রাম/);
  assert.doesNotMatch(res.text, /evil|menu/);
});

test('device tools: remember, note, reminder, skill come back as actions', async () => {
  script = [{ call: 'remember', args: { fact: 'ঢাকায় থাকেন', share_with_all_agents: true } }, { text: 'মনে রাখলাম।' }];
  let r = await chat({ agent: 'mita', context: ctx, messages: [{ role: 'user', content: 'I live in Dhaka' }] });
  let a = r.events.find((e) => e.type === 'action');
  assert.equal(a.action, 'memory_add');
  assert.equal(a.text, 'ঢাকায় থাকেন');
  assert.equal(a.shared, true);
  assert.equal(a.agent, 'mita');

  script = [{ call: 'save_note', args: { title: 'Plan', content: '# Plan\n- a' } }, { text: 'ok' }];
  r = await chat({ agent: 'rongon', context: ctx, messages: [{ role: 'user', content: 'save' }] });
  a = r.events.find((e) => e.type === 'action');
  assert.equal(a.action, 'note_save');
  assert.equal(a.content, '# Plan\n- a');

  const at = new Date(Date.now() + 3600e3).toISOString().replace('Z', '+00:00');
  script = [{ call: 'set_reminder', args: { text: 'পানি খাও', at, repeat: 'daily', task: 'news' } }, { text: 'ok' }];
  r = await chat({ agent: 'mita', context: ctx, messages: [{ role: 'user', content: 'remind' }] });
  a = r.events.find((e) => e.type === 'action');
  assert.equal(a.action, 'reminder_add');
  assert.equal(a.repeat, 'daily');
  assert.equal(a.task, 'news');

  script = [{ call: 'save_skill', args: { title: 'Poem', instructions: 'Always 4 lines' } }, { text: 'ok' }];
  r = await chat({ agent: 'rongon', context: ctx, messages: [{ role: 'user', content: 'learn' }] });
  assert.equal(r.events.find((e) => e.type === 'action').action, 'skill_save');
});

test('device tools refuse bad input and never claim success', async () => {
  seen.length = 0;
  script = [{ call: 'remember', args: { fact: 'my password is hunter2' } }, { text: 'x' }];
  let r = await chat({ agent: 'mita', context: ctx, messages: [{ role: 'user', content: 'x' }] });
  assert.equal(r.events.some((e) => e.type === 'action'), false);
  assert.match(JSON.parse(seen[1].messages.find((m) => m.role === 'tool').content).error, /password/);

  script = [{ call: 'set_reminder', args: { text: 'x', at: '2020-01-01T08:00:00+06:00' } }, { text: 'x' }];
  r = await chat({ agent: 'mita', context: ctx, messages: [{ role: 'user', content: 'x' }] });
  assert.equal(r.events.some((e) => e.type === 'action'), false);
  assert.equal(r.events.find((e) => e.phase === 'done').ok, false);

  script = [{ call: 'forget_memory', args: { memory_id: 'not-mine' } }, { text: 'x' }];
  r = await chat({ agent: 'mita', context: ctx, messages: [{ role: 'user', content: 'x' }] });
  assert.equal(r.events.some((e) => e.type === 'action'), false);

  script = [{ call: 'run_shell', args: { cmd: 'ls' } }, { text: 'x' }];
  r = await chat({ agent: 'shongket', context: ctx, messages: [{ role: 'user', content: 'x' }] });
  assert.equal(r.events.find((e) => e.phase === 'done').ok, false);
});

test('private addresses are blocked when the guard is on', async () => {
  const tools = require('../tools.js');
  for (const ip of ['127.0.0.1', '10.1.2.3', '169.254.169.254', '192.168.1.1', '172.20.0.1', '::1', '::ffff:127.0.0.1', 'fd00::1']) {
    assert.equal(tools.isPrivateIp(ip), true, ip);
  }
  assert.equal(tools.isPrivateIp('8.8.8.8'), false);
  assert.throws(() => tools.calculate({ expression: 'process.exit(1)' }));
  assert.equal(tools.calculate({ expression: '2^10 + sqrt(16)' }).result, 1028);
});

test('a model without tool support still answers', async () => {
  script = [{ status: 400, body: '{"error":{"message":"tools are not supported by this model"}}' }, { text: 'উত্তর' }];
  seen.length = 0;
  const r = await chat({ agent: 'mita', context: ctx, messages: [{ role: 'user', content: 'x' }] });
  assert.equal(r.text, 'উত্তর');
  assert.equal(seen[1].tools, undefined);
});

test('background task: started from chat, runs, and only its token reads it', async () => {
  script = [
    { call: 'start_background_task', args: { title: 'গবেষণা', goal: 'Compare two phones' } },
    { text: 'শুরু করেছি।' },
  ];
  // The task itself: one tool round, then the report.
  taskScript = [{ call: 'calculate', args: { expression: '1+1' } }, { text: '# Report\nDone.' }];
  const r = await chat({ agent: 'onnesha', context: ctx, messages: [{ role: 'user', content: 'research' }] });
  const a = r.events.find((e) => e.type === 'action');
  assert.equal(a.action, 'task_started');
  assert.ok(a.id && a.token);
  let t;
  for (let i = 0; i < 50; i++) {
    const s = await (await post('/v1/tasks/status', { tasks: [{ id: a.id, token: a.token }] })).json();
    t = s.tasks[0];
    if (t.status === 'done' || t.status === 'failed') break;
    await new Promise((x) => setTimeout(x, 50));
  }
  assert.equal(t.status, 'done', JSON.stringify(t));
  assert.equal(t.result, '# Report\nDone.');
  assert.equal(t.steps[0].tool, 'calculate');
  const wrong = await (await post('/v1/tasks/status', { tasks: [{ id: a.id, token: 'nope' }] })).json();
  assert.equal(wrong.tasks[0].status, 'missing');
  assert.equal(wrong.tasks[0].result, undefined);
  const cancel = await post(`/v1/tasks/${a.id}/cancel`, { token: 'nope' });
  assert.equal(cancel.status, 404);
});

test('background task started directly, then cancelled', async () => {
  script = [{ status: 200, body: '' }];
  // A slow model: hold the task in "running" by never finishing quickly.
  script = [];
  const r = await post('/v1/tasks', { agent: 'mita', title: 'Brief', goal: 'Morning brief', context: ctx });
  assert.equal(r.status, 200);
  const { task } = await r.json();
  assert.match(task.id, /^t[0-9a-f]{12}$/);
  const c = await (await post(`/v1/tasks/${task.id}/cancel`, { token: task.token })).json();
  assert.ok(['cancelled', 'done'].includes(c.task.status));
});
