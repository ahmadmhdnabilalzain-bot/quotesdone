// A REHEARSAL NEVER MAKES A LIVE USER WAIT (it_engineer, 13 Nov 2026; rewritten after independent review the same day).
//
// MEASURED on production, 13 Nov 2026 (postgres logs, read-only): between 05:30 and 09:29 UTC there were 218 "still waiting
// for ... lock" lines, and 217 of them waited behind a management-API session: 103 live PostgREST requests behind 28
// distinct holders, 11 pg_cron jobs, the rest other rehearsals. Those holders were rolled-back rehearsals sent through
// safe_replay.mjs: a whole file of DDL on hot tables (the sales_engineer W2 file: ALTER TABLE inquiries ADD COLUMN, ALTER
// TABLE quotes DROP/ADD CONSTRAINT, DROP/CREATE TRIGGER on quotes, ALTER COLUMN ... DROP NOT NULL) plus a 12-15 s probe in
// ONE transaction, run eight times in 25 minutes while its probe kept failing. A lock taken by DDL is held until the final
// raise, so for 12-15 s at a time every reader of quotes/inquiries/transactions queued, and the functions' own 8 s
// statement_timeout (role authenticator) killed them:
//   07:46:10 a supplier's signed-agreement certificate write on leads (compliance_archive cert_record_failed, 11.1 s);
//   08:11:08 a supplier's spec_fill at the hold desk (fn_customer_support_takes_delivery read inquiries): 11.3 s;
//   08:47    a customer's acceptance of the terms (kyc discarded the write's error and let him into his dashboard);
//   08:03 and 08:08: 22 and 7 timeouts in one minute, customer dashboards and project reads, plain SELECTs.
//
// THE FIRST VERSION OF THIS GUARD RECOGNISED DDL BY REGEX ON A HOT-TABLE LIST, and review showed (local Postgres 16 built from
// the mirror) that quoted names, DDL inside DO/EXECUTE or a called function, DROP INDEX, a new table that REFERENCES a hot one,
// CREATE OR REPLACE VIEW, the second table of TRUNCATE a, b / LOCK a, b, storage/auth tables, CREATE TABLE IF NOT EXISTS of an
// existing table, and the row locks of UPDATE/DELETE all passed with a 120 s hold; a live reader behind a missed ALTER plus a
// 12 s probe was cancelled at 8.03 s. Three of its 24 "hot tables" were not tables, nine busy ones were missing.
//
// SO THE GUARD NO LONGER DEPENDS ON RECOGNISING ANYTHING. Every replay sent to production carries, in front of the text (one
// line, so error line numbers still match):
//   * transaction_timeout = 5 s (Postgres 17; set inside the transaction it bounds the whole transaction from that moment:
//     measured on production 13 Nov, `set local transaction_timeout = '2s'` then 2.5 s of pg_sleep was terminated). Whatever
//     the text locks, by whatever route, row locks included, is released within 5 s, under the live role's 8 s timeout;
//   * lock_timeout = 1 s: a replay never queues in front of live readers waiting for its own lock;
//   * one replay at a time (a transaction-scoped advisory lock; a busy one is re-sent by safe_replay, never queued).
// A replay that needs longer than 5 s runs on the LOCAL database (scripts/db/local_pg16.mjs), full stop.
//
// The static reading below is only an EARLY, FRIENDLY refusal: a statement that takes a lock stronger than ROW EXCLUSIVE that
// stops writers (SHARE, SHARE ROW EXCLUSIVE, EXCLUSIVE, ACCESS EXCLUSIVE) on ANY relation that exists on production is refused
// before anything is sent, so the operator learns it in a second instead of after a 5 s stall. The existing relations are
// read from pg_class with one light SELECT (relationCatalogue), never from a list. Quoted names are read as names; DO bodies
// and their EXECUTE strings are read too. What it cannot see (DDL in a routine the file calls) is still cut at 5 s.
// SHARE UPDATE EXCLUSIVE (COMMENT ON, CREATE STATISTICS) is not refused: it conflicts with neither a reader nor a writer.
//
// Row locks taken by a routine replay are a different subject: scripts/lib/replay_locks.mjs.
import { maskSql } from './sql_text.mjs';

