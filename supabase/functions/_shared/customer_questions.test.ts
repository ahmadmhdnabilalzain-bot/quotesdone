// What the customer reads for a spec (customer_questions.ts): plain words in both languages, an example, "Not sure", and the
// supplier-facing label left exactly as the pack wrote it. Read against the repository packs, as the loader maps them.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { ARABIC_FRAME, CUSTOMER_QUESTION, explainTerms, GLOSSARY, NOT_SURE, optionAr, plainFrame, plainOf, sameArabic, saysNotSureAr } from './customer_questions.ts';
import { HOME_TRADES } from './customer_questions_home.ts';
import { BUILDING_TRADES } from './customer_questions_building.ts';
import { WORKS_TRADES } from './customer_questions_works.ts';
import { COMMERCIAL_TRADES } from './customer_questions_commercial.ts';
import { SERVICES_TRADES } from './customer_questions_services.ts';
import { INDUSTRIAL_TRADES } from './customer_questions_industrial.ts';
import { GOODS_TRADES } from './customer_questions_goods.ts';
import { checklistsOf as tradeChecklists, packFields, type TradeContext } from './inquiry_trades.ts';
import { checklistsOf as loaderRows, specCode } from '../../../scripts/kb/load_trade_spec_checklists.mjs';

const ROOT = new URL('../../../', import.meta.url);
type Pack = { trade: string; entries: { id: string; kind: string; required_specs?: string[]; blocking?: string[] }[] };
const packs: Pack[] = [...Deno.readDirSync(new URL('knowledge/packs/', ROOT))]
  .filter((e) => e.name.endsWith('.json') && !e.name.includes('.market.') && !e.name.includes('.draft.'))
  .map((e) => JSON.parse(Deno.readTextFileSync(new URL('knowledge/packs/' + e.name, ROOT))));
const allCodes = new Set(packs.flatMap((p) => (p.entries ?? []).filter((e) => e.kind === 'spec_checklist').flatMap((e) => (e.required_specs ?? []).map(specCode))));
const latinWords = (s: string) => (s.match(/[A-Za-z]{2,}/g) ?? []);

Deno.test('every entry names a real spec of a pack (or a universal field), in plain English and Arabic, with no English in the Arabic', () => {
  for (const [code, q] of Object.entries(CUSTOMER_QUESTION)) {
    assert(allCodes.has(code) || ['location', 'payment_terms'].includes(code), `${code}: no pack has this spec`);
    assert(q.en.trim() && q.ar.trim(), `${code}: a language is missing`);
    for (const ar of [q.ar, q.eg_ar ?? '', q.alt_ar ?? '', ...(q.options ?? []).map((o) => o[1])]) {
      assertEquals(latinWords(ar), [], `${code}: English in the Arabic: ${ar}`);
      if (ar) assert(/[؀-ۿ]/.test(ar), `${code}: not Arabic: ${ar}`);
    }
    assertEquals(!!q.eg_en, !!q.eg_ar, `${code}: an example in one language only`);
    assertEquals(!!q.alt_en, !!q.alt_ar, `${code}: an alternative in one language only`);
  }
  assertEquals(latinWords(ARABIC_FRAME), []);
});

Deno.test('every HVAC split-AC spec and every blocking HVAC spec has its plain question; capacity offers the photo of the label', () => {
  const hvac = packs.find((p) => p.trade === 'hvac')!;
  const split = hvac.entries.find((e) => e.id === 'hvac:spec-split-ac')!;
  const universal = new Set(['spec_site_location_and_emirate', 'spec_payment_terms']);
  for (const s of split.required_specs!) if (!universal.has(specCode(s))) assert(CUSTOMER_QUESTION[specCode(s)], `split AC: ${s}`);
  for (const e of hvac.entries) for (const b of e.blocking ?? []) if (!universal.has(specCode(b))) assert(CUSTOMER_QUESTION[specCode(b)], `${e.id}: blocking ${b}`);
  const cap = plainOf('spec_cooling_capacity', 'cooling capacity (BTU/h, TR or kW) per unit');
  assert(/photo of the sticker/.test(cap.question_plain_en) && /صورة الملصق/.test(cap.question_plain_ar!), cap.question_plain_en);
  assertEquals(cap.options.at(-1), NOT_SURE.en);
  assertEquals(cap.options_ar.at(-1), NOT_SURE.ar);
});

