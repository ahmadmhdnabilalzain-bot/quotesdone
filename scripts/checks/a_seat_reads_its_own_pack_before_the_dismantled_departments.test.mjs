// A SEAT READS ITS OWN PACK BEFORE THE DISMANTLED DEPARTMENTS (ceo, ledger 1003 stage 2, 19 Oct 2026).
//
// WHAT FAILS IF THE CAUSE RETURNS (static, no token):
//   * either retrieval routine reads an ops_knowledge row that carries a dept_key (the departments the founder removed
//     on 7 Sep 2026; 7,039 such rows ranked beside the seat packs and answered "the CFO holds the bank details");
//   * fn_reason_retrieve_ml scores a row that has no multilingual vector yet at the gte weight only, or reports its
//     similarity as 0 (every seat pack row loaded after the nightly backfill lost every ranking that way);
//   * a routine loses its pinned search_path or its revoke, or the file is both / neither pending and in the MANIFEST.
//
//   node --test scripts/checks/a_seat_reads_its_own_pack_before_the_dismantled_departments.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const NAME = 'a_seat_reads_its_own_pack_before_the_dismantled_departments';
const FILE = `scripts/sql/${NAME}.sql`;
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const routine = (s, name) => s.slice(s.indexOf(`FUNCTION public.${name}(`), s.indexOf('end $fn$;', s.indexOf(`FUNCTION public.${name}(`)));

test('no ops_knowledge row of a dismantled department is a candidate in either routine', () => {
  const s = code(read(FILE));
  const gte = routine(s, 'fn_reason_retrieve'), ml = routine(s, 'fn_reason_retrieve_ml');
  assert.equal((gte.match(/from public\.ops_knowledge o/g) || []).length, (gte.match(/o\.dept_key is null/g) || []).length, 'fn_reason_retrieve');
  assert.ok((ml.match(/public\.ops_knowledge o/g) || []).length >= 2);
  assert.equal((ml.match(/o\.dept_key is null/g) || []).length, 2, 'both ops_knowledge candidate branches of fn_reason_retrieve_ml');
});

test('a row with no multilingual vector is ranked by its gte rank at full weight and reports its gte similarity', () => {
  const ml = routine(code(read(FILE)), 'fn_reason_retrieve_ml');
  assert.match(ml, /case when r\.r_ml is null and r\.r_gte is not null then 1\.0 \/ \(60 \+ r\.r_gte\) else/);
  assert.equal((ml.match(/coalesce\(sc\.s_ml, sc\.s_gte\) s_ml/g) || []).length, 11, 'every source branch reports coalesce(s_ml, s_gte)');
});

test('both routines keep a pinned search_path and their revoke; the file is pending or in the MANIFEST, not both', () => {
  const s = code(read(FILE));
  assert.equal((s.match(/SET search_path TO 'public'/g) || []).length, 2);
  for (const sig of ['fn_reason_retrieve(text, vector, integer, text, text, text)', 'fn_reason_retrieve_ml(text, vector, vector, integer, integer, text, text, text)']) {
    assert.ok(s.includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), sig);
  }
  const listed = read('scripts/sql/MANIFEST.txt').split('\n').some((l) => l.trim() === FILE);
  const pending = existsSync(join(REPO, `scripts/sql/pending/${NAME}.txt`));
  assert.ok(listed !== pending, 'exactly one of: a MANIFEST line, a pending note');
});
