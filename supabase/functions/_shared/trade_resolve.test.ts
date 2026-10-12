// trade_resolve — a supplier's text names a trade by an exact code or by meaning, never by its words.
// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/trade_resolve.test.ts
//
// The exact path is decided by public.fn_norm_trades in production (fn_norm_trades_many). Offline it is given
// EXACT below: the same rule (fn_trade_code equality with a live code or an intake slug), over a slice of the live
// codes and slugs. scripts/checks/a_suppliers_documents_name_trades_by_exact_code_or_meaning_never_by_words.test.mjs
// runs the real routine and the real gte-small model on ZZ DEMO documents.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { exactCandidates, nameForms, textLines, tradesOfText, withoutNames, type TradeResolveDeps } from './trade_resolve.ts';
import type { MeaningService } from './service_meaning.ts';
import { meaningClauses } from './service_meaning.ts';
import { isNameOrReachLine } from './catalogue_read.ts';
import FIXTURES from './trade_words.fixtures.json' with { type: 'json' };

// fn_trade_code, and fn_taxonomy_trades_for over a slice of production (29 Sep 2026): codes resolve to themselves,
// an intake slug to its codes.
const code = (s: string) => s.trim().toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '_').replace(/^_+|_+$/g, '');
const CODES = ['hvac', 'plumbing', 'electrical', 'joinery', 'interior_fitout', 'aluminium', 'glazing', 'painting', 'office_equipment', 'pos_retail'];
const SLUGS: Record<string, string[]> = { carpentry: ['joinery'], fitout: ['interior_fitout'], glass: ['glazing'] };
const EXACT = async (phrases: string[]) => {
  const out: Record<string, string[]> = {};
  for (const p of phrases) {
    const c = code(p);
    const codes = [...new Set([...(CODES.includes(c) ? [c] : []), ...(SLUGS[c] ?? [])])];
    if (codes.length) out[p] = codes;
  }
  return out;
};

// Three services with hand-made vectors (the rules are tested here; the live model in the check).
const SERVICES: MeaningService[] = [
  { trade_code: 'office_equipment', code: 'printers_mfp', label_en: 'Printers & copiers', label_ar: 'الطابعات وآلات النسخ', aliases: [], vec: [1, 0, 0] },
  { trade_code: 'plumbing', code: 'drainage', label_en: 'Drainage works', label_ar: 'أعمال الصرف', aliases: [], vec: [0, 1, 0] },
  { trade_code: 'hvac', code: 'chiller_maintenance', label_en: 'Chiller maintenance', label_ar: 'صيانة المبردات', aliases: [], vec: [0, 0, 1] },
];
const VEC: Record<string, number[]> = {
  'We distribute office printers': [0.99, 0.1, 0],   // clauses: meaningClauses splits at 'and'
  'Gold partner of the leading brands': [0.95, 0.2, 0.1],            // near printers, and no head word: never accepted
  'drainage maintenance': [0.05, 0.97, 0.1],
};
const deps = (o: Partial<TradeResolveDeps> = {}): TradeResolveDeps => ({
  normTrades: EXACT, services: SERVICES, embed: async (t) => VEC[t] ?? [0.3, 0.3, 0.3], budget: { left: 16 }, ...o,
});
const codes = (r: { trades: { code: string }[] }) => r.trades.map((t) => t.code).sort();

Deno.test('words alone decide nothing: no fixture sentence resolves by the exact path', async () => {
  const noMeaning = deps({ embed: async () => null, budget: { left: 1e6 } });
  for (const f of FIXTURES as { text: string; codes: string[] }[]) {
    const r = await tradesOfText(f.text, noMeaning);
    assertEquals(codes(r), [], `"${f.text}" named a trade by its words`);
    // 7 Oct 2026: a fixture whose every clause is one word is not read by meaning at all (a single word is a code or nothing), so its
    // state is nothing_to_read; every longer one still reports that the embedding could not be read.
    const one = (s: string) => s.trim().split(/\s+/).length < 2;
    const oneWordEach = f.text.split(/\n/).every((l) => !one(l) && meaningClauses(l).every(one));
    // 12 Oct 2026: a fixture made only of name / contact lines is not read at all (isNameOrReachLine)
    const contactOnly = f.text.split(/\n/).every((l) => isNameOrReachLine(l.trim()));
    assertEquals(r.meaning, oneWordEach || contactOnly ? 'nothing_to_read' : 'embedding_unavailable', f.text);
  }
  // the sentence trade_words.ts read as plumbing because two aliases occur in it
  assertEquals(codes(await tradesOfText('Activities: Plumbing works and drainage maintenance', noMeaning)), []);
});

