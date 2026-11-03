// strip_contact — the pre-reveal Q&A scrubber (clarify_ask / clarify_answer), moved out of index.ts unchanged
// (3 Nov 2026, sales_engineer) so scripts/e2e/identity_leak_pipeline.ts and strip_contact.test.ts run the SAME code
// the function runs, rather than a copy.
import { knownNameRe, scrubIdentityText } from '../_shared/identity_text.ts';
const clip = (v: unknown, n: number) => String(v ?? '').trim().slice(0, n);
const STRIP: RegExp[] = [
  /[A-Za-z0-9._%+-]+\s*(?:@|\(at\)|\[at\])\s*[A-Za-z0-9.-]+\s*(?:\.|\(dot\)|\[dot\])\s*[A-Za-z]{2,}/gi,
  /(?:https?:\/\/|www\.)[^\s,;)\]]+/gi,
  /\b[A-Za-z0-9-]{2,}\.(?:ae|com|net|org|co|io|me|biz|info|app|link)(?:\.[A-Za-z]{2})?\b/gi,
  /(?:\+|00)\s?971[\s.\-]?\d(?:[\s.\-]?\d){6,10}/g,
  /\b0\d(?:[\s.\-]?\d){7,8}\b/g,
  /\b5\d(?:[\s.\-]?\d){7}\b/g,
  /\b(?:whats\s*app|wa\.me|telegram|t\.me|viber|botim|snapchat|skype|instagram)\b\S*/gi,
  /(^|\s)@[A-Za-z0-9_.]{3,}/g,
];
const NAME_STOP = new Set(['llc', 'l.l.c', 'trading', 'contracting', 'general', 'company', 'group', 'est', 'establishment', 'services', 'technical', 'the', 'and']);
// ponytail: a name is removed as whole words of 4+ letters; a nickname or misspelling survives.
// Upgrade path is customer_api's companyRe if a leak is ever measured.
function scrubName(text: string, name: unknown): string {
  const words = String(name || '').split(/[^A-Za-z؀-ۿ]+/).filter((w) => w.length >= 4 && !NAME_STOP.has(w.toLowerCase()));
  let out = text;
  for (const w of words) out = out.replace(new RegExp('(^|[^A-Za-z؀-ۿ])' + w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(?=$|[^A-Za-z؀-ۿ])', 'gi'), '$1[removed]');
  return out;
}
export function stripContact(raw: unknown, names: unknown[] = []): string {
  // Arabic-Indic digits first, so ٠٥٠١٢٣٤٥٦٧ is caught by the same number patterns.
  let s = clip(raw, 1500).replace(/[٠-٩]/g, (c) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(c))).replace(/[۰-۹]/g, (c) => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(c)));
  for (const re of STRIP) s = s.replace(re, (m: string, lead?: string) => (typeof lead === 'string' && /^\s?$/.test(lead) && m.startsWith(lead) ? lead : '') + '[removed]');
  // 3 Nov 2026 (identity_never_leaks_before_reveal.mjs: 60 of 60 messages leaked): "(050) 000 0058", "971500000064",
  // an Arabic firm name, "Thanks, ZZ Rashid Ketbi" and the customer's project went through. The shared list runs
  // too, and each known name is also matched by knownNameRe (the whole name, any two consecutive words of it).
  s = scrubIdentityText(s, '[removed]');
  for (const n of names) { const re = knownNameRe(n); if (re) s = s.replace(re, '[removed]'); }
  for (const n of names) s = scrubName(s, n);
  return s.trim();
}
