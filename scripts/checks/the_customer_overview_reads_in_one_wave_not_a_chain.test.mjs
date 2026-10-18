// THE CUSTOMER OVERVIEW READS IN ONE WAVE, NOT A CHAIN (coordinator ruling G5, 19 Oct 2026, it_engineer).
//
// The overview must settle in under 2.5 s. Every database read behind project_api `dashboard` and
// customer_api `my_inquiries` runs in under 4 ms in Postgres (pg_stat_statements max), so the cost is
// the number of edge-to-database round trips made one after another. This fails if either action goes
// back to the chained shape that was removed:
//   * dashboard reading quotes by the ids of an inquiries read it had to wait for;
//   * my_inquiries awaiting the sanctions read and the quote lines one after the other.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const slice = (file, start, end) => {
  const s = readFileSync(new URL('../../' + file, import.meta.url), 'utf8');
  const a = s.indexOf(start); assert.ok(a >= 0, `${file}: ${start} not found`);
  const b = s.indexOf(end, a + start.length); assert.ok(b > a, `${file}: end marker not found`);
  return s.slice(a, b);
};

test('project_api dashboard reads quotes in the same wave as the inquiries', () => {
  const body = slice('supabase/functions/project_api/index.ts', "action === 'dashboard'", "action === 'create'");
  assert.doesNotMatch(body, /from\('quotes'\)[^;]*\.in\('inquiry_id'/, 'quotes read by inquiry ids waits for a second round trip');
  assert.equal((body.match(/await /g) || []).length, 1, 'dashboard must make exactly one awaited wave');
});

test('customer_api my_inquiries does not chain the sanctions read and the quote lines', () => {
  const body = slice('supabase/functions/customer_api/index.ts', "action === 'my_inquiries'", "action === 'spec_offer_reply'");
  assert.doesNotMatch(body, /=\s*await\s+sanctionedLeads\(/, 'sanctionedLeads awaited on its own');
  assert.doesNotMatch(body, /=\s*await\s+itemsByQuote\(/, 'itemsByQuote awaited on its own');
  assert.doesNotMatch(body, /await Promise\.all\(\[admin\.from\('leads'\)/, 'supplier rows awaited as their own wave');
});