Deno.test('the supplier keeps the technical label; the customer reads the plain question beside it', () => {
  const rows = loaderRows(JSON.parse(Deno.readTextFileSync(new URL('knowledge/packs/hvac.json', ROOT))), 'hvac.json');
  const ctx: TradeContext = { codes: ['hvac'], trades: [{ code: 'hvac', label: 'HVAC', group_code: 'mep_building_systems' }], services: [], specs: {}, approvals: {}, checklists: tradeChecklists(rows) };
  const fs = packFields(ctx, ['hvac:spec-split-ac']);
  const cap = fs.find((f) => f.key === 'spec_cooling_capacity')!;
  assertEquals(cap.question, 'Cooling capacity (BTU/h, TR or kW) per unit');   // what the supplier and the model's checklist read
  assert(cap.question_plain_en!.startsWith('How big is each AC unit?'));
  assert(cap.question_plain_ar!.startsWith('ما حجم كل وحدة تكييف؟'));
  assertEquals(cap.options, [], 'a pack spec stays free text for the interview\'s readers');
  assert(cap.card_options!.includes(NOT_SURE.en) && cap.card_options_ar!.includes(NOT_SURE.ar));
  assertEquals(fs.find((f) => f.key === 'location')?.question_plain_ar, 'أين موقع العمل، وفي أي إمارة؟ مثلًا: فيلا في البرشاء، دبي.');
});

Deno.test('a spec with no entry: its label as a plain English question without the unit list, and no Arabic of its own', () => {
  assertEquals(plainFrame('size (DN) and pressure class (PN or ANSI class)'), 'Size and pressure class? If you are not sure, tap "Not sure" and the supplier will advise.');
  const p = plainOf('spec_zz_nothing', 'zz thing (a, b)');
  assertEquals([p.plain, p.question_plain_ar, p.options, p.options_ar], [false, undefined, [NOT_SURE.en], [NOT_SURE.ar]]);
});

Deno.test('what a word means, from the glossary, in the customer\'s language; a word it does not hold adds nothing', () => {
  assert(explainTerms(['BTU'], 'en').startsWith('BTU measures how much cooling'));
  assert(explainTerms(['"heat-load"'], 'ar').startsWith('حساب الحمل الحراري'));
  assertEquals(explainTerms(['BTU', 'btu'], 'en').split('BTU measures').length, 2, 'each explained once');
  assertEquals(explainTerms(['zzword'], 'en'), '');
  assertEquals(explainTerms('BTU', 'en'), '');
  for (const g of GLOSSARY) assert(g.en.trim() && /[؀-ۿ]/.test(g.ar), g.terms.join('/'));
});

// Coverage is MEASURED over the packs as the loader reads them, per trade, and printed. Every blocking spec of every pack has its
// plain wording (16 Nov 2026: 1,604 of 1,604, 1,273 distinct spec codes; before the sweep 309 of 1,604).
const UNIVERSAL = ['spec_site_location_and_emirate', 'spec_payment_terms'];
const hasPlain = (code: string) => !!CUSTOMER_QUESTION[code] || UNIVERSAL.includes(code);
Deno.test('coverage across every pack (measured, printed): every blocking spec a customer is asked has plain wording in both languages', () => {
  let blocking = 0, covered = 0;
  const perTrade = new Map<string, [number, number]>();
  const missing: string[] = [];
  for (const p of packs) for (const e of p.entries ?? []) if (e.kind === 'spec_checklist') for (const b of e.blocking ?? []) {
    blocking++;
    const c = specCode(b), ok = hasPlain(c);
    if (ok) covered++; else missing.push(`${p.trade}: ${b}`);
    const t = perTrade.get(p.trade) ?? [0, 0];
    t[0]++; if (ok) t[1]++;
    perTrade.set(p.trade, t);
  }
  console.log(`blocking specs with plain wording: ${covered} of ${blocking} (${Object.keys(CUSTOMER_QUESTION).length} distinct spec codes in the table)`);
  const short = [...perTrade].filter(([, [n, c]]) => c < n).map(([t, [n, c]]) => `${t} ${c}/${n}`);
  console.log(`trades not whole: ${short.length ? short.join(', ') : 'none'}`);
  assertEquals(missing, [], 'a blocking spec with no plain wording');
  assertEquals(covered, blocking);
});

