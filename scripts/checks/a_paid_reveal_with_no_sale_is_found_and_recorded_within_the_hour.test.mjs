// A PAID REVEAL WITH NO SALE IS FOUND AND RECORDED WITHIN THE HOUR (accountant, 3 Nov 2026).
//
//   node --test scripts/checks/a_paid_reveal_with_no_sale_is_found_and_recorded_within_the_hour.test.mjs
//
// If element_pay, element_settle and stripe_webhook invoice.paid all fail to record a reveal (the webhook answers 500
// since #1835 and Stripe stops retrying after about three days), the customer has paid and transactions holds nothing.
// scripts/sql/a_paid_reveal_with_no_sale_is_found_and_recorded_within_the_hour.sql registers the hourly accountant duty;
// the sweep is supabase/functions/_shared/reveal_reconcile.ts (its Deno test proves the behaviour) behind the accountant
// runtime's action 'reveal_reconcile'; the probe proves the duty and the findings on production, rolled back.
// This reads only the repository. It fails if the duty, its owner or clock, the one recording path, the demo exclusion,
// the bounds, the grants, the table registrations or the probe is lost.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const F = 'scripts/sql/a_paid_reveal_with_no_sale_is_found_and_recorded_within_the_hour.sql';
const PROBE = F.replace(/\.sql$/, '_probe.sql');
const code = read(F).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const SWEEP = read('supabase/functions/_shared/reveal_reconcile.ts');
// the whole accountant function: index.ts plus the modules it was split into on 9 Nov 2026 (reveal_reconcile and
// bank_statement are both in actions/reconcile.ts, in that order, so the slice below stays inside the one handler)
const ACC = functionSource('accountant');

const body = (fn) => {
  const at = code.indexOf(`create or replace function public.${fn}(`);
  assert.ok(at >= 0, fn + ' is not defined');
  const from = code.indexOf('$fn$', at);
  return code.slice(from + 4, code.indexOf('$fn$', from + 4));
};

test('the duty is the accountant\'s, every hour, its routine defined here, and the file is the last MANIFEST line it is on', () => {
  assert.match(code, /\('accountant\.reveal_reconcile', 'accountant', interval '1 hour', 'fn_accountant_reveal_reconcile_tick',/);
  assert.match(code, /'scripts\/sql\/a_paid_reveal_with_no_sale_is_found_and_recorded_within_the_hour\.sql'\)\s+on conflict \(duty\)/);
  const manifest = read('scripts/sql/MANIFEST.txt').split('\n');
  assert.ok(manifest.includes(F), 'not in MANIFEST.txt');
  assert.ok(!manifest.includes(PROBE), 'a probe is never a MANIFEST line');
  assert.ok(existsSync(join(ROOT, 'scripts/sql/pending/' + PROBE.split('/').pop().replace(/\.sql$/, '.txt'))), 'the probe has no pending note');
});

