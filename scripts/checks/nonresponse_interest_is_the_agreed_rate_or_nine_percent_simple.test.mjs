// NON-RESPONSE INTEREST IS THE AGREED RATE, OR 9% WHERE NONE WAS AGREED, AND ALWAYS SIMPLE (30 Sep 2026, accountant;
// founder ruling ledger 1086, Federal Decree-Law 50/2022).
//
// MEASURED BEFORE THE FIX: fn_accountant_nonresponse_charge gave a supplier with no agreed rate
// least(pricing_config APR, coalesce(cap row, pricing_config APR)) with no literal ceiling. With the policy rows at 50%
// (the aborted probe below, run against the production body) it charged such a supplier 50%.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: the SQL loses the 0.09 literal on the no-agreed-rate branch or the 0.12 ceiling on v14; supplier_charge.ts
//     accepts a rate no signed version names; fn_supplier_dues_accrue_interest adds interest to what it already holds;
//     the file carries both (or neither of) a pending note and a MANIFEST line;
//   * production, ONE aborted transaction (the file replayed first while it is pending; nothing commits), ZZ DEMO
//     suppliers at @example.invalid only, pricing_config and every rate policy row raised to 50%:
//       a v14 signer -> 12% simple; a v12 signer -> 9%; a supplier with no version -> 9%;
//       two billing periods 30 days apart: interest = principal x rate x days / 365 in both, never interest on interest;
//       a supplier who pays half on day 100 after the due date: interest and total equal supplier_charge.ts computeCharge()
//       to the fils (before the fix the database charged interest on the paid half for the remaining 265 days);
//       that part payment goes through fn_accountant_record_supplier_payment (a second call with the same reference is
//       refused, and a half payment does not mark the due paid); a Stripe settlement (the webhook's own write, delivered
//       twice) leaves exactly one full-payment row and the charge shows nothing outstanding.
//
//   node --test scripts/checks/nonresponse_interest_is_the_agreed_rate_or_nine_percent_simple.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';
import { computeCharge, addDays, DUE_AFTER_NOTICE_DAYS } from '../../supabase/functions/_shared/supplier_charge.ts';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/nonresponse_interest_is_the_agreed_rate_or_nine_percent.sql';
const FILE2 = 'scripts/sql/every_nonresponse_due_settlement_is_a_payment_row.sql';
const pending = (f = FILE) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));
const code = (s) => s.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');

