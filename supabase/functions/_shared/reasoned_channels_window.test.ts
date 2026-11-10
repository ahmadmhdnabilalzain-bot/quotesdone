// What the WhatsApp intent decision sees (reasoned_channels.intentWindow, 10 Nov 2026, ledger 1572): every turn the person
// wrote, and our replies from the last six turns. No network.
// Run: deno test --no-lock --node-modules-dir=none supabase/functions/_shared/reasoned_channels_window.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { intentWindow, RECENT_REPLIES, whatsappMeaning } from './reasoned_channels.ts';
import type { Turn } from './think.ts';

const conv: Turn[] = [{ role: 'customer', text: 'I need two quotes: aluminium windows and a glass partition.' }, { role: 'seat', text: 'Noted, both.' }];
for (let i = 0; i < 20; i++) conv.push({ role: i % 2 ? 'seat' : 'customer', text: 'turn ' + i });

Deno.test('the topic the customer set at the start is still in what the intent decision reads, twenty turns later', () => {
  const w = intentWindow(conv);
  assert(w.some((t) => t.text.startsWith('I need two quotes')), 'the opening request was cut');
  assertEquals(w.filter((t) => t.role === 'customer').length, conv.filter((t) => t.role === 'customer').length);
  assert(!w.some((t) => t.text === 'Noted, both.'), 'an old reply of ours rides too');
  assertEquals(w.slice(-RECENT_REPLIES), conv.slice(-RECENT_REPLIES));
  // order is kept
  assertEquals(w.map((t) => conv.indexOf(t)), [...w.map((t) => conv.indexOf(t))].sort((a, b) => a - b));
});

Deno.test('the WhatsApp reading is asked with that window, not the last six turns', async () => {
  // deno-lint-ignore no-explicit-any
  let asked: any = null;
  const deps = { gate: () => Promise.resolve(null), embed: () => Promise.resolve(null), rpc: () => Promise.resolve({ data: null, error: null }),
    // deno-lint-ignore no-explicit-any
    llm: (_p: string, _s: string, input: string) => { asked ??= JSON.parse(input); return Promise.resolve({ content: JSON.stringify({ answer: 'x', decision: { choice: 'none' }, confidence: 0.9, reasoning: [], cited: [] }), model: 'm' }); } } as any;
  await whatsappMeaning(deps, { message: 'what about the second one?', intents: [], trades: [], phone: '+971500000000', conversation: conv }).catch(() => null);
  // deno-lint-ignore no-explicit-any
  const sent = (asked?.context?.conversation ?? []) as any[];
  assert(sent.some((t) => String(t.text).startsWith('I need two quotes')), JSON.stringify(sent).slice(0, 300));
});
