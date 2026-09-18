// THE SALES ENGINEER'S REWRITE, PROVED CASE BY CASE. Seat: sales_engineer. 18 Sep 2026.
//
// The rewrite decides which inquiries reach a supplier, so every rule in service_rewrite.ts is a row
// in a table here: English, Arabic, the two mixed, duplicates, Arabic proclitics and the definite
// article, a longer alias beating a shorter one, and — the one that must never regress — a phrase the
// aliases do NOT name, which is kept in the supplier's own words and flagged, never dropped and never
// mapped to a neighbour (founder, 14 Sep 2026: "either exact match or no match").
//
//   deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/service_rewrite.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  flattenImplications, impliedServices, rewriteServices, servicesFromText, splitPhrases, tidy,
  type Implication, type ServiceTerm,
} from './service_rewrite.ts';
import type { TradeTerm } from './trade_words.ts';
import ALIASES from './service_aliases.json' with { type: 'json' };
import IMPLICATIONS from './service_implications.json' with { type: 'json' };

// The real seed, read the way the edge function reads the database: every active service with its
// aliases. A fixture of three made-up services would prove the code and not the taxonomy.
const SERVICES: ServiceTerm[] = Object.entries(ALIASES as Record<string, { en: string[]; ar: string[] }>)
  .map(([key, v]) => {
    const trade_code = key.slice(0, key.indexOf('.'));
    const code = key.slice(key.indexOf('.') + 1);
    return { trade_code, code, label_en: code.replace(/_/g, ' '), label_ar: 'خدمة ' + code, aliases: [...v.en, ...v.ar] };
  });
const TRADES: TradeTerm[] = [
  { code: 'interior_fitout', aliases: ['fit out', 'fitout', 'interior fit out', 'تجهيز داخلي', 'ديكور'] },
  { code: 'flooring', aliases: ['flooring', 'ارضيات'] },
  { code: 'hvac', aliases: ['hvac', 'air conditioning', 'تكييف'] },
];
const MAP: Implication[] = flattenImplications(IMPLICATIONS as { from: string; to: string[]; en: string; ar: string }[]);

const keys = (text: string) => rewriteServices(text, SERVICES, TRADES).service_keys;
const words = (text: string) => rewriteServices(text, SERVICES, TRADES).own_words;

// ── 1. what the rewriter must recognise ───────────────────────────────────────────────────────────
const RECOGNISES: { name: string; text: string; expect: string[] }[] = [
  { name: 'EN, one service', text: 'We do ducting.', expect: ['hvac.ducting'] },
  { name: 'EN, comma list', text: 'Ducting, cable tray, water heater', expect: ['hvac.ducting', 'electrical.cable_tray', 'plumbing.heaters_pumps'] },
  { name: 'EN, "and" inside one phrase', text: 'ducting and cable tray', expect: ['hvac.ducting', 'electrical.cable_tray'] },
  { name: 'EN, bullets', text: '• Ducting\n• Cable tray', expect: ['hvac.ducting', 'electrical.cable_tray'] },
  { name: 'EN, numbered', text: '1. ducting\n2. cable tray', expect: ['hvac.ducting', 'electrical.cable_tray'] },
  { name: 'EN, longer alias wins', text: 'solar panel cleaning', expect: ['solar.maintenance'] },
  { name: 'EN, the shorter alias on its own', text: 'solar panel supply', expect: ['solar.pv_install'] },
  { name: 'AR, one service', text: 'تمديدات كهربائية', expect: ['electrical.wiring_install'] },
  { name: 'AR, with the definite article', text: 'التمديدات الكهربائية', expect: ['electrical.wiring_install'] },
  { name: 'AR, with a proclitic', text: 'نقوم بتمديدات كهربائية', expect: ['electrical.wiring_install'] },
  { name: 'AR, و as the conjunction', text: 'تمديدات كهربائية ولوحات توزيع', expect: ['electrical.wiring_install', 'electrical.db_panels'] },
  { name: 'AR, Arabic comma', text: 'صيانة مكيف، صرف صحي', expect: ['hvac.maintenance_amc', 'plumbing.drainage'] },
  { name: 'AR, tashkeel and tatweel folded', text: 'تَمديدات كهربائيـة', expect: ['electrical.wiring_install'] },
  { name: 'mixed EN + AR in one text', text: 'Ducting\nصرف صحي', expect: ['hvac.ducting', 'plumbing.drainage'] },
  { name: 'duplicates collapse', text: 'ducting, ducting, Ducting', expect: ['hvac.ducting'] },
  { name: 'AR duplicates collapse across forms', text: 'صرف صحي، الصرف الصحي', expect: ['plumbing.drainage'] },
];
for (const c of RECOGNISES) {
  Deno.test(`rewrite recognises: ${c.name}`, () => {
    assertEquals([...keys(c.text)].sort(), [...c.expect].sort(), c.text);
  });
}

