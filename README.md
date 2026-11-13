# Bangla AI server

The backend for the Bangla AI app and its admin dashboard. It keeps the
OmniRoute API key on the server, gives the app its settings, and passes
chats to OmniRoute so the key never ships inside the app.

Node 20+, one dependency (`pg`). Runs on Render's free plan.

The Bangla AI Android app (Flutter) is in [`app/`](app/). Build it with
`cd app && flutter pub get && flutter build apk --release --target-platform android-arm64`;
it talks to `https://bangla-ai-server-1a46.onrender.com` unless you pass
`--dart-define=BACKEND_URL=...`. Ready-made APKs are on the Releases page.

## Endpoints

| Method | Path | Who | What |
| --- | --- | --- | --- |
| GET | `/health` | anyone | `{"ok":true}`; fast, no database |
| GET | `/v1/config` | app | models, default model, voice, speed, pitch, on/off switch (no key) |
| POST | `/v1/chat` | app | OpenAI-style `{messages, model, stream}`; streams OmniRoute's reply |
| POST | `/admin/request-code` | none | `{email}`: emails a 6-digit code if it is `ADMIN_EMAIL` (same answer either way) |
| POST | `/admin/verify-code` | none | `{email, code}` -> `{token}` (valid 30 days). Codes last 10 minutes, work once, 5 wrong tries |
| GET | `/admin/config` | admin | full config; key shown only as `••••last4` |
| PUT | `/admin/config` | admin | change any field; an empty `apiKey` keeps the old key |
| POST | `/admin/test` | admin | sends one tiny message to OmniRoute with the stored or draft values |

The chat proxy only allows models from the admin's list (anything else uses
the default model) and puts the admin's system prompt before the app's own
lines (reply in Bangla, short spoken replies in calls).

## Deploy on Render (free)

1. Push this folder to a GitHub repo (this repo).
2. Create a free Postgres database on Neon (neon.tech, sign in with GitHub),
   open the project, click **Connect**, and copy the connection string. Change
   `sslmode=require&channel_binding=require` at the end to `sslmode=verify-full`.
3. In Render: **New > Blueprint**, pick the repo. Render reads `render.yaml`
   and creates `bangla-ai-server`, a free Node web service.
4. Render asks for the values marked `sync: false`:
   - `DATABASE_URL`: the Neon connection string from step 2.
   - `ADMIN_EMAIL`: the only email that can sign in to the admin app.
   - `RESEND_API_KEY`: a Resend key with sending access (emails the codes). On Resend's free plan without your own domain, it can only send to the Resend account's own email, so use that as `ADMIN_EMAIL`.
   - `OMNIROUTE_BASE_URL`, `OMNIROUTE_API_KEY`: optional starting values. You
     can leave them empty and set them in the admin app instead.
5. Click **Apply**. The first build takes a few minutes.
6. Open `https://<your-service>.onrender.com/health`. It should show
   `"ok":true` and `"storeOk":true`.
7. Put that address in the admin app at first launch, sign in with
   the 6-digit code emailed to `ADMIN_EMAIL`, and set the OmniRoute address, key, models and voice.

Without a Blueprint: New > Web Service from this repo, Free instance, build
command `npm install --omit=dev`, start command `node server.js`, health check
path `/health`, and the environment variables below.

### Environment variables

| Name | Needed | Meaning |
| --- | --- | --- |
| `ADMIN_EMAIL` | yes | the admin's email; sign-in codes go here |
| `RESEND_API_KEY` | yes | Resend key that sends the codes (Render's free plan blocks SMTP) |
| `MAIL_FROM` | no | sender, default `Bangla AI <onboarding@resend.dev>` |
| `DATABASE_URL` | yes on Render | Postgres connection string (Neon) |
| `CONFIG_TABLE` | no | table name, default `bangla_ai_config` |
| `OMNIROUTE_BASE_URL` | no | first value of the OmniRoute address, e.g. `https://host/v1` |
| `OMNIROUTE_API_KEY` | no | first value of the key |
| `MODELS` | no | comma list, default `auto,auto/fast` |
| `DEFAULT_MODEL`, `SYSTEM_PROMPT` | no | first values |
| `VOICE_NAME`, `VOICE_LOCALE`, `VOICE_SPEED`, `VOICE_PITCH` | no | first voice values (`bn-BD`, `1.0`, `1.0`) |
| `APP_ENABLED`, `DISABLED_MESSAGE` | no | on/off switch and the message users see when off |
| `TOKEN_SECRET` | no | signs admin tokens and code hashes; random per start if unset |
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
- **Why Neon and not Render's Postgres.** Render's free Postgres expires 30
  days after you create it (then a 14-day grace period before deletion), and a
  workspace can have only one free database. Neon's free plan does not expire
  (0.5 GB storage, 100 compute hours a month per project). Its database pauses
  when idle and wakes in about a second, which is fine for this server. Any
  Postgres works: to move, set `DATABASE_URL` to the new one and press Save once
  in the admin app so the config is written there.
- **If the database is unreachable,** the server still starts with the
  environment values (so `/health` and the app keep working), keeps retrying
  every 15 seconds, and the admin app shows that saving failed.

## Run locally

```
npm install
ADMIN_EMAIL=you@example.com RESEND_API_KEY=re_... node server.js        # stores config in data/config.json
npm test                                    # 9 tests with a fake OmniRoute
```
