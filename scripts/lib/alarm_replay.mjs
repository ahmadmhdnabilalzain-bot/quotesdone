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

export function replaySql(name, def, entry, at, stage = '') {
  let body = def
    .replace(new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${name}\\s*\\(`, 'i'), `create function pg_temp.qd_replay_${name}(`)
    .replace(/\bnow\(\)|\bclock_timestamp\(\)|\bcurrent_timestamp\b|\btransaction_timestamp\(\)|\bstatement_timestamp\(\)/gi, 'pg_temp.qd_asof()')
    .replace(/\bpublic\.fn_it_engineer_finding_upsert\s*\(/gi, 'pg_temp.qd_quiet_capture(');
  for (const t of Object.keys(entry.asOf ?? {})) body = body.replace(new RegExp(`\\bpublic\\.${t}\\b`, 'g'), `pg_temp.qd_asof_${t}`);
  const views = Object.entries(entry.asOf ?? {})
    .map(([t, c]) => `create temp view qd_asof_${t} as select * from public.${t} where ${c} < ${lit(at)}::timestamptz;`).join('\n');
  const fromResult = entry.findings
    ? `(select coalesce(jsonb_agg(f->>'detector_key' || ' -- ' || left(f->>'title', 90)), '[]') from jsonb_array_elements(v->'${entry.findings}') f)`
    : `'[]'::jsonb`;
  return `begin;
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
// `pendingSrc` (29 Sep 2026, sales_engineer, #1106): the text of the scripts/sql/pending file that defines a routine not
// yet in production. The replay then runs that whole file FIRST, inside the same transaction the raise rolls back, and
// replays the definition it creates - so a new alarm is proved quiet on its own PR instead of failing "not in
// production" until the apply. A routine that IS in production is always replayed from production's definition.
export async function replay(sql, name, entry, at, stage = '', pendingSrc = null) {
  let def = (await sql(`select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                         where n.nspname = 'public' and p.proname = ${lit(name)}`))?.[0]?.d;
  let prefix = '';
  if (!def && pendingSrc) {
    const i = pendingSrc.search(new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${name}\\s*\\(`, 'i'));
    const tag = i < 0 ? null : pendingSrc.slice(i).match(/\sas\s+(\$[A-Za-z_]*\$)/i)?.[1];
    const end = tag ? pendingSrc.indexOf(tag, pendingSrc.indexOf(tag, i) + tag.length) : -1;
    if (end > 0) { def = pendingSrc.slice(i, end + tag.length); prefix = pendingSrc + '\n'; }
  }
  assert.ok(def, `${name} is not in production`);
  let message = '';
  // Retried on 429/5xx like any read: a replay is seconds long, writes only temp objects and rows the
  // raise rolls back, so a second copy cannot deadlock the first (the hazard db.mjs names is DDL replays).
  try { await sql(prefix ? 'begin;\n' + prefix + replaySql(name, def, entry, at, stage).replace(/^begin;/, '') : replaySql(name, def, entry, at, stage)); message = 'the replay returned without raising, so it did not roll back'; }
  catch (e) { message = String(e.message); }
  const chk = message.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(chk, `${name} at ${at}: ${message.slice(0, 1500)}`);
  return JSON.parse(chk[1].replace(/\\"/g, '"'));
}
