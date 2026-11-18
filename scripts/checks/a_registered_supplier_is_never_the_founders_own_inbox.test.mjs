// A REGISTERED SUPPLIER IS NEVER THE FOUNDER'S OWN INBOX (sales_engineer, 18 Nov 2026; founder ruling 1729). fn_is_founder_own_inbox named
// ahmad@666realestate.ae, so the mail of Triple Six Real Estate (lead 158318, approved; claimed by info@666realestate.ae) was read as the
// founder's own test mail: nobody waiting, nothing sent. The founder has e-mail authority over that company, but it is a supplier.
// FAILS if: the canonical body (MANIFEST then pending) names any 666realestate address, or any address of an approved supplier the
// repository knows; drops one of his own inboxes; loses its revoke or its pinned search_path.
//   node --test scripts/checks/a_registered_supplier_is_never_the_founders_own_inbox.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { manifestWithPending, applyState } from '../lib/pending_sql.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const FILE = 'scripts/sql/triple_six_real_estate_is_a_supplier_and_its_mail_is_real_supplier_mail.sql';
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const HIS = ['management@quotesdone.com', 'ahmadmhdnabilalzain@gmail.com', 'management@doratajewelries.com', 'djzaino@outlook.com', 'bookings@djzaino.com', 'fati.labib@icloud.com'];
// the suppliers whose mail is real supplier mail although the founder can read it (ruling 1729)
const SUPPLIERS = ['ahmad@666realestate.ae', 'info@666realestate.ae', '666realestate'];

function canonical(fn) {
  const re = new RegExp(`create or replace function public\\.${fn}\\(`, 'i');
  const path = manifestWithPending().filter((p) => { try { return re.test(code(R(p))); } catch { return false; } }).pop();
  assert.ok(path, `${fn} is defined nowhere`);
  const src = code(R(path));
  const open = src.search(re);
  return { path, body: src.slice(open, src.indexOf('$fn$;', src.indexOf('$fn$', open) + 4) + 5), src };
}

test('the founder\'s own inbox list names none of a supplier\'s addresses, and still names all of his', () => {
  const { path, body, src } = canonical('fn_is_founder_own_inbox');
  for (const a of SUPPLIERS) assert.ok(!body.toLowerCase().includes(a), `${path}: fn_is_founder_own_inbox names ${a}, a supplier (ruling 1729)`);
  for (const a of HIS) assert.ok(body.includes(`'${a}'`), `${path}: ${a} is no longer one of his inboxes`);
  assert.match(body, /key in \('founder_email', 'admin_emails'\)/, 'his configured addresses are no longer read');
  assert.match(body, /set search_path to 'public', 'pg_temp'/);
  assert.ok(src.includes('revoke execute on function public.fn_is_founder_own_inbox(text) from public, anon, authenticated;'), 'the revoke is missing');
});

test('the change is applied or pending, never both, and ends in a verdict row', () => {
  const st = applyState(FILE);
  assert.ok(st.applied !== (st.note !== null), 'exactly one of a MANIFEST line and a pending note');
  if (st.note !== null) assert.ok(st.note.length > 40, 'the pending note says nothing');
  assert.match(R(FILE), /'PROBE OK: Triple Six Real Estate is a supplier/);
  assert.doesNotMatch(code(R(FILE)), /raise notice/i);
});
