// A SEAT'S OWN ENTRY REACHES THE ANSWER WHOLE (ceo, ledger 1003 stage 2, 19 Oct 2026). Measured on the real-model seat
// exam: in 39 failed items the expected pack entry was retrieved but the fact sat past the 1,200th character of its
// excerpt. Both retrieval routines now give a seat-pack row 2,400 characters (every other source keeps 1,200), and
// think.ts no longer cuts it back to 1,200. Fails if either side returns to the old cut, or the change reaches beyond
// the excerpt (the audience guard and the reservation stay byte-identical to the file it is stacked on).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { sharedModuleSource } from '../lib/function_sources.mjs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const now = read('scripts/sql/a_seats_own_entry_reaches_the_answer_whole.sql');
const was = read('scripts/sql/a_seats_own_pack_fills_half_of_every_retrieval.sql');
const think = sharedModuleSource('think');
const SEAT_TABLES = ['sales_knowledge', 'accountant_knowledge', 'it_engineer_knowledge', 'marketing_knowledge', 'ceo_knowledge', 'support_knowledge'];
const body = (src, fn) => { const i = src.search(new RegExp(String.raw`FUNCTION public\.${fn}\(`)); return src.slice(i, src.indexOf('end $fn$;', i)); };

test('every seat-pack branch of both routines returns 2,400 characters; the shared corpora keep 1,200', () => {
  for (const fn of ['fn_reason_retrieve', 'fn_reason_retrieve_ml']) {
    const b = body(now, fn);
    for (const t of SEAT_TABLES) assert.match(b, new RegExp(String.raw`\(select '${t}', s\.record_id, s\.title, left\(s\.(content|body), 2400\)`), `${fn}: ${t}`);
    for (const t of ['kb_chunks', 'ops_knowledge', 'agent_knowledge', 'company_faq']) assert.match(b, new RegExp(String.raw`'${t}'[^\n]*left\([a-z.]+, 1200\)`), `${fn}: ${t} unchanged`);
  }
});

test('nothing but the excerpt changed: same signatures (CREATE OR REPLACE keeps the ACL), same body otherwise', () => {
  for (const fn of ['fn_reason_retrieve', 'fn_reason_retrieve_ml']) {
    assert.match(now, new RegExp(String.raw`CREATE OR REPLACE FUNCTION public\.${fn}\(`), fn);
    assert.equal(body(now, fn).replaceAll(', 2400)', ', 1200)').replace(/^FUNCTION/, ''), body(was, fn).replace(/^FUNCTION/, ''), fn + ' differs beyond the excerpt');
  }
  assert.doesNotMatch(now, /^DROP FUNCTION/m);
});

test('think.ts keeps what the routine returns', () => {
  assert.match(think, /export const EXCERPT_MAX = 2400;/);
  assert.match(think, /excerpt: String\(r\.excerpt \?\? ''\)\.slice\(0, EXCERPT_MAX\)/);
});
