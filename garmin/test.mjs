// Run: npm test (inside garmin/). Never talks to Garmin: GOTA_GARMIN_API_BASE points
// the CLI at a local HTTP server.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { classifyError, parseDateArg, parseMlArg, parseTimeArg, localParts, HelperError } from './gota-garmin.mjs';

const CLI = path.join(path.dirname(fileURLToPath(import.meta.url)), 'gota-garmin.mjs');

// ---------- pure helpers ----------

test('classifyError maps library and network failures to stable codes', () => {
  const cases = [
    [Object.assign(new Error('getaddrinfo ENOTFOUND connectapi.garmin.com'), { code: 'ENOTFOUND' }), 'network'],
    [new Error('timeout of 20000ms exceeded'), 'network'],
    [new Error('ERROR: (401), Unauthorized'), 'auth_required'],
    [new Error('ERROR: (403), Forbidden'), 'auth_required'],
    [new TypeError("Cannot set properties of undefined (setting 'last_update_date')"), 'auth_required'],
    [Object.assign(new Error('ERROR: (429), Too Many Requests'), { response: { status: 429 } }), 'rate_limited'],
    [new Error('ERROR: (503), Service Unavailable'), 'garmin_unavailable'],
    [new Error('ERROR: (404), Not Found'), 'garmin_changed'],
    [new Error('Garmin SSO widget did not provide a CSRF token'), 'garmin_changed'],
    [new HelperError('usage', 'x'), 'usage'],
    [new Error('something odd'), 'internal'],
  ];
  for (const [err, code] of cases) assert.equal(classifyError(err).code, code, err.message);
});

test('parseDateArg accepts real dates only', () => {
  assert.equal(parseDateArg('2026-11-05'), '2026-11-05');
  for (const bad of ['2026-02-30', '05/11/2026', '2026-1-5', undefined]) {
    assert.throws(() => parseDateArg(bad), { code: 'usage' });
  }
});

test('parseMlArg accepts non-zero integers within range', () => {
  assert.equal(parseMlArg('500'), 500);
  assert.equal(parseMlArg('-250'), -250);
  for (const bad of ['0', '12.5', 'abc', '9000', undefined]) {
    assert.throws(() => parseMlArg(bad), { code: 'usage' });
  }
});

test('parseTimeArg + localParts give Mac-local date and timestamp', () => {
  const dt = parseTimeArg('2026-11-05T14:30:00');
  assert.deepEqual(localParts(dt), { date: '2026-11-05', timestampLocal: '2026-11-05T14:30:00.000' });
  assert.throws(() => parseTimeArg('14:30'), { code: 'usage' });
});

// ---------- CLI end to end ----------

function run(args, { env = {}, stdin = 'ignore' } = {}) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [CLI, ...args], {
      env: { ...process.env, ...env },
      stdio: [stdin, 'pipe', 'pipe'],
    });
    let out = '';
    let err = '';
    child.stdout.on('data', (d) => (out += d));
    child.stderr.on('data', (d) => (err += d));
    child.on('close', (code) => resolve({ code, out, err, json: JSON.parse(out.trim().split('\n').pop() || 'null') }));
  });
}

function tempTokenDir(withTokens) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'gota-garmin-test-'));
  if (withTokens) {
    const future = Math.floor(Date.now() / 1000) + 3600;
    fs.writeFileSync(path.join(dir, 'oauth1_token.json'), JSON.stringify({ oauth_token: 't', oauth_token_secret: 's' }));
    fs.writeFileSync(
      path.join(dir, 'oauth2_token.json'),
      JSON.stringify({ access_token: 'a', refresh_token: 'r', expires_at: future, refresh_token_expires_at: future })
    );
  }
  return dir;
}

