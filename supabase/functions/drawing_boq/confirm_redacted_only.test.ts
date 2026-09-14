// deno test supabase/functions/drawing_boq/confirm_redacted_only.test.ts
// The confirm step's vision model may only ever see a page drawing_redact produced and recorded as
// fully cleaned. Review of #642 (14 Sep 2026): the first version sent the request's ORIGINAL page, in
// parallel with redaction. This is the decision itself; the wiring (drawing_boq takes no request image,
// customer_api calls it only after redaction) is held by
// scripts/checks/drawing_confirm_sees_only_redacted_pages.test.mjs, which can read source files.
import { assertEquals } from 'jsr:@std/assert@1';
import { redactedPageFor } from './confirm.ts';

const OK = { id: '0b9f6a34-7d1c-4a5e-9f00-1a2b3c4d5e6f', status: 'complete', pages_in: 1, pages_out: 1, output_paths: ['redacted/5d2f0c11-2a3b-4c5d-8e9f-0a1b2c3d4e5f/page_p0.jpg'] };

Deno.test('only a complete, recorded redaction run yields a page', () => {
  assertEquals(redactedPageFor(OK), { path: OK.output_paths[0], job_id: OK.id });
  for (const bad of [
    null, undefined,
    { ...OK, status: 'partial' }, { ...OK, status: 'failed' }, { ...OK, status: 'detect_failed' }, { ...OK, status: 'boq_held' },
    { ...OK, pages_out: 0 }, { ...OK, pages_in: 0, pages_out: 0 }, { ...OK, pages_in: 2, pages_out: 1 },
    { ...OK, output_paths: [] }, { ...OK, output_paths: null },
    // the customer's original upload, or any path not made by drawing_redact
    { ...OK, output_paths: ['drawings/5d2f0c11-2a3b-4c5d-8e9f-0a1b2c3d4e5f/original.png'] },
    { ...OK, output_paths: ['redacted/../drawings/x/page_p0.jpg'] },
    { ...OK, output_paths: ['refphoto/5d2f0c11-2a3b-4c5d-8e9f-0a1b2c3d4e5f/page_p0.jpg'] },
  ]) assertEquals(redactedPageFor(bad as never), null, JSON.stringify(bad));
});
