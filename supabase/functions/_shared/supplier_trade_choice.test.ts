// supplier_trade_choice — the model chooses a supplier's trades from our codes; code proves every one by its quote.
// Regression fixtures from the 29 real UAE profiles measured on 13 Oct 2026 (ACCURACY_real_profiles.md), names
// replaced by ZZ DEMO. deno test --no-lock --node-modules-dir=none supabase/functions/_shared/supplier_trade_choice.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { checkChoice, majority, needsThird, settleReadings, checkVerify, choiceRequest, choiceSystem, isHeading, mergeChoices, quoteContext, quoteKey, textChunks, verifyRequest, type TradeDef } from './supplier_trade_choice.ts';
import { readDocForTrades, type TradeResolveDeps } from './supplier_doc_trades.ts';

/** A model-labelled quote: what the line is in the document. */
const F = (text: string, form = 'list_item') => ({ text, form });
const DEFS: TradeDef[] = [
  { code: 'joinery', label: 'Joinery & carpentry', services: ['Kitchens', 'Wardrobes & closets'] },
  { code: 'fire_fighting', label: 'Fire fighting & life safety', services: ['Sprinkler systems', 'Fire alarm systems'] },
  { code: 'it_services', label: 'IT services', services: ['Network installation'] },
  { code: 'doors', label: 'Doors', services: ['Wooden doors'] },
];
const DOC = 'ZZ DEMO Joinery LLC\nScope of Work: Supply & Installation of Doors, Kitchen,\nWardrobes and Vanity Cabinets\nWe take up Service, Installation & Maintenance of:\nSprinkler Systems, Foam System';

Deno.test('every trade the model names is proven by a quote that is in the document; anything else is refused', () => {
  const r = checkChoice(JSON.stringify({ trades: [
    { code: 'fire_fighting', quotes: [F('Sprinkler Systems, Foam System')], reason: 'it installs sprinklers' },
    { code: 'hvac', quotes: [F('Sprinkler Systems')], reason: 'not one of our codes' },                    // not an active code
    { code: 'doors', quotes: [F('')], reason: 'no quote' },                                                    // no quote
    { code: 'it_services', quotes: [F('We install data networks')], reason: 'made up' },                      // not in the text
  ] }), DOC, DEFS);
  assert(r.ok);
  assertEquals(r.trades.map((t) => t.code), ['fire_fighting']);
  assertEquals(r.rejected.map((x) => x.code), ['hvac', 'doors', 'it_services']);
});

Deno.test('a quote that runs across a PDF line break is still found, line by line (Royal Joinery, run 4)', () => {
  const r = checkChoice(JSON.stringify({ trades: [{ code: 'joinery', quotes: [F('Supply & Installation of Doors, Kitchen,\nWardrobes and Vanity Cabinets')], reason: 'kitchens and wardrobes' }] }), DOC, DEFS);
  assert(r.ok);
  assertEquals(r.trades.map((t) => t.code), ['joinery']);
  assertEquals(quoteKey('Doors,  Kitchen,'), 'doors kitchen');
});

Deno.test('prose instead of JSON is not an answer', () => {
  const r = checkChoice('The company does joinery.', DOC, DEFS);
  assertEquals(r.ok, false);
});

Deno.test('the second look keeps only what it kept; history and internal functions are dropped (C03, C06, run 5)', () => {
  const chosen = { trades: [
    { code: 'joinery', quote: 'Wardrobes and Vanity Cabinets', reason: 'wardrobes' },
    { code: 'doors', quote: 'Doors', reason: 'began as a wooden doors trading company, only as history' },
    { code: 'it_services', quote: 'network', reason: 'its IT department maintains its own network (internal)' },
  ], rejected: [] };
  const r = checkVerify(JSON.stringify({ keep: ['joinery'], drop: [{ code: 'doors', why: 'history' }, { code: 'it_services', why: 'internal' }] }), chosen);
  assert(r.ok);
  assertEquals(r.trades.map((t) => t.code), ['joinery']);
  assertEquals(r.rejected.map((x) => x.code), ['doors', 'it_services']);
  assertEquals(checkVerify('ok', chosen).ok, false, 'an unreadable check proposes nothing');
});