test('static: every branch carries its literal, the documents name only signed rates, accrual never compounds', () => {
  const sql = code(read(FILE));
  assert.match(sql, /v_apr\s+:= least\(coalesce\(c\.supplier_nonresponse_interest_apr, 0\.09\), coalesce\(v_cap, 0\.09\), 0\.09\);/, 'the no-agreed-rate branch has no literal 9% ceiling');
  assert.match(sql, /'supplier_nonresponse_interest_apr_from_v14'\), 0\.12\), 0\.12\);/, 'the v14 branch has no 12% ceiling');
  assert.match(sql, /v_acc_int := v_acc_int \+ v_out \* v_apr \* \(greatest\(v_due, v_pay\.paid_on\) - v_from\) \/ 365\.0;/, 'interest does not run on the outstanding principal between payments');
  assert.match(sql, /v_out\s+:= v_out - v_on_pr;/, 'a payment does not reduce the principal');
  assert.match(sql, /v_int\s+:= greatest\(0, round\(v_acc_int, 2\) - v_overpay\);/, 'interest is not the simple accrual');
  assert.doesNotMatch(sql, /v_out\s*:=\s*v_out\s*\+/, 'interest is added to the principal');
  const ts = read('supabase/functions/_shared/supplier_charge.ts');
  assert.match(ts, /export const INTEREST_RATE_PA = 0\.09;/);
  assert.match(ts, /export const INTEREST_RATE_PA_FROM_V14 = 0\.12;/);
  assert.match(ts, /if \(rate !== INTEREST_RATE_PA && rate !== INTEREST_RATE_PA_FROM_V14\) throw/, 'computeCharge() accepts any rate');
  const mirror = readSchemaMirror();
  const at = mirror.indexOf('FUNCTION public.fn_supplier_dues_accrue_interest(');
  const accrue = mirror.slice(at);
  assert.ok(at > 0 && /set interest_amount = \(v->>'interest_aed'\)::numeric/.test(accrue.slice(0, 4000)), 'fn_supplier_dues_accrue_interest no longer overwrites interest from the fresh charge');
  assert.doesNotMatch(accrue.slice(0, 4000), /interest_amount\s*=\s*(coalesce\()?\s*interest_amount\s*\+/, 'accrual adds interest to interest');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim());
  for (const f of [FILE, FILE2]) assert.ok(pending(f) !== manifest.includes(f), f + ': exactly one of a pending note and a MANIFEST line');
  const s2 = code(read(FILE2));
  assert.match(s2, /after insert or update of paid_at on public\.supplier_dues/, 'no trigger records a settlement as a payment row');
  assert.match(s2, /revoke execute on function public\.fn_accountant_record_supplier_payment\(bigint, numeric, date, text, text\) from public, anon, authenticated;/, 'the routine is not revoked');
  assert.match(s2, /round\(p_amount, 2\) > v_owed/, 'the bank-payment routine accepts more than is owed');
  assert.match(s2, /check \(entered_by in \('accountant', 'service'\)\)/, 'a payment row does not say who entered it');
  assert.match(s2, /from public\.supplier_due_checkouts c/, 'a Stripe settlement row does not read the amount stored at checkout');
  assert.match(read('supabase/functions/supplier_pay/index.ts'), /from\('supplier_due_checkouts'\)\s*\.insert\(/, 'supplier_pay does not store what each session charges');
  assert.match(read('supabase/functions/stripe_webhook/index.ts'), /payment_ref: payRef, stripe_session_id: String\(s\.id\)/, 'stripe_webhook does not record which session was paid');
  assert.match(s2, /unique \(due_id, reference\)/, 'a reference can be recorded twice');
  assert.match(s2, /total_claim = v_owed,/, 'the portal figure (total_claim) does not reflect recorded payments');
  const pay = read('supabase/functions/supplier_pay/index.ts');
  assert.match(pay, /admin\.rpc\('fn_supplier_dues_outstanding'/, 'supplier_pay does not bill the live outstanding figure');
  assert.doesNotMatch(pay, /Number\(d\.amount_due \|\| 0\) \+ Number\(d\.admin_fee \|\| 0\)/, 'supplier_pay sums the stored columns again');
});

