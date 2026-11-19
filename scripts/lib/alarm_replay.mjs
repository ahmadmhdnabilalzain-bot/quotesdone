// Replays one IT alarm routine at a past instant, inside a transaction that always rolls back.
// The register, the healthy instants and the reasons are in
// scripts/checks/every_alarm_is_quiet_on_a_healthy_day.test.mjs; this file is only the machinery,
// kept apart so any instant can be replayed by hand without running the test.
//
// How: the routine's live definition (pg_get_functiondef) is rebuilt as pg_temp.qd_replay_<name>,
//   - every clock (now(), clock_timestamp(), current_timestamp, ...) reads pg_temp.qd_asof(), the instant;
//   - each table in entry.asOf becomes a pg_temp view holding only the rows written up to the instant;
//   - every fn_it_engineer_finding_upsert call goes to a pg_temp capture instead of the ledger.
// Then entry.replay is called and the transaction is ended by `raise exception 'CHK<<...>>'`, so
// nothing it did commits: the rows `stage` wrote, the temp objects, any close it made.
import assert from 'node:assert/strict';

import { lit } from './db.mjs';

export const DEFAULT_STUBS = {
  'public.fn_seat_duty_run': `'{}'::jsonb`, 'public.fn_seat_duty_isolate': 'null',
  'public.fn_seat_handoff': 'null::bigint', 'public.fn_seat_handoff_act': `'{}'::jsonb`,
  'public.fn_seat_handoff_complete': 'null', 'public.fn_customer_support_takes_delivery': 'null',
  'public.enqueue_supplier_invites': 'null', 'public.fn_ceo_improvement_open': 'null',
  'public.fn_ceo_improvement_close': 'null', 'public.fn_seat_deliberation_close': 'null',
};

/** Replace every call `fn(...)` in sql by `value`, matching the call's parentheses even when they nest. */
export function stubCalls(sql, fn, value) {
  const re = new RegExp(`\\b${fn.replace(/\./g, '\\.')}\\s*\\(`, 'gi');
  // in-string positions: a name quoted inside a message text is not a call
  // (a `--` comment is skipped, so an apostrophe in prose never flips the string state)
  const inStr = new Uint8Array(sql.length + 1); let qs = false;
  for (let k = 0; k < sql.length; k++) {
    if (!qs && sql[k] === '-' && sql[k + 1] === '-') { while (k < sql.length && sql[k] !== '\n') inStr[k++] = 1; continue; }
    if (sql[k] === "'") qs = !qs; inStr[k] = qs ? 1 : 0;
  }
  let out = ''; let from = 0; let m;
  while ((m = re.exec(sql))) {
    if (inStr[m.index]) continue;
    let i = m.index + m[0].length; let depth = 1; let q = false;
    for (; i < sql.length && depth; i++) {
      const ch = sql[i];
      if (ch === "'") q = !q;
      else if (!q && ch === '(') depth++;
      else if (!q && ch === ')') depth--;
    }
    if (depth) break;   // unbalanced: leave the rest untouched
    out += sql.slice(from, m.index) + value; from = i; re.lastIndex = i;
  }
  return out + sql.slice(from);
}

/** Drop FOR UPDATE / FOR SHARE row-lock clauses (with OF, SKIP LOCKED, NOWAIT). */
export const stripRowLocks = (sql) =>
  sql.replace(/\bfor\s+(?:no\s+key\s+)?(?:update|share|key\s+share)(?:\s+of\s+[\w.]+(?:\s*,\s*[\w.]+)*)?(?:\s+(?:skip\s+locked|nowait))?/gi, '');

// entry.callees (27 Oct 2026): public routines the alarm's DECISION is made in, called from its body. A callee runs as
// the live routine, so it read the live tables at today's clock, not the as-of views at the instant: fn_seat_duties_tick
// raises what fn_seat_duty_health returns, and that read today's seat_duty, so a duty registered on 29 Sep and failing
// on 27 Oct "fired" at 14 Sep. Each callee named here is rebuilt the same way as the routine (clock, as-of views,
// capture, stubs, no row locks) as pg_temp.qd_replay_<callee>, and every call to it is sent to the copy.
// calleeDefs = { name: pg_get_functiondef text }.
export function replaySql(name, def, entry, at, stage = '', prelude = '', calleeDefs = {}) {
  const callees = (entry.callees ?? []).map((c) => {
    assert.ok(calleeDefs[c], `${name}: callee ${c} has no definition to replay`);
    return `${rewrite(c, calleeDefs[c], entry, Object.keys(calleeDefs))};`;
  }).join('\n');
  return replayWith(name, rewrite(name, def, entry, Object.keys(calleeDefs)), entry, at, stage, prelude, callees);
}

