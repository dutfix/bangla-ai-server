'use strict';

// Background tasks: an agent works on a goal on the server (searching and
// reading many pages) while the user does something else or closes the app.
// Each task has a random token that only the device that started it holds;
// the server keeps just its hash, so nobody else can read the result.
//
// Tasks are saved in Postgres (table bangla_ai_tasks) when DATABASE_URL is
// set, else in a JSON file. A task that was running when the server stopped
// is marked as interrupted on the next start.

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const env = process.env;
const TABLE = /^[a-z_][a-z0-9_]{0,62}$/.test(env.TASKS_TABLE || '') ? env.TASKS_TABLE : 'bangla_ai_tasks';
const KEEP_DAYS = 30;
const MAX_RUNNING = Number(env.TASKS_MAX_RUNNING || 3);
const PER_IP_HOUR = Number(env.TASKS_PER_IP_HOUR || 12);
const TASK_TIMEOUT_MS = Number(env.TASK_TIMEOUT_MS || 6 * 60 * 1000);

const sha = (s) => crypto.createHash('sha256').update(String(s)).digest('hex');

function safeEq(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

class PgTasks {
  constructor(url) {
    const { Pool } = require('pg');
    const local = /@(localhost|127\.0\.0\.1)[:/]/.test(url) || /\.internal[:/]|@dpg-[^.]+[:/]/.test(url);
    this.pool = new Pool({ connectionString: url, max: 2, ssl: local || /sslmode=disable/.test(url) ? false : { rejectUnauthorized: false } });
  }
  async init() {
    await this.pool.query(`CREATE TABLE IF NOT EXISTS ${TABLE} (id TEXT PRIMARY KEY, data JSONB NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT now())`);
    await this.pool.query(
      `UPDATE ${TABLE} SET data = data || '{"status":"failed","error":"interrupted"}'::jsonb, updated_at = now() WHERE data->>'status' IN ('queued','running')`,
    );
    await this.pool.query(`DELETE FROM ${TABLE} WHERE updated_at < now() - interval '${KEEP_DAYS} days'`);
  }
  async put(t) {
    await this.pool.query(
      `INSERT INTO ${TABLE} (id, data, updated_at) VALUES ($1, $2, now()) ON CONFLICT (id) DO UPDATE SET data = EXCLUDED.data, updated_at = now()`,
      [t.id, t],
    );
  }
  async get(id) {
    const r = await this.pool.query(`SELECT data FROM ${TABLE} WHERE id = $1`, [id]);
    return r.rows[0] ? r.rows[0].data : null;
  }
}

class FileTasks {
  constructor(file) {
    this.file = file;
    this.map = new Map();
  }
  async init() {
    try {
      for (const t of JSON.parse(fs.readFileSync(this.file, 'utf8'))) {
        if (t.status === 'queued' || t.status === 'running') Object.assign(t, { status: 'failed', error: 'interrupted' });
        this.map.set(t.id, t);
      }
    } catch {}
  }
  async put(t) {
    this.map.set(t.id, t);
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    fs.writeFileSync(this.file, JSON.stringify([...this.map.values()].slice(-500)));
  }
  async get(id) {
    return this.map.get(id) || null;
  }
}

/**
 * makeTasks({ run }) where run(task, { onStep, signal }) does the work and
 * resolves the result text.
 */
function makeTasks({ run }) {
  const store = env.DATABASE_URL
    ? new PgTasks(env.DATABASE_URL)
    : new FileTasks(env.TASKS_FILE || path.join(path.dirname(env.CONFIG_FILE || path.join(__dirname, 'data', 'config.json')), 'tasks.json'));
  let ready = null;
  const live = new Map(); // id -> task object while it runs (fresh steps)
  const controllers = new Map();
  const queue = [];
  const ipStarts = new Map();
  let running = 0;

  const init = () => (ready ||= store.init().catch((e) => {
    ready = null;
    console.error(`Tasks store unavailable: ${e.message}`);
    throw e;
  }));

  const save = (t) => store.put(t).catch((e) => console.error(`Could not save task ${t.id}: ${e.message}`));

  function pump() {
    while (running < MAX_RUNNING && queue.length) {
      const t = queue.shift();
      running += 1;
      execute(t).finally(() => {
        running -= 1;
        pump();
      });
    }
  }

  async function execute(t) {
    const ctl = new AbortController();
    controllers.set(t.id, ctl);
    const timer = setTimeout(() => ctl.abort(), TASK_TIMEOUT_MS);
    t.status = 'running';
    t.startedAt = new Date().toISOString();
    await save(t);
    let lastSave = Date.now();
    try {
      const result = await run(t, {
        signal: ctl.signal,
        onStep: (step) => {
          t.steps.push({ ...step, at: new Date().toISOString() });
          if (t.steps.length > 60) t.steps.splice(0, t.steps.length - 60);
          if (Date.now() - lastSave > 4000) {
            lastSave = Date.now();
            save(t);
          }
        },
      });
      if (t.status === 'cancelled') return;
      t.result = String(result || '').trim();
      t.status = t.result ? 'done' : 'failed';
      if (!t.result) t.error = 'The agent finished without a result.';
    } catch (e) {
      if (t.status !== 'cancelled') {
        t.status = 'failed';
        t.error = ctl.signal.aborted ? 'The task ran out of time.' : String((e && e.message) || e).slice(0, 400);
      }
    } finally {
      clearTimeout(timer);
      controllers.delete(t.id);
      t.finishedAt = new Date().toISOString();
      live.delete(t.id);
      await save(t);
    }
  }

  /** Starts a task. Resolves { id, token, title }. */
  async function start({ agent, title, goal, ctx, ip }) {
    await init();
    const now = Date.now();
    const recent = (ipStarts.get(ip) || []).filter((x) => now - x < 3600e3);
    if (recent.length >= PER_IP_HOUR) throw Object.assign(new Error('Too many background tasks in the last hour. Try again later.'), { status: 429 });
    if (queue.length > 30) throw Object.assign(new Error('The server is busy with other tasks. Try again in a few minutes.'), { status: 503 });
    recent.push(now);
    ipStarts.set(ip, recent);
    if (ipStarts.size > 5000) ipStarts.clear();
    const id = `t${crypto.randomBytes(6).toString('hex')}`;
    const token = crypto.randomBytes(24).toString('base64url');
    const t = {
      id,
      tokenHash: sha(token),
      agent,
      title: String(title || '').slice(0, 120),
      goal: String(goal || '').slice(0, 4000),
      ctx: ctx ? { name: ctx.name, now: ctx.now, memory: ctx.memory, skills: ctx.skills } : null,
      status: 'queued',
      steps: [],
      result: '',
      error: '',
      createdAt: new Date().toISOString(),
    };
    live.set(id, t);
    await save(t);
    queue.push(t);
    pump();
    return { id, token, title: t.title };
  }

  const view = (t) => ({
    id: t.id,
    agent: t.agent,
    title: t.title,
    goal: t.goal,
    status: t.status,
    steps: (t.steps || []).slice(-20),
    result: t.result || '',
    error: t.error || '',
    createdAt: t.createdAt,
    startedAt: t.startedAt,
    finishedAt: t.finishedAt,
  });

  async function find(id, token) {
    await init();
    const t = live.get(id) || (await store.get(id));
    if (!t || !token || !safeEq(t.tokenHash, sha(token))) return null;
    return t;
  }

  /** Status for a list of { id, token } the device holds. */
  async function status(items) {
    const out = [];
    for (const it of (Array.isArray(items) ? items : []).slice(0, 50)) {
      const id = String((it && it.id) || '');
      const t = /^t[0-9a-f]{12}$/.test(id) ? await find(id, String(it.token || '')) : null;
      out.push(t ? view(t) : { id, status: 'missing' });
    }
    return out;
  }

  async function cancel(id, token) {
    const t = await find(id, token);
    if (!t) return null;
    if (t.status === 'queued' || t.status === 'running') {
      t.status = 'cancelled';
      t.error = '';
      const qi = queue.indexOf(t);
      if (qi >= 0) queue.splice(qi, 1);
      const c = controllers.get(id);
      if (c) c.abort();
      t.finishedAt = new Date().toISOString();
      await save(t);
    }
    return view(t);
  }

  return { init, start, status, cancel, get running() { return running; }, get queued() { return queue.length; } };
}

module.exports = { makeTasks };
