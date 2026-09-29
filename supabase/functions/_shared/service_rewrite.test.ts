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
  flattenImplications, impliedServices, ownWordsOf, rewriteServices, servicesFromText, splitPhrases, tidy, withExactTrades,
  type Implication, type ServiceTerm,
} from './service_rewrite.ts';
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
const MAP: Implication[] = flattenImplications(IMPLICATIONS as { from: string; to: string[]; en: string; ar: string }[]);

const keys = (text: string) => rewriteServices(text, SERVICES).service_keys;
const words = (text: string) => rewriteServices(text, SERVICES).own_words;

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
    const r = rewriteServices(c.text, SERVICES);
    assertEquals(r.service_keys, [], 'invented a service for text no alias names');
    assert(r.own_words.includes(c.kept), `expected ${c.kept} in ${JSON.stringify(r.own_words)}`);
    assert(r.items.some((i) => i.kind === 'unmatched' && i.text === c.kept), 'not flagged for the sales engineer');
  });
}

Deno.test('a recognised phrase and an unknown one in the same line both survive', () => {
  const r = rewriteServices('Ducting and helicopter window polishing', SERVICES);
  assertEquals(r.service_keys, ['hvac.ducting']);
  assertEquals(r.own_words, ['Helicopter window polishing']);
});

// RULING 890 (29 Sep 2026, ledger 1054). Until today "We are an interior fit out company" became a TRADE item
// because 'fit out' was a trade alias (trade_words.ts). A trade is no longer read from words: the phrase names
// nothing here (the Services tab gives it to meaning, supplier_services.servicesRewrite), and only a phrase that
// IS a code or an intake slug becomes a trade, decided by fn_norm_trades (withExactTrades).
Deno.test('a phrase whose words resemble a trade names no trade; one that IS a code or a slug does, exactly', () => {
  const r = rewriteServices('We are an interior fit out company', SERVICES);
  assertEquals(r.service_keys, []);
  assert(!r.items.some((i) => i.kind === 'trade'), 'a trade was read from words: ' + JSON.stringify(r.items));
  const typed = rewriteServices('Ducting, HVAC, Carpentry, helicopter window polishing', SERVICES);
  assertEquals(ownWordsOf(typed), ['HVAC', 'Carpentry', 'Helicopter window polishing']);
  // what fn_norm_trades_many answers for those phrases: the code and the slug resolve, the rest does not
  const x = withExactTrades(typed, { HVAC: ['hvac'], Carpentry: ['joinery'] });
  assertEquals(x.service_keys, ['hvac.ducting']);
  assertEquals(x.items.filter((i) => i.kind === 'trade').map((i) => i.kind === 'trade' ? i.trades : []), [['joinery']]);  // hvac is carried by hvac.ducting
  assertEquals(x.own_words, ['Carpentry', 'Helicopter window polishing']);
  assertEquals(withExactTrades(typed, null), typed, 'no answer from the database changes nothing');
});

// ── 3. tidying ────────────────────────────────────────────────────────────────────────────────────
// ── ARABIC COVERAGE OF EVERY SERVICE (audit 21 Sep 2026, finding 8) ──────────────────────────────
// "الدهانات" fell to the supplier's own words although Painting exists. Every one of the 201 services
// must carry at least one Arabic alias, and every Arabic alias must come back as ITS OWN key when a
// supplier writes it plainly, with the definite article, or after the conjunction و — the three ways
// a service is named in an Arabic sentence. A cross-hit is allowed (two aliases on the same words are
// both kept); a miss is not.
Deno.test('every service has an Arabic alias, and every Arabic alias resolves to its own service', () => {
  const misses: string[] = [];
  for (const [key, v] of Object.entries(ALIASES as Record<string, { en: string[]; ar: string[] }>)) {
    if (!v.ar.length) { misses.push(key + ': no Arabic alias'); continue; }
    for (const a of v.ar) {
      const forms = [a, 'ال' + a, 'نقوم بأعمال ' + a + ' و' + a];
      for (const f of forms) if (!keys(f).includes(key)) misses.push(`${key}: "${f}"`);
    }
  }
  assertEquals(misses, [], misses.join('\n'));
});

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
  const r = rewriteServices('Ducting, helicopter window polishing', SERVICES);
  assertEquals(words('Ducting, helicopter window polishing'), r.own_words);
  assert(!r.own_words.some((w) => r.service_keys.includes(w)));
});

// ── 7. the scan is bounded, and measured ──────────────────────────────────────────────────────────
Deno.test('the worst case — 2000 characters matching nothing — stays well inside the CPU budget', () => {
  const worst = Array.from({ length: 40 }, () => 'zzqq xxwv yyrr '.repeat(30)).join('\n').slice(0, 2000);
  const t0 = performance.now();
  const r = rewriteServices(worst, SERVICES);
  const ms = performance.now() - t0;
  assertEquals(r.service_keys, []);
  assert(ms < 4000, `the adversarial rewrite took ${Math.round(ms)}ms`);
  console.log(`worst-case rewrite over ${SERVICES.length} services: ${Math.round(ms)}ms`);
});

