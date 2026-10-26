// A check that replays SQL replays what production runs (accountant, 21 Sep 2026).
//
// Fails if scripts/lib/canonical_sql.mjs ever hands a check a SUPERSEDED body again -- the cause of
// "column l.iban_doc_path does not exist" in payments_are_the_accountant on 21 Sep 2026: the replay re-ran
// the_it_engineer_knows_what_should_be_backed_up_and_closes_the_loop.sql after #777 had dropped the
// column and redefined its readers.
//
//   node --test scripts/lib/canonical_sql.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { canonicalReplay, definitions } from './canonical_sql.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const OLD = 'the_it_engineer_knows_what_should_be_backed_up_and_closes_the_loop.sql';
const manifest = readFileSync(`${REPO}scripts/sql/MANIFEST.txt`, 'utf8').split(/\r?\n/).map((s) => s.trim());

test('a column #777 dropped is not in the replay of a file written before it', () => {
  assert.match(readFileSync(`${REPO}scripts/sql/${OLD}`, 'utf8'), /l\.iban_doc_path/, 'the old file no longer shows the case this guards');
  assert.doesNotMatch(canonicalReplay([OLD]), /iban_doc_path/);
});

test('every replayed routine comes from the LAST file in MANIFEST order that defines it', () => {
  const text = canonicalReplay([OLD, 'payments_are_the_accountant_and_the_seats_close_every_refund_together.sql']);
  for (const [, file, stmt] of text.matchAll(/^-- canonical: (\S+)\n([\s\S]*?)(?=\n\n-- canonical: |$)/g)) {
    const [d] = definitions(stmt);
    const at = manifest.indexOf(file);
    const later = manifest.slice(at + 1).filter((p) => /^scripts\/sql\/[^/]+\.sql$/.test(p)).find((p) => {
      try { return definitions(readFileSync(`${REPO}${p}`, 'utf8')).some((x) => x.key === d.key); } catch { return false; }
    });
    assert.equal(later, undefined, `${d.key} is replayed from ${file} but ${later} redefines it`);
  }
});

test('one routine spelled with and without names and defaults is ONE routine', () => {
  const a = definitions('create or replace function public.f(bigint, text) returns int language sql as $$ select 1 $$;');
  const b = definitions('create function public.f(p_id bigint, p_note text default null) returns int language sql as $x$ select 2 $x$;');
  assert.equal(a[0].key, b[0].key);
  assert.match(b[0].stmt, /^create or replace function/);
  assert.notEqual(definitions('create function public.f(p_id bigint, out n int) returns int language sql as $$ select 1 $$;')[0].key,
    definitions('create function public.f(p_id bigint, p_n int) returns int language sql as $$ select 1 $$;')[0].key);
});