// ── 2. what it must NOT invent ────────────────────────────────────────────────────────────────────
// A phrase no alias names is kept verbatim and flagged. It is never mapped to something that looks
// close, and it is never dropped.
const KEEPS_VERBATIM: { name: string; text: string; kept: string }[] = [
  { name: 'EN, nothing like it on the platform', text: 'Helicopter window polishing', kept: 'Helicopter window polishing' },
  { name: 'AR, nothing like it on the platform', text: 'تلميع نوافذ المروحيات', kept: 'تلميع نوافذ المروحيات' },
];
for (const c of KEEPS_VERBATIM) {
  Deno.test(`rewrite keeps the supplier's words: ${c.name}`, () => {
    const r = rewriteServices(c.text, SERVICES, TRADES);
    assertEquals(r.service_keys, [], 'invented a service for text no alias names');
    assert(r.own_words.includes(c.kept), `expected ${c.kept} in ${JSON.stringify(r.own_words)}`);
    assert(r.items.some((i) => i.kind === 'unmatched' && i.text === c.kept), 'not flagged for the sales engineer');
  });
}

Deno.test('a recognised phrase and an unknown one in the same line both survive', () => {
  const r = rewriteServices('Ducting and helicopter window polishing', SERVICES, TRADES);
  assertEquals(r.service_keys, ['hvac.ducting']);
  assertEquals(r.own_words, ['Helicopter window polishing']);
});

Deno.test('a phrase that names only a TRADE is kept with that trade, not guessed into a service', () => {
  const r = rewriteServices('We are an interior fit out company', SERVICES, TRADES);
  assertEquals(r.service_keys, []);
  assert(r.items.some((i) => i.kind === 'trade' && i.trades.includes('interior_fitout')), JSON.stringify(r.items));
});

// ── 3. tidying ────────────────────────────────────────────────────────────────────────────────────
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

// ── 4. the implication map, ONE LEVEL ─────────────────────────────────────────────────────────────
Deno.test('the founder’s own example: decoration implies flooring, with a reason in both languages', () => {
  const out = impliedServices(['interior_fitout.decoration'], MAP, ['interior_fitout.decoration']);
  const tiling = out.find((i) => i.key === 'flooring.tiling');
  assert(tiling, 'decoration does not imply flooring.tiling');
  assert(tiling.because[0].en.length > 10 && /[ء-ي]/.test(tiling.because[0].ar), 'a reason is missing a language');
});

Deno.test('NO CHAINING: what an implied service would imply is never added', () => {
  // decoration -> gypsum.false_ceiling (curated), and false_ceiling -> gypsum.acoustic_ceiling.
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

Deno.test('every seeded implication names a service the alias file also knows', () => {
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

// ── 5. the inquiry side reads the same aliases ────────────────────────────────────────────────────
Deno.test('servicesFromText reads an inquiry with the same rules, in both languages', () => {
  assertEquals(servicesFromText('Supply and install ducting for the villa', SERVICES), ['hvac.ducting']);
  assertEquals(servicesFromText('مطلوب تمديدات كهربائية للفيلا', SERVICES), ['electrical.wiring_install']);
  assertEquals(servicesFromText('Helicopter window polishing', SERVICES), []);
});

// ── 6. EN/AR parity of the seed itself ────────────────────────────────────────────────────────────
Deno.test('every service carries at least one English AND one Arabic alias', () => {
  const bad: string[] = [];
  for (const [key, v] of Object.entries(ALIASES as Record<string, { en: string[]; ar: string[] }>)) {
    if (!v.en.length || !v.ar.length) bad.push(key);
    if (v.ar.some((a) => !/[ء-ي]/.test(a))) bad.push(key + ' (an "ar" alias has no Arabic letter)');
    if (v.en.some((a) => /[ء-ي]/.test(a))) bad.push(key + ' (an "en" alias has an Arabic letter)');
  }
  assertEquals(bad, []);
});

Deno.test('no Arabic alias is stored with the definite article (the matcher adds it)', () => {
  const bad: string[] = [];
  for (const [key, v] of Object.entries(ALIASES as Record<string, { en: string[]; ar: string[] }>)) {
    for (const a of v.ar) if (/^ال[ء-ي]/.test(a.trim())) bad.push(`${key}: ${a}`);
  }
  assertEquals(bad, []);
});

Deno.test('unused export guard: own_words never contains a service key', () => {
  const r = rewriteServices('Ducting, helicopter window polishing', SERVICES, TRADES);
  assertEquals(words('Ducting, helicopter window polishing'), r.own_words);
  assert(!r.own_words.some((w) => r.service_keys.includes(w)));
});

// ── 7. the scan is bounded, and measured ──────────────────────────────────────────────────────────
Deno.test('the worst case — 2000 characters matching nothing — stays well inside the CPU budget', () => {
  const worst = Array.from({ length: 40 }, () => 'zzqq xxwv yyrr '.repeat(30)).join('\n').slice(0, 2000);
  const t0 = performance.now();
  const r = rewriteServices(worst, SERVICES, TRADES);
  const ms = performance.now() - t0;
  assertEquals(r.service_keys, []);
  assert(ms < 4000, `the adversarial rewrite took ${Math.round(ms)}ms`);
  console.log(`worst-case rewrite over ${SERVICES.length} services: ${Math.round(ms)}ms`);
});