export const PROBE = `
do $$
declare v14 bigint; v12 bigint; v0 bigint; vp bigint; dp bigint; t14 uuid; t12 uuid; t0 uuid; tp uuid; pre jsonb; rec jsonb; rec2 jsonb; vs bigint; ds bigint; ts_ uuid; st jsonb; pr jsonb; sp jsonb; chk jsonb; vr bigint; dr bigint; tr uuid; dn bigint; dv bigint; dz bigint; dq bigint; r_prev numeric; r_today numeric; ov jsonb; rv jsonb; g jsonb; d date := (now() at time zone 'Asia/Dubai')::date; out jsonb := '{}';
begin
  update public.pricing_config set supplier_nonresponse_interest_apr = 0.5;
  update public.decision_policy set value = to_jsonb(0.5) where key in ('supplier_charge_max_lawful_apr', 'supplier_nonresponse_interest_apr_from_v14');
  insert into public.leads (company_name, email, accepted_terms_version, accepted_terms_at) values
    ('ZZ DEMO interest probe v14 (QuotesDone fixture, not a real company)', 'zz-demo-interest-v14@example.invalid', 'v14', now() - interval '30 days') returning id into v14;
  insert into public.leads (company_name, email, accepted_terms_version, accepted_terms_at) values
    ('ZZ DEMO interest probe v12 (QuotesDone fixture, not a real company)', 'zz-demo-interest-v12@example.invalid', 'v12', now() - interval '30 days') returning id into v12;
  insert into public.leads (company_name, email) values
    ('ZZ DEMO interest probe no version (QuotesDone fixture, not a real company)', 'zz-demo-interest-none@example.invalid') returning id into v0;
  insert into public.transactions (supplier_id, revealed_at, total_charged, reveal_fee, refund_amount_aed, refund_status, refund_confirmed_at)
    values (v14, now() - interval '20 days', 300, 300, 300, 'refunded', now() - interval '10 days') returning id into t14;
  insert into public.transactions (supplier_id, revealed_at, total_charged, reveal_fee, refund_amount_aed, refund_status, refund_confirmed_at)
    values (v12, now() - interval '20 days', 300, 300, 300, 'refunded', now() - interval '10 days') returning id into t12;
  insert into public.transactions (supplier_id, revealed_at, total_charged, reveal_fee, refund_amount_aed, refund_status, refund_confirmed_at)
    values (v0, now() - interval '20 days', 300, 300, 300, 'refunded', now() - interval '10 days') returning id into t0;
  -- BANK PART PAYMENT: a supplier with no agreed rate, notified 400 days ago (so the due date is in the past), pays HALF
  -- the principal 100 days after the due date, recorded through the accountant's routine; read 365 days after the due.
  insert into public.leads (company_name, email) values
    ('ZZ DEMO interest probe part payer (QuotesDone fixture, not a real company)', 'zz-demo-interest-part@example.invalid') returning id into vp;
  insert into public.transactions (supplier_id, revealed_at, total_charged, reveal_fee, refund_amount_aed, refund_status, refund_confirmed_at)
    values (vp, now() - interval '420 days', 300, 300, 300, 'refunded', now() - interval '410 days') returning id into tp;
  insert into public.supplier_dues (transaction_id, supplier_id, amount_due, admin_fee, status) values (tp, vp, 300, 250, 'open') returning id into dp;
  -- the delivered notice the charge dates from, as a bare row: its triggers (handoff notes, outbox) are held for this
  -- one insert, so the aborted probe can never reach a delivery path or a real person
  set local session_replication_role = replica;
  insert into public.agent_actions (agent, kind, status, target_id, decided_at, evidence, detail)
    values ('customer_support', 'handoff', 'done', 'delivery.request:nonresponse_charge:' || dp, now() - interval '400 days', '{"delivered": true}',
            '{"summary": {"known": "ZZ DEMO probe fixture", "tried": [], "needed": "nothing, aborted probe", "evidence": "ZZ DEMO"}}');
  set local session_replication_role = origin;
  pre := public.fn_accountant_nonresponse_charge(tp, null);
  rec := public.fn_accountant_record_supplier_payment(dp, 275, (pre->>'due_date')::date + 100, 'ZZ-DEMO-BANK-TRANSFER-1');
  rec2 := public.fn_accountant_record_supplier_payment(dp, 275, (pre->>'due_date')::date + 100, 'ZZ-DEMO-BANK-TRANSFER-1');
  -- GAP 1: an overpayment attempt is refused, raises an accountant finding and records nothing
  ov := public.fn_accountant_record_supplier_payment(dp, 10000, d, 'ZZ-DEMO-BANK-OVERPAY');
  g := jsonb_build_object('over_ok', ov->'ok', 'over_rows', (select count(*) from public.supplier_due_payments where reference = 'ZZ-DEMO-BANK-OVERPAY'),
         'over_finding', (select count(*) from public.it_engineer_finding where issue_key = 'acct:supplier_overpayment:' || dp || ':ZZ-DEMO-BANK-OVERPAY'),
         'principal_min', (public.fn_accountant_nonresponse_charge(tp, null)->>'unpaid_principal_aed')::numeric,
         'bad_entered_by_ok', public.fn_accountant_record_supplier_payment(dp, 1, d, 'ZZ-DEMO-BANK-WHO', 'customer')->'ok');
  -- GAP 2: who and when on the accountant's row
  g := g || jsonb_build_object('acct_row', (select jsonb_build_object('by', entered_by, 'at', created_at is not null) from public.supplier_due_payments where due_id = dp and reference = 'ZZ-DEMO-BANK-TRANSFER-1'));
  out := jsonb_build_object('part', jsonb_build_array(public.fn_accountant_nonresponse_charge(tp, (pre->>'due_date')::date + 365)),
    'part_rec', jsonb_build_object('ok', rec->'ok', 'dup_ok', rec2->'ok', 'rows', (select count(*) from public.supplier_due_payments where due_id = dp),
      'paid_at_set', (select paid_at is not null from public.supplier_dues where id = dp)));
  -- CHECKOUT: supplier_pay bills fn_supplier_dues_outstanding today; the portal's stored total_claim after the accrual
  chk := public.fn_supplier_dues_outstanding(array[dp], null) -> dp::text;
  perform public.fn_supplier_dues_accrue_interest(null);
  out := jsonb_set(out, '{part_rec,checkout}', jsonb_build_object('owed', chk->'owed_aed', 'today', d,
           'total_claim', (select total_claim from public.supplier_dues where id = dp)));
  -- the rest then settles through Stripe: the settlement row is the remainder billed, never the whole stored figure
  insert into public.supplier_due_checkouts (session_id, due_id, amount_aed) values ('cs_ZZDEMO_rest', dp, (chk->>'owed_aed')::numeric);
  update public.supplier_dues set status = 'paid', paid_at = now(), payment_ref = 'pi_ZZDEMO_rest', stripe_session_id = 'cs_ZZDEMO_rest' where id = dp and paid_at is null;
  -- GAP 1: a due already paid refuses a bank payment
  g := g || jsonb_build_object('paid_due_ok', public.fn_accountant_record_supplier_payment(dp, 1, d, 'ZZ-DEMO-BANK-AFTER')->'ok',
         'svc_row_by', (select entered_by from public.supplier_due_payments where due_id = dp and reference = 'pi_ZZDEMO_rest'));
  out := jsonb_set(out, '{part_rec,settle}', jsonb_build_object(
           'rest_row', (select amount_aed from public.supplier_due_payments where due_id = dp and reference = 'pi_ZZDEMO_rest'),
           'rows', (select count(*) from public.supplier_due_payments where due_id = dp),
           'after', public.fn_accountant_nonresponse_charge(tp, null) -> 'total_aed'));
  -- STRIPE FULL PAYMENT: the webhook's own write (status paid, paid_at, payment_ref), delivered twice
  insert into public.leads (company_name, email) values
    ('ZZ DEMO interest probe stripe payer (QuotesDone fixture, not a real company)', 'zz-demo-interest-stripe@example.invalid') returning id into vs;
  insert into public.transactions (supplier_id, revealed_at, total_charged, reveal_fee, refund_amount_aed, refund_status, refund_confirmed_at)
    values (vs, now() - interval '20 days', 300, 300, 300, 'refunded', now() - interval '10 days') returning id into ts_;
  insert into public.supplier_dues (transaction_id, supplier_id, amount_due, admin_fee, interest_amount, status) values (ts_, vs, 300, 250, 0, 'open') returning id into ds;
  insert into public.supplier_due_checkouts (session_id, due_id, amount_aed)
    values ('cs_ZZDEMO_probe', ds, (public.fn_supplier_dues_outstanding(array[ds], null) -> ds::text ->> 'owed_aed')::numeric);
  update public.supplier_dues set status = 'paid', paid_at = now(), payment_ref = 'pi_ZZDEMO_probe', stripe_session_id = 'cs_ZZDEMO_probe' where id = ds and paid_at is null;
  update public.supplier_dues set status = 'paid', paid_at = now(), payment_ref = 'pi_ZZDEMO_probe', stripe_session_id = 'cs_ZZDEMO_probe' where id = ds and paid_at is null;
  st := public.fn_accountant_nonresponse_charge(ts_, null);
  out := out || jsonb_build_object('stripe', jsonb_build_object('rows', (select count(*) from public.supplier_due_payments where due_id = ds),
    'amount', (select sum(amount_aed) from public.supplier_due_payments where due_id = ds),
    'unpaid', st->'unpaid_principal_aed', 'total', st->'total_aed'));
  -- GAP 3: DAY ROLLOVER. An overdue due (interest accrues daily): checkout opened yesterday at yesterday's figure, paid today.
  insert into public.leads (company_name, email) values
    ('ZZ DEMO interest probe rollover (QuotesDone fixture, not a real company)', 'zz-demo-interest-rollover@example.invalid') returning id into vr;
  insert into public.transactions (supplier_id, revealed_at, total_charged, reveal_fee, refund_amount_aed, refund_status, refund_confirmed_at)
    values (vr, now() - interval '420 days', 300, 300, 300, 'refunded', now() - interval '410 days') returning id into tr;
  insert into public.supplier_dues (transaction_id, supplier_id, amount_due, admin_fee, status) values (tr, vr, 300, 250, 'open') returning id into dr;
  set local session_replication_role = replica;
  insert into public.agent_actions (agent, kind, status, target_id, decided_at, evidence, detail)
    values ('customer_support', 'handoff', 'done', 'delivery.request:nonresponse_charge:' || dr, now() - interval '400 days', '{"delivered": true}',
            '{"summary": {"known": "ZZ DEMO probe fixture", "tried": [], "needed": "nothing, aborted probe", "evidence": "ZZ DEMO"}}');
  set local session_replication_role = origin;
  r_prev := (public.fn_supplier_dues_outstanding(array[dr], d - 1) -> dr::text ->> 'owed_aed')::numeric;
  r_today := (public.fn_supplier_dues_outstanding(array[dr], d) -> dr::text ->> 'owed_aed')::numeric;
  insert into public.supplier_due_checkouts (session_id, due_id, amount_aed) values ('cs_ZZDEMO_rollover', dr, r_prev);
  update public.supplier_dues set status = 'paid', paid_at = now(), payment_ref = 'pi_ZZDEMO_rollover', stripe_session_id = 'cs_ZZDEMO_rollover' where id = dr;
  g := g || jsonb_build_object('roll', jsonb_build_object('yesterday', r_prev, 'today', r_today,
         'row', (select sum(amount_aed) from public.supplier_due_payments where due_id = dr), 'rows', (select count(*) from public.supplier_due_payments where due_id = dr)));
  -- a Stripe settlement with no stored amount records nothing and raises a finding (no recompute fallback)
  insert into public.supplier_dues (transaction_id, supplier_id, amount_due, admin_fee, status) values (null, vr, 300, 250, 'open') returning id into dn;
  update public.supplier_dues set status = 'paid', paid_at = now(), payment_ref = 'pi_ZZDEMO_nocheckout' where id = dn;
  g := g || jsonb_build_object('nockout_rows', (select count(*) from public.supplier_due_payments where due_id = dn),
         'nockout_finding', (select count(*) from public.it_engineer_finding where issue_key = 'acct:stripe_settlement_without_checkout_amount:' || dn));
  -- a due with no transaction, paid in full by bank, is settled (review of #1173: it stayed owed forever)
  insert into public.supplier_dues (transaction_id, supplier_id, amount_due, admin_fee, status) values (null, vr, 300, 250, 'open') returning id into dz;
  rv := public.fn_accountant_record_supplier_payment(dz, 550, d, 'ZZ-DEMO-BANK-FULL');
  g := g || jsonb_build_object('notx', jsonb_build_object('s', rv->'settled', 'p', (select paid_at is not null from public.supplier_dues where id = dz)));
  -- a stale checkout paid after a bank part payment: recorded as Stripe took it, and an overpayment finding
  insert into public.supplier_dues (transaction_id, supplier_id, amount_due, admin_fee, status) values (null, vr, 300, 250, 'open') returning id into dq;
  insert into public.supplier_due_checkouts (session_id, due_id, amount_aed) values ('cs_ZZDEMO_stale', dq, 550);
  perform public.fn_accountant_record_supplier_payment(dq, 100, d, 'ZZ-DEMO-BANK-PART');
  update public.supplier_dues set status = 'paid', paid_at = now(), payment_ref = 'pi_ZZDEMO_stale', stripe_session_id = 'cs_ZZDEMO_stale' where id = dq;
  g := g || jsonb_build_object('stale', jsonb_build_object('r', (select amount_aed from public.supplier_due_payments where due_id = dq and reference = 'pi_ZZDEMO_stale'),
         'f', (select count(*) from public.it_engineer_finding where issue_key = 'acct:stripe_overpayment:' || dq || ':pi_ZZDEMO_stale')));
  -- GAP 1: a reversed due refuses a bank payment
  insert into public.supplier_dues (transaction_id, supplier_id, amount_due, admin_fee, status) values (null, vr, 300, 250, 'reversed') returning id into dv;
  rv := public.fn_accountant_record_supplier_payment(dv, 10, d, 'ZZ-DEMO-BANK-REVERSED');
  g := g || jsonb_build_object('reversed_ok', rv->'ok', 'reversed_rows', (select count(*) from public.supplier_due_payments where due_id = dv));
  -- GAP 2: only the service role (and the owner) may execute the routine
  g := g || jsonb_build_object('exec', (select jsonb_build_object(
           'public', exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'),
           'anon', has_function_privilege('anon', p.oid, 'execute'), 'authenticated', has_function_privilege('authenticated', p.oid, 'execute'),
           'service_role', has_function_privilege('service_role', p.oid, 'execute'),
           'overloads', (select count(*) from pg_proc q where q.proname = 'fn_accountant_record_supplier_payment'))
         from pg_proc p where p.oid = 'public.fn_accountant_record_supplier_payment(bigint, numeric, date, text, text)'::regprocedure));
  out := out || jsonb_build_object(
    'v14', jsonb_build_array(public.fn_accountant_nonresponse_charge(t14, d + 372) - 'basis' - 'refund_source', public.fn_accountant_nonresponse_charge(t14, d + 402) - 'basis' - 'refund_source'),
    'v12', jsonb_build_array(public.fn_accountant_nonresponse_charge(t12, d + 372) - 'basis' - 'refund_source', public.fn_accountant_nonresponse_charge(t12, d + 402) - 'basis' - 'refund_source'),
    'none', jsonb_build_array(public.fn_accountant_nonresponse_charge(t0, d + 372) - 'basis' - 'refund_source', public.fn_accountant_nonresponse_charge(t0, d + 402) - 'basis' - 'refund_source'));
  pr := out->'part_rec'; sp := out->'stripe';
  -- only the figures the verdict reads, so the error text is never truncated before the closing marker
  select jsonb_object_agg(k, (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('ok', e->'ok', 'v', e->'signed_version', 'apr', e->'interest_apr',
           'days', e->'interest_days', 'int', e->'interest_aed', 'refunded', case when k = 'part' then e->'refunded_aed' end,
           'principal', (e->>'refunded_aed')::numeric + (e->>'processor_fee_aed')::numeric + (e->>'admin_fee_aed')::numeric, 'fee', case when k = 'part' then e->'admin_fee_aed' end,
           'reason', e->'reason', 'due', case when k = 'part' then e->'due_date' end, 'as_of', case when k = 'part' then e->'as_of' end,
           'paid', case when k = 'part' then e->'paid_aed' end, 'total', case when k = 'part' then e->'total_aed' end))) from jsonb_array_elements(v) e))
    into out from jsonb_each(out) as x(k, v) where jsonb_typeof(v) = 'array';
  out := out || jsonb_build_object('part_rec', pr, 'stripe', sp, 'gaps', g);
  raise exception 'CHK<<%>>', out::text;
end $$;`;

