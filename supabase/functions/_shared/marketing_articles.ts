// THE MARKETING SEAT'S ARTICLE GATE (marketing, 22 Sep 2026; founder instruction 722).
//
// Since 29 Sep 2026 (founder 1058) a blog is a MARKET topic, never about QuotesDone: see the section at the end.
// The gate below is unchanged and is what every market article passes too.
// An article about QuotesDone (how it works, a buyer guide, a trade explainer) was written by the founder and
// Claude, grounded ONLY in company knowledge, and ingested through marketing_outreach action ingest_article (that
// action and the approve_article action were removed on 29 Sep 2026; those four drafts are withdrawn). Today
// checkArticle runs inside acceptArticle, on every market draft and revision (the section at the end).
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

// ── A BLOG IS A MARKET TOPIC THE CEO SEAT REVIEWS (29 Sep 2026; founder 1058, 1059) ──────────────────────────────
// scripts/sql/a_blog_article_is_a_market_topic_the_ceo_reviews_until_it_is_useful.sql is the pipe. Here: the three
// prompts (draft, CEO review, revision) and the code gates their answers pass. The model writes and judges; code
// decides whether what it wrote may be stored. A market article is grounded in its topic's MARKET sources (the
// search or news item, the trade's verified knowledge): checkArticle refuses any number that is not in them.
export type ArticleBody = { en: Body; ar: Body };
export interface MarketSource { ref: string; url?: string | null; title?: string | null; text?: string | null }
export interface Lesson { criterion?: string; reason?: string; round?: number }
export interface DraftTopic { topic_id: number; kind: string; title: string; trade: string | null; evidence: unknown[]; sources: MarketSource[]; lessons: Lesson[] }
export interface ReviewReason { verdict: 'pass' | 'fail'; reason: string }
export type Reasons = Record<Criterion, ReviewReason>;
export interface ReviseRound { article_id: number; topic_id: number; slug: string; round: number; version: ArticleBody; reasons: Reasons; sources: MarketSource[]; history: unknown[] }
export interface ReviewRound { round_id: number; slug: string; round: number; version: ArticleBody; drafted_by_model: string | null; changes: unknown; topic: { title: string; kind: string; evidence: unknown[]; sources: MarketSource[] }; history: unknown[]; revise_rounds: number }

// The CEO's rubric (1059). The same six keys are enforced by fn_marketing_review_reasons_ok in the database.
export const CRITERIA = {
  useful: 'useful to UAE buyers, contractors and suppliers of construction, fit-out, MEP and building materials',
  market_topic_not_quotesdone: 'about the trending market topic, not about QuotesDone',
  accurate_grounded: 'every fact and number is in the cited market sources; nothing invented',
  no_supplier_named: 'names no supplier, contractor, manufacturer or brand',
  language_quality: 'clear professional English and natural Modern Standard Arabic that say the same thing',
  seo_geo: 'a searchable title, an excerpt that answers the question, headings phrased as the questions people ask; quotable by search and answer engines',
} as const;
export type Criterion = keyof typeof CRITERIA;
export const MAX_REVISE_ROUNDS = 4;
const SHAPE = '{"en":{"title","excerpt","meta_desc","category","body_html"},"ar":{same keys}}';
const WRITING = [
  'Write for a UAE buyer or contractor: what the topic means for them, what to check, what to specify, what to ask a supplier for.',
  'It is NOT about our company: never mention QuotesDone or any marketplace or platform. Never name a supplier, contractor, manufacturer or brand.',
  'Every fact and every number comes from the sources below and nowhere else; link the source you use in the body (<a href="url">title</a>).',
  'English and Modern Standard Arabic, written (not translated), with the same structure: the same number of h2, h3, p, li and table tags in both.',
  'Search and answer engines: the search term in the title, an excerpt that answers the question in one or two sentences, a meta description under 160 characters, h2 headings phrased as the questions people ask.',
  'Plain senior professional prose: no hype, no emoji, no cliche openers, no "delve", "seamless", "cutting-edge" or "in today\'s fast-paced".',
];
const refusals = (r: string[]) => r.length ? 'Your earlier attempt(s) were refused by the article gate; fix each: ' + r.join(' | ') : '';

