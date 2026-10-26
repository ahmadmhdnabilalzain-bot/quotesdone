import { assertEquals } from 'jsr:@std/assert';
import { heldFromGate, modelHeld, HOLD_PROBE_MODEL } from './llm_hold.ts';

// The gate's own answers (public.fn_kernel_paid_provider_gate), verbatim in shape.
Deno.test('the founder hold on ANY route is the hold — the gate says so, not a row count', () => {
  assertEquals(heldFromGate({ allowed: false, rule: 'founder_hold', held: 1, routes: 8 }), true);
});

Deno.test('the no_paid_ai switch and an empty route table are the hold too', () => {
  assertEquals(heldFromGate({ allowed: false, rule: 'no_paid_ai_switch' }), true);
  assertEquals(heldFromGate({ allowed: false, rule: 'empty_route_state' }), true);
});

Deno.test('a refusal of the probe model itself is not the hold', () => {
  assertEquals(heldFromGate({ allowed: false, rule: 'route_not_registered' }), false);
  assertEquals(heldFromGate({ allowed: true, rule: 'registered_breaker_closed' }), false);
});

Deno.test('no answer is not a hold — the gateway decides', () => {
  assertEquals(heldFromGate(null), false);
  assertEquals(heldFromGate(undefined), false);
});

Deno.test('modelHeld asks the gate with the probe model, and a partial hold reads as held', async () => {
  const calls: unknown[] = [];
  const admin = { rpc: (fn: string, args: unknown) => { calls.push([fn, args]); return Promise.resolve({ data: { allowed: false, rule: 'founder_hold', held: 1, routes: 8 }, error: null }); } };
  assertEquals(await modelHeld(admin, 0), true);
  assertEquals(calls, [['fn_kernel_paid_provider_gate', { p_model: HOLD_PROBE_MODEL }]]);
});
