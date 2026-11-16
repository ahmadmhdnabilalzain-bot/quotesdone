// A SUPPLIER'S REFERRAL LINK REACHES THE REGISTRATION (sales_engineer, 16 Nov 2026; agent W3_PEOPLE; SUPPLIER hole #11).
// An approved supplier's link (fn_supplier_referral_link, scripts/sql/a_referral_is_recorded_counted_and_thanked.sql) carries its
// code as the link's own tags: utm_source=referral, utm_medium=supplier, utm_content=<code>. The browser keeps the first tagged
// visit (src/lib/firstTouch.ts) and the registration hands it to fn_marketing_first_touch_record, whose trigger z40 records the
// referrer. One rule is new here: a colleague's own referral link is a stronger cause than an earlier post, so a referral visit
// replaces a kept non-referral touch, and is never itself replaced. Offline: no database, no network.
//   env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL node --test scripts/checks/a_referral_link_reaches_the_registration.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { captureFirstTouch, readFirstTouch, FIRST_TOUCH_KEY } from '../../src/lib/firstTouch.ts';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const store = () => { const m = new Map(); return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)) }; };
const LINK = 'https://quotesdone.com/en/supplier?utm_source=referral&utm_medium=supplier&utm_content=qdabc123def4';
const POST = 'https://quotesdone.com/en/supplier?utm_source=linkedin&utm_medium=social&utm_campaign=2026-11&utm_content=post-7';

test('the referral link is kept as the first touch, with its code', () => {
  const s = store();
  captureFirstTouch(LINK, s);
  const t = readFirstTouch(s);
  assert.equal(t.utm_source, 'referral');
  assert.equal(t.utm_medium, 'supplier');
  assert.equal(t.utm_content, 'qdabc123def4');
});

test('a referral visit replaces an earlier post\'s touch; a later post never replaces the referral', () => {
  const s = store();
  captureFirstTouch(POST, s);
  assert.equal(readFirstTouch(s).utm_source, 'linkedin');
  captureFirstTouch(LINK, s);
  assert.equal(readFirstTouch(s).utm_content, 'qdabc123def4', 'the colleague\'s link wins over an earlier post');
  captureFirstTouch(POST, s);
  assert.equal(readFirstTouch(s).utm_source, 'referral', 'a later post does not undo it');
  const s2 = store();
  captureFirstTouch(POST, s2);
  captureFirstTouch('https://quotesdone.com/en/supplier?utm_source=facebook&utm_medium=social', s2);
  assert.equal(readFirstTouch(s2).utm_source, 'linkedin', 'first touch still wins between ordinary tags');
  assert.ok(FIRST_TOUCH_KEY);
});

test('the routine\'s link is the shape the browser keeps, and both registration doors send the kept touch', () => {
  const sql = readFileSync(join(ROOT, 'scripts/sql/a_referral_is_recorded_counted_and_thanked.sql'), 'utf8');
  assert.match(sql, /utm_source=referral&utm_medium=supplier&utm_content=' \|\| v_code/);
  assert.match(sql, /new\.utm_source is distinct from 'referral'/);
  assert.match(readFileSync(join(ROOT, 'src/components/portal/supplier/core/Onboarding.tsx'), 'utf8'), /first_touch: \(\(\) => \{ try \{ return readFirstTouch/);
  assert.match(readFileSync(join(ROOT, 'src/components/portal/SupplierPortal.tsx'), 'utf8'), /first_touch: \(\(\) => \{ try \{ return readFirstTouch/);
});
