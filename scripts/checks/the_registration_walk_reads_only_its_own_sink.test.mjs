// THE REGISTRATION WALK READS ONLY ITS OWN SINK (28 Oct 2026, sales_engineer, ledger 1375). scripts/e2e/resend_sink.mjs
// lets the production walk receive the REAL sign-up code: the form sends it to delivered+qd-<tag>-sup<n>@resend.dev
// (Resend's test sink: accepted, recorded delivered, dropped) and the walk reads it back from Resend through pg_net.
// That reader can see the account's whole sent-mail list, so it must be incapable of returning anything but the run's
// own sink message, and the clean-up must be incapable of deleting a real account. This fails if either guard goes.
// Offline: both refusals throw before any network call.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isSink, sinkAddress, readCode, cleanSink } from '../e2e/resend_sink.mjs';

test('a run sink address is recognised, and nothing else is', () => {
  assert.equal(isSink(sinkAddress('ab12cd34', 0)), true);
  for (const a of ['delivered@resend.dev', 'management@quotesdone.com', 'supplier@quotesdone.com', 'someone@gmail.com',
                   'delivered+qd-ab12cd34-sup0@resend.dev.evil.com', 'qd-ab12cd34-sup0@example.invalid', 'bounced+qd-ab12cd34-sup0@resend.dev'])
    assert.equal(isSink(a), false, a);
});

test('the code reader and the clean-up refuse any other address before touching the network', async () => {
  await assert.rejects(() => readCode('someone@gmail.com', Date.now()), /only a run sink/);
  await assert.rejects(() => cleanSink('management@quotesdone.com'), /only a run sink/);
});
