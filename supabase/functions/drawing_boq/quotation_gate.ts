// quotation_gate — a customer's existing quotation reaches suppliers as OUR inquiry: its items, descriptions, quantities,
// units and the makes it specifies, and nothing of the old supplier: no rate, amount, total, discount, VAT, payment term
// or validity, no party, no reference number, no letterhead word (13 Nov 2026, sales_engineer; founder ruling 1683: "He
// removes the details of the existing supplier and reformat the inquiry in our template and shares it with the
// suppliers that are relevant").
//
// WHY A CODE GATE when the model reads first (rulings 1663/1664/1666). The model decides what the file IS and rebuilds
// it (drawing_boq SYS, document_kind 'quotation'). This gate is the backstop that must hold when the model is careless.
// MEASURED (anonymity audit A, 13 Nov 2026, A_customer_to_supplier/s1_model_stub.ts): a careless reading of the ZZ DEMO
// Falcon Trading quotation, through every gate the PDF path had, reached the supplier's BOQ with "Falcon Trading",
// "Ahmed Saeed", "FT/Q/2026/0412", "FT-SD-04", and the prices "AED 95.00/m2, amount 8,170.00", "rate 1,180" and
// "AED 32,816.70" in `basis`, `assumptions` and `summary` (the portal's BoqTable shows basis and assumptions).
//
// WHAT IT DOES, and only on a priced document (the model said so, or the text is priced: looksPriced):
//  * `basis` is replaced by one fixed phrase: a quotation's line basis is the old supplier's own pricing note, and a
//    supplier needs only that the line is as the customer's document lists it.
//  * `assumptions` are replaced by QUOTATION_NOTE: what the model assumed about another supplier's offer is not ours.
//  * the summary, every description, section, specification, keyword and missing item lose every money shape, every
//    reference number (and every code that shares its prefix: "FT-SD-04" beside "FT/Q/2026/0412"), and every party term
//    the document states outside its table (quotation_parties.ts). A sentence about payment, validity, discount or VAT
//    goes whole.
//  * a total, subtotal, VAT or discount row is not an item and is dropped.
// WHAT IT NEVER DOES: touch a quantity, a unit, a dimension ("300x600mm", "150mm upstand"), a model number, a standard, a
// warranty or a country of origin. Held to that by the over-redaction rows of the test.
// prevented by: drawing_boq/a_quotation_reaches_suppliers_as_our_inquiry.test.ts

import { QUOTATION_NOTE, quotationPartyTerms, scrubTerms } from './quotation_parties.ts';
import { UNIT_ALTERNATION } from './boq_from_text.ts';

export const QUOTATION_BASIS = 'As listed in the customer\'s document';

