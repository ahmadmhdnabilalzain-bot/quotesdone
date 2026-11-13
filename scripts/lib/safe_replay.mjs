// THE ONE DOOR FOR REPLAYING scripts/sql FILES AGAINST PRODUCTION (it_engineer, 30 Sep 2026).
//
// Why it exists. Many checks prove a committed-but-unapplied file by sending its text to production inside one
// request that ends in `raise exception`, so the whole request rolls back. On 30 Sep 2026 a local run of
// every_model_class_is_on_the_founders_matrix.test.mjs replayed a pending file that carried its own transaction
// lines; its COMMIT ran before the probe's raise, and the file was applied to production before its PR merged.
// #1152 guarded that one check. About forty other checks built the same request by hand. They all go through
// here now, and scripts/checks/every_sql_replay_goes_through_safe_replay.test.mjs fails a file that does not.
//
// What it guarantees, in order:
//   1. Nothing in the text can end the transaction. Top-level BEGIN / START TRANSACTION / COMMIT / END are
//      blanked (a file wrapped in its own transaction replays as that transaction's body). ROLLBACK, ABORT,
//      SAVEPOINT, RELEASE, PREPARE TRANSACTION, COMMIT PREPARED and SET TRANSACTION are REFUSED: stripping them
//      would change what the file means. The scan is sql_text.mjs's, so a `commit` inside a string, a comment
//      or a $tag$ body (a procedure that commits, a raise message) is left alone.
//   2. Nothing that Postgres refuses inside a transaction block, or that it cannot undo, is sent: CONCURRENTLY,
//      VACUUM, ALTER SYSTEM, ALTER TYPE ... ADD VALUE, CREATE/DROP DATABASE and TABLESPACE. `BEGIN ATOMIC`
//      bodies are refused too, because their inner `;` and `end` are code to this scan.
//   3. The request always ends in a raise: the caller's own probe raises first with its verdict, and if it does
//      not, SAFE_REPLAY_ROLLBACK does. `rows: true` is for a probe that ends in a verdict query: that query is
//      moved inside the final raise and its rows come back in the exception, so it rolls back too.
//   4. Afterwards it checks that nothing committed: a fingerprint of every routine and relation the text
//      creates (oid plus pg_get_functiondef) is read before and after, and a difference throws.
//   5. (13 Nov 2026) It never makes a live user wait: on production the text runs behind replay_guard.mjs's one-line
//      prelude (lock_timeout 1 s, a transaction_timeout, one replay at a time), a text that would take a strong lock on
//      a hot table is refused unless the operator accepts a stall of at most 5 s, and a configured local database
//      (QD_LOCAL_DB_URL) is used instead of production. Measured: rehearsals held quotes/inquiries for 12-15 s and live
//      requests timed out behind them (the header of replay_guard.mjs).
import { spawnSync } from 'node:child_process';
import { sql as send } from './db.mjs';
import { maskSql } from './sql_text.mjs';
import { BUSY_MARK, planReplay, stallAccepted } from './replay_guard.mjs';

// THE LOCAL DATABASE: psql with -1, so the whole text is ONE transaction and the final raise rolls all of it back,
// exactly as one management-API request does. Its error text is what a rows-mode replay reads its rows from.
function sendLocal(url, query) {
  const r = spawnSync('psql', [url, '-X', '-q', '-A', '-t', '-1', '-v', 'ON_ERROR_STOP=1', '-f', '-'], { input: query, encoding: 'utf8', maxBuffer: 64 << 20 });
  if (r.error) throw r.error;
  if (r.status !== 0) throw Object.assign(new Error(`local database: ${String(r.stderr).slice(0, 2000)}`), { body: String(r.stderr) });
  return r.stdout;
}
async function localFingerprint(url, objects) {
  if (!objects.routines.length && !objects.relations.length) return '';
  return String(sendLocal(url, fingerprintSql(objects))).trim();
}

export const ROLLBACK_MARK = 'SAFE_REPLAY_ROLLBACK';
const TAIL = `\n;\ndo $safe_replay$ begin raise exception '${ROLLBACK_MARK}: the replay is always rolled back'; end $safe_replay$;\n`;

