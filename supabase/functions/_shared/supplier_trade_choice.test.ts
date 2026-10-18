// supplier_trade_choice — the model chooses a supplier's trades from our codes; code proves every one by its quote.
// Regression fixtures from the 29 real UAE profiles measured on 13 Oct 2026 (ACCURACY_real_profiles.md), names
// replaced by ZZ DEMO. deno test --no-lock --node-modules-dir=none supabase/functions/_shared/supplier_trade_choice.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { checkChoice, checkVerify, choiceRequest, choiceSystem, quoteContext, quoteKey, type TradeDef } from './supplier_trade_choice.ts';
import { readDocForTrades, type TradeResolveDeps } from './supplier_doc_trades.ts';

const DEFS: TradeDef[] = [
  { code: 'joinery', label: 'Joinery & carpentry', services: ['Kitchens', 'Wardrobes & closets'] },
  { code: 'fire_fighting', label: 'Fire fighting & life safety', services: ['Sprinkler systems', 'Fire alarm systems'] },
  { code: 'it_services', label: 'IT services', services: ['Network installation'] },
  { code: 'doors', label: 'Doors', services: ['Wooden doors'] },
];
const DOC = 'ZZ DEMO Joinery LLC\nScope of Work: Supply & Installation of Doors, Kitchen,\nWardrobes and Vanity Cabinets\nWe take up Service, Installation & Maintenance of:\nSprinkler Systems, Foam System';

Deno.test('every trade the model names is proven by a quote that is in the document; anything else is refused', () => {
  const r = checkChoice(JSON.stringify({ trades: [
    { code: 'fire_fighting', quote: 'Sprinkler Systems, Foam System', reason: 'it installs sprinklers' },
    { code: 'hvac', quote: 'Sprinkler Systems', reason: 'not one of our codes' },                    // not an active code
    { code: 'doors', quote: '', reason: 'no quote' },                                                    // no quote
    { code: 'it_services', quote: 'We install data networks', reason: 'made up' },                      // not in the text
  ] }), DOC, DEFS);
  assert(r.ok);
  assertEquals(r.trades.map((t) => t.code), ['fire_fighting']);
  assertEquals(r.rejected.map((x) => x.code), ['hvac', 'doors', 'it_services']);
});

Deno.test('a quote that runs across a PDF line break is still found, line by line (Royal Joinery, run 4)', () => {
  const r = checkChoice(JSON.stringify({ trades: [{ code: 'joinery', quote: 'Supply & Installation of Doors, Kitchen,\nWardrobes and Vanity Cabinets', reason: 'kitchens and wardrobes' }] }), DOC, DEFS);
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
  const deps: TradeResolveDeps = { normTrades: async () => ({}), services: [], embed: async () => null, budget: { left: 0 },
    chooseTrades: async () => ({ ok: false, error: 'model unavailable (502): breaker open' }) };
  const ev = await readDocForTrades({ path: 'p', name: 'p.txt', kind: 'profile', photo_text: 'We install sprinkler systems' }, deps);
  assertEquals([ev.status, ev.choice, ev.trades.length], ['read', 'unavailable', 0]);
  assert(/breaker open/.test(ev.reason || ''), ev.reason);
  const ok = await readDocForTrades({ path: 'p', name: 'p.txt', kind: 'profile', photo_text: 'We install sprinkler systems' },
    { ...deps, chooseTrades: async (t) => checkChoice(JSON.stringify({ trades: [{ code: 'fire_fighting', quote: 'install sprinkler systems', reason: 'r' }] }), t, DEFS) });
  assertEquals(ok.trades.map((t) => [t.code, t.via]), [['fire_fighting', 'model_choice']]);
});

Deno.test('the second look sees the quote with the lines around it (Al Nas Elevators, run 7: a quote cut short)', () => {
  const text = 'ABOUT US\nZZ DEMO Elevator company offers a comprehensive range of products and services including\nsupply and installation, modernization, maintenance of elevators and escalators etc.\nWe are an ISO certified company.';
  const c = quoteContext(text, 'supply and installation, modernization,');
  assert(c.includes('maintenance of elevators and escalators'), c);
  assertEquals(quoteContext(text, 'not in the text at all'), 'not in the text at all');
});

Deno.test('an answer in a code fence or after a sentence is still read; a failure says what came back (Summertown, run 9)', () => {
  const fenced = 'Here is the result:\n```json\n{"trades":[{"code":"joinery","quote":"Wardrobes and Vanity Cabinets","reason":"r"}]}\n```\nDone.';
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
Deno.test('an image-only profile proposes only what its printed lines quote; a summary phrase proposes nothing (H01)', async () => {
  const { modelReadText } = await import('./supplier_doc_trades.ts');
  const lines = ['ZZ DEMO Aluminium works, Glass works, UPVC windows & doors', 'Glass Partitions', 'Doors & windows'];
  const deps: TradeResolveDeps = { normTrades: async () => ({}), services: [], embed: async () => null, budget: { left: 0 },
    chooseTrades: async (t) => checkChoice(JSON.stringify({ trades: [
      { code: 'doors', quote: 'Doors & windows', reason: 'printed service' },
      { code: 'fire_fighting', quote: 'Plumbing and sanitary installation', reason: 'from the summary' },   // not a printed line
    ] }), t, DEFS) };
  const ev = await readDocForTrades({ path: 'p', name: 'p.pdf', kind: 'profile', photo_text: modelReadText('profile', lines) }, deps);
  assertEquals(ev.trades.map((t) => t.code), ['doors']);
});

Deno.test('the profile reading asks for printed lines verbatim, never from a certificate or letter', async () => {
  const LX = await import('./licence_extract.ts');
  assert(/copied EXACTLY as printed/.test(LX.SYS_PROFILE) && /never from a certificate, a letter of recommendation/.test(LX.SYS_PROFILE));
  assertEquals(LX.profileExtractRequest({ images: [] }, null).sys, LX.SYS_PROFILE);
});
