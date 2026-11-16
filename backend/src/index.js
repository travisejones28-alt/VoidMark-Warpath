// VoidMark Warpath analytics: Cloudflare Worker + D1.
//
// Privacy rules enforced here:
//  * Only anonymous installation ids (random UUIDs), addon repo names, versions, game type,
//    event types, Warpath version and day-level times are stored.
//  * Raw IP addresses and user-agent strings are never written to D1. The IP is only used,
//    hashed with a daily salt, as a key for Cloudflare's in-memory rate limiter.
//  * Every ingest request must carry consent:true (the client only sends after opt-in).
//  * Admin queries need a bearer token whose SHA-256 is stored as a Worker secret.

export const GAMES = new Set(['WoW Forever', 'WoW Classic Era']);
export const TYPES = new Set(['install', 'update', 'detected', 'checkin']);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const EVENT_ID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const REPO_RE = /^(VoidMark|VoidLink)[A-Za-z0-9._-]{0,60}$/;
const VERSION_RE = /^[0-9A-Za-z][0-9A-Za-z.+_-]{0,39}$/;
const MAX_BODY = 32 * 1024;
const MAX_EVENTS = 50;
const MAX_ADDONS = 40;
const DAY_MS = 86400000;

// Limits (per hour unless noted). Generous for real users, tight for floods.
export const LIMITS = {
  perInstallPerHour: 30,
  globalPerMinute: 600,
  adminFailuresPerHour: 20,
  deletesPerInstallPerHour: 5,
};

export default {
  async fetch(request, env, ctx) {
    try {
      return await handle(request, env, new Date());
    } catch (err) {
      // Never echo internals or request data back.
      return json({ ok: false, error: 'server_error' }, 500);
    }
  },
  async scheduled(event, env, ctx) {
    ctx.waitUntil(applyRetention(env, new Date()));
  },
};

export async function handle(request, env, now) {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, '') || '/';
  if (request.method === 'GET' && path === '/v1/health') return json({ ok: true });

  if (path === '/v1/events') {
    if (request.method !== 'POST') return json({ ok: false, error: 'method' }, 405);
    return ingest(request, env, now);
  }
  if (path === '/v1/installations/delete' && request.method === 'POST') {
    return deleteOwn(request, env, now);
  }
  if (path.startsWith('/v1/admin/')) {
    const auth = await checkAdmin(request, env, now);
    if (auth) return auth;
    if (request.method === 'GET' && path === '/v1/admin/summary') {
      return json(await summary(env, now, url.searchParams));
    }
    const m = path.match(/^\/v1\/admin\/installations\/([0-9a-f-]{36})$/);
    if (m && request.method === 'DELETE') {
      if (!UUID_RE.test(m[1])) return json({ ok: false, error: 'invalid_id' }, 400);
      await deleteInstall(env, m[1]);
      return json({ ok: true, deleted: true });
    }
    return json({ ok: false, error: 'not_found' }, 404);
  }
  return json({ ok: false, error: 'not_found' }, 404);
}

// ---------------------------------------------------------------- helpers

function json(body, status = 200, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...extra },
  });
}

export function isoDay(d) {
  return new Date(d).toISOString().slice(0, 10);
}
function addDays(now, days) {
  return isoDay(now.getTime() + days * DAY_MS);
}

