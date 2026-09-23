// The marketing step runner with a MOCKED database and a MOCKED model: no gateway, no storage, no real call.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { type Deps, parseAnswer, runStep, type Step } from './marketing_judgement.ts';

// deno-lint-ignore no-explicit-any
function fakeAdmin(request: any) {
  // deno-lint-ignore no-explicit-any
  const calls: any[] = [];
  return {
    calls,
    // deno-lint-ignore no-explicit-any
    rpc: (name: string, args: any) => {
      calls.push({ name, args });
      if (name === 'fn_marketing_step_request') return Promise.resolve({ data: request, error: null });
      if (name === 'fn_marketing_step_accept') {
        const o = args.p_outcome;
        return Promise.resolve({ data: { ok: o === 'answered', outcome: o === 'held' ? 'held_not_run' : o === 'answered' ? 'written' : o, written: o === 'answered' }, error: null });
      }
      return Promise.resolve({ data: null, error: { message: 'unexpected ' + name } });
    },
  };
}
const neverCalled = (): Deps['callModel'] => () => { throw new Error('the model must not be called'); };

Deno.test('held: records "held, not run" and never builds a request or calls the model', async () => {
  const admin = fakeAdmin({});
  const out = await runStep({ admin, held: () => Promise.resolve(true), callModel: neverCalled() }, 'marketing', 'watch', 'abc');
  assertEquals(out.outcome, 'held_not_run');
  assertEquals(admin.calls.map((c) => c.name), ['fn_marketing_step_accept']);
  assertEquals(admin.calls[0].args.p_outcome, 'held');
  assertEquals(admin.calls[0].args.p_output, null);
});

Deno.test('the CEO review is not a step here (873: it is a seat_deliberation) and is refused before anything is read', async () => {
  const admin = fakeAdmin({});
  let threw = false;
  try { await runStep({ admin, held: () => Promise.resolve(false), callModel: neverCalled() }, 'marketing', 'ceo_review' as Step, '2026-10-01'); }
  catch (e) { threw = /unknown marketing step/.test(String(e)); }
  assert(threw);
  assertEquals(admin.calls.length, 0);
});

Deno.test('watch: the WHOLE video goes in as a base64 video part with vision+audio, and the mocked answer is accepted', async () => {
  const admin = fakeAdmin({ task_class: 'marketing_watch', max_tokens: 2500, system: 'watch', input: { a: 1 }, output_schema: {},
    require_caps: ['vision', 'audio'], video: { bucket: 'marketing-media', path: 'v.mp4', bytes: 5 } });
  // deno-lint-ignore no-explicit-any
  let seen: any = null;
  const out = await runStep({ admin, held: () => Promise.resolve(false),
    download: () => Promise.resolve(new Uint8Array([1, 2, 3, 4, 5])),
    callModel: (cls, max, messages, caps) => { seen = { cls, max, messages, caps };
      return Promise.resolve({ content: '```json\n{"scenes":[{"start_s":0}]}\n```', error: null, truncated: false, model: 'google/gemini-3.8-flash' }); },
  }, 'marketing', 'watch', 'abc');
  assertEquals(seen.cls, 'marketing_watch');
  assertEquals(seen.caps, ['vision', 'audio']);
  const parts = seen.messages[1].content;
  assertEquals(parts[1].type, 'video_url');
  assertEquals(parts[1].video_url.url, 'data:video/mp4;base64,AQIDBAU=');
  const acc = admin.calls.find((c) => c.name === 'fn_marketing_step_accept')!.args;
  assertEquals(acc.p_outcome, 'answered');
  assertEquals(acc.p_output, { scenes: [{ start_s: 0 }] });
  assertEquals(acc.p_model, 'google/gemini-3.8-flash');
  assertEquals(out.outcome, 'written');
});

Deno.test('quality review SEES the key frames: each one is an image part', async () => {
  const admin = fakeAdmin({ task_class: 'marketing_quality_review', max_tokens: 2000, system: 'review', input: {}, output_schema: {},
    images: [{ bucket: 'marketing-media', path: 'features/x/kf_0.jpg' }, { bucket: 'marketing-media', path: 'features/x/kf_1.jpg' }] });
  // deno-lint-ignore no-explicit-any
  let parts: any[] = [];
  await runStep({ admin, held: () => Promise.resolve(false), signedUrl: (_b, p) => Promise.resolve('https://signed/' + p),
    callModel: (_c, _m, messages) => { parts = messages[1].content; return Promise.resolve({ content: '{"hook":{}}', error: null, truncated: false }); },
  }, 'marketing', 'quality_review', 'abc');
  assertEquals(parts.filter((p) => p.type === 'image_url').map((p) => p.image_url.url),
    ['https://signed/features/x/kf_0.jpg', 'https://signed/features/x/kf_1.jpg']);
});

Deno.test('truncated, gateway-held and non-JSON answers write nothing', async () => {
  for (const [ans, want] of [[{ content: '{"a":1', error: null, truncated: true }, 'rejected'],
                             [{ content: null, error: 'gateway_http_503:circuit_open', truncated: false }, 'held'],
                             [{ content: 'sure! here you go', error: null, truncated: false }, 'rejected']] as const) {
    const admin = fakeAdmin({ task_class: 'marketing_evaluate', max_tokens: 3000, system: 's', input: {}, output_schema: {} });
    await runStep({ admin, held: () => Promise.resolve(false), callModel: () => Promise.resolve(ans) }, 'marketing', 'evaluate', '2026-10-01');
    const acc = admin.calls.find((c) => c.name === 'fn_marketing_step_accept')!.args;
    assertEquals(acc.p_outcome, want);
    assertEquals(acc.p_output, null);
  }
  assertEquals(parseAnswer('[1,2]'), null);
});