const CUR = '(?:AED|Dhs?\\.?|DH|د\\.?\\s?إ\\.?|درهم|USD|US\\$|\\$|€|£|EUR|GBP|SAR|ريال)';
const NUM = '\\d[\\d,]*(?:\\.\\d+)?';
const UNIT_AFTER = '(?:\\s*(?:/\\s*)?(?:m2|m²|sqm|sq\\.?\\s?m|m3|lm|rm|m|mm|cm|kg|kw|kva|tr|nos?|pcs|sets?|each|ea|lot|ls|month|months|hr|hrs|hour|day|days))?';
// A figure followed by a unit, a size or a percentage is a QUANTITY, never money (review of 13 Nov 2026, item 6a: "2,400.00 m2"
// came out ".00 m2" because the figure backtracked to "2,400" and ".00 m2" was not a unit). The BOQ reader's own unit table
// (boq_from_text.ts UNIT_ALTERNATION), the sizes and the rest of the trade's units; and the whole figure first (no backtrack).
const UNITS = `${UNIT_ALTERNATION}|mm|cm|m3|ltrs?|litres?|liters?|btu|kva|kwh?|hp|w|v|a|bar|psi|inch(?:es)?|in|ft|feet|"|x|×|%|rooms?|floors?|zones?|points?|lengths?|rolls?|bags?|sheets?|boxes|panels?|pairs?`;
const NOT_A_MEASURE = `(?![\\d.,])(?!\\s*(?:${UNITS})(?![a-z]))`;
/** Money as a quotation prints it: a currency with a figure, a priced word with a figure, a figure per unit with a currency. */
const MONEY = new RegExp([
  `${CUR}\\s*${NUM}${UNIT_AFTER}`, `${NUM}\\s*${CUR}${UNIT_AFTER}`,
  `\\b(?:unit\\s+)?(?:rate|price|amount|total|sub-?\\s?total|grand\\s+total|cost|discount|vat)\\b\\s*(?:of|at|is|was|:|=|-)?\\s*(?:${CUR}\\s*${NUM}${UNIT_AFTER}|${NUM}(?:\\s*%)?${NOT_A_MEASURE})`,
  `@\\s*(?:${CUR}\\s*)?${NUM}${UNIT_AFTER}`, `\\b${NUM}\\s*\\/-`,
  // a figure with thousands separators, or with two decimals and no unit after it, is money in a quotation's prose
  `\\b\\d{1,3}(?:,\\d{3})+(?:\\.\\d{1,2})?${NOT_A_MEASURE}`, `(?<![+\\-±.\\d])\\b\\d{2,}\\.\\d{2}${NOT_A_MEASURE}`,
  `(?:السعر|المبلغ|الإجمالي|سعر الوحدة)\\s*[:：]?\\s*${NUM}`,
].join('|'), 'gi');
/** A sentence about the old offer's commercial terms: it goes whole. */
// The old offer's own terms (payment, validity, bank, who quoted it): such a sentence goes whole, money or not.
const TERMS_SENTENCE = /\b(?:payment|advance|down\s*payment|retention|validity|valid\s+(?:for|until|till)|competitor|quoted\s+(?:at|by)|bank|iban|cheques?|pdc)\b|الدفع|صالح/i;
// A sentence about price (rate, total, VAT, discount): it goes whole only when it also holds money (review item 6e: "Supply and
// fix tiles to 2 bathrooms, total area 85 m2." was dropped for the word "total").
const PRICE_SENTENCE = /\b(?:discount|vat|tax|prices?|priced|rates?|amounts?|totals?)\b|الخصم|الضريبة|السعر|الأسعار/i;
/** A reference number: letters and digits with two or more separators and a year, or a labelled one. */
const REF = /\b(?:(?:quotation|quote|qtn|offer|proforma|ref(?:erence)?|our\s+ref|your\s+ref|enquiry|inquiry|rfq|po|job)\s*(?:no\.?|number|#|ref\.?)?\s*[:：.]?\s*)?[A-Z]{1,6}[/\-](?:[A-Z0-9]{1,8}[/\-]){1,4}[A-Z0-9]{1,8}\b/g;
// A standard, a pipe class or a grade is a SPECIFICATION (review item 6b: "DN-100-PN16", "EN-1504-2", "ASTM-C-920", "SS-316-L"
// were removed). A reference is a token with a year, a labelled one, or one built on the document's own prefix.
const SPEC_PREFIX = /^(?:EN|BS|BSEN|ASTM|DIN|ISO|IEC|SS|DN|PN|UL|NFPA|ANSI|ASME|AISI|JIS|GB|IP|IK|CE|SASO|ESMA|UAE\.S|GSO|NEMA|EN\d*)$/i;
const isReference = (tok: string) => { const t = tok.replace(/^.*?[:：.]\s*/, '').trim(); const p = /^([A-Z]{1,6})[/\-]/i.exec(t)?.[1] || ''; return !SPEC_PREFIX.test(p) && /(?:19|20)\d{2}/.test(t); };
const REF_LABELLED = /\b(?:quotation|quote|qtn|offer|proforma|ref(?:erence)?|our\s+ref|your\s+ref|enquiry|inquiry|rfq)\s*(?:no\.?|number|#)\s*[:：.]?\s*[A-Z0-9][A-Z0-9/\-.]{2,}/gi;
const TOTAL_ROW = /^\s*(?:sub-?\s*total|grand\s+total|total(?:\s+amount)?|net\s+(?:amount|total)|vat(?:\s*@?\s*\d+\s*%)?|value\s+added\s+tax|discount|less\s+discount|amount\s+in\s+words|rounding|المجموع|الإجمالي|ضريبة القيمة المضافة|الخصم)\b/i;

/** A reference number a priced document carries, and the letter prefix it is built on ("FT/Q/2026/0412" -> "FT"). */
export function referencesIn(text: string): { refs: string[]; prefixes: string[] } {
  const refs = new Set<string>(); const prefixes = new Set<string>();
  for (const m of String(text || '').matchAll(REF)) {
    const tok = m[0].replace(/^.*?[:：.]\s*/, '').trim();
    // a reference carries a year and is not a standard ("FD-1", "600-600", "DN-100-PN16", "EN-1504-2" are not references)
    if (!isReference(tok)) continue;
    refs.add(tok);
    const p = /^([A-Z]{2,6})[/\-]/.exec(tok)?.[1];
    if (p) prefixes.add(p);
  }
  for (const m of String(text || '').matchAll(REF_LABELLED)) refs.add(m[0].trim());
  return { refs: [...refs], prefixes: [...prefixes] };
}

/**
 * Code backstop for "what priced document is this" (review item: a drawing whose text says "flow rate ... amount" was routed as
 * another supplier's quotation). 'quotation': a party (a letterhead firm or a To / Attn / M/s block) AND priced lines AND a total
 * with money. 'priced': money printed three or more times without that structure (a consultant's or the customer's own priced
 * BOQ: its rates are the customer's budget, hidden from suppliers by the same rule). null: not priced. The model's document_kind
 * decides first; this only adds what code can see on the text layer.
 */
export function pricedKind(text: string): 'quotation' | 'priced' | null {
  const t = String(text || '');
  const lines = t.split('\n');
  const money = (t.match(new RegExp(`${CUR}\\s*${NUM}|${NUM}\\s*${CUR}|\\b${NUM}\\s*\\/-`, 'gi')) || []).length;
  const pricedLines = lines.filter((l) => /\d{1,3}(?:,\d{3})+(?:\.\d{2})?(?![\d.,])|(?<![\d.])\d{2,}\.\d{2}(?![\d.,])/.test(l) && new RegExp(`\\b\\d+(?:\\.\\d+)?\\s*(?:${UNIT_ALTERNATION})\\b`, 'i').test(l)).length;
  const total = lines.some((l) => /\b(?:grand\s+total|sub-?\s*total|total(?:\s+amount)?|net\s+amount)\b|الإجمالي|المجموع/i.test(l) && /\d{1,3}(?:,\d{3})+|\d+\.\d{2}/.test(l));
  const party = lines.slice(0, 15).some((l) => /\b(?:l\.?l\.?c|fze|fzco|trading|contracting|est\.|establishment)\b|ذ\.?م\.?م|شرك[ةه]|مؤسس[ةه]/i.test(l))
    || lines.some((l) => /^\s*(?:to|attn|attention|m\/s|messrs\.?|kind\s+attn\.?|السادة)\s*[:：.]?\s+\S/i.test(l));
  const priceHead = lines.some((l) => /\b(?:unit\s+price|u\.?\s?price|rate)\b.*\b(?:amount|total)\b|سعر الوحدة/i.test(l));
  if (party && (pricedLines >= 2 || priceHead) && total) return 'quotation';
  if (money >= 3 || (priceHead && pricedLines >= 2) || (total && pricedLines >= 2)) return 'priced';
  return null;
}
/** Priced in any way: its money never reaches a supplier and its pages are never pictured. */
export const looksPriced = (text: string) => pricedKind(text) !== null;

/** What is still priced or referenced in a string (the residual the test and the supplier door read). */
export function priceResidue(s: string, refs: string[] = []): string[] {
  const t = String(s || '');
  const found = [...t.matchAll(MONEY)].map((m) => m[0].trim()).filter((x) => /\d/.test(x));
  for (const r of refs) if (r.length >= 4 && t.toLowerCase().includes(r.toLowerCase())) found.push(r);
  return found;
}

export type QuotationTerms = { parties: string[]; refs: string[]; prefixes: string[] };
// A firm's first word becomes a term of its own only when it is its distinctive name, never a trade, material or common word
// (review item 6c: "Marble Trading LLC" made "marble" a term, erased from every line and seeded at every door). The words are
// _shared/identity_text.ts TRADE_WORDS (the short-name list of the text backstop) and the materials of the BOQ readers.
const TRADE_OR_COMMON = new Set(`dubai sharjah ajman emirates general modern global royal golden prime first united national gulf arabian interior
  interiors building technical trading contracting engineering establishment company group holding supply cheques payment insulation glass
  concrete timber wood paint paints tiles tile marble granite stone steel iron metal metals aluminium aluminum copper brass cable cables pipe
  pipes electric electrical electro mechanical plumbing cooling air water pool pools solar power energy light lighting safety security fire
  cleaning gypsum ceiling doors door windows window furniture kitchen kitchens carpentry joinery scaffolding elevator elevators lifts
  waterproofing flooring decor mirror cement sand blocks ceramic ceramics porcelain roofing landscaping glazing facade hvac smart home
  green blue star city world best quality perfect future modern standard`.split(/\s+/).filter(Boolean));

/** The party, reference and prefix terms of a priced document, from its text lines (a PDF's linesFromRuns, a doc_read text). */
export function quotationTerms(lines: string[], extra: string[] = []): QuotationTerms {
  // The lines OUTSIDE the priced table: a line that carries a quantity with a unit or a price is a table row.
  const outside = lines.filter((l) => !(new RegExp(`\\b\\d+(?:\\.\\d+)?\\s*(?:m2|m²|sqm|nos?|pcs|sets?|lm|m|kg|lot)\\b`, 'i').test(l) && /\d[\d,]*\.\d{2}|\d{1,3}(?:,\d{3})+/.test(l)));
  const parties = quotationPartyTerms(outside);
  // The distinctive first word of a firm's name ("Falcon" of "Falcon Trading LLC"): a description says "as per Falcon
  // standard detail". Five letters or more, capitalised, and not a word of the trade.
  for (const p of [...parties]) {
    if (!/\b(?:l\.?l\.?c|fze|fzco|trading|contracting|est\.?|establishment|engineering|interiors?|group|company|co\.)\b/i.test(p)) continue;
    // only a firm's own name ("ZZ DEMO Falcon Trading LLC"), never a line that merely mentions one
    if (!/^(?:ZZ\s+DEMO\s+)?[\p{Lu}][\p{L}&'.-]*(?:\s+[\p{Lu}][\p{L}&'.-]*){0,4}$/u.test(p.trim())) continue;
    const w = /^(?:ZZ\s+DEMO\s+)?([A-Z][a-z]{4,}|[A-Z]{5,})\b/.exec(p)?.[1];
    if (w && !TRADE_OR_COMMON.has(w.toLowerCase())) parties.push(w[0] + w.slice(1).toLowerCase());
  }
  const { refs, prefixes } = referencesIn(lines.join('\n'));
  // A file name contributes nothing of its own (review item 6d: "tiles.pdf" erased "tiles"): it only confirms parties the document states.
  void extra;
  return { parties: [...new Set(parties)].sort((a, b) => b.length - a.length), refs, prefixes };
}

const clean = (s: string) => s.replace(/\(\s*\)|\[\s*\]/g, '').replace(/\s+([,.;:)])/g, '$1').replace(/([(])\s+/g, '$1').replace(/(?:,\s*){2,}/g, ', ').replace(/\s{2,}/g, ' ').replace(/^[\s,;:\-–]+|[\s,;:\-–]+$/g, '').trim();

/** One string of a priced document, as a supplier may read it. */
export function scrubQuotationText(s: unknown, t: QuotationTerms): string {
  let x = String(s ?? '');
  x = scrubTerms(x, t.refs);
  for (const p of t.prefixes) x = x.replace(new RegExp(`\\b${p}[/\\-][A-Z0-9/\\-]{1,24}\\b`, 'g'), '');
  x = x.replace(REF, (m) => (isReference(m) ? '' : m)).replace(REF_LABELLED, (m) => (SPEC_PREFIX.test((/[:：.#]\s*([A-Z]{1,6})[/\-]/i.exec(m) || [])[1] || '') ? m : ''));
  x = x.replace(MONEY, '');
  x = scrubTerms(x, t.parties);
  // "as per <removed> standard detail" / "as quoted" / "as per quotation" leave nothing a supplier can use
  x = x.replace(/\bas\s+(?:per\s+)?(?:quoted|per\s+(?:the\s+)?(?:quotation|quote|offer))\b/gi, '').replace(/\bquoted\s+by\b\s*/gi, '')
    // the old supplier's own "standard detail", its name and code removed, says nothing a supplier can price
    .replace(/,?\s*\bas\s+per\s+(?:the\s+|our\s+|their\s+)?standard\s+details?\b/gi, '');
  return clean(x);
}
/** A sentence-list field (summary, missing_info): sentences about the old offer's terms go whole, the rest is scrubbed. */
const hasMoney = (u: string) => new RegExp(MONEY.source, 'i').test(u);
const scrubSentences = (s: unknown, t: QuotationTerms) => clean(String(s ?? '').split(/(?<=[.;!?])\s+/).filter((u) => !TERMS_SENTENCE.test(u) && !(PRICE_SENTENCE.test(u) && hasMoney(u))).map((u) => scrubQuotationText(u, t)).filter(Boolean).join(' '));

/** A customer-authored sentence on a request built from a quotation (the summary): money and commercial-terms sentences out. */
export const quotationProse = (s: unknown) => scrubSentences(s, { parties: [], refs: [], prefixes: [] });

/** The old supplier's terms the request keeps for its own doors (customer-only spec key old_supplier_terms): compact, capped. */
// The terms kept as seeds are the MAXIMAL ones (a full firm name, a person, a project), the distinctive first words and the
// references; never the two-word runs cut out of them for the reading's own lines ("Garden Villa"), nor a trade word.
export const termsToKeep = (t: QuotationTerms) => {
  const ps = t.parties.filter((p) => p.length >= 4 && p.length <= 80);
  const maximal = ps.filter((p) => (p.includes(' ') ? !ps.some((q) => q !== p && q.toLowerCase().includes(p.toLowerCase())) : !TRADE_OR_COMMON.has(p.toLowerCase())));
  return [...new Set([...maximal, ...t.refs])].slice(0, 80);
};

// deno-lint-ignore no-explicit-any
type Line = Record<string, any>;
/** The whole reading of a priced document, rebuilt as our inquiry (idempotent: running it twice changes nothing). */
// deno-lint-ignore no-explicit-any
export const PRICED_NOTE = 'Rates in the customer\'s document are not shared: quantities, units and specifications only.';
export function quotationGate<B extends Record<string, any>>(boq: B, t: QuotationTerms, kind: 'quotation' | 'priced' = 'quotation'): B {
  if (!boq || typeof boq !== 'object') return boq;
  const lines: Line[] = Array.isArray(boq.boq) ? boq.boq : [];
  // a total row is no item; "Total 85 m2 of tiles" (a measure) is one
  const isTotalRow = (d: string) => TOTAL_ROW.test(d) && !new RegExp(`\\d\\s*(?:${UNIT_ALTERNATION})(?![a-z])`, 'i').test(d);
  const kept = lines.filter((l) => !isTotalRow(String(l?.description ?? l?.item ?? ''))).map((l) => {
    const o: Line = { ...l, basis: QUOTATION_BASIS };
    for (const k of ['section', 'description', 'description_ar', 'section_ar', 'specification', 'brand', 'model', 'notes']) if (typeof o[k] === 'string') o[k] = scrubQuotationText(o[k], t);
    if (typeof o.item === 'string' && !/^\d{1,4}(?:\.\d{1,3})*$/.test(o.item.trim())) o.item = scrubQuotationText(o.item, t);
    for (const k of ['rate', 'unit_price', 'price', 'amount', 'total', 'discount', 'vat']) delete o[k];
    return o;
  }).filter((l) => String(l.description || '').trim());
  const out: Line = kind === 'quotation' ? { ...boq, boq: kept, document_kind: 'quotation', assumptions: [QUOTATION_NOTE] } : { ...boq, boq: kept, document_kind: 'boq', priced: true, assumptions: [PRICED_NOTE] };
  delete out.old_supplier_terms;
  for (const k of ['summary', 'drawing_type', 'scale_detected']) if (typeof out[k] === 'string') out[k] = scrubSentences(out[k], t);
  if (Array.isArray(out.missing_info)) out.missing_info = out.missing_info.map((m: unknown) => scrubSentences(m, t)).filter(Boolean);
  if (Array.isArray(out.keywords)) out.keywords = out.keywords.map((k: unknown) => scrubQuotationText(k, t)).filter(Boolean);
  if (out.sufficiency && typeof out.sufficiency === 'object' && Array.isArray(out.sufficiency.missing)) out.sufficiency = { ...out.sufficiency, missing: out.sufficiency.missing.map((m: unknown) => scrubSentences(m, t)).filter(Boolean) };
  return out as B;
}

/** True when a reading says it is a priced document: the model's own word, or the code reader's quotation note. */
// deno-lint-ignore no-explicit-any
export const isQuotationReading = (boq: any) => !!boq && typeof boq === 'object' && (boq.document_kind === 'quotation' || (Array.isArray(boq.assumptions) && boq.assumptions.includes(QUOTATION_NOTE)));
