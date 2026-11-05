#!/usr/bin/env node
// Gota ↔ Garmin Connect helper. Contract: see garmin/README.md.
//
// stdout carries exactly one JSON line per run, success or failure. Everything
// else (library logs, interactive prompts) goes to stderr, so the Swift app can
// parse stdout blindly.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline';
import { pathToFileURL } from 'node:url';

export const TOKEN_DIR =
  process.env.GOTA_GARMIN_TOKEN_DIR ||
  path.join(os.homedir(), 'Library', 'Application Support', 'Gota', 'garmin');
const OAUTH1_FILE = 'oauth1_token.json';
const OAUTH2_FILE = 'oauth2_token.json';
const REQUEST_TIMEOUT_MS = 20_000;
const RUN_TIMEOUT_MS = 45_000;

export class HelperError extends Error {
  constructor(code, message, detail) {
    super(message);
    this.code = code;
    this.detail = detail;
  }
}

// ---------- pure helpers (unit-tested in test.mjs) ----------

const NETWORK_CODES = new Set([
  'ENOTFOUND', 'EAI_AGAIN', 'ECONNREFUSED', 'ECONNRESET', 'ETIMEDOUT',
  'ECONNABORTED', 'ENETUNREACH', 'EHOSTUNREACH', 'ERR_NETWORK', 'EPIPE',
]);

/** Maps any thrown value to a stable { code, message, detail } for the JSON contract. */
export function classifyError(err) {
  if (err instanceof HelperError) {
    return { code: err.code, message: err.message, detail: err.detail };
  }
  const detail = err instanceof Error ? err.message : String(err);
  const sysCode = err?.code ?? err?.cause?.code;
  const status =
    err?.response?.status ?? (Number((detail.match(/ERROR: \((\d{3})\)/) || [])[1]) || undefined);

  if (NETWORK_CODES.has(sysCode) || /timeout of \d+ms exceeded|socket hang up|network error/i.test(detail)) {
    return { code: 'network', message: 'Sem conexão com o Garmin Connect.', detail };
  }
  // A rejected token refresh surfaces from the library as a TypeError on 'last_update_date'
  // (it reads the token off a failed response), not as a 401.
  if (status === 401 || status === 403 || /No Oauth2Token or Oauth1Token|'last_update_date'/.test(detail)) {
    return { code: 'auth_required', message: 'Sessão do Garmin expirada. Rode o login de novo.', detail };
  }
  if (status === 429) {
    return { code: 'rate_limited', message: 'O Garmin pediu para esperar antes de tentar de novo.', detail };
  }
  if (status >= 500) {
    return { code: 'garmin_unavailable', message: 'O Garmin Connect está fora do ar agora.', detail };
  }
  if (status >= 400 || /CSRF|service ticket|consumer_key|Unexpected token|is not valid JSON/i.test(detail)) {
    return { code: 'garmin_changed', message: 'O Garmin mudou algo e o ajudante precisa de atualização.', detail };
  }
  return { code: 'internal', message: 'Erro inesperado no ajudante do Garmin.', detail };
}

/** Validates YYYY-MM-DD and that it is a real calendar date. */
export function parseDateArg(s) {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s)) {
    throw new HelperError('usage', 'Data inválida; use AAAA-MM-DD.', String(s));
  }
  const [y, m, d] = s.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) {
    throw new HelperError('usage', 'Data inválida; use AAAA-MM-DD.', s);
  }
  return s;
}

/** Non-zero integer ml; negative removes water (a correction, as in the Garmin app). */
export function parseMlArg(s) {
  if (typeof s !== 'string' || !/^-?\d+$/.test(s)) {
    throw new HelperError('usage', 'Quantidade inválida; use ml inteiros.', String(s));
  }
  const ml = Number(s);
  if (ml === 0 || Math.abs(ml) > 5000) {
    throw new HelperError('usage', 'Quantidade fora do intervalo (1 a 5000 ml, ou negativa para corrigir).', s);
  }
  return ml;
}

/** ISO 8601 date-time (with or without offset) → Date. */
export function parseTimeArg(s) {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(s)) {
    throw new HelperError('usage', 'Horário inválido; use ISO 8601, por exemplo 2026-11-05T14:30:00-03:00.', String(s));
  }
  const dt = new Date(s);
  if (Number.isNaN(dt.getTime())) {
    throw new HelperError('usage', 'Horário inválido; use ISO 8601.', s);
  }
  return dt;
}

