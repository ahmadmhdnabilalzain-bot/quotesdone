// ONE INCIDENT PER CAUSE, AND NO MODEL ON AN ALARM THAT MEASURES HEALTHY (it_engineer, 16 Nov 2026, founder ledger 1557).
// Measured before (SELECT, 7 days to 16 Nov 2026): 1,916 it_incident rows, of which 1,025 one cause (unconfirmed delivery
// requests) and 614 one cause (resilience_ping heartbeat steps); replayed one-per-cause: 125. resilience_ping's own model
// spend, AED 19.90 for 897 calls, is queued work; the alarm-made share was a postmortem asked once per occurrence and a
// CEO judgement reasoned after its finding had cleared. The file: scripts/sql/a_recurring_fault_is_one_incident_and_a_cleared_alarm_asks_no_model.sql.
// Offline, from the text, this fails when:
//   1. fn_it_incident_open stops counting a recurrence on the open incident of its cause (and writes a row per hand-over again),
//      or loses the customer-facing rule, or stops writing cause_key at open;
//   2. nothing closes an incident whose cause measures healthy, or the 15-minute impact tick stops running it;
//   3. the postmortem re-opens or asks about an occurrence counted on an incident, or re-asks a class after a failed ask;
//   4. a CEO judgement of a cleared IT finding can still reach a model;
//   5. a new routine is not revoked and pinned, or the file enters MANIFEST.txt unapplied.
// LOCAL (QD_LOCAL_DB_URL = a LOCAL Postgres 16 built from the mirror with production's bodies; never production): the file
// applies twice to a copy, and the probe answers PROBE OK twice. The probe also proves, kind by kind, that every alarm the
// founder's rulings still route to him (billing, a credential only he holds, legal, an outage, a person asking for a human)
// still reaches him, and that an IT fault never mails him directly.
//   env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL QD_LOCAL_DB_URL=postgresql://postgres@%2Fdev%2Fshm%2Fpg-L3IT:55440/l3base \
//     node --test scripts/checks/one_incident_per_cause_and_no_model_on_a_healthy_alarm.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const NAME = 'a_recurring_fault_is_one_incident_and_a_cleared_alarm_asks_no_model';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const C = read(FILE).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const body = (name) => {
  const at = C.search(new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${name}\\s*\\(`, 'i'));
  assert.ok(at >= 0, `${FILE} defines ${name}`);
  const open = C.indexOf('$function$', at);
  return C.slice(at, C.indexOf('$function$', open + 10));
};

test('1. a recurrence is counted on the open incident of its cause, never a second row', () => {
  const b = body('fn_it_incident_open');
  assert.match(b, /v_key := public\.fn_it_incident_cause_key\(h\.detail\)/, 'the cause is known at open');
  assert.match(b, /r\.cause_key = v_key and r\.same_cause_as is null/, 'it looks for the incident of the same cause');
  assert.match(b, /r\.ended_at is null or coalesce\(r\.last_seen_at, r\.started_at, r\.created_at\) > v_at - interval '24 hours'/,
    'an open incident, or one seen in the last 24 hours, is the same incident');
  assert.match(b, /set occurrences = occurrences \+ 1/, 'the recurrence is counted on it');
  assert.match(b, /jsonb_build_object\('incident_id', v_root\.id/, 'the hand-over carries the incident it was counted on');
  assert.match(b, /return v_root\.id;\s*end if;/, 'and no row is written for it');
  assert.match(b, /not v_pub or \(coalesce\(r\.impact, ''\) like 'Customer-facing%' and \(r\.ended_at is null or h\.status = 'done'\)\)/,
    'a live customer-facing occurrence is never folded into an ended outage');
  assert.match(b, /h\.detail->>'incident_id' ~ '\^\[0-9\]\+\$'/, 'asking twice never counts twice');
  assert.match(b, /insert into public\.it_incident \([^)]*cause_key, last_seen_at\)/, 'a new cause opens with its cause_key and last_seen_at');
  const key = body('fn_it_incident_cause_key');
  assert.match(key, /'playbook:' \|\|[\s\S]*'class:' \|\| public\.fn_it_postmortem_class_key\(p_detail\)[\s\S]*'issue:' \|\|/,
    'the same three-step cause key fn_it_incident_collapse writes');
});

test('2. an incident closes when its cause measures healthy, every 15 minutes', () => {
  const s = body('fn_it_incident_settle');
  assert.match(s, /from public\.it_engineer_finding f where f\.closed_at is null/, 'the open findings are the live causes');
  assert.match(s, /set ended_at = now\(\)[\s\S]*not exists \(select 1 from live where live\.k = r\.cause_key\)/, 'no live cause: closed');
  assert.match(body('fn_it_incident_impact_tick'), /'settled', public\.fn_it_incident_settle\(\)/, 'the 15-minute duty runs it');
});

test('3. the postmortem neither re-opens nor asks about an occurrence already counted', () => {
  const b = body('fn_it_engineer_postmortem');
  assert.equal((b.match(/and not \(a\.detail \? 'incident_id'\)/g) || []).length, 3, 'all three "has no incident" reads honour incident_id');
  assert.match(b, /if not exists \(select 1 from public\.it_incident where id = v_inc and handoff_id = h\.id\) then\s*n_folded := n_folded \+ 1;\s*continue;/,
    'a counted occurrence gets no postmortem of its own');
  assert.match(b, /q\.status in \('held', 'reasoned', 'applied', 'failed'\)/, 'a failed ask counts as asked for its class');
  assert.match(body('fn_it_daily_line'), /and not \(a\.detail \? 'incident_id'\)/, 'a counted occurrence is not an auto-fixed class');
});

test('4. a CEO judgement of an IT finding that has cleared never reaches a model', () => {
  const b = body('fn_reason_held_sweep');
  assert.match(b, /h\.surface = 'ceo\.it_finding' and h\.status = 'held'[\s\S]*?set status = 'expired'|set status = 'expired'[\s\S]*?h\.surface = 'ceo\.it_finding' and h\.status = 'held'/,
    'the sweep expires it');
  assert.match(b, /a\.status = 'pending'\s*and f\.closed_at is null/, 'only a pending hand-over whose finding is still open keeps its question');
  assert.match(b, /status in \('reasoned', 'applied', 'failed'\)/, 'one postmortem per fault holds after a failed ask');
  // the sweep runs first inside fn_reason_held_due, the only door to the held replay's model calls
  assert.match(read('scripts/sql/a_held_question_lives_fourteen_days_once_the_model_is_open_and_the_newest_is_answered_first.sql') +
    read('scripts/sql/a_held_question_is_paid_for_once_and_test_traffic_never_waits_for_a_model.sql'), /perform public\.fn_reason_held_sweep\(\)/);
});

test('5. new routines are revoked and pinned; the file is pending until applied', () => {
  for (const fn of ['fn_it_incident_cause_key(jsonb)', 'fn_it_incident_settle()']) {
    assert.match(C, new RegExp(`revoke execute on function public\\.${fn.replace(/[()]/g, '\\$&')} from public, anon, authenticated`), `${fn} revoked`);
  }
  for (const m of C.matchAll(/create\s+or\s+replace\s+function\s+public\.(\w+)[\s\S]*?\$function\$/gi)) {
    assert.match(m[0], /set search_path to 'public', 'pg_temp'/i, `${m[1]} pins its search_path`);
  }
  const manifest = read('scripts/sql/MANIFEST.txt');
  const pending = existsSync(join(REPO, `scripts/sql/pending/${NAME}.txt`));
  assert.ok(pending !== manifest.includes(`${NAME}.sql`), 'exactly one of: a pending note, or a MANIFEST line');
  assert.ok(existsSync(join(REPO, `scripts/sql/pending/${NAME}_probe.txt`)) && !manifest.includes(`${NAME}_probe.sql`), 'the probe is never applied');
});

const URL_ = process.env.QD_LOCAL_DB_URL ?? '';
const isLocal = /^postgres(ql)?:\/\/[^@]*@(%2F|localhost|127\.0\.0\.1)/i.test(URL_);
const LOCAL_SKIP = !URL_ ? 'QD_LOCAL_DB_URL not set (a local Postgres 16 built from the mirror)' : !isLocal ? 'QD_LOCAL_DB_URL is not a local database: refused' : false;

test('6. (local Postgres) the file applies twice and the probe answers PROBE OK twice', { skip: LOCAL_SKIP, timeout: 300000 }, () => {
  const db = 'incident_check_' + process.pid;
  const admin = (args) => spawnSync('psql', [URL_, '-v', 'ON_ERROR_STOP=1', '-q', ...args], { encoding: 'utf8' });
  const at = (args) => spawnSync('psql', [URL_.replace(/\/[^/?]+(\?|$)/, `/${db}$1`), '-q', ...args], { encoding: 'utf8' });
  const tpl = URL_.match(/\/([^/?]+)(\?|$)/)[1];
  assert.equal(admin(['-c', `create database ${db} template ${tpl}`]).status, 0, 'the copy of the local database');
  try {
    for (const f of [FILE, FILE]) {
      const r = at(['-v', 'ON_ERROR_STOP=1', '-1', '-f', join(REPO, f)]);
      assert.equal(r.status, 0, `${f} does not apply: ${r.stderr.slice(0, 600)}`);
    }
    for (let i = 0; i < 2; i++) {
      const out = at(['-f', join(REPO, PROBE)]).stderr;
      assert.match(out, /CHK<<PROBE OK/, `the probe: ${out.slice(0, 1500)}`);
    }
  } finally { admin(['-c', `drop database if exists ${db}`]); }
});
