// Demo identities never pair with real ones and nothing about them is dispatched (14 Sep 2026).
//
// The e2e harness (scripts/e2e/) creates ZZ DEMO customers and suppliers on the one production
// project. scripts/sql/demo_identities_are_marked_and_never_reach_a_real_person.sql makes that safe;
// this proves it on PRODUCTION inside an aborted transaction, so it leaves nothing behind:
//
//   1. the derived marker lands on a demo customer and a demo supplier, and not on real ones
//   2. a demo request is never matched to a real supplier, nor a real request to a demo supplier,
//      while demo-to-demo still matches (the harness needs that)
//   3. a demo supplier cannot quote a real request
//   4. a notification to a demo mobile, or to a REAL address about a demo supplier, is captured
//      (status 'suppressed') on insert; a queued row moved onto a demo mobile is captured on update
//   5. a control row to a real address about nothing demo is NOT captured
//
// The "real" parties use @quotesdone.com probe addresses: our own domain, so even a hypothetical
// escape reaches our own mailbox, never a stranger. Every write is rolled back by the final raise.
// Autodispatch is disarmed the documented way (routing.dispatched_at set) so no inquiry trigger
// calls out; pg_net requests are queued in-transaction and roll back with it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const TOKEN_FILE = join(homedir(), '.supabase', 'access-token');
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(TOKEN_FILE) ? readFileSync(TOKEN_FILE, 'utf8') : '')).trim();
const REF = 'htdblwldjkcgjvmqkbeh';

const PROBE = `do $$
declare
  v_dc uuid; v_rc uuid; v_dl bigint; v_rl bigint; v_di uuid; v_ri uuid;
  n_dd int; n_dr int; n_rd int; v_quote text := 'accepted';
  s_phone text; s_subject text; s_control text; s_update text; v_nid bigint;
  mk_dc boolean; mk_rc boolean; mk_dl boolean; mk_rl boolean;
begin
  insert into public.customers (id, email, full_name, phone)
    values (gen_random_uuid(), 'qd-probe-cust0@example.invalid', 'ZZ DEMO probe customer', '+971500000041') returning id into v_dc;
  insert into public.customers (id, email, full_name)
    values (gen_random_uuid(), 'e2e-probe-real-customer@quotesdone.com', 'Probe Real Customer') returning id into v_rc;
  insert into public.leads (company_name, email, source)
    values ('ZZ DEMO probe supplier', 'qd-probe-sup0@example.invalid', 'e2e_probe') returning id into v_dl;
  insert into public.leads (company_name, email, source)
    values ('Probe Real Supplier LLC', 'e2e-probe-real-supplier@quotesdone.com', 'e2e_probe') returning id into v_rl;
  select is_demo into mk_dc from public.customers where id = v_dc;
  select is_demo into mk_rc from public.customers where id = v_rc;
  select is_demo into mk_dl from public.leads where id = v_dl;
  select is_demo into mk_rl from public.leads where id = v_rl;

  insert into public.inquiries (customer_id, category, emirate, raw_input, summary, status, routing)
    values (v_dc, 'aluminium', 'Dubai', 'probe', 'probe', 'sent', jsonb_build_object('dispatched_at', now())) returning id into v_di;
  insert into public.inquiries (customer_id, category, emirate, raw_input, summary, status, routing)
    values (v_rc, 'aluminium', 'Dubai', 'probe', 'probe', 'sent', jsonb_build_object('dispatched_at', now())) returning id into v_ri;

  insert into public.inquiry_matches (inquiry_id, supplier_id) values (v_di, v_dl);
  insert into public.inquiry_matches (inquiry_id, supplier_id) values (v_di, v_rl);
  insert into public.inquiry_matches (inquiry_id, supplier_id) values (v_ri, v_dl);
  select count(*) into n_dd from public.inquiry_matches where inquiry_id = v_di and supplier_id = v_dl;
  select count(*) into n_dr from public.inquiry_matches where inquiry_id = v_di and supplier_id = v_rl;
  select count(*) into n_rd from public.inquiry_matches where inquiry_id = v_ri and supplier_id = v_dl;

  begin
    insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, source)
      values (v_ri, v_dl, 1000, 'draft', 'form');
  exception when others then v_quote := 'refused:' || sqlstate;
  end;

  insert into public.notifications (type, to_phone, channel, status, sender, body)
    values ('e2e_probe', '+971500000042', 'whatsapp', 'queued', 'customer_support', 'probe') returning status into s_phone;
  -- Roles supplier / customer on purpose: a10_notifications_founder_mail_policy drops (returns null)
  -- any founder/admin row not addressed to the founder himself, which would measure that policy, not this one.
  insert into public.notifications (type, to_email, to_role, lead_id, channel, status, sender, subject, body)
    values ('e2e_probe', 'e2e-probe-real-supplier@quotesdone.com', 'supplier', v_dl, 'email', 'queued', 'customer_support', 'probe', 'probe')
    returning status into s_subject;
  insert into public.notifications (type, to_email, to_role, channel, status, sender, subject, body)
    values ('e2e_probe', 'e2e-probe-control@quotesdone.com', 'customer', 'email', 'queued', 'customer_support', 'probe', 'probe')
    returning id, status into v_nid, s_control;
  update public.notifications set to_phone = '+971500000043', channel = 'whatsapp', status = 'queued' where id = v_nid;
  select status into s_update from public.notifications where id = v_nid;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'marker', jsonb_build_object('demo_customer', mk_dc, 'real_customer', mk_rc, 'demo_supplier', mk_dl, 'real_supplier', mk_rl),
    'matches', jsonb_build_object('demo_demo', n_dd, 'demo_real', n_dr, 'real_demo', n_rd),
    'quote', v_quote,
    'notifications', jsonb_build_object('demo_mobile', s_phone, 'real_addr_demo_subject', s_subject, 'control', s_control, 'moved_to_demo_mobile', s_update))::text;
end $$;`;

test('production: demo identities are marked, never meet real ones, and nothing about them is dispatched',
  { skip: !token && 'no SUPABASE_ACCESS_TOKEN (expected in CI)' }, async () => {
    const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
      method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: PROBE }),
    });
    const body = await r.text();
    const m = /CHK<<(\{.*\})>>/s.exec(body.replace(/\\"/g, '"'));
    assert.ok(m, `probe did not report (HTTP ${r.status}): ${body.slice(0, 400)}`);
    const x = JSON.parse(m[1]);
    assert.deepEqual(x.marker, { demo_customer: true, real_customer: false, demo_supplier: true, real_supplier: false });
    assert.deepEqual(x.matches, { demo_demo: 1, demo_real: 0, real_demo: 0 });
    assert.equal(x.quote, 'refused:23514');
    assert.equal(x.notifications.demo_mobile, 'suppressed');
    assert.equal(x.notifications.real_addr_demo_subject, 'suppressed');
    assert.ok(x.notifications.control && x.notifications.control !== 'suppressed', `control row: ${x.notifications.control}`);
    assert.equal(x.notifications.moved_to_demo_mobile, 'suppressed');
  });
