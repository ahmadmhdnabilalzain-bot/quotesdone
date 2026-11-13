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

export const QUOTATION_BASIS = 'As listed in the customer\'s document';

const CUR = '(?:AED|Dhs?\\.?|DH|د\\.?\\s?إ\\.?|درهم|USD|US\\$|\\$|€|£|EUR|GBP|SAR|ريال)';
const NUM = '\\d[\\d,]*(?:\\.\\d+)?';
const UNIT_AFTER = '(?:\\s*(?:/\\s*)?(?:m2|m²|sqm|sq\\.?\\s?m|m3|lm|rm|m|mm|cm|kg|kw|kva|tr|nos?|pcs|sets?|each|ea|lot|ls|month|months|hr|hrs|hour|day|days))?';
// A figure followed by a unit, a size or a percentage is a measure, never money: "1,200 m2", "300x600", "2.40 m", "15%".
const NOT_A_MEASURE = '(?!\\s*(?:mm|cm|m2|m²|m3|m³|m\\b|sqm|sq\\.?\\s?m|lm|rm|kg|kw|kva|tr|nos?\\b|pcs|sets?\\b|lot|ls\\b|x|×|%|"|inch|in\\b|ft|litres?|l\\b|bar\\b|w\\b|v\\b|a\\b))';
/** Money as a quotation prints it: a currency with a figure, a priced word with a figure, a figure per unit with a currency. */
const MONEY = new RegExp([
  `${CUR}\\s*${NUM}${UNIT_AFTER}`, `${NUM}\\s*${CUR}${UNIT_AFTER}`,
  `\\b(?:unit\\s+)?(?:rate|price|amount|total|sub-?\\s?total|grand\\s+total|cost|discount|vat)\\b\\s*(?:of|at|is|was|:|=|-)?\\s*(?:${CUR}\\s*)?${NUM}(?:\\s*%)?${UNIT_AFTER}`,
  `@\\s*(?:${CUR}\\s*)?${NUM}${UNIT_AFTER}`,
  // a figure with thousands separators, or with two decimals and no unit after it, is money in a quotation's prose
  `\\b\\d{1,3}(?:,\\d{3})+(?:\\.\\d{1,2})?\\b${NOT_A_MEASURE}`, `(?<![+\\-±.\\d])\\b\\d{2,}\\.\\d{2}\\b${NOT_A_MEASURE}`,
  `السعر\\s*[:：]?\\s*${NUM}`, `المبلغ\\s*[:：]?\\s*${NUM}`, `الإجمالي\\s*[:：]?\\s*${NUM}`,
].join('|'), 'gi');
/** A sentence about the old offer's commercial terms: it goes whole. */
const TERMS_SENTENCE = /\b(?:payment|advance|down\s*payment|retention|validity|valid\s+(?:for|until|till)|discount|vat|tax|incl(?:uding|\.)?\s+vat|excl(?:uding|\.)?\s+vat|prices?|priced|rates?|amounts?|totals?|grand\s+total|competitor|quoted\s+(?:at|by)|bank|iban|cheque|pdc)\b|الدفع|الخصم|الضريبة|السعر|الأسعار|صالح/i;
/** A reference number: letters and digits with two or more separators and a year, or a labelled one. */
const REF = /\b(?:(?:quotation|quote|qtn|offer|proforma|ref(?:erence)?|our\s+ref|your\s+ref|enquiry|inquiry|rfq|po|job)\s*(?:no\.?|number|#|ref\.?)?\s*[:：.]?\s*)?[A-Z]{1,6}[/\-](?:[A-Z0-9]{1,8}[/\-]){1,4}[A-Z0-9]{1,8}\b/g;
const REF_LABELLED = /\b(?:quotation|quote|qtn|offer|proforma|ref(?:erence)?|our\s+ref|your\s+ref|enquiry|inquiry|rfq)\s*(?:no\.?|number|#)\s*[:：.]?\s*[A-Z0-9][A-Z0-9/\-.]{2,}/gi;
const TOTAL_ROW = /^\s*(?:sub-?\s*total|grand\s+total|total(?:\s+amount)?|net\s+(?:amount|total)|vat(?:\s*@?\s*\d+\s*%)?|value\s+added\s+tax|discount|less\s+discount|amount\s+in\s+words|rounding|المجموع|الإجمالي|ضريبة القيمة المضافة|الخصم)\b/i;

/** A reference number a priced document carries, and the letter prefix it is built on ("FT/Q/2026/0412" -> "FT"). */
export function referencesIn(text: string): { refs: string[]; prefixes: string[] } {
  const refs = new Set<string>(); const prefixes = new Set<string>();
  for (const m of String(text || '').matchAll(REF)) {
    const tok = m[0].replace(/^.*?[:：.]\s*/, '').trim();
    // a reference has a year or a run of three or more digits; a size ("FD-1", "600-600") does not
    if (!/(?:19|20)\d{2}|\d{3,}/.test(tok)) continue;
    refs.add(tok);
    const p = /^([A-Z]{2,6})[/\-]/.exec(tok)?.[1];
    if (p) prefixes.add(p);
  }
  for (const m of String(text || '').matchAll(REF_LABELLED)) refs.add(m[0].trim());
  return { refs: [...refs], prefixes: [...prefixes] };
}

/** Code backstop for "is this a priced document": money printed three or more times, or a total row with money. */
export function looksPriced(text: string): boolean {
  const t = String(text || '');
  const money = (t.match(new RegExp(`${CUR}\\s*${NUM}|${NUM}\\s*${CUR}`, 'gi')) || []).length;
  const totals = /\b(?:grand\s+total|sub-?\s*total|total\s+amount|vat\s*(?:@|\d))/i.test(t) && /\d{1,3}(?:,\d{3})+(?:\.\d{2})?|\d+\.\d{2}/.test(t);
  const priceHead = /\b(?:unit\s+)?(?:rate|price)\b/i.test(t) && /\bamount\b/i.test(t);
  return money >= 3 || totals || priceHead;
}

/** What is still priced or referenced in a string (the residual the test and the supplier door read). */
export function priceResidue(s: string, refs: string[] = []): string[] {
  const t = String(s || '');
  const found = [...t.matchAll(MONEY)].map((m) => m[0].trim()).filter((x) => /\d/.test(x));
  for (const r of refs) if (r.length >= 4 && t.toLowerCase().includes(r.toLowerCase())) found.push(r);
  return found;
}

export type QuotationTerms = { parties: string[]; refs: string[]; prefixes: string[] };

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
    if (w && !/^(?:dubai|sharjah|ajman|emirates|general|modern|global|royal|golden|prime|first|united|national|gulf|arabian|interior|building|technical|trading|contracting|engineering|establishment|company|group|holding|supply|cheques|payment)$/i.test(w)) parties.push(w[0] + w.slice(1).toLowerCase());
  }
  const { refs, prefixes } = referencesIn(lines.join('\n'));
  return { parties: [...new Set([...parties, ...extra.filter((x) => String(x || '').trim().length >= 4)])].sort((a, b) => b.length - a.length), refs, prefixes };
}

const clean = (s: string) => s.replace(/\(\s*\)|\[\s*\]/g, '').replace(/\s+([,.;:)])/g, '$1').replace(/([(])\s+/g, '$1').replace(/(?:,\s*){2,}/g, ', ').replace(/\s{2,}/g, ' ').replace(/^[\s,;:\-–]+|[\s,;:\-–]+$/g, '').trim();

/** One string of a priced document, as a supplier may read it. */
export function scrubQuotationText(s: unknown, t: QuotationTerms): string {
  let x = String(s ?? '');
  x = scrubTerms(x, t.refs);
  for (const p of t.prefixes) x = x.replace(new RegExp(`\\b${p}[/\\-][A-Z0-9/\\-]{1,24}\\b`, 'g'), '');
  x = x.replace(REF, (m) => (/(?:19|20)\d{2}|\d{3,}/.test(m) ? '' : m)).replace(REF_LABELLED, '');
  x = x.replace(MONEY, '');
  x = scrubTerms(x, t.parties);
  // "as per <removed> standard detail" / "as quoted" / "as per quotation" leave nothing a supplier can use
  x = x.replace(/\bas\s+(?:per\s+)?(?:quoted|per\s+(?:the\s+)?(?:quotation|quote|offer))\b/gi, '').replace(/\bquoted\s+by\b\s*/gi, '');
  return clean(x);
}
/** A sentence-list field (summary, missing_info): sentences about the old offer's terms go whole, the rest is scrubbed. */
const scrubSentences = (s: unknown, t: QuotationTerms) => clean(String(s ?? '').split(/(?<=[.;!?])\s+/).filter((u) => !TERMS_SENTENCE.test(u)).map((u) => scrubQuotationText(u, t)).filter(Boolean).join(' '));

/** A customer-authored sentence on a request built from a quotation (the summary): money and commercial-terms sentences out. */
export const quotationProse = (s: unknown) => scrubSentences(s, { parties: [], refs: [], prefixes: [] });

/** The old supplier's terms the request keeps for its own doors (customer-only spec key old_supplier_terms): compact, capped. */
export const termsToKeep = (t: QuotationTerms) => [...new Set([...t.parties, ...t.refs])].filter((x) => x.length >= 4 && x.length <= 80).slice(0, 80);

// deno-lint-ignore no-explicit-any
type Line = Record<string, any>;
/** The whole reading of a priced document, rebuilt as our inquiry (idempotent: running it twice changes nothing). */
// deno-lint-ignore no-explicit-any
export function quotationGate<B extends Record<string, any>>(boq: B, t: QuotationTerms): B {
  if (!boq || typeof boq !== 'object') return boq;
  const lines: Line[] = Array.isArray(boq.boq) ? boq.boq : [];
  const kept = lines.filter((l) => !TOTAL_ROW.test(String(l?.description ?? l?.item ?? ''))).map((l) => {
    const o: Line = { ...l, basis: QUOTATION_BASIS };
    for (const k of ['section', 'description', 'description_ar', 'section_ar', 'specification', 'brand', 'model', 'notes']) if (typeof o[k] === 'string') o[k] = scrubQuotationText(o[k], t);
    if (typeof o.item === 'string' && !/^\d{1,4}(?:\.\d{1,3})*$/.test(o.item.trim())) o.item = scrubQuotationText(o.item, t);
    for (const k of ['rate', 'unit_price', 'price', 'amount', 'total', 'discount', 'vat']) delete o[k];
    return o;
  }).filter((l) => String(l.description || '').trim());
  const out: Line = { ...boq, boq: kept, document_kind: 'quotation', assumptions: [QUOTATION_NOTE] };
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
