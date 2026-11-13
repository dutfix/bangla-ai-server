// Voice providers for the Bangla AI server.
//
// The main app speaks in one of two ways:
//   - 'device': the phone's own speech engine (Google's Bangla voices). Free.
//   - a cloud provider below: the app sends a sentence to POST /v1/tts and
//     plays the audio the server gets back. The provider key stays here.
//
// To add a provider, add one entry to PROVIDERS: a label, the fields the
// admin fills in (the admin app draws its form from this list), and a synth()
// that returns { audio: Buffer, type: 'audio/mpeg' }. Nothing else changes.

'use strict';

const MP3 = 'audio/mpeg';

function pct(x) {
  const n = Math.round((x - 1) * 100);
  return `${n >= 0 ? '+' : ''}${n}%`;
}

function xmlEscape(s) {
  return String(s).replace(/[<>&'"]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', "'": '&apos;', '"': '&quot;' })[c]);
}

async function failIfBad(res, who) {
  if (res.ok) return;
  let detail = '';
  try {
    detail = (await res.text()).slice(0, 300);
  } catch {}
  if (res.status === 401 || res.status === 403) throw new Error(`${who} rejected the key (${res.status}).`);
  throw new Error(`${who} error ${res.status}${detail ? `: ${detail}` : ''}`);
}

async function audioOf(res) {
  return { audio: Buffer.from(await res.arrayBuffer()), type: MP3 };
}

const PROVIDERS = {
  azure: {
    label: 'Microsoft Azure Speech',
    note:
      'Microsoft neural voices, including Bangla. Create a Speech resource in the Azure portal ' +
      '(it has a free tier) and copy its key and region.',
    fields: [
      { key: 'region', label: 'Region', hint: 'eastus', required: true },
      { key: 'apiKey', label: 'Speech key', secret: true, required: true },
      {
        key: 'voice',
        label: 'Voice',
        hint: 'bn-BD-NabanitaNeural',
        required: true,
        suggestions: ['bn-BD-NabanitaNeural', 'bn-BD-PradeepNeural', 'bn-IN-TanishaaNeural', 'bn-IN-BashkarNeural'],
      },
    ],
    async synth(p, text, { speed = 1, pitch = 1, signal } = {}) {
      const region = String(p.region || '').trim().toLowerCase();
      if (!/^[a-z0-9-]{2,40}$/.test(region)) throw new Error('Azure region looks wrong (for example: eastus).');
      const voice = p.voice || 'bn-BD-NabanitaNeural';
      const lang = voice.split('-').slice(0, 2).join('-') || 'bn-BD';
      const ssml =
        `<speak version="1.0" xml:lang="${xmlEscape(lang)}"><voice name="${xmlEscape(voice)}">` +
        `<prosody rate="${pct(speed)}" pitch="${pct(pitch)}">${xmlEscape(text)}</prosody></voice></speak>`;
      const res = await fetch(`https://${region}.tts.speech.microsoft.com/cognitiveservices/v1`, {
        method: 'POST',
        headers: {
          'Ocp-Apim-Subscription-Key': p.apiKey,
          'Content-Type': 'application/ssml+xml',
          'X-Microsoft-OutputFormat': 'audio-24khz-48kbitrate-mono-mp3',
          'User-Agent': 'bangla-ai-server',
        },
        body: ssml,
        signal,
      });
      await failIfBad(res, 'Azure Speech');
      return audioOf(res);
    },
  },

  google: {
    label: 'Google Cloud Text-to-Speech',
    note: 'Google Cloud voices (Bangla voices are bn-IN). Needs a Google Cloud API key with Text-to-Speech enabled.',
    fields: [
      { key: 'apiKey', label: 'API key', secret: true, required: true },
      {
        key: 'voice',
        label: 'Voice',
        hint: 'bn-IN-Wavenet-A',
        required: true,
        suggestions: ['bn-IN-Wavenet-A', 'bn-IN-Wavenet-B', 'bn-IN-Standard-A', 'bn-IN-Standard-B'],
      },
    ],
    async synth(p, text, { speed = 1, pitch = 1, signal } = {}) {
      const voice = p.voice || 'bn-IN-Wavenet-A';
      const res = await fetch(
        `https://texttospeech.googleapis.com/v1/text:synthesize?key=${encodeURIComponent(p.apiKey)}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            input: { text },
            voice: { languageCode: voice.split('-').slice(0, 2).join('-'), name: voice },
            audioConfig: {
              audioEncoding: 'MP3',
              speakingRate: Math.min(Math.max(speed, 0.25), 4),
              pitch: Math.round((pitch - 1) * 20 * 10) / 10,
            },
          }),
          signal,
        },
      );
      await failIfBad(res, 'Google TTS');
      const j = await res.json();
      if (!j.audioContent) throw new Error('Google TTS sent no audio.');
      return { audio: Buffer.from(j.audioContent, 'base64'), type: MP3 };
    },
  },

  openai: {
    label: 'OpenAI-compatible',
    note:
      'Any service with an OpenAI-style /audio/speech endpoint: OpenAI itself, or a gateway or ' +
      'self-hosted server that offers it. Check that the voice speaks Bangla well.',
    fields: [
      { key: 'baseUrl', label: 'Base URL', hint: 'https://api.openai.com/v1', required: true, url: true },
      { key: 'apiKey', label: 'API key', secret: true },
      { key: 'model', label: 'Model', hint: 'gpt-4o-mini-tts', required: true },
      { key: 'voice', label: 'Voice', hint: 'alloy', required: true },
    ],
    async synth(p, text, { speed = 1, signal } = {}) {
      const base = String(p.baseUrl || 'https://api.openai.com/v1').replace(/\/+$/, '');
      const res = await fetch(`${base}/audio/speech`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(p.apiKey ? { Authorization: `Bearer ${p.apiKey}` } : {}),
        },
        body: JSON.stringify({
          model: p.model,
          voice: p.voice,
          input: text,
          response_format: 'mp3',
          speed: Math.min(Math.max(speed, 0.25), 4),
        }),
        signal,
      });
      await failIfBad(res, 'Voice service');
      return audioOf(res);
    },
  },

  elevenlabs: {
    label: 'ElevenLabs',
    note: 'ElevenLabs voices. Paste a voice ID from your ElevenLabs voice library and check it speaks Bangla well.',
    fields: [
      { key: 'apiKey', label: 'API key', secret: true, required: true },
      { key: 'voice', label: 'Voice ID', hint: 'from your voice library', required: true },
      { key: 'model', label: 'Model', hint: 'eleven_flash_v2_5', required: true },
    ],
    async synth(p, text, { signal } = {}) {
      const res = await fetch(
        `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(p.voice)}?output_format=mp3_44100_64`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'xi-api-key': p.apiKey, Accept: MP3 },
          body: JSON.stringify({ text, model_id: p.model || 'eleven_flash_v2_5' }),
          signal,
        },
      );
      await failIfBad(res, 'ElevenLabs');
      return audioOf(res);
    },
  },
};

/** What the admin app needs to draw the provider forms (no functions). */
function providerTypes() {
  return Object.entries(PROVIDERS).map(([type, p]) => ({
    type,
    label: p.label,
    note: p.note,
    fields: p.fields,
  }));
}

const FIELD_MAX = 500;

/**
 * Cleans the admin's list of providers. A missing or empty apiKey means
 * "keep the saved one" (merge() fills it in); clearApiKey removes it.
 */
function cleanProviders(list, bad) {
  if (!Array.isArray(list)) throw bad('voiceProviders must be a list.');
  if (list.length > 20) throw bad('Too many voice providers (20 at most).');
  const ids = new Set();
  return list.map((raw, i) => {
    if (!raw || typeof raw !== 'object') throw bad(`Voice provider ${i + 1} is not valid.`);
    const def = PROVIDERS[raw.type];
    if (!def) throw bad(`Unknown voice provider type: ${raw.type}`);
    let id = typeof raw.id === 'string' ? raw.id.trim() : '';
    if (!/^[a-z0-9-]{1,40}$/.test(id)) id = `${raw.type}-${Math.random().toString(36).slice(2, 8)}`;
    if (ids.has(id) || id === 'device') throw bad(`Two voice providers share the id ${id}.`);
    ids.add(id);
    const name = typeof raw.name === 'string' && raw.name.trim() ? raw.name.trim().slice(0, 60) : def.label;
    const out = { id, type: raw.type, name };
    for (const f of def.fields) {
      const v = raw[f.key];
      if (v === undefined || v === null) continue;
      if (typeof v !== 'string') throw bad(`${name}: ${f.label} must be text.`);
      if (v.length > FIELD_MAX) throw bad(`${name}: ${f.label} is too long.`);
      const t = v.trim();
      if (f.secret) {
        if (t) out[f.key] = t;
        continue;
      }
      if (f.url && t) {
        let u;
        try {
          u = new URL(t);
        } catch {
          throw bad(`${name}: ${f.label} is not a valid address.`);
        }
        if (!/^https?:$/.test(u.protocol)) throw bad(`${name}: ${f.label} must start with https://`);
        out[f.key] = t.replace(/\/+$/, '');
        continue;
      }
      out[f.key] = t;
    }
    if (raw.clearApiKey === true) out.clearApiKey = true;
    return out;
  });
}

