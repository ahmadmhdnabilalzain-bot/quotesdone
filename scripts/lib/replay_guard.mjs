// A REHEARSAL NEVER MAKES A LIVE USER WAIT (it_engineer, 13 Nov 2026).
//
// MEASURED on production, 13 Nov 2026 (postgres logs, read-only): between 05:30 and 09:29 UTC there were 218 "still waiting
// for ... lock" lines, and 217 of them waited behind a management-API session: 103 live PostgREST requests behind 28
// distinct holders, 11 pg_cron jobs, the rest other rehearsals. Those holders were rolled-back rehearsals sent through
// safe_replay.mjs: a whole file of DDL on hot tables (the sales_engineer W2 file: ALTER TABLE inquiries ADD COLUMN, ALTER
// TABLE quotes DROP/ADD CONSTRAINT, DROP/CREATE TRIGGER on quotes, ALTER COLUMN ... DROP NOT NULL) plus a 12-15 s probe in
// ONE transaction, run eight times in 25 minutes while its probe kept failing. A lock taken by DDL is held until the final
// raise, so for 12-15 s at a time every reader of quotes/inquiries/transactions queued, and the functions' own 8 s
// statement_timeout (role authenticator) killed them:
//   07:46:10 a supplier's signed-agreement certificate write on leads (the gate it fires inserts a notice whose trigger
//            reads quotes; queued behind pid 1717167 = the W2 rehearsal): compliance_archive cert_record_failed, 11.1 s;
//   08:11:08 a supplier's spec_fill at the hold desk (fn_customer_support_takes_delivery read inquiries behind pid
//            1720813): supplier_api unexpected_error, 11.3 s;
//   08:03 and 08:08: 22 and 7 timeouts in one minute, customer dashboards and project reads, plain SELECTs.
// Reproduced on a local Postgres (alter table quotes add column if not exists + a 12 s probe): a live SELECT on quotes was
// cancelled at 8.04 s. lock_timeout alone does not help: the rehearsal gets its lock at once and then HOLDS it.
//
// So a replay sent to production now carries, in front of the caller's text (one line, so error line numbers still match):
//   * lock_timeout 1 s: a rehearsal never queues in front of live readers waiting for its own lock;
//   * a transaction_timeout (Postgres 17: set inside the transaction it bounds the whole transaction; measured on
//     production 13 Nov: set local transaction_timeout = '2s' then 1 s + 1.5 s of pg_sleep was terminated) of 120 s, and
//     of 5 s when the text takes a strong lock on a hot table, so no lock is ever held longer than that;
//   * one rehearsal at a time (a transaction-scoped advisory lock; a busy one is retried by safe_replay, never queued);
// and a text whose DDL takes a strong lock on a hot table is REFUSED unless the operator says he accepts a short stall
// (acceptStall / QD_REPLAY_ACCEPT_STALL=1). Rehearse such a file on the local database (QD_LOCAL_DB_URL, built by
// scripts/db/local_from_mirror.mjs), which is the default whenever one is configured.
//
// Row locks taken by a routine replay are a different subject: scripts/lib/replay_locks.mjs.
import { maskSql } from './sql_text.mjs';

// THE HOT TABLES: read by a person's request every second. From pg_stat_user_tables on production, 13 Nov 2026 (reads =
// seq_scan + idx_scan since the last reset): knowledge_vector_ml 216 M, lead_email_check 96 M, email_domain_mx 26 M,
// doc_backups 23 M, leads 16.5 M, agent_runs 13 M, notifications 12 M, supplier_capabilities 9.7 M, agent_actions 7.3 M,
// documents 7.3 M, quote_pdf_cache 7.1 M, reveal_invoices 7.1 M, customers 5.9 M, it_engineer_finding 2.9 M, inquiries
// 2.1 M; plus the tables every quotation and payment path reads (quotes, quote_lines, quote_spec_hold, transactions) and the
// sign-in tables. A table not listed is not safe because it is quiet today: the transaction_timeout still bounds it.
export const HOT_TABLES = new Set([
  'leads', 'customers', 'inquiries', 'quotes', 'quote_lines', 'quote_spec_hold', 'transactions', 'notifications',
  'doc_backups', 'agent_runs', 'agent_actions', 'supplier_capabilities', 'documents', 'knowledge_vector_ml',
  'lead_email_check', 'email_domain_mx', 'quote_pdf_cache', 'reveal_invoices', 'it_engineer_finding', 'company_event',
  'app_secrets', 'pricing_config', 'login_otp', 'conversation_turn',
]);

