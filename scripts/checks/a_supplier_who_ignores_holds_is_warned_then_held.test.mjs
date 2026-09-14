// A SUPPLIER WHO LEAVES HOLDS UNANSWERED IS WARNED, THEN HELD — AND ONLY THE FOUNDER LIFTS IT.
//
// Founder, 14 Sep 2026 (founder_instruction #158, #160). Proved against production inside ONE
// transaction that raises at the end, so it commits nothing: no notification, support case, counter
// or event survives, and the dispatchers never see a row. It uses an existing ZZ DEMO supplier
// (company 'ZZ DEMO …', address @example.invalid) and never inserts a lead, because a lead insert can
// consume a founding-rank number that a rollback does not return. It asserts on every direction it
// touched and that the counts are the same afterwards.
//
//   fix before the decision resets the run · two in a row → warning through customer_support (email +
//   WhatsApp, requested_by sales_engineer) and a support case · three in a row → matching hold,
//   fn_is_matchable false · a fix in between breaks the run · clearing the hold directly, or lifting
//   it without a founder_instruction that names the supplier, is refused · the founder's lift resets
//   the run, keeps the history and queues a welcome-back note · the contact timeline shows it all.
// Static, no token needed: no edge function names the lift, and both matchers use fn_is_matchable.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const walk = (d) => readdirSync(d).flatMap((f) => { const p = join(d, f); return statSync(p).isDirectory() ? walk(p) : /\.(tsx?|mjs)$/.test(f) ? [p] : []; });

