// site_location — the customer's exact site is the customer's, and only the emirate reaches a supplier before a reveal
// (13 Nov 2026, sales_engineer; founder ruling 1683: "Dubai in general is okay. We can keep that. But villa number, for
// example, has to be hidden ... Al Barsha 2, Villa 15 ... Al Barsha and Villa 15 need to be hidden when they are shared
// with the supplier").
//
// WHAT WAS MEASURED (anonymity audit A, 13 Nov 2026, REPORT_A L1). All 3 inquiries in production (all ZZ DEMO) served a
// summary naming the area to every matched supplier ("... in Al Nahda, Sharjah", "... in Khalifa City, Abu Dhabi", "... in
// Business Bay, Dubai"): the intake asked the model for `location: "<area + emirate>"`, and the 35 trades whose checklist
// has a `location` key ("Delivery emirate and address?") stored the address in inquiries.spec, which the supplier inbox
// serves as JSON. Nothing removed an area.
//
// THE CONTRACT, WITH NO SCHEMA CHANGE.
//  * `spec.site_location` holds the exact place (area, community, building, villa or unit, plot, Makani, a landmark) as
//    the customer gave it. It is a CUSTOMER-ONLY key: every supplier door drops it before a reveal (supplierSpec), and
//    the revealed supplier gets it with the rest of the unscrubbed request (supplier_api inbox, `revealed`).
//  * `spec.location` carries the emirate only (create_inquiry splitSite; the door reduces an older row the same way).
//  * The exact place is also a SEED: the words of it are removed wherever they appear in what a supplier receives (the
//    summary, the brief, the BOQ, the e-mail), so an older row whose summary names the area is safe on read, and a
//    careless model that repeats the area in the summary is caught by the customer's own words. A place the customer
//    never stated in a site field is left to the shared text backstop (identity_text.ts, a separate change).
//
// prevented by: supplier_api/nothing_below_the_emirate_reaches_a_supplier.test.ts

import { norm } from './anonymise.ts';

export const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Fujairah', 'Umm Al Quwain'] as const;
/** The keys a supplier never receives before a reveal. */
// old_supplier_terms: the names and references of the old supplier read from a customer's existing quotation (customer_api
// analyze_drawing, drawing_boq/quotation_gate.ts termsToKeep). Kept so every door removes them from the customer's own text
// too (a summary that says "as quoted by Falcon Trading"); never shown to a supplier.
export const CUSTOMER_ONLY_SPEC_KEYS = ['site_location', 'old_supplier_terms'] as const;
/** The checklist key whose question is "Delivery emirate and address?": a supplier is given its emirate only. */
export const ADDRESS_KEY = 'location';

// An emirate, the country, or a word that names no place of its own, in English or Arabic.
const NOT_A_PLACE = new RegExp('^(?:' + [
  'dubai', 'abu ?dhabi', 'sharjah', 'ajman', 'ras al ?khaimah', 'rak', 'fujairah', 'umm al ?quwain', 'uaq',
  'uae', 'u a e', 'united arab emirates', 'emirates', 'the uae', 'emirate of [a-z ]+', '[a-z ]+ emirate',
  'دبي', 'ابوظبي', 'ابو ظبي', 'الشارقه', 'عجمان', 'راس الخيمه', 'الفجيره', 'ام القيوين', 'الامارات', 'الامارات العربيه المتحده',
  // a kind of site is not a place: a supplier needs it and it names nobody
  'villa', 'a villa', 'apartment', 'an apartment', 'flat', 'office', 'warehouse', 'shop', 'site', 'home', 'house', 'building',
  'فيلا', 'شقه', 'مكتب', 'مستودع', 'محل',
].join('|') + ')$');
// A level or a floor is what a supplier prices access by ("ground floor", "3rd floor", "G+1", "level 4"), never a place.
const A_LEVEL = /^(?:(?:the\s+)?(?:ground|first|second|third|top|\d+(?:st|nd|rd|th)?)\s+floor|floor\s*\d+|level\s*\d+|g\s*\+\s*\d+|basement|roof|mezzanine)$/i;

