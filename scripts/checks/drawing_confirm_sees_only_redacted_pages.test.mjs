// drawing_confirm_sees_only_redacted_pages — the drawing confirm step's vision model can only ever
// receive a page produced and recorded by the redaction step. Assigned: sales_engineer.
//
// Independent review of #642, 14 Sep 2026: customer_api started drawing_boq in parallel with
// redaction, and drawing_boq's confirm step sent the request's first page — the ORIGINAL, with the
// client's name, site and logo — to a third-party model. Now:
//   * drawing_boq's confirmStep takes a RedactedPage and nothing from the request; its one call site
//     passes the page redactedPageFor() derived from the drawing_redaction_runs record;
//   * customer_api calls mode 'confirm' after redaction finished, with the run id only when every
//     page came back, and with no page images at all.
// The decision itself (which runs yield a page) is tested in
// supabase/functions/drawing_boq/confirm_redacted_only.test.ts.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { functionSource } from '../lib/function_sources.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');

test('drawing_boq: confirmStep takes no image from the request and is called only with a redacted page', () => {
  const src = read('supabase/functions/drawing_boq/index.ts');
  const start = src.indexOf('async function confirmStep(');
  assert.ok(start > 0, 'confirmStep not found');
  const fn = src.slice(start, src.indexOf('\nfunction ', start));
  // + the draft's author model (23 Sep 2026, founder instruction ~891): a model id or 'deterministic', never page content
  assert.match(fn, /confirmStep\(lines: any\[\], page: RedactedPage, author: string\)/, 'the signature takes a RedactedPage');
  // Reading the request = a property access on the handler's body (the fetch option key is not).
  assert.doesNotMatch(fn, /\bbody\s*(?:\.|\?\.|\[)/, 'confirmStep must not read the request body');
  assert.doesNotMatch(fn, /\bimages\b/, 'confirmStep must not touch request images');
  const calls = [...src.matchAll(/await confirmStep\(([^)]*)\)/g)].map((m) => m[1]);
  assert.deepEqual(calls, ['lines, page, author'], 'exactly one call, with the page');
  assert.match(src, /const page = redactedPageFor\(/, 'the page comes from redactedPageFor');
});

test('customer_api asks for the confirm only after redaction, with the run id, never with images', () => {
  const src = functionSource('customer_api');
  const at = src.indexOf("mode: 'confirm'");
  assert.ok(at > 0, 'confirm call not found');
  const call = src.slice(src.lastIndexOf('fetch(', at), src.indexOf('});', at));
  assert.doesNotMatch(call, /\bimages\b|original_b64/, 'the confirm call carries no page images');
  assert.match(call, /redaction_job_id: redMeta\.redaction_complete \? redJobs\[0\] : null/, 'job id only when redaction completed');
  assert.ok(src.indexOf('const redMeta') > 0 && src.indexOf('const redMeta') < at, 'the confirm call comes after redaction finished');
});