function rewrite(name, def, entry, callees = []) {
  let body = def
    .replace(new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${name}\\s*\\(`, 'i'), `create function pg_temp.qd_replay_${name}(`)
    .replace(/\bnow\(\)|\bclock_timestamp\(\)|\bcurrent_timestamp\b|\btransaction_timestamp\(\)|\bstatement_timestamp\(\)/gi, 'pg_temp.qd_asof()')
    .replace(/\bpublic\.fn_it_engineer_finding_upsert\s*\(/gi, 'pg_temp.qd_quiet_capture(');
  // entry.stub: calls the replayed body must NOT make on the live database, replaced by a constant. A call that takes a
  // row lock on a live table holds it for the whole replay transaction, and a live caller that skips locked rows then
  // silently skips that work (19 Oct 2026: fn_seat_duty_run under the fn_seat_duties_tick replay). DEFAULT_STUBS are
  // the pure follow-on actions (start, act on, complete a handoff; run a duty), never an alarm's own decision.
  for (const [fn, value] of Object.entries({ ...DEFAULT_STUBS, ...(entry.stub ?? {}) })) body = stubCalls(body, fn, value);
  // A row lock in the replayed body itself is dropped: that body reads its as-of views, and a FOR UPDATE there would
  // hold a live row until the rollback.
  body = stripRowLocks(body);
  // entry.shadow: live tables the replayed body itself writes; it writes a temp copy instead, so it holds no live row.
  for (const t of entry.shadow ?? []) body = body.replace(new RegExp(`\\bpublic\\.${t}\\b`, 'g'), `pg_temp.qd_shadow_${t}`);
  for (const t of Object.keys(entry.asOf ?? {})) body = body.replace(new RegExp(`\\bpublic\\.${t}\\b`, 'g'), `pg_temp.qd_asof_${t}`);
  for (const c of callees) if (c !== name) body = body.replace(new RegExp(`\\bpublic\\.${c}\\s*\\(`, 'gi'), `pg_temp.qd_replay_${c}(`);
  return body;
}

function replayWith(name, body, entry, at, stage, prelude, callees) {
  const shadows = (entry.shadow ?? []).map((t) => `create temp table qd_shadow_${t} as select * from public.${t};`).join('\n');
  const views = Object.entries(entry.asOf ?? {})
    .map(([t, c]) => `create temp view qd_asof_${t} as select * from public.${t} where ${c} < ${lit(at)}::timestamptz;`).join('\n');
  const fromResult = entry.findings
    ? `(select coalesce(jsonb_agg(f->>'detector_key' || ' -- ' || left(f->>'title', 90)), '[]') from jsonb_array_elements(v->'${entry.findings}') f)`
    : `'[]'::jsonb`;
  return `begin;
${prelude}
create function pg_temp.qd_asof() returns timestamptz language sql stable as $a$ select ${lit(at)}::timestamptz $a$;
create temp table qd_quiet_fired (issue_key text, title text);
create function pg_temp.qd_quiet_capture(p_issue_key text, p_title text, p_where text, p_blast text, p_affected integer default 0,
  p_evidence jsonb default '{}', p_ruled_out text[] default '{}', p_undetermined text[] default '{}', p_raised_by text default 'it_engineer')
returns jsonb language plpgsql as $c$ begin insert into qd_quiet_fired values (p_issue_key, p_title); return '{}'::jsonb; end $c$;
${views}
${shadows}
${callees}
${body};
do $q$
declare v jsonb;
begin
  ${stage}
  v := ${entry.replay};
  raise exception 'CHK<<%>>', jsonb_build_object('at', ${lit(at)},
    'fired', ${fromResult} || (select coalesce(jsonb_agg(issue_key || ' -- ' || left(title, 90)), '[]') from qd_quiet_fired))::text;
end $q$;`;
}

// -> { at, fired: ['<key> -- <title>', ...] }
// A ROUTINE STILL WAITING IN scripts/sql/pending/ (29 Sep 2026) is not in production, so the PR that adds it could
// not replay it. `pending` = { file, def }: its pending file's SQL, run first inside the same rolled-back transaction
// (what it calls then exists), and the routine's own definition from that file. The new alarm is replayed before
// it is applied, not discovered loud after.
/** The text of `create or replace function public.<name>(` in a SQL file, up to the next routine of that file, or null. */
export function definitionIn(file, name) {
  if (!file) return null;
  const heads = [...String(file).matchAll(/create\s+or\s+replace\s+function\s+public\.(\w+)\s*\(/gi)];
  const i = heads.findIndex((m) => m[1].toLowerCase() === String(name).toLowerCase());
  return i < 0 ? null : file.slice(heads[i].index, heads[i + 1]?.index ?? file.length);
}

export async function replay(sql, name, entry, at, stage = '', pending = null) {
  const live = (await sql(`select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                           where n.nspname = 'public' and p.proname = ${lit(name)}`))?.[0]?.d;
  const def = pending?.def ?? live;
  assert.ok(def, `${name} is not in production`);
  const calleeDefs = {};
  for (const c of entry.callees ?? []) {
    // a callee the routine's pending file defines is replayed from that file, as the routine is (19 Nov 2026): before the apply
    // it is not in production at all, and after it the file is the definition the replay is checking
    const fromPending = definitionIn(pending?.file, c);
    if (fromPending) { calleeDefs[c] = fromPending; continue; }
    calleeDefs[c] = (await sql(`select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                where n.nspname = 'public' and p.proname = ${lit(c)}`))?.[0]?.d;
    assert.ok(calleeDefs[c], `${name}: its callee ${c} is not in production`);
  }
  let message = '';
  // THROUGH THE ONE DOOR (13 Nov 2026, scripts/lib/safe_replay.mjs + replay_guard.mjs). This sent its text straight to the
  // management API with db.mjs's sql(): a PENDING routine's prelude is its whole pending file (ALTER TABLE, DROP/CREATE
  // TRIGGER, routine replacements) held until the final raise, with no lock_timeout and no time limit, which is the shape that
  // held quotes and inquiries on 13 Nov. It now runs on the local database, or on production only with QD_REPLAY_ON_PRODUCTION=1
  // behind the 5 s guard, sent once.
  const { replaySql: guarded } = await import('./safe_replay.mjs');
  try { await guarded(replaySql(name, def, entry, at, stage, pending?.file ?? '', calleeDefs), { label: `the alarm replay of ${name} at ${at}` }); message = 'the replay returned without raising, so it did not roll back'; }
  catch (e) { message = String(e?.body ?? e?.message ?? e); }
  const chk = message.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(chk, `${name} at ${at}: ${message.slice(0, 1500)}`);
  return JSON.parse(chk[1].replace(/\\"/g, '"'));
}
