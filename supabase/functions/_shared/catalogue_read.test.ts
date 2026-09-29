// A CATALOGUE IS READ AS A CATALOGUE — proved on the ZZ DEMO fixture that reproduces the structure of a
// real IT importer's catalogue (catalogue_fixtures/), with no model and no network.
//   deno test -A supabase/functions/_shared/catalogue_read.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { createWorker } from 'npm:tesseract.js@7.0.0';
import { readDocument } from './doc_read/index.ts';
import { allText, readDocForTrades, type TradeResolveDeps } from './supplier_doc_trades.ts';
import { catalogueLines, readCatalogue, supplyOnlyOf } from './catalogue_read.ts';
import { exactService, flattenImplications, impliedServices, isInstallWork, phraseParts, rewriteServices, splitPhrases, type ServiceTerm } from './service_rewrite.ts';
import { OFF_MESSAGE, PHOTO_VISION_FLAG, CATALOGUE_MODEL_FLAG, parseModelRead, readWithModel } from './catalogue_model.ts';
import ALIASES from './service_aliases.json' with { type: 'json' };
import IMPLICATIONS from './service_implications.json' with { type: 'json' };

const here = new URL('.', import.meta.url);
const path = (u: URL) => decodeURIComponent(u.pathname).replace(/^\/([A-Za-z]:)/, '$1');
const SERVICES: ServiceTerm[] = Object.entries(ALIASES as Record<string, { en: string[]; ar: string[] }>).map(([key, v]) => ({
  trade_code: key.slice(0, key.indexOf('.')), code: key.slice(key.indexOf('.') + 1),
  label_en: key.slice(key.indexOf('.') + 1).replace(/_/g, ' '), label_ar: 'خدمة', aliases: [...v.en, ...v.ar],
}));
// The catalogue upload's TRADES come from an exact code or from meaning (trade_resolve.ts, ruling 890), never from
// these service aliases. Offline there is no model, so `embed` records what meaning WOULD read and answers null;
// what the real gte-small makes of the same catalogue is proved by
// scripts/checks/a_suppliers_documents_name_trades_by_exact_code_or_meaning_never_by_words.test.mjs.
const offline = (seen: string[] = []): TradeResolveDeps => ({
  normTrades: async () => ({}),
  services: SERVICES.map((s) => ({ ...s, vec: [1, 0] })),
  embed: async (t) => { seen.push(t); return null; },
  budget: { left: 16 },
});
const FIXTURE = new URL('catalogue_fixtures/zz_demo_it_wholesaler_catalogue.pdf', here);
const fixtureText = async () => {
  const r = await readDocument(Deno.readFileSync(FIXTURE), 'zz_demo_it_wholesaler_catalogue.pdf', 'application/pdf', 0, { textOnly: true });
  assert(r.ok, 'the fixture PDF must read');
  return allText(r);
};

const MUST = ['it_services.hardware_supply', 'office_equipment.printers_mfp', 'office_equipment.photocopiers',
  'office_equipment.toners_cartridges', 'pos_retail.pos_terminals', 'pos_retail.receipt_printers',
  'pos_retail.barcode_scanners', 'security_systems.cctv', 'power_generators.ups', 'av_it.audio_visual'];
const NEVER = ['electrical.wiring_install', 'logistics_moving.storage', 'electrical.lighting',
  'it_services.network_install', 'it_services.structured_cabling', 'security_systems.intruder_alarm', 'av_it.data_cabling'];
/** The keys a text names EXACTLY (a phrase or list part that IS a service). Since 29 Sep 2026 (ruling 890,
 *  decision point 93) the rewrite may name nothing else: every key it returns must be in this set. */
const exactKeysOf = (text: string) => new Set(splitPhrases(text, 80_000, 400).flatMap((p) => [p, ...phraseParts(p)])
  .map((p) => exactService(p, SERVICES)).filter((s): s is ServiceTerm => !!s).map((s) => `${s.trade_code}.${s.code}`));

// Offline there is no model: the MUST list is what words AND meaning read together on the live model
// (scripts/checks/a_catalogue_line_is_understood_by_meaning.test.mjs). Here: what the rewrite names is only what
// the catalogue writes exactly, none of the false hits, and every heading it names nothing for is kept for meaning.
Deno.test('the ZZ DEMO catalogue reads as a supply-only supplier; only exact names are named, never a false hit', async () => {
  const text = await fixtureText();
  const c = readCatalogue(text, SERVICES);
  assertEquals(c.supply_only, true);
  assert(c.supply.supply_words.includes('wholesaler') && c.supply.supply_words.includes('stockist'), JSON.stringify(c.supply));
  const exact = exactKeysOf(c.matched_text);
  for (const k of c.rewrite.service_keys) assert(exact.has(k), `${k} was named by a word, not by its exact name`);
  for (const k of NEVER) assert(!c.rewrite.service_keys.includes(k), `false hit ${k}`);
  assert(c.rewrite.service_keys.includes('office_equipment.photocopiers'), 'the heading "Photocopiers" is that service\'s own code');
  assert(c.rewrite.own_words.includes('Printers') && c.rewrite.own_words.includes('Laptops'), 'a heading no name matched must be kept for meaning: ' + JSON.stringify(c.rewrite.own_words));
  assert(MUST.length > 0);
  // Implications: CCTV -> intruder alarms exists in the map, and for a supply-only company it comes back struck out.
  const map = flattenImplications(IMPLICATIONS as { from: string; to: string[]; en: string; ar: string }[]);
  const stated = ['security_systems.cctv'];
  const sources = [...stated, 'security_systems'];
  const imp = impliedServices(sources, map, stated, [], true);
  assert(imp.some((i) => i.key === 'security_systems.intruder_alarm'), 'the CCTV -> intruder alarm row is what this proves against');
  assert(imp.every((i) => i.removed), 'a supply-only company is implied nothing');
  assert(impliedServices(sources, map, stated, [], false).some((i) => i.key === 'security_systems.intruder_alarm' && !i.removed),
    'an installer still gets the implication');
});

