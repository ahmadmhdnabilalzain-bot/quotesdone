// The WhatsApp template watcher's gate reads public.messaging_template ("is anything undecided?").
// On 28 Sep 2026 its poll read only the wa_template_sids map, so 9 undecided register rows were never
// asked about, the gate never shut, and every run re-announced "all approved" (8 error rows in 24 h),
// called a pg_cron unschedule routine that does not exist, and polled 17 sids one after another past
// resilience_ping's 20 s timeout (heartbeat step `orphans` red from 16:46 UTC). Ledger 760.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../../supabase/functions/wa_templates_watch/index.ts', import.meta.url), 'utf8');

test('the poll covers the undecided register rows the gate reads', () => {
  assert.match(src, /\[\.\.\.sids, \.\.\.extra\]/);
});

test('Twilio is asked in parallel, not one sid after another', () => {
  assert.match(src, /Promise\.all\(\[\.\.\.sids, \.\.\.extra\]\.map/);
});

test('no call to the pg_cron unschedule routine, which does not exist', () => {
  assert.doesNotMatch(src, /rpc\(\s*'cron_unschedule/);
});

test('an already-live channel is not re-announced', () => {
  assert.match(src, /allApproved && \(\(await sec\('wa_templates_ready'\)\)/);
});