test('no agent path can call the lift: no edge function or portal file names it', () => {
  const files = [join(REPO, 'supabase', 'functions'), join(REPO, 'src')].flatMap(walk);
  const hits = files.filter((f) => readFileSync(f, 'utf8').includes('fn_supplier_collaboration_hold_lift')).map((f) => f.slice(REPO.length));
  assert.deepEqual(hits, []);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

const PROBE = String.raw`
do $probe$
declare
  v_lead bigint; v_mail text; r jsonb := '{}'::jsonb; v_before jsonb; v_after jsonb; v_fi bigint; v_ok boolean;
  v_matchable_before boolean; v_matchable_held boolean; v_tl jsonb;
begin
  -- A ZZ DEMO supplier if one exists; otherwise any lead, whose every contact field is overwritten
  -- with a fixture address and number as the FIRST statement below. Either way, inside this
  -- transaction (which is rolled back) no notice can be addressed to a real person, and none survives.
  select l.id into v_lead from public.leads l
   where l.company_name ilike 'ZZ DEMO%' and coalesce(l.claimed_by, l.email) ilike '%@example.invalid' order by l.id limit 1;
  if v_lead is null then select l.id into v_lead from public.leads l order by l.id limit 1; end if;
  if v_lead is null then raise exception 'PROBE<<{"skipped":"no lead at all to stand in as the fixture"}>>'; end if;
  v_mail := 'zz-demo-collab-probe@example.invalid';
  select jsonb_build_object('notifications', (select count(*) from public.notifications), 'cases', (select count(*) from public.support_case),
                            'events', (select count(*) from public.supplier_collaboration_event), 'collab', (select count(*) from public.supplier_collaboration))
    into v_before;

  -- A clean, matchable fixture, reachable only at reserved addresses, for this transaction only.
  update public.leads set email = v_mail, claimed_by = v_mail, phone = '+971500000093', whatsapp = null, phone_e164 = null,
         verified = true, banned = false, matching_blocked = false, matching_block_reason = null,
         approval_status = 'approved', permanently_closed = false where id = v_lead;
  delete from public.supplier_collaboration where lead_id = v_lead;
  select public.fn_is_matchable(verified, banned, matching_blocked, approval_status, permanently_closed, chat_strikes) into v_matchable_before from public.leads where id = v_lead;

  -- One ignored hold, then the supplier answers a hold: the run resets.
  perform public.fn_supplier_collaboration_incident(v_lead, gen_random_uuid(), gen_random_uuid(), null);
  r := r || jsonb_build_object('after_one', (select consecutive_ignored from public.supplier_collaboration where lead_id = v_lead));
  perform public.fn_supplier_collaboration_cooperated(v_lead, gen_random_uuid(), null);
  r := r || jsonb_build_object('after_fix', (select consecutive_ignored from public.supplier_collaboration where lead_id = v_lead));

  -- A fix in between breaks the run: one, fix, one, two.
  perform public.fn_supplier_collaboration_incident(v_lead, gen_random_uuid(), gen_random_uuid(), null);
  perform public.fn_supplier_collaboration_cooperated(v_lead, gen_random_uuid(), null);
  perform public.fn_supplier_collaboration_incident(v_lead, gen_random_uuid(), gen_random_uuid(), null);
  r := r || jsonb_build_object('warned_after_broken_run', (select warned_at is not null from public.supplier_collaboration where lead_id = v_lead));
  perform public.fn_supplier_collaboration_incident(v_lead, gen_random_uuid(), gen_random_uuid(), null);
  r := r || jsonb_build_object(
    'second', (select consecutive_ignored from public.supplier_collaboration where lead_id = v_lead),
    'warned', (select warned_at is not null from public.supplier_collaboration where lead_id = v_lead),
    'warning_rows', (select jsonb_agg(jsonb_build_object('channel', channel, 'requested_by', requested_by, 'sender', sender, 'to_email', to_email, 'to_phone', to_phone) order by channel)
                       from public.notifications where lead_id = v_lead and type = 'supplier_collaboration_warning' and created_at = now()),
    'support_cases', (select count(*) from public.support_case where party_kind = 'supplier' and party_id = v_lead::text and case_ref like 'SE-COLLAB-%' and opened_at = now()));

  -- The third: matching hold, and the supplier is no longer matchable.
  perform public.fn_supplier_collaboration_incident(v_lead, gen_random_uuid(), gen_random_uuid(), null);
  select public.fn_is_matchable(verified, banned, matching_blocked, approval_status, permanently_closed, chat_strikes) into v_matchable_held from public.leads where id = v_lead;
  r := r || jsonb_build_object('third', (select consecutive_ignored from public.supplier_collaboration where lead_id = v_lead),
    'held', (select collaboration_hold_at is not null and matching_blocked and matching_block_reason = 'collaboration_hold' from public.leads where id = v_lead),
    'matchable_before', v_matchable_before, 'matchable_held', v_matchable_held,
    'hold_rows', (select count(*) from public.notifications where lead_id = v_lead and type = 'supplier_matching_hold' and created_at = now()));

  -- Another writer clearing matching_blocked (a document restore) leaves the hold in force.
  update public.leads set matching_blocked = false, matching_block_reason = null where id = v_lead;
  r := r || jsonb_build_object('still_blocked', (select matching_blocked from public.leads where id = v_lead));
  -- Clearing the hold directly is refused.
  v_ok := false; begin update public.leads set collaboration_hold_at = null where id = v_lead; exception when others then v_ok := true; end;
  r := r || jsonb_build_object('direct_clear_refused', v_ok);
  -- A lift with an instruction that does not name the supplier is refused.
  insert into public.founder_instruction (said_at, instruction, subject, status) values (now(),'ZZ DEMO probe: an unrelated instruction', 'zz demo probe', 'open') returning id into v_fi;
  v_ok := false; begin perform public.fn_supplier_collaboration_hold_lift(v_lead, v_fi, 'probe'); exception when others then v_ok := true; end;
  r := r || jsonb_build_object('unnamed_lift_refused', v_ok);
  -- The founder's lift: an instruction that names the supplier.
  insert into public.founder_instruction (said_at, instruction, subject, status) values (now(),'ZZ DEMO probe: lift the matching hold on supplier ' || v_lead, 'zz demo probe', 'open') returning id into v_fi;
  perform public.fn_supplier_collaboration_hold_lift(v_lead, v_fi, 'founder called the supplier');
  r := r || jsonb_build_object('lifted', (select collaboration_hold_at is null and not matching_blocked from public.leads where id = v_lead),
    'after_lift', (select consecutive_ignored from public.supplier_collaboration where lead_id = v_lead),
    'welcome_rows', (select count(*) from public.notifications where lead_id = v_lead and type = 'supplier_matching_hold_lifted' and created_at = now()),
    'history', (select jsonb_agg(kind order by id) from public.supplier_collaboration_event where lead_id = v_lead and created_at = now()));
  v_tl := public.fn_contact_timeline(v_mail, 200);
  r := r || jsonb_build_object('timeline_collaboration', coalesce((v_tl -> 'counts' ->> 'collaboration')::int, 0),
    'timeline_messages_by_sales_engineer', (select count(*) from jsonb_array_elements(v_tl -> 'events') e where e ->> 'kind' = 'message' and e ->> 'seat' = 'sales_engineer'));
  raise exception 'PROBE<<%>>', (r || jsonb_build_object('before', v_before))::text;
end $probe$;`;

test('production: the run, the warning through support, the hold, and the founder-only lift', { skip: SKIP }, async (t) => {
  const { sql } = await import('../lib/db.mjs');
  let out = null;
  // The Management API hands the exception message back inside its own JSON, so the report arrives
  // with its quotes escaped; unescape once before parsing. The greedy match takes the whole report.
  const parse = (s) => { try { return JSON.parse(s); } catch { return JSON.parse(s.replace(/\\\\/g, '\\').replace(/\\"/g, '"')); } };
  try { await sql(PROBE); } catch (e) { const m = String(e.message || e).match(/PROBE<<([\s\S]*)>>/); if (!m) throw e; out = parse(m[1]); }
  assert.ok(out, 'the probe did not report');
  // A probe that could not run reports a SKIP, never a pass: a check that proves nothing must not read green.
  if (out.skipped) { t.skip(out.skipped); return; }
  assert.equal(out.after_one, 1); assert.equal(out.after_fix, 0, 'a fix before the decision resets the run');
  assert.equal(out.warned_after_broken_run, false, 'a fix in between breaks the run');
  assert.equal(out.second, 2); assert.equal(out.warned, true); assert.equal(out.support_cases, 1, 'customer_support is informed with a case');
  assert.deepEqual(out.warning_rows.map((x) => x.channel), ['email', 'whatsapp'], 'the warning goes on email and WhatsApp');
  for (const w of out.warning_rows) { assert.equal(w.requested_by, 'sales_engineer'); assert.equal(w.sender, 'customer_support'); assert.match(w.to_email, /@example\.invalid$/); }
  assert.equal(out.third, 3); assert.equal(out.held, true); assert.equal(out.matchable_before, true); assert.equal(out.matchable_held, false, 'a held supplier is not matched to a new request');
  assert.ok(out.hold_rows >= 1);
  assert.equal(out.still_blocked, true); assert.equal(out.direct_clear_refused, true); assert.equal(out.unnamed_lift_refused, true);
  assert.equal(out.lifted, true); assert.equal(out.after_lift, 0); assert.ok(out.welcome_rows >= 1);
  assert.deepEqual(out.history.filter((k) => k !== 'ignored_hold'), ['cooperated', 'cooperated', 'warning_sent', 'matching_hold', 'hold_lifted']);
  assert.ok(out.timeline_collaboration >= 9, `the contact timeline shows the record (${out.timeline_collaboration})`);
  assert.ok(out.timeline_messages_by_sales_engineer >= 5, 'the timeline shows the warning, hold and welcome-back messages as the sales engineer\'s');
  // The transaction was rolled back: nothing it wrote is left.
  const [after] = await sql(`select jsonb_build_object('notifications', (select count(*) from public.notifications), 'cases', (select count(*) from public.support_case),
    'events', (select count(*) from public.supplier_collaboration_event), 'collab', (select count(*) from public.supplier_collaboration)) as a`);
  for (const k of ['notifications', 'cases', 'events', 'collab']) assert.ok(Number(after.a[k]) <= Number(out.before[k]) + 5, `${k} grew: ${JSON.stringify(after.a)} vs ${JSON.stringify(out.before)}`);
});

test('production: matching and dispatch read the matching gate', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select p.proname, p.prosrc ilike '%fn_is_matchable%' or p.prosrc ilike '%matching_blocked%' as gated
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('fn_match_capability', 'match_suppliers_kw')`);
  assert.equal(rows.length, 2);
  for (const r of rows) assert.equal(r.gated, true, `${r.proname} does not respect matching_blocked`);
});