export const LOCK_TIMEOUT = '1s';
export const REPLAY_LIMIT = '5s';
// A real apply (scripts/apply_sql.mjs) is not a rehearsal: it must commit, so it gets 60 s when it takes a strong lock.
// Its lock_timeout is 1500 ms unless the operator passes --lock-timeout=<ms> (decided 13 Nov 2026, guard fix round, item 4);
// the file's own lock_timeout is lowered to the same value, and the apply prints what it set (applyPrelude).
export const APPLY_LOCK_CAP = '1500ms';
export const APPLY_LOCK_MAX_MS = 15000;
export const APPLY_HOLD_LIMIT = '60s';
export const ONE_AT_A_TIME = 'qd_safe_replay_one_at_a_time';
export const BUSY_MARK = 'SAFE_REPLAY_BUSY';
export const LOCAL_COMMAND = 'node scripts/db/local_pg16.mjs start && export QD_LOCAL_DB_URL="$(node scripts/db/local_pg16.mjs url)"';

// ---------------------------------------------------------------------------------------------------------------------------
// A SQL LEXER that keeps what sql_text.mjs's mask blanks: a quoted identifier is a NAME ("public"."quotes" is quotes), a string
// keeps its text (an EXECUTE 'alter table ...' is read), a $tag$ body keeps its text (a DO block is read).
// token: { t: 'word' | 'qid' | 'str' | 'body' | 'num' | 'p', v, pos }
export function lex(sql) {
  const s = String(sql); const n = s.length; const out = []; let i = 0;
  const isId = (c) => /[A-Za-z0-9_$]/.test(c ?? '');
  while (i < n) {
    const c = s[i], d = s[i + 1];
    if (/\s/.test(c)) { i++; continue; }
    if (c === '-' && d === '-') { const e = s.indexOf('\n', i); i = e < 0 ? n : e; continue; }
    if (c === '/' && d === '*') {
      let depth = 1; i += 2;
      while (i < n && depth) { if (s[i] === '/' && s[i + 1] === '*') { depth++; i += 2; } else if (s[i] === '*' && s[i + 1] === '/') { depth--; i += 2; } else i++; }
      continue;
    }
    const at = i;
    if ((c === 'E' || c === 'e') && d === "'" && !isId(s[i - 1])) {
      i += 2; let v = '';
      while (i < n) { if (s[i] === '\\') { v += s[i + 1] ?? ''; i += 2; continue; } if (s[i] === "'") { if (s[i + 1] === "'") { v += "'"; i += 2; continue; } i++; break; } v += s[i++]; }
      out.push({ t: 'str', v, pos: at }); continue;
    }
    if (c === "'") {
      i++; let v = '';
      while (i < n) { if (s[i] === "'") { if (s[i + 1] === "'") { v += "'"; i += 2; continue; } i++; break; } v += s[i++]; }
      out.push({ t: 'str', v, pos: at }); continue;
    }
    if (c === '"') {
      i++; let v = '';
      while (i < n) { if (s[i] === '"') { if (s[i + 1] === '"') { v += '"'; i += 2; continue; } i++; break; } v += s[i++]; }
      out.push({ t: 'qid', v, pos: at }); continue;
    }
    if (c === '$' && !isId(s[i - 1])) {
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(s.slice(i, i + 80));
      if (m) {
        const e = s.indexOf(m[0], i + m[0].length);
        out.push({ t: 'body', v: s.slice(i + m[0].length, e < 0 ? n : e), pos: at, end: e < 0 ? n : e + m[0].length });
        i = e < 0 ? n : e + m[0].length; continue;
      }
    }
    if (/[A-Za-z_\u0080-￿]/.test(c)) { let j = i + 1; while (j < n && /[A-Za-z0-9_$\u0080-￿]/.test(s[j])) j++; out.push({ t: 'word', v: s.slice(i, j).toLowerCase(), pos: at }); i = j; continue; }
    if (/[0-9]/.test(c)) { let j = i + 1; while (j < n && /[0-9.]/.test(s[j])) j++; out.push({ t: 'num', v: s.slice(i, j), pos: at }); i = j; continue; }
    out.push({ t: 'p', v: c, pos: at }); i++;
  }
  return out;
}

