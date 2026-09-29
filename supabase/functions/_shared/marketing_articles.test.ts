// The marketing seat's article gate (marketing, 22 Sep 2026). No network, no file permissions: the article and
// its sources are imported as JSON.
//   deno test supabase/functions/_shared/marketing_articles.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { articlePost, checkArticle, type Article } from './marketing_articles.ts';
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
