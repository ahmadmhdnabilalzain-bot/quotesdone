// supplier_profile_reading — the profile is read first and mapped second; code checks the claims and decides what is listed and what
// is asked (sales_engineer, 12 Nov 2026; ruling 1647; docs/reports/2026-11-12-supplier-service-profiling.md 3.1-3.3, 3.10).
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/supplier_profile_reading.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { aboutHash, applyMapping, checkReading, LIMITS, phrasesOf, proposalOf, readInTwoSteps, sliceTrades, type ProfileReading, type Taxonomy } from './supplier_profile_reading.ts';

const svc = (t: string, ...c: string[]) => c.map((x) => ({ key: `${t}.${x}`, label: x.replace(/_/g, ' ') }));
const TAX: Taxonomy = { trades: [
  { code: 'landscaping', label: 'Landscaping', services: svc('landscaping', 'softscape', 'hardscape', 'irrigation', 'maintenance', 'pools', 'artificial_grass', 'plant_rental', 'artificial_greenery') },
  { code: 'swimming_pools', label: 'Swimming pools', umbrella_code: 'landscaping', services: svc('swimming_pools', 'pool_construction', 'pool_maintenance', 'water_features') },
  { code: 'interior_fitout', label: 'Interior fit-out', services: svc('interior_fitout', 'decoration', 'office', 'turnkey') },
  { code: 'labour_supply', label: 'Labour supply', services: svc('labour_supply', 'general', 'skilled', 'hourly') },
  { code: 'event_management', label: 'Event management', services: svc('event_management', 'corporate', 'weddings') },
  { code: 'textiles', label: 'Textiles & garments', services: svc('textiles', 'garments') },
], adjacent: [['interior_fitout', 'landscaping']] };
const DOCS = [
  { path: 'p.pdf', name: 'profile.pdf', kind: 'profile' as const, text: 'ZZ DEMO Rimal Decoration\nGarden design and landscaping: planting, lawns and palm trees\nMonthly garden maintenance contracts\nSwimming pools are built through our specialist partner, ZZ DEMO Blue Lagoon Pools.\nWe supply staff and similar services.\nBoutique office interior, Business Bay (2024)' },
  { path: 'l.pdf', name: 'licence.pdf', kind: 'licence' as const, text: 'Activities: Readymade Garments Trading' },
];
const CODES = new Set(TAX.trades.map((t) => t.code));
const answer = (o: Record<string, unknown>) => JSON.stringify({ summary: 'A decoration company.', vague: [], also_ask: [], licence: { covers_profile: 'partly', note: '' }, ...o });

Deno.test('checkReading: a quote from the licence alone, or from nowhere, is refused; a basis that is not one of the four is asked, never listed', () => {
  const r = checkReading(answer({ evidence: [
    { words: 'Garden planting', quote: 'Garden design and landscaping: planting, lawns and palm trees', basis: 'stated', trade: 'landscaping' },
    { words: 'Garments', quote: 'Readymade Garments Trading', basis: 'stated', trade: 'textiles' },            // licence only
    { words: 'Roofing', quote: 'We build roofs', basis: 'stated', trade: 'landscaping' },                         // not in any document
    { words: 'Office interiors', quote: 'Boutique office interior, Business Bay (2024)', basis: 'portfolio', trade: 'interior_fitout' },
    { words: 'Garden maintenance', quote: 'Monthly garden maintenance contracts', basis: 'stated', trade: 'not_a_trade' },
  ] }), DOCS, CODES);
  assert(r.ok);
  assertEquals(r.reading.evidence.map((e) => e.words), ['Garden planting', 'Office interiors', 'Garden maintenance']);
  assertEquals(r.reading.evidence[1].basis, 'shown');
  assertEquals(r.reading.evidence[2].trade, null, 'a trade that is not ours is none, never the nearest');
  assertEquals(r.reading.evidence[0].doc, 'p.pdf');
  assert(r.reading.rejected.some((x) => x.what === 'Garments' && /not the trade licence/.test(x.why)));
  assert(r.reading.rejected.some((x) => x.what === 'Roofing'));
  assertEquals(checkReading('I could not read it', DOCS, CODES).ok, false);
});