async function sha256Hex(text) {
  const data = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function timingSafeEqualHex(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function readJson(request) {
  const len = Number(request.headers.get('content-length') || '0');
  if (len > MAX_BODY) return { error: 'too_large' };
  const text = await request.text();
  if (text.length > MAX_BODY) return { error: 'too_large' };
  try {
    const body = JSON.parse(text);
    if (!body || typeof body !== 'object' || Array.isArray(body)) return { error: 'invalid_json' };
    return { body };
  } catch {
    return { error: 'invalid_json' };
  }
}

// Count one hit in a D1 bucket and return the new count.
async function bump(env, bucket, windowStart) {
  const row = await env.DB.prepare(
    'INSERT INTO rate_limits (bucket, window_start, count) VALUES (?, ?, 1) ' +
      'ON CONFLICT(bucket) DO UPDATE SET count = count + 1 RETURNING count'
  )
    .bind(bucket, windowStart)
    .first();
  return row ? Number(row.count) : 1;
}

// Cloudflare's rate limiting binding, keyed by a hashed IP that is never stored.
async function ipLimited(request, env, now, scope) {
  if (!env.INGEST_LIMITER || typeof env.INGEST_LIMITER.limit !== 'function') return false;
  const ip = request.headers.get('cf-connecting-ip') || '';
  if (!ip) return false;
  const key = await sha256Hex(scope + '|' + ip + '|' + isoDay(now) + '|' + (env.RATE_SALT || ''));
  const { success } = await env.INGEST_LIMITER.limit({ key });
  return !success;
}

async function globalLimited(env, now) {
  const minute = Math.floor(now.getTime() / 60000);
  return (await bump(env, 'g:' + minute, minute * 60)) > LIMITS.globalPerMinute;
}

function clampDay(ts, now) {
  const t = Date.parse(ts);
  if (!Number.isFinite(t)) return isoDay(now);
  const min = now.getTime() - 45 * DAY_MS;
  return isoDay(Math.min(now.getTime(), Math.max(min, t)));
}

function cleanVersion(v) {
  if (v === undefined || v === null || v === '') return null;
  const s = String(v).trim();
  return VERSION_RE.test(s) ? s : undefined; // undefined = invalid
}

function cleanTime(v, now) {
  // In-game timestamps: unix seconds from WoW's time(). Must be plausible.
  if (v === undefined || v === null) return null;
  const n = Number(v);
  if (!Number.isFinite(n) || n < 1500000000) return null;
  const ms = Math.min(n * 1000, now.getTime() + DAY_MS);
  return new Date(ms).toISOString().slice(0, 19) + 'Z';
}

// ---------------------------------------------------------------- ingest

export function validateEvent(e, now) {
  if (!e || typeof e !== 'object') return null;
  if (typeof e.id !== 'string' || !EVENT_ID_RE.test(e.id)) return null;
  if (!TYPES.has(e.type)) return null;
  const out = { id: e.id, type: e.type, day: clampDay(e.ts, now) };
  if (e.type === 'checkin') {
    if (!Array.isArray(e.addons) || e.addons.length > MAX_ADDONS) return null;
    out.addons = [];
    const seen = new Set();
    for (const a of e.addons) {
      if (!a || !GAMES.has(a.game) || typeof a.repo !== 'string' || !REPO_RE.test(a.repo)) return null;
      const version = cleanVersion(a.version);
      if (version === undefined) return null;
      const key = a.game + '|' + a.repo;
      if (seen.has(key)) continue;
      seen.add(key);
      const u = a.usage && typeof a.usage === 'object' ? a.usage : {};
      out.addons.push({
        game: a.game,
        repo: a.repo,
        version,
        lastInit: cleanTime(u.init, now),
        lastActive: cleanTime(u.active, now),
      });
    }
    return out;
  }
  if (!GAMES.has(e.game) || typeof e.repo !== 'string' || !REPO_RE.test(e.repo)) return null;
  const version = cleanVersion(e.version);
  if (version === undefined) return null;
  out.game = e.game;
  out.repo = e.repo;
  out.version = version;
  return out;
}

async function ingest(request, env, now) {
  if (await ipLimited(request, env, now, 'ingest')) return json({ ok: false, error: 'rate_limited' }, 429, { 'retry-after': '60' });
  const { body, error } = await readJson(request);
  if (error) return json({ ok: false, error }, error === 'too_large' ? 413 : 400);
  if (body.consent !== true) return json({ ok: false, error: 'consent_required' }, 400);
  const installId = String(body.installId || '').toLowerCase();
  if (!UUID_RE.test(installId)) return json({ ok: false, error: 'invalid_install_id' }, 400);
  const appVersion = cleanVersion(body.appVersion);
  if (appVersion === undefined) return json({ ok: false, error: 'invalid_app_version' }, 400);
  if (!Array.isArray(body.events) || body.events.length === 0 || body.events.length > MAX_EVENTS) {
    return json({ ok: false, error: 'invalid_events' }, 400);
  }
  if (await globalLimited(env, now)) return json({ ok: false, error: 'busy' }, 429, { 'retry-after': '60' });
  const hour = Math.floor(now.getTime() / 3600000);
  if ((await bump(env, 'i:' + installId + ':' + hour, hour * 3600)) > LIMITS.perInstallPerHour) {
    return json({ ok: false, error: 'rate_limited' }, 429, { 'retry-after': '3600' });
  }

  const accepted = [];
  const rejected = [];
  const today = isoDay(now);
  await upsertInstall(env, installId, today, appVersion);
  for (const raw of body.events) {
    const e = validateEvent(raw, now);
    if (!e) {
      // Malformed events are dropped for good: retrying them can never succeed.
      if (raw && typeof raw.id === 'string' && raw.id.length <= 40) rejected.push(raw.id);
      continue;
    }
    await applyEvent(env, installId, appVersion, e, now);
    accepted.push(e.id);
  }
  return json({ ok: true, accepted, rejected });
}

async function upsertInstall(env, installId, day, appVersion) {
  await env.DB.prepare(
    'INSERT INTO installs (install_id, first_seen, last_seen, app_version) VALUES (?, ?, ?, ?) ' +
      'ON CONFLICT(install_id) DO UPDATE SET last_seen = MAX(last_seen, excluded.last_seen), ' +
      'app_version = COALESCE(excluded.app_version, app_version)'
  )
    .bind(installId, day, day, appVersion)
    .run();
}

async function applyEvent(env, installId, appVersion, e, now) {
  const db = env.DB;
  const received = now.toISOString();
  // Dedup first: a retried event id changes nothing.
  const ins = await db
    .prepare(
      'INSERT OR IGNORE INTO events (event_id, install_id, type, game, repo, version, app_version, day, received_at) ' +
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
    )
    .bind(e.id, installId, e.type, e.game || null, e.repo || null, e.version || null, appVersion, e.day, received)
    .run();
  if (!ins.meta || ins.meta.changes === 0) return;

  const stmts = [
    db
      .prepare('INSERT OR IGNORE INTO daily_activity (day, install_id, game, repo, version) VALUES (?, ?, \'\', \'\', ?)')
      .bind(e.day, installId, appVersion),
  ];
  const addons =
    e.type === 'checkin'
      ? e.addons
      : [{ game: e.game, repo: e.repo, version: e.version, lastInit: null, lastActive: null }];
  const kind = e.type === 'install' ? 'install' : 'detected';
  for (const a of addons) {
    stmts.push(
      db
        .prepare(
          'INSERT INTO addon_installs (install_id, game, repo, first_kind, first_seen, last_seen, version, last_init, last_active) ' +
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(install_id, game, repo) DO UPDATE SET ' +
            'version = CASE WHEN excluded.last_seen >= last_seen THEN COALESCE(excluded.version, version) ELSE version END, ' +
            'last_seen = MAX(last_seen, excluded.last_seen), ' +
            'first_seen = MIN(first_seen, excluded.first_seen), ' +
            'last_init = CASE WHEN excluded.last_init IS NULL THEN last_init WHEN last_init IS NULL THEN excluded.last_init ELSE MAX(last_init, excluded.last_init) END, ' +
            'last_active = CASE WHEN excluded.last_active IS NULL THEN last_active WHEN last_active IS NULL THEN excluded.last_active ELSE MAX(last_active, excluded.last_active) END'
        )
        .bind(installId, a.game, a.repo, kind, e.day, e.day, a.version, a.lastInit, a.lastActive)
    );
    stmts.push(
      db
        .prepare(
          'INSERT INTO daily_activity (day, install_id, game, repo, version) VALUES (?, ?, ?, ?, ?) ' +
            'ON CONFLICT(day, install_id, game, repo) DO UPDATE SET version = COALESCE(excluded.version, version)'
        )
        .bind(e.day, installId, a.game, a.repo, a.version)
    );
  }
  await db.batch(stmts);
}

// ---------------------------------------------------------------- deletion

async function deleteOwn(request, env, now) {
  if (await ipLimited(request, env, now, 'delete')) return json({ ok: false, error: 'rate_limited' }, 429);
  const { body, error } = await readJson(request);
  if (error) return json({ ok: false, error }, 400);
  const installId = String(body.installId || '').toLowerCase();
  if (!UUID_RE.test(installId)) return json({ ok: false, error: 'invalid_install_id' }, 400);
  const hour = Math.floor(now.getTime() / 3600000);
  if ((await bump(env, 'd:' + installId + ':' + hour, hour * 3600)) > LIMITS.deletesPerInstallPerHour) {
    return json({ ok: false, error: 'rate_limited' }, 429);
  }
  await deleteInstall(env, installId);
  // Same answer whether or not anything existed.
  return json({ ok: true, deleted: true });
}

export async function deleteInstall(env, installId) {
  const db = env.DB;
  await db.batch([
    db.prepare('DELETE FROM events WHERE install_id = ?').bind(installId),
    db.prepare('DELETE FROM daily_activity WHERE install_id = ?').bind(installId),
    db.prepare('DELETE FROM addon_installs WHERE install_id = ?').bind(installId),
    db.prepare('DELETE FROM installs WHERE install_id = ?').bind(installId),
    db.prepare("DELETE FROM rate_limits WHERE bucket LIKE ?").bind('i:' + installId + ':%'),
  ]);
}

// ---------------------------------------------------------------- admin

async function checkAdmin(request, env, now) {
  if (!env.ADMIN_TOKEN_SHA256 || !/^[0-9a-f]{64}$/.test(env.ADMIN_TOKEN_SHA256)) {
    return json({ ok: false, error: 'admin_not_configured' }, 503);
  }
  if (await ipLimited(request, env, now, 'admin')) return json({ ok: false, error: 'rate_limited' }, 429);
  const hour = Math.floor(now.getTime() / 3600000);
  const failBucket = 'af:' + hour;
  const prior = await env.DB.prepare('SELECT count FROM rate_limits WHERE bucket = ?').bind(failBucket).first();
  if (prior && Number(prior.count) >= LIMITS.adminFailuresPerHour) {
    return json({ ok: false, error: 'locked' }, 429, { 'retry-after': '3600' });
  }
  const header = request.headers.get('authorization') || '';
  const m = header.match(/^Bearer ([A-Za-z0-9_-]{32,200})$/);
  const ok = m ? timingSafeEqualHex(await sha256Hex(m[1]), env.ADMIN_TOKEN_SHA256) : false;
  if (!ok) {
    await bump(env, failBucket, hour * 3600);
    return json({ ok: false, error: 'unauthorized' }, 401, { 'www-authenticate': 'Bearer' });
  }
  return null;
}

const RANGES = { '7': 7, '30': 30, '90': 90, all: 0 };

export async function summary(env, now, params) {
  const db = env.DB;
  const game = GAMES.has(params.get('game')) ? params.get('game') : null;
  const repo = REPO_RE.test(params.get('repo') || '') ? params.get('repo') : null;
  const rangeKey = Object.prototype.hasOwnProperty.call(RANGES, params.get('range')) ? params.get('range') : '30';
  const today = isoDay(now);
  const from = RANGES[rangeKey] ? addDays(now, -(RANGES[rangeKey] - 1)) : '2000-01-01';
  const d7 = addDays(now, -6);
  const d30 = addDays(now, -29);
  const t7 = new Date(now.getTime() - 7 * DAY_MS).toISOString().slice(0, 19) + 'Z';
  const t30 = new Date(now.getTime() - 30 * DAY_MS).toISOString().slice(0, 19) + 'Z';

  const f = [];
  const fa = [];
  if (game) { f.push('game = ?'); fa.push(game); }
  if (repo) { f.push('repo = ?'); fa.push(repo); }
  const filtered = f.length > 0;
  const W = filtered ? ' AND ' + f.join(' AND ') : '';

  const one = async (sql, ...args) => {
    const r = await db.prepare(sql).bind(...args).first();
    return r ? Number(Object.values(r)[0]) || 0 : 0;
  };
  const all = async (sql, ...args) => (await db.prepare(sql).bind(...args).all()).results || [];

  const totals = {
    warpathInstalls: filtered
      ? await one('SELECT COUNT(DISTINCT install_id) FROM addon_installs WHERE 1=1' + W, ...fa)
      : await one('SELECT COUNT(*) FROM installs'),
    addonInstalls: await one('SELECT COUNT(*) FROM addon_installs WHERE 1=1' + W, ...fa),
    active7: filtered
      ? await one("SELECT COUNT(DISTINCT install_id) FROM daily_activity WHERE repo <> '' AND day >= ?" + W, d7, ...fa)
      : await one("SELECT COUNT(DISTINCT install_id) FROM daily_activity WHERE repo = '' AND day >= ?", d7),
    active30: filtered
      ? await one("SELECT COUNT(DISTINCT install_id) FROM daily_activity WHERE repo <> '' AND day >= ?" + W, d30, ...fa)
      : await one("SELECT COUNT(DISTINCT install_id) FROM daily_activity WHERE repo = '' AND day >= ?", d30),
    newWarpathWeek: await one('SELECT COUNT(*) FROM installs WHERE first_seen >= ?', d7),
    newWarpathMonth: await one('SELECT COUNT(*) FROM installs WHERE first_seen >= ?', d30),
    newAddonInstallsWeek: await one("SELECT COUNT(*) FROM addon_installs WHERE first_kind = 'install' AND first_seen >= ?" + W, d7, ...fa),
    newAddonInstallsMonth: await one("SELECT COUNT(*) FROM addon_installs WHERE first_kind = 'install' AND first_seen >= ?" + W, d30, ...fa),
    detectedExisting: await one("SELECT COUNT(*) FROM addon_installs WHERE first_kind = 'detected'" + W, ...fa),
    updatesInRange: await one("SELECT COUNT(*) FROM events WHERE type = 'update' AND day >= ?" + W, from, ...fa),
    updatesAllTime: await one("SELECT COUNT(*) FROM events WHERE type = 'update'" + W, ...fa),
    inGameActive30: await one('SELECT COUNT(DISTINCT install_id) FROM addon_installs WHERE last_active >= ?' + W, t30, ...fa),
  };

  const popular = await all(
    'SELECT game, repo, COUNT(*) AS installs FROM addon_installs WHERE 1=1' +
      (game ? ' AND game = ?' : '') +
      ' GROUP BY game, repo ORDER BY installs DESC, repo LIMIT 1',
    ...(game ? [game] : [])
  );
  totals.mostPopular = popular[0] ? { game: popular[0].game, repo: popular[0].repo, installs: Number(popular[0].installs) } : null;

  const base = await all(
    'SELECT game, repo, COUNT(*) AS total, ' +
      "SUM(CASE WHEN first_kind = 'install' THEN 1 ELSE 0 END) AS viaWarpath, " +
      "SUM(CASE WHEN first_kind = 'detected' THEN 1 ELSE 0 END) AS detected, " +
      'SUM(CASE WHEN last_init >= ? THEN 1 ELSE 0 END) AS inGameLoaded30, ' +
      'SUM(CASE WHEN last_active >= ? THEN 1 ELSE 0 END) AS inGameUsed7, ' +
      'SUM(CASE WHEN last_active >= ? THEN 1 ELSE 0 END) AS inGameUsed30, ' +
      'SUM(CASE WHEN last_init IS NOT NULL THEN 1 ELSE 0 END) AS reportsUsage ' +
      'FROM addon_installs WHERE 1=1' + W + ' GROUP BY game, repo',
    t30, t7, t30, ...fa
  );
  const act = await all(
    'SELECT game, repo, COUNT(DISTINCT CASE WHEN day >= ? THEN install_id END) AS active7, ' +
      "COUNT(DISTINCT install_id) AS active30 FROM daily_activity WHERE repo <> '' AND day >= ?" + W +
      ' GROUP BY game, repo',
    d7, d30, ...fa
  );
  const upd = await all(
    "SELECT game, repo, COUNT(*) AS updates FROM events WHERE type = 'update'" + W + ' GROUP BY game, repo',
    ...fa
  );
  const key = (r) => r.game + '|' + r.repo;
  const actMap = new Map(act.map((r) => [key(r), r]));
  const updMap = new Map(upd.map((r) => [key(r), r]));
  const versions = await all(
    'SELECT game, repo, version, COUNT(*) AS installs, SUM(CASE WHEN last_seen >= ? THEN 1 ELSE 0 END) AS active30 ' +
      'FROM addon_installs WHERE 1=1' + W + ' GROUP BY game, repo, version ORDER BY installs DESC',
    d30, ...fa
  );
  const addons = base.map((r) => {
    const a = actMap.get(key(r)) || {};
    return {
      game: r.game,
      repo: r.repo,
      total: Number(r.total) || 0,
      viaWarpath: Number(r.viaWarpath) || 0,
      detected: Number(r.detected) || 0,
      active7: Number(a.active7) || 0,
      active30: Number(a.active30) || 0,
      updates: Number((updMap.get(key(r)) || {}).updates) || 0,
      inGameLoaded30: Number(r.inGameLoaded30) || 0,
      inGameUsed7: Number(r.inGameUsed7) || 0,
      inGameUsed30: Number(r.inGameUsed30) || 0,
      reportsUsage: Number(r.reportsUsage) || 0,
      versions: versions
        .filter((v) => key(v) === key(r))
        .map((v) => ({ version: v.version || '', installs: Number(v.installs) || 0, active30: Number(v.active30) || 0 })),
    };
  });

  const seriesQ = async (sql, ...args) => {
    const rows = await all(sql, ...args);
    return rows.map((r) => ({ day: r.day, count: Number(r.count) || 0 }));
  };
  const series = {
    newInstalls: await seriesQ(
      "SELECT first_seen AS day, COUNT(*) AS count FROM addon_installs WHERE first_kind = 'install' AND first_seen >= ?" + W + ' GROUP BY first_seen ORDER BY first_seen',
      from, ...fa
    ),
    detected: await seriesQ(
      "SELECT first_seen AS day, COUNT(*) AS count FROM addon_installs WHERE first_kind = 'detected' AND first_seen >= ?" + W + ' GROUP BY first_seen ORDER BY first_seen',
      from, ...fa
    ),
    newWarpath: await seriesQ('SELECT first_seen AS day, COUNT(*) AS count FROM installs WHERE first_seen >= ? GROUP BY first_seen ORDER BY first_seen', from),
    active: filtered
      ? await seriesQ("SELECT day, COUNT(DISTINCT install_id) AS count FROM daily_activity WHERE repo <> '' AND day >= ?" + W + ' GROUP BY day ORDER BY day', from, ...fa)
      : await seriesQ("SELECT day, COUNT(DISTINCT install_id) AS count FROM daily_activity WHERE repo = '' AND day >= ? GROUP BY day ORDER BY day", from),
    updates: await seriesQ("SELECT day, COUNT(*) AS count FROM events WHERE type = 'update' AND day >= ?" + W + ' GROUP BY day ORDER BY day', from, ...fa),
  };
  // Weeks start on Monday.
  const weekly = await all(
    "SELECT date(day, '-6 days', 'weekday 1') AS week, COUNT(DISTINCT install_id) AS active FROM daily_activity WHERE " +
      (filtered ? "repo <> ''" : "repo = ''") + ' AND day >= ?' + W + ' GROUP BY week ORDER BY week',
    from, ...fa
  );
  const weeklyNew = await all(
    "SELECT date(first_seen, '-6 days', 'weekday 1') AS week, COUNT(*) AS count FROM addon_installs WHERE first_kind = 'install' AND first_seen >= ?" + W + ' GROUP BY week',
    from, ...fa
  );
  const wn = new Map(weeklyNew.map((r) => [r.week, Number(r.count) || 0]));
  const weeks = new Set([...weekly.map((r) => r.week), ...wn.keys()]);
  series.weekly = [...weeks].sort().map((w) => ({
    week: w,
    active: Number((weekly.find((r) => r.week === w) || {}).active) || 0,
    newInstalls: wn.get(w) || 0,
  }));

  return {
    ok: true,
    generatedAt: now.toISOString(),
    filters: { game, repo, range: rangeKey, from, to: today },
    totals,
    addons,
    series,
    notes: {
      installations: 'Anonymous installation IDs count Warpath copies, not people.',
      active: 'Active = Warpath ran and found the addon installed. It does not prove the addon was used in game.',
      inGame: 'In-game use comes only from addons that record usage times in SavedVariables.',
    },
  };
}

// ---------------------------------------------------------------- retention

export async function applyRetention(env, now) {
  const days = Math.max(30, Number(env.RETENTION_DAYS) || 395);
  const cutoff = addDays(now, -days);
  const db = env.DB;
  const stale = (await db.prepare('SELECT install_id FROM installs WHERE last_seen < ?').bind(cutoff).all()).results || [];
  for (const r of stale) await deleteInstall(env, r.install_id);
  await db.batch([
    db.prepare('DELETE FROM events WHERE day < ?').bind(cutoff),
    db.prepare('DELETE FROM daily_activity WHERE day < ?').bind(cutoff),
    db.prepare('DELETE FROM rate_limits WHERE window_start < ?').bind(Math.floor(now.getTime() / 1000) - 2 * 86400),
  ]);
  return { cutoff, removedInstalls: stale.length };
}
