// The marketing seat's article gate (marketing, 22 Sep 2026). No network, no file permissions: the article and
// its sources are imported as JSON.
//   deno test supabase/functions/_shared/marketing_articles.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { acceptArticle, acceptReview, articlePost, checkArticle, CRITERIA, reviewPrompt, type Article, type ArticleBody } from './marketing_articles.ts';
import FIRST from '../../../scripts/marketing/articles/how-quotesdone-works-for-procurement-teams.json' with { type: 'json' };
import SITE_CONTENT from '../../../src/content/marketing.json' with { type: 'json' };

// deno-lint-ignore no-explicit-any
const faq = (SITE_CONTENT as any).faq;
const withSources = (a: Omit<Article, 'sources'>): Article => ({ ...a, sources: [{ ref: 'faq.en', text: faq.en.html }, { ref: 'faq.ar', text: faq.ar.html }] });

Deno.test('the first article passes the gate it will be ingested through', () => {
  const c = checkArticle(withSources(FIRST as unknown as Article));
  assertEquals(c.lint, []);
  assertEquals(c.ungrounded, []);
  assertEquals(c.post.lint, []);
});

// A market article (founder 1058): the heading fields about the buyer's task, never the company; the FAQ stands in
// for the topic's market sources here.
const market = (): ArticleBody => {
  const a = structuredClone({ en: (FIRST as unknown as Article).en, ar: (FIRST as unknown as Article).ar });
  a.en.title = 'Comparing supplier quotes for a fit-out package in the UAE';
  a.en.meta_desc = 'What a UAE procurement team should check before comparing supplier quotes for a fit-out package.';
  a.ar.title = 'مقارنة عروض أسعار الموردين لحزمة تشطيبات في الإمارات';
  a.ar.meta_desc = 'ما الذي يراجعه فريق المشتريات في الإمارات قبل مقارنة عروض أسعار الموردين لحزمة تشطيبات.';
  return a;
};
const SOURCES = [{ ref: 'faq.en', text: faq.en.html }, { ref: 'faq.ar', text: faq.ar.html }];

Deno.test('a market draft is stored only through the gate: grounded, whole, not about QuotesDone', () => {
  const ok = acceptArticle({ sources: SOURCES, prior: null, failed: [] }, 'Here it is: ' + JSON.stringify(market()), false);
  assert(ok.ok, JSON.stringify(ok));
  assertEquals(ok.ok && ok.slug, 'comparing-supplier-quotes-for-a-fit-out-package-in-the-uae');
  const invented = market(); invented.en.excerpt += ' Buyers save 47% on average.';
  const r = acceptArticle({ sources: SOURCES, prior: null, failed: [] }, JSON.stringify(invented), false);
  assert(!r.ok && r.reason.includes('47'), JSON.stringify(r));
  const aboutUs = acceptArticle({ sources: SOURCES, prior: null, failed: [] }, JSON.stringify({ en: FIRST.en, ar: FIRST.ar }), false);
  assert(!aboutUs.ok && aboutUs.reason.includes('QuotesDone'), JSON.stringify(aboutUs));
  assertEquals(acceptArticle({ sources: SOURCES, prior: null, failed: [] }, JSON.stringify(market()), true), { ok: false, reason: 'the answer was cut off' });
});

Deno.test('a revision answers every failed reason, and is not the version reviewed', () => {
  const prior = market();
  const next = market(); next.en.excerpt += ' Check that every quote prices the same scope.';
  const o = { sources: SOURCES, prior, failed: ['seo_geo', 'useful'] as const, slug: 'comparing-supplier-quotes-for-a-fit-out-package-in-the-uae' };
  const half = acceptArticle({ ...o, failed: [...o.failed] }, JSON.stringify({ ...next, changes: [{ criterion: 'seo_geo', change: 'The title now carries the search term.' }] }), false);
  assert(!half.ok && half.reason.includes('useful'), JSON.stringify(half));
  const same = acceptArticle({ ...o, failed: [] }, JSON.stringify(prior), false);
  assertEquals(same, { ok: false, reason: 'the revision is identical to the version reviewed' });
  const whole = acceptArticle({ ...o, failed: [...o.failed] }, JSON.stringify({ ...next, changes: [
    { criterion: 'seo_geo', change: 'The title now carries the search term.' },
    { criterion: 'useful', change: 'Added what to check in each quote before comparing.' }] }), false);
  assert(whole.ok && whole.changes.length === 2, JSON.stringify(whole));
});

Deno.test('the CEO decision carries six reasons; approve only when all pass; no fifth revise', () => {
  const reasons = (fail: string[] = []) => Object.fromEntries(Object.keys(CRITERIA).map((k) =>
    [k, { verdict: fail.includes(k) ? 'fail' : 'pass', reason: 'The article earns this: a full sentence of reason.' }]));
  assert(acceptReview(JSON.stringify({ decision: 'approve', reasons: reasons() }), false, true).ok);
  assertEquals(acceptReview(JSON.stringify({ decision: 'approve' }), false, true), { ok: false, reason: 'the reason for useful is missing or too short' });
  assertEquals(acceptReview(JSON.stringify({ decision: 'approve', reasons: reasons(['seo_geo']) }), false, true), { ok: false, reason: 'approve with a failed criterion' });
  assert(acceptReview(JSON.stringify({ decision: 'revise', reasons: reasons(['seo_geo']) }), false, true).ok);
  assert(!acceptReview(JSON.stringify({ decision: 'revise', reasons: reasons(['seo_geo']) }), false, false).ok);
  assert(acceptReview(JSON.stringify({ decision: 'replace_topic', reasons: reasons(['useful']) }), false, false).ok);
  const p = reviewPrompt({ round_id: 1, slug: 's-x', round: 5, version: market(), drafted_by_model: null, changes: null,
    topic: { title: 't', kind: 'search', evidence: [], sources: [] }, history: [], revise_rounds: 4 });
  assert(p.includes('decide "approve" or "replace_topic" only') && !p.includes('"revise" (at least'));
});

Deno.test('an invented figure, a machine phrase or a missing Arabic paragraph is refused', () => {
  const a = structuredClone(FIRST) as unknown as Article;
  a.en.body_html += '<p>Teams save 40% on average.</p>';
  let c = checkArticle(withSources(a));
  assert(c.ungrounded.includes('40'), JSON.stringify(c.ungrounded));
  assert(c.lint.some((x) => x.rule === 'structure_differs'));
  const b = structuredClone(FIRST) as unknown as Article;
  b.en.excerpt = 'Let us delve into a seamless way to buy.';
  c = checkArticle(withSources(b));
  assert(c.lint.some((x) => x.field === 'en.excerpt' && x.rule === 'ai_tell.en'));
});

Deno.test('the LinkedIn post links the article in each language', () => {
  const p = articlePost({ slug: 'x-y', title_en: 'T', excerpt_en: 'E', title_ar: 'عنوان', excerpt_ar: 'مقدمة' });
  assert(p.text_en.endsWith('https://quotesdone.ae/blog/x-y'));
  assert(p.text_ar.endsWith('https://quotesdone.ae/ar/blog/x-y'));
});