/** Carries saved keys over to providers the admin edited without retyping them. */
function mergeProviders(saved, next) {
  const old = new Map((saved || []).map((p) => [p.id, p]));
  return next.map((p) => {
    const o = old.get(p.id);
    const out = { ...p };
    delete out.clearApiKey;
    if (p.clearApiKey) out.apiKey = '';
    else if (!out.apiKey && o && o.type === p.type && o.apiKey) out.apiKey = o.apiKey;
    return out;
  });
}

/** The admin's view: keys masked to their last four characters. */
function maskProviders(list) {
  return (list || []).map((p) => {
    const k = p.apiKey || '';
    const out = { ...p, apiKeySet: Boolean(k), apiKeyHint: k ? `••••${k.slice(-4)}` : '' };
    delete out.apiKey;
    return out;
  });
}

/** What is still missing before a provider can speak, or '' when ready. */
function missing(p) {
  const def = p && PROVIDERS[p.type];
  if (!def) return 'unknown provider';
  const need = def.fields.filter((f) => f.required && !String(p[f.key] || '').trim());
  return need.map((f) => f.label).join(', ');
}

async function synthesize(p, text, opts) {
  const def = PROVIDERS[p.type];
  if (!def) throw new Error('Unknown voice provider.');
  const gap = missing(p);
  if (gap) throw new Error(`${p.name || def.label} is missing: ${gap}.`);
  return def.synth(p, text, opts);
}

module.exports = { PROVIDERS, providerTypes, cleanProviders, mergeProviders, maskProviders, missing, synthesize };
