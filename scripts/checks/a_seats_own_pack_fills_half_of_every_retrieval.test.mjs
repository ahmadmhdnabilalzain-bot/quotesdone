// A SEAT'S OWN PACK FILLS HALF OF EVERY RETRIEVAL (ceo, ledger 1003 stage 2, 19 Oct 2026). Measured: retrieval
// returned generic kb_chunks at ~0.85 and reserved only 3 own-seat rows of 12, so a seat's own short fact (the Resend
// cap, a cadence, an owner) never reached think(). Both routines now reserve the seat's best k own rows. This pins the
// reservation in the file that defines them; the effect is measured by seat_qualification_exam.mjs --with-sql.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const FILE = 'scripts/sql/a_seats_own_pack_fills_half_of_every_retrieval.sql';
const src = readFileSync(new URL('../../' + FILE, import.meta.url), 'utf8');
const body = (name) => src.slice(src.indexOf(`FUNCTION public.${name}(`), src.indexOf('end $fn$;', src.indexOf(`FUNCTION public.${name}(`)));

test('fn_reason_retrieve_ml reserves at least k own rows of the k * 2 it returns', () => {
  assert.match(body('fn_reason_retrieve_ml'), /own\s+integer := least\(greatest\(coalesce\(p_own, 3\), k\), 2 \* k\);/);
  assert.match(body('fn_reason_retrieve_ml'), /select \* from hits where mine order by score desc limit own/);
});

test('fn_reason_retrieve reserves the seat\'s best k own rows and puts them first', () => {
  const b = body('fn_reason_retrieve');
  assert.match(b, /row_number\(\) over \(partition by h\.mine order by h\.sim desc\) <= k reserved/);
  assert.match(b, /order by reserved desc, sim desc limit k \* 2/);
  // every seat-pack table is marked own; the generic corpus is not
  for (const t of ['sales_knowledge', 'accountant_knowledge', 'it_engineer_knowledge', 'support_knowledge', 'ceo_knowledge', 'marketing_knowledge'])
    assert.match(b, new RegExp(String.raw`'reviewed', true\s+from public\.` + t + ' s'), t);
  for (const t of ['kb_chunks', 'ops_knowledge', 'company_faq']) assert.doesNotMatch(b, new RegExp(String.raw`'reviewed', true\s+from public\.` + t), t);
});

test('both signatures keep their revoke, and the file waits for merge with a note', () => {
  assert.match(src, /revoke execute on function public\.fn_reason_retrieve\(text, vector, integer, text, text, text\) from public, anon, authenticated;/);
  assert.match(src, /revoke execute on function public\.fn_reason_retrieve_ml\(text, vector, vector, integer, integer, text, text, text\) from public, anon, authenticated;/);
  const pending = existsSync(new URL('../../scripts/sql/pending/a_seats_own_pack_fills_half_of_every_retrieval.txt', import.meta.url));
  const listed = readFileSync(new URL('../../scripts/sql/MANIFEST.txt', import.meta.url), 'utf8').split('\n').includes('a_seats_own_pack_fills_half_of_every_retrieval.sql');
  assert.ok(pending !== listed, 'exactly one of: a pending note, or a MANIFEST line');
});
