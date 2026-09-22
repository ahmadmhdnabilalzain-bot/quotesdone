// THE MARKETING SEAT'S ARTICLE GATE (marketing, 22 Sep 2026; founder instruction 722).
//
// An article about QuotesDone (how it works, a buyer guide, a trade explainer) is written by the founder and
// Claude, grounded ONLY in company knowledge, and ingested through marketing_outreach action ingest_article.
// checkArticle is what that ingest runs: every field in both languages through lintDraft, every number in the
// article against the text of the sources it cites (ungroundedNumbers), and the same structure in English
// and Arabic (headings, paragraphs, list items), which scripts/checks/blog_index_matches_data.mjs also
// requires once the article is baked into src/content/blog.json. articlePost is the LinkedIn post that
// announces it, drafted into #834's marketing_post at ingest.
//   Tested by supabase/functions/_shared/marketing_articles.test.ts.
import { lintDraft, ungroundedNumbers, type Finding } from './marketing_style.ts';
import { SITE } from './marketing_outreach.ts';
export const FIELDS = ['title', 'excerpt', 'meta_desc', 'category', 'body_html'] as const;
type Body = Record<(typeof FIELDS)[number], string>;
export type Article = { slug: string; en: Body; ar: Body; sources: Array<{ ref: string; text: string }> };

export function articlePost(a: { slug: string; title_en: string; excerpt_en: string; title_ar: string; excerpt_ar: string }) {
  const en = `${a.title_en}\n\n${a.excerpt_en}\n\n${SITE}/blog/${a.slug}`;
  const ar = `${a.title_ar}\n\n${a.excerpt_ar}\n\n${SITE}/ar/blog/${a.slug}`;
  return { text_en: en, text_ar: ar, lint: [...lintDraft(en, 'post'), ...lintDraft(ar, 'post')] };
}

const TAGS = ['h2', 'h3', 'p', 'li', 'tr', 'td', 'th', 'table'];
const count = (html: string, t: string) => (String(html || '').match(new RegExp('<' + t + '[\\s>]', 'g')) || []).length;

export function checkArticle(a: Article) {
  const lint: Array<Finding & { field: string }> = [];
  for (const lang of ['en', 'ar'] as const) for (const f of FIELDS) {
    for (const x of lintDraft(String(a?.[lang]?.[f] || ''), f === 'body_html' ? 'article' : 'post')) lint.push({ ...x, field: `${lang}.${f}` });
  }
  const post = articlePost({ slug: a.slug, title_en: a.en?.title, excerpt_en: a.en?.excerpt, title_ar: a.ar?.title, excerpt_ar: a.ar?.excerpt });
  for (const x of post.lint) lint.push({ ...x, field: 'linkedin_post' });
  for (const t of TAGS) {
    const e = count(a.en?.body_html, t), r = count(a.ar?.body_html, t);
    if (e !== r) lint.push({ rule: 'structure_differs', match: `<${t}> ${e} in English, ${r} in Arabic`, field: 'body_html' });
  }
  const all = FIELDS.flatMap((f) => [a.en?.[f], a.ar?.[f]]).join('\n');
  const ungrounded = ungroundedNumbers(all, (a.sources || []).map((s) => String(s.text || '')));
  return { lint, ungrounded, post };
}
