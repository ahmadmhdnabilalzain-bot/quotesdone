// identity_scrub — the supplier inbox's identity scrubbers, moved out of index.ts unchanged (21 Sep 2026,
// sales_engineer) so the drawing chain test (drawing_boq/drawing_chain.test.ts) runs the SAME code the inbox
// runs on a BOQ before a supplier sees it, rather than a copy. Behaviour is byte-for-byte what index.ts had.
import { redactBoq } from '../_shared/anonymise.ts';
import { neutraliseCadLines } from '../_shared/cad_identity.ts';
import { LICENCE_NO, TRN_BARE, TRN_LABELLED } from '../_shared/identity_numbers.ts';
// ANONYMITY FIX 27 Jul 2026 -------------------------------------------------------------------
// submit_quote stored the supplier's typed scope / conditions / exclusions / notes with nothing
// but a length clip, and set anonymized = (source === 'upload'). The UPLOAD path is scrubbed by
// quote_extract's model prompt; the FORM path was never scrubbed at all, so every typed quote was
// served to the buyer verbatim BEFORE the reveal is paid for. One supplier typing "call Ahmed on
// 050 123 4567, Al Noor Trading LLC, www.alnoor.ae" into scope hands the buyer everything the 3%
// reveal fee is charged for, and the platform is cut out of its own transaction.
//
// scrubIdentity redacts, case-insensitively: the supplier's OWN company_name (loaded from leads
// for this supplier_id) with the usual LLC / L.L.C / Trading / Contracting / Est suffix variants,
// email addresses, URLs and bare domains, and UAE phone numbers (+971, 00971, and 0 followed by
// 8-9 digits, which covers 05x mobiles and 02/03/04/06/07/09 landlines). Each hit becomes
// '[removed]' and the original string is collected into quotes.masked_terms - the same audit
// shape quote_extract already writes for the upload path, so both paths are reviewable the
// same way. It deliberately over-redacts: a false positive costs a line of scope text, a false
// negative costs the whole commission.
const CO_SUFFIX = '(?:l\\.?\\s?l\\.?\\s?c\\.?|fz-?llc|fzc|fze|trading|contracting|establishment|est\\.?|general|co\\.?|company|group)';
const ID_PATTERNS: RegExp[] = [
  // A TRN or a licence number finds the company on a public register (founder, 14 Sep 2026). First,
  // so the phone patterns below cannot take a 15-digit TRN apart and leave its label behind.
  TRN_LABELLED, TRN_BARE, LICENCE_NO,
  /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g,
  /(?:https?:\/\/|www\.)[^\s,;)\]]+/gi,
  /\b[A-Za-z0-9-]{2,}\.(?:ae|com|net|org|co|io|me|biz|info)(?:\.[A-Za-z]{2})?\b/gi,
  /\+\s?971[\s.-]?\d(?:[\s.-]?\d){6,10}/g,
  /\b00\s?971[\s.-]?\d(?:[\s.-]?\d){6,10}/g,
  /\b0\d(?:[\s.-]?\d){7,8}\b/g,
];
const rxEsc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
function companyRe(name: unknown): RegExp | null {
  const base = String(name || '').replace(new RegExp('\\b' + CO_SUFFIX, 'gi'), ' ').replace(/[^A-Za-z0-9؀-ۿ ]+/g, ' ').trim();
  const words = base.split(/\s+/).filter((w) => w.length > 1).map(rxEsc);
  if (!words.length || base.replace(/\s+/g, '').length < 3) return null;
  try { return new RegExp('\\b' + words.join('[\\s.,_-]*') + '(?:[\\s.,_-]*' + CO_SUFFIX + ')*', 'gi'); } catch (_e) { return null; }
}
export function scrubIdentity(text: string | null, ownName: unknown, hits: string[]): string | null {
  if (text == null) return text;
  let out = String(text);
  const nameRe = companyRe(ownName);
  // Contact patterns run BEFORE the company-name pattern on purpose: "www.alnoor.ae" must be
  // taken out whole as a URL, otherwise the name pattern eats "alnoor" first and leaves a
  // half-redacted "www.[removed].ae" that still points at the supplier.
  for (const re of (nameRe ? [...ID_PATTERNS, nameRe] : ID_PATTERNS)) {
    out = out.replace(re, (m: string) => { const t = String(m).trim(); if (t.length < 3) return m; if (!hits.includes(t)) hits.push(t); return '[removed]'; });
  }
  return out;
}
// ANONYMITY FIX 27 Jul 2026 (customer -> supplier direction) ----------------------------------
// scrubIdentity above protects the SUPPLIER's identity in the text a supplier types. The same
// leak exists in the opposite direction and is worth more money: inbox serves the buyer's own
// free text (summary / spec / boq) to every matched supplier BEFORE the 3% reveal fee is paid.
// A brief reading "villa fit-out for Ahmed Khan, call 050 123 4567" hands the supplier
// everything the reveal fee is charged for, and the platform is cut out of its own transaction.
//
// inquiry_ai's prompt already tells the model not to put identity into summary/spec, but that is
// a soft control the customer can bypass entirely: customer_api's create_inquiry inserts a
// client-supplied summary/spec/raw_input, and edit_inquiry patches summary/spec/boq with no
// scrub at all. This is the deterministic server-side backstop for both paths.
//
// scrubDeep walks JSONB (spec, boq) and applies the EXISTING scrubIdentity to every string it
// finds, so emails, URLs, bare domains and UAE phone numbers are redacted by exactly the same
// patterns already trusted on the supplier side. Numbers are returned untouched, so BOQ
// quantities and prices are unaffected. `ownName` is the buyer's own full_name, which lets
// companyRe redact the buyer by name the same way it redacts a supplier by company name.
export function scrubDeep(v: unknown, ownName: unknown, hits: string[]): unknown {
  if (typeof v === 'string') return scrubIdentity(v, ownName, hits);
  if (Array.isArray(v)) return v.map((x) => scrubDeep(x, ownName, hits));
  if (v && typeof v === 'object') { const o: Record<string, unknown> = {}; for (const k of Object.keys(v as Record<string, unknown>)) o[k] = scrubDeep((v as Record<string, unknown>)[k], ownName, hits); return o; }
  return v;
}
/**
 * THE LAST GATE before a supplier sees a BOQ (index.ts inbox). scrubDeep takes out contacts and the buyer's
 * own name; redactBoq removes the buyer's seed terms and the generic identifiers, then residual-scans.
 * Anything still identifying HOLDS the BOQ (boq null, withheld true). It never fails open.
 */
// 22 Sep 2026: a CAD take-off's layer and block names are neutralised here too (cad_identity rule 2), so a
// BOQ stored before customer_api scrubbed CAD names — or a DWG's, whose file customer_api cannot read —
// never shows a supplier "linework on layer <consultant>-M-DUCT".
export function inboxBoq<T>(boq: T | null | undefined, buyerName: string | null, seeds: string[], hits: string[]): { boq: T | null; withheld: boolean } {
  if (!boq) return { boq: null, withheld: false };
  const r = redactBoq(scrubDeep(neutraliseCadLines(boq), buyerName, hits) as T, seeds);
  return r.held ? { boq: null, withheld: true } : { boq: r.boq, withheld: false };
}