/** The statements of a text: arrays of tokens, split on top-level `;`. */
export function statements(sql) {
  const out = []; let cur = [];
  for (const t of lex(sql)) { if (t.t === 'p' && t.v === ';') { if (cur.length) out.push(cur); cur = []; } else cur.push(t); }
  if (cur.length) out.push(cur);
  return out;
}

export const STRONG_MODES = new Set(['SHARE', 'SHARE ROW EXCLUSIVE', 'EXCLUSIVE', 'ACCESS EXCLUSIVE']);
const NOT_A_NAME = new Set(['only', 'if', 'exists', 'not', 'table', 'on', 'cascade', 'restrict', 'in', 'nowait', 'concurrently', 'using']);

// A relation name at toks[i]: word or "quoted", optionally schema-qualified. null when the token is not a name (a %I).
function readName(toks, i) {
  const a = toks[i]; if (!a || !(a.t === 'word' || a.t === 'qid') || (a.t === 'word' && NOT_A_NAME.has(a.v))) return null;
  if (toks[i + 1]?.v === '.' && (toks[i + 2]?.t === 'word' || toks[i + 2]?.t === 'qid')) return { name: `${a.v}.${toks[i + 2].v}`, next: i + 3 };
  return { name: a.v, next: i + 1 };
}

// The locks ONE statement takes, by what it says: [{ name: 'schema.rel' | 'rel' | '?', mode, kind }].
function locksOf(toks, dynamic = false) {
  const out = []; let i = 1;
  const w = (k) => (toks[k]?.t === 'word' ? toks[k].v : null);
  const add = (name, mode, kind) => out.push({ name: name ?? '?', mode, kind: name ? kind : `${kind}, on a name built at run time`, dynamic: dynamic || !name });
  const eat = (...ws) => (ws.includes(w(i)) ? (i++, true) : false);
  const eatIf = () => { if (w(i) === 'if' && w(i + 1) === 'exists') i += 2; else if (w(i) === 'if' && w(i + 1) === 'not' && w(i + 2) === 'exists') i += 3; };
  const name = () => { eat('only'); const r = readName(toks, i); if (r) i = r.next; if (toks[i]?.v === '*') i++; return r?.name ?? null; };
  const list = () => { const names = []; for (;;) { names.push(name()); if (toks[i]?.v === ',') { i++; continue; } return names; } };
  const after = (word) => { for (let k = i; k < toks.length; k++) if (w(k) === word) return k; return -1; };
  const at = (word, kind, mode) => { const k = after(word); if (k >= 0) { i = k + 1; add(name(), mode, kind); } return out; };
  const refs = () => { for (let k = i; k < toks.length; k++) if (w(k) === 'references') add(readName(toks, k + 1)?.name, 'SHARE ROW EXCLUSIVE', 'REFERENCES'); };
  const head = w(0);
  if (head === 'alter') {
    if (eat('table')) { if (w(i) === 'all') return out; eatIf(); add(name(), 'ACCESS EXCLUSIVE', 'ALTER TABLE'); refs(); return out; }
    if (eat('trigger', 'policy', 'rule')) return at('on', `ALTER ${toks[1].v.toUpperCase()}`, 'ACCESS EXCLUSIVE');
    if (w(i) === 'materialized' && w(i + 1) === 'view') i += 2; else if (w(i) === 'foreign' && w(i + 1) === 'table') i += 2;
    else if (!eat('index', 'view', 'sequence')) return out;
    eatIf(); add(name(), 'ACCESS EXCLUSIVE', `ALTER ${toks[1].v.toUpperCase()}`); return out;
  }
  if (head === 'drop') {
    if (eat('trigger', 'rule', 'policy')) return at('on', `DROP ${toks[1].v.toUpperCase()}`, 'ACCESS EXCLUSIVE');
    if (eat('schema')) { eatIf(); for (const n of list()) if (n) out.push({ schema: n, name: `${n}.*`, mode: 'ACCESS EXCLUSIVE', kind: 'DROP SCHEMA' }); return out; }
    if (w(i) === 'materialized' && w(i + 1) === 'view') i += 2; else if (w(i) === 'foreign' && w(i + 1) === 'table') i += 2;
    else if (!eat('table', 'view', 'index', 'sequence')) return out;
    if (eat('concurrently')) return out;   // refused by safe_replay.mjs: it cannot run in a transaction
    eatIf(); for (const n of list()) add(n, 'ACCESS EXCLUSIVE', `DROP ${toks[1].v.toUpperCase()}`); return out;
  }
  if (head === 'create') {
    const replace = w(1) === 'or' && w(2) === 'replace'; if (replace) i = 3;
    while (eat('temp', 'temporary', 'unlogged', 'global', 'local', 'recursive', 'unique', 'constraint')) { /* modifiers */ }
    if (eat('trigger')) return at('on', 'CREATE TRIGGER', 'SHARE ROW EXCLUSIVE');
    if (eat('index')) return w(i) === 'concurrently' ? out : at('on', 'CREATE INDEX', 'SHARE');
    if (eat('policy')) return at('on', 'CREATE POLICY', 'ACCESS EXCLUSIVE');
    if (eat('rule')) return at('to', 'CREATE RULE', 'ACCESS EXCLUSIVE');
    if (eat('view')) { if (replace) add(name(), 'ACCESS EXCLUSIVE', 'CREATE OR REPLACE VIEW'); return out; }
    if (eat('table')) {
      refs();
      for (let k = i; k < toks.length; k++) if (w(k) === 'partition' && w(k + 1) === 'of') add(readName(toks, k + 2)?.name, 'ACCESS EXCLUSIVE', 'CREATE TABLE ... PARTITION OF');
    }
    return out;
  }
  if (head === 'truncate') { eat('table'); for (const n of list()) add(n, 'ACCESS EXCLUSIVE', 'TRUNCATE'); return out; }
  if (head === 'lock') {
    eat('table'); const names = list(); let mode = 'ACCESS EXCLUSIVE';
    if (eat('in')) { const m = []; while (i < toks.length && w(i) && w(i) !== 'mode') m.push(toks[i++].v); mode = m.join(' ').toUpperCase(); }
    for (const n of names) add(n, mode, 'LOCK');
    return out;
  }
  if (head === 'reindex') {
    if (toks[i]?.v === '(') { while (i < toks.length && toks[i].v !== ')') i++; i++; }
    if (eat('table', 'index') && !eat('concurrently')) add(name(), 'ACCESS EXCLUSIVE', 'REINDEX');
    return out;
  }
  if (head === 'cluster') { if (toks[i]) add(name(), 'ACCESS EXCLUSIVE', 'CLUSTER'); return out; }
  if (head === 'refresh' && w(1) === 'materialized' && w(2) === 'view') { i = 3; const conc = eat('concurrently'); add(name(), conc ? 'EXCLUSIVE' : 'ACCESS EXCLUSIVE', 'REFRESH MATERIALIZED VIEW'); }
  return out;
}

