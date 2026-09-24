// THE INVITATION BATCH WAITS FOR THE MORNING'S SEED TO LAND IN BOTH INBOXES (24 Sep 2026, it_engineer).
//
// Each sending day, one seed invitation goes to the founder's Gmail and Microsoft 365 inbox at 05:15 UTC
// through the real path. The folder it lands in is read back, and the 06:00 UTC batch goes only on
// Inbox + Inbox. This FAILS if any part of that comes back undone:
//   * static: a new or redefined routine loses its pinned search_path or its exact-signature revoke; the
//     table loses RLS, its policy or its revoke; the seed stops being supplier_invite_seed (so it spends
//     the cap); the allowlist stops being the two exact addresses in both the schema and the reader, or
//     leaves scripts/invitation_inbox_check.mjs FOUNDER_INBOXES; a failed check stops pausing through the
//     shared pause and filing the it_engineer finding; the same-day brake stops using the same pause;
//     enqueue_supplier_invites or the outreach tick stop asking the gate, or a non-pass stops holding;
//     the gate stops failing closed on a day with no check; the heartbeat step or its resilience_step row
//     goes (pg_cron is dead on this project, so a cron.schedule here would never fire); the file carries
//     both, or neither, of a pending note and a MANIFEST line.
//   * production, in ONE aborted transaction (the file replayed while pending, the campaign gates switched
//     on inside it, simulated clocks, nothing commits, and the uncommitted seed rows cannot be claimed by
//     send_outbox): the seed is queued at 05:15 and not before; the gate waits and then fails closed; junk
//     pauses the campaign and files the finding; Inbox + Inbox passes and closes it; a From change or a
//     day with no check holds; an address outside the allowlist is refused by the schema.
//
//   node --test scripts/checks/the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.sql';
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const SQL = code(read(FILE));
const TS = read('supabase/functions/_shared/inbox_placement.ts');
const PING = read('supabase/functions/resilience_ping/index.ts');
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

// A routine's body, from its create statement to the closing $fn$, so prose elsewhere cannot satisfy it.
function body(name) {
  const open = SQL.indexOf(`create or replace function public.${name}(`);
  assert.ok(open >= 0, `${name} is no longer defined in ${FILE}`);
  const end = SQL.indexOf('$fn$;', SQL.indexOf('$fn$', open) + 4);
  return SQL.slice(open, end);
}

const ROUTINES = {
  fn_invite_campaign_pause: 'text, text, jsonb',
  fn_invite_same_day_brake: '',
  fn_invite_placement_deadline: 'date',
  fn_invite_placement_day_closed: 'timestamptz',
  fn_invite_placement_settle: 'date, timestamptz',
  fn_invite_placement_due: 'timestamptz',
  fn_invite_placement_record: 'date, jsonb, jsonb, timestamptz',
  fn_invite_placement_gate: 'date, timestamptz',
  fn_sales_engineer_supplier_outreach_tick: 'boolean',
  enqueue_supplier_invites: 'integer',
};

