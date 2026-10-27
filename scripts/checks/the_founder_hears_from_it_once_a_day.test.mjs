// THE FOUNDER HEARS FROM IT ONCE A DAY, AND ONLY ABOUT WHAT NEEDS HIM.
//
// Founder instruction 642, 22 Sep 2026. Measured: 88 IT emails and 35 WhatsApp copies in 14 days, every
// non-outage one of kind it_new_bug, sent up to once an hour by fn_customer_support_sends_the_it_digest.
// scripts/sql/the_founder_hears_from_it_once_a_day.sql makes that routine decide once a day at 19:00 Dubai
// and send only (a) decisions only he can make and (b) faults open more than 24 hours the company could
// not fix, email only; and makes the emergency class the only other IT mail that reaches him.
// Supersedes the_founder_gets_one_it_digest_per_tick.test.mjs (retired with its subject).
//
// STATIC (CI, no token), on each routine's canonical body -- the last file in apply order that defines it:
//   * support still holds a founder it_new_bug request before anything can notify him;
//   * NO routine passes kind it_new_bug to fn_notify_founder, and only the digest passes it_daily_digest;
//   * the digest leaves at the fixed hour, at a level that does not fan out to WhatsApp;
//   * the IT tick calls the digest.
// LIVE (token): the policy's it_engineer kinds allowed to reach him are exactly the emergency class plus
// the digest; and ONE transaction that always rolls back (ZZ DEMO subjects, the founder stub on, a day in
// 2099 so no real digest day is touched) proves: too early -> nothing; a decision is told; a fault of any age (30 hours,
// 3 hours) stays internal on the OS (ruling of 4 Oct 2026, the_originator_closes_what_was_answered_and_the_digest_carries_only_his_decisions.sql); a closed fault is completed as fixed; a CEO-silence report stays internal;
// a day already decided is not decided twice; 0 rows are queued to the founder. Until the file is applied
// the same transaction first runs the file itself, so this rehearses the change before it goes live.
//
//   node --test scripts/checks/the_founder_hears_from_it_once_a_day.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';
import { manifestWithPending } from '../lib/pending_sql.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FILE = 'scripts/sql/the_founder_hears_from_it_once_a_day.sql';
const files = readFileSync(join(REPO, 'scripts', 'sql', 'MANIFEST.txt'), 'utf8')
  .split(/\r?\n/).map((l) => l.trim()).filter((l) => l.endsWith('.sql') && !l.startsWith('#'));
// Until the coordinator appends it, this file is pending; it is applied LAST, so it is read last.
if (!files.includes(FILE)) files.push(FILE);