const HEADS = new Set(['alter', 'drop', 'create', 'truncate', 'lock', 'reindex', 'cluster', 'refresh']);
// in plpgsql a statement can follow these without a `;` of its own
const BLOCK_WORDS = new Set(['begin', 'then', 'else', 'loop', 'declare']);

/** Every lock a text takes by what it says, top-level and inside DO blocks (with their EXECUTE strings), with its line. */
export function statedLocks(text) {
  const s = String(text); const out = [];
  const scanBody = (body, line, dynamic) => {
    for (const st of statements(body)) {
      const k = st.findIndex((t, j) => t.t === 'word' && HEADS.has(t.v) && (j === 0 || (st[j - 1].t === 'word' && BLOCK_WORDS.has(st[j - 1].v))));
      if (k >= 0) for (const l of locksOf(st.slice(k), dynamic)) out.push({ ...l, line });
      // EXECUTE 'sql' / EXECUTE format('sql %I', x): the strings are SQL, and a %I/%s where a name goes is a name built at run time
      if (st.some((t) => t.t === 'word' && t.v === 'execute')) {
        for (const t of st) if (t.t === 'str' || t.t === 'body') scanText(t.v.replace(/%[ILs]/g, ' % '), line, true);
      }
    }
  };
  const scanText = (sql, lineOverride, dynamic) => {
    for (const st of statements(sql)) {
      const line = lineOverride ?? s.slice(0, st[0].pos).split('\n').length;
      if (st[0].t === 'word' && st[0].v === 'do') {
        const b = st.find((t) => t.t === 'body' || t.t === 'str');
        if (b) scanBody(b.v, line, dynamic);
        continue;
      }
      for (const l of locksOf(st, dynamic)) out.push({ ...l, line });
    }
  };
  scanText(s, null, false);
  return out;
}