const pad = (n, w = 2) => String(n).padStart(w, '0');

/** Date → Mac-local "YYYY-MM-DD" and "YYYY-MM-DDTHH:mm:ss.SSS" (what Garmin calls timestampLocal). */
export function localParts(dt) {
  const date = `${dt.getFullYear()}-${pad(dt.getMonth() + 1)}-${pad(dt.getDate())}`;
  const time = `${pad(dt.getHours())}:${pad(dt.getMinutes())}:${pad(dt.getSeconds())}.${pad(dt.getMilliseconds(), 3)}`;
  return { date, timestampLocal: `${date}T${time}` };
}

// ---------- I/O ----------

function emit(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

// Pipe writes are async on macOS: exit only after stdout has drained.
function exitAfterFlush(code) {
  process.stdout.write('', () => process.exit(code));
}

// The library prints to console.log/console.error; keep stdout clean for JSON.
function routeConsoleToStderr() {
  const toErr = (...args) => process.stderr.write(args.map(String).join(' ') + '\n');
  console.log = console.info = console.warn = console.error = console.debug = toErr;
}

function readTokens() {
  try {
    const oauth1 = JSON.parse(fs.readFileSync(path.join(TOKEN_DIR, OAUTH1_FILE), 'utf8'));
    const oauth2 = JSON.parse(fs.readFileSync(path.join(TOKEN_DIR, OAUTH2_FILE), 'utf8'));
    return { oauth1, oauth2 };
  } catch {
    return null;
  }
}

function writeTokens({ oauth1, oauth2 }) {
  fs.mkdirSync(TOKEN_DIR, { recursive: true, mode: 0o700 });
  fs.chmodSync(TOKEN_DIR, 0o700);
  for (const [file, data] of [[OAUTH1_FILE, oauth1], [OAUTH2_FILE, oauth2]]) {
    const p = path.join(TOKEN_DIR, file);
    const tmp = `${p}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(data), { mode: 0o600 });
    fs.chmodSync(tmp, 0o600);
    fs.renameSync(tmp, p);
  }
}

async function newClient(credentials = { username: '', password: '' }) {
  const { default: lib } = await import('@flow-js/garmin-connect'); // CJS package
  const gc = new lib.GarminConnect(credentials);
  gc.client.client.defaults.timeout = REQUEST_TIMEOUT_MS;
  // Test seam: point every API call at a local fake and skip the consumer-key download,
  // so the test suite never reaches Garmin.
  if (process.env.GOTA_GARMIN_API_BASE) {
    gc.url.GC_API = process.env.GOTA_GARMIN_API_BASE;
    gc.client.OAUTH_CONSUMER = { key: 'test', secret: 'test' };
  }
  return gc;
}

/** Client with saved tokens; persists them again if the library refreshed them. */
async function withSession(fn) {
  const tokens = readTokens();
  if (!tokens) {
    throw new HelperError('auth_required', 'Sem sessão do Garmin. Rode o login primeiro.');
  }
  const gc = await newClient();
  gc.loadToken(tokens.oauth1, tokens.oauth2);
  try {
    return await fn(gc);
  } finally {
    try {
      const now = gc.exportToken();
      if (JSON.stringify(now.oauth2) !== JSON.stringify(tokens.oauth2)) writeTokens(now);
    } catch {
      // no tokens to save
    }
  }
}

function isObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

// ---------- commands ----------

async function cmdGet(dateArg) {
  const date = parseDateArg(dateArg);
  return withSession(async (gc) => {
    const data = await gc.get(`${gc.url.DAILY_HYDRATION}/${date}`);
    if (!isObject(data) || !('valueInML' in data)) {
      throw new HelperError('garmin_changed', 'Resposta de hidratação em formato inesperado.', JSON.stringify(data)?.slice(0, 300));
    }
    return {
      ok: true,
      date,
      ml: Math.round(data.valueInML ?? 0),
      goal_ml: data.goalInML == null ? null : Math.round(data.goalInML),
      last_entry_local: data.lastEntryTimestampLocal ?? null,
    };
  });
}

async function cmdAdd(mlArg, timeArg) {
  const ml = parseMlArg(mlArg);
  const { date, timestampLocal } = localParts(parseTimeArg(timeArg));
  return withSession(async (gc) => {
    const profile = await gc.getUserProfile();
    if (!isObject(profile) || profile.profileId == null) {
      throw new HelperError('garmin_changed', 'Perfil do Garmin em formato inesperado.');
    }
    // Same endpoint and body the library's updateHydrationLogOunces uses, but in ml and
    // with the Mac's local time (the library sends UTC labelled as local).
    const res = await gc.put(gc.url.HYDRATION_LOG, {
      calendarDate: date,
      timestampLocal,
      valueInML: ml,
      userProfileId: profile.profileId,
    });
    if (!isObject(res) || typeof res.valueInML !== 'number') {
      throw new HelperError('garmin_changed', 'Resposta da gravação em formato inesperado.', JSON.stringify(res)?.slice(0, 300));
    }
    return { ok: true, date, added_ml: ml, timestamp_local: timestampLocal, total_ml: Math.round(res.valueInML) };
  });
}

function ask(rl, question) {
  return new Promise((resolve) => rl.question(question, (a) => resolve(a.trim())));
}

function askHidden(question) {
  return new Promise((resolve, reject) => {
    const stdin = process.stdin;
    process.stderr.write(question);
    let value = '';
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding('utf8');
    const onData = (chunk) => {
      for (const ch of chunk) {
        if (ch === '\r' || ch === '\n') {
          stdin.setRawMode(false);
          stdin.pause();
          stdin.off('data', onData);
          process.stderr.write('\n');
          return resolve(value);
        }
        if (ch === '\u0003') {
          stdin.setRawMode(false);
          return reject(new HelperError('cancelled', 'Login cancelado.'));
        }
        if (ch === '\u007f' || ch === '\b') value = value.slice(0, -1);
        else value += ch;
      }
    };
    stdin.on('data', onData);
  });
}

async function cmdLogin() {
  if (!process.stdin.isTTY) {
    throw new HelperError('not_interactive', 'O login precisa ser feito no Terminal.');
  }
  process.stderr.write('Login no Garmin Connect (a senha não é gravada; só a sessão fica salva).\n');
  let rl = readline.createInterface({ input: process.stdin, output: process.stderr });
  const username = await ask(rl, 'E-mail: ');
  rl.close();
  const password = await askHidden('Senha: ');
  if (!username || !password) throw new HelperError('usage', 'E-mail e senha são obrigatórios.');

  const gc = await newClient({ username, password });
  let mfaUsed = false;
  try {
    await gc.login(username, password, {
      mfaHandler: async () => {
        mfaUsed = true;
        rl = readline.createInterface({ input: process.stdin, output: process.stderr });
        const code = await ask(rl, 'Código de verificação (e-mail ou app): ');
        rl.close();
        return code;
      },
    });
  } catch (err) {
    const c = classifyError(err);
    if (c.code === 'auth_required' || /login failed|check username and password|MFA/i.test(c.detail ?? '')) {
      throw new HelperError('login_failed', 'Login recusado pelo Garmin (e-mail, senha ou código).', c.detail);
    }
    throw err;
  }
  writeTokens(gc.exportToken());
  let display_name = null;
  try {
    display_name = (await gc.getUserProfile())?.displayName ?? null;
  } catch {
    // tokens are saved; the name is only a courtesy
  }
  return { ok: true, display_name, mfa: mfaUsed, token_dir: TOKEN_DIR };
}

const USAGE = 'Uso: gota-garmin login | get <AAAA-MM-DD> | add <ml> <horário ISO>';

export async function main(argv) {
  routeConsoleToStderr();
  const [cmd, ...args] = argv;
  let watchdog;
  if (cmd === 'get' || cmd === 'add') {
    watchdog = setTimeout(() => {
      emit({ ok: false, error: { code: 'network', message: 'O Garmin Connect não respondeu a tempo.' } });
      exitAfterFlush(1);
    }, RUN_TIMEOUT_MS);
  }
  try {
    let result;
    if (cmd === 'login' && args.length === 0) result = await cmdLogin();
    else if (cmd === 'get' && args.length === 1) result = await cmdGet(args[0]);
    else if (cmd === 'add' && args.length === 2) result = await cmdAdd(args[0], args[1]);
    else throw new HelperError('usage', USAGE);
    emit(result);
    return 0;
  } catch (err) {
    const { code, message, detail } = classifyError(err);
    emit({ ok: false, error: detail ? { code, message, detail } : { code, message } });
    return 1;
  } finally {
    clearTimeout(watchdog);
  }
}

if (import.meta.url === pathToFileURL(fs.realpathSync(process.argv[1])).href) {
  main(process.argv.slice(2)).then(exitAfterFlush);
}
