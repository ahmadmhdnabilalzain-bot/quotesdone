// The refund settlement logic lives in the database (fn_refund_settle) and is tested there against
// the seven delivery scenarios. What this file checks is the half that lives in the repo: that
// stripe_webhook still recognises all three refund event types and still extracts the fields the
// settlement function needs from each of their two different payload shapes.
//
// The shapes differ and it matters:
//   charge.refunded  -> data.object is a CHARGE, refunds are in data.object.refunds.data[]
//   refund.created   -> data.object IS the refund
//   refund.updated   -> data.object IS the refund
// Reading only one shape silently drops the other, and a dropped refund is money that never
// reconciles.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(HERE, '..', '..');
const src = fs.readFileSync(path.join(ROOT, 'supabase', 'functions', 'stripe_webhook', 'index.ts'), 'utf8');

test('the webhook handles all three refund event types', () => {
  for (const evt of ['charge.refunded', 'refund.updated', 'refund.created']) {
    assert.ok(src.includes(evt), `stripe_webhook does not handle ${evt}`);
  }
});

test('the webhook reads both refund payload shapes', () => {
  assert.match(src, /refunds\?\.data/, 'the charge.refunded array shape is not read');
  assert.match(src, /object === 'refund'/, 'the bare refund object shape is not read');
});

test('the webhook passes every field the settlement function needs', () => {
  for (const field of ['p_stripe_refund_id', 'p_status', 'p_amount_fils', 'p_payment_intent', 'p_charge_id', 'p_failure_reason']) {
    assert.ok(src.includes(field), `stripe_webhook does not pass ${field} to fn_refund_settle`);
  }
});

test('the webhook still verifies the Stripe signature before doing anything', () => {
  // The refund work was added to a function that already verified signatures. Losing that while
  // adding events would turn an unauthenticated POST into a way to fabricate refund records.
  assert.match(src, /stripe-signature/i, 'the signature header is no longer read');
  const sigAt = src.search(/stripe-signature/i);
  const refundAt = src.indexOf('charge.refunded');
  assert.ok(sigAt > 0 && sigAt < refundAt, 'refund handling appears before signature verification');
});

test('settlement is delegated to the database, not reimplemented in the handler', () => {
  // The ordering and idempotency rules are in fn_refund_settle. A second implementation in
  // TypeScript would be a second set of rules to keep in step.
  assert.match(src, /rpc\('fn_refund_settle'/, 'the webhook no longer calls fn_refund_settle');
  assert.doesNotMatch(src, /from\('refunds'\)\s*\.\s*(insert|update|upsert)/,
    'the webhook writes to refunds directly, bypassing the ordering guard');
});
