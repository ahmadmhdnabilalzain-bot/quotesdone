// scripts/invitation_inbox_check.mjs --send-seed sends a real invitation through send_outbox. It must be
// INCAPABLE of reaching a real person: only inbox-placement test services are accepted (22 Sep 2026,
// customer_support; founder instruction 635 allowed mail-tester.com and similar services only).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { seedAddressAllowed } from '../invitation_inbox_check.mjs';

test('a mail-tester address (and its srv subdomain) is accepted', () => {
  assert.equal(seedAddressAllowed('test-abc123@srv1.mail-tester.com'), true);
  assert.equal(seedAddressAllowed('x@mail-tester.com'), true);
});

test("the founder's own two inboxes are accepted, and nobody else on those domains", () => {
  assert.equal(seedAddressAllowed('ahmadmhdnabilalzain@gmail.com'), true);
  assert.equal(seedAddressAllowed('Management@QuotesDone.com'), true);
  assert.equal(seedAddressAllowed('management@doratajewelries.com'), true);
  assert.equal(seedAddressAllowed('info@doratajewelries.com'), false);
  for (const a of ['info@quotesdone.com', 'someone@gmail.com', 'ahmadmhdnabilalzain@gmail.com.evil.ae']) assert.equal(seedAddressAllowed(a), false, a);
});

test('a real supplier, a lookalike and a smuggled address are refused', () => {
  for (const a of ['info@acme.ae', 'test@mail-tester.com.evil.ae', 'test@evilmail-tester.com', 'a@b.com,x@srv1.mail-tester.com',
    'x@srv1.mail-tester.com>, <info@acme.ae', '', undefined, 'no-at-sign']) {
    assert.equal(seedAddressAllowed(a), false, String(a));
  }
});

// 5 Oct 2026 (ledger 1115): --lane=m365 routes the seed to the Microsoft 365 lane by marking its kind. The marker
// must be exactly send_outbox/m365_lane.ts's M365_SEED_KIND, and only the two known lanes are accepted.
test('--lane=m365 marks the seed with the kind send_outbox routes on; nothing else is a lane', async () => {
  const { LANES, seedKind } = await import('../invitation_inbox_check.mjs');
  const { readFileSync } = await import('node:fs');
  const src = readFileSync(new URL('../../supabase/functions/send_outbox/m365_lane.ts', import.meta.url), 'utf8');
  const kind = /M365_SEED_KIND = '([a-z0-9_]+)'/.exec(src)?.[1];
  assert.equal(seedKind('m365'), `'${kind}'`);
  assert.equal(seedKind('resend'), 'null');
  assert.deepEqual(LANES, ['resend', 'm365']);
});
