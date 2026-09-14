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
// 3 SEP 2026: the event names live in ONE shared list (_shared/stripe_events.ts) that both the
// handler and stripe_setup read, so a branch cannot exist without its subscription. The handler
// branches on the exported arrays rather than on string literals, so this check reads the shared
// list for the names and the handler for the branches.
const shared = fs.readFileSync(path.join(ROOT, 'supabase', 'functions', '_shared', 'stripe_events.ts'), 'utf8');

test('the webhook handles all four refund event types', () => {
  assert.ok(src.includes("from '../_shared/stripe_events.ts'") && src.includes('REFUND_EVENTS'),
    'stripe_webhook does not read the shared REFUND_EVENTS list');
  assert.ok(src.includes('(REFUND_EVENTS as readonly string[]).includes(String(event.type))'),
    'stripe_webhook does not branch on REFUND_EVENTS');
  const start = shared.indexOf('REFUND_EVENTS = [');
  const list = start >= 0 ? shared.slice(start, shared.indexOf(']', start)) : '';
  for (const evt of ['charge.refunded', 'refund.updated', 'refund.created', 'refund.failed']) {
    assert.ok(list.includes(`'${evt}'`), `the shared REFUND_EVENTS list (read by stripe_webhook) does not carry ${evt}`);
  }
});

test('a test-mode endpoint can share this handler without weakening live verification', () => {
  // Two endpoints, two signing secrets, each verified in full. This is what lets refund behaviour
  // be proven in Stripe test mode instead of by refunding real customer payments.
  //
  // 14 SEP 2026 — THE RULE CHANGED, THE PROTECTION DID NOT. The handler used to try the live secret,
  // then the test secret. It now reads the livemode the event claims and verifies with THAT mode's
  // secret only (_shared/stripe_events.ts stripeEventMode / signingSecretFor); a claim the signature
  // does not back is rejected. So a live event is still verified with the live secret, a test event
  // can never be accepted by the live secret, and neither mode has a shortcut: both go through the
  // same full HMAC routine.
  assert.match(src, /stripe_webhook_secret_test/, 'no test-mode signing secret is accepted');
  assert.match(src, /stripe_webhook_secret'/, 'the live signing secret is no longer read');
  assert.match(src, /signingSecretFor\(stripeEventMode\(event\), \{ live: whsecLive, test: whsecTest \}\)/,
    'verification no longer picks the secret from the event\'s signed livemode');
  assert.match(src, /verifySig\(sig, raw, whsecForMode\)/, 'the chosen secret is not verified with the full HMAC routine');
  // The helper: a live event gets the LIVE secret, a test event the TEST secret, anything else none.
  assert.match(shared, /livemode === true\) return 'live'/, 'a livemode:true event is no longer treated as live');
  assert.match(shared, /livemode === false\) return 'test'/, 'a livemode:false event is no longer treated as test');
  assert.match(shared, /mode === 'live' \? secrets\.live : mode === 'test' \? secrets\.test : ''/,
    'signingSecretFor no longer maps live->live and test->test with nothing for an unknown mode');
  // An unverified request must still be refused outright, before anything is written.
  assert.match(src, /if \(!sigMode\)/, 'a request matching no secret is no longer rejected');
});

test('a refund amount is looked up with the key for the mode it arrived on', () => {
  // A test-mode refund id queried with the live key returns 404, which would look like "Stripe has
  // no amount" and quarantine a perfectly well-formed refund.
  assert.match(src, /sigMode === 'test'/, 'the amount lookup ignores which mode the event came from');
  assert.match(src, /stripe_secret_key_test/, 'there is no test-mode API key for the lookup');
});

test('no secret value is ever logged', () => {
  // Only which mode verified, never the material. Grep for the obvious mistakes.
  assert.doesNotMatch(src, /logRun\([^)]*whsec/, 'a signing secret is passed into a log line');
  assert.doesNotMatch(src, /logRun\([^)]*\bsk\b/, 'a Stripe API key is passed into a log line');
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

test('a missing amount is looked up from Stripe before it is accepted as unknown', () => {
  // The webhook must ask the authoritative source before recording "unknown". One extra API call on
  // a path that almost never fires is cheap; a refund with no amount in the ledger is not.
  assert.match(src, /api\.stripe\.com\/v1\/refunds\//,
    'stripe_webhook does not look the refund up by id when the event carries no amount');
  assert.match(src, /amountSource = 'stripe_api'/,
    'a looked-up amount is not recorded as coming from the Stripe API');
  assert.match(src, /p_amount_source/, 'the amount source is not passed to the ledger');
});

test('the webhook never fabricates a refund amount', () => {
  // The 1-fils placeholder is gone from both sides. A number that is not known is not written.
  assert.doesNotMatch(src, /amount_fils:\s*1\b/, 'a literal 1-fils amount is back in the webhook');
  assert.match(src, /let amountFils: number \| null/,
    'the amount is no longer allowed to be null - unknown will be coerced into a number again');
});

test('an event that cannot be recorded is quarantined, not dropped', () => {
  assert.match(src, /fn_refund_quarantine/,
    'stripe_webhook does not quarantine refund events it cannot record');
});

test('settlement is delegated to the database, not reimplemented in the handler', () => {
  // The ordering and idempotency rules are in fn_refund_settle. A second implementation in
  // TypeScript would be a second set of rules to keep in step.
  assert.match(src, /rpc\('fn_refund_settle'/, 'the webhook no longer calls fn_refund_settle');
  assert.doesNotMatch(src, /from\('refunds'\)\s*\.\s*(insert|update|upsert)/,
    'the webhook writes to refunds directly, bypassing the ordering guard');
});