Deno.test('the catalogue upload reads what meaning should read, never a spec row or an address, and no alias word proposes a trade', async () => {
  const bytes = Deno.readFileSync(FIXTURE);
  const seen: string[] = [];
  const ev = await readDocForTrades({ path: 'catalog/1/zz.pdf', name: 'zz.pdf', kind: 'catalogue', bytes, mime: 'application/pdf' }, offline(seen));
  // The service aliases name ten services in this catalogue (the test above); none of them proposes a trade here.
  assertEquals(ev.trades, [], 'a trade was proposed without an exact code or a meaning: ' + JSON.stringify(ev.trades));
  assertEquals([ev.exact, ev.meaning], ['on', 'embedding_unavailable'], 'an empty proposal must say meaning could not run');
  assertEquals(ev.supply_only, true);
  assertEquals(ev.source, 'document_text');
  assert(seen.length > 0 && seen.length <= 16, `meaning read ${seen.length} lines`);
  assert(!seen.some((l) => /\b\d+(?:\.\d+)?\s?(?:VA|TB|GB|W)\b|LLC|Tel|@/i.test(l)), 'a spec row or a contact line reached meaning: ' + JSON.stringify(seen));
});

Deno.test('context, not a blocklist: a spec row, an address and a sentence name no service', () => {
  const L = catalogueLines([
    'DVR Storage Upto 6TB', 'Power Indicator LED Light Power Indicator LED Light', 'Type UPS with Built-in AVR Type UPS with Built-in AVR',
    'Our battery backups protect your electric gadgets.', 'ACME TRADING LLC (Warehouse)', 'Tel: +971 500000099',
    'Model No: ZZ-X1 / ZZ-X2', 'Storage 256GB SSD', 'PRINTERS', 'LED lighting supply',
  ].join('\n'));
  assertEquals(L.headings, ['PRINTERS', 'LED lighting supply']);
  assertEquals(L.types, ['UPS with Built-in AVR', 'UPS with Built-in AVR']);
  assertEquals(L.statements.length, 1);
  // The heading is kept, whole, for meaning to read (since 29 Sep 2026 no alias word names it here): the rule is
  // the line's role, not the word.
  const rw = rewriteServices(L.headings.join('\n'), SERVICES);
  assertEquals(rw.service_keys, []);
  assert(rw.own_words.includes('LED lighting supply'), 'the product line was dropped instead of kept for meaning');
});

Deno.test('a name is the whole text, never a word inside it: "UPS" is UPS, "upset" and "ups units" are not', () => {
  const keys = (t: string) => rewriteServices(t, SERVICES).service_keys;
  assertEquals(keys('UPS'), ['power_generators.ups']);
  for (const t of ['ups units and batteries', 'upset customers', 'upstairs rooms', 'POS', 'position of the gate', 'post office']) {
    assertEquals(keys(t), [], `"${t}" named a service by a word`);
  }
});

Deno.test('supply only needs a trading word and no installation word, in English and Arabic', () => {
  assertEquals(supplyOnlyOf('IMPORTER, EXPORTER AND WHOLESALER').supply_only, true);
  assertEquals(supplyOnlyOf('We are importers and we install CCTV').supply_only, false);
  assertEquals(supplyOnlyOf('مستورد وموزع للأجهزة الإلكترونية').supply_only, true);
  assertEquals(supplyOnlyOf('نقوم بتوريد وتركيب الكاميرات').supply_only, false);
  assertEquals(supplyOnlyOf('We are a fit-out contractor').supply_only, false);
  assertEquals(supplyOnlyOf('Laptops and printers').supply_only, false, 'no trading word: not proposed');
  // A battery spec ("Sealed Maintenance Free") is a spec row and is not read for this.
  assertEquals(readCatalogue('IMPORTER AND WHOLESALER\nType Sealed Maintenance Free Type Sealed Maintenance Free', SERVICES).supply_only, true);
});

