// EVERY SEND COMES BACK TO WHOEVER ASKED FOR IT.
//
// Founder, 14 Sep 2026 (founder_instruction #207, verbatim): "always make sure things are in loop.
// nothing literally should ever be a one way communication".
//
// Statically (runs in CI without a token):
//   * no edge function writes the outbox table itself. The one door is _shared/deliver.ts, which
//     calls fn_customer_support_takes_delivery; every call site that used to write the table directly
//     now goes through it, and the scan must actually find those callers (a scan that finds nothing
//     proves nothing).
//   * no SQL routine except support's two door routines may mark a row as already tracked, and the
//     trigger that adopts every other row written to the outbox table exists.
// Against production (skipped without a management token), ONE aborted transaction, a pure probe with
// no DDL, on ZZ DEMO / @example.invalid identities and a reserved fixture mobile only:
//   A  delivered:   an edge-door notice, the dispatcher's success simulated (sent + provider id) ->
//                   a delivery.result to the sales engineer, which re-reads the row and closes it
//                   'confirmed'; nothing is filed as refund-ladder evidence.
//   B  suppressed:  the result makes the sales engineer RETRY on WhatsApp; that is suppressed too ->
//                   escalated to the CEO from the sales engineer, and the original shows how it ended.
//   C  refused:     support refuses a request (the accountant may not address a customer) -> the
//                   accountant gets 'not_queued' back and escalates; nothing is left failed and unread.
//   D  overdue:     a notice still queued 25 hours after it was queued -> raised to the CEO once.
//   E  another seat: an it_engineer notice comes back to the it_engineer and is escalated by it.
//   F  a routine's own insert: adopted at once as a request from the seat that owns the type, and it
//      comes back like any other; a row the door queued is never adopted a second time.
//   G  an adopted send the dispatcher FAILS: open at adoption (no result, no close), then it comes back
//      'failed' and the asking seat retries it on the other channel, then escalates -- never closes it.
//   H  the WhatsApp rule (#657): a supplier whose only number is the scraped listing gets no WhatsApp
//      retry; a customer with a verified mobile who never answered the WhatsApp question is retried by SMS.
//   and nothing the probe queued could have reached a person, and none of it survives.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';
import { seatWorkFixtures } from '../lib/seat_work_fixtures.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FNS = join(REPO, 'supabase', 'functions');
const DOOR = join(FNS, '_shared', 'deliver.ts');
const walk = (d) => readdirSync(d).flatMap((f) => {
  const p = join(d, f);
  return statSync(p).isDirectory() ? walk(p) : /\.tsx?$/.test(f) && !/\.test\./.test(f) ? [p] : [];
});
const rel = (p) => relative(REPO, p).split('\\').join('/');

