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

// ── HIS CHANGE TO A DRAFT (marketing, 29 Sep 2026; review of #1039) ─────────────────────────────────────────────
// The model redraws the draft with his words; code decides whether the redraw may be written. The gate is the one
// every article passes (checkArticle), with the draft itself and his change as the only sources: a redraw can move,
// cut or reword, but it cannot bring a number that is in neither.
export type ArticleBody = { en: Body; ar: Body };
export interface ReviseDue { slug: string; change: string; earlier_changes: string[]; article: ArticleBody }

export function revisePrompt(d: ReviseDue): string {
  return [
    'You are revising a QuotesDone blog article, in English and Arabic, exactly as the founder asked.',
    'His change: ' + d.change,
    d.earlier_changes.length ? 'Changes he asked for before (keep them): ' + d.earlier_changes.join(' | ') : '',
    'Rules: keep the same HTML structure in both languages (the same number of h2, h3, p, li and table tags in English and Arabic);',
    'add no fact, figure or claim that is not already in the article or in his words; plain professional English and Modern Standard Arabic.',
    'Answer with ONLY a JSON object {"en":{"title","excerpt","meta_desc","category","body_html"},"ar":{same keys}} and nothing else.',
    'The article: ' + JSON.stringify(d.article),
  ].filter(Boolean).join('\n');
}

/** The redraw, or why it may not be written. Never throws. */
export function acceptRevision(d: ReviseDue, answer: string | null, truncated: boolean):
  { ok: true; article: ArticleBody; post: { text_en: string; text_ar: string } } | { ok: false; reason: string } {
  if (!answer) return { ok: false, reason: 'no answer' };
  if (truncated) return { ok: false, reason: 'the answer was cut off' };
  let j: ArticleBody;
  try {
    j = JSON.parse(answer.slice(answer.indexOf('{'), answer.lastIndexOf('}') + 1));
  } catch { return { ok: false, reason: 'the answer is not the article JSON' }; }
  for (const lang of ['en', 'ar'] as const) for (const f of FIELDS) {
    if (typeof j?.[lang]?.[f] !== 'string' || !j[lang][f].trim()) return { ok: false, reason: `${lang}.${f} is missing` };
  }
  if (FIELDS.every((f) => j.en[f] === d.article.en[f] && j.ar[f] === d.article.ar[f])) return { ok: false, reason: 'the redraw is identical to the draft' };
  const draftText = FIELDS.flatMap((f) => [d.article.en[f], d.article.ar[f]]).join('\n');
  const c = checkArticle({ slug: d.slug, en: j.en, ar: j.ar, sources: [{ ref: 'draft', text: draftText }, { ref: 'founder', text: d.change }] });
  if (c.lint.length) return { ok: false, reason: 'lint: ' + c.lint.slice(0, 5).map((x) => `${x.field} ${x.rule} ${x.match}`).join('; ') };
  if (c.ungrounded.length) return { ok: false, reason: 'numbers in neither the draft nor his words: ' + c.ungrounded.join(', ') };
  return { ok: true, article: { en: j.en, ar: j.ar }, post: { text_en: c.post.text_en, text_ar: c.post.text_ar } };
}