Deno.test('a supply-only company is not proposed installation work, from its own label', () => {
  assert(isInstallWork({ label_en: 'Network installation', code: 'network_install' }));
  assert(isInstallWork({ label_en: 'Structured cabling', code: 'structured_cabling' }));
  assert(isInstallWork({ label_en: 'Printer & copier servicing', code: 'printer_service' }));
  assert(!isInstallWork({ label_en: 'Lighting supply & installation', code: 'lighting' }), 'supply & install keeps its supply half');
  assert(!isInstallWork({ label_en: 'Hardware supply', code: 'hardware_supply' }));
  assert(!isInstallWork({ label_en: 'CCTV', code: 'cctv' }));
  const rw = rewriteServices('Networking\nCat 6 Cable\nCCTV', SERVICES, { supplyOnly: true });
  assert(!rw.service_keys.includes('it_services.network_install') && !rw.service_keys.includes('it_services.structured_cabling'));
  assert(rw.service_keys.includes('security_systems.cctv'));
});

Deno.test('TEXT IN A PHOTO: the ZZ DEMO UPS label, read by tesseract.js, names UPS systems', async () => {
  const worker = await createWorker('eng', 1, { langPath: path(new URL('../../../public/ocr/lang', here)), gzip: true, cacheMethod: 'none' });
  let text = '';
  try { text = (await worker.recognize(Deno.readFileSync(new URL('catalogue_fixtures/zz_demo_ups_label.png', here)))).data.text; } finally { await worker.terminate(); }
  assert(/UPS/.test(text), `OCR did not read the label: ${text}`);
  const seen: string[] = [];
  const ev = await readDocForTrades({ path: 'catalog/1/label.png', name: 'label.png', kind: 'catalogue', photo_text: text }, offline(seen));
  assertEquals(ev.source, 'photo_text');
  assertEquals(ev.status, 'read');
  assert(seen.some((l) => /UPS/.test(l)), 'the label text did not reach meaning: ' + JSON.stringify(seen));
  // The Services tab names from the same text only what it writes exactly (decision point 93, 29 Sep 2026).
  const c = readCatalogue(text, SERVICES);
  const exact = exactKeysOf(c.matched_text);
  for (const k of c.rewrite.service_keys) assert(exact.has(k), `${k} was named by a word, not by its exact name`);
});

// A stub admin for the decision_policy read: `flags` is what the table holds.
const adminWith = (flags: Record<string, unknown>) => ({
  from: () => ({ select: () => ({ eq: (_c: string, key: string) => ({ maybeSingle: async () => ({ data: key in flags ? { value: flags[key] } : null }) }) }) }),
});
const KEYS = new Set(['power_generators.ups', 'office_equipment.printers_mfp']);

Deno.test('the model paths are OFF by default and say so in English and Arabic, without calling anything', async () => {
  let called = 0;
  const stub = async () => { called++; return { content: '{}', error: null }; };
  for (const kind of ['photo', 'text'] as const) {
    const o = await readWithModel(adminWith({}), kind, { image_b64: 'AAAA', text: 'x' }, KEYS, stub);
    assertEquals(o.state, 'off');
    if (o.state === 'off') { assertEquals(o.message_en, OFF_MESSAGE[kind].en); assert(/[ء-ي]/.test(o.message_ar)); }
  }
  assertEquals(called, 0);
  assertEquals(OFF_MESSAGE.photo.en, 'We read the text in this photo; recognising what it shows is waiting on the vision model.');
  // The seed switches them off, and nothing else in the repository switches them on.
  const sql = Deno.readTextFileSync(new URL('../../../scripts/sql/a_catalogue_is_read_as_a_catalogue_and_two_trades_join_the_taxonomy.sql', here));
  for (const k of [PHOTO_VISION_FLAG, CATALOGUE_MODEL_FLAG]) assert(sql.includes(`'${k}'`), k);
  assert(sql.includes(`'{"enabled": false}'::jsonb, v.description`));
});

Deno.test('the vision path, switched on, reads a stubbed gateway reply and keeps only real service keys', async () => {
  const seen: unknown[] = [];
  const stub = async (_s: string, messages: unknown[]) => {
    seen.push(messages);
    return { content: 'Here: {"product_types":["UPS"],"services":["power_generators.ups","made_up.service"],"confidence":1.7,"reason":"a UPS nameplate"}', error: null };
  };
  const o = await readWithModel(adminWith({ [PHOTO_VISION_FLAG]: { enabled: true } }), 'photo', { image_b64: 'AAAA', mime: 'image/png' }, KEYS, stub);
  assertEquals(o.state, 'read');
  if (o.state === 'read') {
    assertEquals(o.read.services, ['power_generators.ups']);
    assertEquals(o.read.confidence, 1);
    assertEquals(o.source, 'model_vision');
  }
  assert(JSON.stringify(seen).includes('data:image/png;base64,AAAA'), 'the image went in as an image part');
  assertEquals(parseModelRead('no json here', KEYS), null);
  const failed = await readWithModel(adminWith({ [CATALOGUE_MODEL_FLAG]: true }), 'text', { text: 'x' }, KEYS, async () => ({ content: null, error: 'circuit_open' }));
  assertEquals(failed.state, 'failed');
});
