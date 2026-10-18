// AN ARABIC QUESTION IS RANKED IN THE SPACE THAT READS ARABIC (6 Oct 2026, it_engineer with sales_engineer).
//
// Measured: fn_reason_retrieve_ml read Arabic market questions at recall@5 0.672 (134 of 412 pairs at 0) because
// (1) every Arabic pack row was embedded under an ENGLISH title, (2) optional Arabic marks reached the model, and
// (3) the fusion gave English-only gte-small a say on Arabic questions. Staged with all three fixed: 0.973 / 10 pairs.
// See scripts/sql/an_arabic_question_is_ranked_in_the_space_that_reads_arabic.sql.
//
// WHAT FAILS IF A CAUSE RETURNS (offline, no token):
//   * a market entry whose pack has label_ar but no Arabic topic_ar, or a loader that titles the Arabic row in English;
//   * a recipe that lets a mark through on either side, or a caller that prefixes a text by hand around the recipe;
//   * think() sending a gte vector for an Arabic question, or the daily exam doing so;
//   * the SQL file losing its re-embed of marked rows, or carrying both / neither of a pending note and a MANIFEST line.
//
//   node --test scripts/checks/an_arabic_question_is_ranked_in_the_space_that_reads_arabic.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readPacks, rowsOf } from '../kb/verified_packs.mjs';
import { mlClean, mlQueryText, mlRowText, gteReads, ML_QUERY_PREFIX, ML_PASSAGE_PREFIX } from '../kb/ml_embed_recipe.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const AR = /[؀-ۿ]/;
const FILE = 'scripts/sql/an_arabic_question_is_ranked_in_the_space_that_reads_arabic.sql';
const NOTE = 'scripts/sql/pending/an_arabic_question_is_ranked_in_the_space_that_reads_arabic.txt';

test('every market entry is titled in Arabic on its Arabic row, and in English on its English row', () => {
  const packs = readPacks(join(REPO, 'knowledge')).filter((p) => p.kind === 'trade' && p.pack.label_ar);
  assert.ok(packs.length >= 200, `only ${packs.length} market packs`);
  const missing = [];
  for (const p of packs) {
    for (const e of p.pack.entries.filter((x) => /:uae-market-(products|brands|sizes)$/.test(x.id))) {
      if (!(typeof e.topic_ar === 'string' && AR.test(e.topic_ar))) missing.push(e.id);
    }
    for (const r of rowsOf(p)) {
      const e = p.pack.entries.find((x) => x.id === r.entry_id);
      assert.equal(r.cols.title, r.lang === 'ar' && e.topic_ar ? e.topic_ar : e.topic, r.record_id);
      assert.ok(r.text.startsWith(r.cols.title + '\n'), `${r.record_id}: embedded text does not start with its title`);
    }
  }
  assert.deepEqual(missing, []);
});

test('the recipe takes the optional Arabic marks out on both sides and nothing else', () => {
  const marked = 'يُسعَّر الإسمـنت';
  assert.equal(mlClean(marked), 'يسعر الإسمنت');
  assert.equal(mlClean('CEM I 42.5N أ إ آ ى ة'), 'CEM I 42.5N أ إ آ ى ة', 'letters are not folded (folding measured worse)');
  assert.equal(mlQueryText('  ' + marked + '  '), ML_QUERY_PREFIX + 'يسعر الإسمنت');
  assert.equal(mlRowText('sales_knowledge', 'عنوانٌ', marked), ML_PASSAGE_PREFIX + 'عنوان\nيسعر الإسمنت');
  assert.equal(mlRowText('seat_case_memory', null, marked), ML_QUERY_PREFIX + 'يسعر الإسمنت');
  for (const f of ['supabase/functions/_shared/ml_embed.ts', 'scripts/kb/run_ml_embed_backfill.mjs', 'scripts/eval/multilingual_recall_eval.mjs']) {
    assert.doesNotMatch(read(f), /ML_(QUERY|PASSAGE)_PREFIX\s*\+/, `${f} prefixes a text by hand around the recipe`);
  }
  assert.match(read('supabase/functions/_shared/ml_embed.ts'), /embedRaw\(\[mlQueryText\(/);
});

test('gte-small is not asked about an Arabic question, in think() or in the daily exam', () => {
  assert.equal(gteReads('كيف يُباع الإسمنت وحديد التسليح في الإمارات؟'), false);
  assert.equal(gteReads('ما معدات شحن CCS2 وType 2 في الإمارات؟'), false);
  assert.equal(gteReads('How is rebar priced in the UAE?'), true);
  assert.equal(gteReads('Price of OPC cement in Dubai - إسمنت'), true);
  assert.match(read('supabase/functions/_shared/think.ts'), /const vg = rt === ROUTINES\.ml && gteReads\(s\.query\) \?/);
  assert.match(read(FILE), /fn_reason_retrieve_ml\(q\.seat, q\.embedding_ml, case when q\.lang = 'ar' then null else q\.embedding end, 6\)/);
});

test('the SQL file re-embeds every marked row and replays safely', () => {
  const sql = read(FILE).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
  assert.doesNotMatch(sql, /^\s*(begin|commit)\s*;/im);
  assert.match(sql, /delete from public\.knowledge_vector_ml v\s+using public\.v_knowledge_ml_source s/);
  assert.match(sql, /update public\.seat_knowledge_eval_question set embedding_ml = null/);
  const inManifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(FILE);
  assert.ok(existsSync(join(REPO, NOTE)) !== inManifest, 'exactly one of a pending note and a MANIFEST line');
});
