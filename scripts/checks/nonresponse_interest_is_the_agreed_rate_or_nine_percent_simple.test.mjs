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
  assert.match(s2, /revoke execute on function public\.fn_accountant_record_supplier_payment\(bigint, numeric, date, text\) from public, anon, authenticated;/, 'the routine is not revoked');
  assert.match(s2, /unique \(due_id, reference\)/, 'a reference can be recorded twice');
});

export const PROBE = `
do $$
declare v14 bigint; v12 bigint; v0 bigint; vp bigint; dp bigint; t14 uuid; t12 uuid; t0 uuid; tp uuid; pre jsonb; rec jsonb; rec2 jsonb; vs bigint; ds bigint; ts_ uuid; st jsonb; pr jsonb; sp jsonb; d date := (now() at time zone 'Asia/Dubai')::date; out jsonb := '{}';
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
  out := jsonb_build_object('part', jsonb_build_array(public.fn_accountant_nonresponse_charge(tp, (pre->>'due_date')::date + 365)),
    'part_rec', jsonb_build_object('ok', rec->'ok', 'dup_ok', rec2->'ok', 'rows', (select count(*) from public.supplier_due_payments where due_id = dp),
      'paid_at_set', (select paid_at is not null from public.supplier_dues where id = dp)));
  -- the rest then settles through Stripe: only the unrecorded remainder (550 - 275) becomes a row, never the whole 550
  update public.supplier_dues set status = 'paid', paid_at = now(), payment_ref = 'pi_ZZDEMO_rest' where id = dp and paid_at is null;
  out := jsonb_set(out, '{part_rec,sum_after_settle}', to_jsonb((select sum(amount_aed) from public.supplier_due_payments where due_id = dp)));
  -- STRIPE FULL PAYMENT: the webhook's own write (status paid, paid_at, payment_ref), delivered twice
  insert into public.leads (company_name, email) values
    ('ZZ DEMO interest probe stripe payer (QuotesDone fixture, not a real company)', 'zz-demo-interest-stripe@example.invalid') returning id into vs;
  insert into public.transactions (supplier_id, revealed_at, total_charged, reveal_fee, refund_amount_aed, refund_status, refund_confirmed_at)
    values (vs, now() - interval '20 days', 300, 300, 300, 'refunded', now() - interval '10 days') returning id into ts_;
  insert into public.supplier_dues (transaction_id, supplier_id, amount_due, admin_fee, interest_amount, status) values (ts_, vs, 300, 250, 0, 'open') returning id into ds;
  update public.supplier_dues set status = 'paid', paid_at = now(), payment_ref = 'pi_ZZDEMO_probe' where id = ds and paid_at is null;
  update public.supplier_dues set status = 'paid', paid_at = now(), payment_ref = 'pi_ZZDEMO_probe' where id = ds and paid_at is null;
  st := public.fn_accountant_nonresponse_charge(ts_, null);
  out := out || jsonb_build_object('stripe', jsonb_build_object('rows', (select count(*) from public.supplier_due_payments where due_id = ds),
    'amount', (select sum(amount_aed) from public.supplier_due_payments where due_id = ds),
    'unpaid', st->'unpaid_principal_aed', 'total', st->'total_aed'));
  out := out || jsonb_build_object(
    'v14', jsonb_build_array(public.fn_accountant_nonresponse_charge(t14, d + 372) - 'basis' - 'refund_source', public.fn_accountant_nonresponse_charge(t14, d + 402) - 'basis' - 'refund_source'),
    'v12', jsonb_build_array(public.fn_accountant_nonresponse_charge(t12, d + 372) - 'basis' - 'refund_source', public.fn_accountant_nonresponse_charge(t12, d + 402) - 'basis' - 'refund_source'),
    'none', jsonb_build_array(public.fn_accountant_nonresponse_charge(t0, d + 372) - 'basis' - 'refund_source', public.fn_accountant_nonresponse_charge(t0, d + 402) - 'basis' - 'refund_source'));
  pr := out->'part_rec'; sp := out->'stripe';
  -- only the figures the verdict reads, so the error text is never truncated before the closing marker
  select jsonb_object_agg(k, (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('ok', e->'ok', 'v', e->'signed_version', 'apr', e->'interest_apr',
           'days', e->'interest_days', 'int', e->'interest_aed', 'refunded', e->'refunded_aed',
           'principal', (e->>'refunded_aed')::numeric + (e->>'processor_fee_aed')::numeric + (e->>'admin_fee_aed')::numeric, 'fee', e->'admin_fee_aed',
           'reason', e->'reason', 'due', case when k = 'part' then e->'due_date' end, 'as_of', case when k = 'part' then e->'as_of' end,
           'paid', e->'paid_aed', 'total', case when k = 'part' then e->'total_aed' end))) from jsonb_array_elements(v) e))
    into out from jsonb_each(out) as x(k, v) where jsonb_typeof(v) = 'array';
  out := out || jsonb_build_object('part_rec', pr, 'stripe', sp);
  raise exception 'CHK<<%>>', out::text;
end $$;`;

export async function runProbe(replay, replay2 = replay) {
  const { sql } = await import('../lib/db.mjs');
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
  if (Number(r.sum_after_settle) !== 550) bad.push('part: after a Stripe settlement of the rest the due records ' + r.sum_after_settle + ', want 550 (no double count)');
  if (sp.rows !== 1 || Number(sp.amount) !== 550) bad.push('stripe: the settled due has ' + sp.rows + ' payment row(s) of ' + sp.amount + ', want 1 of 550');
  if (Number(sp.unpaid) !== 0 || Number(sp.total) !== 0) bad.push('stripe: the charge still shows ' + sp.unpaid + ' principal / ' + sp.total + ' outstanding');
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
