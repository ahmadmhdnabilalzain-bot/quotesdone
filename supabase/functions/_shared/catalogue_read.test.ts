// A CATALOGUE IS READ AS A CATALOGUE — proved on the ZZ DEMO fixture that reproduces the structure of a
// real IT importer's catalogue (catalogue_fixtures/), with no model and no network.
//   deno test -A supabase/functions/_shared/catalogue_read.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { createWorker } from 'npm:tesseract.js@7.0.0';
import { readDocument } from './doc_read/index.ts';
import { allText, readDocForTrades, type TradeResolveDeps } from './supplier_doc_trades.ts';
import { catalogueLines, supplyOnlyOf } from './catalogue_read.ts';
import { flattenImplications, impliedServices, isInstallWork, rewriteServices, type ServiceTerm } from './service_rewrite.ts';
import { OFF_MESSAGE, PHOTO_VISION_FLAG, CATALOGUE_MODEL_FLAG, parseModelRead, readWithModel } from './catalogue_model.ts';
import ALIASES from './service_aliases.json' with { type: 'json' };
import IMPLICATIONS from './service_implications.json' with { type: 'json' };

const here = new URL('.', import.meta.url);
const path = (u: URL) => decodeURIComponent(u.pathname).replace(/^\/([A-Za-z]:)/, '$1');
const SERVICES: ServiceTerm[] = Object.entries(ALIASES as Record<string, { en: string[]; ar: string[] }>).map(([key, v]) => ({
  trade_code: key.slice(0, key.indexOf('.')), code: key.slice(key.indexOf('.') + 1),
  label_en: key.slice(key.indexOf('.') + 1).replace(/_/g, ' '), label_ar: 'خدمة', aliases: [...v.en, ...v.ar],
}));
// The catalogue upload's trades and services are understood by the reader model with the supplier's other documents (ruling
// 1627, supplier_doc_trades.readTogether); never from these service aliases. Offline there is no model: this chooser records
// what the model WOULD be given and answers that it could not be asked.
const offline = (seen: string[] = []): TradeResolveDeps => ({
  chooseTrades: async (t) => { seen.push(t); return { ok: false, error: 'model unavailable (offline test)' }; },
});
const FIXTURE = new URL('catalogue_fixtures/zz_demo_it_wholesaler_catalogue.pdf', here);
// IMPLICATIONS (unchanged by ruling 1627): CCTV -> intruder alarms exists in the map, and for a supply-only company it comes back struck out.
Deno.test('a supply-only company is implied no installation work', () => {
  const map = flattenImplications(IMPLICATIONS as { from: string; to: string[]; en: string; ar: string }[]);
  const stated = ['security_systems.cctv'];
  const sources = [...stated, 'security_systems'];
  const imp = impliedServices(sources, map, stated, [], true);
  assert(imp.some((i) => i.key === 'security_systems.intruder_alarm'), 'the CCTV -> intruder alarm row is what this proves against');
  assert(imp.every((i) => i.removed), 'a supply-only company is implied nothing');
  assert(impliedServices(sources, map, stated, [], false).some((i) => i.key === 'security_systems.intruder_alarm' && !i.removed),
    'an installer still gets the implication');
});

