# Bangla AI server

The backend for the Bangla AI app and its admin dashboard. It keeps the
OmniRoute API key on the server, gives the app its settings, and passes
chats to OmniRoute so the key never ships inside the app.

Node 20+, one dependency (`pg`). Runs on Render's free plan.

## Endpoints

| Method | Path | Who | What |
| --- | --- | --- | --- |
| GET | `/health` | anyone | `{"ok":true}`; fast, no database |
| GET | `/v1/config` | app | models, default model, voice, speed, pitch, on/off switch (no key) |
| POST | `/v1/chat` | app | OpenAI-style `{messages, model, stream}`; streams OmniRoute's reply |
| POST | `/admin/login` | admin | `{password}` -> `{token}` (valid 12 hours) |
| GET | `/admin/config` | admin | full config; key shown only as `••••last4` |
| PUT | `/admin/config` | admin | change any field; an empty `apiKey` keeps the old key |
| POST | `/admin/test` | admin | sends one tiny message to OmniRoute with the stored or draft values |

The chat proxy only allows models from the admin's list (anything else uses
the default model) and puts the admin's system prompt before the app's own
lines (reply in Bangla, short spoken replies in calls).

## Deploy on Render (free)

1. Push this folder to a GitHub repo (this repo).
2. In Render: **New > Blueprint**, pick the repo. Render reads `render.yaml`
   and creates:
   - `bangla-ai-server`, a free Node web service, and
   - `bangla-ai-db`, a free Postgres database, wired in as `DATABASE_URL`.
3. Render asks for the values marked `sync: false`:
   - `ADMIN_PASSWORD`: the password for the admin app. Use a long one.
   - `OMNIROUTE_BASE_URL`, `OMNIROUTE_API_KEY`: optional starting values. You
     can leave them empty and set them in the admin app instead.
4. Click **Apply**. The first build takes a few minutes.
5. Open `https://<your-service>.onrender.com/health`. It should show
   `"ok":true` and `"storeOk":true`.
6. Put that address in the admin app at first launch, sign in with
   `ADMIN_PASSWORD`, and set the OmniRoute address, key, models and voice.

Without a Blueprint: create the Postgres database first (New > Postgres,
Free), then New > Web Service from this repo with build command
`npm install --omit=dev`, start command `node server.js`, health check path
`/health`, and the environment variables below. Set `DATABASE_URL` to the
database's **Internal Database URL**.

### Environment variables

| Name | Needed | Meaning |
| --- | --- | --- |
| `ADMIN_PASSWORD` | yes | admin app password; changing it signs the admin out |
| `DATABASE_URL` | yes on Render | Postgres connection string |
| `OMNIROUTE_BASE_URL` | no | first value of the OmniRoute address, e.g. `https://host/v1` |
| `OMNIROUTE_API_KEY` | no | first value of the key |
| `MODELS` | no | comma list, default `auto,auto/fast` |
| `DEFAULT_MODEL`, `SYSTEM_PROMPT` | no | first values |
| `VOICE_NAME`, `VOICE_LOCALE`, `VOICE_SPEED`, `VOICE_PITCH` | no | first voice values (`bn-BD`, `1.0`, `1.0`) |
| `APP_ENABLED`, `DISABLED_MESSAGE` | no | on/off switch and the message users see when off |
| `TOKEN_SECRET` | no | signs admin tokens; derived from the password if unset |
| `APP_KEY` | no | if set, the app must send it as `X-App-Key` (light abuse filter) |

The environment values are only the starting point. After the first start the
config lives in the database, and the admin app changes it there.

## Free plan limits and what they mean

- **The web service sleeps.** A free Render web service spins down when it
  gets no traffic for a while and takes about a minute to wake on the next
  request. Both apps show a Bangla "server is waking up" message, wait up to
  90 seconds and retry, and the main app starts from its saved copy of the
  config. To keep it awake, have a free uptime monitor (for example
  UptimeRobot or cron-job.org) call `https://<your-service>.onrender.com/health`
  every 10 minutes. Free instance hours are limited per month, and one service
  that is always awake uses most of them.
- **The free Postgres database expires.** Render's free Postgres is meant for
  trying things out: it expires about a month after you create it, and is
  deleted after a short grace period unless you upgrade. Before then, either
  upgrade it to a paid plan, or move to a free Postgres that does not expire,
  such as Neon (neon.tech):
  1. Create a Neon project and copy its connection string
     (`postgresql://...neon.tech/...?sslmode=require`).
  2. In Render, set the web service's `DATABASE_URL` to that string and save.
  3. Open the admin app and press Save once, so the config is written to Neon.
  Neon's free databases pause when idle and wake in about a second, which is
  fine for this server.
- **If the database is unreachable,** the server still starts with the
  environment values (so `/health` and the app keep working), keeps retrying
  every 15 seconds, and the admin app shows that saving failed.

## Run locally

```
npm install
ADMIN_PASSWORD=secret node server.js        # stores config in data/config.json
npm test                                    # 9 tests with a fake OmniRoute
```
