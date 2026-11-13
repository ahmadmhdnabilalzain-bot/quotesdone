// site_location — the customer's exact site is the customer's, and only the emirate reaches a supplier before a reveal
// (13 Nov 2026, sales_engineer; founder ruling 1683: "Dubai in general is okay. We can keep that. But villa number, for
// example, has to be hidden ... Al Barsha 2, Villa 15 ... Al Barsha and Villa 15 need to be hidden when they are shared
// with the supplier").
//
// WHAT WAS MEASURED (anonymity audit A, 13 Nov 2026, REPORT_A L1). All 3 inquiries in production (all ZZ DEMO) served a
// summary naming the area to every matched supplier ("... in Al Nahda, Sharjah", "... in Khalifa City, Abu Dhabi", "... in
// Business Bay, Dubai"), and the checklist answers that ask where the job is went to the supplier inbox whole.
//
// THE CONTRACT, WITH NO SCHEMA CHANGE.
//  * Every checklist answer that asks WHERE (asksWhere: the question names an emirate, an address, a community, a plot or
//    Makani, or access limits) is an ADDRESS KEY. Read from production category_specs on 13 Nov 2026 (396 fields), the
//    named ones are ADDRESS_KEYS below; a field with no key of its own (the deterministic interview calls it field_N) is
//    recorded per request at create_inquiry under `site_keys`. scripts/checks/every_checklist_question_that_asks_where_is_an_address_key.test.mjs
//    fails when a new checklist key asks where and is not on the list.
//  * An address answer is REDUCED (reducePlace): it keeps the emirate, a level or floor ("3rd floor", "G+1", "roof"), a kind
//    of site ("apartment", "warehouse"), a measure ("350 m2", "5 rooms") and the access words a supplier prices by ("no
//    lift", "narrow stairs"); every other part is a place and goes, and the whole answer as the customer gave it is kept
//    under the CUSTOMER-ONLY key `site_location`. Allowlist, so an unknown word fails closed.
//  * The dropped place phrases are SEEDS: removed wherever they appear in what a supplier receives. A seed is the phrase with
//    its number ("unit 1204", "al barsha 2"), and a shorter form only when a distinctive name is left ("barsha"); never a
//    bare premises word ("unit", "tower", "gate", "springs"): measured by the review of 13 Nov 2026, "Unit 1204, Tower 2"
//    erased "unit" from "Split AC units" and "tower" from "Cooling tower motor".
//  * The revealed supplier gets the brief whole, `site_location` with it (supplier_api inbox, the projects card).
//
// prevented by: supplier_api/nothing_below_the_emirate_reaches_a_supplier.test.ts

import { norm } from './anonymise.ts';

export const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Fujairah', 'Umm Al Quwain'] as const;
/** The emirate a browser sent, as one of the seven, or null (13 Nov 2026: create_inquiry and edit_inquiry took any string). */
export function oneOfSeven(v: unknown): string | null {
  const n = norm(String(v ?? '')).replace(/\s+/g, '');
  return EMIRATES.find((e) => norm(e).replace(/\s+/g, '') === n) ?? null;
}
/** The keys a supplier never receives before a reveal: the exact site, the old supplier's terms, and the list of site keys. */
// old_supplier_terms: the names and references of the old supplier read from a customer's existing quotation (customer_api
// analyze_drawing, drawing_boq/quotation_gate.ts termsToKeep); never shown to any supplier, revealed or not.
export const CUSTOMER_ONLY_SPEC_KEYS = ['site_location', 'old_supplier_terms', 'site_keys'] as const;
/** The named checklist keys whose question asks where (production category_specs, 13 Nov 2026; see asksWhere). */
export const ADDRESS_KEYS = ['access', 'access_constraints', 'emirate', 'emirate_access', 'emirate_building', 'emirate_location', 'from_to',
  'location', 'location_area', 'location_floor', 'property', 'property_location'] as const;

/** A checklist question that asks where the job is (or how to reach it): the classifier ADDRESS_KEYS was derived with. */
export function asksWhere(f: { key?: unknown; question?: unknown; question_plain_en?: unknown; label?: unknown }): boolean {
  const q = [f.question, f.question_plain_en, f.label].map((x) => String(x ?? '')).join(' ');
  return /\b(?:emirates?|address|community|plot\s+number|makani|district|neighbou?rhood)\b|\baccess\s+(?:constraints?|method|limits?|restrictions?)\b|\blift\/access\b/i.test(q)
    || /(?:^|_)(?:location|address|emirate)(?:_|$)/i.test(String(f.key ?? ''));
}

