// THE SALES ENGINEER'S REWRITE, PROVED CASE BY CASE. Seat: sales_engineer. 18 Sep 2026; 29 Sep 2026.
//
// The rewrite decides which inquiries reach a supplier, so every rule in service_rewrite.ts is a row in a table
// here. Since 29 Sep 2026 (ruling 890, decision point 93) the rules are: a phrase, or a part of one, that IS a
// service (its key, its code, its English or Arabic name) is that service; nothing else is named here — above all
// not by an alias word inside it. What the rest MEANS is read over the stored vectors by the callers
// (service_meaning.ts, service_vocabulary.test.ts, and the live check
// scripts/checks/services_are_named_by_exact_name_or_meaning_never_by_alias_words.test.mjs). A part no service is
// found for is kept in the supplier's own words and flagged, never dropped and never mapped to a neighbour
// (founder, 14 Sep 2026: "either exact match or no match").
//
//   deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/service_rewrite.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  exactService, flattenImplications, impliedServices, ownWordsOf, rewriteServices, splitPhrases, tidy, withExactTrades,
  type Implication, type ServiceTerm,
} from './service_rewrite.ts';
import ALIASES from './service_aliases.json' with { type: 'json' };
import IMPLICATIONS from './service_implications.json' with { type: 'json' };

// Real names, read from production taxonomy_trade_service on 29 Sep 2026, for the services the name cases use.
const NAMES: Record<string, [string, string]> = {
  'hvac.ducting': ['Ducting & ventilation', 'مجاري الهواء والتهوية'],
  'gypsum.false_ceiling': ['False ceilings', 'الأسقف المعلقة'],
  'gypsum.partitions': ['Gypsum partitions', 'قواطع الجبس'],
  'plumbing.heaters_pumps': ['Water heaters & pumps', 'سخانات ومضخات المياه'],
  'security_systems.cctv': ['CCTV', 'كاميرات المراقبة'],
  'interior_fitout.decoration': ['Interior decoration', 'الديكور الداخلي'],
  'electrical.wiring_install': ['Wiring & electrical installation', 'التمديدات والتركيبات الكهربائية'],
  'painting.interior': ['Interior painting', 'الدهان الداخلي'],
};
// The seed, read the way the edge function reads the database: every active service with its names and aliases.
const SERVICES: ServiceTerm[] = Object.entries(ALIASES as Record<string, { en: string[]; ar: string[] }>)
  .map(([key, v]) => {
    const trade_code = key.slice(0, key.indexOf('.'));
    const code = key.slice(key.indexOf('.') + 1);
    const [label_en, label_ar] = NAMES[key] ?? [code.replace(/_/g, ' ') + ' (service)', 'خدمة ' + code];
    return { trade_code, code, label_en, label_ar, aliases: [...v.en, ...v.ar] };
  });
const MAP: Implication[] = flattenImplications(IMPLICATIONS as { from: string; to: string[]; en: string; ar: string }[]);

const keys = (text: string) => rewriteServices(text, SERVICES).service_keys;
const words = (text: string) => rewriteServices(text, SERVICES).own_words;

// ── 1. what IS a service: its key, its code, its name, written as a whole phrase or list part ──────
const EXACT: { name: string; text: string; expect: string[] }[] = [
  { name: 'the key', text: 'hvac.ducting', expect: ['hvac.ducting'] },
  { name: 'the code as words', text: 'Ducting', expect: ['hvac.ducting'] },
  { name: 'the code with underscores or hyphens', text: 'false_ceiling\nfalse-ceiling', expect: ['gypsum.false_ceiling'] },
  { name: 'the English name, any case', text: 'FALSE CEILINGS', expect: ['gypsum.false_ceiling'] },
  { name: 'the Arabic name', text: 'الأسقف المعلقة', expect: ['gypsum.false_ceiling'] },
  { name: 'the Arabic name, tashkeel and tatweel folded', text: 'الأسقـف المُعلقة', expect: ['gypsum.false_ceiling'] },
  { name: 'a name that holds "&" is read whole first', text: 'Water heaters & pumps', expect: ['plumbing.heaters_pumps'] },
  { name: 'a comma list of names', text: 'CCTV, Gypsum partitions, Interior painting', expect: ['gypsum.partitions', 'painting.interior', 'security_systems.cctv'] },
  { name: 'names joined by "and"', text: 'CCTV and False ceilings', expect: ['gypsum.false_ceiling', 'security_systems.cctv'] },
  { name: 'bullets and numbers', text: '• Ducting\n2) CCTV', expect: ['hvac.ducting', 'security_systems.cctv'] },
  { name: 'duplicates collapse', text: 'CCTV, cctv, security_systems.cctv', expect: ['security_systems.cctv'] },
  // A curated alias, as the WHOLE phrase or list item, is a name (a lookup like fn_norm_trades' slugs).
  { name: 'an English alias, whole', text: 'Cable tray', expect: ['electrical.cable_tray'] },
  { name: 'an Arabic alias, whole', text: 'تمديدات كهربائية', expect: ['electrical.wiring_install'] },
  { name: 'an Arabic alias, whole, diacritics and tatweel folded', text: 'تَمديدات كهربائيـة', expect: ['electrical.wiring_install'] },
];
for (const c of EXACT) {
  Deno.test(`exact: ${c.name}`, () => assertEquals([...keys(c.text)].sort(), [...c.expect].sort(), c.text));
}

