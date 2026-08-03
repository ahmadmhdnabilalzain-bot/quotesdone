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
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FNDIR = join(root, 'supabase', 'functions');
const read = (slug) => readFileSync(join(FNDIR, slug, 'index.ts'), 'utf8');

test('secretary_act requests a refund through the policy function, it does not decide one', () => {
  const src = read('secretary_act');
  const fn = src.slice(src.indexOf('async function tool_issue_refund('), src.indexOf('async function tool_supplier_decision('));
  assert.ok(fn.length > 0, 'tool_issue_refund is gone from secretary_act - this guard is now testing nothing');
  assert.match(fn, /rpc\('fn_refund_request'/,
    'tool_issue_refund does not call fn_refund_request, so it is deciding a refund outside the one function ' +
    'that knows the window and the ceiling.');
  assert.doesNotMatch(fn, /refund_status:\s*'refunded'/,
    "tool_issue_refund still writes refund_status: 'refunded' directly. That marks the books refunded without " +
    'a refunds row, without Stripe, and without the Control Mode gate on refunds_api.');
  assert.doesNotMatch(fn, /refund_resolved_at/,
    'tool_issue_refund still stamps refund_resolved_at itself. Resolution is what refunds_api does after Stripe ' +
    'confirms; asserting it here makes the timestamp a claim rather than a record.');
});

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

test('the refund reason recorded is from the closed vocabulary, not guessed from free text', () => {
  const src = read('secretary_act');
  const fn = src.slice(src.indexOf('async function tool_issue_refund('), src.indexOf('async function tool_supplier_decision('));
  assert.match(fn, /p_reason_code: 'other'/,
    "tool_issue_refund does not pin p_reason_code. refunds.reason_code has a CHECK constraint with eight legal " +
    'values; inferring one from a founder sentence either violates the constraint or files the wrong reason.');
  assert.match(fn, /p_note: String\(reason/,
    'the founder\'s own wording is not preserved in p_note, so the reason for the refund is lost.');
});

test('refunds_api still gates the Stripe execution on Control Mode', () => {
  const src = read('refunds_api');
  assert.match(src, /control_mode/i,
    'refunds_api no longer references Control Mode. `resolve` issues a REAL Stripe refund; without that gate the ' +
    'only thing standing between an internal credential and money leaving the account is the credential itself.');
});