// ── what an address answer may keep ─────────────────────────────────────────────────────────────────────────
const EMIRATE_RE = /^(?:dubai|abu\s?dhabi|sharjah|ajman|ras\s?al\s?khaimah|rak|fujairah|umm\s?al\s?quwain|uaq|uae|u\s?a\s?e|united\s+arab\s+emirates|the\s+uae|دبي|ابو\s?ظبي|الشارقه|عجمان|راس\s?الخيمه|الفجيره|ام\s?القيوين|الامارات(?:\s?العربيه\s?المتحده)?)$/i;
// A level or a floor is what a supplier prices access by ("ground floor", "3rd floor", "G+1", "level 4", "roof").
const LEVEL = /^(?:(?:on\s+)?(?:the\s+)?(?:ground|first|second|third|fourth|fifth|top|upper|lower|\d+(?:st|nd|rd|th)?)\s+(?:floor|level)|(?:floor|level)\s*\d+|g\s*\+\s*\d+|basement(?:\s*\d)?|roof(?:\s*top)?|mezzanine|ground)$/i;
// A measure: area, size, counts of rooms, floors, units ("350 m2", "5 bedrooms", "3 floors", "2 units").
const MEASURE = /^\d[\d.,]*\s*(?:x\s*\d[\d.,]*\s*)?(?:m2|m²|sqm|sq\.?\s?m|sqft|sq\.?\s?ft|ft2|m|mm|cm|ft|rooms?|bedrooms?|bathrooms?|br|floors?|storeys?|stories|levels?|units?|zones?|bays?|halls?|people|persons|staff|kw|tr|tons?)$/i;
// The words a supplier prices by and that name nobody: kinds of site, access, timing, condition.
const PLAIN = new Set(norm(`a an the of and or with without no not only on in at to for by is are has have there its very
  villa villas apartment apartments flat flats penthouse townhouse duplex studio office offices warehouse warehouses shop shops store
  showroom restaurant cafe kitchen hotel school clinic gym garage factory workshop labour camp camps building buildings tower high rise
  low rise residential commercial industrial retail private compound mall unit house home site plot land roof floor ground basement
  occupied empty vacant new existing old under construction fitted shell core furnished
  lift lifts elevator elevators service passenger goods stairs staircase stair narrow wide small large big crane cranes parking loading
  bay dock ramp door doors gate entrance access permit permits security pass working hours night nights day days weekend weekends
  morning mornings evening evenings friday saturday sunday restricted easy difficult limited height width clearance metres meters
  delivery pickup install installation storey storeys floors levels back front rear side main entry exit outside inside open covered`).split(' '));

