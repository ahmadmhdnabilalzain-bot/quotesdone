// A SEAT'S OWN PACK FILLS HALF OF EVERY INTERNAL RETRIEVAL, AND NEVER REACHES AN OUTSIDE AUDIENCE (ceo, ledger 1003
// stage 2, 19 Oct 2026, #1567). Measured: retrieval returned generic kb_chunks at ~0.85 and reserved only 3 own-seat
// rows of 12, so a seat's own short fact never reached think(). Both routines now reserve the seat's best k own rows,
// for an audience named internal or founder only; for any other audience (customer, supplier, visitor, none) they never
// return a seat-pack row tagged audience:internal (scripts/kb/verified_packs.mjs isOwnEntry) or kind:company, and
// reserve nothing. Release-operator blocker of 19 Oct: the first version reserved own rows with no audience at all.
// The effect is measured by seat_qualification_exam.mjs --with-sql --audience internal|customer.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { isOwnEntry } from '../kb/verified_packs.mjs';

const FILE = 'scripts/sql/a_seats_own_pack_fills_half_of_every_retrieval.sql';
const src = readFileSync(new URL('../../' + FILE, import.meta.url), 'utf8');
const body = (name) => { const i = src.indexOf(`FUNCTION public.${name}(`); return src.slice(i, src.indexOf('end $fn$;', i)); };
const AUD = /v_internal constant boolean := lower\(btrim\(coalesce\(p_audience, ''\)\)\) in \('internal', 'founder'\);/;
const SEAT_TABLES = ['sales_knowledge', 'accountant_knowledge', 'it_engineer_knowledge', 'support_knowledge', 'ceo_knowledge', 'marketing_knowledge'];
const GUARD = "and (v_internal or not (s.tags && array['audience:internal', 'kind:company'] or exists (select 1 from unnest(s.source_ids) x where x like 'internal:founder_instruction/%' or x like 'internal:memory/%')))";

test('both routines take p_audience last, default NULL, and the old signatures are dropped and revoked anew', () => {
  for (const [fn, oldSig, newSig] of [
    ['fn_reason_retrieve', 'text, vector, integer, text, text, text', 'text, vector, integer, text, text, text, text'],
    ['fn_reason_retrieve_ml', 'text, vector, vector, integer, integer, text, text, text', 'text, vector, vector, integer, integer, text, text, text, text']]) {
    assert.ok(src.includes(`DROP FUNCTION IF EXISTS public.${fn}(${oldSig});`), fn + ': old overload dropped');
    assert.match(src, new RegExp(String.raw`CREATE FUNCTION public\.${fn}\([^)]*p_area text DEFAULT NULL::text, p_audience text DEFAULT NULL::text\)`), fn);
    assert.ok(src.includes(`revoke execute on function public.${fn}(${newSig}) from public, anon, authenticated;`), fn + ': revoke on the new signature');
    assert.match(body(fn), AUD, fn + ': a missing or unknown audience is external');
  }
});

test('an external audience never reads an internal seat-pack row; an internal one reads it', () => {
  // every seat-table branch carries the guard: once in fn_reason_retrieve, twice (both spaces) in fn_reason_retrieve_ml
  for (const [fn, per] of [['fn_reason_retrieve', 1], ['fn_reason_retrieve_ml', 2]]) {
    const b = body(fn);
    for (const t of SEAT_TABLES) {
      const branches = b.split(/union(?: all)?/).filter((x) => new RegExp(String.raw`from public\.(knowledge_vector_ml v join public\.)?${t} s\b`).test(x));
      assert.equal(branches.length, per, `${fn} ${t}: branches`);
      for (const x of branches) assert.ok(x.includes(GUARD), `${fn} ${t}: a branch without the audience guard`);
    }
    // the generic corpus branches (aliases c and f) carry no guard: only seat packs hold the company's own facts
    for (const t of ['kb_chunks c ', 'company_faq f ']) assert.ok(!b.split(/union(?: all)?/).some((x) => x.includes('from public.' + t) && x.includes(GUARD)), t + 'is not a seat pack');
  }
});

test('the own-row reservation is for an internal audience only, and at least k of the k * 2', () => {
  assert.match(body('fn_reason_retrieve_ml'), /own\s+integer := case when lower\(btrim\(coalesce\(p_audience, ''\)\)\) in \('internal', 'founder'\) then least\(greatest\(coalesce\(p_own, 3\), k\), 2 \* k\) else 0 end;/);
  assert.match(body('fn_reason_retrieve_ml'), /select \* from hits where mine order by score desc limit own/);
  assert.match(body('fn_reason_retrieve'), /v_internal and h\.mine and row_number\(\) over \(partition by h\.mine order by h\.sim desc\) <= k reserved/);
});

test('the two internal exams name their audience', () => {
  assert.match(src, /fn_reason_retrieve\(e\.seat, e\.q_vec, 6, p_audience => 'internal'\)/);
  assert.match(src, /fn_reason_retrieve_ml\(q\.seat, q\.embedding_ml, case when q\.lang = 'ar' then null else q\.embedding end, 6, p_audience => 'internal'\)/);
});

test('the internal tag is data: a seat pack\'s company or internal-sourced entry, never a trade pack', () => {
  assert.ok(isOwnEntry({ kind: 'company', sources: [] }));
  assert.ok(isOwnEntry({ kind: 'decision_rule', sources: ['internal:founder_instruction/1086'] }));
  assert.ok(!isOwnEntry({ kind: 'law', sources: ['https://uaelegislation.gov.ae/x'] }));
});

test('the file waits for merge with a note, or is in MANIFEST, never both', () => {
  const pending = existsSync(new URL('../../scripts/sql/pending/a_seats_own_pack_fills_half_of_every_retrieval.txt', import.meta.url));
  const listed = readFileSync(new URL('../../scripts/sql/MANIFEST.txt', import.meta.url), 'utf8').split(/\r?\n/).some((l) => l.endsWith(FILE));
  assert.ok(pending !== listed);
});