export const LOCK_TIMEOUT = '1s';
export const HOLD_LIMIT_HOT = '5s';
export const HOLD_LIMIT = '120s';
export const ONE_AT_A_TIME = 'qd_safe_replay_one_at_a_time';
export const BUSY_MARK = 'SAFE_REPLAY_BUSY';

const T = '((?:"?[a-z_][a-z0-9_$]*"?\\.)?"?[a-z_][a-z0-9_$]*"?)';
// Each statement shape that takes ACCESS EXCLUSIVE, or SHARE / SHARE ROW EXCLUSIVE (which stops every writer), on a table.
const STRONG = [
  [new RegExp(`^alter table (?:if exists )?(?:only )?${T}`), 'ALTER TABLE'],
  [new RegExp(`^drop trigger (?:if exists )?\\S+ on (?:only )?${T}`), 'DROP TRIGGER'],
  [new RegExp(`^create (?:or replace )?(?:constraint )?trigger \\S+ .*? on (?:only )?${T}`), 'CREATE TRIGGER'],
  [new RegExp(`^create (?:unique )?index (?!concurrently)(?:if not exists )?(?:\\S+ )?on (?:only )?${T}`), 'CREATE INDEX'],
  [new RegExp(`^(?:create|drop|alter) policy (?:if exists )?\\S+ on ${T}`), 'POLICY'],
  [new RegExp(`^lock (?:table )?(?:only )?${T}`), 'LOCK TABLE'],
  [new RegExp(`^truncate (?:table )?(?:only )?${T}`), 'TRUNCATE'],
  [new RegExp(`^drop table (?:if exists )?${T}`), 'DROP TABLE'],
  [new RegExp(`^(?:reindex table|cluster) ${T}`), 'REINDEX / CLUSTER'],
  [new RegExp(`^create (?:or replace )?rule \\S+ as on \\S+ to ${T}`), 'CREATE RULE'],
];
const bare = (n) => n.replace(/"/g, '').toLowerCase().replace(/^public\./, '');

/** Every statement of the text that takes a strong table lock: [{ line, kind, table, hot }]. Code inside $bodies$ is not read. */
export function strongTableLocks(text) {
  const s = String(text); const mask = maskSql(s); const out = [];
  let from = 0;
  for (let at = 0; at <= mask.length; at++) {
    if (at < mask.length && mask[at] !== ';') continue;
    const code = mask.slice(from, at).trim().toLowerCase().replace(/\s+/g, ' ');
    for (const [re, kind] of STRONG) {
      const m = re.exec(code);
      if (m) {
        const start = from + Math.max(0, mask.slice(from, at).search(/\S/));
        const table = bare(m[1]);
        out.push({ line: s.slice(0, start).split('\n').length, kind, table, hot: HOT_TABLES.has(table) });
        break;
      }
    }
    from = at + 1;
  }
  return out;
}

/** The statements that would stall live users: strong locks on a hot table the text does not itself create. */
export function stallsLiveUsers(text) {
  const created = new Set([...maskSql(String(text)).matchAll(new RegExp(`\\bcreate (?:unlogged )?table (?:if not exists )?${T}`, 'gi'))].map((m) => bare(m[1])));
  return strongTableLocks(text).filter((l) => l.hot && !created.has(l.table));
}

// A caller's text may tighten the limits, never loosen them: a later SET would override the guard's own line.
// 41 committed scripts/sql files set their own lock_timeout (250 ms to 15 s, counted 13 Nov 2026) for their real apply,
// and the gate replays them, so a STATEMENT that sets it above 1 s is lowered to 1 s IN THE REPLAY ONLY (a stricter
// replay, the same text otherwise, on the same line). A routine's own SET attribute is not a statement and is left alone.
// A transaction_timeout in the text would lift the hold limit, and nothing committed sets one: that is refused.
const SET_LOCK = /^(\s*)set\s+(?:local\s+|session\s+)?lock_timeout\s*(?:=|to)\s*'?\s*(\d+)\s*(ms|s|min)?\s*'?\s*$/i;
const toMs = (n, u) => (u === 'min' ? Number(n) * 60000 : u === 's' ? Number(n) * 1000 : Number(n));

/** The text with every standalone lock_timeout above 1 s (or 0) lowered to 1 s; throws on a transaction_timeout. */
export function tightenLimits(text, label = 'the replay') {
  const s = String(text); const mask = maskSql(s);
  if (/\btransaction_timeout\b/i.test(mask)) {
    throw new Error(`SAFE REPLAY REFUSED: ${label} sets its own transaction_timeout; on production the guard owns it `
      + '(scripts/lib/replay_guard.mjs). Remove the line.');
  }
  let out = ''; let from = 0;
  for (let at = 0; at <= mask.length; at++) {
    if (at < mask.length && mask[at] !== ';') continue;
    // the mask says it is a statement (not text inside a $body$ or a string); the real text gives the value
    const piece = s.slice(from, at); const start = Math.max(0, mask.slice(from, at).search(/\S/));
    const stmt = piece.slice(start);
    const m = /^\s*set\s+(?:local\s+|session\s+)?lock_timeout\b/i.test(mask.slice(from, at)) ? SET_LOCK.exec(stmt) : null;
    out += (m && (toMs(m[2], m[3]?.toLowerCase()) > 1000 || Number(m[2]) === 0)
      ? piece.slice(0, start) + `set local lock_timeout = '${LOCK_TIMEOUT}'`
      : piece) + (at < mask.length ? ';' : '');
    from = at + 1;
  }
  return out;
}

/** One line, put in front of the caller's text, so the text's own line numbers do not move. */
export function guardPrelude({ hot = false } = {}) {
  return `set local lock_timeout = '${LOCK_TIMEOUT}'; set local transaction_timeout = '${hot ? HOLD_LIMIT_HOT : HOLD_LIMIT}'; `
    + `do $qd_one$ begin if not pg_try_advisory_xact_lock(hashtext('${ONE_AT_A_TIME}')) then raise exception '${BUSY_MARK}: another rehearsal holds production; this one waits its turn'; end if; end $qd_one$; `;
}

/** acceptStall from the caller, or from the operator's environment for one command line. */
export const stallAccepted = (opts = {}) => opts.acceptStall === true || process.env.QD_REPLAY_ACCEPT_STALL === '1';

/** Decide, before anything is sent: the prelude to use, or a refusal naming each statement. */
export function planReplay(text, { label = 'the replay', acceptStall = false } = {}) {
  const tightened = tightenLimits(text, label);
  const stalls = stallsLiveUsers(text);
  if (stalls.length && !acceptStall) {
    throw new Error(`SAFE REPLAY REFUSED: ${label} takes a strong lock on a hot table, which makes every live request on it wait until `
      + `the replay ends: ${stalls.slice(0, 6).map((l) => `line ${l.line} ${l.kind} ${l.table}`).join('; ')}. Rehearse it on the local `
      + 'database (QD_LOCAL_DB_URL; scripts/db/local_from_mirror.mjs), or, if a stall of at most ' + HOLD_LIMIT_HOT + ' is acceptable now, pass '
      + 'acceptStall (QD_REPLAY_ACCEPT_STALL=1): the whole replay is then cut at ' + HOLD_LIMIT_HOT + '.');
  }
  return { prelude: guardPrelude({ hot: stalls.length > 0 }), text: tightened, stalls };
}