Deno.test('the exact path: a line that IS a code or a slug, with the line as evidence', async () => {
  const r = await tradesOfText('ZZ DEMO COMPANY PROFILE\nOur divisions:\nHVAC\nCarpentry, Glass\nWe do plumbing works', deps({ embed: async () => null }));
  assertEquals(r.exact, 'on');
  assertEquals(codes(r), ['glazing', 'hvac', 'joinery']);
  const h = r.trades.find((t) => t.code === 'hvac')!;
  assertEquals(h.via, 'exact_code');
  assertEquals(h.phrases, ['hvac']);
  assertEquals(h.snippet, 'HVAC');
  assertEquals(r.trades.find((t) => t.code === 'glazing')!.snippet, 'Carpentry, Glass');
});

Deno.test('the meaning path: a line that MEANS a service names its trade, only with the head word in it', async () => {
  const r = await tradesOfText('We distribute office printers and copiers\nGold partner of the leading brands', deps());
  assertEquals(r.meaning, 'on');
  assertEquals(codes(r), ['office_equipment']);
  const h = r.trades[0];
  assertEquals(h.via, 'meaning');
  assertEquals(h.phrases, ['printers & copiers']);
  assertEquals(h.snippet, 'We distribute office printers and copiers');
  assert(h.similarity! > 0.9);
  // the old example, read by meaning: drainage names plumbing through the service, with "drainage" as its head word
  assertEquals(codes(await tradesOfText('Activities: Plumbing works and drainage maintenance', deps())), ['plumbing']);
});

Deno.test('a path that could not run says so; it is never an empty answer', async () => {
  assertEquals((await tradesOfText('HVAC', deps({ normTrades: async () => null }))).exact, 'unavailable');
  assertEquals((await tradesOfText('We distribute office printers', deps({ services: SERVICES.map((s) => ({ ...s, vec: null })) }))).meaning, 'service_vectors_missing');
  assertEquals((await tradesOfText('We distribute office printers', deps({ embed: async () => { throw new Error('down'); } }))).meaning, 'embedding_unavailable');
  assertEquals((await tradesOfText('', deps())).meaning, 'nothing_to_read');
  assertEquals((await tradesOfText('', deps())).exact, 'nothing_to_read');
});

Deno.test('meaning shares one line budget across every text read with the same deps', async () => {
  const d = deps({ budget: { left: 2 } });
  const first = await tradesOfText('line one here\nline two here\nline three here', d);
  assertEquals(first.meaning, 'on');
  assertEquals(d.budget.left, 0);
  assertEquals((await tradesOfText('We distribute office printers and copiers', d)).meaning, 'budget_spent');
});

Deno.test('exact candidates are lines and list items of a few words, once', () => {
  const lines = textLines('HVAC\n  HVAC  \nPlumbing, Painting; Joinery\nWe are a leading contracting company based in Dubai with many years');
  assertEquals(lines.length, 3);
  const c = exactCandidates(lines);
  for (const p of ['HVAC', 'Plumbing', 'Painting', 'Joinery']) assert(c.includes(p), p);
  assert(!c.some((p) => p.startsWith('We are a leading')), 'a sentence is not a code candidate');
});

