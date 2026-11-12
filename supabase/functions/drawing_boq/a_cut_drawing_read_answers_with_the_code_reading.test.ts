// A CUT DRAWING READ ANSWERS WITH THE CODE READING (it_engineer, 12 Nov 2026; founder ledger 1642; final audit 2026-11-12
// section 3, E5 / customer_journey.md H4: "a one-sheet drawing took 67 s and came back with no quantities").
//
// Journey 2's villa HVAC sheet (fixtures/zz_demo_villa_hvac_sheet_m101.pdf, the audit's own ZZ DEMO file, run d9a04dbc). On
// 11 Nov 23:49 the drawing model call was cut at the gateway's 55 s wall (ai_cost_log 103045/103046), drawing_boq answered 200
// from its code reading, and the customer still got 0 lines. Why, established here: the code reading's summary is the
// customer's own note, "a G+1 private villa in Al Barsha South", and the identity gate held the whole take-off because the
// note shares words with the title strip's project name. The real handler is driven (twilio_free_harness: no network, no
// model); the gateway stub answers as it did that night (502, gateway_deadline).
//   1. the cut read answers with the code reading's lines, gated, and the customer's note is not carried as the summary;
//   2. the model waits what is left of ONE budget for the read (DRAWING_BUDGET_MS, inside customer_api's 140 s and the 150 s
//      edge wall), with no time left it is not asked, and every read records its outcome (boq.model_read).
// Run: deno test --no-lock --node-modules-dir=auto -A supabase/functions/drawing_boq/a_cut_drawing_read_answers_with_the_code_reading.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
const PDF = Deno.readFileSync(new URL('./fixtures/zz_demo_villa_hvac_sheet_m101.pdf', import.meta.url));
let b64 = ''; for (let i = 0; i < PDF.length; i += 0x8000) b64 += String.fromCharCode(...PDF.subarray(i, i + 0x8000));
b64 = btoa(b64);
// The harness's journey 2 opener, as the customer typed it (scripts: audit evidence_pack_audit.mjs journey 2).
const HINT = 'Hi, we are finishing a G+1 private villa in Al Barsha South, Dubai and need the air conditioning supplied and installed as per the attached HVAC drawing and BOQ: ducted split units concealed in the false ceiling, with ductwork, grilles, thermostats and exhaust fans, including testing and commissioning.';

const sentToGateway: Record<string, unknown>[] = [];
let onAuth: (() => void) | null = null;   // called when the handler checks its caller: after its clock started
const stub: Stub = {
  rpc: { fn_internal_auth: { ok: true, context: 'fn.customer_api', credential_id: 7, legacy: false } },
  handle: async (req, u) => {
    if (u.pathname.endsWith('/rpc/fn_internal_auth') && onAuth) onAuth();
    if (u.pathname === '/functions/v1/ai_gateway') {
      sentToGateway.push(await req.clone().json());
      return J({ ok: false, error: 'gateway_deadline', detail: 'no model answered within the 55000ms budget the caller waits for; last error: gateway_wall: aborted after 54726 ms' }, 502);
    }
    return undefined;
  },
};
const fn = await loadFunction('drawing_boq', () => import('./index.ts'));
const { DRAWING_BUDGET_MS, FALLBACK_RESERVE_MS, modelWaitMs } = await import('./index.ts');
const { ANALYZE_DRAWING_BUDGET_MS } = await import('../customer_api/actions/documents.ts');
let lastBoq: Record<string, unknown> | null = null;

Deno.test('the model is cut at its wall: the customer gets the code reading of the sheet, not 0 lines', async () => {
  sentToGateway.length = 0;
  const r = await invoke(fn, stub, { __secret: 'zz-cred-0123456789abcdef0123', hint: HINT, images: [{ b64: 'iVBORw0KGgo=', mime: 'image/png' }], original_b64: b64, mime: 'application/pdf' });
  assertEquals(r.status, 200, JSON.stringify(r.json).slice(0, 300));
  assertEquals(sentToGateway.length, 1, 'the model was asked once');
  const boq = r.json.boq as { boq?: unknown[]; summary?: string; author_model?: string; fallback_reason?: string } | null;
  assert(!r.json.identity_held, 'the whole reading was held: ' + JSON.stringify(r.json).slice(0, 300));
  assert(boq && Array.isArray(boq.boq) && boq.boq.length >= 1, 'no lines: ' + JSON.stringify(r.json).slice(0, 300));
  assertEquals([boq.author_model, boq.fallback_reason], ['deterministic', 'ai_gateway_refused']);
  lastBoq = boq as Record<string, unknown>;
  assert(!/private villa|Al Barsha/i.test(JSON.stringify(boq)), 'a term of the title strip went out on the take-off');
});

Deno.test('the read records its outcome: cut at the budget, so the paid journey can read it', () => {
  const boq = lastBoq!;
  assertEquals((boq.model_read as Record<string, unknown>).outcome, 'cut_at_budget');
  assertEquals((boq.model_read as Record<string, unknown>).budget_ms, DRAWING_BUDGET_MS);
});

Deno.test('the model waits what is left of ONE budget for the read, and the function answers inside the edge wall', () => {
  const declared = Number(sentToGateway[0]?.client_timeout_ms ?? 0);
  // ai_gateway/handle.ts: the wall is the declared wait less 3 s; with none declared it is 55 s, where high was cut 8 of 9
  // times on 11-12 Nov. Now: what is left of DRAWING_BUDGET_MS less the code reading's reserve.
  assert(declared - 3000 > 55_000, 'declared ' + declared);
  assert(declared <= DRAWING_BUDGET_MS - FALLBACK_RESERVE_MS, 'the model may run into the code reading\'s reserve: ' + declared);
  assertEquals(modelWaitMs(1_000, 3_000), DRAWING_BUDGET_MS - FALLBACK_RESERVE_MS - 2_000, 'time spent before the call comes off the wait');
  assert(DRAWING_BUDGET_MS + 5_000 <= ANALYZE_DRAWING_BUDGET_MS && ANALYZE_DRAWING_BUDGET_MS <= 150_000 - 10_000,
    'drawing_boq inside customer_api\'s budget, and that 10 s inside the edge wall');
  const portal = Number(Deno.readTextFileSync(new URL('../../../src/components/me/api.ts', import.meta.url)).match(/const DRAWING_READ_TIMEOUT_MS = (\d+)/)![1]);
  assert(portal > ANALYZE_DRAWING_BUDGET_MS, 'the portal must wait longer than the analysis budget, so it reads our answer');
});

Deno.test('with no time left the model is not asked and the code reading answers at once', async () => {
  sentToGateway.length = 0;
  const realNow = Date.now;
  // the read's clock has started when the handler checks its caller; from then on, the budget is spent
  onAuth = () => { Date.now = () => realNow() + DRAWING_BUDGET_MS; };
  try {
    const r = await invoke(fn, stub, { __secret: 'zz-cred-0123456789abcdef0123', hint: 'ZZ DEMO HVAC', images: [{ b64: 'iVBORw0KGgo=', mime: 'image/png' }], original_b64: b64, mime: 'application/pdf' });
    assertEquals(sentToGateway.length, 0, 'the model was asked with no time left');
    const boq = r.json.boq as Record<string, unknown>;
    assert(Array.isArray(boq.boq) && (boq.boq as unknown[]).length >= 1);
    assertEquals((boq.model_read as Record<string, unknown>).outcome, 'cut_at_budget');
  } finally { Date.now = realNow; onAuth = null; }
});
