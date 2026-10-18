// THE INVITATION BATCH WAITS FOR THE MORNING'S SEED TO LAND IN BOTH INBOXES (24 Sep 2026, it_engineer).
//
// Each sending day, one seed invitation goes to the founder's Gmail and Microsoft 365 inbox at 05:15 UTC
// through the real path. The folder it lands in is read back, and the 06:00 UTC batch goes only on
// Inbox + Inbox. This FAILS if any part of that comes back undone:
//   * static: a new or redefined routine loses its pinned search_path or its exact-signature revoke; the
//     table loses RLS, its policy or its revoke; the seed stops being supplier_invite_seed (so it spends
//     the cap); the allowlist stops being the two exact addresses in both the schema and the reader, or
//     leaves scripts/invitation_inbox_check.mjs FOUNDER_INBOXES; a junk placement pauses the campaign again
//     (founder ruling, ledger 1001: it is diagnosed, filed with the sender lane, handed to marketing, and the
//     batch sends) or stops filing the finding or opening the handoff; the same-day brake (#943) stops being
//     the one automatic pause;
//     enqueue_supplier_invites or the outreach tick stop asking the gate, or a non-pass stops holding;
//     the gate stops failing closed on a day with no check; the heartbeat step or its resilience_step row
//     goes (pg_cron is dead on this project, so a cron.schedule here would never fire); the file carries
//     both, or neither, of a pending note and a MANIFEST line.
//   * production, in ONE aborted transaction (the file replayed while pending, the campaign gates switched
//     on inside it, simulated clocks, nothing commits, and the uncommitted seed rows cannot be claimed by
//     send_outbox): the seed is queued at 05:15 and not before; the gate waits and then fails closed; junk
//     keeps the campaign on, lets the batch pass, files the diagnosis and opens the marketing handoff; Inbox +
//     Inbox passes and closes both; a From change or a
//     day with no check holds; an address outside the allowlist is refused by the schema.
//
//   node --test scripts/checks/the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

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
  fn_invite_campaign_pause: 'text, text, jsonb, jsonb',
  fn_invite_same_day_brake: '',
  fn_invite_placement_deadline: 'date',
  fn_invite_placement_cutoff: 'date',
  fn_invite_placement_sender: '',
  fn_invite_placement_finding: 'date, text, text, jsonb',
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

