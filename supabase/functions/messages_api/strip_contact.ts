// strip_contact — the pre-reveal Q&A scrubber (clarify_ask / clarify_answer), moved out of index.ts unchanged
// (3 Nov 2026, sales_engineer) so scripts/e2e/identity_leak_pipeline.ts and strip_contact.test.ts run the SAME code
// the function runs, rather than a copy.
import { knownNameRe, scrubAddresses, scrubIdentityText } from '../_shared/identity_text.ts';
import { generaliseText } from '../_shared/quote_generalise.ts';
const clip = (v: unknown, n: number) => String(v ?? '').trim().slice(0, n);
// The e-mail (obfuscated too), bare-domain, messenger and @handle patterns that lived here moved to the shared list
// (_shared/identity_text.ts EMAIL / DOMAIN / DOMAIN_LC / SOCIAL / HANDLE), adversarial review of #1838: these copies
// read "Supply 10 nos @ 450. Total" and "meet @ site. Send" as addresses, "2 years.App based" as a host, and "WhatsApp
// group for site updates" as a handle. The quotation and BOQ scrubbers now read every one of them too.
const STRIP: RegExp[] = [
  /(?:https?:\/\/|www\.)[^\s,;)\]]+/gi,
  /(?:\+|00)\s?971[\s.\-]?\d(?:[\s.\-]?\d){6,10}/g,
  // Second review of #1838: unbounded, these took "050 075 110" out of "UPVC pipe dia 050 075 110 160", "00 25200.00" out
  // of a BOQ row and "05.11.2026 10" out of a date. A number standing ALONE (no digit group before or after it) is still
  // read in any spacing ("0 4 1 2 3 4 5 6 7", "50 123 4567"); the leading-0 form takes no dots (the shared list reads
  // "050.123.4567").
  /(?<!\d[\s.\-]?)(?<!\d)0\d(?:[\s\-]?\d){7,8}(?![\s.\-]?\d)/g,
  /(?<!\d[\s.\-]?)(?<!\d)5\d(?:[\s.\-]?\d){7}(?![\s.\-]?\d)/g,
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
/** `whole`: names removed only as the whole name (a project's name is ordinary words: "Villa Kitchen Renovation"). */
export function stripContact(raw: unknown, names: unknown[] = [], whole: unknown[] = []): string {
  // Arabic-Indic digits first, so ٠٥٠١٢٣٤٥٦٧ is caught by the same number patterns.
  let s = clip(raw, 1500).replace(/[٠-٩]/g, (c) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(c))).replace(/[۰-۹]/g, (c) => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(c)));
  for (const re of STRIP) s = s.replace(re, '[removed]');
  // 3 Nov 2026 (identity_never_leaks_before_reveal.mjs: 60 of 60 messages leaked): "(050) 000 0058", "971500000064",
  // an Arabic firm name, "Thanks, ZZ Rashid Ketbi" and the customer's project went through. The shared list runs
  // too, and each known name is also matched whole by knownNameRe. A PROJECT name goes in `whole` only: scrubName
  // removes every 4+ letter word of a name, and "kitchen", "villa", "renovation" are the answer (review of #1838).
  // Known names BEFORE the shared list (13 Nov 2026): the list reduces places now, and a project named after its area
  // ("ZZ DEMO Barsha Garden Villa") must go whole before "Barsha" becomes "Dubai". Addresses first, so a name inside an
  // e-mail address cannot leave half the address behind.
  s = scrubAddresses(s, '[removed]');
  for (const n of [...names, ...whole]) { const re = knownNameRe(n); if (re) s = s.replace(re, '[removed]'); }
  s = scrubIdentityText(s, '[removed]');
  for (const n of [...names, ...whole]) { const re = knownNameRe(n); if (re) s = s.replace(re, '[removed]'); }
  for (const n of names) s = scrubName(s, n);
  return s.trim();
}

/**
 * A SUPPLIER'S QUESTION TO THE CUSTOMER before the reveal (clarify_ask). 13 Nov 2026 (anonymity audit, REPORT_C L5): "Do
 * you accept Jotun Fenomastic / Daikin FTKF50?" reached the customer's e-mail and portal as written, while the brand note
 * (a-brand-is-generalised-at-the-customer-door-not-in-the-supplier-copy) rules that no brand, model or product line
 * reaches the customer before the reveal. The same scrub as an answer, then the customer-door generaliser with the
 * supplier's own name as its context: a brand becomes "<tier> <origin> brand", a model "model stated (shown after
 * reveal)". The question is the supplier's own text, so his name is matched with its fragments too ("Falcolux", "FT team").
 */
export function stripSupplierQuestion(raw: unknown, names: unknown[] = []): string {
  let s = stripContact(raw, names);
  for (const n of names) { const re = knownNameRe(n, { fragments: true }); if (re) s = s.replace(re, '[removed]'); }
  return generaliseText(s, { supplierNames: names.map((n) => String(n ?? '')).filter(Boolean) }).text.trim();
}