export async function runProbe(replay, replay2 = replay) {
  const { replaySql: sql } = await import('../lib/safe_replay.mjs');   // the one door: cannot commit
  try { await sql((replay ? read(FILE) + '\n' : '') + (replay2 ? read(FILE2) + '\n' : '') + PROBE, { retry: false }); } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw new Error('the probe failed before it could report: ' + String(e.message).slice(0, 800));
    return JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  throw new Error('the probe committed instead of rolling back');
}

export function verdict(o) {
  const bad = [];
  for (const [k, rate, ver] of [['v14', 0.12, 14], ['v12', 0.09, 12], ['none', 0.09, 0]]) {
    for (const c of o[k]) {
      if (c.ok !== true) { bad.push(`${k}: ${JSON.stringify(c)}`); continue; }
      if (c.v !== ver) bad.push(`${k}: read as v${c.v}`);
      if (Number(c.apr) !== rate) bad.push(`${k}: charged ${Number(c.apr) * 100}% instead of ${rate * 100}%`);
      const simple = Math.round(Number(c.principal) * rate * c.days / 365 * 100) / 100;
      if (Number(c.int) !== simple) bad.push(`${k}: interest ${c.int} over ${c.days} days is not ${simple} (simple at ${rate})`);
    }
    if (o[k][1].days - o[k][0].days !== 30) bad.push(`${k}: the two periods are not 30 days apart`);
  }
  // the part payer: the database's figure must equal the documents' (supplier_charge.ts computeCharge), to the fils
  const c = o.part[0];
  if (c.ok !== true) return [...bad, 'part: ' + JSON.stringify(c)];
  const ts = computeCharge({ refunded_reveal_fee: Number(c.refunded), refunded_processing_fee: 0, notice_date: addDays(c.due, -DUE_AFTER_NOTICE_DAYS),
    as_of: c.as_of, payments: [{ date: addDays(c.due, 100), amount: 275 }], admin_fee_aed: Number(c.fee), rate_pa: 0.09 });
  const r = o.part_rec, sp = o.stripe;
  if (r.ok !== true || r.dup_ok !== false || r.rows !== 1) bad.push('part: the routine recorded ' + JSON.stringify(r) + ' (want ok, the duplicate refused, 1 row)');
  if (r.paid_at_set !== false) bad.push('part: a half payment marked the due paid');
  // checkout: the exact remainder today, as the documents compute it
  const today = computeCharge({ refunded_reveal_fee: Number(c.refunded), refunded_processing_fee: 0, notice_date: addDays(c.due, -DUE_AFTER_NOTICE_DAYS),
    as_of: r.checkout.today, payments: [{ date: addDays(c.due, 100), amount: 275 }], admin_fee_aed: Number(c.fee), rate_pa: 0.09 });
  if (Number(r.checkout.owed) !== today.total_due) bad.push(`checkout: bills ${r.checkout.owed}, the documents say ${today.total_due} is still owed`);
  if (Number(r.checkout.total_claim) !== today.total_due) bad.push(`portal: total_claim ${r.checkout.total_claim} is not the ${today.total_due} still owed`);
  if (Number(r.settle.rest_row) !== today.total_due || r.settle.rows !== 2) bad.push('settle: ' + JSON.stringify(r.settle) + `, want one more row of ${today.total_due}`);
  if (Number(r.settle.after) !== 0) bad.push('settle: the charge still shows ' + r.settle.after + ' outstanding');
  if (sp.rows !== 1 || Number(sp.amount) !== 550) bad.push('stripe: the settled due has ' + sp.rows + ' payment row(s) of ' + sp.amount + ', want 1 of 550');
  if (Number(sp.unpaid) !== 0 || Number(sp.total) !== 0) bad.push('stripe: the charge still shows ' + sp.unpaid + ' principal / ' + sp.total + ' outstanding');
  const g = o.gaps;
  if (g.over_ok !== false || g.over_rows !== 0 || g.over_finding !== 1) bad.push('gap 1: an overpayment was not refused with a finding ' + JSON.stringify(g));
  if (!(Number(g.principal_min) >= 0)) bad.push('gap 1: the principal went negative (' + g.principal_min + ')');
  if (g.paid_due_ok !== false || g.reversed_ok !== false || g.reversed_rows !== 0) bad.push('gap 1: a paid or reversed due accepted a payment ' + JSON.stringify(g));
  if (g.bad_entered_by_ok !== false) bad.push('gap 2: entered_by outside accountant/service was accepted');
  if (!g.acct_row || g.acct_row.by !== 'accountant' || g.acct_row.at !== true || g.svc_row_by !== 'service') bad.push('gap 2: who/when not recorded ' + JSON.stringify(g));
  const x = g.exec;
  if (x.public || x.anon || x.authenticated || !x.service_role || x.overloads !== 1) bad.push('gap 2: execute grants ' + JSON.stringify(x));
  const rl = g.roll;
  if (Number(rl.yesterday) === Number(rl.today)) bad.push('gap 3: the rollover case does not change the figure across the day ' + JSON.stringify(rl));
  if (rl.rows !== 1 || Number(rl.row) !== Number(rl.yesterday)) bad.push('gap 3: the settlement row is not what the checkout charged ' + JSON.stringify(rl));
  if (g.nockout_rows !== 0 || g.nockout_finding !== 1) bad.push('gap 3: a Stripe settlement with no stored amount was recomputed ' + JSON.stringify(g));
  if (g.notx.s !== true || g.notx.p !== true) bad.push('a no-transaction due paid in full by bank is not settled ' + JSON.stringify(g.notx));
  if (Number(g.stale.r) !== 550 || g.stale.f !== 1) bad.push('a stale checkout overpayment was not recorded as charged with a finding ' + JSON.stringify(g.stale));
  if (Number(c.paid) !== 275) bad.push(`part: the payment of 275 is not read (paid ${c.paid})`);
  if (Number(c.int) !== ts.interest) bad.push(`part: interest ${c.int} is not the documents' ${ts.interest}`);
  if (Number(c.total) !== ts.total_due) bad.push(`part: total ${c.total} is not the documents' ${ts.total_due}`);
  return bad;
}

// PROBE_IMPORTED: a caller importing runProbe/verdict runs the probe itself; two copies at once deadlock on pricing_config.
const hasToken = !process.env.PROBE_IMPORTED && (!!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token')));

test('production, aborted: agreed rate or 9%, simple across two periods, policy rows at 50%', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const o = await runProbe(pending(FILE), pending(FILE2));
  assert.deepEqual(verdict(o), [], JSON.stringify(o));
});
