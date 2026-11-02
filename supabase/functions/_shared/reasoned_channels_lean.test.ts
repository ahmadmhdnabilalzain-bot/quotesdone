// LEAN CLASSIFICATION (customer_support, 2 Nov 2026): the WhatsApp reading sends no company brief, decides the same option,
// and carries the recent turns. Known-bad control: with waLean.on = false the same call DOES send the brief.
// The real-model parity (old shape vs lean, same messages) is scripts/e2e/wa_exchange_real_driver.ts.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { ThinkDeps } from './think.ts';
import { waLean, whatsappReadings } from './reasoned_channels.ts';

const J = JSON.stringify;
const WA = { message: 'what about the second one?', intents: [{ intent_key: 'pricing', label: 'Fees and pricing' }], trades: [{ code: 'hvac', label: 'HVAC' }], phone: 'whatsapp:+971500000021', messageSid: 'SMZZDEMO1' };

async function run(lean: boolean) {
  waLean.on = lean;
  const stable: string[] = []; const inputs: string[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: false, rule: 'route_not_registered' } as never),
    llm: (_p, _s, input, o) => {
      stable.push(String(o?.sysStable ?? '')); inputs.push(input);
      return Promise.resolve({ content: J({ answer: 'x', decision: { choice: 'intent:pricing' }, needs_a_person: 'no_person', menu_meaning: 'other' }), model: 'mock' });
    },
    embed: () => Promise.resolve(null),
    rpc: () => Promise.resolve({ data: { cases: [] }, error: null }),
  };
  try {
    const r = await whatsappReadings(deps, { ...WA, menu: [{ id: 'a', title: 'A', description: 'a' }], conversation: [{ role: 'supplier', text: 'ZQ-EARLIER-TURN' }, { role: 'seat', text: 'ok' }] });
    return { choice: r.intent, stable, inputs };
  } finally { waLean.on = true; }
}

Deno.test('WhatsApp readings are lean: no settled facts in the deciding call, the same decision, the recent turns ride; the full shape sends the brief', async () => {
  const lean = await run(true); const full = await run(false);
  assertEquals(lean.choice, 'intent:pricing');
  assertEquals(lean.choice, full.choice, 'the decision does not change');
  assert(lean.stable.length > 0 && lean.stable.every((s) => s === ''), 'lean: no settled facts sent');
  assert(full.stable.some((s) => s.length > 1000), 'control: the full shape sends the brief');
  assert(lean.inputs.join('').includes('ZQ-EARLIER-TURN'), 'the recent turns reach the decision');
});