Deno.test('the catalogue upload gives the model its headings and product types, never a spec row or an address, and guesses nothing without it', async () => {
  const bytes = Deno.readFileSync(FIXTURE);
  const seen: string[] = [];
  const ev = await readDocForTrades({ path: 'catalog/1/zz.pdf', name: 'zz.pdf', kind: 'catalogue', bytes, mime: 'application/pdf' }, offline(seen));
  // The service aliases name ten services in this catalogue; with no model none of them proposes anything (ruling 1627).
  assertEquals(ev.trades, [], 'a trade was proposed without the model: ' + JSON.stringify(ev.trades));
  assertEquals(ev.choice, 'unavailable', 'an empty proposal must say the model could not be asked');
  assert(/still being read/.test(ev.reason ?? ''), ev.reason);
  assertEquals(ev.supply_only, true);
  assertEquals(ev.source, 'document_text');
  assertEquals(seen.length, 1, 'the documents are given to the model once, together');
  const body = seen[0].split('\n').filter((l) => !/^=== /.test(l));
  assert(body.some((l) => /PRINTERS|Printers/.test(l)), 'the headings did not reach the model');
  assert(!body.some((l) => /\b\d+(?:\.\d+)?\s?(?:VA|TB|GB|W)\b|LLC|Tel|@/i.test(l)), 'a spec row or a contact line reached the model: ' + JSON.stringify(body.slice(0, 40)));
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
  assertEquals(keys('POS'), ['pos_retail.pos_terminals']);   // the whole text IS a curated alias (a name lookup)
  for (const t of ['ups units and batteries', 'upset customers', 'upstairs rooms', 'POS machines for the shop', 'position of the gate', 'post office']) {
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
  const L = catalogueLines('IMPORTER AND WHOLESALER\nType Sealed Maintenance Free Type Sealed Maintenance Free');
  assertEquals(supplyOnlyOf([...L.headings, ...L.statements].join('\n')).supply_only, true);
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

Deno.test('TEXT IN A PHOTO: the ZZ DEMO UPS label, read by tesseract.js, reaches the model', async () => {
  const worker = await createWorker('eng', 1, { langPath: path(new URL('../../../public/ocr/lang', here)), gzip: true, cacheMethod: 'none' });
  let text = '';
  try { text = (await worker.recognize(Deno.readFileSync(new URL('catalogue_fixtures/zz_demo_ups_label.png', here)))).data.text; } finally { await worker.terminate(); }
  assert(/UPS/.test(text), `OCR did not read the label: ${text}`);
  const seen: string[] = [];
  const ev = await readDocForTrades({ path: 'catalog/1/label.png', name: 'label.png', kind: 'catalogue', photo_text: text }, offline(seen));
  assertEquals(ev.source, 'photo_text');
  assertEquals(ev.status, 'read');
  assert(seen.some((l) => /UPS/.test(l)), 'the label text did not reach the model: ' + JSON.stringify(seen));
});

// A stub admin for the decision_policy read: `flags` is what the table holds.
const adminWith = (flags: Record<string, unknown>) => ({
  from: () => ({ select: () => ({ eq: (_c: string, key: string) => ({ maybeSingle: async () => ({ data: key in flags ? { value: flags[key] } : null }) }) }) }),
});
const KEYS = new Set(['power_generators.ups', 'office_equipment.printers_mfp']);

Deno.test('an absent switch is OFF, says so in English and Arabic, and calls nothing', async () => {
  let called = 0;
  const stub = async () => { called++; return { content: '{}', error: null }; };
  for (const kind of ['photo', 'text'] as const) {
    const o = await readWithModel(adminWith({}), kind, { image_b64: 'AAAA', text: 'x' }, KEYS, stub);
    assertEquals(o.state, 'off');
    if (o.state === 'off') { assertEquals(o.message_en, OFF_MESSAGE[kind].en); assert(/[ء-ي]/.test(o.message_ar)); }
  }
  assertEquals(called, 0);
});

// 10 Nov 2026 (launch verification, should-fix 2): suppliers were told "Reading the rest is waiting on the language model,
// which is switched off for now" seven weeks after rulings 1175 and 1260 lifted the hold for good.
Deno.test('the off line promises nothing about a switch and asks the supplier for his own words (known-bad: "switched off for now")', () => {
  for (const kind of ['photo', 'text'] as const) {
    const en = OFF_MESSAGE[kind].en; const ar = OFF_MESSAGE[kind].ar;
    assert(!/switched off|for now|waiting on|model/i.test(en), `${kind}: "${en}" promises or names a switch`);
    assert(!/متوقف|تنتظر|تفعيل/.test(ar), `${kind}: the Arabic line still waits on a switch`);
    assert(/your own words/.test(en) && /بكلمات/.test(ar), `${kind}: the supplier is not asked for his own words`);
  }
});

Deno.test('rulings 1175 and 1260: the last SQL to set the two switches turns both ON', () => {
  const on = Deno.readTextFileSync(new URL('../../../scripts/sql/the_supplier_catalogue_and_photo_readers_follow_the_rulings_that_keep_the_models_on.sql', here));
  for (const k of [PHOTO_VISION_FLAG, CATALOGUE_MODEL_FLAG]) {
    assert(new RegExp(`set value = '\\{"enabled": true\\}'::jsonb,[\\s\\S]{0,600}where key = '${k}'`).test(on), `${k} is not switched on`);
  }
  const manifest = Deno.readTextFileSync(new URL('../../../scripts/sql/MANIFEST.txt', here)).split('\n').map((l) => l.trim());
  const seed = manifest.indexOf('scripts/sql/a_catalogue_is_read_as_a_catalogue_and_two_trades_join_the_taxonomy.sql');
  const later = manifest.slice(seed + 1).filter((f) => f.endsWith('.sql') && !f.startsWith('#'));
  for (const f of later) {
    // comments are measurements, not statements: a header quoting the old {"enabled": false} switches nothing off
    let t = ''; try { t = Deno.readTextFileSync(new URL('../../../' + f, here)).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n'); } catch { continue; }
    for (const k of [PHOTO_VISION_FLAG, CATALOGUE_MODEL_FLAG]) {
      assert(!(t.includes(k) && /"enabled": false/.test(t)), `${f} switches ${k} off again after the rulings`);
    }
  }
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