Deno.test('every entry gives the customer a way out: the card always ends with "Not sure", never twice', () => {
  for (const [code, q] of Object.entries(CUSTOMER_QUESTION)) {
    const p = plainOf(code, code);
    assertEquals(p.options.at(-1), NOT_SURE.en, code);
    assertEquals(p.options_ar.at(-1), NOT_SURE.ar, code);
    assertEquals(p.options.filter((o) => o === NOT_SURE.en).length, 1, `${code}: Not sure twice`);
    for (const [en, ar] of q.options ?? []) {
      assert(!/not sure/i.test(en) && !saysNotSureAr(ar), `${code}: the table must not carry "Not sure", the card adds it`);
      assert(en.trim() && ar.trim(), `${code}: an option in one language only`);
    }
  }
});

Deno.test('one short question per entry, a concrete example where there is one, Arabic that is not the English', () => {
  const words = (s: string) => s.trim().split(/\s+/).length;
  let over15 = 0, withExample = 0, withAlt = 0, withOptions = 0;
  for (const [code, q] of Object.entries(CUSTOMER_QUESTION)) {
    assert(words(q.en) <= 25, `${code}: too long to read in a chat (${words(q.en)} words)`);
    if (words(q.en) > 15) over15++;
    assert((q.en.match(/\?/g) ?? []).length <= 2, `${code}: more than one question`);
    assert(q.en !== q.ar && /^[^A-Za-z]*$|[؀-ۿ]/.test(q.ar), code);
    if (q.eg_en) { withExample++; assert(q.eg_en.startsWith('For example:') || /^[A-Z]/.test(q.eg_en), `${code}: example`); }
    if (q.alt_en) withAlt++;
    if (q.options?.length) withOptions++;
  }
  console.log(`entries ${Object.keys(CUSTOMER_QUESTION).length}: ${withExample} with an example, ${withAlt} with a practical alternative, ${withOptions} with tap options, ${over15} over 15 words`);
  assert(over15 <= 40, `questions are getting long: ${over15} over 15 words`);
  assert(withExample >= 700, `examples fell: ${withExample}`);
});

