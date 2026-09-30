// NO SUPPLIER IS CHARGED INTEREST ABOVE 9% A YEAR (30 Sep 2026, accountant; founder ruling: 9% a year, simple,
// the maximum lawful).
//
// MEASURED BEFORE THE FIX: fn_accountant_nonresponse_charge capped the rate at decision_policy.supplier_charge_max_lawful_apr
// (0.09) and then, for a supplier who had signed Supplier Agreement v14 before the reveal, overwrote it with
// decision_policy.supplier_nonresponse_interest_apr_from_v14 (0.12). A v14 signer was charged 12%.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: supplier_charge.ts (the documents' arithmetic) stops capping termsAt() or computeCharge() at 9%; the SQL
//     file loses its cap; the file carries both (or neither of) a pending note and a MANIFEST line;
//   * production, in ONE aborted transaction (the file replayed first while it is pending, nothing commits): a ZZ DEMO
//     supplier (@example.invalid) who signed v14 before the reveal, with a settled AED 300 refund, and BOTH policy rows
//     raised to 50%: the charge's interest_apr is 0.09 and its interest is 9% simple on the total; fn_refund_amount_aed
//     states 9.
//
//   node --test scripts/checks/no_supplier_is_charged_interest_above_nine_percent.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/no_supplier_is_charged_interest_above_nine_percent_a_year.sql';
const pending = () => existsSync(join(REPO, 'scripts/sql/pending', FILE.split('/').pop().replace(/\.sql$/, '.txt')));

test('static: the SQL and the documents both cap at 9%, and the file is pending XOR applied', () => {
  const sqlCode = read(FILE).split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
  // the cap must come AFTER the v14 branch, i.e. after the last other assignment to v_apr
  const cap = sqlCode.indexOf('v_apr := least(v_apr, coalesce(v_cap, 0.09), 0.09);');
  assert.ok(cap > 0, 'fn_accountant_nonresponse_charge has no 9% cap');
  assert.ok(cap > sqlCode.lastIndexOf('v_apr       := coalesce('), 'the cap sits before the v14 rate, so the v14 rate wins again');
  assert.match(sqlCode, /v_pct\s+:= least\(coalesce\([\s\S]{0,200}refund_late_fee_annual_pct'\), 9\), 9\);/, 'fn_refund_amount_aed has no 9% cap');
  const ts = read('supabase/functions/_shared/supplier_charge.ts');
  assert.match(ts, /export const MAX_LAWFUL_RATE_PA = 0\.09;/);
  assert.match(ts, /rate_pa: Math\.min\([^\n]*MAX_LAWFUL_RATE_PA\)/, 'termsAt() is not capped');
  assert.match(ts, /const rate = Math\.min\(asked, MAX_LAWFUL_RATE_PA\);/, 'computeCharge() is not capped');
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim());
  assert.ok(pending() !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: a v14 signer with both policy rows at 50% is charged 9%', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const replay = pending() ? read(FILE) + '\n' : '';
  let o;
  try {
    await sql(replay + `
do $$
declare v_lead bigint; v_tx uuid; r jsonb; ref jsonb;
begin
  update public.decision_policy set value = to_jsonb(0.5) where key = 'supplier_nonresponse_interest_apr_from_v14';
  update public.decision_policy set value = to_jsonb(50) where key = 'refund_late_fee_annual_pct';
  insert into public.leads (company_name, email, accepted_terms_version, accepted_terms_at)
  values ('ZZ DEMO interest ceiling probe (QuotesDone fixture, not a real company)', 'zz-demo-interest-probe@example.invalid', 'v14', now() - interval '30 days') returning id into v_lead;
  insert into public.transactions (supplier_id, revealed_at, total_charged, reveal_fee, refund_amount_aed, refund_status, refund_confirmed_at)
  values (v_lead, now() - interval '20 days', 300, 300, 300, 'refunded', now() - interval '10 days')
  returning id into v_tx;
  r := public.fn_accountant_nonresponse_charge(v_tx, ((now() at time zone 'Asia/Dubai')::date + 372));
  ref := public.fn_refund_amount_aed(300, now() - interval '365 days', now());
  raise exception 'CHK<<%>>', jsonb_build_object('charge', (r - 'basis' - 'refund_source' - 'due_basis' - 'admin_fee_basis' - 'interest_apr_basis'), 'ref', jsonb_build_object('interest_pct_pa', ref->'interest_pct_pa'))::text;
end $$;`, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  const c = o.charge;
  assert.equal(c.ok, true, JSON.stringify(c));
  assert.equal(c.signed_version, 14, 'the fixture is not read as a v14 signer: ' + JSON.stringify(c));
  assert.equal(Number(c.interest_apr), 0.09, 'a v14 signer is charged above 9%: ' + JSON.stringify(c));
  assert.ok(c.interest_days > 300, 'no interest period: ' + JSON.stringify(c));
  const principal = Number(c.refunded_aed) + Number(c.processor_fee_aed) + Number(c.admin_fee_aed);
  assert.equal(Number(c.interest_aed), Math.round(principal * 0.09 * c.interest_days / 365 * 100) / 100, 'not 9% simple on the total');
  assert.equal(Number(o.ref.interest_pct_pa), 9, 'fn_refund_amount_aed states above 9%: ' + JSON.stringify(o.ref));
});