const splitParts = (v: string) => String(v).replace(/\(([^)]*)\)/g, ', $1, ').split(/\s*(?:[,;،\n|]|\s-\s|\s–\s|\bnear\b|\bnext to\b|\bopposite\b|\bbehind\b|\bclose to\b|\bbeside\b|بالقرب من|قرب|مقابل)\s*/i)
  .map((p) => p.replace(/[()"'.]+/g, ' ').replace(/\s+/g, ' ').trim()).filter(Boolean);
/** A part of an address answer that names nobody: the emirate, a level, a measure, or plain words only. */
function plainPart(p: string): boolean {
  const n = norm(p);
  if (!n || EMIRATE_RE.test(n) || LEVEL.test(p) || MEASURE.test(p)) return true;
  // figures alone are a place (coordinates "25.1123", a Makani or plot number), never a measure without its unit
  if (/^[\d\s.,+/-]+$/.test(p)) return false;
  // a premises word with its number IS a place ("Villa 15", "Unit 1204", "Tower 2", "Gate 3")
  if (/\b[a-z]+\s*(?:no\s*)?\d+[a-z]?\b/i.test(n) && !MEASURE.test(p) && !LEVEL.test(p)) return n.split(' ').every((w) => /^\d+(?:st|nd|rd|th)?$/.test(w) || (PLAIN.has(w) && !/^(?:villa|unit|tower|plot|gate|building|apartment|flat|shop|office|warehouse|house|store)$/.test(w)));
  return n.split(' ').every((w) => PLAIN.has(w) || /^\d+(?:st|nd|rd|th)?$/.test(w) || EMIRATE_RE.test(w));
}

/** An address answer as a supplier may read it: what names nobody, the emirate first. `dropped` are the place phrases. */
export function reducePlace(value: unknown, emirate: string | null | undefined): { value: string; dropped: string[] } {
  const parts = splitParts(String(value ?? ''));
  const kept: string[] = [], dropped: string[] = [];
  for (const p of parts) {
    if (!plainPart(p)) { dropped.push(p); continue; }
    // the emirate is said once, first, as one of the seven
    if (EMIRATE_RE.test(norm(p))) continue;
    kept.push(p);
  }
  const em = oneOfSeven(emirate) || emirateIn(value);
  const head = em ? [em] : (dropped.length ? ['[site details withheld]'] : []);
  return { value: [...head, ...kept].join(', '), dropped };
}

/** The place phrases of one stated site, below the emirate: "Villa 15, Al Barsha 2, Dubai" -> ["Villa 15", "Al Barsha 2"]. */
export function siteParts(value: unknown): string[] {
  const out: string[] = [];
  const add = (v: unknown) => {
    if (v == null) return;
    if (Array.isArray(v)) { v.forEach(add); return; }
    if (typeof v === 'object') { Object.values(v as Record<string, unknown>).forEach(add); return; }
    for (const p of reducePlace(String(v), null).dropped) {
      const bare = p.replace(new RegExp('\\s+(?:' + EMIRATES.join('|') + '|UAE)$', 'i'), '').replace(/^(?:in|at|the)\s+/i, '').trim();
      if (bare.length >= 3) out.push(bare);
    }
  };
  add(value);
  return [...new Set(out)];
}

/** True when a stated answer says anything below the emirate. */
export const belowEmirate = (value: unknown) => reducePlace(value, null).dropped.length > 0;

/** The emirate a stated location names, if exactly one of the seven: "Al Barsha 2, Dubai" -> "Dubai". */
export function emirateIn(value: unknown): string | null {
  const t = norm(String(value ?? ''));
  const hit = EMIRATES.filter((e) => new RegExp('(?:^|\\s)' + norm(e).replace(/ /g, '\\s?') + '(?:\\s|$)').test(t));
  return hit.length === 1 ? hit[0] : null;
}

/** A trade's checklist questions that ask where and carry no key of their own, by the key the interview gives them (field_N). */
export function keylessPlaceKeys(fields: unknown): string[] {
  return Array.isArray(fields) ? fields.flatMap((f, i) => (f && typeof f === 'object' && !(f as { key?: unknown }).key && asksWhere(f as Record<string, unknown>) ? ['field_' + (i + 1)] : [])) : [];
}

/** The address keys of one brief: the named ones, and the keys create_inquiry recorded for this request (site_keys). */
export function addressKeysOf(spec: Record<string, unknown>): string[] {
  const own = Array.isArray(spec.site_keys) ? spec.site_keys.map(String) : [];
  // and any key the model named for a place question of its own (a keyless "Emirate / area" field is written as it likes)
  const named = Object.keys(spec).filter((k) => /(?:^|_)(?:location|address|emirate|community|site_area)(?:_|$)/i.test(k) && !(CUSTOMER_ONLY_SPEC_KEYS as readonly string[]).includes(k));
  return [...new Set([...ADDRESS_KEYS, ...own, ...named])].filter((k) => k in spec);
}

/** The customer's stated site: the customer-only key and every address answer. */
export function statedSite(spec: unknown): unknown[] {
  if (!spec || typeof spec !== 'object') return [];
  const s = spec as Record<string, unknown>;
  return [s.site_location, ...addressKeysOf(s).map((k) => s[k])].filter((v) => v != null && String(v).trim() !== '');
}

// A premises or common word is never a seed on its own (review of 13 Nov 2026, item 7).
const COMMON = new Set(norm(`unit units tower towers block blocks gate gates street st road rd phase cluster sector zone hall room rooms store
  springs lakes meadows villa villas apartment apt flat building plot office shop floor level area community district city park garden
  gardens heights height view views residence residences complex compound village square plaza centre center mall marina bay island
  islands hills hill creek downtown industrial south north east west new old the of al el greens ranches arabian business sports
  international media internet silicon oasis jumeirah فيلا رقم شقه برج مبني مكتب منطقه شارع`).split(' '));
const distinctive = (n: string) => n.length >= 5 && n.split(' ').some((w) => w.length >= 4 && !COMMON.has(w) && !/^\d/.test(w));

/**
 * Seeds for _shared/anonymise redactBoq, in its normalised form: each place phrase as said ("unit 1204", "al barsha 2"); the
 * phrase without its trailing number and without a leading "al" only when a distinctive name is left ("al barsha", "barsha").
 */
export function siteSeeds(spec: unknown, extra: unknown[] = []): string[] {
  const out = new Set<string>();
  for (const p of siteParts([...statedSite(spec), ...extra])) {
    const n = norm(p);
    // the phrase as said is always a seed, unless it is one premises word alone
    if (n.length >= 4 && !(n.split(' ').length === 1 && COMMON.has(n))) out.add(n);
    // the glued form ("MarsaHeights", "AlBarsha2"): a whole phrase written as one word is the same place
    if (n.includes(' ') && n.replace(/ /g, '').length >= 6) out.add(n.replace(/ /g, ''));
    const noNum = n.replace(/\s+\d+[a-z]?$/, '').trim();
    if (noNum !== n && distinctive(noNum)) out.add(noNum);
    const noAl = noNum.replace(/^(?:al|el|ال)\s+/, '').trim();
    if (noAl !== noNum && distinctive(noAl)) out.add(noAl);
  }
  return [...out].sort((a, b) => b.length - a.length);
}

/**
 * The brief as a supplier receives it before a reveal: the customer-only keys dropped, every address answer reduced.
 * Every other key is unchanged (quantities, levels, finishes).
 */
export function supplierSpec<T>(spec: T, emirate: string | null | undefined): T {
  if (!spec || typeof spec !== 'object' || Array.isArray(spec)) return spec;
  const o: Record<string, unknown> = { ...(spec as Record<string, unknown>) };
  for (const k of addressKeysOf(o)) if (typeof o[k] === 'string' && belowEmirate(o[k])) o[k] = reducePlace(o[k], emirate).value;
  for (const k of CUSTOMER_ONLY_SPEC_KEYS) delete o[k];
  return o as T;
}
/** The brief a REVEALED supplier receives: the customer's site is his now; the old supplier's terms never are. */
export function revealedSpec<T>(spec: T): T {
  if (!spec || typeof spec !== 'object' || Array.isArray(spec)) return spec;
  const o: Record<string, unknown> = { ...(spec as Record<string, unknown>) };
  delete o.old_supplier_terms; delete o.site_keys;
  return o as T;
}

/**
 * At create_inquiry: each address answer that says more than the emirate is kept whole under the customer-only key and
 * reduced in place. `extraKeys` are this category's keyless place questions (field_N), recorded under `site_keys`.
 */
export function splitSite(spec: Record<string, unknown>, emirate: string | null | undefined, briefSite?: unknown, extraKeys: string[] = []): Record<string, unknown> {
  const o: Record<string, unknown> = { ...spec };
  if (extraKeys.length) o.site_keys = [...new Set([...(Array.isArray(o.site_keys) ? o.site_keys.map(String) : []), ...extraKeys])];
  const stated: string[] = [briefSite, o.site_location].filter((v) => v != null && String(v).trim() !== '').map((v) => String(v).trim());
  for (const k of addressKeysOf(o)) {
    if (typeof o[k] !== 'string' || !belowEmirate(o[k])) continue;
    stated.push(String(o[k]).trim());
    o[k] = reducePlace(o[k], emirate).value;
  }
  if (stated.length) o.site_location = [...new Set(stated)].join('; ').slice(0, 400);
  return o;
}

const EM = '(?:Dubai|Abu Dhabi|Sharjah|Ajman|Ras Al Khaimah|Fujairah|Umm Al Quwain)';
/** After redaction the sentence still reads: "Kitchen fit-out in █, Dubai" -> "in Dubai"; "at [removed]" -> "in Dubai". */
export function tidyWithheld(s: string, emirate?: string | null): string {
  const em = oneOfSeven(emirate);
  let t = String(s ?? '')
    .replace(/(?:█|\[removed\])(?:\s*[,;]?\s*(?:█|\[removed\]))+/g, '█')
    .replace(new RegExp(`(?:█|\\[removed\\])\\s*,\\s*(?=(?:${EM}|UAE)\\b)`, 'g'), '');
  // a place withheld at the end of a phrase: "at █" / "in [removed]" reads "in <emirate>" (or goes, with no emirate)
  t = t.replace(/\b(?:at|in|near|on|for|of|from)\s+(?:the\s+)?(?:█|\[removed\])(?=\s*(?:[.;,)]|$))/gi, em ? `in ${em}` : '');
  return t.replace(new RegExp(`\\bin ${EM}(?:,?\\s*in ${EM})+`, 'g'), (m) => m.replace(/,?\s*in .*$/, '')).replace(/\s{2,}/g, ' ').replace(/\s+([,.;])/g, '$1').trim();
}

/** What the customer is told when his words are kept from the suppliers (rfq_note, add_missing_specs, clarify_answer). */
export const KEPT_FROM_SUPPLIERS = {
  en: 'Your answer names your site or your contact details, so it is kept with your request and not sent to the suppliers. They see the emirate only; your exact site goes to the supplier whose quotation you open.',
  ar: 'إجابتك تذكر موقعك أو بيانات تواصلك، لذا حُفظت مع طلبك ولم تُرسل إلى المورّدين. يرى المورّدون الإمارة فقط، ويصل موقعك الدقيق إلى المورّد الذي تفتح عرضه.',
};
