// THE MARKETING SEAT'S STYLE GATE (marketing, 22 Sep 2026).
//
// Founder, instruction 722: the seat writes blogs and LinkedIn messages, and "no one should feel he is an
// agent -- replies extremely professional". Two deterministic gates run on EVERYTHING the seat stores for
// a reader (an article, its LinkedIn post, an outreach message, a follow-up):
//
//   lintDraft          refuses the marks of machine writing and sales spam: the cliche openers, the words
//                      models overuse, unsupported social proof ("trusted by", "thousands of"), emoji,
//                      more than one exclamation mark, a run of em dashes in a short text, and a list of
//                      three stock adjectives ("fast, simple and transparent"). The phrase lists are data
//                      in marketing_style_tells.json; docs/marketing/writing_style.md is the guide.
//   ungroundedNumbers  an article may state no number its cited company sources do not contain (a price,
//                      a percentage, a count, a year). The seat invents nothing; a figure it cannot cite
//                      is refused at ingest, not corrected later.
//
// Deterministic by design: no model is called here, and none is needed to refuse a phrase.
// Tested by supabase/functions/_shared/marketing_style.test.ts.
import TELLS from './marketing_style_tells.json' with { type: 'json' };

export type DraftKind = 'message' | 'note' | 'post' | 'article';
export type Finding = { rule: string; match: string };

type Groups = Record<string, string[]>;
const GROUPS: Array<[string, Groups]> = [['en', TELLS.en as Groups], ['ar', TELLS.ar as Groups]];
const ADJ = new Set((TELLS.adjectives as string[]).map((a) => a.toLowerCase()));
const ADJ_SUFFIX = /(ive|ful|less|able|ible|ous|ent|ant|ary)$/;

/** Text a reader sees: tags removed, entities for spaces/dashes decoded, whitespace collapsed. */
export function plain(s: string): string {
  return String(s || '')
    .replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;/g, ' ').replace(/&mdash;/g, '—').replace(/&amp;/g, '&').replace(/&#39;|&rsquo;/g, "'")
    .replace(/\s+/g, ' ').trim();
}

// The apostrophe a phone or an editor types (U+2019) must not let "you’re" slip past "you're".
const fold = (s: string) => plain(s).toLowerCase().replace(/[‘’]/g, "'");

export function lintDraft(text: string, kind: DraftKind): Finding[] {
  const t = fold(text);
  const out: Finding[] = [];
  for (const [lang, groups] of GROUPS) {
    for (const [group, phrases] of Object.entries(groups)) {
      for (const p of phrases) if (t.includes(p.toLowerCase())) out.push({ rule: `${group}.${lang}`, match: p });
    }
  }
  const emoji = t.match(/\p{Extended_Pictographic}/gu);
  if (emoji) out.push({ rule: 'emoji', match: emoji.join('') });
  if ((t.match(/!/g) || []).length > 1) out.push({ rule: 'exclamation', match: '!'.repeat((t.match(/!/g) || []).length) });
  if (kind !== 'article' && (t.match(/—/g) || []).length > 1) out.push({ rule: 'em_dash_run', match: '—' });
  for (const m of t.matchAll(/\b([a-z-]+), ([a-z-]+),? and ([a-z-]+)\b/g)) {
    const words = [m[1], m[2], m[3]];
    if (words.filter((w) => ADJ.has(w) || ADJ_SUFFIX.test(w)).length >= 2 && words.some((w) => ADJ.has(w))) {
      out.push({ rule: 'adjective_triplet', match: m[0] });
    }
  }
  return out;
}

const DIGITS_AR = /[٠-٩۰-۹]/g;
const toLatin = (s: string) => s.replace(DIGITS_AR, (d) => String((d.charCodeAt(0) & 0xf) % 10));
/** Every digit run in the text ("3", "1633275", "2026", "3.5"), Arabic-Indic digits read as Latin. */
export function numbersIn(text: string): string[] {
  return [...new Set(toLatin(plain(text)).match(/\d+(?:[.,]\d+)*/g) || [])];
}

/** The numbers an article states that none of its sources contains. Empty = grounded. */
export function ungroundedNumbers(text: string, sources: string[]): string[] {
  const known = new Set(sources.flatMap((s) => numbersIn(s)));
  return numbersIn(text).filter((n) => !known.has(n));
}
