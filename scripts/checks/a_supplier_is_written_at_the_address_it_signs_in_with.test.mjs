// A SUPPLIER IS WRITTEN AT THE ADDRESS IT SIGNS IN WITH (customer_support, 10 Nov 2026; supplier follow-up of #1909, item 4).
//
// MEASURED on origin/main: the loss notice job_awarded_other went to leads.email, the listing's address, in BOTH places
// that send it (customer_api/lib/matching.ts notifyLosers and fn_sales_engineer_tells_losing_suppliers), and so did the
// new-request notice (matching.ts new_inquiry) and the licence-renewal ask (fn_licence_expiry_sweep). The address a
// registered supplier signs in with is leads.claimed_by. One helper each side: _shared/supplier_address.ts and
// public.fn_supplier_address (scripts/sql/a_supplier_is_written_at_the_address_it_signs_in_with.sql).
//
//   node --test scripts/checks/a_supplier_is_written_at_the_address_it_signs_in_with.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const REPO = join(import.meta.dirname, '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/a_supplier_is_written_at_the_address_it_signs_in_with.sql';

test('the edge side writes a supplier through supplierAddress, never leads.email', () => {
  const src = read('supabase/functions/customer_api/lib/matching.ts');
  assert.doesNotMatch(src, /to_email:\s*s\.email\b/, 'a supplier notice addressed to the listing');
  assert.match(src, /type: 'job_awarded_other', to_email: supplierAddress\(s\)/);
  assert.match(src, /type: 'new_inquiry', to_email: supplierAddress\(s\)/);
  assert.equal((src.match(/from\('leads'\)\.select\('[^']*claimed_by[^']*'\)/g) || []).length, 2, 'both reads fetch claimed_by');
});

test('the database side: both routines read fn_supplier_address, applied or pending', () => {
  const sql = read(FILE);
  assert.match(sql, /select nullif\(lower\(btrim\(coalesce\(nullif\(btrim\(p_claimed_by\), ''\), p_email, ''\)\)\), ''\)/);
  assert.match(sql, /coalesce\(public\.fn_supplier_address\(le\.claimed_by, le\.email\), ''\) as to_email/);
  assert.match(sql, /public\.fn_supplier_address\(l\.claimed_by, l\.email\) as email/);
  const mirror = readSchemaMirror();
  const live = (name) => { const i = mirror.indexOf('FUNCTION public.' + name + '('); return mirror.slice(i, mirror.indexOf('$function$', mirror.indexOf('$function$', i) + 10)); };
  const applied = live('fn_sales_engineer_tells_losing_suppliers').includes('fn_supplier_address') && live('fn_licence_expiry_sweep').includes('fn_supplier_address');
  assert.ok(applied || existsSync(join(REPO, 'scripts/sql/pending/a_supplier_is_written_at_the_address_it_signs_in_with.txt')),
    'the routines write to the listed address and no pending note says the fix is on its way');
});
