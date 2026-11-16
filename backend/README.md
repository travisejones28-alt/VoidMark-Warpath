# VoidMark Warpath analytics backend

A Cloudflare Worker with a D1 (SQLite) database. No runtime dependencies. On the free
Workers plan this costs nothing at VoidMark's scale (free tier: 100,000 requests/day,
5 GB of D1 storage). Each Warpath sends roughly one request a day.

## What it does

| Endpoint | Who | Purpose |
| --- | --- | --- |
| `POST /v1/events` | Warpath (only after the player opted in) | install / update / detected / daily check-in |
| `POST /v1/installations/delete` | Warpath (Privacy > Delete) | deletes everything for that installation id |
| `GET /v1/admin/summary?game=&repo=&range=7\|30\|90\|all` | Owner (bearer token) | all dashboard numbers |
| `DELETE /v1/admin/installations/<id>` | Owner (bearer token) | delete one installation |
| `GET /v1/health` | anyone | `{"ok":true}` |

* **Consent:** every ingest must say `consent: true`; Warpath only sends after the player says yes.
* **Dedup:** each event has a client-made id that is reused on retries; the database ignores repeats.
  Addon registrations are unique per installation + game + addon, so re-registering never double-counts.
* **Validation:** UUID v4 installation ids, the two games only, repo names starting with
  `VoidMark`/`VoidLink`, short version strings, max 50 events and 32 KB per request.
* **Rate limits:** Cloudflare's rate limiter (20 requests/minute per hashed IP, kept in memory,
  never stored), 30 requests/hour per installation, 600 requests/minute in total, and 20 wrong
  admin tokens per hour locks the admin API for that hour.
* **Retention:** a daily job deletes events/activity older than `RETENTION_DAYS` (395) and any
  installation not seen for that long.

### Privacy

Stored: random installation ids, Warpath version, game, addon repo, addon version, event type, day,
and (for addons that record it) the last in-game load/use time. **Not stored:** IP addresses,
user agents, names, characters, accounts, PC/Windows names, file paths. The IP is only used,
hashed with a daily salt, as the key for Cloudflare's in-memory rate limiter.

**What Cloudflare itself sees:** like any web host, Cloudflare processes the connecting IP to
deliver the request and keeps aggregate, non-exportable request analytics. This Worker turns off
Workers Logs (`[observability] enabled = false`) and uses no Logpush, so no per-request logs with
IPs or user agents are kept for this project. Don't enable Workers Logs, Logpush or `wrangler tail`
for long periods if you want to keep it that way.

## Deploy (one time, about 10 minutes)

You need a free Cloudflare account and Node.js. In this `backend` folder:

1. `npx wrangler@latest login` (opens the browser to authorize Wrangler).
2. `npx wrangler@latest d1 create voidmark-analytics`
   Copy the `database_id` it prints into `wrangler.toml` (replace `REPLACE_WITH_YOUR_D1_DATABASE_ID`).
   The id is not a secret.
3. `npm run db:migrate` (creates the tables in the remote database).
4. `npm run token` prints a new **TOKEN** and its **ADMIN_TOKEN_SHA256**. Then:
   * `npx wrangler@latest secret put ADMIN_TOKEN_SHA256` and paste the hash.
   * `npx wrangler@latest secret put RATE_SALT` and paste any long random text.
   * Keep the TOKEN somewhere private (password manager). Never commit it.
5. `npm run deploy`. It prints the address, e.g. `https://voidmark-analytics.<you>.workers.dev`.
6. Check it: open `<address>/v1/health` in a browser; it must show `{"ok":true}`.
7. In Warpath: Owner > **Analytics** > **Settings**. Paste the address and the TOKEN, Save.
   Saving publishes `analytics-endpoint.txt` to GitHub with your saved GitHub key, so every
   Warpath (3.5.0+) starts sending for players who opted in. Empty address = statistics off for all.

Rotating the admin token: run `npm run token` again, `secret put ADMIN_TOKEN_SHA256`, paste the new
TOKEN in Warpath's Analytics settings.

## Tests

```
npm test                                 # Worker tests (Node 22+, uses node:sqlite as a stand-in for D1)
node test/dev-server.mjs 8787            # then, from the repo root:
WARPATH_TEST_SERVER=http://127.0.0.1:8787 WARPATH_TEST_TOKEN=dev-admin-token-0123456789abcdefghijkl \
  pwsh -File tests/Run-Tests.ps1         # Warpath client tests incl. end-to-end against the Worker
```

The same end-to-end test was also run against `wrangler dev --local` (the real Workers runtime with a
local D1 database).
