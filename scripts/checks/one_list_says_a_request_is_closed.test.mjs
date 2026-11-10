// ONE LIST SAYS A REQUEST IS CLOSED (sales_engineer, customer-journey audit 10 Nov 2026).
//
// MEASURED on origin/main: the database ends a request in five statuses — completed, closed, cancelled, expired and lost
// (fn_sales_engineer_stalled_inquiry_rescue and fn_sales_engineer_closes_unreached_requests both exclude
// ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost'), 'revealed' being a live deal). Seven copies of a
// three-status list in the portal and the edge functions did not know 'expired' or 'lost'. A request the 14-day sweep had
// closed — the customer e-mailed "We have closed your request" — therefore read "Matching" in the portal with a Cancel
// button, took customer notes that customer_api mailed to every matched supplier, took supplier questions
// (messages_api), and counted as an open request on the dashboard (customer_portal).
//
// This holds the two code lists equal to each other and to the SQL's, and holds every surface to them: no surface may
// spell the short list again.
//
//   node --test scripts/checks/one_list_says_a_request_is_closed.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const REPO = join(import.meta.dirname, '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const listIn = (src) => {
  const m = /CLOSED_REQUEST_STATUSES\s*=\s*\[([^\]]*)\]/.exec(src);
  assert.ok(m, 'CLOSED_REQUEST_STATUSES is declared');
  return [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]).sort();
};

// The surfaces that decide on a request's status. Each must use the shared list and spell none of its own.
const SURFACES = [
  'src/components/me/shell/StatusParts.tsx',
  'src/components/me/requests/InquiryCard.tsx',
  'src/components/me/Clarifications.tsx',
  'supabase/functions/customer_api/actions/inquiry_lifecycle.ts',
  'supabase/functions/customer_portal/index.ts',
  'supabase/functions/messages_api/index.ts',
];

test('the portal list and the edge list are one list', () => {
  assert.deepEqual(listIn(read('src/components/me/requestStatus.ts')), listIn(read('supabase/functions/_shared/request_closed.ts')));
});

test('the list is the database\'s: every status the SQL treats as the end of a request, and no other', () => {
  const mirror = readSchemaMirror();
  const start = mirror.indexOf('FUNCTION public.fn_sales_engineer_stalled_inquiry_rescue(');
  assert.ok(start > 0, 'fn_sales_engineer_stalled_inquiry_rescue is in the mirror');
  const body = mirror.slice(start, mirror.indexOf('$function$', mirror.indexOf('$function$', start) + 10));
  const m = /coalesce\(i\.status, ''\) not in \(([^)]*)\)/.exec(body);
  assert.ok(m, 'the rescue names the statuses it does not rescue');
  const sql = [...m[1].matchAll(/'([a-z_]+)'/g)].map((x) => x[1]).filter((s) => s !== 'revealed').sort();
  assert.deepEqual(listIn(read('src/components/me/requestStatus.ts')), sql);
});

test('no surface spells its own short list of closed statuses', () => {
  const short = /\[\s*'(completed|closed|cancelled)',\s*'(completed|closed|cancelled)',\s*'(completed|closed|cancelled)'\s*[\],]/;
  for (const f of SURFACES) {
    const src = read(f);
    assert.ok(!short.test(src), f + ' spells a closed-status list of its own instead of isClosedRequest');
    assert.match(src, /isClosedRequest/, f + ' decides with isClosedRequest');
  }
});

// THE SQL DOORS SAY THE SAME (customer-journey follow-up, 10 Nov 2026). Measured on origin/main: fn_cancel_inquiry knew
// 'cancelled' and the revealed states only, fn_edit_inquiry and fn_inquiry_add_missing_specs a list without 'expired' and
// 'lost', and fn_customer_concierge_held the same three. Each routine, as the last applied-or-pending file defines it, must
// refuse every status on the list: the union of the statuses it compares against before it writes covers the whole list.
test('the SQL routines that refuse a closed request refuse every status on the list', async () => {
  const { canonicalBody } = await import('../lib/canonical_body.mjs');
  const want = listIn(read('supabase/functions/_shared/request_closed.ts'));
  for (const fn of ['fn_cancel_inquiry', 'fn_edit_inquiry', 'fn_inquiry_add_missing_specs', 'fn_customer_concierge_held', 'fn_supplier_apply_change']) {
    const { file, body } = canonicalBody(fn);
    const code = body.replace(/--[^\n]*/g, '');
    const seen = new Set();
    for (const m of code.matchAll(/(?<!q\.)status(?:\s*,\s*''\s*\))?\s*(?:(?:not\s+)?in\s*\(([^)]*)\)|=\s*'([a-z_]+)')/g)) {
      if (m[1]) for (const s of m[1].matchAll(/'([a-z_]+)'/g)) seen.add(s[1]); else seen.add(m[2]);
    }
    const missing = want.filter((s) => !seen.has(s));
    assert.deepEqual(missing, [], `${fn} (${file}) does not refuse a request that is ${missing.join(', ')}`);
  }
});