test('a junk placement never pauses: it is diagnosed, filed and handed to marketing; the #943 brake is the one automatic pause', () => {
  const pause = body('fn_invite_campaign_pause');
  assert.match(pause, /update app_secrets set value = 'false' where key = 'invite_enabled'/);
  assert.match(pause, /update notifications set status = 'cancelled'\s+where type = 'supplier_invite' and status = 'queued'/);
  assert.match(pause, /insert into it_watch_finding/);
  assert.doesNotMatch(pause, /value = 'true'/, 'the pause can switch the campaign ON');
  const settle = body('fn_invite_placement_settle');
  assert.equal((settle.match(/fn_invite_campaign_pause\(|key = 'invite_enabled'/g) || []).length, 0, 'the placement settle pauses the campaign again (ledger 1001)');
  assert.match(settle, /if v in \('spam', 'elsewhere'\) then\s+[^\n]*\n\s+v_handoff := public\.fn_seat_handoff\('it_engineer', 'marketing', 'deliverability\.inbox_placement',/,
    'a junk placement opens no marketing handoff');
  assert.match(settle, /'sender_lane', v_lane/, 'the diagnosis does not name the sender lane');
  assert.match(settle, /'diagnosis', jsonb_build_object\('gmail', coalesce\(r\.gmail_detail -> 'messages'/, 'the finding does not carry the reader\'s diagnosis');
  assert.match(settle, /fn_seat_handoff_complete\(h\.id,/, 'an inbox verdict does not close the marketing handoff');
  assert.match(SQL, /'deliverability\.inbox_placement', 'it_engineer', 'marketing',[\s\S]*?'fn_marketing_takes_the_inbox_placement_fix', interval '1 day', true,/, 'the handoff kind is unregistered');
  assert.match(TS, /X-Forefront-Antispam-Report/, 'the Microsoft diagnosis is not read');
  assert.match(TS, /metadataHeaders=Authentication-Results/, 'the Gmail Authentication-Results is not read');
  assert.match(settle, /perform public\.fn_invite_placement_finding\(p_day, v, v_why, v_ev\);/, 'a failed verdict files no finding');
  assert.match(settle, /if 'spam' in \(r\.gmail_folder, r\.outlook_folder\) then v := 'spam'/);
  assert.match(settle, /elsif r\.gmail_folder = 'inbox' and r\.outlook_folder = 'inbox' then v := 'inbox'/, 'inbox must need BOTH seeds in the Inbox');
  assert.match(settle, /elsif p_now >= public\.fn_invite_placement_cutoff\(p_day\) then/, 'unread/not_found are settled before the read cutoff');
  const finding = body('fn_invite_placement_finding');
  assert.match(finding, /v_key constant text := 'deliverability:inbox_placement'/);
  assert.match(finding, /public\.fn_it_engineer_finding_upsert\(v_key,/);
  assert.match(finding, /evidence ->> 'dubai_day' = p_day::text and evidence ->> 'verdict' = p_verdict/, 'the finding is not filed once per day and verdict');
  assert.match(finding, /invite_lane_domain_unverified/, 'the lane-refused hint is gone');
  const brake = body('fn_invite_same_day_brake');
  assert.match(brake, /public\.fn_invite_campaign_pause\('invite_same_day_brake', v_why,/);
  assert.doesNotMatch(brake, /update app_secrets set value/, 'the brake pauses on its own again: two pause paths');
  assert.doesNotMatch(SQL, /set value = 'true'/, 'this file switches a campaign gate on');
});

test('the batch fails closed: the gate, the tick and the enqueue; the sender is the effective one', () => {
  const gate = body('fn_invite_placement_gate');
  assert.match(gate, /if p_now < public\.fn_invite_placement_cutoff\(v_day\) then return 'wait'; end if;\s+if public\.fn_invite_placement_day_closed\(p_now\) is null then\s+perform public\.fn_invite_placement_finding\(v_day, 'no_check',/,
    'a day with no check does not fail closed, or holds in silence');
  assert.match(gate, /return 'fail:no_check';/);
  assert.match(gate, /if v not in \('inbox', 'spam', 'elsewhere'\) then return 'fail:' \|\| v; end if;/, 'a measured placement no longer lets the batch go, or a failure to measure does');
  assert.match(gate, /if public\.fn_invite_placement_sender\(\) is distinct from r\.from_address then return 'fail:from_changed'; end if;/);
  assert.equal((gate.match(/return 'pass'/g) || []).length, 1, 'more than one way to pass');
  const sender = body('fn_invite_placement_sender');
  assert.match(sender, /key = 'invite_lane_enabled'\), 'false'\) = 'true'/, 'the lane is not read, or a missing key is not the lane off');
  assert.match(sender, /key = 'invite_lane_from'/);
  assert.match(sender, /key = 'email_from_supplier'/);
  assert.match(body('fn_invite_placement_due'), /v_from := public\.fn_invite_placement_sender\(\);/, 'the check records a sender other than the effective one');
  const tick = body('fn_sales_engineer_supplier_outreach_tick');
  const g = tick.indexOf('v_gate := public.fn_invite_placement_gate(');
  assert.ok(g > 0, 'the outreach tick no longer asks the placement gate');
  assert.ok(g < tick.indexOf('public.enqueue_supplier_invites(null)') && g < tick.indexOf('public.fn_invite_ramp()'), 'the tick asks the gate after the batch');
  assert.match(tick, /if v_gate = 'wait' and not p_force then\s+v_batch_wait := true;/, 'a running check does not make the batch wait');
  assert.match(tick, /elsif v_gate <> 'pass' then\s+v_batch_why :=/, 'a failed gate does not hold the batch');
  assert.match(tick, /if not v_batch_wait then[\s\S]*?public\.enqueue_supplier_invites\(null\)/, 'the batch is enqueued while the gate waits');
  const rem = tick.indexOf('fn_supplier_registration_reminders_due()');
  const early = tick.slice(0, rem);
  assert.doesNotMatch(early.slice(early.indexOf('if v_daily_done and not p_force then')), /return jsonb_build_object\('due', false, 'reason', 'waiting/, 'the daily work waits for the gate');
  assert.match(tick, /if v_why is not null then continue; end if;/, 'reminders are held by something other than the campaign gates');
  assert.match(tick, /'supplier_outreach_batch'/, 'a later beat cannot run the owed batch');
  const enq = body('enqueue_supplier_invites');
  const eg = enq.indexOf('v_gate := public.fn_invite_placement_gate(');
  assert.ok(eg > 0, 'enqueue_supplier_invites no longer asks the placement gate');
  assert.ok(eg < enq.indexOf('insert into notifications(type, to_email, to_role, lead_id'), 'the batch is queued before the gate');
  assert.match(enq.slice(eg), /^v_gate := [^\n]*\n\s*if v_gate <> 'pass' then[\s\S]*?return 0;\s*end if;/, 'a non-pass does not return before queueing');
  const due = body('fn_invite_placement_due');
  assert.match(due, /p_now < v_deadline - interval '90 minutes' or p_now >= v_cutoff - interval '30 minutes'/, 'the seed is not queued from 90 minutes before the window');
  assert.match(due, /if p_now >= v_cutoff then/, 'the day is settled before the read cutoff');
  assert.match(body('fn_invite_placement_cutoff'), /fn_invite_placement_deadline\(p_day\) \+ interval '2 hours'/);
  assert.match(body('fn_invite_placement_deadline'), /'window_start_hour'/, 'the deadline is not the batch window');
  const record = body('fn_invite_placement_record');
  assert.match(record, /case when v_g is null or/, 'a failed reading can overwrite a found folder');
});

test('the reader: only the seed counts, the answer is public-safe, the listing is paged', () => {
  assert.match(TS, /if \(gmailIsOwnCopy\(labels\)\) \{ ownCopies\+\+; continue; \}/, 'a Gmail Sent/Draft copy can decide the placement');
  assert.match(TS, /l\.includes\('SENT'\) \|\| l\.includes\('DRAFT'\)/);
  assert.match(TS, /if \(addressOf\(from\) !== want\) \{ otherSender\+\+; continue; \}/, 'a token mail from another sender can decide the placement');
  assert.match(TS, /m\.parentFolderId === ids\.sentitems \|\| m\.parentFolderId === ids\.drafts/, 'a Graph Sent Items/Drafts copy can decide the placement');
  assert.match(TS, /@odata\.nextLink/, 'the Graph listing is not paged');
  assert.match(TS, /if \(due\.action !== 'read'\) return \{ ok: true, \.\.\.publicView\(due\) \};/, 'the raw due row (token, notification ids) reaches the public answer');
  assert.doesNotMatch(TS.slice(TS.indexOf('export async function placementTick')), /token: |sender: |notifications/, 'placementTick returns a sensitive field');
});

test('the schedule is the heartbeat inside an existing 15-minute step: no new step, no row, no pg_cron; pending XOR MANIFEST', () => {
  // every_tick_step_is_scheduled.mjs compares STEP_RUN with production's resilience_step rows; a new step would be
  // red until this file is applied, so the check rides on itintegrations (every 15 min), as #961 rides on itlater.
  const fnStart = PING.indexOf('async function itIntegrationsTick()');
  assert.ok(fnStart > 0, 'itIntegrationsTick is gone');
  assert.match(PING.slice(fnStart, PING.indexOf('\n}\n', fnStart)), /await Promise\.all\(\[integrations, inboxPlacement\(\)\]\)/,
    'itintegrations no longer runs the placement check on its own path (an integration settle error would skip it)');
  assert.match(PING.slice(PING.indexOf('async function inboxPlacement()'), fnStart), /placementTick\(/);
  const open = PING.indexOf("const STEP_RUN: Record<string, Omit<Step, 'name'>> = {");
  assert.doesNotMatch(PING.slice(open, PING.indexOf('\n};', open)), /inboxPlacement/, 'a new STEP_RUN entry needs a resilience_step row first');
  assert.doesNotMatch(SQL, /resilience_step/, 'this file seeds a resilience_step row the deployed code may not have');
  assert.match(TS, /SCHEMA_MISSING\.has\(String\(error\.code\)\)\) return \{ ok: true, skipped: 'schema not applied'/, 'deployed before the apply, the step would fail every beat');
  assert.doesNotMatch(SQL, /cron\.schedule/, 'pg_cron holds one inactive job on this project; a schedule there never fires');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
  assert.ok(pending(FILE) !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

// PR #961 owns the pause: fn_invite_campaign_pause(source, why, evidence, counts) and the brake that calls it. Both
// files carry the two blocks, so they must be identical or the one applied second silently rewrites the other.
const PM = 'scripts/sql/the_it_engineer_reads_gmail_postmaster_daily_and_a_spam_spike_stops_the_invitations.sql';
export function block(text, name) {
  const open = text.indexOf(`create or replace function public.${name}(`);
  if (open < 0) return null;
  let end = text.indexOf('\n', text.indexOf(`revoke execute on function public.${name}(`, open));
  if (text.startsWith(`grant execute on function public.${name}(`, end + 1)) end = text.indexOf('\n', end + 1);
  return text.slice(open, end);
}

test('the pause and the brake are byte-identical to PR #961 whenever both files are in the tree', { skip: existsSync(join(REPO, PM)) ? false : 'PR #961 not in this tree' }, () => {
  const mine = read(FILE), theirs = read(PM);
  for (const fn of ['fn_invite_campaign_pause', 'fn_invite_same_day_brake']) {
    const a = block(mine, fn), b = block(theirs, fn);
    assert.ok(a && b, `${fn} is missing from one of the two files`);
    assert.equal(a, b, `${fn} differs from PR #961: whichever applies second would rewrite the other`);
  }
});

test('no three-argument fn_invite_campaign_pause is defined anywhere', () => {
  const three = /function public\.fn_invite_campaign_pause\(\s*(?:[a-z_]+\s+)?text\s*,\s*(?:[a-z_]+\s+)?text\s*,\s*(?:[a-z_]+\s+)?jsonb\s*\)/i;
  const bad = readdirSync(join(REPO, 'scripts/sql')).filter((f) => f.endsWith('.sql')).filter((f) => three.test(code(read('scripts/sql/' + f))));
  assert.deepEqual(bad, [], 'a second overload of the pause: the 4-argument one of PR #961 is the only one');
  const sigs = [...SQL.matchAll(/function public\.fn_invite_campaign_pause\(([^)]*)\)/g)].map((m) => m[1].replace(/\s+/g, ' ').trim());
  assert.ok(sigs.length >= 2);
  for (const g of sigs) assert.ok(/^(p_source text, p_why text, p_evidence jsonb, p_counts jsonb|text, text, jsonb, jsonb)$/.test(g), `unexpected signature ${g}`);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: queue from 04:30, wait, junk sends and hands off, inbox passes, lane or From change holds, unsent and no check hold without a pause, allowlist refuses', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const replay = pending(FILE) ? read(FILE) : '';
  let o;
  try { await replaySql(replay + '\n' + PROBE, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.equal(o.at_0450, 'queued', 'the seed was not queued at 04:35 UTC');
  assert.equal(o.early, 'idle', 'the seed was queued before 04:30 UTC');
  assert.equal(o.queued, 'queued');
  assert.equal(o.queued_leaks, false, 'the due answer carries the token or notification ids');
  assert.deepEqual(o.seeds, ['ahmadmhdnabilalzain@gmail.com', 'management@doratajewelries.com']);
  assert.deepEqual(o.types, ['supplier_invite_seed']);
  assert.equal(o.gate_wait, 'wait');
  assert.equal(o.spam, 'spam');
  assert.equal(o.paused, 'true', 'junk placement paused the campaign (ledger 1001: only the #943 brake pauses)');
  assert.equal(o.finding_open, true, 'junk placement filed no it_engineer finding');
  assert.equal(o.finding_lane, 'email_from_supplier', 'the finding does not name the sender lane');
  assert.equal(o.handoff_open, true, 'junk placement opened no marketing handoff');
  assert.equal(o.gate_after_spam, 'pass', 'junk placement held the batch');
  assert.equal(o.inbox, 'inbox');
  assert.equal(o.gate_pass, 'pass');
  assert.equal(o.finding_closed, true, 'an inbox verdict did not close the finding');
  assert.equal(o.handoff_closed, true, 'an inbox verdict did not close the marketing handoff');
  assert.equal(o.from_changed, 'fail:from_changed');
  assert.equal(o.unsent_at_window, 'wait', 'a check still running at 06:00 already failed');
  assert.equal(o.unsent, 'fail:not_sent', 'a seed never sent did not fail closed at the cutoff');
  assert.equal(o.unsent_paused, 'true', 'a not-sent day paused the campaign: only a provider placement may');
  assert.equal(o.no_check_early, 'wait');
  assert.equal(o.no_check_late, 'fail:no_check');
  assert.equal(o.no_check_filed, true, 'an open day with no check held the batch in silence');
  assert.equal(o.lane_changed, 'fail:from_changed', 'switching the invitation lane on did not invalidate the pass');
  assert.equal(o.refused, true, 'the schema accepted an address outside the allowlist');
});

const PROBE = String.raw`
do $$ declare
  o jsonb := '{}'; d date[]; t timestamptz; r jsonb; ids bigint[];
begin
  update app_secrets set value = 'true' where key in ('invite_enabled', 'supplier_outreach_golive');
  delete from app_secrets where key in ('invite_lane_enabled', 'invite_lane_from');
  select array_agg(x::date order by x) into d
    from generate_series(current_date + 1, current_date + 30, interval '1 day') x
   where extract(isodow from x) < 6
     and not exists (select 1 from company_calendar c where c.kind = 'public_holiday'
                      and x::date between c.starts_on and coalesce(c.ends_on, c.starts_on));

  -- day 1: not queued at 04:25, queued at 04:35 (the window opens at t = 06:00 UTC); Outlook in junk pauses and files
  t := fn_invite_placement_deadline(d[1]);
  o := o || jsonb_build_object('early', fn_invite_placement_due(t - interval '95 minutes') ->> 'action');
  r := fn_invite_placement_due(t - interval '85 minutes');
  select array_agg(n.id) into ids from notifications n where n.type = 'supplier_invite_seed'
     and n.subject like '%(ref ' || (select token from invite_placement_check where dubai_day = d[1]) || ')';
  o := o || jsonb_build_object('queued', r ->> 'action', 'at_0450', r ->> 'action',
    'queued_leaks', (r ? 'token') or (r ? 'notifications'),
    'seeds', (select jsonb_agg(to_email order by id) from notifications where id = any(ids)),
    'types', (select jsonb_agg(distinct type) from notifications where id = any(ids)),
    'gate_wait', fn_invite_placement_gate(d[1], t - interval '30 minutes'));
  update notifications set status = 'sent' where id = any(ids);
  -- A write and the reads of its effect are separate statements: a subquery sees the statement's snapshot, taken
  -- before a volatile call in the same statement wrote anything.
  o := o || jsonb_build_object('spam', fn_invite_placement_record(d[1], '{"folder":"inbox"}', '{"folder":"spam"}', t - interval '10 minutes') ->> 'verdict');
  o := o || jsonb_build_object(
    'paused', (select value from app_secrets where key = 'invite_enabled'),
    'finding_open', exists (select 1 from it_engineer_finding where issue_key = 'deliverability:inbox_placement' and closed_at is null),
    'finding_lane', (select evidence ->> 'sender_lane' from it_engineer_finding where issue_key = 'deliverability:inbox_placement' and closed_at is null),
    'handoff_open', exists (select 1 from agent_actions where kind = 'handoff' and agent = 'marketing' and target_id = 'deliverability.inbox_placement:' || d[1]
                                                        and status not in ('done', 'failed')),
    'gate_after_spam', fn_invite_placement_gate(d[1], t + interval '1 minute'));

  -- day 2: both in the Inbox passes and closes the finding; the From, then the invitation lane, invalidate it
  update app_secrets set value = 'true' where key = 'invite_enabled';
  t := fn_invite_placement_deadline(d[2]);
  perform fn_invite_placement_due(t - interval '60 minutes');
  update notifications set status = 'sent' where type = 'supplier_invite_seed'
     and subject like '%(ref ' || (select token from invite_placement_check where dubai_day = d[2]) || ')';
  o := o || jsonb_build_object('inbox', fn_invite_placement_record(d[2], '{"folder":"inbox"}', '{"folder":"inbox"}', t - interval '10 minutes') ->> 'verdict');
  o := o || jsonb_build_object(
    'gate_pass', fn_invite_placement_gate(d[2], t + interval '1 minute'),
    'finding_closed', exists (select 1 from it_engineer_finding where issue_key = 'deliverability:inbox_placement' and closed_at is not null),
    'handoff_closed', exists (select 1 from agent_actions where kind = 'handoff' and agent = 'marketing' and target_id = 'deliverability.inbox_placement:' || d[1]
                                                          and status = 'done'));
  insert into app_secrets(key, value) values ('invite_lane_enabled', 'true'), ('invite_lane_from', 'QuotesDone <zz-lane@example.invalid>');
  o := o || jsonb_build_object('lane_changed', fn_invite_placement_gate(d[2], t + interval '2 minutes'));
  delete from app_secrets where key in ('invite_lane_enabled', 'invite_lane_from');
  update app_secrets set value = 'ZZ DEMO <zz@example.invalid>' where key = 'email_from_supplier';
  o := o || jsonb_build_object('from_changed', fn_invite_placement_gate(d[2], t + interval '3 minutes'));

  -- day 3: queued, never sent, never read: still waiting at 06:00, held at the cutoff WITHOUT a pause
  t := fn_invite_placement_deadline(d[3]);
  perform fn_invite_placement_due(t - interval '60 minutes');
  o := o || jsonb_build_object('unsent_at_window', fn_invite_placement_gate(d[3], t + interval '1 minute'),
    'unsent', fn_invite_placement_gate(d[3], fn_invite_placement_cutoff(d[3]) + interval '1 minute'));
  o := o || jsonb_build_object(
    'unsent_paused', (select value from app_secrets where key = 'invite_enabled'));

  -- day 4: no check at all: wait, then fail and file the finding
  t := fn_invite_placement_deadline(d[4]);
  o := o || jsonb_build_object('no_check_early', fn_invite_placement_gate(d[4], t - interval '1 hour'),
                               'no_check_late', fn_invite_placement_gate(d[4], fn_invite_placement_cutoff(d[4]) + interval '1 minute'));
  o := o || jsonb_build_object('no_check_filed', exists (select 1 from it_engineer_finding where issue_key = 'deliverability:inbox_placement'
                                                          and closed_at is null and evidence ->> 'verdict' = 'no_check'));

  begin
    insert into invite_placement_check(dubai_day, token, from_address, subject, gmail_to, outlook_to)
    values (d[5], 'QD0000000000', 'x', 'x', 'someone.else@gmail.com', 'management@doratajewelries.com');
    o := o || jsonb_build_object('refused', false);
  exception when check_violation then o := o || jsonb_build_object('refused', true);
  end;

  raise exception 'CHK<<%>>', o::text;
end $$;
`;
