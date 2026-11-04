// drawing_redact encodes a page at most once in a worker (it_engineer, 2 Nov 2026). On 1 Nov 4 of 4 model-path calls
// died "CPU Time exceeded" (HTTP 546, 5.8-14.4 s wall, no drawing_redaction_runs row written): the verifier's retry
// painted and encoded the page a second time in the worker that had already decoded and encoded it. The retry now
// runs in a fresh worker (mode 'repaint', _shared/drawing_redact_page.ts repaintJpeg). Offline: reads the source.
//   deno test supabase/functions/drawing_redact/one_encode_per_worker.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';

const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url)).replace(/\r\n/g, '\n');
const count = (re: RegExp) => (src.match(re) || []).length;

Deno.test('the model path encodes a page once; the retry is handed to another worker', () => {
  assertEquals(count(/\.encodeJPEG\(/g), 1, 'a second JPEG encode is back in drawing_redact/index.ts');
  assertMatch(src, /repaintElsewhere\(/);
  assertMatch(src, /body\.mode === 'repaint'/);
});

Deno.test('a repaint that does not come back refuses the page (fail closed)', () => {
  assertMatch(src, /rp\.ok \? \{ clean: rp\.clean, found: rp\.found \} : \{ clean: false,/);
});

Deno.test('the repaint worker records and uploads nothing', () => {
  const start = src.indexOf("if (body.mode === 'repaint')");
  assert(start > 0);
  const branch = src.slice(start, src.indexOf('\n    }\n', start));
  assert(!/publish\(|storage\.from\(/.test(branch), 'the repaint branch must leave recording and upload to its caller');
});
