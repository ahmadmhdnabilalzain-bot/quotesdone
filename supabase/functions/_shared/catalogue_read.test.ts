// A CATALOGUE IS READ AS A CATALOGUE — proved on the ZZ DEMO fixture that reproduces the structure of a
// real IT importer's catalogue (catalogue_fixtures/), with no model and no network.
//   deno test -A supabase/functions/_shared/catalogue_read.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { createWorker } from 'npm:tesseract.js@7.0.0';
import { readDocument } from './doc_read/index.ts';
import { allText, readDocForTrades } from './supplier_doc_trades.ts';
import { catalogueLines, readCatalogue, supplyOnlyOf } from './catalogue_read.ts';
import { flattenImplications, impliedServices, isInstallWork, rewriteServices, type ServiceTerm } from './service_rewrite.ts';
import { OFF_MESSAGE, PHOTO_VISION_FLAG, CATALOGUE_MODEL_FLAG, parseModelRead, readWithModel } from './catalogue_model.ts';
import type { TradeTerm } from './trade_words.ts';
import ALIASES from './service_aliases.json' with { type: 'json' };
import IMPLICATIONS from './service_implications.json' with { type: 'json' };

const here = new URL('.', import.meta.url);
const path = (u: URL) => decodeURIComponent(u.pathname).replace(/^\/([A-Za-z]:)/, '$1');
const SERVICES: ServiceTerm[] = Object.entries(ALIASES as Record<string, { en: string[]; ar: string[] }>).map(([key, v]) => ({
  trade_code: key.slice(0, key.indexOf('.')), code: key.slice(key.indexOf('.') + 1),
  label_en: key.slice(key.indexOf('.') + 1).replace(/_/g, ' '), label_ar: 'خدمة', aliases: [...v.en, ...v.ar],
}));
// The live trade aliases that produced the false hits on 21 Sep 2026, plus the two new trades.
const TRADES: TradeTerm[] = [
  { code: 'electrical', aliases: ['electrical', 'electric', 'wiring', 'lighting'] },
  { code: 'logistics_moving', aliases: ['moving and storage', 'warehousing service'] },
  { code: 'av_it', aliases: ['audio visual', 'networking', 'low current', 'structured cabling'] },
  { code: 'it_services', aliases: ['it services', 'structured cabling'] },
  { code: 'security_systems', aliases: ['cctv', 'surveillance', 'intruder alarm'] },
  { code: 'power_generators', aliases: ['generator', 'ups system'] },
  { code: 'office_equipment', aliases: ['office equipment', 'photocopier', 'printer', 'toner'] },
  { code: 'pos_retail', aliases: ['point of sale', 'pos system', 'barcode scanner', 'receipt printer'] },
];
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

Deno.test('the ZZ DEMO catalogue reads as a supply-only IT, office-equipment, POS, CCTV, UPS and projector supplier', async () => {
  const c = readCatalogue(await fixtureText(), SERVICES, TRADES);
  assertEquals(c.supply_only, true);
  assert(c.supply.supply_words.includes('wholesaler') && c.supply.supply_words.includes('stockist'), JSON.stringify(c.supply));
  for (const k of MUST) assert(c.rewrite.service_keys.includes(k), `missing ${k}: ${c.rewrite.service_keys}`);
  for (const k of NEVER) assert(!c.rewrite.service_keys.includes(k), `false hit ${k}`);
  // Implications: CCTV -> intruder alarms exists in the map, and for a supply-only company it comes back struck out.
  const map = flattenImplications(IMPLICATIONS as { from: string; to: string[]; en: string; ar: string }[]);
  const sources = [...c.rewrite.service_keys, ...c.rewrite.service_keys.map((k) => k.split('.')[0])];
  const imp = impliedServices(sources, map, c.rewrite.service_keys, [], true);
  assert(imp.some((i) => i.key === 'security_systems.intruder_alarm'), 'the CCTV -> intruder alarm row is what this proves against');
  assert(imp.every((i) => i.removed), 'a supply-only company is implied nothing');
  assert(impliedServices(sources, map, c.rewrite.service_keys, [], false).some((i) => i.key === 'security_systems.intruder_alarm' && !i.removed),
    'an installer still gets the implication');
});

