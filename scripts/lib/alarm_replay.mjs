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

export function replaySql(name, def, entry, at, stage = '', prelude = '') {
  let body = def
    .replace(new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${name}\\s*\\(`, 'i'), `create function pg_temp.qd_replay_${name}(`)
    .replace(/\bnow\(\)|\bclock_timestamp\(\)|\bcurrent_timestamp\b|\btransaction_timestamp\(\)|\bstatement_timestamp\(\)/gi, 'pg_temp.qd_asof()')
    .replace(/\bpublic\.fn_it_engineer_finding_upsert\s*\(/gi, 'pg_temp.qd_quiet_capture(');
  // entry.stub: calls the replayed body must NOT make on the live database, replaced by a constant. A call that takes a
  // row lock on a live table holds it for the whole replay transaction, and a live caller that skips locked rows then
  // silently skips that work (19 Oct 2026: fn_seat_duty_run under the fn_seat_duties_tick replay).
  for (const [fn, value] of Object.entries(entry.stub ?? {})) body = body.replace(new RegExp(`\\b${fn.replace('.', '\\.')}\\s*\\([^()]*\\)`, 'gi'), value);
  for (const t of Object.keys(entry.asOf ?? {})) body = body.replace(new RegExp(`\\bpublic\\.${t}\\b`, 'g'), `pg_temp.qd_asof_${t}`);
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
export async function replay(sql, name, entry, at, stage = '', pending = null) {
  const live = (await sql(`select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                           where n.nspname = 'public' and p.proname = ${lit(name)}`))?.[0]?.d;
  const def = pending?.def ?? live;
  assert.ok(def, `${name} is not in production`);
  let message = '';
  // A LIVE routine's replay is retried on 429/5xx like any read: it is seconds long, writes only temp objects and
  // rows the raise rolls back, so a second copy cannot deadlock the first. A PENDING routine's replay is NOT retried:
  // its prelude is the whole pending file - ALTER TABLE, DROP/CREATE TRIGGER, routine replacements and any at-apply
  // step - all rolled back by the same raise, but DDL taking table locks, which is the replay hazard db.mjs names.
  try { await sql(replaySql(name, def, entry, at, stage, pending?.file ?? ''), { retry: !pending }); message = 'the replay returned without raising, so it did not roll back'; }
  catch (e) { message = String(e.message); }
  const chk = message.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(chk, `${name} at ${at}: ${message.slice(0, 1500)}`);
  return JSON.parse(chk[1].replace(/\\"/g, '"'));
}
