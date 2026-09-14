// COMPLAINT TICKETS: THE CONTRACT BETWEEN THE SQL, THE TWO EDGE FUNCTIONS AND THE STATUS PAGE.
//
// Agent: customer_support. The website audit of 14 Sep 2026 required a ticket number and a public
// status page for every complaint, with the 2- and 10-working-day timers visible and the DET /
// 800 1222 escalation printed on the final response. This check reads the repository (no network)
// and fails if any one of the four pieces drifts from the others.
//
//   node --test scripts/checks/complaint_ticket_contract.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const R = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const sql = R('scripts/sql/complaints_get_a_ticket_number_and_a_status_the_customer_can_watch.sql');
const cfg = R('supabase/config.toml');
const submit = R('supabase/functions/contact_submit/index.ts');
const status = R('supabase/functions/complaint_status/index.ts');
const page = R('src/components/ComplaintStatus.tsx');

test('complaint_tickets is RLS on, has a policy and is closed to public/anon/authenticated', () => {
  assert.match(sql, /alter table public\.complaint_tickets enable row level security;/);
  assert.match(sql, /create policy complaint_tickets_service_role_only on public\.complaint_tickets/);
  assert.match(sql, /revoke all on public\.complaint_tickets from public, anon, authenticated;/);
});

test('every fn_complaint_* signature is revoked and search_path is pinned', () => {
  const sigs = {
    fn_complaint_open: 'text, text, text, bigint',
    fn_complaint_lookup: 'text, text',
    fn_complaint_set_status: 'text, text, text',
  };
  const creates = [...sql.matchAll(/create or replace function public\.(fn_complaint_\w+)\(/g)].map((m) => m[1]);
  assert.deepEqual(creates.sort(), Object.keys(sigs).sort());
  for (const [fn, sig] of Object.entries(sigs)) {
    const re = new RegExp(`revoke execute on function public\\.${fn}\\(${sig}\\) from public, anon, authenticated;`);
    assert.match(sql, re, fn + ' revoke missing');
  }
  const pinned = sql.match(/security definer\s*\nset search_path to 'public', 'pg_temp'/g) || [];
  assert.equal(pinned.length, 3);
  assert.match(sql, /^begin;$/m);
  assert.match(sql, /^commit;$/m);
});

test('complaint_status is deployed with verify_jwt = false', () => {
  assert.match(cfg, /\[functions\.complaint_status\]\s*\nverify_jwt = false/);
  assert.match(status, /rpc\('fn_complaint_lookup'/);
  assert.match(status, /rl_check/);
});

test('contact_submit opens a ticket for kind complaint', () => {
  assert.match(submit, /b\.kind \|\| ''\) === 'complaint'/);
  assert.match(submit, /rpc\('fn_complaint_open'/);
  assert.match(submit, /status_path: '\/complaints\/status'/);
  assert.doesNotMatch(submit, /founder/i);
});

test('the status page carries the escalation and both Arabic status labels', () => {
  for (const s of ['800 1222', 'tel:8001222', 'consumerrights.ae', 'تم الاستلام', 'قيد المراجعة', 'الرد النهائي']) {
    assert.ok(page.includes(s), 'missing: ' + s);
  }
});
