// quotation_parties — who a PRICED document (a competitor's quotation, a proforma, an offer) names, read from the
// words AROUND its table, so none of them reaches a supplier (10 Nov 2026, sales_engineer; founder 10 Nov: a
// competitor's quotation a customer uploads is treated as an inquiry, with names and prices removed and rebuilt in
// our template).
//
// WHY. boqFromRows never reads a rate, price or amount column, and scrubIdentity removes contact SHAPES (phones,
// e-mails, TRNs, IBANs, firm suffixes). What neither knew is the competitor's NAME without its suffix and the
// customer's name and project as the quotation writes them ("To: ZZ DEMO Rashid Kareem", "Project: ZZ DEMO Palm
// Villa 14, Al Barsha South"). A description that repeats one ("as per Gulf Fitout standard detail", "Palm Villa
// boundary wall") would carry it to every supplier. These are the terms; the callers remove them from every string.
//
// WHERE IT LOOKS. Only the letterhead, the address block and the signature: the lines OUTSIDE the priced table (the
// caller passes them). There a labelled value (To / Attn / M/s / Client / Project / Site / Quotation No / From / For
// ...), a line naming a firm (LLC, FZE, Trading, Contracting, Est., شركة ...), the letterhead's first line, and a
// person before a job title ("ZZ DEMO Sameer Nasser, Sales Manager") are terms.
//
// WHAT IT NEVER DOES. Read the table: a brand in a Brand column (RAK Ceramics, Knauf) is a specification the
// supplier needs, not a party.

const LABEL = /^\s*(?:to|attn|attention|kind(?:ly)?\s*attn\.?|m\/s|messrs\.?|from|client|customer|company|consultant|contractor|developer|owner|project(?:\s*(?:name|title))?|site(?:\s*address)?|location|address|subject|prepared\s*(?:for|by)|sales\s*(?:person|engineer|manager|executive)|contact(?:\s*person)?|(?:quotation|quote|offer|proforma|tender|enquiry|inquiry)\s*(?:no\.?|number|ref\.?)|our\s*ref\.?|your\s*ref\.?|ref(?:erence)?\s*(?:no\.?)?|for(?:\s*and\s*on\s*behalf\s*of)?|المالك|العميل|السادة|الموقع|المشروع|اسم\s*المشروع|العنوان|الموضوع)\s*[:：.]?\s+(.{3,120})$/i;
const FIRM = /\b(?:l\.?l\.?c|fze|fzco|fz-llc|est\.?|establishment|trading|contracting|contractors?|engineering|interiors?|fit-?out|group|holding|co\.|company|ltd|limited|inc|plc|gmbh)\b|ذ\.?م\.?م|مؤسس[ةه]|شرك[ةه]/i;
const TITLE = /\b(?:manager|engineer|director|estimator|executive|officer|coordinator|consultant|surveyor|sales|proprietor|partner|ceo|gm)\b/i;
/** Words that say WHAT, never WHO: a term made only of these is dropped. */
const GENERIC = /^(?:dubai|abu\s*dhabi|sharjah|ajman|uae|u\.a\.e\.?|united\s*arab\s*emirates|p\.?\s*o\.?\s*box|tel|fax|mob(?:ile)?|e-?mail|www|date|quotation|interior\s*fit-?out\s*works|fit-?out\s*works|works|supply|installation|[\d\s.\/-]+)$/i;

/** The party, project and job terms a priced document states outside its table. Longest first. */
export function quotationPartyTerms(outsideTable: string[]): string[] {
  const out = new Set<string>();
  const add = (v: string) => {
    for (const part of v.split(/\s*[|,;•]\s*|\s{3,}/)) {
      const t = part.replace(/^(?:tel|mob(?:ile)?|e-?mail|date|trn)\b.*$/i, '').replace(/\s*\(.*?\)\s*/g, ' ').trim();
      if (t.length >= 4 && !GENERIC.test(t) && /[\p{L}]/u.test(t)) out.add(t);
    }
  };
  const lines = outsideTable.map((l) => String(l || '').replace(/\s+/g, ' ').trim()).filter(Boolean);
  if (lines.length && !LABEL.test(lines[0])) add(lines[0]);                 // the letterhead's own name
  for (const l of lines) {
    const m = LABEL.exec(l);
    if (m) { add(m[1]); continue; }
    if (FIRM.test(l)) add(l);
    const p = /^([^,]{4,60}),\s*([^,]{3,40})/.exec(l);                     // "Name, Sales Manager, +971 ..."
    if (p && TITLE.test(p[2])) add(p[1]);
  }
  // A description repeats a name in part ("Palm Villa ground floor" for "ZZ DEMO Palm Villa 14"): every run of two or
  // more of a term's words that holds a proper word of its own is a term too.
  for (const t of [...out]) {
    const w = t.split(/\s+/);
    for (let i = 0; i < w.length; i++) for (let j = i + 2; j <= w.length; j++) {
      const g = w.slice(i, j);
      if (g.length === w.length) continue;
      if (g.some((x) => /^[\p{Lu}][\p{L}'-]{3,}$/u.test(x) && !COMMON.test(x))) out.add(g.join(' '));
    }
  }
  return [...out].sort((a, b) => b.length - a.length);
}
/** A capitalised word that is a firm's legal form, a place or a demo marker, not a name of its own. */
const COMMON = /^(?:demo|contracting|contractors?|trading|establishment|company|limited|group|holding|engineering|interiors?|fitout|services|dubai|sharjah|ajman|emirates|south|north|east|west|street|road|tower|building|villa|floor|sales|manager|engineer|mobile)$/i;

/** A priced document: a price column (or a rate written in the text) together with the words a quotation is titled by. */
export const isQuotation = (text: string, priced: boolean) => priced && /\b(?:quotation|quote|proforma|offer|tender|estimate)\b|عرض\s*(?:سعر|أسعار)/i.test(text);

export const QUOTATION_NOTE = 'This is another supplier\'s priced quotation, rebuilt as our inquiry: items, quantities, units and specifications only - no rate, price, amount, total or VAT, and no party name, contact or project name was read.';

/** Remove each term (whole phrase, case-insensitive) from a string. */
export function scrubTerms(s: string, terms: string[]): string {
  let t = String(s || '');
  for (const v of terms) { if (v.length < 4) continue; t = t.replace(new RegExp(v.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '\\s+'), 'gi'), ''); }
  return t.replace(/\s{2,}/g, ' ').replace(/^[\s,;:-]+|[\s,;:-]+$/g, '').trim();
}