Deno.test('every service of the seed is found by its key and by its code, and by nothing but equality', () => {
  const misses: string[] = [];
  for (const s of SERVICES) {
    const k = `${s.trade_code}.${s.code}`;
    if (exactService(k, SERVICES)?.code !== s.code) misses.push(k + ' by key');
    const byCode = exactService(s.code.replace(/_/g, ' '), SERVICES);
    // a code two trades share names neither (exact or none)
    const shared = SERVICES.filter((x) => x.code === s.code).length > 1;
    if (!shared && byCode?.trade_code !== s.trade_code) misses.push(k + ' by code');
    if (shared && byCode) misses.push(k + ': a code two trades share named one of them');
  }
  assertEquals(misses, [], misses.join('\n'));
});

// ── 2. RULING 890: an alias word inside a phrase names NOTHING ─────────────────────────────────────
// Every one of these named a service by an alias until 29 Sep 2026. They are now the supplier's own words,
// for meaning to read (a proposal he confirms) or the sales engineer to map.
const WORDS_ARE_NOT_A_NAME: { name: string; text: string; kept: string[] }[] = [
  { name: 'EN, an alias inside a sentence', text: 'We do ducting.', kept: ['We do ducting'] },
  // prose-shaped as a whole: not an own-words item; the Services tab and serviceKeysOf give it to meaning
  { name: 'EN, an alias inside prose', text: 'Supply and install ducting for the villa', kept: [] },
  { name: 'EN, a plural is not the name', text: 'Cable trays', kept: ['Cable trays'] },
  { name: 'AR, an alias with a proclitic', text: 'نقوم بتمديدات كهربائية', kept: ['نقوم بتمديدات كهربائية'] },
  { name: 'AR, an alias inside a sentence', text: 'مطلوب تمديدات كهربائية للفيلا', kept: ['مطلوب تمديدات كهربائية'] },   // 2 Nov 2026: "للفيلا" (for the villa) is who it is for, not a service
];
for (const c of WORDS_ARE_NOT_A_NAME) {
  Deno.test(`no word matching: ${c.name}`, () => {
    const r = rewriteServices(c.text, SERVICES);
    assertEquals(r.service_keys, [], 'an alias word named a service');
    for (const k of c.kept) assert(r.own_words.includes(k), `expected ${k} in ${JSON.stringify(r.own_words)}`);
  });
}

// A phrase nothing names is kept verbatim and flagged. It is never mapped to something that looks close,
// and it is never dropped.
for (const text of ['Helicopter window polishing', 'تلميع نوافذ المروحيات']) {
  Deno.test(`rewrite keeps the supplier's words: ${text}`, () => {
    const r = rewriteServices(text, SERVICES);
    assertEquals(r.service_keys, []);
    assert(r.items.some((i) => i.kind === 'unmatched' && i.text === text), 'not flagged for the sales engineer');
  });
}

Deno.test('a name and an unknown in the same line both survive', () => {
  const r = rewriteServices('Ducting and helicopter window polishing', SERVICES);
  assertEquals(r.service_keys, ['hvac.ducting']);
  assertEquals(r.own_words, ['Helicopter window polishing']);
});

Deno.test('a supply-only company is never named an installation service, even exactly', () => {
  assertEquals(rewriteServices('Wiring & electrical installation', SERVICES, { supplyOnly: true }).service_keys, []);
  assertEquals(rewriteServices('Wiring & electrical installation', SERVICES).service_keys, ['electrical.wiring_install']);
  assertEquals(rewriteServices('CCTV', SERVICES, { supplyOnly: true }).service_keys, ['security_systems.cctv']);
});