// ── 8. the sales engineer's queue holds services, not grammar ─────────────────────────────────────
// Measured 18 Sep 2026 on a realistic supplier paragraph: the queue was being handed "We are an",
// "Plus", "ننفذ" and "تجهيز في دبي". Nothing the supplier NAMED was ever lost; the queue was filling
// with sentence glue, which is how a review queue stops being read.
const NOT_A_SERVICE: { name: string; text: string }[] = [
  { name: 'EN, a whole sentence of glue', text: 'We are a leading company with many years of experience' },
  { name: 'EN, where the company works', text: 'Dubai, Abu Dhabi, Sharjah and Ras Al Khaimah' },
  { name: 'AR, a whole sentence of glue', text: 'نحن شركة رائدة لدينا خبرة سنوات طويلة' },
  { name: 'AR, where the company works', text: 'دبي، أبوظبي، الشارقة، عجمان' },
];
for (const c of NOT_A_SERVICE) {
  Deno.test(`not a pending taxonomy item: ${c.name}`, () => {
    const r = rewriteServices(c.text, SERVICES);
    assertEquals(r.own_words, [], `sentence glue reached the sales engineer: ${JSON.stringify(r.own_words)}`);
  });
}

Deno.test('a realistic paragraph yields services and only real unknowns', () => {
  const r = rewriteServices(
    'We are an interior decoration and fit-out company in Dubai. We do gypsum partitions, false ceilings and painting, '
    + 'plus chiller maintenance and helicopter window polishing.', SERVICES);
  assert(r.service_keys.includes('interior_fitout.decoration'), JSON.stringify(r.service_keys));
  assert(r.service_keys.includes('gypsum.partitions') && r.service_keys.includes('gypsum.false_ceiling'));
  assert(r.service_keys.includes('hvac.maintenance_amc'));
  // What no service alias names, kept exactly as written. Until 29 Sep 2026 "fit-out company in Dubai" was
  // swallowed by the TRADE alias 'fit out' (trade_words.ts); a trade is no longer read from words (ruling 890), so
  // it stays the supplier's own words - the save reads it exactly or by reasoning (supplier_services.resolveText).
  assertEquals(r.own_words.filter((w) => !/^painting$/i.test(w)), ['Fit-out company in dubai', 'Helicopter window polishing']);
  assert(!r.items.some((i) => i.kind === 'trade'), 'a trade was read from words');
});

Deno.test('the Arabic paragraph behaves the same way', () => {
  const r = rewriteServices(
    'شركة ديكور داخلي وتجهيز في دبي. ننفذ قواطع جبس وأسقف مستعارة ودهانات، وصيانة تشيلر، وتلميع نوافذ المروحيات.',
    SERVICES);
  assert(r.service_keys.includes('gypsum.partitions'), JSON.stringify(r.service_keys));
  assert(r.service_keys.includes('gypsum.false_ceiling'));
  assert(r.service_keys.includes('hvac.maintenance_amc'));
  assert(r.own_words.some((w) => w.includes('المروحيات')), JSON.stringify(r.own_words));
  assert(!r.own_words.some((w) => /^ننفذ$/.test(w)), `glue survived: ${JSON.stringify(r.own_words)}`);
});

// ── 9. the Arabic a supplier actually types ───────────────────────────────────────────────────────
Deno.test('a UAE decoration company is read as decoration, not as the design service', () => {
  // "ديكور داخلي" is what a DECORATION contractor writes; interior_design is the drawings service.
  // This is the founder's own cross-matching example (instruction 439), so it gets its own row.
  assertEquals(keys('شركة ديكور داخلي في دبي'), ['interior_fitout.decoration']);
  assertEquals(keys('تصميم داخلي'), ['interior_fitout.interior_design']);
});

Deno.test('a list item does not keep the Arabic conjunction stuck to its front', () => {
  const r = rewriteServices('قواطع جبس، وتلميع نوافذ المروحيات', SERVICES);
  assertEquals(r.service_keys, ['gypsum.partitions']);
  assertEquals(r.own_words, ['تلميع نوافذ المروحيات']);
});

Deno.test('a single Arabic word beginning with و keeps its first letter', () => {
  assertEquals(tidy('وقود'), 'وقود');
  assertEquals(tidy('وكالة'), 'وكالة');
});

// AUDIT 21 Sep 2026, finding 8 (ZZ DEMO Interiors, gypsum). The exact sentence a supplier typed: only
// the false ceilings were recognised; "الدهانات" fell to "kept in your own words" although Painting ›
// Interior painting exists, and "الجبس" named nothing. The matcher already strips ال / و / وال (the
// PROCLITIC in alias_pattern.ts, once trade_words.ts) and reads a word to its end (دهان -> دهانات); what was missing was the
// bare word a supplier actually uses — the aliases carried only "دهان داخلي" and "قواطع جبس".
Deno.test('audit 21 Sep: "نقوم بأعمال الجبس والأسقف المستعارة والدهانات" names gypsum, false ceilings and painting', () => {
  const rw = rewriteServices('نقوم بأعمال الجبس والأسقف المستعارة والدهانات', SERVICES);
  const got = new Set(rw.service_keys);
  assert(got.has('painting.interior'), JSON.stringify(rw.items));
  assert(got.has('gypsum.false_ceiling'), JSON.stringify(rw.items));
  assert(got.has('gypsum.partitions'), JSON.stringify(rw.items));
  assertEquals(rw.own_words, [], 'nothing of this sentence is left in the supplier\'s own words');
});

Deno.test('the bare Arabic words do not steal a longer, more exact alias', () => {
  assertEquals(keys('دهانات خارجية'), ['painting.exterior']);
  assertEquals(keys('اعادة دهان'), ['painting.repainting']);
  assertEquals(keys('أسقف جبس'), ['gypsum.false_ceiling']);
  assertEquals(keys('جبس ديكور'), ['gypsum.decorative']);
});