const STRIP = /^(begin|start\s+transaction|commit|end)\b/;
const REFUSE = [
  [/^commit\s+prepared\b/, 'COMMIT PREPARED'],
  [/^(rollback|abort)\b/, 'ROLLBACK'],
  [/^(savepoint|release)\b/, 'SAVEPOINT / RELEASE'],
  [/^prepare\s+transaction\b/, 'PREPARE TRANSACTION'],
  [/^set\s+(session\s+characteristics|(local\s+|session\s+)?transaction)\b/, 'SET TRANSACTION'],
  [/\bconcurrently\b/, 'CONCURRENTLY'],
  [/^vacuum\b/, 'VACUUM'],
  [/^alter\s+system\b/, 'ALTER SYSTEM'],
  [/^alter\s+type\b[\s\S]*\badd\s+value\b/, 'ALTER TYPE ... ADD VALUE'],
  [/^(create|drop)\s+(database|tablespace)\b/, 'CREATE/DROP DATABASE or TABLESPACE'],
  [/\bbegin\s+atomic\b/, 'BEGIN ATOMIC'],
];

/** The text with its top-level transaction wrapper blanked; throws on anything that cannot be replayed safely. */
export function sanitizeReplay(text, label = 'the replay') {
  const s = String(text); const mask = maskSql(s);
  let out = ''; let from = 0;
  for (let at = 0; at <= mask.length; at++) {
    if (at < mask.length && mask[at] !== ';') continue;
    const code = mask.slice(from, at).trim().toLowerCase().replace(/\s+/g, ' ');
    const hit = code && REFUSE.find(([re]) => re.test(code));
    if (hit) {
      const line = s.slice(0, from).split('\n').length;
      throw new Error(`SAFE REPLAY REFUSED: ${label} carries ${hit[1]} near line ${line} ("${code.slice(0, 80)}"). `
        + 'It cannot run inside the one rolled-back transaction a replay is. Remove it from the file.');
    }
    const piece = s.slice(from, at);
    out += (code && STRIP.test(code) ? piece.replace(/[^\n]/g, ' ') : piece) + (at < mask.length ? ';' : '');
    from = at + 1;
  }
  return out;
}

