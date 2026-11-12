// A NOTICE IS A DUPLICATE ONLY OF THE SAME EVENT (sales_engineer, 12 Nov 2026; final audit customer_journey M8 and
// integration_review finding 4, fix group Q5; ruling 1631). Every new_quote notice on a request reads the same, so the
// duplicate guards, keyed on the text alone, would have cancelled a second supplier's quote notice (6 of 8 in the audit).
// The insert trigger and the send-time guard now both compare the event: inquiry_id, quote_id and dedupe_key.
// WHAT FAILS IF THE CAUSE RETURNS
//   * the trigger stops comparing any of the three event columns;
//   * the send-time key (_shared/outbox_duplicate_guard.ts messageKey) and the trigger stop comparing the same three;
//   * supplier_api stops naming the quote on new_quote;
//   * the probe stops proving both halves (two quotes kept, the same quote twice refused).
// Behaviour: the deno tests in _shared/outbox_duplicate_guard.test.ts and the aborted probe on production.
//   node --test scripts/checks/a_notice_is_a_duplicate_only_of_the_same_event.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const NAME = 'a_notice_is_a_duplicate_only_of_the_same_event';
const code = (p) => readFileSync(ROOT + p, 'utf8').split('\n').filter((l) => !/^\s*(--|\/\/)/.test(l)).join('\n');

test('the insert trigger compares the event the row is about', () => {
  const s = code('scripts/sql/' + NAME + '.sql');
  assert.match(s, /create or replace function public\.fn_notifications_the_same_message_is_sent_once\(\)/);
  assert.match(s, /and n\.inquiry_id is not distinct from new\.inquiry_id/);
  assert.match(s, /and n\.quote_id is not distinct from new\.quote_id/);
  assert.match(s, /and coalesce\(btrim\(n\.dedupe_key\), ''\) = coalesce\(btrim\(new\.dedupe_key\), ''\)/);
  assert.match(s, /security definer\s+set search_path to 'public', 'pg_temp'/);
  assert.match(s, /new\.status := 'cancelled'/, 'a true repeat is no longer refused');
});

test('the send-time guard compares the same three columns, and reads them back', () => {
  const g = code('supabase/functions/_shared/outbox_duplicate_guard.ts');
  assert.match(g, /fold\(r\.inquiry_id\), fold\(r\.quote_id\), text\(r\.dedupe_key\)\]\.join/);
  assert.match(g, /const cols = '[^']*,inquiry_id,quote_id,dedupe_key';/);
});

test('the new_quote notice names its quote', () => {
  const q = code('supabase/functions/supplier_api/lib/quote_acceptance.ts');
  assert.match(q, /type: 'new_quote',[^}]*inquiry_id: inquiryId, quote_id: quoteId,/);
  assert.match(q, /notifyNewQuote\(inquiryId, qid\)/);
});

test('its probe is pure and proves both halves', () => {
  const p = readFileSync(ROOT + 'scripts/sql/' + NAME + '_probe.sql', 'utf8');
  assert.match(p, /@example\.invalid/);
  assert.doesNotMatch(p, /\b(create|alter|drop)\s+(function|table|trigger)/i);
  assert.match(p, /the second supplier''s quote was cancelled/);
  assert.match(p, /the same quote told again was/);
  assert.match(p, /raise exception 'CHK<<PROBE OK/);
});

test('both files wait with a note until they are applied', () => {
  const manifest = readFileSync(ROOT + 'scripts/sql/MANIFEST.txt', 'utf8').split('\n');
  for (const f of [NAME, NAME + '_probe']) {
    const listed = manifest.includes('scripts/sql/' + f + '.sql');
    assert.ok(listed !== existsSync(ROOT + 'scripts/sql/pending/' + f + '.txt'), f + ': exactly one of a MANIFEST line or a pending note');
  }
});