Deno.test('the prompt carries every trade with its definition, and the request routes to its own model policy', () => {
  const s = choiceSystem(DEFS);
  assert(s.includes('joinery = Joinery & carpentry (covers: Kitchens; Wardrobes & closets)'));
  const req = choiceRequest('text', 'profile', DEFS, null);
  assertEquals([req.fn, req.temperature], ['supplier_doc_trades', 0]);
  assert(String(req.sys_stable).length > 0, 'the definitions are the cacheable part');
});

Deno.test('a profile whose trades could not be chosen proposes NOTHING and says why (never a guess)', async () => {
  const deps: TradeResolveDeps = { chooseTrades: async () => ({ ok: false, error: 'model unavailable (502): breaker open' }) };
  const ev = await readDocForTrades({ path: 'p', name: 'p.txt', kind: 'profile', photo_text: 'We install sprinkler systems' }, deps);
  assertEquals([ev.status, ev.choice, ev.trades.length], ['read', 'unavailable', 0]);
  assert(/breaker open/.test(ev.reason || ''), ev.reason);
  const ok = await readDocForTrades({ path: 'p', name: 'p.txt', kind: 'profile', photo_text: 'We install sprinkler systems' },
    { ...deps, chooseTrades: async (t) => checkChoice(JSON.stringify({ trades: [{ code: 'fire_fighting', quotes: [F('install sprinkler systems')], reason: 'r' }] }), t, DEFS) });
  // text read off a picture: chosen and quoted, and PROPOSED for the supplier to confirm (ledger 1442; held for the sales engineer before)
  assertEquals([ok.trades.map((t) => [t.code, t.via]), ok.vision_held], [[['fire_fighting', 'model_choice']], undefined]);
});

Deno.test('the second look sees the quote with the lines around it (Al Nas Elevators, run 7: a quote cut short)', () => {
  const text = 'ABOUT US\nZZ DEMO Elevator company offers a comprehensive range of products and services including\nsupply and installation, modernization, maintenance of elevators and escalators etc.\nWe are an ISO certified company.';
  const c = quoteContext(text, 'supply and installation, modernization,');
  assert(c.includes('maintenance of elevators and escalators'), c);
  assertEquals(quoteContext(text, 'not in the text at all'), 'not in the text at all');
});

Deno.test('an answer in a code fence or after a sentence is still read; a failure says what came back (Summertown, run 9)', () => {
  const fenced = 'Here is the result:\n```json\n{"trades":[{"code":"joinery","quotes":[{"text":"Wardrobes and Vanity Cabinets","form":"list_item"}],"reason":"r"}]}\n```\nDone.';
  const r = checkChoice(fenced, DOC, DEFS);
  assert(r.ok);
  assertEquals(r.trades.map((t) => t.code), ['joinery']);
  const bad = checkChoice('I cannot answer that {not json}', DOC, DEFS);
  assert(!bad.ok && /I cannot answer/.test(bad.error), JSON.stringify(bad));
});

// H01, held-out set (review of #1412, 18 Oct 2026): an image-only aluminium and glass profile. Its trades were chosen
// from the vision model's own SUMMARY of services ("Plumbing and sanitary installation", "Painting, tiling and building
// cleaning"), so every quote matched text the model itself had written and six trades it does not sell got through.
// The picture's trades are now chosen only from the lines it PRINTS (license_extract profile.lines, verbatim); a quote
// from a summary is not in those lines and is refused. Lines below are ZZ DEMO paraphrases of the file's kind.
Deno.test('an image-only profile proposes what its PRINTED lines quote, for the supplier to confirm; a summary phrase is refused (H01, ledger 1442)', async () => {
  const { modelReadText } = await import('./supplier_doc_trades.ts');
  const lines = ['ZZ DEMO Aluminium works, Glass works, UPVC windows & doors', 'Glass Partitions', 'Doors & windows'];
  const deps: TradeResolveDeps = {
    chooseTrades: async (t) => checkChoice(JSON.stringify({ trades: [
      { code: 'doors', quotes: [F('Doors & windows')], reason: 'printed service' },
      { code: 'fire_fighting', quotes: [F('Plumbing and sanitary installation')], reason: 'from the summary' },   // not a printed line
    ] }), t, DEFS) };
  const ev = await readDocForTrades({ path: 'p', name: 'p.pdf', kind: 'profile', photo_text: modelReadText('profile', lines) }, deps);
  assertEquals([ev.trades.map((t) => t.code), ev.vision_held], [['doors'], undefined]);   // the summary phrase's trade (fire_fighting) is refused
});