// RULING 890 (29 Sep 2026, ledger 1054). A phrase whose words resemble a trade names no trade; only a phrase that
// IS a code or an intake slug becomes a trade, decided by fn_norm_trades (withExactTrades).
Deno.test('a phrase whose words resemble a trade names no trade; one that IS a code or a slug does, exactly', () => {
  const r = rewriteServices('We are an interior fit out company', SERVICES);
  assertEquals(r.service_keys, []);
  assert(!r.items.some((i) => i.kind === 'trade'), 'a trade was read from words: ' + JSON.stringify(r.items));
  const typed = rewriteServices('Ducting, HVAC, Carpentry, helicopter window polishing', SERVICES);
  assertEquals(ownWordsOf(typed), ['HVAC', 'Carpentry', 'Helicopter window polishing']);
  const x = withExactTrades(typed, { HVAC: ['hvac'], Carpentry: ['joinery'] });
  assertEquals(x.service_keys, ['hvac.ducting']);
  assertEquals(x.items.filter((i) => i.kind === 'trade').map((i) => i.kind === 'trade' ? i.trades : []), [['joinery']]);  // hvac is carried by hvac.ducting
  assertEquals(x.own_words, ['Carpentry', 'Helicopter window polishing']);
  assertEquals(withExactTrades(typed, null), typed, 'no answer from the database changes nothing');
});

// ── 3. tidying and splitting ──────────────────────────────────────────────────────────────────────
Deno.test('tidy: sentence case in English, acronyms kept, Arabic untouched', () => {
  assertEquals(tidy('  HELICOPTER   window   POLISHING '), 'Helicopter window polishing');
  assertEquals(tidy('VRF system servicing'), 'VRF system servicing');
  assertEquals(tidy('  تلميع   نوافذ  '), 'تلميع نوافذ');
  assertEquals(tidy('and ducting,'), 'Ducting');
});
Deno.test('splitPhrases: line breaks, commas, both semicolons, bullets, numbers', () => {
  assertEquals(splitPhrases('a1, b2؛ c3\n• d4\n2) e5'), ['a1', 'b2', 'c3', 'd4', 'e5']);
});
Deno.test('splitPhrases caps a very long text rather than looping over it', () => {
  assert(splitPhrases(Array.from({ length: 200 }, (_, i) => 'phrase' + i).join('\n')).length <= 40);
});
Deno.test('a list item does not keep the Arabic conjunction stuck to its front', () => {
  assertEquals(words('قواطع الجبس، وتلميع نوافذ المروحيات'), ['تلميع نوافذ المروحيات']);
  assertEquals(keys('قواطع الجبس، وتلميع نوافذ المروحيات'), ['gypsum.partitions']);
});
Deno.test('a single Arabic word beginning with و keeps its first letter', () => {
  assertEquals(tidy('وقود'), 'وقود');
  assertEquals(tidy('وكالة'), 'وكالة');
});

// ── 4. the implication map, ONE LEVEL ─────────────────────────────────────────────────────────────
Deno.test('the founder’s own example: decoration implies flooring, with a reason in both languages', () => {
  const out = impliedServices(['interior_fitout.decoration'], MAP, ['interior_fitout.decoration']);
  const tiling = out.find((i) => i.key === 'flooring.tiling');
  assert(tiling, 'decoration does not imply flooring.tiling');
  assert(tiling.because[0].en.length > 10 && /[ء-ي]/.test(tiling.because[0].ar), 'a reason is missing a language');
});
Deno.test('NO CHAINING: what an implied service would imply is never added', () => {
  const direct = impliedServices(['gypsum.false_ceiling'], MAP, []).map((i) => i.key);
  assert(direct.includes('gypsum.acoustic_ceiling'), 'the fixture assumes false_ceiling implies acoustic_ceiling');
  const oneLevel = impliedServices(['interior_fitout.decoration'], MAP, ['interior_fitout.decoration']).map((i) => i.key);
  assert(oneLevel.includes('gypsum.false_ceiling'), 'decoration should imply false_ceiling');
  assert(!oneLevel.includes('gypsum.acoustic_ceiling'), 'decoration reached acoustic_ceiling through a chain');
});
Deno.test('a stated service is never repeated as an implied one', () => {
  const out = impliedServices(['interior_fitout.decoration'], MAP, ['interior_fitout.decoration', 'flooring.tiling']);
  assert(!out.some((i) => i.key === 'flooring.tiling'), 'flooring.tiling is stated and was implied again');
});
Deno.test('a removed implication is still offered, marked removed, so it can be put back', () => {
  const out = impliedServices(['interior_fitout.decoration'], MAP, ['interior_fitout.decoration'], ['flooring.tiling']);
  const tiling = out.find((i) => i.key === 'flooring.tiling');
  assert(tiling && tiling.removed, 'a removed implication disappeared instead of being marked');
});
Deno.test('every seeded implication names a service the seed knows', () => {
  const known = new Set(Object.keys(ALIASES as Record<string, unknown>));
  const bad = MAP.filter((r) => !known.has(r.to) || (r.from.includes('.') && !known.has(r.from)));
  assertEquals(bad.map((b) => `${b.from} -> ${b.to}`), [], 'the implication seed names a service that does not exist');
});
Deno.test('every seeded implication carries a reason in English AND Arabic', () => {
  const bad = MAP.filter((r) => r.en.trim().length < 10 || !/[ء-ي]/.test(r.ar));
  assertEquals(bad.map((b) => `${b.from} -> ${b.to}`), []);
});
Deno.test('no seeded implication is a self-reference', () => {
  assertEquals(MAP.filter((r) => r.from === r.to).map((r) => r.from), []);
});