Deno.test('applyMapping: a key must be in the catalogue and of a trade the call was shown; at most two keys a phrase', () => {
  const r = checkReading(answer({ evidence: [{ words: 'Garden maintenance', quote: 'Monthly garden maintenance contracts', basis: 'stated', trade: 'landscaping' }] }), DOCS, CODES);
  assert(r.ok);
  const ph = phrasesOf(r.reading), rejected: { what: string; why: string }[] = [];
  const shown = new Set(sliceTrades(['landscaping'], TAX));
  assertEquals([...shown].sort(), ['interior_fitout', 'landscaping', 'swimming_pools'], 'adjacent and umbrella children are shown');
  assert(applyMapping(JSON.stringify({ map: [{ i: 1, keys: ['landscaping.maintenance', 'labour_supply.general', 'landscaping.irrigation'] }, { i: 1, keys: ['landscaping.nonsense'] }] }), ph, shown, TAX, rejected));
  assertEquals(r.reading.evidence[0].keys, ['landscaping.maintenance']);
  assertEquals(rejected.map((x) => x.why).sort(), ['not a catalogue service key', 'not a service of a trade the mapping was shown']);
  assertEquals(applyMapping('no json here', ph, shown, TAX, rejected), false);
});

const reading = (over: Partial<ProfileReading> = {}): ProfileReading => ({ summary: '', evidence: [], vague: [], also_ask: [], licence: { covers_profile: 'partly', note: '' }, brands: [], areas: [], roles: [], rejected: [], ...over });
const claim = (words: string, basis: 'stated' | 'shown' | 'partner' | 'brand', keys: string[], trade: string | null = keys[0]?.split('.')[0] ?? null, partner_name: string | null = null) =>
  ({ words, quote: words + ' line', basis, partner_name, trade, doc: 'p.pdf', keys });

Deno.test('proposalOf: stated and mapped is listed (never ticked: there is no tick field); partner is listed apart; no key is his own words', () => {
  const p = proposalOf(reading({ evidence: [
    claim('Garden planting', 'stated', ['landscaping.softscape']), claim('Garden maintenance', 'stated', ['landscaping.maintenance']),
    claim('Pool building', 'partner', ['swimming_pools.pool_construction', 'landscaping.pools'], 'swimming_pools', 'ZZ DEMO Blue Lagoon Pools'),
    claim('Garden maintenance by partner', 'partner', ['landscaping.maintenance']),     // he also states it himself: his own
    claim('Garden lighting', 'stated', [], 'landscaping'), claim('Jacuzzi', 'partner', [], 'swimming_pools'),
  ] }), TAX, []);
  assertEquals(p.tick.map((x) => x.key), ['landscaping.softscape', 'landscaping.maintenance']);
  assertEquals(p.partner.map((x) => x.key), ['swimming_pools.pool_construction', 'landscaping.pools']);
  assertEquals(p.partner[0].partner_name, 'ZZ DEMO Blue Lagoon Pools');
  assertEquals(p.own_words.map((x) => x.words), ['Garden lighting', 'Jacuzzi']);
  assertEquals(p.trades.map((t) => t.code), ['landscaping'], 'a partner trade is not put on his list');
  assert(!JSON.stringify(p.tick).includes('"ticked"') && !('services' in p), 'nothing here writes services');
  // one card per partner named (else per trade); a partner line whose keys he states himself asks nothing
  const partner = p.questions.filter((q) => q.kind === 'partner');
  assertEquals(partner.map((q) => q.options.map((o) => o.key ?? o.label_en)), [['swimming_pools.pool_construction', 'landscaping.pools'], ['Jacuzzi']]);
  assertEquals(partner[0].about.partner_name, 'ZZ DEMO Blue Lagoon Pools');
  assertEquals(partner[1].options[0].own_words, true);
});

Deno.test('proposalOf: a reading that names nothing is the question "what does your company do", never held', () => {
  const p = proposalOf(reading({ vague: [{ quote: '', doc: null, why: 'nothing said', ask: 'What does the company do?', options: [] }] }), TAX, []);
  assertEquals(p.questions.map((q) => [q.kind, q.status, q.prompt_en, q.options.length]), [['nothing', 'open', 'Your profile does not say what your company does. Tell us in a line or two.', 0]]);
  assertEquals([p.tick.length, p.trades.length], [0, 0]);
});