Deno.test('the catalogue upload proposes the trades the catalogue names, and not the false ones', async () => {
  const bytes = Deno.readFileSync(FIXTURE);
  const ev = await readDocForTrades({ path: 'catalog/1/zz.pdf', name: 'zz.pdf', kind: 'catalogue', bytes, mime: 'application/pdf' }, TRADES, SERVICES);
  const codes = ev.trades.map((t) => t.code);
  for (const c of ['it_services', 'office_equipment', 'pos_retail', 'security_systems', 'power_generators', 'av_it']) assert(codes.includes(c), `${c} not proposed: ${codes}`);
  for (const c of ['electrical', 'logistics_moving']) assert(!codes.includes(c), `${c} proposed from a spec row or a sentence`);
  assertEquals(ev.supply_only, true);
  assertEquals(ev.source, 'document_text');
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
  // The same words stated as a heading still name the service: the rule is the line's role, not the word.
  const rw = rewriteServices(L.headings.join('\n'), SERVICES, TRADES);
  assert(rw.service_keys.includes('electrical.lighting'), 'LED lighting as a product line is still lighting');
});

Deno.test('UPS and POS are whole words: "upset" and "position" name nothing', () => {
  const keys = (t: string) => rewriteServices(t, SERVICES, TRADES).service_keys;
  assert(keys('UPS').includes('power_generators.ups'));
  assert(keys('ups units and batteries').includes('power_generators.ups'));
  assert(!keys('upset customers').includes('power_generators.ups'));
  assert(!keys('upstairs rooms').includes('power_generators.ups'));
  assert(keys('POS').includes('pos_retail.pos_terminals'));
  assert(!keys('position of the gate').includes('pos_retail.pos_terminals'));
  assert(!keys('post office').includes('pos_retail.pos_terminals'));
});

Deno.test('supply only needs a trading word and no installation word, in English and Arabic', () => {
  assertEquals(supplyOnlyOf('IMPORTER, EXPORTER AND WHOLESALER').supply_only, true);
  assertEquals(supplyOnlyOf('We are importers and we install CCTV').supply_only, false);
  assertEquals(supplyOnlyOf('مستورد وموزع للأجهزة الإلكترونية').supply_only, true);
  assertEquals(supplyOnlyOf('نقوم بتوريد وتركيب الكاميرات').supply_only, false);
  assertEquals(supplyOnlyOf('We are a fit-out contractor').supply_only, false);
  assertEquals(supplyOnlyOf('Laptops and printers').supply_only, false, 'no trading word: not proposed');
  // A battery spec ("Sealed Maintenance Free") is a spec row and is not read for this.
  assertEquals(readCatalogue('IMPORTER AND WHOLESALER\nType Sealed Maintenance Free Type Sealed Maintenance Free', SERVICES, TRADES).supply_only, true);
});

Deno.test('a supply-only company is not proposed installation work, from its own label', () => {
  assert(isInstallWork({ label_en: 'Network installation', code: 'network_install' }));
  assert(isInstallWork({ label_en: 'Structured cabling', code: 'structured_cabling' }));
  assert(isInstallWork({ label_en: 'Printer & copier servicing', code: 'printer_service' }));
  assert(!isInstallWork({ label_en: 'Lighting supply & installation', code: 'lighting' }), 'supply & install keeps its supply half');
  assert(!isInstallWork({ label_en: 'Hardware supply', code: 'hardware_supply' }));
  assert(!isInstallWork({ label_en: 'CCTV', code: 'cctv' }));
  const rw = rewriteServices('Networking\nCat 6 Cable\nCCTV', SERVICES, TRADES, { supplyOnly: true });
  assert(!rw.service_keys.includes('it_services.network_install') && !rw.service_keys.includes('it_services.structured_cabling'));
  assert(rw.service_keys.includes('security_systems.cctv'));
});

Deno.test('TEXT IN A PHOTO: the ZZ DEMO UPS label, read by tesseract.js, names UPS systems', async () => {
  const worker = await createWorker('eng', 1, { langPath: path(new URL('../../../public/ocr/lang', here)), gzip: true, cacheMethod: 'none' });
  let text = '';
  try { text = (await worker.recognize(Deno.readFileSync(new URL('catalogue_fixtures/zz_demo_ups_label.png', here)))).data.text; } finally { await worker.terminate(); }
  assert(/UPS/.test(text), `OCR did not read the label: ${text}`);
  const ev = await readDocForTrades({ path: 'catalog/1/label.png', name: 'label.png', kind: 'catalogue', photo_text: text }, TRADES, SERVICES);
  assertEquals(ev.source, 'photo_text');
  assert(ev.trades.some((t) => t.code === 'power_generators'), JSON.stringify(ev.trades));
  assert(readCatalogue(text, SERVICES, TRADES).rewrite.service_keys.includes('power_generators.ups'));
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