Deno.test('the profile reading asks for printed lines verbatim, never from a certificate or letter', async () => {
  const LX = await import('./licence_extract.ts');
  assert(/copied EXACTLY as printed/.test(LX.SYS_PROFILE) && /never from a certificate, a letter of recommendation/.test(LX.SYS_PROFILE));
  assertEquals(LX.profileExtractRequest({ images: [] }, null).sys, LX.SYS_PROFILE);
});

// 19 Oct 2026, the held-out misses (ACCURACY_real_profiles.md): H08 lost a trade because only its weakest line was
// quoted; H05's "Access Control" sat under an "ELECTRICAL WORKS" heading the second look never saw.
Deno.test('several quotes per code: each is proven on its own, the code stands on any proven one, and the check sees them all', () => {
  const r = checkChoice(JSON.stringify({ trades: [
    { code: 'joinery', quotes: [F('We make bespoke kitchens for everyone'), F('Wardrobes and Vanity Cabinets')], reason: 'r' },   // first one invented
    { code: 'doors', quotes: [F('Invented line one'), F('Invented line two')], reason: 'r' },
  ] }), DOC, DEFS);
  assert(r.ok);
  assertEquals(r.trades.map((t) => [t.code, t.quotes]), [['joinery', ['Wardrobes and Vanity Cabinets']]]);
  assertEquals(r.rejected.map((x) => x.code), ['doors']);
  const req = verifyRequest(r.trades, DEFS, null, DOC);
  assert(JSON.stringify(req.input).includes('Wardrobes and Vanity Cabinets'));
});

Deno.test('the second look is told the list heading a quoted item sits under, found by code', () => {
  const text = 'ZZ DEMO MEP LLC\nPLUMBING WORKS\nWater heaters   Booster pumps\nDrainage lines\nGrease traps\nAbout our quality';
  assert(quoteContext(text, 'Grease traps').startsWith('[under the heading: PLUMBING WORKS]'));
  assert(isHeading('ELECTRICAL       WORKS') && isHeading('Civil :') && !isHeading('Water heaters   Booster pumps') && !isHeading('ISO 9001'));
});