// ── 5. the alias seed itself (still stored: service_meaning.ts corroborates a vector hit with it, point 92) ──
Deno.test('every service carries at least one English AND one Arabic alias', () => {
  const bad: string[] = [];
  for (const [key, v] of Object.entries(ALIASES as Record<string, { en: string[]; ar: string[] }>)) {
    if (!v.en.length || !v.ar.length) bad.push(key);
    if (v.ar.some((a) => !/[ء-ي]/.test(a))) bad.push(key + ' (an "ar" alias has no Arabic letter)');
    if (v.en.some((a) => /[ء-ي]/.test(a))) bad.push(key + ' (an "en" alias has an Arabic letter)');
  }
  assertEquals(bad, []);
});
Deno.test('no Arabic alias is stored with the definite article (the pattern adds it)', () => {
  const bad: string[] = [];
  for (const [key, v] of Object.entries(ALIASES as Record<string, { en: string[]; ar: string[] }>)) {
    for (const a of v.ar) if (/^ال[ء-ي]/.test(a.trim())) bad.push(`${key}: ${a}`);
  }
  assertEquals(bad, []);
});

// ── 6. the queue holds services, not grammar; the scan is bounded ─────────────────────────────────
Deno.test('own_words never contains a service key', () => {
  const r = rewriteServices('Ducting, helicopter window polishing', SERVICES);
  assertEquals(words('Ducting, helicopter window polishing'), r.own_words);
  assert(!r.own_words.some((w) => r.service_keys.includes(w)));
});
Deno.test('the worst case — 2000 characters matching nothing — stays well inside the CPU budget', () => {
  const worst = Array.from({ length: 40 }, () => 'zzqq xxwv yyrr '.repeat(30)).join('\n').slice(0, 2000);
  const t0 = performance.now();
  const r = rewriteServices(worst, SERVICES);
  const ms = performance.now() - t0;
  assertEquals(r.service_keys, []);
  assert(ms < 200, `the adversarial rewrite took ${Math.round(ms)}ms`);
});
// Measured 18 Sep 2026 on a realistic supplier paragraph: the queue was being handed "We are an", "Plus",
// "ننفذ" and "تجهيز في دبي". Sentence glue is not a pending taxonomy item.
for (const c of [
  { name: 'EN, a whole sentence of glue', text: 'We are a leading company with many years of experience' },
  { name: 'EN, where the company works', text: 'Dubai, Abu Dhabi, Sharjah and Ras Al Khaimah' },
  { name: 'AR, a whole sentence of glue', text: 'نحن شركة رائدة لدينا خبرة سنوات طويلة' },
  { name: 'AR, where the company works', text: 'دبي، أبوظبي، الشارقة، عجمان' },
]) {
  Deno.test(`not a pending taxonomy item: ${c.name}`, () => assertEquals(words(c.text), [], JSON.stringify(words(c.text))));
}