// ---------------------------------------------------------------------------------------------------------------------------
// THE EXISTING RELATIONS, read once per process with one light SELECT: every table, view, matview, foreign table, sequence and
// index outside the catalogues, an index carrying the table it belongs to (a lock on an index is felt by its table's readers).
export const CATALOGUE_SQL = `select /* qd_relation_catalogue */ string_agg(n.nspname || '.' || c.relname
       || coalesce('>' || tn.nspname || '.' || t.relname, ''), ',') as relations
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  left join pg_index ix on ix.indexrelid = c.oid left join pg_class t on t.oid = ix.indrelid
  left join pg_namespace tn on tn.oid = t.relnamespace
 where c.relkind in ('r','p','v','m','f','S','i','I')
   and n.nspname not in ('pg_catalog','information_schema') and n.nspname !~ '^pg_(toast|temp)'`;

/** { has(name), tableOf(name), schemaHasAny(schema) } from CATALOGUE_SQL's one row. */
export function catalogueFrom(row) {
  const map = new Map();
  for (const e of String(row?.relations ?? '').split(',').filter(Boolean)) { const [r, t] = e.split('>'); map.set(r, t ?? r); }
  if (!map.size) throw new Error('the relation catalogue of production came back empty; the replay is not planned on nothing');
  return { size: map.size, has: (n) => map.has(n), tableOf: (n) => map.get(n) ?? n, schemaHasAny: (sc) => [...map.keys()].some((k) => k.startsWith(`${sc}.`)) };
}
let cached = null;
/** The catalogue of production, read once per process through `read(query)` (a read-only send). */
export function relationCatalogue(read) {
  cached ??= Promise.resolve().then(() => read(CATALOGUE_SQL)).then((rows) => catalogueFrom(Array.isArray(rows) ? rows[0] : rows))
    .catch((e) => { cached = null; throw e; });
  return cached;
}

const qualify = (n) => (n.includes('.') ? n : `public.${n}`);
/** The statements that would stop live writers (and, under ACCESS EXCLUSIVE, readers): strong locks on relations that exist. */
export function stallsLiveUsers(text, catalogue) {
  return statedLocks(text).filter((l) => STRONG_MODES.has(l.mode)).flatMap((l) => {
    if (l.schema) return catalogue.schemaHasAny(l.schema) ? [{ ...l, table: l.name }] : [];
    if (l.name === '?') return [{ ...l, table: '?' }];
    const q = qualify(l.name);
    return catalogue.has(q) ? [{ ...l, table: catalogue.tableOf(q).replace(/^public\./, '') }] : [];
  });
}

// ---------------------------------------------------------------------------------------------------------------------------
// A caller's text may tighten the limits, never loosen them: a later SET would override the guard's own line.
// 41 committed scripts/sql files set their own lock_timeout (250 ms to 15 s, counted 13 Nov 2026) for their real apply, and the
// gate replays them, so every way a statement can raise it is lowered to the cap, on the same line:
//   set [local|session] lock_timeout {=|to} <above the cap | 0 | default>, reset lock_timeout,
//   set_config('lock_timeout', '<above the cap | 0>', ...) anywhere (a value that is not a literal is refused).
// RESET ALL, and anything that names transaction_timeout, would lift the guard's other limit: refused. A routine's own SET
// attribute is not a statement and is left alone (the transaction_timeout still bounds it).
const SET_LOCK = /^\s*set\s+(?:local\s+|session\s+)?lock_timeout\s*(?:=|to)\s*'?\s*([a-z0-9.]+)\s*(ms|s|min)?\s*'?\s*$/i;
const msOf = (v) => { const m = /^\s*(\d+(?:\.\d+)?)\s*(ms|s|min)?\s*$/i.exec(String(v)); if (!m) return null; const u = (m[2] || 'ms').toLowerCase(); return Number(m[1]) * (u === 'min' ? 60000 : u === 's' ? 1000 : 1); };

