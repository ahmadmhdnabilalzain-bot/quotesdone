import { assertEquals } from 'jsr:@std/assert';
import { advanceDeliberation, MAX_IMAGES, parseReviewOutput } from './seat_deliberation.ts';

Deno.test('a review reply is one JSON object, fenced or not', () => {
  assertEquals(parseReviewOutput('{"verdict":"approve","steelman_against":"x"}')?.verdict, 'approve');
  assertEquals(parseReviewOutput('```json\n{"verdict":"reject"}\n```')?.verdict, 'reject');
});

Deno.test('anything else is not a review: prose, an array, nothing', () => {
  assertEquals(parseReviewOutput('I approve this plan.'), null);
  assertEquals(parseReviewOutput('[{"verdict":"approve"}]'), null);
  assertEquals(parseReviewOutput(null), null);
});

// The CEO sees the key frames, not their paths: both the blind and the compare call carry image parts.
Deno.test('a mocked review: key frames reach the model as image parts on both calls; a missing one is noted, not fatal', async () => {
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
  const frames = ['marketing-media/a.png', 'b.png', 'gone.png'];
  const steps = ['blind', 'compare'].map((phase) => ({
    action: 'call_model', phase, task_class: 'seat_deliberation_' + phase, model: 'anthropic/claude-opus-5.5',
    counterpart_model: 'openai/gpt-5.6-sol', max_tokens: 1500, reviewer_seat: 'ceo', dept: 'marketing', system: 'sys',
    payload: { phase, evidence: { key_frames: frames } },
  }));
  const recorded: Record<string, unknown>[] = [];
  const downloads: string[] = [];
  const admin = {
    rpc: (fn: string, args: Record<string, unknown>) => {
      if (fn === 'fn_seat_deliberation_step') return Promise.resolve({ data: steps.shift() ?? { action: 'none' }, error: null });
      recorded.push(args);
      return Promise.resolve({ data: 1, error: null });
    },
    storage: { from: (bucket: string) => ({ download: (path: string) => {
      downloads.push(bucket + ':' + path);
      return Promise.resolve(path === 'gone.png' ? { data: null, error: { message: 'Object not found' } }
                                                 : { data: new Blob([png], { type: 'image/png' }), error: null });
    } }) },
  };
  // deno-lint-ignore no-explicit-any
  const calls: any[] = [];
  // deno-lint-ignore no-explicit-any
  const makeLlm = () => (_sys: string, input: string, _max?: number, _st?: string, opts?: any) => {
    calls.push({ input, opts });
    return Promise.resolve({ used_llm: true, error: null, model: 'anthropic/claude-opus-5.5',
      content: JSON.stringify({ verdict: 'approve', steelman_against: 'six words or more against it here',
                                agreements: 'x', disagreements: 'none' }) });
  };
  await advanceDeliberation(admin, 7, 2, makeLlm);

  assertEquals(calls.length, 2, 'blind and compare both called the model');
  for (const c of calls) {
    assertEquals(c.opts.counterpartModel, 'openai/gpt-5.6-sol');
    const user = c.opts.messages[1].content;
    const images = user.filter((p: { type: string }) => p.type === 'image_url');
    assertEquals(images.length, 2);
    assertEquals(images[0].image_url.url, 'data:image/png;base64,' + btoa(String.fromCharCode(...png)));
    assertEquals(JSON.parse(user[0].text).images_not_attached, ['gone.png (Object not found)']);
  }
  assertEquals(downloads.slice(0, 3), ['marketing-media:a.png', 'marketing-media:b.png', 'marketing-media:gone.png']);
  assertEquals(recorded.map((r) => r.p_phase), ['blind', 'compare']);
  assertEquals(MAX_IMAGES, 6);
});
