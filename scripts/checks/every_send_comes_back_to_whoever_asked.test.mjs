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
//   * fn_seat_handoff_act routes every delivery.result to the asking seat's close.
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
//   and nothing the probe queued could have reached a person, and none of it survives.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

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

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

const PROBE = `
do $probe$
declare
  n0 bigint; a0 bigint; c uuid; l bigint; v jsonb; w jsonb; ra bigint; rb bigint; rc bigint; rd bigint; re bigint; rr bigint;
  x public.agent_actions; y public.agent_actions; nid bigint; out jsonb := '{}'::jsonb; k int;
  cust text := 'zz-demo-loop-cust@example.invalid'; sup text := 'zz-demo-loop-sup@example.invalid';
  door_row jsonb;
begin
  select coalesce(max(id), 0) into n0 from public.notifications;
  select coalesce(max(id), 0) into a0 from public.agent_actions;
  insert into public.customers (full_name, email) values ('ZZ DEMO Loop Customer', cust) returning id into c;
  -- leads.is_demo is generated from the ZZ DEMO name and the reserved address; asserted, not assumed.
  insert into public.leads (company_name, email, claimed_by, whatsapp)
  values ('ZZ DEMO Loop Supplier', sup, sup, '+971500000077') returning id into l;
  if not (select is_demo from public.leads where id = l) then raise exception 'ZZFAIL: the fixture supplier is not marked demo'; end if;

  -- ── A. DELIVERED, CHECKED, CLOSED ──
  v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
         'type', 'new_quote', 'to_email', cust, 'to_role', 'customer', 'subject', 'ZZ DEMO probe A', 'body', 'ZZ DEMO probe A')));
  ra := (v->0->>'handoff_id')::bigint; nid := (v->0->>'notification_id')::bigint;
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
  try { await sql(PROBE); message = 'the probe returned without raising, so it did not roll back'; } catch (e) { message = String(e.message); }
  const chk = message.match(/CHK<<([\s\S]*?)>>/);
  assert.ok(chk, message.slice(0, 2000));
  const res = JSON.parse(chk[1].replace(/\\"/g, '"'));
  for (const k of ['A', 'B', 'C', 'D', 'E']) assert.ok(res[k], `scenario ${k} did not report`);
  assert.equal(res.reachable_rows, 0);
  console.log(JSON.stringify(res));
});
