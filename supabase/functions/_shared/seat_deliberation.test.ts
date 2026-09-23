import { assertEquals } from 'jsr:@std/assert';
import { advanceDeliberation, evidenceImages, MAX_IMAGES, parseReviewOutput } from './seat_deliberation.ts';

Deno.test('a review reply is one JSON object, fenced or not', () => {
  assertEquals(parseReviewOutput('{"verdict":"approve","steelman_against":"x"}')?.verdict, 'approve');
  assertEquals(parseReviewOutput('```json\n{"verdict":"reject"}\n```')?.verdict, 'reject');
});

Deno.test('anything else is not a review: prose, an array, nothing', () => {
  assertEquals(parseReviewOutput('I approve this plan.'), null);
  assertEquals(parseReviewOutput('[{"verdict":"approve"}]'), null);
  assertEquals(parseReviewOutput(null), null);
});

const SHA = 'a'.repeat(64);
const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);

// A mocked bucket: object metadata by path, and a record of every list and download.
function mockAdmin(objects: Record<string, { size: number; mimetype: string } | undefined>, steps: unknown[] = []) {
  const listed: string[] = [], downloads: string[] = [], recorded: Record<string, unknown>[] = [];
  const admin = {
    rpc: (fn: string, args: Record<string, unknown>) => {
      if (fn === 'fn_seat_deliberation_step') return Promise.resolve({ data: steps.shift() ?? { action: 'none' }, error: null });
      recorded.push(args);
      return Promise.resolve({ data: 1, error: null });
    },
    storage: { from: (bucket: string) => ({
      list: (dir: string, o: { search: string }) => {
        listed.push(bucket + ':' + dir + '/' + o.search);
        const m = objects[dir + '/' + o.search];
        return Promise.resolve({ data: m ? [{ name: o.search, metadata: m }] : [], error: null });
      },
      download: (path: string) => {
        downloads.push(bucket + ':' + path);
        return Promise.resolve({ data: new Blob([png], { type: 'image/png' }), error: null });
      },
    }) },
  };
  return { admin, listed, downloads, recorded };
}

// The CEO sees the key frames, not their paths: both the blind and the compare call carry image parts.
Deno.test('a mocked review: server key frames reach the model as image parts on both calls; a missing one is noted', async () => {
  const a = `features/${SHA}/f1.png`, b = `features/${SHA}/f2.jpg`, gone = `features/${SHA}/f3.png`;
  const steps = ['blind', 'compare'].map((phase) => ({
    action: 'call_model', phase, task_class: 'seat_deliberation_' + phase, model: 'anthropic/claude-opus-5.5',
    counterpart_model: 'openai/gpt-5.6-sol', max_tokens: 1500, reviewer_seat: 'ceo', dept: 'marketing', system: 'sys',
    payload: { phase, evidence: { key_frames: ['marketing-media/' + a, b, gone] } },
  }));
  const m = mockAdmin({ [a]: { size: 7, mimetype: 'image/png' }, [b]: { size: 7, mimetype: 'image/jpeg' } }, steps);
  // deno-lint-ignore no-explicit-any
  const calls: any[] = [];
  // deno-lint-ignore no-explicit-any
  const makeLlm = () => (_sys: string, input: string, _max?: number, _st?: string, opts?: any) => {
    calls.push({ input, opts });
    return Promise.resolve({ used_llm: true, error: null, model: 'anthropic/claude-opus-5.5',
      content: JSON.stringify({ verdict: 'approve', steelman_against: 'six words or more against it here',
                                agreements: 'x', disagreements: 'none' }) });
  };
  await advanceDeliberation(m.admin, 7, 2, makeLlm);

  assertEquals(calls.length, 2, 'blind and compare both called the model');
  for (const c of calls) {
    assertEquals(c.opts.counterpartModel, 'openai/gpt-5.6-sol');
    const user = c.opts.messages[1].content;
    const images = user.filter((p: { type: string }) => p.type === 'image_url');
    assertEquals(images.length, 2);
    assertEquals(images[0].image_url.url, 'data:image/png;base64,' + btoa(String.fromCharCode(...png)));
    assertEquals(images[1].image_url.url.startsWith('data:image/jpeg;base64,'), true);
    assertEquals(JSON.parse(user[0].text).images_not_attached, [gone + ' (not found)']);
  }
  assertEquals(m.recorded.map((r) => r.p_phase), ['blind', 'compare']);
  assertEquals(MAX_IMAGES, 6);
});

Deno.test('traversal, foreign and encoded paths are refused without a list or a download', async () => {
  const bad = [`features/${SHA}/../secret.png`, '../features/x.png', `features/${SHA}\\x.png`, `features/${SHA}/a%2e.png`,
               `features//${SHA}/a.png`, 'contracts/deal.png', `features/${SHA}/a..png`];
  const m = mockAdmin({});
  const r = await evidenceImages(m.admin, { key_frames: bad });
  assertEquals(r.parts.length, 0);
  assertEquals(r.missing.length, bad.length);
  assertEquals(r.missing.every((x) => x.endsWith('(not a server-produced key frame path; not read)')), true);
  assertEquals([m.listed.length, m.downloads.length], [0, 0]);
});

Deno.test('a video and an oversized frame are refused from their metadata, before any download', async () => {
  const video = `features/${SHA}/clip.png`, big = `features/${SHA}/big.png`, mp4 = `features/${SHA}/clip.mp4`;
  const m = mockAdmin({ [video]: { size: 900, mimetype: 'video/mp4' }, [big]: { size: 1_500_001, mimetype: 'image/png' } });
  const r = await evidenceImages(m.admin, { key_frames: [video, big, mp4] });
  assertEquals(r.parts.length, 0);
  assertEquals(r.missing, [video + ' (video/mp4, not an image; not read)', big + ' (1500001 bytes, over the cap; not read)',
                           mp4 + ' (not a server-produced key frame path; not read)']);
  assertEquals(m.downloads.length, 0, 'nothing was downloaded');
});
