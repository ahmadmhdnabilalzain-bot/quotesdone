// brand_facts.mjs — the brand table the quotation generaliser reads, DERIVED FROM THE PACKS (10 Nov 2026,
// sales_engineer; founder ledger 1588-1590).
//
// WHY. A quotation shown to the customer before the reveal must not name a brand, a model or a product line
// that points to one or two suppliers; each is replaced by a FACTUALLY CORRECT generic description that keeps
// origin and tier ("premium German brand mixer"). The generaliser can only do that for a brand it knows, and the
// estate already knows them: every knowledge/packs/<trade>.market.json carries a uae_market_brands entry naming
// the brands sold in the UAE for that trade (219 of 220 packs, measured 10 Nov 2026). Their ORIGIN and TIER are
// not stated there per brand yet (two parallel branches, sales_engineer-expert-knowledge-k1/k2, are adding them),
// so knowledge/brands/origin_and_tier.json holds an explicit table meanwhile. This script merges the two:
//
//   1. every name the packs list (a comma list after a colon in body_en, and "Name (Country)" sentences),
//   2. an origin stated BY THE PACK — a structured `brands: [{name, origin, tier}]` array on the entry (the k1/k2
//      shape) or a country in brackets right after the name ("Ashok Leyland (India)") — wins,
//   3. otherwise the explicit table's origin and tier,
//   4. otherwise origin null and tier null: the generaliser then writes "branded", never a guessed origin.
//
//   node scripts/kb/brand_facts.mjs            # write supabase/functions/_shared/brand_facts.generated.ts
//   node scripts/kb/brand_facts.mjs --check    # exit 1 when the committed file is not what the packs give now
//
// prevented by: scripts/checks/the_brand_table_is_what_the_packs_say.test.mjs (runs --check, and asserts the
// table's own facts: no origin outside ISO-2, no tier outside the three words, the founder's own example present).
import { readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const PACKS = join(REPO, 'knowledge', 'packs');
const TABLE = join(REPO, 'knowledge', 'brands', 'origin_and_tier.json');
const OUT = join(REPO, 'supabase', 'functions', '_shared', 'brand_facts.generated.ts');

// Country names a pack writes in brackets after a make, to ISO-2. Only these are read as an origin.
export const COUNTRY = {
  germany: 'DE', italy: 'IT', spain: 'ES', france: 'FR', japan: 'JP', china: 'CN', india: 'IN', 'united states': 'US',
  usa: 'US', us: 'US', 'united kingdom': 'GB', uk: 'GB', britain: 'GB', turkey: 'TR', türkiye: 'TR', korea: 'KR',
  'south korea': 'KR', uae: 'AE', 'united arab emirates': 'AE', 'saudi arabia': 'SA', switzerland: 'CH', sweden: 'SE',
  denmark: 'DK', norway: 'NO', finland: 'FI', netherlands: 'NL', belgium: 'BE', austria: 'AT', taiwan: 'TW',
  canada: 'CA', australia: 'AU', ireland: 'IE', egypt: 'EG', jordan: 'JO', oman: 'OM', thailand: 'TH', vietnam: 'VN',
  malaysia: 'MY', indonesia: 'ID', poland: 'PL', portugal: 'PT', 'czech republic': 'CZ', israel: 'IL', brazil: 'BR',
  mexico: 'MX', singapore: 'SG', pakistan: 'PK', 'new zealand': 'NZ', liechtenstein: 'LI',
};
const ISO2 = new Set(Object.values(COUNTRY));
// A nationality is an origin, never a make ("Chinese and Malaysian producers" listed "Malaysian" as a brand, and the
// generaliser then read "Malaysian origin" as a brand name and lost the origin the customer asked for).
const NATIONALITY = /^(?:german|italian|spanish|french|japanese|chinese|indian|american|british|english|turkish|korean|emirati|saudi|swiss|swedish|danish|norwegian|finnish|dutch|belgian|austrian|taiwanese|canadian|australian|irish|egyptian|jordanian|omani|thai|vietnamese|malaysian|indonesian|polish|portuguese|czech|israeli|brazilian|mexican|singaporean|pakistani|european|asian|african|arab|arabic|gulf|local|regional|gcc|bangladeshi|sri lankan|filipino|kuwaiti|qatari|bahraini|iranian|russian|ukrainian|romanian|greek|hungarian)(?:\s+(?:and|or)\s+\w+)?$/i;
const TIERS = new Set(['premium', 'mid-range', 'economy']);

// Words a list carries that are not a brand: places the packs name, generic groups, and connective words.
const NOT_A_BRAND = /^(?:the|and|or|plus|other|others|many|local|regional|international|imported|chinese|indian|european|turkish|gcc|uae|dubai|sharjah|abu dhabi|ajman|fujairah|ras al khaimah|umm al quwain|al ain|deira|al quoz|musaffah|mussafah|jebel ali|jafza|icad|naif|al ras|ras al khor|al qusais|dragon mart|business bay|bur dubai|hamriyah|ruwais|kizad|dafza|dmcc|rakez|ifza|europe|asia|china|india|turkey|germany|italy|spain|japan|korea|usa|uk|origins?|brands?|makers?|suppliers?|distributors?)$/i;
// "Origins: UAE, Germany, ..." and "Distribution clusters in: ..." are lists of places, not of brands.
const PLACE_LIST = /(origins?|sourced from|imported from|come[s]? from|clusters?|concentrated|markets? include|areas?|located|operate[s]? in|based in)\s*:?\s*$/i;

/** The names one uae_market_brands entry lists, with any origin the pack itself states. */
export function namesOf(entry) {
  const out = new Map();   // name -> { origin, tier, from }
  const add = (raw, origin = null, tier = null, from = 'pack_list') => {
    let name = String(raw || '').replace(/\s+/g, ' ').replace(/^(?:and|plus|or|the)\s+/i, '').replace(/[.;:]+$/, '').trim();
    if (!name || name.length < 2 || name.length > 40) return;
    if (!/^[A-Z0-9ÄÖÜ]/.test(name)) return;                // a name starts with a capital or a digit (3M)
    if (name.split(' ').length > 5 || NOT_A_BRAND.test(name) || NATIONALITY.test(name) || COUNTRY[name.toLowerCase()]) return;
    // A list item that runs on into a sentence ("Ashok Leyland builds trucks", "Ajman for aftermarket brands") is not a
    // name: every word of a name is capitalised, a digit, a symbol, or one of the particles brand names carry.
    if (name.split(' ').some((w) => /^[a-z]/.test(w) && !/^(?:de|di|da|del|der|den|van|von|la|le|du|y|e|et|und|&|of)$/.test(w))) return;
    // A place, a zone or a venue the packs name beside the brands ("Dubai Mall", "SAIF Zone", "ICAD").
    if (/\b(?:Zone|Mall|City|Area|Areas|Park|Port|Market|Souk|Industrial|Emirate|Free)\b/.test(name) || /^(?:ICAD|KIZAD|JAFZA|DAFZA|DMCC|RAKEZ|IFZA|SAIF)\b/.test(name)) return;
    const prev = out.get(name);
    if (!prev || (!prev.origin && origin)) out.set(name, { origin: origin ?? prev?.origin ?? null, tier: tier ?? prev?.tier ?? null, from: origin ? from : (prev?.from ?? from) });
  };
  // 1. the structured facts on the entry win over everything read from prose. The knowledge packs of 10 Nov 2026 (k1/k2/k3,
  // ledger 1587) write `brand_origins: [{brand, origin, tier, generic_en, generic_ar}]`; an older shape wrote
  // `brands: [{name, origin, tier}]`. Both are read. Their tier words map onto the generaliser's three: 'mid' is
  // mid-range and 'luxury' is premium. 'dealer', 'operator' and 'supplier' mark a SELLER the pack named, not a make:
  // it gets no origin or tier here (a seller's own name is removed as "the supplier" by quote_generalise, never
  // described as a brand), so it is skipped.
  const TIER_OF = { premium: 'premium', luxury: 'premium', 'mid-range': 'mid-range', mid: 'mid-range', economy: 'economy' };
  const structured = [...(Array.isArray(entry.brand_origins) ? entry.brand_origins : []), ...(Array.isArray(entry.brands) ? entry.brands : [])];
  for (const b of structured) {
    const name = b?.brand ?? b?.name;
    const rawTier = typeof b?.tier === 'string' ? b.tier.toLowerCase().trim() : '';
    if (!name || /^(?:dealer|operator|supplier)$/.test(rawTier)) continue;
    const o = typeof b.origin === 'string' ? (ISO2.has(b.origin.toUpperCase()) ? b.origin.toUpperCase() : COUNTRY[b.origin.toLowerCase().trim()] ?? null) : null;
    const t = TIER_OF[rawTier] ?? null;
    add(name, o, t, 'pack_structured');
  }
  const body = String(entry.body_en || '');
  // 2. "Name (Country)": the pack states where the make is from.
  for (const m of body.matchAll(/([A-Z][\w&+'’-]*(?: [A-Z][\w&+'’-]*){0,3})\s*\(([A-Za-z ]+)\)/g)) {
    const c = COUNTRY[m[2].trim().toLowerCase()];
    if (c) add(m[1], c, null, 'pack_bracket');
  }
  // 3. every comma list after a colon that is not a list of places.
  for (const sentence of body.split(/(?<=\.)\s+(?=[A-Z])/)) {
    const i = sentence.indexOf(':');
    if (i < 0 || PLACE_LIST.test(sentence.slice(0, i))) continue;
    const list = sentence.slice(i + 1).replace(/\.$/, '');
    if (!list.includes(',')) continue;
    // Brackets carry an owner or a sub-brand ("Fertiglobe (ADNOC)", "Arc (Arcoroc, Chef & Sommelier)"): both are names.
    const flat = list.replace(/\(([^)]*)\)/g, (_, inner) => (COUNTRY[inner.trim().toLowerCase()] ? '' : ', ' + inner));
    for (const part of flat.split(/,\s*|\s+and\s+/)) add(part);
  }
  return out;
}