test('every routine pins search_path and revokes its exact signature; the table is service-role only', () => {
  for (const [fn, sig] of Object.entries(ROUTINES)) {
    assert.match(body(fn), /security definer\s+set search_path to 'public', 'pg_temp'/, `${fn}: search_path not pinned`);
    assert.ok(SQL.includes(`revoke execute on function public.${fn}(${sig}) from public, anon, authenticated;`), `${fn}(${sig}) is not revoked`);
  }
  assert.match(SQL, /alter table public\.invite_placement_check enable row level security/);
  assert.match(SQL, /create policy invite_placement_check_service_role_only on public\.invite_placement_check[\s\S]{0,80}using \(false\) with check \(false\)/);
  assert.match(SQL, /revoke all on public\.invite_placement_check from anon, authenticated/);
  assert.doesNotMatch(SQL, /fn_reason_hold|think\(|openrouter/i, 'routine work calls a model');
  assert.doesNotMatch(TS, /think\(|openrouter|ai_gateway/i, 'the reader calls a model');
});

test('the seed is supplier_invite_seed to exactly the two allowlisted inboxes, in the schema and in the reader', () => {
  const due = body('fn_invite_placement_due');
  const inserts = [...due.matchAll(/insert into public\.notifications[\s\S]*?values \('([a-z_]+)'/g)].map((m) => m[1]);
  assert.deepEqual(inserts, ['supplier_invite_seed', 'supplier_invite_seed'], 'the seed is not a supplier_invite_seed (it would spend the cap)');
  assert.match(due, /'ahmadmhdnabilalzain@gmail\.com', 'management@doratajewelries\.com'/);
  assert.match(SQL, /gmail_to\s+text not null check \(gmail_to = 'ahmadmhdnabilalzain@gmail\.com'\)/, 'the Gmail seed is not fixed by the schema');
  assert.match(SQL, /outlook_to\s+text not null check \(outlook_to = 'management@doratajewelries\.com'\)/, 'the Outlook seed is not fixed by the schema');
  const gm = TS.match(/export const SEED_GMAIL = '([^']+)'/)?.[1];
  const ol = TS.match(/export const SEED_OUTLOOK = '([^']+)'/)?.[1];
  assert.equal(gm, 'ahmadmhdnabilalzain@gmail.com');
  assert.equal(ol, 'management@doratajewelries.com');
  assert.match(TS, /export const PLACEMENT_SEEDS: readonly string\[\] = \[SEED_GMAIL, SEED_OUTLOOK\];/);
  assert.doesNotMatch(TS, /endsWith\(|SEED_DOMAINS/, 'the reader matches a domain instead of an exact address');
  const founder = read('scripts/invitation_inbox_check.mjs').match(/export const FOUNDER_INBOXES = \[([^\]]+)\]/)?.[1] || '';
  for (const a of [gm, ol]) assert.ok(founder.includes(`'${a}'`), `${a} is not one of the founder's own inboxes in invitation_inbox_check.mjs`);
});

test('a failed check pauses through the one shared pause and files the it_engineer finding; the brake uses the same pause', () => {
  const pause = body('fn_invite_campaign_pause');
  assert.match(pause, /update app_secrets set value = 'false' where key = 'invite_enabled'/);
  assert.match(pause, /update notifications set status = 'cancelled'\s+where type = 'supplier_invite' and status = 'queued'/);
  assert.match(pause, /insert into it_watch_finding/);
  assert.doesNotMatch(pause, /value = 'true'/, 'the pause can switch the campaign ON');
  const settle = body('fn_invite_placement_settle');
  assert.match(settle, /public\.fn_invite_campaign_pause\(v_key,/);
  assert.match(settle, /public\.fn_it_engineer_finding_upsert\(v_key,/);
  assert.match(settle, /v_key constant text := 'deliverability:inbox_placement'/);
  assert.match(settle, /if 'spam' in \(r\.gmail_folder, r\.outlook_folder\) then v := 'spam'/);
  assert.match(settle, /elsif r\.gmail_folder = 'inbox' and r\.outlook_folder = 'inbox' then v := 'inbox'/, 'inbox must need BOTH seeds in the Inbox');
  const brake = body('fn_invite_same_day_brake');
  assert.match(brake, /public\.fn_invite_campaign_pause\('deliverability:supplier_invite',/);
  assert.doesNotMatch(brake, /update app_secrets set value/, 'the brake pauses on its own again: two pause paths');
  assert.doesNotMatch(SQL, /set value = 'true'/, 'this file switches a campaign gate on');
});

test('the batch fails closed: the gate, the tick and the enqueue', () => {
  const gate = body('fn_invite_placement_gate');
  assert.match(gate, /then 'wait' else 'fail:no_check' end/, 'a day with no check does not fail closed');
  assert.match(gate, /if v <> 'inbox' then return 'fail:' \|\| v; end if;/);
  assert.match(gate, /if v_from is distinct from r\.from_address then return 'fail:from_changed'; end if;/);
  assert.equal((gate.match(/return 'pass'/g) || []).length, 1, 'more than one way to pass');
  const tick = body('fn_sales_engineer_supplier_outreach_tick');
  const g = tick.indexOf('v_gate := public.fn_invite_placement_gate(');
  assert.ok(g > 0, 'the outreach tick no longer asks the placement gate');
  assert.ok(g < tick.indexOf('public.enqueue_supplier_invites(null)') && g < tick.indexOf('public.fn_invite_ramp()'), 'the tick asks the gate after the batch');
  assert.match(tick, /if v_gate = 'wait' and not p_force then\s+return jsonb_build_object\('due', false/, 'a check still running spends the once-a-day run');
  assert.match(tick, /if v_gate <> 'pass' then\s+v_why :=/, 'a failed gate does not hold the day');
  const enq = body('enqueue_supplier_invites');
  const eg = enq.indexOf('v_gate := public.fn_invite_placement_gate(');
  assert.ok(eg > 0, 'enqueue_supplier_invites no longer asks the placement gate');
  assert.ok(eg < enq.indexOf('insert into notifications(type, to_email, to_role, lead_id'), 'the batch is queued before the gate');
  assert.match(enq.slice(eg), /^v_gate := [^\n]*\n\s*if v_gate <> 'pass' then[\s\S]*?return 0;\s*end if;/, 'a non-pass does not return before queueing');
  const due = body('fn_invite_placement_due');
  assert.match(due, /p_now < v_deadline - interval '45 minutes' or p_now >= v_deadline/, 'the seed window is not the 45 minutes before the batch');
  assert.match(body('fn_invite_placement_deadline'), /'window_start_hour'/, 'the deadline is not the batch window');
  const record = body('fn_invite_placement_record');
  assert.match(record, /case when v_g is null or/, 'a failed reading can overwrite a found folder');
});

test('the schedule is the heartbeat: the step, its row, no pg_cron; pending XOR MANIFEST', () => {
  const open = PING.indexOf("const STEP_RUN: Record<string, Omit<Step, 'name'>> = {");
  assert.match(PING.slice(open, PING.indexOf('\n};', open)), /^\s{2}inboxPlacement:\s*\{\s*run:\s*inboxPlacementTick\s*\}/m);
  assert.match(PING, /placementTick\(/);
  assert.match(SQL, /\('inboxPlacement', interval '15 min', \d+, 'plan', 0,[\s\S]*?'it_engineer'\)/, 'the resilience_step row is not seeded for it_engineer');
  assert.doesNotMatch(SQL, /cron\.schedule/, 'pg_cron holds one inactive job on this project; a schedule there never fires');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(FILE) !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: queue at 05:15, wait, junk pauses, inbox passes, no check holds, allowlist refuses', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const replay = pending(FILE) ? read(FILE) : '';
  let o;
  try { await sql(replay + '\n' + PROBE, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.equal(o.early, 'idle', 'the seed was queued before 05:15 UTC');
  assert.equal(o.queued, 'queued');
  assert.deepEqual(o.seeds, ['ahmadmhdnabilalzain@gmail.com', 'management@doratajewelries.com']);
  assert.deepEqual(o.types, ['supplier_invite_seed']);
  assert.equal(o.gate_wait, 'wait');
  assert.equal(o.spam, 'spam');
  assert.equal(o.paused, 'false', 'junk placement did not pause the campaign');
  assert.equal(o.finding_open, true, 'junk placement filed no it_engineer finding');
  assert.equal(o.gate_after_spam, 'fail:spam');
  assert.equal(o.inbox, 'inbox');
  assert.equal(o.gate_pass, 'pass');
  assert.equal(o.finding_closed, true, 'an inbox verdict did not close the finding');
  assert.equal(o.from_changed, 'fail:from_changed');
  assert.equal(o.unsent, 'fail:not_sent', 'a seed never sent did not fail closed at the deadline');
  assert.equal(o.no_check_early, 'wait');
  assert.equal(o.no_check_late, 'fail:no_check');
  assert.equal(o.refused, true, 'the schema accepted an address outside the allowlist');
});

const PROBE = String.raw`
do $$ declare
  o jsonb := '{}'; d date[]; t timestamptz; r jsonb; ids bigint[];
begin
  update app_secrets set value = 'true' where key in ('invite_enabled', 'supplier_outreach_golive');
  select array_agg(x::date order by x) into d
    from generate_series(current_date + 1, current_date + 30, interval '1 day') x
   where extract(isodow from x) < 6
     and not exists (select 1 from company_calendar c where c.kind = 'public_holiday'
                      and x::date between c.starts_on and coalesce(c.ends_on, c.starts_on));

  -- day 1: queued at 05:15 and not at 05:10; the gate waits; Outlook in junk pauses and files the finding
  t := fn_invite_placement_deadline(d[1]);
  o := o || jsonb_build_object('early', fn_invite_placement_due(t - interval '50 minutes') ->> 'action');
  r := fn_invite_placement_due(t - interval '44 minutes');
  select array_agg(x::bigint) into ids from jsonb_array_elements_text(r -> 'notifications') x;
  o := o || jsonb_build_object('queued', r ->> 'action',
    'seeds', (select jsonb_agg(to_email order by id) from notifications where id = any(ids)),
    'types', (select jsonb_agg(distinct type) from notifications where id = any(ids)),
    'gate_wait', fn_invite_placement_gate(d[1], t - interval '30 minutes'));
  update notifications set status = 'sent' where id = any(ids);
  o := o || jsonb_build_object('spam', fn_invite_placement_record(d[1], '{"folder":"inbox"}', '{"folder":"spam"}', t - interval '10 minutes') ->> 'verdict',
    'paused', (select value from app_secrets where key = 'invite_enabled'),
    'finding_open', exists (select 1 from it_engineer_finding where issue_key = 'deliverability:inbox_placement' and closed_at is null),
    'gate_after_spam', fn_invite_placement_gate(d[1], t + interval '1 minute'));

  -- day 2: both in the Inbox passes and closes the finding; a From change afterwards holds
  update app_secrets set value = 'true' where key = 'invite_enabled';
  t := fn_invite_placement_deadline(d[2]);
  r := fn_invite_placement_due(t - interval '40 minutes');
  update notifications set status = 'sent' where id in (select x::bigint from jsonb_array_elements_text(r -> 'notifications') x);
  o := o || jsonb_build_object('inbox', fn_invite_placement_record(d[2], '{"folder":"inbox"}', '{"folder":"inbox"}', t - interval '10 minutes') ->> 'verdict',
    'gate_pass', fn_invite_placement_gate(d[2], t + interval '1 minute'),
    'finding_closed', exists (select 1 from it_engineer_finding where issue_key = 'deliverability:inbox_placement' and closed_at is not null));
  update app_secrets set value = 'ZZ DEMO <zz@example.invalid>' where key = 'email_from_supplier';
  o := o || jsonb_build_object('from_changed', fn_invite_placement_gate(d[2], t + interval '2 minutes'));

  -- day 3: queued, never sent, never read: at the window it fails closed
  t := fn_invite_placement_deadline(d[3]);
  perform fn_invite_placement_due(t - interval '40 minutes');
  o := o || jsonb_build_object('unsent', fn_invite_placement_gate(d[3], t + interval '1 minute'));

  -- day 4: no check at all
  t := fn_invite_placement_deadline(d[4]);
  o := o || jsonb_build_object('no_check_early', fn_invite_placement_gate(d[4], t - interval '1 hour'),
                               'no_check_late', fn_invite_placement_gate(d[4], t + interval '1 minute'));

  begin
    insert into invite_placement_check(dubai_day, token, from_address, subject, gmail_to, outlook_to)
    values (d[5], 'QD0000000000', 'x', 'x', 'someone.else@gmail.com', 'management@doratajewelries.com');
    o := o || jsonb_build_object('refused', false);
  exception when check_violation then o := o || jsonb_build_object('refused', true);
  end;

  raise exception 'CHK<<%>>', o::text;
end $$;
`;