const canonical = new Map();
for (const f of files) {
  const p = join(REPO, f);
  if (!existsSync(p)) continue;
  const src = readFileSync(p, 'utf8');
  const heads = [...src.matchAll(/create\s+or\s+replace\s+function\s+public\.(\w+)\s*\(/gi)];
  heads.forEach((m, i) => canonical.set(m[1].toLowerCase(), src.slice(m.index, heads[i + 1]?.index ?? src.length)));
}
const body = (n) => { const b = canonical.get(n); assert.ok(b, `${n} is defined by no file in MANIFEST.txt`); return b; };

// 27 Oct 2026: re-applying the_it_engineer_closes_every_loop_it_opens.sql (for #1587) re-ran its 14 Sep upsert and turned
// it_new_bug back ON in production, against instruction 642. No applied or pending file may upsert the kind open again.
test('no SQL file can re-open the per-issue it_new_bug email (instruction 642)', () => {
  const all = manifestWithPending().filter((f) => existsSync(join(REPO, f)));
  const bad = all.filter((f) => /values\s*\(\s*'it_new_bug'\s*,\s*true[\s\S]{0,600}?on conflict \(kind\) do update/i
    .test(readFileSync(join(REPO, f), 'utf8').replace(/--[^\n]*/g, '')));
  assert.deepEqual(bad, [], 'these files upsert it_new_bug open again on a re-apply');
});

test('support holds a founder it_new_bug request before anything can notify him', () => {
  const b = body('fn_customer_support_acts_on_handoff');
  const hold = b.search(/d->>'kind'\s*=\s*'it_new_bug'/);
  const send = b.indexOf('fn_notify_founder(');
  assert.ok(hold > 0 && send > hold, 'the it_new_bug hold must come before the fn_notify_founder call');
  assert.match(b.slice(hold, send), /'waiting'/, "the hold must answer 'waiting' so the request stays pending");
});

test('no routine sends it_new_bug to the founder; only the daily digest sends it_daily_digest', () => {
  const passing = (kind) => [...canonical.entries()]
    .filter(([n, b]) => n !== 'fn_notify_founder' && /fn_notify_founder\s*\(/.test(b) && new RegExp(`p_kind\\s*=>\\s*'${kind}'`).test(b))
    .map(([n]) => n);
  assert.deepEqual(passing('it_new_bug'), []);
  assert.deepEqual(passing('it_daily_digest'), ['fn_customer_support_sends_the_it_digest']);
});

test('the digest leaves once, at 19:00 Dubai, by email only', () => {
  const b = body('fn_customer_support_sends_the_it_digest');
  assert.match(b, /c_hour\s+constant time := time '19:00'/);
  assert.match(b, /at time zone 'Asia\/Dubai'/);
  // fn_notify_founder fans out to WhatsApp for critical, urgent, high and danger.
  const lvl = b.match(/p_level\s*=>\s*'(\w+)'/);
  assert.ok(lvl && !['critical', 'urgent', 'high', 'danger'].includes(lvl[1]), `the digest's level ${lvl?.[1]} would also go to WhatsApp`);
  assert.match(body('fn_it_loop_tick'), /fn_customer_support_sends_the_it_digest\(\)/, 'the IT tick no longer calls the digest');
});

// The register rows as the file writes them: ('<pattern>', true|false, '<why>').
export const registerRows = (src) => [...src.matchAll(/^\s*\('([^']+)',\s*(true|false),/gm)].map((m) => ({ like: m[1], toFounder: m[2] === 'true' }));
// What he has answered or ruled is not his (instructions 585, 636, 639, 22 Sep 2026). A decision row
// matching any of these would ask him again; the file must register them to_founder = false instead.
const NEVER_ASK = /cap_unknown|pitr|campaign|invitation|subscription|renewal|expenses/i;
export const askedAgain = (rows) => rows.filter((r) => r.toFounder && NEVER_ASK.test(r.like)).map((r) => r.like);

test('the decision register never asks him what he has answered: caps, PITR, subscriptions, the campaign go', () => {
  const rows = registerRows(readFileSync(join(REPO, FILE), 'utf8'));
  assert.ok(rows.length >= 8, `the register rows were not read from ${FILE} (${rows.length})`);
  assert.deepEqual(askedAgain(rows), []);
  for (const must of ['duty:usage_%:cap_unknown:%', 'duty:db_backup:pitr', '%campaign%', '%invitation%']) {
    assert.ok(rows.some((r) => r.like === must && !r.toFounder), `${must} must be registered to_founder = false`);
  }
  // and the gate can fail
  assert.deepEqual(askedAgain([{ like: 'duty:usage_%:cap_unknown:%', toFounder: true }, { like: 'duty:access:%', toFounder: true }]),
    ['duty:usage_%:cap_unknown:%']);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';

const PROBE = `
do $p$
declare v jsonb; w jsonb; d jsonb; e jsonb; k int; v_max bigint; v_at timestamptz := timestamptz '2099-01-01 19:05:00+04';
begin
  perform set_config('app.qd_stub_founder_notify', 'on', true);
  select coalesce(max(id), 0) into v_max from public.notifications;
  insert into public.it_engineer_finding (issue_key, title, where_it_is, blast, affected, evidence, raised_by, started_at, last_seen_at, seen_count)
  values ('duty:credential:zz_demo_daily', 'ZZ DEMO credential refused', 'probe', 'internal', 1, '{"demo":true}', 'probe', v_at - interval '2 hours', v_at, 1),
         ('duty:zz_demo_old:a', 'ZZ DEMO old fault', 'probe', 'internal', 1, '{"demo":true,"owner_seat":"sales_engineer"}', 'probe', v_at - interval '30 hours', v_at, 1),
         ('duty:zz_demo_young:a', 'ZZ DEMO young fault', 'probe', 'internal', 1, '{"demo":true}', 'probe', v_at - interval '3 hours', v_at, 1),
         ('duty:zz_demo_closed:a', 'ZZ DEMO closed fault', 'probe', 'internal', 1, '{"demo":true}', 'probe', v_at - interval '30 hours', v_at, 1),
         -- He has ruled these are not his (639 caps, 636 campaign/invitation): day-old, still never told.
         ('duty:usage_zz_demo:cap_unknown:zz_month', 'ZZ DEMO no cap recorded', 'probe', 'internal', 1, '{"demo":true}', 'probe', v_at - interval '30 hours', v_at, 1),
         ('duty:zz_demo_invitation_gate:a', 'ZZ DEMO campaign go', 'probe', 'internal', 1, '{"demo":true}', 'probe', v_at - interval '30 hours', v_at, 1);
  update public.it_engineer_finding set closed_at = v_at, close_note = 'ZZ DEMO closed' where issue_key = 'duty:zz_demo_closed:a';
  for k in 1..7 loop
    perform public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'support_ceo_report', 'zz-demo-daily-' || k,
      jsonb_build_object('recipient_role', 'founder', 'kind', 'it_new_bug', 'level', 'high', 'event', 'ZZ DEMO', 'detail', 'ZZ DEMO',
        'dedupe_key', case k when 5 then 'it_ceo_silent:zz_demo'
                      else 'it_new_bug:' || (array['duty:credential:zz_demo_daily', 'duty:zz_demo_old:a', 'duty:zz_demo_young:a', 'duty:zz_demo_closed:a',
                                                   null, 'duty:usage_zz_demo:cap_unknown:zz_month', 'duty:zz_demo_invitation_gate:a'])[k] end));
  end loop;
  select count(*) into k from public.agent_actions
   where target_id like 'delivery.request:zz-demo-daily-%' and status = 'pending' and evidence->>'digest' = 'pending';
  w := public.fn_customer_support_sends_the_it_digest(v_at - interval '1 hour');
  v := public.fn_customer_support_sends_the_it_digest(v_at);
  select jsonb_object_agg(replace(target_id, 'delivery.request:zz-demo-daily-', ''), case when status = 'pending' then 'pending' else evidence->>'digest' end)
    into e from public.agent_actions where target_id like 'delivery.request:zz-demo-daily-%';
  insert into public.founder_alerts (level, event, detail, channel, dedupe_key) values ('info', 'ZZ DEMO', 'ZZ DEMO', 'os', v->>'digest_key');
  d := public.fn_customer_support_sends_the_it_digest(v_at + interval '1 hour');
  raise exception 'CHK<<%>>', jsonb_build_object('held', k, 'early', w->>'reason', 'again', d->>'reason', 'states', e,
    'event', v->>'event', 'told_decision', v->>'detail' ~ 'DECISION: ZZ DEMO credential refused. Only you can decide this',
    'told_old', v->>'detail' ~ 'ZZ DEMO old fault',
    'told_young_or_closed', v->>'detail' ~ 'ZZ DEMO (young|closed)', 'told_ruled_out', v->>'detail' ~ 'ZZ DEMO (no cap|campaign)',
    'founder_rows', (select count(*) from public.notifications where id > v_max))::text;
end $p$;`;

test('production: the IT kinds that reach the founder at once are exactly the emergency class plus the digest', { skip: SKIP }, async (t) => {
  const { sql } = await import('../lib/db.mjs');
  const r = await sql(`select coalesce(array_agg(kind order by kind), '{}') k from public.founder_mail_policy where owner_role = 'it_engineer' and allowed_to_email`);
  if (!r[0].k.includes('it_daily_digest')) { t.skip(`${FILE} is not applied yet`); return; }
  // integration_reauth_needed joined on founder instruction 979 (24 Sep 2026): an integration only he can restore,
  // sent once per failure and only when the company could not fix it
  // (the_it_engineer_watches_every_integration_and_fixes_what_it_can.sql). Any other addition still fails here.
  assert.deepEqual(r[0].k, ['backup_failed_after_retry', 'integration_reauth_needed', 'it_daily_digest', 'platform_down', 'security_critical', 'uptime_alert']);
});

test('production: one digest a day carries only his decisions, and reaches nobody in a test', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const live = (await sql(`select to_regprocedure('public.fn_customer_support_sends_the_it_digest(timestamptz)') is not null as live`))[0].live;
  // Not applied yet: rehearse the file itself in the same rolled-back transaction.
  const pre = live ? '' : `begin;\n${readFileSync(join(REPO, FILE), 'utf8')}\n`;
  let message = '';
  try { await replaySql(pre + PROBE, { retry: false }); message = 'the probe returned without raising, so it did not roll back'; } catch (e) { message = String(e.message); }
  const chk = message.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(chk, message.slice(0, 1500));
  const o = JSON.parse(chk[1].replace(/\\"/g, '"'));
  assert.equal(o.held, 7, 'the seven requests were not all held for the digest');
  assert.match(o.early, /19:00 Dubai/);
  assert.match(o.again, /already decided/);
  assert.deepEqual(o.states, { 1: 'sent', 2: 'internal', 3: 'internal', 4: 'fixed', 5: 'internal', 6: 'internal', 7: 'internal' });
  assert.equal(o.told_ruled_out, false, 'the digest told him something he ruled is not his');
  assert.equal(o.told_decision, true);
  assert.equal(o.told_old, false, 'a day-old fault was emailed: since 4 Oct 2026 the digest carries only his decisions ' + JSON.stringify(o));
  assert.equal(o.told_young_or_closed, false);
  assert.equal(o.founder_rows, 0, 'a test queued a row to the founder');
});