export function build() {
  const table = JSON.parse(readFileSync(TABLE, 'utf8')).brands;
  const facts = new Map();   // lower(name) -> fact
  const conflicts = [];
  for (const f of readdirSync(PACKS).filter((x) => x.endsWith('.market.json')).sort()) {
    const pack = JSON.parse(readFileSync(join(PACKS, f), 'utf8'));
    for (const e of (pack.entries || []).filter((x) => x.kind === 'uae_market_brands')) {
      for (const [name, v] of namesOf(e)) {
        const k = name.toLowerCase();
        const cur = facts.get(k) || { name, origin: null, tier: null, source: 'pack', trades: [] };
        if (!cur.trades.includes(pack.trade)) cur.trades.push(pack.trade);
        if (v.origin && cur.origin && cur.origin !== v.origin) conflicts.push(`${name}: ${cur.origin} vs ${v.origin} (${pack.trade})`);
        if (v.origin && !cur.origin) { cur.origin = v.origin; cur.source = v.from; }
        if (v.tier && !cur.tier) cur.tier = v.tier;
        facts.set(k, cur);
      }
    }
  }
  for (const [name, v] of Object.entries(table)) {
    const k = name.toLowerCase();
    const cur = facts.get(k) || { name, origin: null, tier: null, source: 'table', trades: [] };
    // The pack wins where it states a fact; the table fills what it leaves open.
    if (!cur.origin && v.origin) { cur.origin = v.origin; cur.source = cur.source === 'pack' ? 'pack+table' : cur.source; }
    if (!cur.tier && v.tier) cur.tier = v.tier;
    facts.set(k, cur);
  }
  // A PLAIN WORD (w): a one-word brand that the packs themselves also use as an ordinary lowercase word ("carrier",
  // "interface", "continental", "triangle"). The generaliser takes such a name out of free text only where the text
  // treats it as a make (beside "brand", "make" or a model code), never every time the word is written.
  const words = new Map();
  for (const f of readdirSync(PACKS).filter((x) => x.endsWith('.json')))
    for (const e of (JSON.parse(readFileSync(join(PACKS, f), 'utf8')).entries || []))
      for (const w of String(e.body_en || '').match(/(?<![A-Za-z])[a-z][a-z-]+(?![A-Za-z])/g) || []) words.set(w, (words.get(w) || 0) + 1);
  const PLAIN_ALWAYS = new Set(['man', 'bd', 'york', 'snap', 'axis', 'apple', 'oracle', 'tally', 'sharp', 'brother', 'guardian', 'viking', 'rational', 'carrier', 'continental', 'triangle', 'kale', 'milestone', 'interface', 'publishing', 'aurora', 'stow', 'double a']);
  const rows = [...facts.values()].sort((a, b) => a.name.localeCompare(b.name));
  for (const r of rows) { const l = r.name.toLowerCase(); r.plain = PLAIN_ALWAYS.has(l) || (!l.includes(' ') && (words.get(l) || 0) >= 2); }
  return { rows, conflicts };
}