// ── 7. the paragraphs the 18 and 21 Sep audits used, read under ruling 890 ────────────────────────
// Until 29 Sep 2026 alias words named gypsum partitions, false ceilings, maintenance and decoration in these. Now
// only a part written as a service's own name is named ("false ceilings" is the name of gypsum.false_ceiling);
// every other part is kept in the supplier's words for meaning (English) or the sales engineer (Arabic: gte-small
// is an English model, service_meaning.ts ARABIC). Nothing he wrote is lost, nothing is guessed.
Deno.test('the English audit paragraph: only an exact name is named, every other service part kept', () => {
  const r = rewriteServices('We are an interior decoration and fit-out company in Dubai. We do gypsum partitions, false ceilings and painting, '
    + 'plus chiller maintenance and helicopter window polishing.', SERVICES);
  assertEquals(r.service_keys, ['gypsum.false_ceiling']);
  for (const w of ['We do gypsum partitions', 'Painting', 'Plus chiller maintenance', 'Helicopter window polishing']) {
    assert(r.own_words.includes(w), `${w} was lost: ${JSON.stringify(r.own_words)}`);
  }
  assert(!r.items.some((i) => i.kind === 'trade'), 'a trade was read from words');
});
Deno.test('audit 21 Sep, finding 8, under ruling 890: the Arabic sentence is kept whole for the sales engineer', () => {
  const r = rewriteServices('نقوم بأعمال الجبس والأسقف المستعارة والدهانات', SERVICES);
  assertEquals(r.service_keys, [], 'an alias word named a service');
  assertEquals(r.own_words, ['نقوم بأعمال الجبس والأسقف المستعارة والدهانات']);
  // and written as the services' own Arabic names, the same supplier is read exactly
  assertEquals([...keys('قواطع الجبس، الأسقف المعلقة، الدهان الداخلي')].sort(), ['gypsum.false_ceiling', 'gypsum.partitions', 'painting.interior']);
});

// ── 8. who the work is FOR is not a service (2 Nov 2026) ────────────────────────────────────────────
// Supplier portal, Services tab: from "... shopfronts and glass curtain walls for villas and offices" the
// rewrite offered "Serviced offices" (from "Offices") and quoted "Glass curtain walls for villas" as the line
// behind Curtain wall. The audience after "for" was split at "and" into parts of its own. Cut at the
// preposition, in grammar, with no list of customers or buildings, so every building type is covered.
const SENTENCE = 'We supply and install aluminium sliding and casement windows, aluminium doors, shopfronts and glass curtain walls for villas and offices';
const AUDIENCE = /villa|office|فلل|مكاتب|hotel|school|restaurant|mall/i;

Deno.test('the portal sentence: no customer or building type becomes a part, and no part carries "for"', () => {
  const rw = rewriteServices(SENTENCE, SERVICES);
  assertEquals(rw.own_words.filter((w) => AUDIENCE.test(w) || /\bfor\b/i.test(w)), [], rw.own_words.join(' | '));
  assert(rw.own_words.includes('Glass curtain walls'), rw.own_words.join(' | '));
});

const AUDIENCE_CASES: { name: string; text: string; keys: string[]; own: string[] }[] = [
  { name: 'English, a service name before "for"', text: 'False ceilings for hotels and restaurants', keys: ['gypsum.false_ceiling'], own: [] },
  { name: 'English, two names then the audience', text: 'CCTV and Interior painting for schools and malls', keys: ['painting.interior', 'security_systems.cctv'], own: [] },
  { name: 'English, another trade and another audience', text: 'Ducting for warehouses and labour camps', keys: ['hvac.ducting'], own: [] },
  { name: 'English, a part no service is written as, before "for"', text: 'Helicopter window polishing for yachts and hangars', keys: [], own: ['Helicopter window polishing'] },
  { name: 'Arabic, ل attached to the article', text: 'الأسقف المعلقة للفلل والمكاتب', keys: ['gypsum.false_ceiling'], own: [] },
  { name: 'Arabic, لـ standing alone', text: 'قواطع الجبس لـ الفلل والمكاتب', keys: ['gypsum.partitions'], own: [] },
  { name: 'Arabic, a part no service is written as', text: 'تلميع نوافذ المروحيات للفنادق والمستشفيات', keys: [], own: ['تلميع نوافذ المروحيات'] },
];
for (const c of AUDIENCE_CASES) {
  Deno.test(`audience cut: ${c.name}`, () => {
    const rw = rewriteServices(c.text, SERVICES);
    assertEquals([...rw.service_keys].sort(), c.keys, c.text);
    assertEquals(rw.own_words, c.own, c.text);
  });
}

// Known-bad controls the cut must NOT touch: a word that merely looks like the preposition, a bare noun the
// supplier gives as a service of its own, and a phrase that begins with the preposition.
const KEPT: { name: string; text: string; own: string[] }[] = [
  { name: 'Arabic louvres begins with ل but is not the preposition', text: 'تركيب لوفرات ألمنيوم', own: ['تركيب لوفرات ألمنيوم'] },
  { name: 'English word that holds "for" inside it', text: 'Information technology consultancy', own: ['Information technology consultancy'] },
  { name: 'a bare "Offices" on its own is the supplier’s own words, not cut to nothing', text: 'Offices', own: ['Offices'] },
  { name: 'a phrase beginning with "for" is left whole', text: 'For yacht interiors', own: ['For yacht interiors'] },
];
for (const c of KEPT) {
  Deno.test(`audience cut leaves alone: ${c.name}`, () => assertEquals(words(c.text), c.own, c.text));
}