Deno.test('a long document is chosen in chunks on line breaks, and the chunks merge into one list (N05 546, H02 deadline)', () => {
  const text = Array.from({ length: 50 }, (_, i) => 'line ' + i + ' ' + 'x'.repeat(500)).join('\n');
  const parts = textChunks(text, 6000);
  assert(parts.length > 1 && parts.every((p) => p.length <= 6000));
  assertEquals(parts.join('\n'), text);
  const m = mergeChoices([
    { trades: [{ code: 'joinery', quote: 'a', quotes: ['a'], reason: 'r' }], rejected: [{ code: 'doors', why: 'x' }] },
    { trades: [{ code: 'joinery', quote: 'b', quotes: ['b'], reason: 'r' }, { code: 'doors', quote: 'c', reason: 'r' }], rejected: [] },
  ]);
  assertEquals(m.trades.map((t) => [t.code, t.quotes]), [['doors', ['c']], ['joinery', ['a', 'b']]]);
  assertEquals(m.rejected, []);
});
Deno.test('a line that only introduces a list is not a quote (N04: "Our main activities are on :")', () => {
  const r = checkChoice(JSON.stringify({ trades: [{ code: 'doors', quotes: [F('We take up Service, Installation & Maintenance of:')], reason: 'r' }] }), DOC, DEFS);
  assert(r.ok && !r.trades.length);
});
Deno.test('a word hyphenated across a line break is read whole (N07 OCR: "Compa-\nny")', () => {
  const text = 'ZZ DEMO REGC is a leading UAE-based General Contracting Compa-\nny. We install Sprinkler Systems.';
  const r = checkChoice(JSON.stringify({ trades: [{ code: 'fire_fighting', quotes: [F('is a leading UAE-based General Contracting Company. We install Sprinkler Systems.')], reason: 'r' }] }), text, DEFS);
  assert(r.ok && r.trades.length === 1, JSON.stringify(r));
});
Deno.test('majority of readings: a third reading settles a code one of two missed; one vote never passes; no agreement holds the document', () => {
  const r = (codes: string[]) => ({ ok: true as const, trades: codes.map((c) => ({ code: c, quote: c + ' line', reason: 'r' })), rejected: [] });
  assert(needsThird(r(['joinery', 'doors']), r(['joinery'])));
  assert(needsThird(r([]), r(['joinery'])));
  assert(!needsThird(r(['doors', 'joinery']), r(['joinery', 'doors'])));
  // M08: two readings of three name prefab -> kept; a code named once -> dropped
  assertEquals(majority([r(['joinery', 'doors']), r(['joinery']), r(['joinery', 'doors', 'fire_fighting'])])!.trades.map((t) => t.code), ['doors', 'joinery']);
  // one reading alone never passes a code (review of #1483): two empty readings and one full one -> held
  assertEquals(majority([r([]), r([]), r(['doors'])]), null);
  // no code with two votes -> held, never ok and empty
  assertEquals(majority([r(['doors']), r(['joinery']), r(['fire_fighting'])]), null);
  assertEquals(majority([r([]), r([]), r([])]), null);
});
Deno.test('a clean first reading is the only reading; an empty or refused one gets the 19 Oct majority rules unchanged', async () => {
  type R = Awaited<ReturnType<Parameters<typeof settleReadings>[0]>>;
  const r = (codes: string[], rejected: { code: string; why: string }[] = []): R => ({ ok: true, trades: codes.map((c) => ({ code: c, quote: c + ' line', reason: 'r' })), rejected });
  const script = (...rs: R[]) => { let n = 0; const f = async () => rs[n++] ?? { ok: false as const, error: 'no more readings scripted' }; return { f, calls: () => n }; };
  // clean: one reading, its codes as they came (the second look still judges them)
  { const s = script(r(['doors', 'joinery'])); assertEquals((await settleReadings(s.f) as { trades: { code: string }[] }).trades.map((t) => t.code), ['doors', 'joinery']); assertEquals(s.calls(), 1); }
  // empty first reading: a second, then a third on disagreement, then majority (M12: empty readings never pass a code)
  { const s = script(r([]), r(['joinery']), r(['joinery'])); assertEquals((await settleReadings(s.f) as { trades: { code: string }[] }).trades.map((t) => t.code), ['joinery']); assertEquals(s.calls(), 3); }
  // code refused a quote in the first: a second reading; two agreeing readings pass without a third
  { const s = script(r(['joinery'], [{ code: 'doors', why: 'the quote is not in the document: "x"' }]), r(['joinery', 'doors']), r(['joinery']));
    const out = await settleReadings(s.f); assert(out.ok); assertEquals(s.calls(), 2); assertEquals(out.ok && out.trades.map((t) => t.code), ['doors', 'joinery']); }
  // an unknown code is a refusal too: never accepted on one reading
  { const s = script(r(['joinery'], [{ code: 'roofing_x', why: 'not an active trade code' }]), r(['joinery'])); assertEquals((await settleReadings(s.f)).ok, true); assertEquals(s.calls(), 2); }
  // no agreement: held, exactly as before
  { const s = script(r([]), r(['doors']), r(['joinery'])); const out = await settleReadings(s.f); assertEquals(out.ok, false); }
  // a failed first reading is retried by a second; two failures return the first failure
  { const s = script({ ok: false, error: 'model unavailable (502)' }, { ok: false, error: 'again' }); const out = await settleReadings(s.f); assertEquals(out.ok ? null : out.error, 'model unavailable (502)'); assertEquals(s.calls(), 2); }
});
Deno.test('two readings name the same code but code refused both quotes: held (null), never ok and empty', () => {
  const r = (code: string) => ({ ok: true as const, trades: [{ code, quote: code + ' line', reason: 'r' }], rejected: [{ code: 'doors', why: 'the quote is not in the document: "x"' }] });
  // both readings NAME doors (its quote refused in each - namedBy counts that), so doors has 2 votes and is in keep;
  // joinery and fire_fighting have 1 vote each. mergeChoices finds no proven doors quote, so merged.trades is empty.
  // Mutation-checked 19 Oct 2026: without the 'merged.trades.length' guard this test fails.
  assertEquals(majority([r('joinery'), r('fire_fighting')]), null);
});
Deno.test('a trade stands only on a line the model labels list_item, heading or title, and that is in the document (M04)', () => {
  const m04 = 'We have professional experts, team of fully expertise skilled workers competent to carry out technical jobs & civil, structural works.';
  const arabic = 'لدينا فريق من المهندسين ذوي الخبرة القادرين على تنفيذ أعمال الحريق';   // "a team of experienced engineers able to carry out fire works"
  const text = `ZZ DEMO Contracting LLC\n${m04}\nOUR SERVICES\nExpertise in Steel Fabrication\nSprinkler Systems, Foam System\n${arabic}`;
  const defs = [...DEFS, { code: 'steel', label: 'Steel & metal fabrication', services: ['Metal fabrication & welding'] }];
  const r = checkChoice(JSON.stringify({ trades: [
    { code: 'joinery', quotes: [F(m04, 'capability_claim')], reason: 'r' },                       // M04: refused for its form
    { code: 'steel', quotes: [F('Expertise in Steel Fabrication', 'list_item')], reason: 'r' },   // a list item: kept
    { code: 'fire_fighting', quotes: [F(arabic, 'capability_claim')], reason: 'r' },              // Arabic capability claim: refused
    { code: 'doors', quotes: [F('Expertise in Steel Fabrication')].map((x) => ({ text: x.text })), reason: 'r' },   // no form given
  ] }), text, defs);
  assert(r.ok);
  assertEquals(r.trades.map((x) => x.code), ['steel']);
  const why = Object.fromEntries(r.rejected.map((x) => [x.code, x.why]));
  assert(/^the quote's form is not a services list, heading or title \(capability_claim\)/.test(why.joinery), why.joinery);
  assert(/^the quote's form is not .*capability_claim/.test(why.fire_fighting), why.fire_fighting);
  assert(/no form given/.test(why.doors), why.doors);
  assert(!/not in the document/.test(why.joinery));
});

// ── 12 Nov 2026: the reader sees the WHOLE catalogue (sales_engineer; ruling 1647, service profiling slice 0) ──────────────
// Measured on production that day: tradeDefs read taxonomy_trade_service in one unpaged select and PostgREST answered 1,000
// of 1,104 active rows, so 104 service keys (landscaping.maintenance, cleaning.ac_duct, joinery.wood_panelling ...) were never
// shown to the model and checkChoice refused them as "not a service of the trade". The stub caps every read at 1,000 rows as
// PostgREST does and honours .range(); the reader's key count must equal the active count.
import { tradeDefs } from './supplier_trade_choice.ts';
function cataloguedAdmin(nServices: number, cap = 1000) {
  const trades = Array.from({ length: 223 }, (_, i) => ({ code: `t${String(i).padStart(3, '0')}`, label: `Trade ${i}` }));
  const services = Array.from({ length: nServices }, (_, i) => ({
    trade_code: trades[i % trades.length].code, code: `s${String(i).padStart(4, '0')}`, label_en: `Service ${i}`,
    active: i % 50 !== 49, sort: i % 7,   // every 50th row inactive: the reader must skip it
  }));
  return {
    from: (table: string) => {
      let lo = 0, hi = Infinity; const eqs: [string, unknown][] = [];
      const b = {
        select: () => b, order: () => b,
        eq: (c: string, v: unknown) => { eqs.push([c, v]); return b; },
        range: (a: number, z: number) => { lo = a; hi = z; return b; },
        then: (ok: (r: unknown) => void) => {
          const src = (table === 'taxonomy_trade' ? trades : services) as Record<string, unknown>[];
          const kept = src.filter((r) => eqs.every(([c, v]) => !(c in r) || r[c] === v))
            .sort((x, y) => String(x.trade_code ?? x.code).localeCompare(String(y.trade_code ?? y.code)) || Number(x.sort ?? 0) - Number(y.sort ?? 0) || String(x.code).localeCompare(String(y.code)));
          ok({ data: kept.slice(lo, Math.min(hi + 1, lo + cap)), error: null });
        },
      };
      return b;
    },
    active: services.filter((s) => s.active).length,
  };
}
Deno.test("the reader's catalogue holds every active service past PostgREST's 1,000-row cap (1,104 on 12 Nov 2026)", async () => {
  const admin = cataloguedAdmin(1104);
  const defs = await tradeDefs(admin);
  assert(defs);
  const keys = defs.flatMap((d) => (d.serviceKeys ?? []).map((s) => s.key));
  assertEquals(keys.length, admin.active, 'every active service is a key the model may name');
  assertEquals(new Set(keys).size, keys.length, 'no key read twice across pages');
  assertEquals(defs.length, 223);
});
