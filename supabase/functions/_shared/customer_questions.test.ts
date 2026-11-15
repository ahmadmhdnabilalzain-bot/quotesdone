// What the customer reads for a spec (customer_questions.ts): plain words in both languages, an example, "Not sure", and the
// supplier-facing label left exactly as the pack wrote it. Read against the repository packs, as the loader maps them.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { ARABIC_FRAME, CUSTOMER_QUESTION, explainTerms, GLOSSARY, NOT_SURE, optionAr, plainFrame, plainOf, sameArabic } from './customer_questions.ts';
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

Deno.test('coverage across every pack (measured, printed): the blocking specs a customer is asked in plain Arabic', () => {
  let blocking = 0, covered = 0;
  for (const p of packs) for (const e of p.entries ?? []) if (e.kind === 'spec_checklist') for (const b of e.blocking ?? []) {
    blocking++;
    const c = specCode(b);
    if (CUSTOMER_QUESTION[c] || ['spec_site_location_and_emirate', 'spec_payment_terms'].includes(c)) covered++;
  }
  console.log(`blocking specs with plain Arabic wording: ${covered} of ${blocking}`);
  assert(covered >= 240, `coverage fell: ${covered}`);
});

Deno.test('a category option\'s Arabic label comes from the portal\'s one table; none without an Arabic letter; diacritics do not matter', () => {
  assertEquals(optionAr('Supply only'), 'توريد فقط');
  assertEquals(optionAr('supply ONLY'), 'توريد فقط');
  assertEquals(optionAr('VRF/VRV'), null, 'a label with no Arabic letter is not an Arabic label');
  assertEquals(optionAr('zz no such option'), null);
  assert(sameArabic('لست متأكداً', 'لست متأكدًا'));
});