/** The text with every lock_timeout above `cap` (or 0, or the default) lowered to it; throws on what would lift a limit. */
export function tightenLimits(text, label = 'the replay', { cap = LOCK_TIMEOUT } = {}) {
  const capMs = msOf(cap);
  const refuse = (what) => { throw new Error(`SAFE REPLAY REFUSED: ${label} ${what}; the guard owns that limit on production (scripts/lib/replay_guard.mjs). Remove the line.`); };
  let s = String(text);
  if (/\btransaction_timeout\b/i.test(maskSql(s)) || /set_config\s*\(\s*'transaction_timeout'/i.test(s)) refuse('sets its own transaction_timeout');
  if (/(^|;)\s*reset\s+all\b/i.test(maskSql(s))) refuse('says RESET ALL, which would lift the lock_timeout and the transaction_timeout');
  // a routine's body is not run by the replay (it runs when called, inside the 5 s): its set_config is left alone
  const routineBodies = statements(s).filter((st) => st[0]?.v === 'create' && st.some((t, k) => k < 5 && (t.v === 'function' || t.v === 'procedure')))
    .flatMap((st) => st.filter((t) => t.t === 'body').map((t) => [t.pos, t.end]));
  s = s.replace(/set_config\s*\(\s*'lock_timeout'\s*,\s*([^,)]+)/gi, (all, arg, at) => {
    if (routineBodies.some(([a, b]) => at > a && at < b)) return all;
    const lit = /^\s*'([^']*)'\s*$/.exec(arg);
    if (!lit) refuse(`computes its lock_timeout in set_config (${all.slice(0, 60)})`);
    const ms = msOf(lit[1]); return ms === null || ms === 0 || ms > capMs ? all.replace(arg, `'${cap}'`) : all;
  });
  const mask = maskSql(s); let out = ''; let from = 0;
  for (let at = 0; at <= mask.length; at++) {
    if (at < mask.length && mask[at] !== ';') continue;
    const piece = s.slice(from, at); const start = Math.max(0, mask.slice(from, at).search(/\S/));
    const code = mask.slice(from, at).trim().toLowerCase();
    let lower = false;
    if (/^set\s+(local\s+|session\s+)?lock_timeout\b/.test(code)) {
      const m = SET_LOCK.exec(piece.slice(start));
      const ms = m && m[1].toLowerCase() !== 'default' ? msOf(m[1] + (m[2] ?? '')) : null;
      lower = ms === null || ms === 0 || ms > capMs;            // `to default`, a form this cannot read, 0, or above the cap
    } else if (/^reset\s+lock_timeout\b/.test(code)) lower = true;
    // a statement spread over lines keeps its line count, so the error line numbers after it still match the file
    out += (lower ? piece.slice(0, start) + `set local lock_timeout = '${cap}'` + '\n'.repeat(piece.slice(start).split('\n').length - 1) : piece)
      + (at < mask.length ? ';' : '');
    from = at + 1;
  }
  return out;
}

/** The apply's lock_timeout from its command line: `--lock-timeout=<ms>` (or 1.5s, 800ms), default APPLY_LOCK_CAP. 0 (no limit),
 *  a value above APPLY_LOCK_MAX_MS, or one this cannot read is refused: an apply never waits long in front of live readers. */
export function applyLockTimeout(argv = []) {
  const arg = argv.find((a) => a === '--lock-timeout' || a.startsWith('--lock-timeout='));
  if (!arg) return APPLY_LOCK_CAP;
  const v = arg.includes('=') ? arg.slice(arg.indexOf('=') + 1) : argv[argv.indexOf(arg) + 1];
  const ms = msOf(/^\d+(\.\d+)?$/.test(String(v ?? '').trim()) ? `${v}ms` : v);
  if (ms === null || !(ms > 0) || ms > APPLY_LOCK_MAX_MS) {
    throw new Error(`--lock-timeout=${v ?? ''} is refused: give milliseconds between 1 and ${APPLY_LOCK_MAX_MS} (default ${APPLY_LOCK_CAP})`);
  }
  return `${Math.round(ms)}ms`;
}