/** Fake Garmin API on localhost; handler(url, method) → [status, json]. */
async function fakeGarmin(handler) {
  const seen = [];
  const server = http.createServer((req, res) => {
    let body = '';
    req.on('data', (d) => (body += d));
    req.on('end', () => {
      seen.push({ method: req.method, url: req.url, body: body ? JSON.parse(body) : null });
      const [status, json] = handler(req.url, req.method);
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end(JSON.stringify(json));
    });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  return { env: { GOTA_GARMIN_API_BASE: base }, seen, close: () => server.close() };
}

test('usage errors come out as JSON', async () => {
  const r = await run(['add', '250']);
  assert.equal(r.code, 1);
  assert.equal(r.json.ok, false);
  assert.equal(r.json.error.code, 'usage');
});

test('get without a saved session → auth_required', async () => {
  const r = await run(['get', '2026-11-05'], { env: { GOTA_GARMIN_TOKEN_DIR: tempTokenDir(false) } });
  assert.equal(r.code, 1);
  assert.equal(r.json.error.code, 'auth_required');
});

test('login outside a terminal → not_interactive', async () => {
  const r = await run(['login'], { stdin: 'pipe' });
  assert.equal(r.json.error.code, 'not_interactive');
});

test('get with no network → network', async () => {
  const r = await run(['get', '2026-11-05'], {
    env: { GOTA_GARMIN_TOKEN_DIR: tempTokenDir(true), GOTA_GARMIN_API_BASE: 'http://127.0.0.1:9' },
  });
  assert.equal(r.json.error.code, 'network');
});

test('get reads ml of the day, 0 when empty, keeps stdout to one JSON line', async () => {
  const g = await fakeGarmin((url) =>
    url.endsWith('/2026-11-05')
      ? [200, { calendarDate: '2026-11-05', valueInML: 1250, goalInML: 2500, lastEntryTimestampLocal: '2026-11-05T13:10:00.0' }]
      : [200, { calendarDate: '2026-11-04', valueInML: null, goalInML: 2500, lastEntryTimestampLocal: null }]
  );
  const env = { ...g.env, GOTA_GARMIN_TOKEN_DIR: tempTokenDir(true) };
  const full = await run(['get', '2026-11-05'], { env });
  const empty = await run(['get', '2026-11-04'], { env });
  g.close();
  assert.equal(full.out.trim().split('\n').length, 1);
  assert.deepEqual(full.json, { ok: true, date: '2026-11-05', ml: 1250, goal_ml: 2500, last_entry_local: '2026-11-05T13:10:00.0' });
  assert.equal(empty.json.ml, 0);
  assert.match(g.seen[0].url, /usersummary-service\/usersummary\/hydration\/allData\/2026-11-05$/);
});

test('add sends ml and local time to the hydration log', async () => {
  const g = await fakeGarmin((url) =>
    url.includes('userprofile') ? [200, { profileId: 42, displayName: 'x' }] : [200, { calendarDate: '2026-11-05', valueInML: 1750 }]
  );
  const r = await run(['add', '500', '2026-11-05T14:30:00'], { env: { ...g.env, GOTA_GARMIN_TOKEN_DIR: tempTokenDir(true) } });
  g.close();
  assert.deepEqual(r.json, { ok: true, date: '2026-11-05', added_ml: 500, timestamp_local: '2026-11-05T14:30:00.000', total_ml: 1750 });
  const put = g.seen.find((s) => s.method === 'PUT');
  assert.match(put.url, /hydration\/log$/);
  assert.deepEqual(put.body, { calendarDate: '2026-11-05', timestampLocal: '2026-11-05T14:30:00.000', valueInML: 500, userProfileId: 42 });
});

test('Garmin rejecting the session → auth_required', async () => {
  const g = await fakeGarmin(() => [401, { message: 'Unauthorized' }]);
  const r = await run(['get', '2026-11-05'], { env: { ...g.env, GOTA_GARMIN_TOKEN_DIR: tempTokenDir(true) } });
  g.close();
  assert.equal(r.json.error.code, 'auth_required');
});

test('unexpected response shape → garmin_changed', async () => {
  const g = await fakeGarmin(() => [200, { somethingElse: true }]);
  const r = await run(['get', '2026-11-05'], { env: { ...g.env, GOTA_GARMIN_TOKEN_DIR: tempTokenDir(true) } });
  g.close();
  assert.equal(r.json.error.code, 'garmin_changed');
});

test('a refreshed session is saved back with permission 600 in a 700 folder', async () => {
  // Garmin answers 401 once; the library exchanges oauth1 for a new oauth2 and retries.
  let rejected = false;
  const g = await fakeGarmin((url) => {
    if (url.includes('/oauth-service/oauth/exchange')) {
      return [200, { access_token: 'new', refresh_token: 'r2', expires_in: 3600, refresh_token_expires_in: 7200 }];
    }
    if (!rejected) {
      rejected = true;
      return [401, { message: 'Unauthorized' }];
    }
    return [200, { calendarDate: '2026-11-05', valueInML: 300, goalInML: 2500 }];
  });
  const dir = tempTokenDir(true);
  fs.chmodSync(dir, 0o755);
  fs.chmodSync(path.join(dir, 'oauth2_token.json'), 0o644);
  const r = await run(['get', '2026-11-05'], { env: { ...g.env, GOTA_GARMIN_TOKEN_DIR: dir } });
  g.close();
  assert.equal(r.json.ml, 300, JSON.stringify(r.json));
  const saved = JSON.parse(fs.readFileSync(path.join(dir, 'oauth2_token.json'), 'utf8'));
  assert.equal(saved.access_token, 'new');
  for (const f of ['oauth1_token.json', 'oauth2_token.json']) {
    assert.equal(fs.statSync(path.join(dir, f)).mode & 0o777, 0o600, f);
  }
  assert.equal(fs.statSync(dir).mode & 0o777, 0o700);
});

test('a correction that empties the day reports total 0 (Garmin sends valueInML null)', async () => {
  const g = await fakeGarmin((url) =>
    url.includes('userprofile') ? [200, { profileId: 42 }] : [200, { calendarDate: '2026-11-05', valueInML: null }]
  );
  const r = await run(['add', '-50', '2026-11-05T14:50:00'], { env: { ...g.env, GOTA_GARMIN_TOKEN_DIR: tempTokenDir(true) } });
  g.close();
  assert.deepEqual(r.json, { ok: true, date: '2026-11-05', added_ml: -50, timestamp_local: '2026-11-05T14:50:00.000', total_ml: 0 });
});