/** The place words of one stated site, below the emirate: "Villa 15, Al Barsha 2, Dubai" -> ["Villa 15", "Al Barsha 2"]. */
export function siteParts(value: unknown): string[] {
  const out: string[] = [];
  const add = (v: unknown) => {
    if (v == null) return;
    if (Array.isArray(v)) { v.forEach(add); return; }
    if (typeof v === 'object') { Object.values(v as Record<string, unknown>).forEach(add); return; }
    // "Dubai (near Mall of the Emirates)": a bracketed place is a place of its own
    for (let part of String(v).replace(/\(([^)]*)\)/g, ', $1, ').split(/\s*(?:[,;،\n|]|\s-\s|\s–\s)\s*/)) {
      part = part.replace(/^(?:near|next to|opposite|behind|close to|in|at|beside|بالقرب من|قرب|في|مقابل)\s+/i, '').replace(/[()"'.]+/g, ' ').replace(/\s+/g, ' ').trim();
      const n = norm(part);
      if (n.length < 3 || NOT_A_PLACE.test(n) || A_LEVEL.test(part)) continue;
      // "Al Barsha 2, Dubai" said as "Al Barsha 2 Dubai": the emirate at the end is not part of the place
      const bare = part.replace(new RegExp('\\s+(?:' + EMIRATES.join('|') + '|UAE)$', 'i'), '').trim();
      if (bare.length >= 3 && !NOT_A_PLACE.test(norm(bare))) out.push(bare);
    }
  };
  add(value);
  return [...new Set(out)];
}

/** True when a stated location says anything below the emirate. */
export const belowEmirate = (value: unknown) => siteParts(value).length > 0;

/** The emirate a stated location names, if exactly one of the seven: "Al Barsha 2, Dubai" -> "Dubai". */
export function emirateIn(value: unknown): string | null {
  const t = norm(String(value ?? ''));
  const hit = EMIRATES.filter((e) => new RegExp('(?:^|\\s)' + norm(e).replace(/ /g, '\\s?') + '(?:\\s|$)').test(t));
  return hit.length === 1 ? hit[0] : null;
}

/** The customer's stated site, from the customer-only key and from an older row's address key. */
export function statedSite(spec: unknown): unknown[] {
  if (!spec || typeof spec !== 'object') return [];
  const s = spec as Record<string, unknown>;
  return [s.site_location, s[ADDRESS_KEY]].filter((v) => v != null && String(v).trim() !== '');
}

/**
 * Seeds for _shared/anonymise redactBoq, in its normalised form: each place phrase, the phrase without its trailing
 * number ("al barsha 2" -> "al barsha"), and without its leading "al" when what is left is a word of five letters or
 * more ("barsha"). A phrase is never split into single words: "Industrial Area 13" must not erase "industrial" from a
 * line of epoxy paint, so the words travel together.
 */
export function siteSeeds(spec: unknown, extra: unknown[] = []): string[] {
  const out = new Set<string>();
  for (const p of siteParts([...statedSite(spec), ...extra])) {
    const n = norm(p);
    if (n.length >= 4) out.add(n);
    const noNum = n.replace(/\s+\d+[a-z]?$/, '').trim();
    if (noNum !== n && noNum.length >= 4 && !NOT_A_PLACE.test(noNum)) out.add(noNum);
    const noAl = noNum.replace(/^(?:al|el|ال)\s+/, '').trim();
    if (noAl !== noNum && noAl.length >= 5 && !NOT_A_PLACE.test(noAl)) out.add(noAl);
  }
  return [...out].sort((a, b) => b.length - a.length);
}

/**
 * The brief as a supplier receives it before a reveal: the customer-only keys dropped, the address key reduced to the
 * emirate ("[site details withheld]" with no emirate). Every other key is unchanged (quantities, levels, finishes).
 */
export function supplierSpec<T>(spec: T, emirate: string | null | undefined): T {
  if (!spec || typeof spec !== 'object' || Array.isArray(spec)) return spec;
  const o: Record<string, unknown> = { ...(spec as Record<string, unknown>) };
  for (const k of CUSTOMER_ONLY_SPEC_KEYS) delete o[k];
  if (o[ADDRESS_KEY] != null && belowEmirate(o[ADDRESS_KEY])) o[ADDRESS_KEY] = emirate || emirateIn(o[ADDRESS_KEY]) || '[site details withheld]';
  return o as T;
}

/**
 * At create_inquiry: the exact place goes under the customer-only key and the address key keeps the emirate. The
 * intake's own `site_location` (the model was asked for it) wins; else an address key that says more than the emirate
 * is moved there whole, so the customer and the revealed supplier keep every word of it.
 */
export function splitSite(spec: Record<string, unknown>, emirate: string | null | undefined, briefSite?: unknown): Record<string, unknown> {
  const o = { ...spec };
  const stated = [briefSite, o.site_location, belowEmirate(o[ADDRESS_KEY]) ? o[ADDRESS_KEY] : null].filter((v) => v != null && String(v).trim() !== '').map((v) => String(v).trim());
  if (stated.length) o.site_location = [...new Set(stated)].join('; ').slice(0, 300);
  if (o[ADDRESS_KEY] != null && belowEmirate(o[ADDRESS_KEY])) o[ADDRESS_KEY] = emirate || emirateIn(o[ADDRESS_KEY]) || '[site details withheld]';
  return o;
}

/** After redaction: "Kitchen fit-out in █, Dubai" reads "Kitchen fit-out in Dubai"; a mark that stands alone stays. */
export function tidyWithheld(s: string): string {
  return String(s ?? '')
    .replace(/█(?:\s*[,;]?\s*█)+/g, '█')
    .replace(/█(?:[\s,]*█)*\s*,\s*(?=(?:Dubai|Abu Dhabi|Sharjah|Ajman|Ras Al Khaimah|Fujairah|Umm Al Quwain|UAE)\b)/gi, '')
    .replace(/\s{2,}/g, ' ').replace(/\s+([,.;])/g, '$1').trim();
}