Deno.test('proposalOf: a vague statement is asked with his sentence and its options (a key wherever one exists, else his words)', () => {
  const p = proposalOf(reading({ evidence: [claim('Recruitment', 'stated', [], 'interior_fitout')], vague: [{ quote: 'We supply staff and similar services.', doc: 'p.pdf', why: 'which staff', ask: 'What sort of staff do you supply?',
    options: [{ label: 'General labourers', trade: 'labour_supply', keys: ['labour_supply.general'] }, { label: 'Skilled tradesmen', trade: 'labour_supply', keys: ['labour_supply.skilled'] }, { label: 'Freelancers', trade: null, keys: [] }] }] }), TAX, []);
  const v = p.questions.find((q) => q.kind === 'vague')!;
  assertEquals(v.prompt_en, 'Your profile says: "We supply staff and similar services." What sort of staff do you supply?');
  assertEquals(v.options, [{ key: 'labour_supply.general', label_en: 'general', own_words: false }, { key: 'labour_supply.skilled', label_en: 'skilled', own_words: false }, { key: null, label_en: 'Freelancers', own_words: true }]);
  assert(p.trades.some((t) => t.code === 'labour_supply' && /similar services/.test(t.quote)), 'the vague statement names its trade (H02)');
  assert(!p.questions.some((q) => q.kind === 'trade_services' && q.about.trade === 'labour_supply'), 'the trade the vague question asks about is not asked twice');
});

Deno.test('proposalOf: a trade with no service is asked (code, no judgement); shown work is asked "as jobs on their own"; the licence mismatch is asked', () => {
  const p = proposalOf(reading({ evidence: [claim('Events', 'stated', [], 'event_management'), claim('Office fit-out', 'shown', ['interior_fitout.office'])],
    licence: { covers_profile: 'no', note: 'The licence is garments trading; the profile is events.' } }), TAX, [], { licenceActivities: ['Readymade Garments Trading'] });
  assertEquals(p.questions.map((q) => q.kind), ['trade_services', 'shown', 'licence']);
  assertEquals(p.questions[0].prompt_en, 'You work in Event management. Which of these do you do or supply?');
  assertEquals(p.questions[1].prompt_en, 'Your projects show office. Do you take these as jobs on their own?');
  assertEquals(p.questions[2].prompt_en, 'Your trade licence lists Readymade Garments Trading. Your profile is about event management and interior fit-out. Which is your business today?');
  assertEquals(p.tick.length, 0, 'shown work is never listed');
});

Deno.test('proposalOf limits: at most 5 open cards, 8 options a card, 12 umbrella chips on 2 open cards; the rest are later, never dropped', () => {
  const vague = Array.from({ length: 3 }, (_, i) => ({ quote: `vague ${i}`, doc: 'p.pdf', why: '', ask: `Q${i}?`, options: Array.from({ length: 12 }, (_, j) => ({ label: `opt ${i}.${j}`, trade: null, keys: [] })) }));
  const p = proposalOf(reading({ evidence: [claim('Planting', 'stated', ['landscaping.softscape']), claim('Irrigation', 'stated', ['landscaping.irrigation']), claim('Office', 'shown', ['interior_fitout.office']), claim('Pools', 'partner', ['swimming_pools.pool_construction'])], vague,
    also_ask: [{ because: 'decorators', options: [{ label: 'Weddings', trade: 'event_management', keys: ['event_management.weddings'] }] }] }), TAX,
    [{ from: 'landscaping.softscape', to: 'labour_supply.general' }]);
  assert(p.questions.every((q) => q.options.length <= LIMITS.options));
  assertEquals(p.questions.filter((q) => q.status === 'open').length, LIMITS.openCards);
  assertEquals(p.questions.slice(0, 5).map((q) => q.kind), ['vague', 'vague', 'vague', 'partner', 'shown'], 'most blocking first');
  const umb = p.questions.filter((q) => q.kind === 'umbrella');
  assert(umb.length >= 1 && umb.every((q) => q.status === 'later'), 'beyond 5 cards an umbrella waits as later');
  // the design's order of candidates: the reading's also-ask, the curated implications, then the trade's own other services
  assertEquals(umb[0].options.slice(0, 3).map((o) => o.key), ['event_management.weddings', 'labour_supply.general', 'landscaping.hardscape']);
  const keys = umb.flatMap((q) => q.options.map((o) => o.key));
  assert(!keys.includes('landscaping.softscape') && !keys.includes('swimming_pools.pool_construction'), 'nothing evidenced or asked elsewhere is offered again');
  // a main trade holds at least two of his listed services; its other services are the umbrella candidates
  const few = proposalOf(reading({ evidence: [claim('Planting', 'stated', ['landscaping.softscape']), claim('Irrigation', 'stated', ['landscaping.irrigation'])] }), TAX, []);
  assertEquals(few.questions.map((q) => [q.kind, q.status, q.options.length]), [['umbrella', 'open', 6]]);
  const one = proposalOf(reading({ evidence: [claim('Planting', 'stated', ['landscaping.softscape'])] }), TAX, []);
  assertEquals(one.questions.length, 0, 'one service in a trade is not a main trade: its catalogue is not offered as candidates');
});

