// The portal conversation's plan per trade (conversation_plan.ts). No network: the extraction call gets a fake fetch.
// Run: deno test --no-lock supabase/functions/sales_engineer/conversation_plan.test.ts
import { assert, assertEquals, assertThrows } from 'jsr:@std/assert';
import { KNOWLEDGE_TEXT } from '../_shared/company_brief.ts';   // every compiled block: the playbooks ride in the trade packs since 3 Nov 2026
import { S } from '../../../scripts/e2e/adaptive_conversation_bank.mjs';
import { extractSlots, fillsOf, jobStart, parseExtraction, PLANS, planState, plansFrom, stateBlock, stem, stems, SUMMARY_AFTER, targets,
  tradeOf, type Turn } from './conversation_plan.ts';

const u = (content: string): Turn => ({ role: 'user', content });
const a = (content: string): Turn => ({ role: 'assistant', content });

Deno.test('Arabic word forms share one stem: camera, room, apartment', () => {
  assertEquals(stem('كاميرا'), stem('كاميرات'));
  assert(stems('كم عدد الكاميرات؟').has(stem('كاميرا')));
  assertEquals(stem('غرفه'), stem('غرفتين'));
  assertEquals(stem('غرف'), stem('غرفه'));
  assertEquals(stem('شقتي'), stem('الشقه'));
  assertEquals(stem('cameras'), stem('camera'));
});

Deno.test('every playbook section names its must-haves, location and timing among them', () => {
  const cats = [...KNOWLEDGE_TEXT.matchAll(/\*\*Categories:\*\*\s*([^\n]+)/g)].flatMap((m) => m[1].split(',').map((c) => c.trim()));
  assert(cats.length >= 50, String(cats.length));
  for (const c of cats) {
    const p = PLANS.get(c);
    assert(p, `no plan for the category ${c}`);
    const ids = p!.slots.map((s) => s.id);
    assert(ids.includes('timing') && ids.includes('location'), `${c}: ${ids.join(',')}`);
    assert(ids.length <= 2 * SUMMARY_AFTER, c);
  }
  assertThrows(() => plansFrom('## X (x)\n- **Open:** a\n- **Must-haves (asked in this order):** colour; timing'), Error, 'unknown slot "colour"');
});

// The bank's 43 openings, each to the playbook a senior estimator would open (bank trade codes are not the
// playbook's: bathrooms is plumbing, paving landscaping, a roof pergola shade, a majlis upholstery).
const EXPECTED: Record<string, string> = {
  wardrobe_photo: 'carpentry-joinery', kitchen_villa_ar: 'kitchens', ac_replacement: 'hvac', roof_waterproofing_ar: 'waterproofing', cctv_shop: 'security',
  floor_tiles: 'tiling', painting_ar: 'painting', pool_build: 'swimming-pools', glass_partition_ar: 'glass', solar_villa: 'solar', bathroom_refit: 'plumbing',
  gypsum_ceiling_ar: 'gypsum', aluminium_windows: 'aluminium', villa_painting_ext_ar: 'painting', office_fitout: 'fitout', pest_control_ar: 'pest',
  electrical_ev: 'electrical', landscaping_ar: 'landscaping', carpet_office: 'carpets', water_tank_ar: 'plumbing', kitchen_cabinets_en: 'kitchens',
  interlock_paving: 'landscaping', smart_home_ar: 'smart-home', fence_gate: 'steel', deep_clean_ar: 'cleaning', mep_maintenance: 'mep', curtains_ar: 'blinds-curtains',
  roof_pergola: 'tents-and-shade-structures', gym_flooring: 'flooring', majlis_furniture_ar: 'upholstery', wardrobe_photo_ar: 'carpentry-joinery',
  kitchen_photo_en: 'kitchens', fire_alarm_office: 'safety', fire_alarm_warehouse_ar: 'safety', ac_undersized_en: 'hvac', ac_ducted_villa_ar: 'hvac',
  glass_partition_trap_en: 'glass', cctv_villa_ar: 'security', parquet_wet_area_trap_en: 'flooring', wardrobe_change_of_mind_en: 'carpentry-joinery',
  boundary_wall_paint_trap_ar: 'painting', shopfront_en: 'glass', villa_painting_int_en: 'painting',
};
type Scenario = { id: string; open: string; facts: [unknown, string, { must?: boolean }?][] };
Deno.test('every bank opening is read as its trade, and every must-have fact fills a slot of that plan', () => {
  for (const s of S as unknown as Scenario[]) {
    const p = tradeOf([s.open]);
    assertEquals(p?.key, EXPECTED[s.id], s.id);
    for (const [, say, o] of s.facts) {
      if (!o?.must) continue;
      const ids = fillsOf(say).map((x) => (x === 'count' ? 'size' : x));
      assert(ids.some((x) => p!.slots.some((y) => y.id === x)), `${s.id}: "${say}" fills ${ids.join(',') || 'nothing'}, none in ${p!.slots.map((y) => y.id).join(',')}`);
    }
  }
  // a wardrobe (خزانة) is never a water tank (خزان), and renovating (تجديد) is not "new" (جديد)
  assertEquals(tradeOf(['أبي خزانة ملابس للغرفة']), PLANS.get('carpentry-joinery'));
  assertEquals(planState([], 'أريد تجديد مطبخ الفيلا بالكامل.').filled.has('existing'), false);
  // 6 mm is the glass thickness, not the partition size
  assertEquals(planState([], 'Frameless glass partitions, 6 mm normal clear glass should be fine.').next, 'size');
});