// The customer is never asked for who they are: no name, address, plot number, phone, e-mail, passport or ID. A sentence that TELLS
// the customer not to send one ("no exact address", "do not send names") is the opposite of an ask and is not read.
Deno.test('no entry asks for anything that identifies the customer', () => {
  const stripNegations = (s: string) => s.replace(/(?:\bno\b|\bnot\b|\bwithout\b|\bdo not\b|بدون|لا حاجة|لا تحتاج|وبدون|ولا)[^.]*\./gi, ' ');
  const idEn = /\b(your|my|full|exact|street|home|company|person'?s)\s+(name|address)\b|\bphone number\b|\bmobile number\b|\bwhatsapp\b|\be-?mail address\b|\bplot number\b|\bmakani\b|\bpassport\b|\bemirates id\b|\bid number\b|\blicen[cs]e number\b|\bpermit number\b|\bregistration number\b|\bnames? of\b/i;
  const idAr = /اسمك|اسم الشركة|اسم الشخص|رقم الهاتف|رقم الجوال|بريدك|رقم الهوية|رقم الجواز|رقم قطعة الأرض|رقم الأرض|رقم الرخصة|رقم التسجيل|عنوانك|العنوان الكامل/;
  // the check itself must bite, and must let a prohibition through
  assert(idEn.test('What is your name?') && idEn.test('Send the plot number.') && idAr.test('ما رقم الهاتف؟'));
  assert(!idEn.test(stripNegations('Area only, no exact address.')));
  // nor for a paper that carries who they are (a utility bill, the company logo, a registration or access card): ask for the
  // figure on it instead; the logo goes to the supplier only after the customer has chosen it (anonymity until reveal)
  const paperEn = /\b(send|photo|copy of|attach|upload)\b[^.?;]*\b(bills?|logo|registration card|card)\b/i;
  const paperAr = /(أرسلوا|صورة|إرسال)[^.؟،]*(فاتورة|الفاتورة|فواتير|الشعار|ملكية|البطاقة)/;
  assert(paperEn.test('Send a photo of a recent bill.') && paperEn.test('Send your logo as it is.') && paperAr.test('أرسلوا صورة فاتورة حديثة.'));
  for (const [code, q] of Object.entries(CUSTOMER_QUESTION)) {
    for (const s of [q.en, q.eg_en ?? '', q.alt_en ?? '']) assert(!paperEn.test(stripNegations(s)), `${code}: asks for a paper that identifies the customer: ${s}`);
    for (const s of [q.ar, q.eg_ar ?? '', q.alt_ar ?? '']) assert(!paperAr.test(stripNegations(s)), `${code}: asks for a paper that identifies the customer: ${s}`);
  }
  for (const [code, q] of Object.entries(CUSTOMER_QUESTION)) {
    for (const s of [q.en, q.eg_en ?? '', q.alt_en ?? '']) assert(!idEn.test(stripNegations(s)), `${code}: asks for something identifying: ${s}`);
    for (const s of [q.ar, q.eg_ar ?? '', q.alt_ar ?? '']) assert(!idAr.test(stripNegations(s)), `${code}: asks for something identifying: ${s}`);
  }
});

// The register (native Arabic review, 15 Nov 2026): every Arabic line addresses the customer in the formal plural, never the
// masculine singular a literal translation of "you" produces. The words below are second-person singular in every context they
// can appear in on a question card (a feminine third-person "تحتاج الغرفة" is not in the list, so it is not caught).
Deno.test('the Arabic addresses the customer in the formal plural, as every customer message of the company does', () => {
  const L = '\u0621-\u064A\u064B-\u0652';
  const singular = new RegExp(`(?<![${L}])(?:[وف]?(?:تريد|تريده|تريدها|لديك|عندك|يمكنك|أرسل|أخبرنا|اذكر|اختر|اكتب|أنت|بكلماتك)|لا تعرف؟|إن لم تكن متأكد[اًً]*)(?![${L}])`);
  assert(singular.test('هل تريد وحدات؟') && singular.test('لا تعرف؟ أرسل صورة.') && !singular.test('هل تريدون وحدات؟ أرسلوا صورة.'));
  for (const [code, q] of Object.entries(CUSTOMER_QUESTION)) {
    for (const s of [q.ar, q.eg_ar ?? '', q.alt_ar ?? '']) assert(!singular.test(s), `${code}: singular address: ${s}`);
  }
  assert(!singular.test(ARABIC_FRAME), ARABIC_FRAME);
});

Deno.test('the trade tables do not overlap: a spec code has ONE wording, so a later table can never silently replace an earlier one', () => {
  const tables: Record<string, Record<string, unknown>> = { HOME_TRADES, BUILDING_TRADES, WORKS_TRADES, COMMERCIAL_TRADES, SERVICES_TRADES, INDUSTRIAL_TRADES, GOODS_TRADES };
  const seen = new Map<string, string>();
  const clashes: string[] = [];
  for (const [name, t] of Object.entries(tables)) for (const k of Object.keys(t)) {
    if (seen.has(k)) clashes.push(`${k}: ${seen.get(k)} and ${name}`);
    seen.set(k, name);
  }
  assertEquals(clashes, []);
  const total = Object.values(tables).reduce((n, t) => n + Object.keys(t).length, 0);
  assert(Object.keys(CUSTOMER_QUESTION).length >= total, 'a table is not merged into CUSTOMER_QUESTION');
});

Deno.test('a category option\'s Arabic label comes from the portal\'s one table; none without an Arabic letter; diacritics do not matter', () => {
  assertEquals(optionAr('Supply only'), 'توريد فقط');
  assertEquals(optionAr('supply ONLY'), 'توريد فقط');
  assertEquals(optionAr('VRF/VRV'), null, 'a label with no Arabic letter is not an Arabic label');
  assertEquals(optionAr('zz no such option'), null);
  assert(sameArabic('لست متأكداً', 'لست متأكدًا'));
});