Deno.test('every question row has the table shape of report 3.10, and the same question hashes the same', () => {
  const p = proposalOf(reading({ evidence: [claim('Events', 'stated', [], 'event_management')] }), TAX, []);
  for (const q of p.questions) {
    assertEquals(Object.keys(q).sort(), ['about', 'about_hash', 'kind', 'multi', 'options', 'prompt_en', 'source', 'status']);
    assertEquals(q.source, 'supplier_doc_trades@5');
    assert(/^[0-9a-f]{8}$/.test(q.about_hash));
    for (const o of q.options) assertEquals(Object.keys(o).sort(), ['key', 'label_en', 'own_words']);
  }
  assertEquals(aboutHash('vague', { quote: 'x' }), aboutHash('vague', { quote: 'x' }));
  assert(aboutHash('vague', { quote: 'x' }) !== aboutHash('shown', { quote: 'x' }));
});

Deno.test('readInTwoSteps: one reading (no vote, no held), every phrase with a trade mapped, a failed mapping call keeps its phrases as his words', async () => {
  const calls: string[] = [];
  const r = await readInTwoSteps(DOCS, 'ZZ DEMO Rimal', TAX, async (step, _sys, text) => {
    calls.push(step);
    if (step === 'read') return { ok: true, content: answer({ evidence: [{ words: 'Garden maintenance', quote: 'Monthly garden maintenance contracts', basis: 'stated', trade: 'landscaping' }, { words: 'Garden lighting', quote: 'ZZ DEMO Rimal Decoration', basis: 'stated', trade: 'landscaping' }] }) };
    assert(text.includes('1. Garden maintenance'));
    return { ok: false, error: 'model unavailable (502)' };
  });
  assert(r.ok);
  assertEquals(calls, ['read', 'map']);
  assertEquals(r.reading.evidence.map((e) => e.keys.length), [0, 0]);
  assert(r.reading.rejected.some((x) => /mapping of phrases 1-2/.test(x.what)));
  const p = proposalOf(r.reading, TAX, []);
  assertEquals([p.tick.length, p.own_words.length], [0, 2]);
  const no = await readInTwoSteps(DOCS, null, TAX, async () => ({ ok: false, error: 'model unavailable (503)' }));
  assertEquals(no.ok, false, 'no model: nothing is proposed (the sweep reads again), never a guess');
});

