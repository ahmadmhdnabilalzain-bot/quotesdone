// drawing_redact encodes a page at most once in a worker (it_engineer, 2 Nov 2026). On 1 Nov 4 of 4 model-path calls
// died "CPU Time exceeded" (HTTP 546, 5.8-14.4 s wall, no drawing_redaction_runs row written): the verifier's retry
// painted and encoded the page a second time in the worker that had already decoded and encoded it. The retry now
// runs in a fresh worker (mode 'repaint', _shared/drawing_redact_page.ts repaintJpeg). Offline: reads the source.
//   deno test supabase/functions/drawing_redact/one_encode_per_worker.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';

const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url)).replace(/\r\n/g, '\n');
const count = (re: RegExp) => (src.match(re) || []).length;

Deno.test('no worker of a page decodes or encodes it more than once; the paint and the retry are handed to other workers', () => {
  // 17 Nov 2026: the one encode left here (the model path's) moved to the paint worker with the manual path's, because the
  // worker that reads the PDF and asks the gate died "CPU Time exceeded" on every 2600 px sheet of the 8-sheet set
  // (a_sheet_is_redacted_within_the_edge_budget.check.ts). Every decode and encode is now in a _shared function one
  // worker mode runs: paint (paintedJpeg), repaint (repaintJpeg), tile (tileJpeg), tiles (tilesJpeg: one decode, an encode a
  // view, 17 Nov 2026), ink (inkCells).
  assertEquals(count(/\.encodeJPEG\(|Image\.decode\(/g), 0, 'a JPEG decode or encode is back in drawing_redact/index.ts');
  assertMatch(src, /paintedElsewhere\(/);
  assertMatch(src, /body\.mode === 'paint'/);
  // 13 Nov 2026: the pixel gate's re-check paints in a fresh worker too (paintElsewhere, mode 'repaint' verify:false).
  assertMatch(src, /paintElsewhere\(/);
  assertMatch(src, /body\.mode === 'repaint'/);
});

Deno.test('a repaint that does not come back refuses the page (fail closed)', () => {
  assertMatch(src, /if \(!r\.ok \|\| j\?\.ok !== true \|\| typeof j\.jpg_b64 !== 'string'\) throw new Error\('repaint_failed'\);/);
});

Deno.test('the repaint worker records and uploads nothing', () => {
  const start = src.indexOf("if (body.mode === 'repaint')");
  assert(start > 0);
  const branch = src.slice(start, src.indexOf('\n    }\n', start));
  assert(!/publish\(|storage\.from\(/.test(branch), 'the repaint branch must leave recording and upload to its caller');
});

Deno.test('the paint worker records and uploads nothing, and a paint that does not come back holds the page', () => {
  const start = src.indexOf("if (body.mode === 'paint')");
  assert(start > 0);
  const branch = src.slice(start, src.indexOf('\n    }\n', start));
  assert(!/publish\(|storage\.from\(/.test(branch), 'the paint branch must leave recording and upload to its caller');
  assertMatch(src, /if \(!r\.ok \|\| j\?\.ok !== true \|\| typeof j\.jpg_b64 !== 'string'\) throw new Error\(j\?\.error === 'decode_failed' \? 'decode_failed' : 'paint_failed'\);/);
  // The manual path counts a failed paint as a skipped page, never publishes it.
  assertMatch(src, /catch \(e\) \{ skipped\+\+; detail\.push\(\{ page: i, skipped: \(e as Error\)\?\.message === 'decode_failed' \? 'decode_failed' : 'paint_failed' \}\); continue; \}/);
});
