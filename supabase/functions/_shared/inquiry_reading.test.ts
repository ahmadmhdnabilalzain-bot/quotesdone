// The portal's and WhatsApp's state reader (inquiry_reading.ts): its prompt, what of its answer is kept, the state patch,
// and the bounded call. No network: `ask` is a stub.
// Run: deno test --no-lock --node-modules-dir=none supabase/functions/_shared/inquiry_reading.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { gatewayAsk, parseReading, readInquiry, readingPatch, readingPrompt } from './inquiry_reading.ts';
import { problemsFor } from './solution_catalogue.ts';
import type { TaxTrade, TradeService } from './inquiry_trades.ts';

const TAX: TaxTrade[] = [
  { code: 'wallpaper', label: 'Wallpaper', group_code: 'construction_building' }, { code: 'joinery', label: 'Joinery', group_code: 'construction_building' },
  { code: 'staff_transport', label: 'Staff transport', group_code: 'transport_mobility' }, { code: 'corrugated_packaging', label: 'Corrugated', group_code: 'materials_packaging' },
];
const SVC: TradeService[] = [{ trade_code: 'staff_transport', code: 'bus_rental', label_en: 'Bus rental with driver' }];
const problems = problemsFor({ slug: 'wallpaper' });

Deno.test('the prompt carries the whole taxonomy by group, the option keys shown, the services, our last reply and their message', () => {
  const p = readingPrompt({ taxonomy: TAX, problems, services: SVC, lastSeat: 'For an MDF partition: PVC panels, a vinyl film wrap, or paint. Which suits you?', message: 'the film please, budget 3k', heldCodes: ['wallpaper'] });
  assert(p.sys.includes('Transport, vehicles, marine & aviation: staff_transport') && p.sys.includes('Materials, chemicals & packaging: corrugated_packaging'));
  assert(p.sys.includes('cover_existing_board/architectural_film: Architectural vinyl film wrap'));
  assert(p.sys.includes('staff_transport.bus_rental: Bus rental with driver') && p.sys.includes('held so far: wallpaper'));
  assert(p.input.includes('OUR LAST REPLY: For an MDF partition') && p.input.includes('CUSTOMER MESSAGE: the film please'));
  assert(/Never guess/.test(p.sys));
});

Deno.test('the answer: real codes, options and services kept; a guessed code or key dropped; the chosen option names its services', () => {
  const r = parseReading('```json\n' + JSON.stringify({ trade_codes: ['wallpaper', 'made_up'], problem: 'cover_existing_board',
    options_offered: ['cover_existing_board/pvc_wpc_panels', 'cover_existing_board/architectural_film', 'cover_existing_board/paint_or_laminate'],
    chosen_option: 'cover_existing_board/architectural_film', condition: { object: 'small MDF partition' }, budget: '3k', service_keys: ['wallpaper.nope'] }) + '\n```', { taxonomy: TAX, services: SVC })!;
  assertEquals(r.trade_codes, ['wallpaper']);
  assertEquals(r.service_keys, []);
  assertEquals(r.chosen_option?.option, 'architectural_film');
  const p = readingPatch(r);
  assertEquals(p.trade_codes, ['wallpaper']);
  assertEquals(p.specs?.service_keys, 'interior_fitout.decoration, wallpaper.supply_install');
  assertEquals(p.budget, '3k');
  assertEquals(p.options_offered?.length, 3);
});

Deno.test('a bus rental on WhatsApp: no catalogue option, the trade and its service still read', () => {
  const r = parseReading(JSON.stringify({ trade_codes: ['staff_transport'], service_keys: ['staff_transport.bus_rental'], condition: { use: '40 staff, Sharjah to JAFZA, twice a day' } }), { taxonomy: TAX, services: SVC })!;
  const p = readingPatch(r);
  assertEquals([p.trade_codes, p.specs?.service_keys, p.condition?.use], [['staff_transport'], 'staff_transport.bus_rental', '40 staff, Sharjah to JAFZA, twice a day']);
  assertEquals(parseReading('not json', { taxonomy: TAX }), null);
});

Deno.test('the call is bounded: no time, no taxonomy or no message asks nothing; a throw is null', async () => {
  let asked = 0;
  const ask = (_s: string, _i: string, ms: number) => { asked++; assert(ms > 0); return Promise.resolve('{"trade_codes":["joinery"]}'); };
  const i = { taxonomy: TAX, problems: [], lastSeat: '', message: 'wardrobes please' };
  assertEquals((await readInquiry(ask, i, Date.now() + 10_000))?.trade_codes, ['joinery']);
  assertEquals(await readInquiry(ask, i, Date.now() + 500), null);
  assertEquals(await readInquiry(ask, { ...i, taxonomy: [] }, Date.now() + 10_000), null);
  assertEquals(await readInquiry(ask, { ...i, message: ' ' }, Date.now() + 10_000), null);
  assertEquals(asked, 1);
  assertEquals(await readInquiry(() => Promise.reject(new Error('down')), i, Date.now() + 10_000), null);
});

Deno.test('the gateway ask posts json_extraction for the seat and returns the content; a failure is null', async () => {
  let body: Record<string, unknown> = {};
  const f = ((_u: string, init: RequestInit) => { body = JSON.parse(String(init.body)); return Promise.resolve(new Response(JSON.stringify({ content: '{}' }))); }) as unknown as typeof fetch;
  assertEquals(await gatewayAsk({ gateway: 'https://x.invalid', secret: 's', fn: 'sales_engineer', agent: 'sales_engineer' }, f)('SYS', 'IN', 3000), '{}');
  assertEquals([body.task_class, body.fn, body.sys, body.input], ['json_extraction', 'sales_engineer', 'SYS', 'IN']);
  const bad = (() => Promise.reject(new Error('net'))) as unknown as typeof fetch;
  assertEquals(await gatewayAsk({ gateway: 'x', secret: 's', fn: 'f', agent: 'a' }, bad)('a', 'b', 1000), null);
});