export function draftPrompt(t: DraftTopic, refused: string[] = []): string {
  return [
    'You are the marketing seat writing this week\'s blog article for a UAE construction and fit-out procurement audience.',
    `The topic (chosen from ${t.kind === 'demand' ? 'the trades UAE buyers asked for' : t.kind === 'search' ? 'what people in the UAE search for' : 'UAE market news'}): ${t.title}${t.trade ? ' (trade: ' + t.trade + ')' : ''}`,
    ...WRITING,
    t.lessons.length ? 'Lessons from topics the CEO seat replaced before (do not repeat them): ' + t.lessons.slice(0, 20).map((l) => `${l.criterion ?? ''}: ${l.reason ?? ''}`).join(' | ') : '',
    refusals(refused),
    `Answer with ONLY a JSON object ${SHAPE} and nothing else.`,
    'Evidence: ' + JSON.stringify(t.evidence),
    'Sources: ' + JSON.stringify(t.sources),
  ].filter(Boolean).join('\n');
}

export function revisePrompt(d: ReviseRound, refused: string[] = []): string {
  const failed = Object.entries(d.reasons || {}).filter(([, v]) => v?.verdict === 'fail');
  return [
    `You are the marketing seat revising blog article round ${d.round} after the CEO seat asked for a revision.`,
    'Answer EVERY reason below in the new version, and say for each what you changed:',
    ...failed.map(([k, v]) => `- ${k} (${CRITERIA[k as Criterion] ?? k}): ${v.reason}`),
    'Keep what the CEO passed.',
    ...WRITING,
    refusals(refused),
    `Answer with ONLY a JSON object {"en":{...},"ar":{...},"changes":[{"criterion":"<one of the failed criteria>","change":"what you changed for it"}]} where en and ar are ${SHAPE}.`,
    'Earlier rounds: ' + JSON.stringify(d.history),
    'Sources: ' + JSON.stringify(d.sources),
    'The article to revise: ' + JSON.stringify(d.version),
  ].filter(Boolean).join('\n');
}

export function reviewPrompt(r: ReviewRound, refused: string[] = []): string {
  const reviseAllowed = r.revise_rounds < MAX_REVISE_ROUNDS;
  return [
    'You are the CEO seat of a UAE construction and fit-out procurement marketplace. Review this week\'s blog article before it is published.',
    'The rule: when it is good for the company, approve it. Judge each criterion "pass" or "fail" with a reason of at least one full sentence that names what in the article earns the verdict:',
    ...Object.entries(CRITERIA).map(([k, v]) => `- ${k}: ${v}`),
    'Decisions: "approve" (all six pass)' + (reviseAllowed ? ', "revise" (at least one fails; the marketing seat answers each failed reason)' : '')
      + ', "replace_topic" (the topic itself cannot make a useful article).',
    reviseAllowed ? '' : `This topic has had ${MAX_REVISE_ROUNDS} revision rounds: decide "approve" or "replace_topic" only.`,
    refusals(refused),
    'Answer with ONLY a JSON object {"decision":"...","reasons":{' + Object.keys(CRITERIA).map((k) => `"${k}":{"verdict":"pass|fail","reason":"..."}`).join(',') + '}}.',
    'The topic: ' + JSON.stringify({ title: r.topic.title, kind: r.topic.kind, evidence: r.topic.evidence }),
    'Its sources: ' + JSON.stringify(r.topic.sources),
    'Earlier rounds: ' + JSON.stringify(r.history),
    r.changes ? 'What the marketing seat changed for your last reasons: ' + JSON.stringify(r.changes) : '',
    `The article, round ${r.round}: ` + JSON.stringify(r.version),
  ].filter(Boolean).join('\n');
}

const jsonOf = (answer: string) => JSON.parse(answer.slice(answer.indexOf('{'), answer.lastIndexOf('}') + 1));
export type Refusal = { ok: false; reason: string };
const lintText = (c: ReturnType<typeof checkArticle>) => c.lint.slice(0, 5).map((x) => `${x.field} ${x.rule} ${x.match}`).join('; ');
export const slugOf = (title: string) => {
  const s = title.toLowerCase().normalize('NFKD').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  return s.length <= 70 ? s : s.slice(0, 70).replace(/-[^-]*$/, '');
};