/** Every routine and relation the text creates, as schema-qualified lower-case names. */
export function createdObjects(text) {
  const code = maskSql(text);
  const q = (n) => (n.includes('.') ? n : `public.${n}`).replace(/"/g, '').toLowerCase();
  const pick = (re) => [...new Set([...code.matchAll(re)].map((m) => q(m[1])))];
  return {
    routines: pick(/\bcreate\s+(?:or\s+replace\s+)?(?:function|procedure)\s+([a-z0-9_."]+)/gi),
    relations: pick(/\bcreate\s+(?:or\s+replace\s+)?(?:unlogged\s+)?(?:table|view|materialized\s+view|sequence)\s+(?:if\s+not\s+exists\s+)?([a-z0-9_."]+)/gi),
  };
}

const arr = (xs) => `array[${xs.map((x) => `'${x.replace(/'/g, "''")}'`).join(',') || "''"}]::text[]`;
async function fingerprint(objects, opts) {
  if (!objects.routines.length && !objects.relations.length) return '';
  const [row] = await send(fingerprintSql(objects), { ref: opts.ref, readOnly: true });
  return row.fp;
}
function fingerprintSql({ routines, relations }) {
  return `select
    coalesce((select md5(string_agg(p.oid::text || pg_get_functiondef(p.oid), '|' order by p.oid))
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where p.prokind in ('f','p') and n.nspname || '.' || p.proname = any(${arr(routines)})), '-')
    || '#' || coalesce((select string_agg(c.oid::text, ',' order by c.oid)
       from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname || '.' || c.relname = any(${arr(relations)})), '-') as fp`;
}

// ROWS MODE: the text's LAST statement must be a query; it is moved inside the final raise, so its rows come back
// in the exception message and the transaction still rolls back. set_config(..., true) verdicts written earlier
// in the text are visible to it, because it is the same transaction.
const ROWS = /SAFE_REPLAY_ROWS<<([\s\S]*)>>SAFE_REPLAY_ROWS/;
// The trailing trim reads the REAL text for whitespace and the MASK only for ';'. MEASURED 10 Nov 2026: it used to test
// the mask for both, and maskSql blanks a quoted identifier, so a last query ending in `as "waBrake"` lost its alias
// (`... ::jsonb) as) safe_replay_row`), a 42601 syntax error that failed
// the_ceo_acts_on_the_supplier_target_and_writes_its_effects B on every run. Exported for its offline test.
export function rowsBody(body, label) {
  const mask = maskSql(body);
  let end = mask.length; while (end > 0 && (/\s/.test(body[end - 1]) || mask[end - 1] === ';')) end--;
  const start = mask.lastIndexOf(';', end - 1) + 1;
  const last = body.slice(start, end);
  if (!/^\s*(select|with|values|table)\b/i.test(mask.slice(start, end))) {
    throw new Error(`SAFE REPLAY REFUSED: ${label} was asked for rows, and its last statement is not a query.`);
  }
  return body.slice(0, start) + `\ndo $safe_replay$ begin raise exception 'SAFE_REPLAY_ROWS<<%>>SAFE_REPLAY_ROWS', `
    // the alias is unusual on purpose: json_agg(x) reads a COLUMN named x before the row alias x.
    + `(select coalesce(json_agg(safe_replay_row), '[]'::json) from (${last}) safe_replay_row); end $safe_replay$;\n`;
}
function rowsFrom(error) {
  let text = String(error?.body ?? error?.message ?? error);
  const brace = text.indexOf('{');
  if (brace >= 0) { try { text = JSON.parse(text.slice(brace)).message ?? text; } catch { /* keep the raw text */ } }
  const m = ROWS.exec(text);
  try { return m ? JSON.parse(m[1]) : null; } catch { return null; }   // unreadable: the caller gets the real error
}

/**
 * Send a replay with the same contract as db.mjs's sql(): it throws what the request threw (the caller's probe
 * verdict, normally). `rows: true` returns the rows of the text's last query instead, still rolled back.
 */
export async function replaySql(text, { label = 'the replay', rows = false, acceptStall, target, ...opts } = {}) {
  const sanitized = sanitizeReplay(text, label);
  const objects = createdObjects(sanitized);
  // WHERE IT RUNS (13 Nov 2026, scripts/lib/replay_guard.mjs): the local database whenever one is configured
  // (QD_LOCAL_DB_URL), production otherwise or when target: 'production' says so; on production, behind the guard.
  const url = target === 'production' ? null : (target?.startsWith?.('postgres') ? target : process.env.QD_LOCAL_DB_URL || null);
  const plan = url ? { prelude: '', text: sanitized } : planReplay(sanitized, { label, acceptStall: stallAccepted({ acceptStall }) });
  const body = plan.text;
  const run = (q) => (url ? sendLocal(url, q) : send(q, opts));
  const fp = (o) => (url ? localFingerprint(url, o) : fingerprint(o, opts));
  const before = await fp(objects);
  let failure = null;
  const request = plan.prelude + (rows ? rowsBody(body, label) : body) + TAIL;
  // ONE AT A TIME: a replay that finds another holding production waits its turn here, outside any transaction, never
  // inside one where it would hold its own locks while it waits. 40 x 3 s = 2 minutes, then it says so.
  for (let turn = 0; ; turn++) {
    failure = null;
    try { await run(request); } catch (e) { failure = e; }
    if (!(failure && String(failure?.body ?? failure?.message ?? failure).includes(BUSY_MARK)) || turn >= 40) break;
    await new Promise((r) => setTimeout(r, 3000));
  }
  const after = await fp(objects);
  if (before !== after) {
    throw new Error(`SAFE REPLAY: ${label} CHANGED PRODUCTION. The routines/relations it creates `
      + `(${[...objects.routines, ...objects.relations].slice(0, 8).join(', ')}) fingerprint differently before and after `
      + 'a request that must roll back. Check routine_change_log now; an apply elsewhere at the same moment is the only innocent cause.');
  }
  if (!failure) throw new Error(`SAFE REPLAY: ${label} returned without raising, so it did not roll back`);
  if (rows) { const r = rowsFrom(failure); if (r) return r; }
  throw failure;
}