// A write to the outbox table, however it is spelled: the supabase-js chain from the table to the end
// of its statement containing a write method, or raw SQL naming the table after an insert.
const TABLE_CHAIN = /\.from\(\s*(['"`])notifications\1\s*\)([^;]*)/g;
const WRITE_IN_CHAIN = /\.(insert|upsert)\s*\(/;
const RAW_SQL_WRITE = /insert\s+into\s+(public\.)?notifications\b/i;

test('no edge function writes the outbox table except through the door', () => {
  const offenders = [];
  let callers = 0;
  for (const f of walk(FNS)) {
    const src = readFileSync(f, 'utf8');
    for (const m of src.matchAll(TABLE_CHAIN)) {
      if (WRITE_IN_CHAIN.test(m[2])) offenders.push(`${rel(f)}:${src.slice(0, m.index).split('\n').length}`);
    }
    if (RAW_SQL_WRITE.test(src)) offenders.push(`${rel(f)}: raw SQL`);
    if (f !== DOOR && /\brequestDelivery\(/.test(src)) callers++;
  }
  assert.deepEqual(offenders, [], 'these write the outbox directly; call requestDelivery (supabase/functions/_shared/deliver.ts) instead');
  // The eight files that wrote it directly until 14 Sep 2026 (seven functions and the shared hold desk)
  // all call the door now.
  assert.ok(callers >= 8,`only ${callers} files call requestDelivery: the scan is not looking at the callers it replaced`);
  assert.match(readFileSync(DOOR, 'utf8'), /rpc\('fn_customer_support_takes_delivery'/, 'the door does not reach support');
});

// fn_seat_handoff_act, which hands every delivery.result to fn_originator_checks_delivery, is defined by
// ONE file: scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql (PR #634), as it is live. The
// production probe below proves that routing on the live routine; this file does not define it again.
test('the watch answers every request, and the routine file is in the index', () => {
  const file = readFileSync(join(REPO, 'scripts', 'sql', 'every_send_comes_back_to_whoever_asked.sql'), 'utf8');
  const watch = file.slice(file.lastIndexOf('create or replace function public.fn_customer_support_delivery_watch('));
  const selection = watch.slice(watch.indexOf('for q in'), watch.indexOf('loop', watch.indexOf('for q in')));
  // The selection used to admit only requests carrying a watch deadline. It must not filter on that key.
  assert.ok(!/watch_until/.test(selection), 'the watch again selects only watched requests: the others would never come back');
  assert.match(selection, /status in \('done', 'failed'\)/, 'a request support refused must come back too');
  for (const fn of ['fn_customer_support_takes_delivery', 'fn_originator_checks_delivery']) {
    assert.ok(file.includes(`create or replace function public.${fn}(`), `${fn} is not defined`);
  }
  const manifest = readFileSync(join(REPO, 'scripts', 'sql', 'MANIFEST.txt'), 'utf8').split('\n').filter((l) => l.endsWith('.sql'));
  assert.ok(manifest.includes('scripts/sql/every_send_comes_back_to_whoever_asked.sql'), 'the routine file has no MANIFEST line');
});

// THE SQL SIDE. A routine may write the table (20 live routines did, 14 Sep 2026); the adoption
// trigger loops every such row. The one way past it is the transaction-local tracked mark, so the
// mark may be written only inside the two routines that track the row themselves.
const SQL_DIR = join(REPO, 'scripts', 'sql');
// the_founder_gets_one_it_digest_per_tick.sql (15 Sep 2026) is the second: it now defines
// fn_customer_support_acts_on_handoff, and its digest routine closes every held request with the
// digest's notification ids, so the rows it marks are tracked by those requests.
// the_founder_hears_from_it_once_a_day.sql (22 Sep 2026) is the third: it redefines the digest, which
// still closes every request it tells the founder about with the digest's notification ids.
const TRACKING_FILES = new Set(['every_send_comes_back_to_whoever_asked.sql', 'the_founder_gets_one_it_digest_per_tick.sql',
  'the_founder_hears_from_it_once_a_day.sql',
  // 22 Sep 2026: redefines the watch (a WhatsApp waits for Twilio's delivery report); its one marking
  // routine is the watch's own email retry, carried over unchanged. Asserted below.
  'every_whatsapp_says_whether_it_arrived.sql',
  // 30 Sep 2026 (founder ruling 1090): redefines the digest with one added step (a founder-required credential
  // closes internal, never a line); its marking and the closing of every told request are carried over unchanged.
  'a_credential_only_the_founder_can_renew_is_never_rotated_or_reminded.sql',
  // 4 Oct 2026: redefines the digest to carry only founder decisions; its marking and the closing of every
  // told request with the digest's notification ids are carried over unchanged.
  'the_originator_closes_what_was_answered_and_the_digest_carries_only_his_decisions.sql',
  // 5 Oct 2026: redefines the digest with one added step (a notify=false integration closes internal); its marking
  // and the closing of every told request with the digest's notification ids are carried over unchanged.
  'an_integration_the_founder_holds_no_account_for_is_never_his_decision.sql',
  // 19 Oct 2026 (#1472): redefines the watch to finish under the API timeout; its one marking step is the watch's
  // own email retry, carried over unchanged and tracked by the request (retry_notification_id). Asserted below.
  'the_backup_prune_and_the_delivery_watch_finish_under_the_api_timeout.sql',
  // 19 Oct 2026 (#1560): redefines the digest (category gate, whole-word titles, owner it_engineer); its marking and the
  // closing of every told request with the digest's notification ids are carried over unchanged.
  'the_it_digest_reaches_the_founder_only_with_his_kind_of_decision_in_whole_words.sql']);
const MARK = /set_config\(\s*'app\.qd_delivery_tracked'/;
test('no SQL routine can switch off the tracking, and every other row is adopted', () => {
  const bypass = []; let writers = 0;
  for (const f of readdirSync(SQL_DIR).filter((x) => x.endsWith('.sql'))) {
    const src = readFileSync(join(SQL_DIR, f), 'utf8');
    if (!TRACKING_FILES.has(f) && MARK.test(src)) bypass.push(f);
    if (RAW_SQL_WRITE.test(src)) writers++;
  }
  assert.deepEqual(bypass, [], 'these files mark rows as tracked without tracking them');
  assert.ok(writers >= 10, `only ${writers} SQL files write the table: the scan is not reading the routines`);
  // WHICH ROUTINES MAY MARK, AND WHOSE COPY DECIDES (rewritten 23 Sep 2026, it_engineer).
  // This used to deep-equal a hard-coded pair per file, which asserted the wrong thing twice over: it
  // broke the moment a routine legitimately moved house (the superseded digest definition was removed
  // from the_founder_gets_one_it_digest_per_tick.sql on 22 Sep, and this check failed although the
  // estate was MORE correct afterwards), and it never asked the question that actually matters — the
  // body that runs is the one in the file that WINS scripts/sql/MANIFEST.txt, and that body is what has
  // to carry the marking. An older file keeping a marking copy is history and is fine; the winner
  // losing the marking would be a silent hole, and a winner outside TRACKING_FILES would be a routine
  // marking rows in a file nobody reviewed for it.
  const order = readFileSync(join(SQL_DIR, 'MANIFEST.txt'), 'utf8').split(/\r?\n/)
    .filter((l) => l.trim().endsWith('.sql')).map((l) => l.trim().replace(/^scripts\/sql\//, ''));
  const defs = (f) => readFileSync(join(SQL_DIR, f), 'utf8').split(/create or replace function public\./i).slice(1)
    .map((c) => ({ name: c.slice(0, c.indexOf('(')), marks: MARK.test(c.slice(0, c.length)) }));
  const canonical = new Map();          // routine -> { file, marks } from the LAST file in manifest order
  const markers = new Set();
  for (const f of order) {
    let list; try { list = defs(f); } catch { continue; }   // a manifest line whose file is gone is another check's finding
    for (const d of list) {
      canonical.set(d.name, { file: f, marks: d.marks });
      if (d.marks) markers.add(d.name);
    }
  }
  assert.deepEqual([...markers].sort(),
    ['fn_customer_support_acts_on_handoff', 'fn_customer_support_delivery_watch', 'fn_customer_support_sends_the_it_digest'],
    'a routine that marks a send as already tracked was added or removed; every one of them must be reviewed here');
  for (const r of markers) {
    const c = canonical.get(r);
    assert.ok(TRACKING_FILES.has(c.file), `${r}'s canonical file is ${c.file}, which is not one of the reviewed tracking files`);
    assert.ok(c.marks, `${r}'s canonical file ${c.file} defines it WITHOUT marking the send as tracked, so the deployed body leaves rows to the adoption trigger`);
  }
  const file = readFileSync(join(SQL_DIR, 'every_send_comes_back_to_whoever_asked.sql'), 'utf8');
  assert.match(file, /create trigger z90_every_send_is_tracked after insert on public\.notifications\s+for each row execute function public\.fn_customer_support_adopts_untracked_send\(\)/);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

const PROBE = `
do $probe$
declare
  n0 bigint; a0 bigint; c uuid; l bigint; v jsonb; w jsonb; ra bigint; rb bigint; rc bigint; rd bigint; re bigint; rr bigint;
  x public.agent_actions; y public.agent_actions; nid bigint; na bigint; rg bigint; rgr bigint; out jsonb := '{}'::jsonb; k int;
  cust text := 'zz-demo-loop-cust@example.invalid'; sup text := 'zz-demo-loop-sup@example.invalid';
  door_row jsonb;
  ch uuid; lh bigint; rh bigint; rhs bigint; hl text;
begin
  select coalesce(max(id), 0) into n0 from public.notifications;
  select coalesce(max(id), 0) into a0 from public.agent_actions;
  insert into public.customers (full_name, email) values ('ZZ DEMO Loop Customer', cust) returning id into c;
  -- leads.is_demo is generated from the ZZ DEMO name and the reserved address; asserted, not assumed.
  -- #657 (founder, 14 Sep 2026): WhatsApp goes only to a CONFIRMED number. The retries in B and G need one,
  -- so the fixture supplier confirmed +971500000077 as a different WhatsApp number (verified by code). It
  -- used to carry it in leads.whatsapp, the scraped listing column, which is no longer a route (see H1).
  insert into public.leads (company_name, email, claimed_by, whatsapp_opt, whatsapp_phone, whatsapp_verified_at)
  values ('ZZ DEMO Loop Supplier', sup, sup, 'other', '+971500000077', now()) returning id into l;
  if not (select is_demo from public.leads where id = l) then raise exception 'ZZFAIL: the fixture supplier is not marked demo'; end if;

  -- ── A. DELIVERED, CHECKED, CLOSED ──
  v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
         'type', 'new_quote', 'to_email', cust, 'to_role', 'customer', 'subject', 'ZZ DEMO probe A', 'body', 'ZZ DEMO probe A')));
  ra := (v->0->>'handoff_id')::bigint; nid := (v->0->>'notification_id')::bigint; na := nid;
  if v->0->>'seat' <> 'sales_engineer' or v->0->>'status' <> 'done' or nid is null then raise exception 'ZZFAIL: A door %', v; end if;
  if not exists (select 1 from public.notifications where id = nid and requested_by = 'sales_engineer' and sender = 'customer_support'
                   and status = 'suppressed') then
    raise exception 'ZZFAIL: A the queued row does not name its requester, or the demo capture did not hold it';
  end if;
  update public.notifications set status = 'sent', sent_at = now(), provider_message_id = 'zz-demo-probe-a' where id = nid;
  w := public.fn_customer_support_delivery_watch(ra);
  select * into x from public.agent_actions where id = ra;
  select * into y from public.agent_actions where id = (x.detail->>'result_handoff_id')::bigint;
  if x.detail->>'result' <> 'delivered' or x.detail->>'loop' <> 'confirmed' or x.detail->>'closed_by' <> 'sales_engineer'
     or y.agent <> 'sales_engineer' or y.status <> 'done' or y.detail->>'type' <> 'delivery.result' then
    raise exception 'ZZFAIL: A not closed on proof: % / %', x.detail, y.status;
  end if;
  if exists (select 1 from public.refund_ladder_evidence where request_handoff_id = ra) then
    raise exception 'ZZFAIL: A a plain delivery was filed as refund-ladder evidence';
  end if;
  if (public.fn_customer_support_delivery_watch(ra)->>'results_returned')::int <> 0 then raise exception 'ZZFAIL: A answered twice'; end if;
  out := out || jsonb_build_object('A', jsonb_build_object('result', x.detail->>'result', 'loop', x.detail->>'loop',
                                   'checked', x.detail->'close_check'->>'provider_message_id'));

  -- ── B. SUPPRESSED -> RETRY ON WHATSAPP -> SUPPRESSED -> ESCALATED ──
  v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
         'type', 'rfq_addendum', 'to_email', sup, 'to_role', 'supplier', 'lead_id', l, 'subject', 'ZZ DEMO probe B', 'body', 'ZZ DEMO probe B')));
  rb := (v->0->>'handoff_id')::bigint;
  w := public.fn_customer_support_delivery_watch(rb);
  select * into x from public.agent_actions where id = rb;
  rr := (x.detail->>'retry_request_id')::bigint;
  if x.detail->>'result' <> 'suppressed' or x.detail->>'loop' <> 'retried_on_whatsapp' or rr is null then
    raise exception 'ZZFAIL: B the sales engineer did not retry on the other channel: %', x.detail;
  end if;
  select * into y from public.agent_actions where id = rr;
  if (y.detail->>'retry_of')::bigint <> rb or not exists (
       select 1 from public.notifications n where n.id = (y.evidence->>'notification_id')::bigint
          and n.channel = 'whatsapp' and n.to_phone = '+971500000077' and n.status = 'suppressed') then
    raise exception 'ZZFAIL: B the retry is not a held WhatsApp to the fixture mobile: %', y.evidence;
  end if;
  w := public.fn_customer_support_delivery_watch(rr);
  select * into y from public.agent_actions where id = rr;
  select * into x from public.agent_actions where id = rb;
  if y.detail->>'loop' <> 'escalated' or x.detail->>'loop' <> 'retry_escalated' or not exists (
       select 1 from public.support_ceo_report where idempotency_key = 'delivery_undelivered:' || rr and source_agent = 'sales_engineer') then
    raise exception 'ZZFAIL: B the failed retry was not escalated by the sales engineer: % / %', y.detail, x.detail->>'loop';
  end if;
  out := out || jsonb_build_object('B', jsonb_build_object('first', 'suppressed -> retried_on_whatsapp', 'retry', 'suppressed -> escalated',
                                   'original_loop', x.detail->>'loop'));

  -- ── C. REFUSED BY SUPPORT -> THE ASKING SEAT HEARS AND ACTS ──
  v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
         'type', 'zz_demo_probe_notice', 'requested_by', 'accountant', 'to_email', cust, 'to_role', 'customer',
         'subject', 'ZZ DEMO probe C', 'body', 'ZZ DEMO probe C')));
  rc := (v->0->>'handoff_id')::bigint;
  if v->0->>'status' <> 'failed' or v->0->>'error' is null or v->0->>'notification_id' is not null then
    raise exception 'ZZFAIL: C support queued what it must refuse: %', v;
  end if;
  w := public.fn_customer_support_delivery_watch(rc);
  select * into x from public.agent_actions where id = rc;
  select * into y from public.agent_actions where id = (x.detail->>'result_handoff_id')::bigint;
  if x.detail->>'result' <> 'not_queued' or y.agent <> 'accountant' or x.detail->>'loop' <> 'escalated' or not exists (
       select 1 from public.support_ceo_report where idempotency_key = 'delivery_undelivered:' || rc and source_agent = 'accountant') then
    raise exception 'ZZFAIL: C the refusal did not come back to the accountant and get escalated: %', x.detail;
  end if;
  out := out || jsonb_build_object('C', jsonb_build_object('result', 'not_queued', 'to', y.agent, 'loop', x.detail->>'loop'));

  -- ── D. NOT TERMINAL IN 24 HOURS -> A FINDING FOR THE CEO, ONCE ──
  -- No address, no number and no lead: this row cannot reach anyone even if it were committed, and it
  -- is not. (An ADMIN row with no address is not usable here: a BEFORE trigger declines to insert it at
  -- all, measured 14 Sep 2026, and that request correctly comes back 'not_sent' and is escalated.)
  v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
         'type', 'rfq_addendum', 'to_role', 'supplier', 'subject', 'ZZ DEMO probe D', 'body', 'ZZ DEMO probe D')));
  rd := (v->0->>'handoff_id')::bigint; nid := (v->0->>'notification_id')::bigint;
  if nid is null then raise exception 'ZZFAIL: D nothing was queued to go overdue: %', v; end if;
  update public.notifications set status = 'queued', created_at = now() - interval '25 hours' where id = nid;
  w := public.fn_customer_support_delivery_watch(rd);
  select * into x from public.agent_actions where id = rd;
  if (w->>'overdue_raised')::int <> 1 or x.detail->>'overdue_report_id' is null or x.detail ? 'result'
     or not exists (select 1 from public.support_ceo_report where idempotency_key = 'delivery_overdue:' || rd and source_agent = 'customer_support') then
    raise exception 'ZZFAIL: D an overdue delivery was not raised: % / %', w, x.detail;
  end if;
  if (public.fn_customer_support_delivery_watch(rd)->>'overdue_raised')::int <> 0 then raise exception 'ZZFAIL: D raised twice'; end if;
  out := out || jsonb_build_object('D', jsonb_build_object('overdue_raised', 1, 'still_waiting', true));

  -- ── E. ANOTHER SEAT HEARS BACK TOO ──
  v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
         'type', 'wa_templates_ready', 'to_role', 'admin', 'to_email', 'zz-demo-loop-founder@example.invalid',
         'subject', 'ZZ DEMO probe E', 'body', 'ZZ DEMO probe E')));
  re := (v->0->>'handoff_id')::bigint;
  w := public.fn_customer_support_delivery_watch(re);
  select * into x from public.agent_actions where id = re;
  select * into y from public.agent_actions where id = (x.detail->>'result_handoff_id')::bigint;
  if v->0->>'seat' <> 'it_engineer' or y.agent <> 'it_engineer' or y.status <> 'done' or x.detail->>'closed_by' <> 'it_engineer' then
    raise exception 'ZZFAIL: E the it_engineer did not hear back: % / %', v, x.detail;
  end if;
  out := out || jsonb_build_object('E', jsonb_build_object('seat', 'it_engineer', 'result', x.detail->>'result', 'loop', x.detail->>'loop'));

  -- ── F. A ROUTINE'S OWN INSERT IS ADOPTED, AND COMES BACK ──
  insert into public.notifications (type, to_email, to_role, lead_id, channel, subject, body, status)
  values ('quote_coaching', sup, 'supplier', l, 'email', 'ZZ DEMO probe F', 'ZZ DEMO probe F', 'queued') returning id into nid;
  select * into x from public.agent_actions where kind = 'handoff' and target_id = 'delivery.request:notification:' || nid;
  if x.id is null or x.detail->>'from' <> 'sales_engineer' or (x.evidence->>'notification_id')::bigint <> nid
     or not coalesce((x.detail->>'adopted')::boolean, false) then
    raise exception 'ZZFAIL: F the routine''s row was not adopted: %', x.detail;
  end if;
  w := public.fn_customer_support_delivery_watch(x.id);
  select * into x from public.agent_actions where id = x.id;
  if x.detail->>'result' <> 'suppressed' or x.detail->>'closed_by' <> 'sales_engineer' or x.detail->>'loop' is null then
    raise exception 'ZZFAIL: F the adopted send did not come back and get acted on: %', x.detail;
  end if;
  -- the door's own row (A) is tracked by its request alone
  if (select count(*) from public.agent_actions where kind = 'handoff' and detail->>'type' = 'delivery.request'
        and (evidence->>'notification_id')::bigint = na) <> 1 then
    raise exception 'ZZFAIL: F the door''s row was adopted a second time';
  end if;
  out := out || jsonb_build_object('F', jsonb_build_object('adopted_from', 'sales_engineer', 'result', x.detail->>'result', 'loop', x.detail->>'loop'));

  -- ── G. AN ADOPTED SEND THAT FAILS LATER IS RETRIED, THEN ESCALATED -- NEVER CLOSED ──
  insert into public.notifications (type, to_email, to_role, lead_id, channel, subject, body, status)
  values ('doc_final_notice', sup, 'supplier', l, 'email', 'ZZ DEMO probe G', 'ZZ DEMO probe G', 'queued') returning id into nid;
  select * into x from public.agent_actions where kind = 'handoff' and target_id = 'delivery.request:notification:' || nid;
  rg := x.id;
  if rg is null or x.detail ? 'result' or x.detail ? 'loop' or x.detail ? 'closed_by'
     or coalesce((x.evidence->>'delivered')::boolean, false) or not coalesce((x.evidence->>'queued')::boolean, false) then
    raise exception 'ZZFAIL: G adoption claimed more than queued, or closed the loop: % / %', x.detail, x.evidence;
  end if;
  -- the dispatcher's failure, simulated after adoption (the reserved address never reaches Resend)
  update public.notifications set status = 'failed', attempts = 3, last_error = 'ZZ DEMO probe G: provider rejected' where id = nid;
  w := public.fn_customer_support_delivery_watch(rg);
  select * into x from public.agent_actions where id = rg;
  rgr := (x.detail->>'retry_request_id')::bigint;
  if x.detail->>'result' <> 'failed' or x.detail->>'loop' <> 'retried_on_whatsapp' or rgr is null then
    raise exception 'ZZFAIL: G the failed adopted send was not retried on the other channel: %', x.detail;
  end if;
  w := public.fn_customer_support_delivery_watch(rgr);
  select * into y from public.agent_actions where id = rgr;
  select * into x from public.agent_actions where id = rg;
  if y.detail->>'loop' <> 'escalated' or x.detail->>'loop' <> 'retry_escalated' or not exists (
       select 1 from public.support_ceo_report where idempotency_key = 'delivery_undelivered:' || rgr and source_agent = 'sales_engineer') then
    raise exception 'ZZFAIL: G the failed retry was not escalated: % / %', y.detail, x.detail->>'loop';
  end if;
  out := out || jsonb_build_object('G', jsonb_build_object('at_adoption', 'open, queued', 'first', 'failed -> retried_on_whatsapp',
                                   'retry', 'suppressed -> escalated', 'original_loop', x.detail->>'loop'));

  -- ── H. THE WHATSAPP RULE (#657): AN UNCONFIRMED NUMBER IS NEVER A ROUTE; A VERIFIED MOBILE STILL GETS SMS ──
  -- H1: a supplier whose only number is the scraped listing (leads.whatsapp) and who never confirmed one.
  insert into public.leads (company_name, email, claimed_by, whatsapp)
  values ('ZZ DEMO Loop Supplier Unconfirmed', 'zz-demo-loop-sup-unconf@example.invalid', 'zz-demo-loop-sup-unconf@example.invalid', '+971500000079')
  returning id into lh;
  v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
         'type', 'rfq_addendum', 'to_email', 'zz-demo-loop-sup-unconf@example.invalid', 'to_role', 'supplier', 'lead_id', lh,
         'subject', 'ZZ DEMO probe H1', 'body', 'ZZ DEMO probe H1')));
  rh := (v->0->>'handoff_id')::bigint;
  w := public.fn_customer_support_delivery_watch(rh);
  select * into x from public.agent_actions where id = rh;
  hl := x.detail->>'loop';
  if x.detail->>'result' <> 'suppressed' or coalesce(hl, '') like 'retried_on_whatsapp%' then
    raise exception 'ZZFAIL: H1 an unconfirmed (scraped) number was used for a WhatsApp retry: %', x.detail;
  end if;
  if exists (select 1 from public.notifications n where n.id > n0 and n.to_phone = '+971500000079' and n.status <> 'skipped') then
    raise exception 'ZZFAIL: H1 a WhatsApp row was queued to the unconfirmed number';
  end if;
  -- H2: a customer who verified the mobile before #657 and never answered the WhatsApp question. #657's
  -- design: no WhatsApp for them, but the undelivered email is still retried by SMS on the verified mobile.
  insert into public.customers (full_name, email, phone, phone_verified)
  values ('ZZ DEMO Loop Customer SMS', 'zz-demo-loop-cust-sms@example.invalid', '+971500000078', true) returning id into ch;
  v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
         'type', 'new_quote', 'to_email', 'zz-demo-loop-cust-sms@example.invalid', 'to_role', 'customer',
         'subject', 'ZZ DEMO probe H2', 'body', 'ZZ DEMO probe H2')));
  rhs := (v->0->>'handoff_id')::bigint;
  w := public.fn_customer_support_delivery_watch(rhs);
  select * into x from public.agent_actions where id = rhs;
  if x.detail->>'result' <> 'suppressed' or x.detail->>'loop' <> 'retried_on_sms' or (x.detail->>'retry_request_id') is null then
    raise exception 'ZZFAIL: H2 a verified mobile with the WhatsApp question unanswered was not retried by SMS: %', x.detail;
  end if;
  select * into y from public.agent_actions where id = (x.detail->>'retry_request_id')::bigint;
  if not exists (select 1 from public.notifications n where n.id = (y.evidence->>'notification_id')::bigint
                   and n.channel = 'sms' and n.to_phone = '+971500000078') then
    raise exception 'ZZFAIL: H2 the retry is not an SMS to the verified mobile: % / %', y.status, y.evidence;
  end if;
  out := out || jsonb_build_object('H', jsonb_build_object('unconfirmed_supplier', 'suppressed -> ' || coalesce(hl, 'no retry'),
                                   'verified_mobile_unanswered', 'suppressed -> retried_on_sms'));

  -- ── NOTHING COULD HAVE REACHED A PERSON ──
  select count(*) into k from public.notifications n
   where n.id > n0 and ((n.to_email is not null and n.to_email !~* '@example[.]invalid$')
                        or (n.to_phone is not null and not public.fn_is_demo_phone(n.to_phone))
                        or (n.status = 'sent' and n.provider_message_id is distinct from 'zz-demo-probe-a'));
  if k <> 0 then raise exception 'ZZFAIL: % queued row(s) had a real address or were sent', k; end if;
  out := out || jsonb_build_object('rows_queued', (select count(*) from public.notifications where id > n0),
                                   'handoffs', (select count(*) from public.agent_actions where id > a0 and kind = 'handoff'),
                                   'reachable_rows', k);
  raise exception 'CHK<<%>>', out::text;
end $probe$;`;

test('production: every send comes back and the asking seat closes or acts (aborted transaction)', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  let message = '';
  // Ruling 1199 (#1479, demo_activity_files_no_seat_task_or_handoff.sql) files no handoff for a ZZ DEMO subject, so
  // a_demo_delivery_request_is_captured_not_refused.sql (#1479) answers 'demo_captured' with no handoff. This probe
  // proves the delivery loop's handoffs on ZZ DEMO fixtures, so it switches that guard off for its own rolled-back
  // transaction (scripts/lib/seat_work_fixtures.mjs).
  try { await replaySql(seatWorkFixtures() + '\n;\n' + PROBE); message = 'the probe returned without raising, so it did not roll back'; } catch (e) { message = String(e.message); }
  const chk = message.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(chk, message.slice(0, 2000));
  const res = JSON.parse(chk[1].replace(/\\"/g, '"'));
  for (const k of ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']) assert.ok(res[k], `scenario ${k} did not report`);
  assert.equal(res.reachable_rows, 0);
  console.log(JSON.stringify(res));
});
