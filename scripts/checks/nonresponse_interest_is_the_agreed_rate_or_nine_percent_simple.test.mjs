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
//       two billing periods 30 days apart: interest = principal x rate x days / 365 in both, never interest on interest.
//
//   node --test scripts/checks/nonresponse_interest_is_the_agreed_rate_or_nine_percent_simple.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/nonresponse_interest_is_the_agreed_rate_or_nine_percent.sql';
const pending = () => existsSync(join(REPO, 'scripts/sql/pending', FILE.split('/').pop().replace(/\.sql$/, '.txt')));
const code = (s) => s.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');

test('static: every branch carries its literal, the documents name only signed rates, accrual never compounds', () => {
  const sql = code(read(FILE));
  assert.match(sql, /v_apr\s+:= least\(coalesce\(c\.supplier_nonresponse_interest_apr, 0\.09\), coalesce\(v_cap, 0\.09\), 0\.09\);/, 'the no-agreed-rate branch has no literal 9% ceiling');
  assert.match(sql, /'supplier_nonresponse_interest_apr_from_v14'\), 0\.12\), 0\.12\);/, 'the v14 branch has no 12% ceiling');
  assert.match(sql, /v_int\s+:= round\(\(v_base \+ v_proc \+ v_fee\) \* v_apr \* v_days \/ 365\.0, 2\);/, 'interest is not simple on the principal');
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
  assert.ok(pending() !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

export const PROBE = `
do $$
declare v14 bigint; v12 bigint; v0 bigint; t14 uuid; t12 uuid; t0 uuid; d date := (now() at time zone 'Asia/Dubai')::date; out jsonb := '{}';
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
  out := jsonb_build_object(
    'v14', jsonb_build_array(public.fn_accountant_nonresponse_charge(t14, d + 372) - 'basis' - 'refund_source', public.fn_accountant_nonresponse_charge(t14, d + 402) - 'basis' - 'refund_source'),
    'v12', jsonb_build_array(public.fn_accountant_nonresponse_charge(t12, d + 372) - 'basis' - 'refund_source', public.fn_accountant_nonresponse_charge(t12, d + 402) - 'basis' - 'refund_source'),
    'none', jsonb_build_array(public.fn_accountant_nonresponse_charge(t0, d + 372) - 'basis' - 'refund_source', public.fn_accountant_nonresponse_charge(t0, d + 402) - 'basis' - 'refund_source'));
  -- only the figures the verdict reads, so the error text is never truncated before the closing marker
  select jsonb_object_agg(k, (select jsonb_agg(jsonb_build_object('ok', e->'ok', 'signed_version', e->'signed_version', 'interest_apr', e->'interest_apr',
           'interest_days', e->'interest_days', 'interest_aed', e->'interest_aed', 'refunded_aed', e->'refunded_aed',
           'processor_fee_aed', e->'processor_fee_aed', 'admin_fee_aed', e->'admin_fee_aed', 'reason', e->'reason')) from jsonb_array_elements(v) e))
    into out from jsonb_each(out) as x(k, v);
  raise exception 'CHK<<%>>', out::text;
end $$;`;

export async function runProbe(replay) {
  const { sql } = await import('../lib/db.mjs');
  try { await sql((replay ? read(FILE) + '\n' : '') + PROBE, { retry: false }); } catch (e) {
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
      if (c.signed_version !== ver) bad.push(`${k}: read as v${c.signed_version}`);
      if (Number(c.interest_apr) !== rate) bad.push(`${k}: charged ${Number(c.interest_apr) * 100}% instead of ${rate * 100}%`);
      const p = Number(c.refunded_aed) + Number(c.processor_fee_aed) + Number(c.admin_fee_aed);
      const simple = Math.round(p * rate * c.interest_days / 365 * 100) / 100;
      if (Number(c.interest_aed) !== simple) bad.push(`${k}: interest ${c.interest_aed} over ${c.interest_days} days is not ${simple} (simple at ${rate})`);
    }
    if (o[k][1].interest_days - o[k][0].interest_days !== 30) bad.push(`${k}: the two periods are not 30 days apart`);
  }
  return bad;
}

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: agreed rate or 9%, simple across two periods, policy rows at 50%', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const o = await runProbe(pending());
  assert.deepEqual(verdict(o), [], JSON.stringify(o));
});