/** What a real apply puts in front of the file (one line, so line numbers match) and the sentence it prints about it. */
export function applyPrelude({ lockTimeout = APPLY_LOCK_CAP, holdsStrongLock = false, tag = '' } = {}) {
  const prelude = `set local lock_timeout = '${lockTimeout}'; `
    + (holdsStrongLock ? `set local transaction_timeout = '${APPLY_HOLD_LIMIT}'; ` : '')
    + (tag ? `set application_name = '${String(tag).replace(/[^A-Za-z0-9 ._-]/g, '_')}'; ` : '');
  const said = `limits set: lock_timeout = ${lockTimeout} (the file's own lock_timeout lowered to it)`
    + (holdsStrongLock ? `, transaction_timeout = ${APPLY_HOLD_LIMIT} (it takes a lock that stops writers)` : ', no transaction_timeout (no lock that stops writers)');
  return { prelude, said };
}

/** One line, put in front of the caller's text on production, so the text's own line numbers do not move. */
export function guardPrelude() {
  return `set local lock_timeout = '${LOCK_TIMEOUT}'; set local transaction_timeout = '${REPLAY_LIMIT}'; `
    + `do $qd_one$ begin if not pg_try_advisory_xact_lock(hashtext('${ONE_AT_A_TIME}')) then raise exception '${BUSY_MARK}: another rehearsal holds production; this one waits its turn'; end if; end $qd_one$; `;
}

/** acceptStall from the caller, or from the operator's environment for one command line. */
export const stallAccepted = (opts = {}) => opts.acceptStall === true || process.env.QD_REPLAY_ACCEPT_STALL === '1';

/** Decide, before anything is sent: the prelude and tightened text, or a refusal naming each statement. */
export function planReplay(text, { label = 'the replay', acceptStall = false, catalogue } = {}) {
  if (!catalogue) throw new Error('planReplay needs the relation catalogue of production (relationCatalogue)');
  const tightened = tightenLimits(text, label);
  const stalls = stallsLiveUsers(text, catalogue);
  if (stalls.length && !acceptStall) {
    throw new Error(`SAFE REPLAY REFUSED: ${label} takes a lock that stops live requests on a relation production has: `
      + `${stalls.slice(0, 6).map((l) => `line ${l.line} ${l.kind} ${l.table} (${l.mode})`).join('; ')}${stalls.length > 6 ? `; and ${stalls.length - 6} more` : ''}. `
      + `Rehearse it on the local database: ${LOCAL_COMMAND}, then the same command. Only if a stall of at most ${REPLAY_LIMIT} is `
      + `acceptable now: QD_REPLAY_ACCEPT_STALL=1 (every production replay is cut at ${REPLAY_LIMIT} either way).`);
  }
  return { prelude: guardPrelude(), text: tightened, stalls };
}

// Production cut a replay (transaction_timeout ends the session) or ended its session some other way, or the API answered 5xx.
export const CUT = /transaction timeout|transaction_timeout|25P04|terminating connection|connection (?:was )?(?:terminated|closed|reset)|server closed the connection|HTTP 5\d\d/i;
export function cutError(label, cause) {
  return Object.assign(new Error(`SAFE REPLAY CUT: ${label} did not finish within the ${REPLAY_LIMIT} every production replay is allowed, `
    + 'or production ended its session; it was NOT re-sent, and nothing was committed. A replay that needs longer runs on the local '
    + `database: ${LOCAL_COMMAND}, then the same command. (${String(cause?.message ?? cause).slice(0, 300)})`), { cut: true });
}

// AFTER A 5xx, DID THE APPLY COMMIT? (scripts/apply_sql.mjs, decided 13 Nov 2026). A request is one transaction, so it committed
// all or nothing. `before`/`after`: what the database holds of the file (its routines' bodies, the public shape) before the send
// and once no session carries the apply's tag; `wouldChange`: a routine of the file differed from its live body before the send.
//   changed                  -> 'committed'      (go on to the read-back; the verdict rows were lost with the answer)
//   unchanged, wouldChange   -> 'not committed'  (proven: the all-or-nothing transaction left nothing) -> safe to re-send
//   unchanged, !wouldChange  -> 'unknown'        (a re-apply, DDL outside the digest, data only)        -> never re-sent
export function settleVerdict(before, after, wouldChange) {
  if (before !== after) return 'committed';
  return wouldChange ? 'not committed' : 'unknown';
}
