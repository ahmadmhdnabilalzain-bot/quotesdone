// The widget's stream contract (stream_reply.ts). Run: deno test supabase/functions/_shared/stream_reply.test.ts
import { assert, assertEquals } from 'jsr:@std/assert';
import { pieces, STATUS, streamReply } from './stream_reply.ts';

async function lines(s: ReadableStream<Uint8Array>) {
  const text = await new Response(s).text();
  return text.split('\n').filter(Boolean).map((l) => JSON.parse(l));
}

Deno.test('the status line leaves before the reply exists, and no reply text rides on it', async () => {
  let release!: (v: Record<string, unknown>) => void;
  const payload = new Promise<Record<string, unknown>>((r) => { release = r; });
  const reader = streamReply(STATUS.en, () => payload).getReader();
  const first = JSON.parse(new TextDecoder().decode((await reader.read()).value!));
  assertEquals(first, { t: 'status', text: STATUS.en });   // nothing from a draft: the payload has not resolved
  release({ reply: 'Approved answer.', routed: 'reasoned' });
  let rest = '';
  for (;;) { const { done, value } = await reader.read(); if (done) break; rest += new TextDecoder().decode(value); }
  assert(rest.includes('Approved answer.'));
});

Deno.test('the deltas join back to exactly the final reply, and done carries the same payload as the JSON path', async () => {
  const reply = 'The reveal fee is 3% of the quote.\nNo card fee is added, and no VAT.  كل شيء واضح';
  const out = await lines(streamReply(STATUS.ar, () => Promise.resolve({ reply, scope: 'public', routed: 'reasoned' })));
  assertEquals(out[0].t, 'status');
  assertEquals(out.filter((e) => e.t === 'delta').map((e) => e.text).join(''), reply);
  assertEquals(out.at(-1), { t: 'done', reply, scope: 'public', routed: 'reasoned' });
  assertEquals(out.filter((e) => e.t === 'done').length, 1);
});

Deno.test('a failed payload still ends the stream with done and no delta', async () => {
  const out = await lines(streamReply(STATUS.en, () => Promise.reject(new Error('boom'))));
  assertEquals(out.map((e) => e.t), ['status', 'done']);
  assertEquals(out[1].error, 'boom');
});

// founder_instruction 1339: the portal tells "OpenRouter was down" from "the model was up" by done.outage alone.
Deno.test('a reply-less turn ends on done carrying outage, so the portal can tell an outage from a refused draft', async () => {
  const out = await lines(streamReply(STATUS.en, (emit) => { emit('Refused words. '); return Promise.resolve({ ok: false, error: 'no_answer', outage: false }); }));
  assertEquals(out.at(-1), { t: 'done', ok: false, error: 'no_answer', outage: false });
  const down = await lines(streamReply(STATUS.en, () => Promise.resolve({ ok: false, error: 'no_answer', outage: true })));
  assertEquals(down.at(-1)?.outage, true);
});

Deno.test('pieces never lose or add a character', () => {
  for (const t of ['', '  lead', 'one', 'a b c d e f g h i', 'x\n\ny  z ']) assertEquals(pieces(t).join(''), t.trim() ? t : '');
});

// prevented by: this test. Sentences emitted while the model writes go out at once; the final text is not sent twice,
// and when the final reply differs (the model rewrote it) a reset precedes it so the widget shows only that text.
Deno.test('live sentences stream as written; a rewritten final reply is preceded by reset', async () => {
  const same = await lines(streamReply(STATUS.en, async (emit) => { emit('One. '); emit('Two.'); return { reply: 'One. Two.' }; }));
  assertEquals(same.map((e) => e.t), ['status', 'delta', 'delta', 'done']);
  const fixed = await lines(streamReply(STATUS.en, async (emit) => { emit('One. '); return { reply: 'Better one.' }; }));
  assertEquals(fixed.map((e) => e.t), ['status', 'delta', 'reset', 'delta', 'done']);
  assertEquals(fixed.at(-1).reply, 'Better one.');
});

// founder ruling 1636 (11 Nov 2026): a long wait is not a dead connection. Known-bad control: without the interval no
// 'working' line is sent; without the caught enqueue a reader that left throws inside run's emit and the answer is lost.
Deno.test('a slow answer: "working" keep-alives while no sentence has been sent, none once the answer streams', async () => {
  const out = await lines(streamReply(STATUS.en, async (emit) => {
    await new Promise((r) => setTimeout(r, 2_300));
    emit('One. ');
    await new Promise((r) => setTimeout(r, 1_200));
    return { reply: 'One.' };
  }, 1_000));
  const kinds = out.map((e) => e.t);
  assertEquals(kinds[0], 'status');
  assertEquals(kinds.filter((k) => k === 'working').length, 2, kinds.join(','));
  assert(kinds.indexOf('working') < kinds.indexOf('delta') && kinds.lastIndexOf('working') < kinds.indexOf('delta'), 'no keep-alive after the answer began');
  assert(out.filter((e) => e.t === 'working').every((e) => Object.keys(e).length === 1), 'a keep-alive carries no text');
});

Deno.test('the person left the page: the answer is still written (run finishes), and nothing throws', async () => {
  let finished = false;
  const s = streamReply(STATUS.en, async (emit) => {
    await new Promise((r) => setTimeout(r, 50));
    emit('Written anyway. ');   // the reader is gone: this must not throw into run
    finished = true;
    return { reply: 'Written anyway.' };
  }, 1_000);
  const reader = s.getReader();
  await reader.read();          // the status line
  await reader.cancel();        // the tab closed
  await new Promise((r) => setTimeout(r, 120));
  assert(finished, 'the answer was finished (and so stored) after the reader left');
});
