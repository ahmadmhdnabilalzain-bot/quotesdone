// THE PLAIN-LANGUAGE SCORE IS THE SAME IN SQL AND IN TYPESCRIPT (customer_support, 27 Oct 2026; founder ledger 1013 item 7).
//
// Replies are scored by checkReadability() in supabase/functions/_shared/readability.ts. Notices -- the templated
// messages routines write into public.notifications -- are scored by its SQL twin, fn_plain_language_score, in
// customer_support_scores_every_notice_a_customer_or_supplier_reads_for_plain_language.sql. Measured 27 Oct 2026: 378
// notices reached customers and suppliers in 30 days and none was scored.
//
// Two scorers drift apart unless something fails when they do. This fails when:
//   * a limit, a jargon word (English or Arabic) or an accepted acronym differs between the two files;
//   * the TypeScript gives a different verdict, score, tone or issue list than the SQL gave, on production, for the
//     recorded corpus (the .fixture.json beside this file: 24 cases, English and Arabic, run 27 Oct 2026 inside a
//     rolled-back transaction, 24/24 identical);
//   * the duty, its tables' RLS policy or the definer's revoke disappear.
//
//   node --test scripts/checks/the_plain_language_score_is_the_same_in_sql_and_typescript.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const TS_PATH = join(REPO, 'supabase/functions/_shared/readability.ts');
const ts = readFileSync(TS_PATH, 'utf8');
const sql = readFileSync(join(REPO, 'scripts/sql/customer_support_scores_every_notice_a_customer_or_supplier_reads_for_plain_language.sql'), 'utf8');
const fixture = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), 'the_plain_language_score_is_the_same_in_sql_and_typescript.fixture.json'), 'utf8'));

const tsConst = (name) => Number(ts.match(new RegExp(`export const ${name} = (\\d+);`))?.[1]);
const sqlConst = (name) => Number(sql.match(new RegExp(`constant int := (\\d+);\\s+-- ${name}`))?.[1]);
const quoted = (s) => [...s.matchAll(/'([^']*)'/g)].map((m) => m[1]);
const tsList = (re) => quoted(ts.match(re)?.[1] ?? '');
const sqlArray = (name) => quoted(sql.match(new RegExp(`${name} constant text\\[\\] := array\\[([\\s\\S]*?)\\];`))?.[1] ?? '');

test('the limits are the same', () => {
  for (const k of ['MAX_SENTENCE_WORDS', 'MAX_AVG_SENTENCE_WORDS', 'MIN_SENTENCES_FOR_AVERAGE']) {
    assert.ok(Number.isInteger(tsConst(k)), `${k} not found in readability.ts`);
    assert.equal(sqlConst(k), tsConst(k), `${k}: SQL ${sqlConst(k)} vs TypeScript ${tsConst(k)}`);
  }
});

test('the jargon lists and the accepted acronyms are the same', () => {
  const en = tsList(/const JARGON_EN = \[([\s\S]*?)\];/);
  const ar = tsList(/const JARGON_AR = \[([\s\S]*?)\];/);
  const acr = tsList(/const ACRONYMS = new Set\(\[([\s\S]*?)\]\)/);
  assert.ok(en.length > 20 && ar.length > 3 && acr.length > 5, 'a list could not be read from readability.ts');
  assert.deepEqual(sqlArray('c_jargon_en'), en);
  assert.deepEqual(sqlArray('c_jargon_ar'), ar);
  assert.deepEqual(sqlArray('c_acronyms'), acr);
});

test('the TypeScript gives what the SQL gave on production for every recorded case', async () => {
  const { checkReadability } = await import(pathToFileURL(TS_PATH).href);
  assert.ok(fixture.cases.length >= 20);
  const diff = [];
  fixture.cases.forEach((c, i) => {
    const r = checkReadability(c.text, c.lang);
    const got = { ok: r.ok, score: r.score, tone: r.tone, issues: r.issues };
    if (JSON.stringify(got) !== JSON.stringify(c.sql)) diff.push(`#${i} ${c.lang} ${JSON.stringify(c.text).slice(0, 60)}: ts ${JSON.stringify(got)} sql ${JSON.stringify(c.sql)}`);
  });
  assert.deepEqual(diff, [], 'the two scorers part: change the SQL to match, re-run the probe and re-record the fixture');
  // the corpus must exercise every rule, or agreement proves little
  const issues = fixture.cases.flatMap((c) => c.sql.issues.map((i) => i.split(':')[0]));
  for (const k of ['long_sentence', 'long_average', 'jargon', 'wrong_language']) assert.ok(issues.includes(k), `no recorded case fails on ${k}`);
  assert.ok(fixture.cases.some((c) => c.sql.tone < 100), 'no recorded case loses tone points');
  assert.ok(fixture.cases.some((c) => c.lang === 'ar' && c.sql.ok), 'no passing Arabic case');
});

test('the duty is registered, the tables are service-role only and the definers are revoked', () => {
  assert.match(sql, /\('customer_support\.notice_plain_language', 'customer_support', interval '1 day', 'fn_customer_support_notice_plain_language'/);
  for (const t of ['notice_plain_language', 'notice_plain_language_cause']) {
    assert.ok(sql.includes(`alter table public.${t} enable row level security;`), `${t}: RLS`);
    assert.match(sql, new RegExp(`create policy ${t}_service_role_only on public\\.${t}`), `${t}: no policy`);
    assert.ok(sql.includes(`revoke all on public.${t} from anon, authenticated;`), `${t}: not revoked`);
  }
  for (const sig of ['fn_plain_language_score(text, text)', 'fn_customer_support_notice_plain_language()']) {
    assert.ok(sql.includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), `${sig} not revoked`);
  }
  // a supplier is always written to in English (founder, 28 Sep 2026)
  assert.match(sql, /when n\.to_role = 'supplier' then 'en'/);
  // the originator closes: the cause is closed by customer_support, and the handoff through the citing closer
  assert.match(sql, /set_config\('qd\.handoff_closer', 'customer_support', true\);\s+perform public\.fn_seat_handoff_complete\(/);
});