Deno.test('the state: the single next must-have, then the summary, then New request', () => {
  let past: Turn[] = [];
  const go = (seat: string, msg: string) => { const st = planState(past, msg); past = [...past, u(msg), a(seat)]; return st; };
  const s1 = go('What are the wall width and ceiling height?', 'I need a built-in wardrobe for my bedroom.');
  assertEquals([s1.mode, s1.next, s1.also], ['ask', 'size', 'layout']);
  const s2 = go('Hanging, shelves or drawers inside?', 'About 2.4 m wide, 2.7 m ceiling.');
  assertEquals(s2.next, 'layout');
  const s3 = go('Sliding or hinged doors?', 'I am not sure, what do you recommend?');
  assert(s3.toConfirm.has('layout') && s3.unsure, 'unsure -> to confirm');
  assertEquals(s3.next, 'doors');
  const s4 = go('Which board and colour? And which emirate and area?', 'Hinged.');
  assertEquals(s4.next, 'finish');
  const s5 = go('When do you need it?', 'White gloss, a villa in Mirdif.');
  assertEquals([s5.next, s5.also], ['timing', null]);
  const s6 = go('Here is your request as I have it: a white gloss wardrobe, 2.4 m by 2.7 m, hinged doors, in Mirdif. Is this correct?', 'Within 5 weeks.');
  assertEquals(s6.mode, 'summary');
  const s7 = planState(past, 'Yes, that is correct.');
  assertEquals(s7.mode, 'confirmed');
  assert(/New request/.test(stateBlock(s7)) && /Ask nothing/.test(stateBlock(s7)));
  // a correction to the summary is summarised again, with the change
  const s8 = planState(past, 'Actually, change the doors to sliding.');
  assertEquals(s8.mode, 'summary');
  assert(s8.changed.has('doors') && /they changed this/.test(stateBlock(s8)), stateBlock(s8));
});

Deno.test(`after ${SUMMARY_AFTER} replies the next reply is the summary, the rest noted to confirm`, () => {
  const past: Turn[] = [u('I need CCTV for my shop.')];
  for (let i = 0; i < SUMMARY_AFTER; i++) past.push(a('Do you need a monitor in the shop?'), u('Maybe.'));
  past.pop();
  const st = planState(past, 'Maybe.');
  assertEquals(st.mode, 'summary');
  assert(st.toConfirm.has('timing') && st.toConfirm.has('location'), [...st.toConfirm].join(','));
  assert(/THIS REPLY IS THE SUMMARY/.test(stateBlock(st)));
});

Deno.test('one conversation per customer: a second job after a confirmed summary starts a fresh plan', () => {
  const t: Turn[] = [u('I need a wardrobe.'), a('Here is your request as I have it: a wardrobe. Is this correct?'), u('Yes, that is correct.'),
    a('Press New request to send it.'), u('Thanks. Also, I need my kitchen redone.')];
  assertEquals(jobStart(t), 4);
  const st = planState(t.slice(0, -1), t.at(-1)!.content);
  assertEquals([st.plan?.key, st.mode, st.seatTurns], ['kitchens', 'ask', 0]);
});

Deno.test('a reply answering the one slot asked fills it in their words; a question back leaves it open', () => {
  const st = planState([u('I bought an electric car and need a charger at home.'), a('How far is the parking from the main electrical board?')], 'Covered car porch, maybe 15 steps.');
  assert(st.filled.has('services'), [...st.filled.keys()].join(','));
  const back = planState([u('I need a charger at home.'), a('How far is the parking from the main electrical board?')], 'Why does that matter?');
  assertEquals(back.next, 'services');
});