/** A draft or a revision, or why it may not be stored. `prior` is the version being revised (null for a draft). Never throws. */
export function acceptArticle(o: { sources: MarketSource[]; prior: ArticleBody | null; failed: Criterion[]; slug?: string },
  answer: string | null, truncated: boolean):
  { ok: true; article: ArticleBody; slug: string; post: { text_en: string; text_ar: string }; changes: { criterion: string; change: string }[] } | Refusal {
  if (!answer) return { ok: false, reason: 'no answer' };
  if (truncated) return { ok: false, reason: 'the answer was cut off' };
  let j: ArticleBody & { changes?: { criterion: string; change: string }[] };
  try { j = jsonOf(answer); } catch { return { ok: false, reason: 'the answer is not the article JSON' }; }
  for (const lang of ['en', 'ar'] as const) for (const f of FIELDS) {
    if (typeof j?.[lang]?.[f] !== 'string' || !j[lang][f].trim()) return { ok: false, reason: `${lang}.${f} is missing` };
  }
  if (o.prior && FIELDS.every((f) => j.en[f] === o.prior!.en[f] && j.ar[f] === o.prior!.ar[f])) return { ok: false, reason: 'the revision is identical to the version reviewed' };
  const changes = Array.isArray(j.changes) ? j.changes.filter((c) => c && typeof c.criterion === 'string' && typeof c.change === 'string') : [];
  const unanswered = o.failed.filter((k) => !changes.some((c) => c.criterion === k && c.change.trim().length >= 10));
  if (unanswered.length) return { ok: false, reason: 'the revision does not say what changed for: ' + unanswered.join(', ') };
  const head = FIELDS.filter((f) => f !== 'body_html').map((f) => j.en[f] + ' ' + j.ar[f]).join(' ');
  if (/quotes ?done/i.test(head)) return { ok: false, reason: 'a market article does not name QuotesDone in its title, excerpt or description' };
  const slug = o.slug ?? slugOf(j.en.title);
  if (!/^[a-z0-9]+(-[a-z0-9]+)+$/.test(slug)) return { ok: false, reason: 'the English title gives no usable slug' };
  // Grounding: the market sources (their title, link and text) and, for a revision, the version already grounded.
  const src = o.sources.map((s) => ({ ref: s.ref, text: [s.title, s.url, s.text].filter(Boolean).join(' ') }));
  if (o.prior) src.push({ ref: 'reviewed_version', text: FIELDS.flatMap((f) => [o.prior!.en[f], o.prior!.ar[f]]).join('\n') });
  const c = checkArticle({ slug, en: j.en, ar: j.ar, sources: src });
  if (c.lint.length) return { ok: false, reason: 'lint: ' + lintText(c) };
  if (c.ungrounded.length) return { ok: false, reason: 'numbers not in the cited market sources: ' + c.ungrounded.join(', ') };
  return { ok: true, article: { en: j.en, ar: j.ar }, slug, post: { text_en: c.post.text_en, text_ar: c.post.text_ar }, changes };
}

/** The CEO's decision, or why it may not be recorded (the database refuses the same). Never throws. */
export function acceptReview(answer: string | null, truncated: boolean, reviseAllowed: boolean):
  { ok: true; decision: 'approve' | 'revise' | 'replace_topic'; reasons: Reasons } | Refusal {
  if (!answer) return { ok: false, reason: 'no answer' };
  if (truncated) return { ok: false, reason: 'the answer was cut off' };
  let j: { decision?: string; reasons?: Record<string, ReviewReason> };
  try { j = jsonOf(answer); } catch { return { ok: false, reason: 'the answer is not the review JSON' }; }
  const d = j?.decision;
  if (d !== 'approve' && d !== 'revise' && d !== 'replace_topic') return { ok: false, reason: 'no decision among approve, revise, replace_topic' };
  if (d === 'revise' && !reviseAllowed) return { ok: false, reason: `after ${MAX_REVISE_ROUNDS} revise rounds the decision is approve or replace_topic` };
  const reasons = {} as Reasons;
  for (const k of Object.keys(CRITERIA) as Criterion[]) {
    const r = j?.reasons?.[k];
    if (!r || (r.verdict !== 'pass' && r.verdict !== 'fail') || typeof r.reason !== 'string' || r.reason.trim().length < 15) {
      return { ok: false, reason: `the reason for ${k} is missing or too short` };
    }
    reasons[k] = { verdict: r.verdict, reason: r.reason.trim() };
  }
  const fails = Object.values(reasons).filter((r) => r.verdict === 'fail').length;
  if (d === 'approve' && fails) return { ok: false, reason: 'approve with a failed criterion' };
  if (d !== 'approve' && !fails) return { ok: false, reason: d + ' with every criterion passed: that is an approval' };
  return { ok: true, decision: d, reasons };
}
