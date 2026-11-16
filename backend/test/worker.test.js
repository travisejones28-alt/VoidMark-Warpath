import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { handle, applyRetention, LIMITS } from '../src/index.js';
import { FakeD1 } from './fake-d1.js';

const TOKEN = 'test-admin-token-0123456789abcdefghijklmnop';
const NOW = new Date('2026-11-16T18:00:00Z');

function env(extra = {}) {
  return {
    DB: new FakeD1(),
    ADMIN_TOKEN_SHA256: createHash('sha256').update(TOKEN).digest('hex'),
    RATE_SALT: 'salt',
    ...extra,
  };
}
function post(path, body, headers = {}) {
  return new Request('https://a.example' + path, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'cf-connecting-ip': '203.0.113.9', 'user-agent': 'VoidMark-Warpath', ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}
function get(path, token = TOKEN) {
  const headers = token ? { authorization: 'Bearer ' + token } : {};
  return new Request('https://a.example' + path, { headers });
}
const ID = () => randomUUID();
function batch(installId, events, extra = {}) {
  return { installId, appVersion: '3.5.0', consent: true, events, ...extra };
}
function ev(type, repo = 'VoidMark-Market', version = '1.23.38', game = 'WoW Forever', ts = NOW.toISOString()) {
  return { id: ID(), type, ts, game, repo, version };
}
async function send(e, body, now = NOW) {
  const r = await handle(post('/v1/events', body), e, now);
  return { status: r.status, body: await r.json() };
}
async function summary(e, q = '', now = NOW, token = TOKEN) {
  const r = await handle(get('/v1/admin/summary' + q, token), e, now);
  return { status: r.status, body: await r.json() };
}

test('install and update events are stored separately and counted', async () => {
  const e = env();
  const id = ID();
  let r = await send(e, batch(id, [ev('install', 'VoidMark-Market', '1.23.37')]));
  assert.equal(r.status, 200);
  assert.equal(r.body.accepted.length, 1);
  r = await send(e, batch(id, [ev('update', 'VoidMark-Market', '1.23.38')]));
  assert.equal(r.body.accepted.length, 1);
  assert.equal(e.DB.count('events', "type='install'"), 1);
  assert.equal(e.DB.count('events', "type='update'"), 1);
  assert.equal(e.DB.count('addon_installs'), 1);
  const s = await summary(e);
  assert.equal(s.status, 200);
  assert.equal(s.body.totals.warpathInstalls, 1);
  assert.equal(s.body.totals.newAddonInstallsWeek, 1);
  assert.equal(s.body.totals.updatesAllTime, 1);
  assert.equal(s.body.addons[0].versions[0].version, '1.23.38');
});

test('a retried event id is only counted once', async () => {
  const e = env();
  const id = ID();
  const one = ev('update');
  await send(e, batch(id, [one]));
  const again = await send(e, batch(id, [one, one]));
  assert.equal(again.status, 200);
  assert.deepEqual(again.body.accepted, [one.id, one.id]); // acknowledged so the client stops retrying
  assert.equal(e.DB.count('events'), 1);
  const s = await summary(e);
  assert.equal(s.body.totals.updatesAllTime, 1);
});

test('detected (pre-existing) addons are not counted as new installs', async () => {
  const e = env();
  await send(e, batch(ID(), [ev('detected', 'VoidMark-Forever', '1.2.29'), ev('detected', 'VoidMark-Nexus', '0.10.23-beta')]));
  await send(e, batch(ID(), [ev('install', 'VoidMark-Forever', '1.2.29')]));
  const s = await summary(e);
  assert.equal(s.body.totals.addonInstalls, 3);
  assert.equal(s.body.totals.detectedExisting, 2);
  assert.equal(s.body.totals.newAddonInstallsMonth, 1);
  const forever = s.body.addons.find((a) => a.repo === 'VoidMark-Forever');
  assert.equal(forever.viaWarpath, 1);
  assert.equal(forever.detected, 1);
  // A repeated "detected" registration for the same addon is idempotent.
  const s2 = await summary(e);
  assert.equal(s2.body.totals.addonInstalls, 3);
});

test('re-registering the same addon on a later launch does not duplicate it', async () => {
  const e = env();
  const id = ID();
  await send(e, batch(id, [ev('detected', 'VoidMark-Debug', '1.3.3-forever')]));
  await send(e, batch(id, [ev('detected', 'VoidMark-Debug', '1.3.3-forever')]));
  assert.equal(e.DB.count('addon_installs'), 1);
});

test('check-ins mark daily activity once per day and keep the newest version', async () => {
  const e = env();
  const id = ID();
  const checkin = (ts, version) => ({
    id: ID(),
    type: 'checkin',
    ts,
    addons: [{ game: 'WoW Forever', repo: 'VoidMark-Market', version }],
  });
  await send(e, batch(id, [checkin('2026-11-01T10:00:00Z', '1.23.30')]));
  await send(e, batch(id, [checkin('2026-11-16T10:00:00Z', '1.23.38')]));
  await send(e, batch(id, [checkin('2026-11-16T12:00:00Z', '1.23.38')]));
  assert.equal(e.DB.count('daily_activity', "repo=''"), 2);
  const s = await summary(e, '?range=30');
  assert.equal(s.body.totals.active7, 1);
  assert.equal(s.body.totals.active30, 1);
  assert.equal(s.body.addons[0].versions.length, 1);
  assert.equal(s.body.addons[0].versions[0].version, '1.23.38');
  const s7 = await summary(e, '?range=7');
  assert.equal(s7.body.series.active.length, 1);
});

test('in-game usage times are kept separately from Warpath check-ins', async () => {
  const e = env();
  const id = ID();
  const init = Math.floor(NOW.getTime() / 1000) - 3600;
  await send(e, batch(id, [{
    id: ID(), type: 'checkin', ts: NOW.toISOString(),
    addons: [
      { game: 'WoW Forever', repo: 'VoidMark-Market', version: '1.23.38', usage: { init, active: init } },
      { game: 'WoW Forever', repo: 'VoidMark-Debug', version: '1.3.3-forever', usage: { init } },
      { game: 'WoW Forever', repo: 'VoidMark-Nexus', version: '0.11.1-beta' },
    ],
  }]));
  const s = await summary(e);
  const by = (r) => s.body.addons.find((a) => a.repo === r);
  assert.equal(by('VoidMark-Market').inGameUsed7, 1);
  assert.equal(by('VoidMark-Debug').inGameLoaded30, 1);
  assert.equal(by('VoidMark-Debug').inGameUsed30, 0);
  assert.equal(by('VoidMark-Nexus').reportsUsage, 0);
  assert.equal(by('VoidMark-Nexus').active7, 1);
});

test('no consent flag is needed (statistics are always on)', async () => {
  const e = env();
  const r = await send(e, batch(ID(), [ev('install')], { consent: undefined }));
  assert.equal(r.status, 200);
  assert.equal(e.DB.count('installs'), 1);
});

test('input validation rejects bad ids, games, repos, versions and oversize bodies', async () => {
  const e = env();
  assert.equal((await send(e, batch('not-a-uuid', [ev('install')]))).status, 400);
  assert.equal((await send(e, '{oops')).status, 400);
  assert.equal((await send(e, batch(ID(), []))).status, 400);
  const tooMany = Array.from({ length: 51 }, () => ev('update'));
  assert.equal((await send(e, batch(ID(), tooMany))).status, 400);
  const big = batch(ID(), [ev('install')], { pad: 'x'.repeat(40000) });
  assert.equal((await send(e, big)).status, 413);
  const bad = [
    { ...ev('install'), game: 'Retail' },
    { ...ev('install'), repo: 'SomeoneElse' },
    { ...ev('install'), version: 'x'.repeat(80) },
    { ...ev('install'), type: 'hack' },
    { ...ev('install'), id: '1' },
    ev('install'),
  ];
  const r = await send(e, batch(ID(), bad));
  assert.equal(r.status, 200);
  assert.equal(r.body.accepted.length, 1);
  assert.equal(r.body.rejected.length, 5);
});

test('per-installation rate limiting', async () => {
  const e = env();
  const id = ID();
  let last;
  for (let i = 0; i < LIMITS.perInstallPerHour + 1; i++) last = await send(e, batch(id, [ev('update')]));
  assert.equal(last.status, 429);
  // A different installation is unaffected.
  assert.equal((await send(e, batch(ID(), [ev('update')]))).status, 200);
});

test('IP rate limiter is keyed by a hash, and no IP or user agent is ever stored', async () => {
  const keys = [];
  const e = env({ INGEST_LIMITER: { limit: async ({ key }) => { keys.push(key); return { success: keys.length <= 2 }; } } });
  assert.equal((await send(e, batch(ID(), [ev('install')]))).status, 200);
  assert.equal((await send(e, batch(ID(), [ev('install')]))).status, 200);
  assert.equal((await send(e, batch(ID(), [ev('install')]))).status, 429);
  assert.ok(keys.every((k) => /^[0-9a-f]{64}$/.test(k) && !k.includes('203.0.113.9')));
  for (const table of ['installs', 'addon_installs', 'events', 'daily_activity', 'rate_limits']) {
    const rows = e.DB.db.prepare(`SELECT * FROM ${table}`).all();
    const text = JSON.stringify(rows);
    assert.ok(!text.includes('203.0.113.9'), table + ' holds an IP');
    assert.ok(!text.includes('VoidMark-Warpath/'), table + ' holds a user agent');
  }
});

test('owner authentication: missing, wrong and correct tokens; lockout after repeated failures', async () => {
  const e = env();
  assert.equal((await summary(e, '', NOW, null)).status, 401);
  assert.equal((await summary(e, '', NOW, 'wrong-token-wrong-token-wrong-token-xx')).status, 401);
  assert.equal((await summary(e)).status, 200);
  for (let i = 0; i < LIMITS.adminFailuresPerHour; i++) await summary(e, '', NOW, 'wrong-token-wrong-token-wrong-token-xx');
  const locked = await summary(e);
  assert.equal(locked.status, 429);
  // Next hour it works again.
  assert.equal((await summary(e, '', new Date(NOW.getTime() + 3600000))).status, 200);
});

test('admin endpoints refuse to run without a configured token hash', async () => {
  const e = env({ ADMIN_TOKEN_SHA256: '' });
  assert.equal((await summary(e)).status, 503);
});

test('an installation can delete all of its own data; owner can delete one installation', async () => {
  const e = env();
  const mine = ID();
  const other = ID();
  await send(e, batch(mine, [ev('install'), { id: ID(), type: 'checkin', ts: NOW.toISOString(), addons: [{ game: 'WoW Forever', repo: 'VoidMark-Market', version: '1' }] }]));
  await send(e, batch(other, [ev('install')]));
  const r = await handle(post('/v1/installations/delete', { installId: mine }), e, NOW);
  assert.equal(r.status, 200);
  for (const t of ['installs', 'addon_installs', 'events', 'daily_activity']) assert.equal(e.DB.count(t, 'install_id = ?', mine), 0, t);
  assert.equal(e.DB.count('installs', 'install_id = ?', other), 1);
  // Owner deletion needs the admin token.
  const noAuth = await handle(new Request('https://a.example/v1/admin/installations/' + other, { method: 'DELETE' }), e, NOW);
  assert.equal(noAuth.status, 401);
  const ok = await handle(new Request('https://a.example/v1/admin/installations/' + other, { method: 'DELETE', headers: { authorization: 'Bearer ' + TOKEN } }), e, NOW);
  assert.equal(ok.status, 200);
  assert.equal(e.DB.count('installs'), 0);
});

test('summary filters by game, addon and range; most popular addon', async () => {
  const e = env();
  for (let i = 0; i < 3; i++) await send(e, batch(ID(), [ev('install', 'VoidMark-Market')]));
  await send(e, batch(ID(), [ev('install', 'VoidMark', '1.3.11', 'WoW Classic Era')]));
  await send(e, batch(ID(), [ev('install', 'VoidMark-Nexus', '0.10.23-beta', 'WoW Forever', '2026-10-01T00:00:00Z')]));
  let s = await summary(e, '?game=WoW%20Classic%20Era');
  assert.equal(s.body.totals.addonInstalls, 1);
  assert.equal(s.body.addons.length, 1);
  s = await summary(e, '?repo=VoidMark-Market');
  assert.equal(s.body.totals.warpathInstalls, 3);
  s = await summary(e);
  assert.equal(s.body.totals.mostPopular.repo, 'VoidMark-Market');
  assert.equal(s.body.totals.warpathInstalls, 5);
  // Clamped: an event from 46+ days ago is filed 45 days back, outside the 7-day range.
  s = await summary(e, '?range=7');
  assert.equal(s.body.series.newInstalls.reduce((n, d) => n + d.count, 0), 4);
  s = await summary(e, '?range=all');
  assert.equal(s.body.series.newInstalls.reduce((n, d) => n + d.count, 0), 5);
  assert.ok(Array.isArray(s.body.series.weekly) && s.body.series.weekly.length >= 1);
});

test('retention removes old activity and installations not seen for the retention period', async () => {
  const e = env({ RETENTION_DAYS: '60' });
  const old = ID();
  await send(e, batch(old, [ev('install')]), new Date('2026-06-01T00:00:00Z'));
  await send(e, batch(ID(), [ev('install')]), NOW);
  const res = await applyRetention(e, NOW);
  assert.equal(res.removedInstalls, 1);
  assert.equal(e.DB.count('installs'), 1);
  assert.equal(e.DB.count('events', 'install_id = ?', old), 0);
});

test('unknown routes and wrong methods', async () => {
  const e = env();
  assert.equal((await handle(new Request('https://a.example/'), e, NOW)).status, 404);
  assert.equal((await handle(new Request('https://a.example/v1/events'), e, NOW)).status, 405);
  assert.equal((await handle(new Request('https://a.example/v1/health'), e, NOW)).status, 200);
});