Deno.test('targets: a question is placed by its slot in any wording; handles is not the door type', () => {
  const p = PLANS.get('carpentry-joinery')!;
  assertEquals(targets('Would you like handles or push-to-open?', p), ['handles']);
  assert(targets('Do you want sliding or hinged doors?', p).includes('doors'));
  assert(targets('كم كاميرا تحتاج؟', PLANS.get('security')!).includes('count'));
  assert(targets('متى تحتاج التركيب؟', p).includes('timing'));
});

Deno.test('the extraction decides only what code cannot: two slots asked, a statement no detector reads', () => {
  const asked2 = [u('I need a wardrobe for my bedroom.'), a('What size is the wall, and what goes inside?')];
  const st = planState(asked2, 'Roughly the full wall, mostly for long dresses.');
  assertEquals(st.undecided, ['size', 'layout']);
  assert(st.toConfirm.has('size') && st.toConfirm.has('layout'), 'left alone, both are to confirm');
  // one slot asked: its answer is that slot's, no call needed
  assertEquals(planState([u('I need a wardrobe for my bedroom.'), a('What goes inside it?')], 'Mostly for long dresses.').undecided, []);
  // a slot read by a detector: the rest were skipped, no call needed
  assertEquals(planState(asked2, 'About 2.4 m wide.').undecided, []);
  assertEquals(parseExtraction('{"layout":"mostly for long dresses","timing":"next week","finish":"oak veneer"}', st, 'Roughly the full wall, mostly for long dresses.'),
    { layout: 'mostly for long dresses' }, 'only undecided slots, only in their words');
  assertEquals(parseExtraction('not json', st, 'x'), {});
  assertEquals(parseExtraction('{"size":"unsure"}', st, 'no idea'), { size: 'unsure' });
  const after = planState(asked2, 'Roughly the full wall, mostly for long dresses.', { layout: 'mostly for long dresses' });
  assert(after.filled.has('layout') && !after.toConfirm.has('layout') && after.toConfirm.has('size'));
});

Deno.test('the extraction call: bounded, json_extraction, never throws, never made when code can decide', async () => {
  const msg = 'Roughly the full wall, mostly for long dresses.';
  const st = planState([u('I need a wardrobe for my bedroom.'), a('What size is the wall, and what goes inside?')], msg);
  const bodies: Record<string, unknown>[] = [];
  const ok = ((_u: string, i: RequestInit) => { bodies.push(JSON.parse(String(i.body))); return Promise.resolve(new Response(JSON.stringify({ content: '{"layout":"long dresses"}' }))); }) as typeof fetch;
  const r = await extractSlots({ gateway: 'https://gw', secret: 's', st, lastSeat: '', message: msg, deadline: Date.now() + 5000 }, ok);
  assertEquals(r?.slots, { layout: 'long dresses' });
  assertEquals(bodies[0].task_class, 'json_extraction');
  assert(Number(bodies[0].client_timeout_ms) <= 5000);
  const boom = (() => Promise.reject(new Error('down'))) as typeof fetch;
  assertEquals(await extractSlots({ gateway: 'https://gw', secret: 's', st, lastSeat: '', message: msg, deadline: Date.now() + 5000 }, boom), null);
  assertEquals(await extractSlots({ gateway: 'https://gw', secret: 's', st, lastSeat: '', message: msg, deadline: Date.now() + 500 }, ok), null, 'no time left');
  const decided = planState([u('I need a wardrobe for my bedroom.'), a('What goes inside it?')], 'Mostly for long dresses, please.');
  assertEquals(await extractSlots({ gateway: 'https://gw', secret: 's', st: decided, lastSeat: '', message: 'Mostly for long dresses, please.', deadline: Date.now() + 5000 }, ok), null, 'code decided');
  assertEquals(await extractSlots({ gateway: 'https://gw', secret: 's', st: planState([], 'How do quotes work?'), lastSeat: '', message: 'How do quotes work here?', deadline: Date.now() + 5000 }, ok), null, 'not a job');
  assertEquals(bodies.length, 1);
});

// smoke run 8962e747 (fire_alarm_office): "What does the office do day to day" was not placed, and the use was asked again
Deno.test('targets: what the place is used for, and "system" only when the question is about the system', () => {
  assert(targets('What does the office do day to day, and what equipment is kept in the server room?', PLANS.get('safety')!).includes('usage'));
  assert(!targets('When do you need the system completed?', PLANS.get('safety')!).includes('system'));
  assert(targets('When do you need the system completed?', PLANS.get('safety')!).includes('timing'));
});