// 12 Oct 2026 (sales_engineer): an Arabic licence activity names its trade by the trade's own Arabic name, exactly.
// The table rows are production's taxonomy_trade (label_ar) as read that day; pest_control shares مكافحة with fire
// fighting. The activities are scripts/e2e/document_intake_corpus.mjs ACT_AR with their trades (not imported: that
// module needs node's sharp).
import { arabicNameHeads, tradesByArabicName } from './trade_resolve.ts';
Deno.test('an Arabic work clause names a trade by its own Arabic name; a company name and a trading clause name none', () => {
  const ar: Record<string, string> = {
    aluminium: 'الألمنيوم والتكسية', non_ferrous_metals: 'الألمنيوم والنحاس والمعادن غير الحديدية', electrical: 'الأعمال الكهربائية',
    elevators: 'المصاعد والسلالم المتحركة', fire_fighting: 'مكافحة الحريق وأنظمة السلامة', pest_control: 'مكافحة الحشرات والقوارض',
    flooring: 'الأرضيات', glazing: 'الزجاج والواجهات الزجاجية', hvac: 'التكييف والتهوية', joinery: 'النجارة والأعمال الخشبية',
    landscaping: 'تنسيق الحدائق والمسابح', painting: 'الدهانات والتشطيبات', plumbing: 'السباكة والأدوات الصحية', waterproofing: 'العزل المائي والحراري', thermal_insulation: 'العزل الحراري والصوتي',
  };
  const en = { aluminium: 'Aluminium & cladding', non_ferrous_metals: 'Aluminium, copper & non-ferrous metals' };
  const heads = arabicNameHeads(ar, en);
  const of = (s: string) => tradesByArabicName(s, heads).map((x) => x.code);
  assertEquals(of('أعمال الألمنيوم'), ['aluminium']);
  assertEquals(of('فالكون الألمنيوم ذ.م.م'), [], 'a company name names no work');
  assertEquals(of('تجارة الألمنيوم والنحاس'), [], 'trading is not contracting');
  // a word of a LATER part of a name decides nothing (review of #1312): أدوات, أنظمة, التشطيبات
  assertEquals(of('تركيب أدوات المطبخ'), [], 'not plumbing');
  assertEquals(of('تركيب أنظمة الأمن'), [], 'not fire fighting');
  assertEquals(of('أعمال التشطيبات الداخلية'), [], 'not painting');
  assertEquals(of('أعمال الأدوات الصحية'), ['plumbing'], 'a whole later part does');
  // nor does the first word of a longer FIRST part (review of #1312, second round)
  assertEquals(of('أعمال تنسيق المشاريع'), [], 'not landscaping');
  assertEquals(of('مقاولات تنسيق المواقع'), [], 'not landscaping');
  assertEquals(of('أعمال تنسيق المشاريع والحدائق'), [], 'the name\'s words must stand together');
  const ACT_AR: [string, string | null][] = [
    ['مقاولات أعمال الألمنيوم', 'aluminium'], ['مقاولات التركيبات الكهربائية', 'electrical'], ['تركيب التمديدات الصحية والسباكة', 'plumbing'],
    ['تركيب أنظمة التكييف والتهوية', 'hvac'], ['أعمال تبليط الأرضيات والجدران', 'flooring'], ['أعمال النجارة', 'joinery'],
    // none, exactly: 'الدهان' is not the name 'الدهانات', and 'عزل' heads three trades' names (waterproofing,
    // thermal and corrosion insulation) - reached by the trade's Arabic name, not by folding here
    ['مقاولات أعمال الدهان', null], ['أعمال عزل المباني ضد الماء', null], ['أعمال تنسيق الحدائق', 'landscaping'],
    ['أعمال الزجاج', 'glazing'], ['تركيب وصيانة المصاعد والسلالم المتحركة', 'elevators'], ['تركيب معدات مكافحة الحريق', 'fire_fighting'],
    ['تجارة عامة', null], ['استيراد وتصدير', null],
  ];
  for (const [act, trade] of ACT_AR) assertEquals(of(act), trade ? [trade] : [], act);
});
// 12 Oct 2026 (sales_engineer, accuracy suite): a company's NAME line proposes no trade by any path. Measured live:
// "Legal Name: ZZ DEMO Falcon Cleaning LLC" -> cleaning, its label -> legal_services (0.82), "... Glazing LLC" -> glazing (0.821).
Deno.test('a name or contact line is read by no path; the work line beside it still is', async () => {
  const asked: string[] = [];
  const deps: TradeResolveDeps = {
    normTrades: async (p) => { asked.push(...p); return Object.fromEntries(p.map((x) => [x, ['cleaning']])); },
    services: [{ trade_code: 'cleaning', code: 'office', label_en: 'Office cleaning', label_ar: '', aliases: [], vec: [1, 0] }],
    embed: async (t) => { asked.push(t); return [1, 0]; },
    budget: { left: 40 },
  };
  const names = ['Legal Name: ZZ DEMO Falcon Cleaning LLC', 'Legal Name: ZZ DEMO Falcon Glazing LLC', 'ZZ DEMO Falcon Cleaning L.L.C - Company Profile'];
  const r = await tradesOfText(names.join('\n'), deps);
  assertEquals([r.trades, asked.filter((a) => /LLC|L\.L\.C/.test(a))], [[], []]);
  const w = await tradesOfText([...names, 'Office cleaning works'].join('\n'), { ...deps, budget: { left: 40 } });
  assertEquals(w.trades.map((t) => t.code), ['cleaning'], 'the work line is still read');
  // #1313 review: work lines carrying "mobile", an address word or a number are NOT name lines
  for (const l of ['Mobile crane hire', 'Office fit-out, 3 floors', 'Warehouse racking up to 12 m', '24/7 building maintenance', 'Road works phase 2', 'Double glazed units 6+12+6 mm'])
    assertEquals(isNameOrReachLine(l), false, l);
  for (const l of ['Tel: +971 4 123 4567', 'sales@zzdemo.example.invalid', 'www.zzdemo.example.invalid', 'ZZ DEMO Falcon FZE', 'فالكون للألمنيوم ذ.م.م', 'Call 04 123 4567'])
    assertEquals(isNameOrReachLine(l), true, l);
});
// 12 Oct 2026 (sales_engineer, unsuffixed-names): a name printed WITHOUT a legal suffix is known by the licence layout
// (its labelled name fields) and by the supplier's known names, exactly; the activity line beside it still proposes.
Deno.test('an unsuffixed name line proposes nothing; the work line beside it still does', async () => {
  const asked: string[] = [];
  const deps: TradeResolveDeps = {
    normTrades: async (p) => { asked.push(...p); return Object.fromEntries(p.filter((x) => /clean|floor|التنظيف/i.test(x)).map((x) => [x, ['cleaning']])); },
    services: [{ trade_code: 'cleaning', code: 'office', label_en: 'Office cleaning', label_ar: '', aliases: [], vec: [1, 0] }],
    embed: async (t) => { asked.push(t); return [1, 0]; },
    budget: { left: 40 },
  };
  const nameLines = ['ZZ DEMO Falcon Cleaning', 'ZZ DEMO Falcon Cleaning - Company Profile', 'Trade Name: Horizon Floor',
    'الاسم التجاري: زد زد ديمو الأفق للتنظيف', 'Company Name : ZZ DEMO Pearl Cleaning'];
  const opts = { names: ['ZZ DEMO Falcon Cleaning LLC'] };
  const r = await tradesOfText(nameLines.join('\n'), deps, opts);
  assertEquals([r.trades, asked.filter((a) => /falcon|horizon|pearl|الأفق|trade name|company name/i.test(a))], [[], []]);
  const w = await tradesOfText([...nameLines, 'ZZ DEMO Falcon Cleaning provides office cleaning works'].join('\n'), { ...deps, budget: { left: 40 } }, opts);
  assertEquals(w.trades.map((t) => t.code), ['cleaning'], 'the work line is still read');
  assert(w.trades[0].snippet.startsWith('provides office cleaning'), w.trades[0].snippet);
  // exact only: a name that merely resembles the company's is not cut
  assertEquals(withoutNames('Falcon cleaning works', nameForms(['ZZ DEMO Falcon Cleaning LLC'])), 'Falcon cleaning works');
  assertEquals(nameForms(['ZZ DEMO Falcon Cleaning L.L.C.', 'Ab', null]), ['zz demo falcon cleaning l.l.c.', 'zz demo falcon cleaning']);
});