export function render(rows) {
  const lines = rows.map((r) => `  ${JSON.stringify(r.name)}: { o: ${JSON.stringify(r.origin)}, t: ${JSON.stringify(r.tier)}, s: ${JSON.stringify(r.source)}, w: ${r.plain ? 1 : 0}, tr: ${JSON.stringify(r.trades.slice(0, 6))} },`);
  return `// GENERATED by scripts/kb/brand_facts.mjs from knowledge/packs/*.market.json (uae_market_brands) and
// knowledge/brands/origin_and_tier.json. Do not edit by hand: change the pack or the table and run the script.
// o = origin (ISO 3166 alpha-2, the country the BRAND comes from) or null; t = tier or null; s = where the fact
// came from (pack_structured | pack_bracket | pack | table | pack+table); w = 1 when the name is also a plain word the
// packs write in lowercase (matched in free text only beside "brand"/"make"/a model code); tr = up to six trades.
// ${rows.length} brands, ${rows.filter((r) => r.origin).length} with an origin, ${rows.filter((r) => r.tier).length} with a tier.
export type BrandRow = { o: string | null; t: 'premium' | 'mid-range' | 'economy' | null; s: string; w: 0 | 1; tr: string[] };
export const BRAND_ROWS: Readonly<Record<string, BrandRow>> = {
${lines.join('\n')}
};
`;
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('brand_facts.mjs')) {
  const { rows, conflicts } = build();
  const text = render(rows);
  if (process.argv.includes('--check')) {
    const now = existsSync(OUT) ? readFileSync(OUT, 'utf8') : '';
    if (now !== text) { console.error(`brand_facts.generated.ts is not what the packs and the table give now (${rows.length} brands). Run: node scripts/kb/brand_facts.mjs`); process.exit(1); }
    console.log(`brand_facts.generated.ts is current: ${rows.length} brands, ${rows.filter((r) => r.origin).length} with an origin.${conflicts.length ? ' Pack conflicts: ' + conflicts.join('; ') : ''}`);
  } else {
    writeFileSync(OUT, text);
    console.log(`wrote ${OUT}: ${rows.length} brands, ${rows.filter((r) => r.origin).length} with an origin, ${rows.filter((r) => r.tier).length} with a tier.`);
    if (conflicts.length) console.log('pack conflicts (first pack wins): ' + conflicts.join('; '));
  }
}