// The 22-scenario run of 9b2f83013, ac_ducted_villa_ar: the drawings and load calculation, a must-have for a ducted
// villa, were not in the HVAC plan, so the plan never asked them. A conditional must-have joins only when the customer
// names a ducted or whole-home system: a bedroom split replacement is never asked for drawings.
Deno.test('a conditional must-have: drawings for a ducted villa, never for a bedroom split', () => {
  const ducted = planState([], 'أبغى أركب تكييف مخفي (دكت) لفيلا جديدة.');
  assert(ducted.plan!.slots.some((x) => x.id === 'design'), ducted.plan!.slots.map((x) => x.id).join(','));
  const split = planState([], 'My AC in the bedroom stopped cooling, I think I need to replace it.');
  assert(!split.plan!.slots.some((x) => x.id === 'design'), split.plan!.slots.map((x) => x.id).join(','));
  assert(PLANS.get('hvac')!.slots.find((x) => x.id === 'design')?.when, 'the playbook marks it conditional');
});

// The 21-scenario run on 6cf746dea: water_tank_ar was asked "the fixtures and where they go" twice (the plumbing plan's
// bathroom slot) and stalled; smart_home_ar's "new build or finished home?" was read only as the finish and deadlocked.
Deno.test('a tank is never asked about fixtures; "new build or finished home" is the existing condition', () => {
  const tank = planState([], 'خزان الماء عندي يسرب وأبي أغيره.');
  assert(!tank.plan!.slots.some((x) => x.id === 'layout'), tank.plan!.slots.map((x) => x.id).join(','));
  const bath = planState([], 'I want to redo my bathroom completely.');
  assert(bath.plan!.slots.some((x) => x.id === 'layout'));
  assert(targets('هل البيت جديد تحت التشطيب، أم جاهز ومسكون؟', PLANS.get('smart-home')!).includes('existing'));
});

// BROWSER PROOF, 2 Nov 2026 (ledger 1464): "Can I post a job worth AED 300?" is a question about the platform, and the read-back
// then said "Budget: AED 300" and answered the next question with the job summary. A figure in a question is not the budget.
Deno.test('a figure inside a question about the platform is not the budget; a statement of it, or a question that says budget, is', () => {
  const job = 'I need aluminium windows for my villa in Al Barsha, the main door must be 2.4 m wide.';
  // known-bad control: the detector alone DOES read the figure as a budget, so it is the guard in planState that stops it
  assert(fillsOf('Can I post a job worth AED 300?').includes('budget'));
  assertEquals(planState([u(job)], 'Can I post a job worth AED 300?').filled.has('budget'), false);
  assertEquals(planState([u(job)], 'Is AED 5,000 enough for the windows?').filled.has('budget'), false);
  // known-good controls: the same figures stated, or asked about as a budget, still fill it
  assertEquals(planState([u(job)], 'My budget is AED 40,000.').filled.has('budget'), true);
  assertEquals(planState([u(job)], 'Is a budget of AED 5,000 realistic?').filled.has('budget'), true);
  assertEquals(planState([u(job)], 'Around AED 40,000 in total.').filled.has('budget'), true);
});

// BROWSER PROOF, 2 Nov 2026 (ledger 1464): with the summary due, "what is the fee again?" was answered without the figure and
// "is it still free?" with the read-back first. A reply due as the summary answers a direct question first.
Deno.test('a summary-due reply is told to answer a direct question first; a statement or a confirmation is not a question', () => {
  let past: Turn[] = [];
  const seat = 'Which board and colour?';
  for (const m of ['I need aluminium windows for my villa in Al Barsha.', 'About 2.4 m wide, 2.7 m high.', 'Sliding.', 'Grey frames.', 'Within 5 weeks.', 'Dubai, Al Barsha.']) past = [...past, u(m), a(seat)];
  const q = planState(past, 'What is the fee again?');
  assertEquals(q.mode, 'summary');
  assert(q.direct, 'a question that states no must-have');
  assert(stateBlock(q).includes('THEY ASKED A QUESTION: answer it first'));
  // known-bad controls: a statement, and a confirmation, are not questions to answer first
  assert(!planState(past, 'Four sliding windows please.').direct);
  assert(!stateBlock(planState(past, 'Four sliding windows please.')).includes('THEY ASKED A QUESTION'));
  const withSummary = [...past, u('Within 5 weeks.'), a('Here is your request as I have it: x. Is this correct?')];
  assert(!planState(withSummary, 'Yes, that is correct.').direct);
});
