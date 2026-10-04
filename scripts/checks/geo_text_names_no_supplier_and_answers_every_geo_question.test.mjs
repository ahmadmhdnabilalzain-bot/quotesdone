// THE GEO TEXT NAMES NO SUPPLIER AND ANSWERS EVERY GEO QUESTION (5 Oct 2026, marketing; backlog T5).
//
// MEASURED before this: the site served Organization and FAQPage JSON-LD and robots allowed every crawler, but there
// was no /llms.txt and no HowTo on /how-it-works; marketing_geo_question held 18 questions (12 active) mapped to nothing.
//
// Prevented by: this check. WHAT FAILS IF THE CAUSE RETURNS
//   * static: /llms.txt stops serving src/content/geo.json; /how-it-works loses its HowTo; the GEO text names
//     machine intelligence, carries a licence number, or turns non-English; it states a fee the site does not
//     (3% reveal, free posting, no commission, AED 1,000 after the first 1,000); a question maps to a section the
//     text does not have.
//   * production (token present): a geo question exists that the map does not answer, or fn_supplier_named_in
//     (the #1164 name rule) finds a supplier's name in the llms text or the how-it-works steps.
//
//   node --test scripts/checks/geo_text_names_no_supplier_and_answers_every_geo_question.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const geo = JSON.parse(read('src/content/geo.json'));
const llms = geo.llms.join('\n');
const steps = JSON.parse(read('messages/en.json')).howPage.steps.map((s) => `${s.title}. ${s.body}`).join('\n');

test('static: served, structured, English, no forbidden words, fees as the site states them', () => {
  assert.match(read('src/app/llms.txt/route.ts'), /geo\.llms\.join/);
  assert.match(read('src/app/[locale]/how-it-works/page.tsx'), /howToLd\(/);
  assert.match(read('src/lib/seo.ts'), /'@type': 'HowTo'/);
  for (const t of [llms, steps]) {
    assert.doesNotMatch(t, /\bAI\b|artificial intelligence/i, 'never say AI');
    assert.doesNotMatch(t, /[؀-ۿ]/, 'English only');
    assert.doesNotMatch(t, /licen[cs]e (no|number)|\b\d{6,}\b/i, 'no licence number');
  }
  for (const fact of ['3% of the one quote', 'Posting and comparing are free', 'no commission', 'AED 1,000', 'except food & beverage', 'Dubai and Abu Dhabi'])
    assert.ok(llms.includes(fact), 'missing: ' + fact);
});

test('static: every mapped question points at a section the text has', () => {
  const sections = new Set(['intro', ...geo.llms.filter((l) => l.startsWith('## ')).map((l) => l.slice(3))]);
  assert.equal(Object.keys(geo.answers).length, 18);
  for (const [id, refs] of Object.entries(geo.answers))
    assert.ok(refs.some((r) => sections.has(r)), `question ${id} maps to no section`);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production: every geo question is mapped, and the #1164 rule finds no supplier name', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql, lit } = await import('../lib/db.mjs');
  const rows = await sql(`select (select coalesce(json_agg(id order by id), '[]') from public.marketing_geo_question) as ids,
    public.fn_supplier_named_in(${lit(llms)}) as llms_hit, public.fn_supplier_named_in(${lit(steps)}) as steps_hit`);
  const r = rows[0];
  const ids = typeof r.ids === 'string' ? JSON.parse(r.ids) : r.ids;
  for (const id of ids) assert.ok(geo.answers[String(id)], `geo question ${id} is not answered by the map`);
  assert.equal(r.llms_hit, null, 'llms.txt names a supplier');
  assert.equal(r.steps_hit, null, 'how-it-works names a supplier');
});
