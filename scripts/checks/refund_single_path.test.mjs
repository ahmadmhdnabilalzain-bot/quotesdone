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
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FNDIR = join(root, 'supabase', 'functions');
const read = (slug) => readFileSync(join(FNDIR, slug, 'index.ts'), 'utf8');

test('no edge function sets a terminal refund state on transactions by hand', () => {
  // The class, not the instance. Any function that writes a settled refund state straight onto
  // transactions has invented a second refund path with its own controls.
  const offenders = [];
  for (const d of readdirSync(FNDIR, { withFileTypes: true })) {
    if (!d.isDirectory() || d.name === '_shared') continue;
    let src;
    try { src = read(d.name); } catch { continue; }
    // refunds_api and stripe_webhook are the two legitimate writers: one gates on Control Mode and
    // calls Stripe, the other records what Stripe already did.
    if (d.name === 'refunds_api' || d.name === 'stripe_webhook') continue;
    if (/refund_status:\s*'(refunded|succeeded)'/.test(src)) offenders.push(d.name);
  }
  assert.deepEqual(offenders, [],
    'these functions write a settled refund state directly onto transactions, bypassing fn_refund_request and ' +
    'the Control Mode gate: ' + offenders.join(', '));
});

test('refunds_api still gates the Stripe execution on Control Mode', () => {
  const src = read('refunds_api');
  assert.match(src, /control_mode/i,
    'refunds_api no longer references Control Mode. `resolve` issues a REAL Stripe refund; without that gate the ' +
    'only thing standing between an internal credential and money leaving the account is the credential itself.');
});
