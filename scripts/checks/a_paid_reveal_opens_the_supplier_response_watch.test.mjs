// A paid reveal opens the supplier response watch (19 Oct 2026, sales_engineer).
//
// MEASURED. public.supplier_response_watch held 0 rows ever: nothing inserted a watch at reveal, so a
// supplier's silence after a paid reveal was recorded nowhere and sandbox run 5 (tag 321d13ae) S12
// found no watch. Fails if the opener disappears, stops firing on INSERT, or (once applied) is
// missing from the production mirror.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const FILE = 'scripts/sql/a_paid_reveal_opens_the_supplier_response_watch.sql';
const root = new URL('../../', import.meta.url);
const sql = readFileSync(new URL(FILE, root), 'utf8');

test('the trigger fires after INSERT on transactions and inserts the watch', () => {
  assert.match(sql, /create trigger z25_reveal_opens_response_watch\s+after insert or update of revealed_at, fee_status on public\.transactions/);
  assert.match(sql, /insert into public\.supplier_response_watch \(transaction_id, lead_id\)/);
  assert.match(sql, /on conflict \(transaction_id\) do nothing/);
});

test('the file is either pending with a note or applied and visible in the production mirror', () => {
  const manifest = readFileSync(new URL('scripts/sql/MANIFEST.txt', root), 'utf8').split(/\r?\n/);
  const applied = manifest.includes(FILE);
  const pending = existsSync(new URL('scripts/sql/pending/a_paid_reveal_opens_the_supplier_response_watch.txt', root));
  assert.ok(applied !== pending, `exactly one of MANIFEST line / pending note must exist (applied=${applied}, pending=${pending})`);
  if (applied) assert.match(readSchemaMirror(), /z25_reveal_opens_response_watch/, 'applied, but production has no z25_reveal_opens_response_watch');
});
