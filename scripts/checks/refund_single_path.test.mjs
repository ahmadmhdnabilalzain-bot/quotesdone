// There must be exactly one path from "refund" to "money moved", and one writer of refunds rows.
//
// Audit 5.3 / 5.5 class. secretary_act's issue_refund tool wrote
//   transactions.refund_status = 'refunded', refund_resolved_at = now()
// directly. It never called refunds_api, never reached Stripe, and never wrote a refunds row - so the
// books said refunded while Stripe said paid, and it bypassed the Control Mode gate that refunds_api
// carries precisely because `resolve` moves real money. The founder chat confirmation in
// secretary_act is a control over INTENT; it is not a substitute for the code path that reconciles.
//
// Founder decision, 4 Aug 2026: inside transactions.refund_deadline and at or below
// org_authority.threshold_aed (AED 2,000) a refund auto-approves; above it, both the approval and
// the payment wait for a human. That policy lives in fn_refund_request, so every requester must go
// through it rather than setting a status itself.
// SECRETARY_ACT WAS DELETED ON 8 SEP 2026 and the two tests that read it went with it. They
// asserted about the shape of tool_issue_refund: that it called fn_refund_request rather than
// stamping refund_status itself, and that it pinned p_reason_code to the closed vocabulary. There
// is no such tool any more — the CEO agent requests a refund through fn_ceo_request_decision and
// the money moves through fn_refund_execute_authorized, which takes no destination and no decision
// parameter at all, so the class of defect those two tests guarded cannot be expressed in the new
// path. §15 of the support acceptance harness covers what replaced them.
//
// The other two tests are untouched and still have live subjects: the scan below is over EVERY
// function in the directory, not over one that was deleted, and refunds_api still exists and still
// carries the Control Mode gate. Deleting the whole file would have taken those down with the dead
// ones — the rule is that a check retires with ITS OWN subject, not with a neighbour's.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { functionSource } from '../lib/function_sources.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FNDIR = join(root, 'supabase', 'functions');
// The whole function, index.ts first: a function split into modules (accountant, 9 Nov 2026) keeps its Stripe call
// in them, and a second refund rail in a module is still a second rail. Throws, like the read it replaced, when a
// directory has no index.ts.
const read = (slug) => functionSource(slug);

test('no edge function sets a terminal refund state on transactions by hand', () => {
  // The class, not the instance. Any function that writes a settled refund state straight onto
  // transactions has invented a second refund path with its own controls.
  const offenders = [];
  for (const d of readdirSync(FNDIR, { withFileTypes: true })) {
    if (!d.isDirectory() || d.name === '_shared') continue;
    let src;
    try { src = read(d.name); } catch { continue; }
    // stripe_webhook is the one legitimate writer: it records what Stripe already did. refunds_api
    // lost its exemption on 14 Sep 2026 when its 'resolve' rail was retired (see the last test).
    if (d.name === 'stripe_webhook') continue;
    if (/refund_status:\s*'(refunded|succeeded)'/.test(src)) offenders.push(d.name);
  }
  assert.deepEqual(offenders, [],
    'these functions write a settled refund state directly onto transactions, bypassing fn_refund_request and ' +
    'the Control Mode gate: ' + offenders.join(', '));
});

// 14 SEP 2026 — ONE REFUND RAIL. This test asserted that refunds_api gated its Stripe call on Control
// Mode. PR #640's review found that call was a SECOND rail (straight off transactions, its own
// idempotency key), so one reveal could be refunded twice; the call was removed rather than gated. The
// stronger property is asserted now: only the accountant's execute path reaches Stripe's refund API,
// through the one shared door, keyed once per transaction. A second rail fails here, gated or not.
test('only the accountant reaches Stripe refunds, through the one door, keyed once per transaction', () => {
  const callers = [];
  for (const d of readdirSync(FNDIR, { withFileTypes: true })) {
    if (!d.isDirectory() || d.name === '_shared') continue;
    let src;
    try { src = read(d.name); } catch { continue; }
    if (/\bstripeRefund\s*\(/.test(src) || /api\.stripe\.com\/v1\/refunds['"`]\s*,\s*\{\s*method:\s*'POST'/.test(src)) callers.push(d.name);
  }
  assert.deepEqual(callers, ['accountant'], 'Stripe refunds must have exactly one caller, the accountant; found: ' + callers.join(', '));
  const acc = read('accountant');
  // An overcharge return (15 Nov 2026) is its own request, still rooted in the transaction: over<refund row>. The fee
  // case keeps the bare transaction key.
  assert.match(acc, /idem:\s*over \? refundIdempotencyKey\(String\(r\.transaction_id\), 'over' \+ r\.id\) : refundIdempotencyKey\(String\(r\.transaction_id\)\)/,
    'execute_refunds must key a case refund on its transaction (refundIdempotencyKey), never on the refunds row id, and an overcharge return on its transaction and over<row>');
  assert.doesNotMatch(read('refunds_api'), /from '\.\.\/_shared\/stripe_refund\.ts'/, 'refunds_api must not import the Stripe refund door');
  // The playbook's top-up and retry are keyed on the transaction too, and reserved on public.refunds
  // before Stripe (re-review of #640): no key may be minted from an incident handoff id.
  assert.doesNotMatch(acc, /idem:\s*'qd_incident_/, 'an incident fix must not mint its own Stripe key; use refundIdempotencyKey(transaction, topup<n>|retry<n>)');
  assert.match(acc, /fn_accountant_reserves_topup/, 'a top-up must be reserved (capped) on public.refunds before Stripe is called');
  assert.match(acc, /refundIdempotencyKey\(txId, 'topup' \+ rowId\)/, 'a top-up is keyed on its transaction and its reserved row');
});