// ── 12 Nov 2026: the reader sees the WHOLE catalogue (slice 0, moved here with the deleted chooser's tradeDefs) ───────────────────
// Measured on production that day: an unpaged select of taxonomy_trade_service answered 1,000 of 1,104 active rows, so 104 keys
// (landscaping.maintenance, cleaning.ac_duct ...) could never be proposed. The stub caps every read at 1,000 rows as PostgREST does.
import { readTaxonomy } from './supplier_profile_reading.ts';
function cataloguedAdmin(nServices: number, cap = 1000) {
  const trades = Array.from({ length: 223 }, (_, i) => ({ code: `t${String(i).padStart(3, '0')}`, label: `Trade ${i}`, umbrella_code: null, active: true }));
  const services = Array.from({ length: nServices }, (_, i) => ({
    trade_code: trades[i % trades.length].code, code: `s${String(i).padStart(4, '0')}`, label_en: `Service ${i}`, active: i % 50 !== 49, sort: i % 7 }));
  const rows: Record<string, Record<string, unknown>[]> = { taxonomy_trade: trades, taxonomy_trade_service: services,
    taxonomy_trade_adjacent: [{ a_code: 't000', b_code: 't001', active: true }], service_implication: [{ from_code: 't000.s0000', implies_trade: 't001', implies_code: 's0001', active: true }] };
  return { from: (table: string) => {
    let lo = 0, hi = Infinity; const eqs: [string, unknown][] = [];
    const b = { select: () => b, order: () => b, eq: (c: string, v: unknown) => { eqs.push([c, v]); return b; }, range: (a: number, z: number) => { lo = a; hi = z; return b; },
      then: (ok: (r: unknown) => void) => {
        const kept = (rows[table] ?? []).filter((r) => eqs.every(([c, v]) => !(c in r) || r[c] === v))
          .sort((x, y) => String(x.trade_code ?? x.code).localeCompare(String(y.trade_code ?? y.code)) || Number(x.sort ?? 0) - Number(y.sort ?? 0) || String(x.code).localeCompare(String(y.code)));
        ok({ data: kept.slice(lo, Math.min(hi + 1, lo + cap)), error: null });
      } };
    return b;
  }, active: services.filter((s) => s.active).length };
}
Deno.test("the reader's catalogue holds every active service past PostgREST's 1,000-row cap (1,104 on 12 Nov 2026)", async () => {
  const admin = cataloguedAdmin(1104);
  const t = await readTaxonomy(admin);
  assert(t);
  const keys = t.taxonomy.trades.flatMap((d) => d.services.map((s) => s.key));
  assertEquals(keys.length, admin.active, 'every active service is a key the mapping may name');
  assertEquals(new Set(keys).size, keys.length, 'no key read twice across pages');
  assertEquals(t.taxonomy.trades.length, 223);
  assertEquals([t.taxonomy.adjacent, t.implications], [[['t000', 't001']], [{ from: 't000.s0000', to: 't001.s0001' }]]);
});

Deno.test('a profile whose work is only in project captions is asked by trade, the main trade first; a caption-only trade asks its services (H09)', () => {
  const p = proposalOf(reading({ evidence: [claim('Office fit-out', 'shown', ['interior_fitout.office']), claim('Turnkey', 'shown', ['interior_fitout.turnkey']),
    claim('Decoration', 'shown', ['interior_fitout.decoration']), claim('Kiosks', 'shown', [], 'labour_supply')] }), TAX, []);
  assertEquals(p.tick, []);
  assertEquals(p.questions.map((q) => [q.kind, q.about.trade, q.status]), [['shown', 'interior_fitout', 'open'], ['shown', 'labour_supply', 'open']]);
  assertEquals(p.questions[0].prompt_en, 'Your projects show office, turnkey and decoration. Do you take these as jobs on their own?');
  assertEquals(p.questions[1].prompt_en, 'Your projects show labour supply work. Do you take these as jobs on their own?');
  assertEquals(p.questions[1].options.map((o) => o.key), ['labour_supply.general', 'labour_supply.skilled', 'labour_supply.hourly']);
});

Deno.test('a trade is covered by a vague question only through an option that is a key of it; a label alone still drafts its card (H05)', () => {
  const p = proposalOf(reading({ evidence: [claim('Tiling maintenance', 'stated', [], 'interior_fitout')],
    vague: [{ quote: 'all kinds of maintenance works', doc: 'p.pdf', why: '', ask: 'Which other works?', options: [{ label: 'Floor repairs', trade: 'interior_fitout', keys: [] }, { label: 'Glass repairs', trade: null, keys: [] }, { label: 'Masonry', trade: null, keys: [] }] }] }), TAX, []);
  assertEquals(p.questions.map((q) => [q.kind, q.about.trade]), [['vague', 'interior_fitout'], ['trade_services', 'interior_fitout']]);
});