test('the tick dispatches to the accountant runtime under the seat\'s own credential, one at a time, and fails when it cannot', () => {
  const t = body('fn_accountant_reveal_reconcile_tick');
  assert.match(t, /functions\/v1\/accountant/);
  assert.match(t, /'__secret', v_cred, 'action', 'reveal_reconcile', 'run_id', v_run, 'days', v_days/);
  assert.match(t, /key = 'cred_fn_accountant'/);
  assert.match(t, /public\.fn_gateway_client_key\(\)/);
  assert.match(t, /requested_at > now\(\) - interval '30 minutes'/, 'a second sweep may be sent while one is in flight');
  assert.match(t, /raise exception 'fn_accountant_reveal_reconcile_tick: project_ref/, 'a tick that cannot send must fail, not report green');
  assert.match(t, /greatest\(1, least\(90,/, 'the window is not bounded');
});

test('the runtime records through recordRevealSale only, with a bounded sweep, and reports to the record routine', () => {
  const a = ACC.slice(ACC.indexOf("if (action === 'reveal_reconcile')"), ACC.indexOf("if (action === 'bank_statement')"));
  assert.ok(a.length > 100, 'the accountant runtime has no reveal_reconcile action');
  assert.match(a, /record: \(a\) => recordRevealSale\(admin, a\)/);
  assert.doesNotMatch(a, /from\('transactions'\)\.(insert|upsert)/, 'the sweep writes a sale itself instead of through recordRevealSale');
  // The updates it may make are the write-once fee and, since 13 Nov 2026 (accountant, ledger 1685), the write-once charge
  // facts the accountant reconciles and the refund clock starts from (_shared/charge_facts.ts: amount received, balance
  // transaction, paid_at). stripe_webhook's recordStripeFee does the same two.
  const updates = [...a.matchAll(/from\('transactions'\)\.update\(([^)]*)\)/g)].map((m) => m[1]);
  assert.deepEqual(updates, ['{ stripe_fee_fils: feeFils, stripe_fee_details: details }', 'facts']);
  assert.match(a, /\.eq\('id', txId\)\.is\('stripe_fee_fils', null\)/, 'the fee is not write-once');
  assert.match(a, /update\(facts\)\.eq\('id', txId\)\.is\('paid_at', null\)/, 'the charge facts are not write-once');
  assert.match(a, /facts: chargeFacts\(j, bt\)/, 'the charge facts are not the pure chargeFacts reading of the PaymentIntent');
  assert.match(a, /maxPages: 5, maxRecords: 25, maxAttempts: 50, graceSeconds: 900/);
  assert.match(a, /xs\.slice\(i \* 100, i \* 100 \+ 100\)/, 'the transactions lookup is not chunked');
  assert.match(a, /rpc\('fn_accountant_reveal_reconcile_record'/);
  assert.match(a, /throw new Error\('transactions could not be read: '/, 'an unread book must stop the sweep, not read as empty');
  assert.match(ACC, /import \{ recordRevealSale \} from '(\.\.\/)+_shared\/reveal_sale\.ts';/);   // actions/ is one level deeper
});

test('the sweep never records an invoice id as the payment reference, and lists by created[gte] with paging', () => {
  assert.match(SWEEP, /if \(!isPi\(pi\)\) \{ done\(c, 'failed'/);
  assert.match(SWEEP, /if \(before\) \{[\s\S]{0,400}done\(cc, 'second_payment', before\.id\);\s+continue;/, 'a sold quote is handed to recordRevealSale');
  assert.match(SWEEP, /paymentRef: pi, invoiceId: c\.invoiceId \|\| ''/);
  assert.match(SWEEP, /invoices\?status=paid&limit=100&created\[gte\]=\$\{since\}&expand\[\]=data\.payments/);
  assert.match(SWEEP, /starting_after=/);
  assert.match(SWEEP, /if \(page >= maxPages\) \{ truncated = true; break; \}/);
});

test('demo payments file no finding: test mode, fn_is_demo_email, or an is_demo customer', () => {
  const r = body('fn_accountant_reveal_reconcile_record');
  assert.match(r, /v_demo := case when x->>'outcome' = 'test_mode_not_demo' then public\.fn_is_demo_email\(x->>'customer_email'\)\s+else \(not coalesce\(\(x->>'livemode'\)::boolean, false\)\s+or public\.fn_is_demo_email\(x->>'customer_email'\)/,
    'a test-mode payment on a quote that is not a demo account\'s must reach the findings unless its own Stripe e-mail is a demo address');
  assert.match(r, /c\.is_demo/);
  const f = body('fn_accountant_reveal_reconcile_findings');
  assert.match(f, /where i\.resolved_at is null and not i\.demo/);
  assert.match(f, /i\.outcome in \('failed', 'refunded_unrecorded', 'second_payment', 'test_mode_not_demo'\)/);
  assert.match(f, /fn_accountant_duty_settle\('reveal_reconcile', v_items\)/);
  assert.match(f, /'reveal:second_payment:' \|\| i\.payment_intent/, 'a second payment recordRevealSale raised (#1835) would be filed twice');
});

test('every routine is SECURITY DEFINER with a pinned search_path and EXECUTE revoked; the tables are service_role only and registered', () => {
  const made = [...code.matchAll(/create or replace function public\.(\w+)\(([^)]*)\)\s*returns[^$]*?security definer set search_path to 'public', 'pg_temp'/g)].map((m) => m[1]);
  assert.deepEqual(made.sort(), ['fn_accountant_reveal_reconcile_findings', 'fn_accountant_reveal_reconcile_record', 'fn_accountant_reveal_reconcile_tick']);
  for (const sig of ['fn_accountant_reveal_reconcile_findings()', 'fn_accountant_reveal_reconcile_record(bigint, jsonb)', 'fn_accountant_reveal_reconcile_tick()']) {
    assert.ok(code.includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), 'no revoke for ' + sig);
  }
  for (const t of ['accountant_reveal_reconcile_item', 'accountant_reveal_reconcile_run']) {
    assert.ok(code.includes(`alter table public.${t} enable row level security;`), t + ' has no RLS');
    assert.match(code, new RegExp(`create policy ${t}_service_role_only on public\\.${t}\\s+as permissive for all to public using \\(false\\) with check \\(false\\);`));
    assert.ok(code.includes(`revoke all on public.${t} from anon, authenticated;`), t + ' is not revoked');
    assert.match(code, new RegExp(`\\('${t}', (true|false), '`), t + ' is not in table_export_registry');
  }
});

test('the probe drives the real runner and proves each rule, rolled back', () => {
  const p = read(PROBE);
  for (const s of ["fn_seat_duty_run('accountant.reveal_reconcile')", "'1:second_dispatch_in_flight; '", "'2:silent_not_filed; '",
    "'3:failed_not_filed; '", "'3:second_payment_not_filed_for_ceo; '", "'3:demo_or_recovered_filed; '", "'4:findings_changed; '",
    "'3:deferred_overwrote_failed; '", "'3:test_mode_not_demo_not_filed; '", "'3:torn_down_demo_filed; '", "set last_started_at = null where duty = 'accountant.reveal_reconcile'", "'5:refund_finding_open; '", "'5:second_payment_filed_twice; '", "'5:live_unread_not_filed; '", "'6:reached_the_founder; '",
    "raise exception 'CHK<<%>>'"]) {
    assert.ok(p.includes(s), 'probe lacks ' + s);
  }
});
