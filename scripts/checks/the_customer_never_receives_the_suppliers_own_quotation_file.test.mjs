// Founder ruling 1220 (13 Oct 2026): a supplier may quote by upload, by the quote form or by a photo in the chat, but
// the customer only ever sees the quotation redone in the QuotesDone template. Before this check, customer_api (reveal
// and supplier profile) and stripe_confirm signed the supplier's stored file in the quote storage bucket and returned it
// as original_file_url after the reveal, so a photographed quotation reached the customer raw.
// This check fails if any function that answers a customer signs or downloads from that bucket again.
// Assigned: sales_engineer.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const CUSTOMER_FACING = ['supabase/functions/customer_api/index.ts', 'supabase/functions/stripe_confirm/index.ts'];
const BUCKET = /storage\s*\.from\(\s*['"]quote-files['"]\s*\)/;

test('no customer-facing function hands out the supplier\'s own quotation file (ruling 1220)', () => {
  const hits = [];
  for (const f of CUSTOMER_FACING) fs.readFileSync(f, 'utf8').split('\n').forEach((l, i) => { if (BUCKET.test(l)) hits.push(`${f}:${i + 1}`); });
  assert.deepEqual(hits, [], 'the customer must only get the QuotesDone template, never the supplier\'s file:\n' + hits.join('\n'));
});
