// requestAttachments.test.mjs — a BOQ and a drawing attached to one request both go to suppliers.
// node --test src/lib/requestAttachments.test.mjs
// Replays the 22 Sep 2026 production walk: BOQ sheet (3 lines) then drawing PDF (1 line, 2 redacted
// pages) — the request must carry the 3 BOQ lines AND the 2 pages. Also asserts the composer only
// offers "Send to suppliers" once the intake says ready (the same walk got HTTP 428 intake_required).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { mergeAttachment } from './requestAttachments.ts';
import { readSource } from '../../scripts/lib/portal_sources.mjs';

const sheet = { drawing_file_path: null, drawing_file_name: 'ZZDEMO_boq.csv', drawing_redacted_paths: null, boq: { boq: [{ description: 'a' }, { description: 'b' }, { description: 'c' }], category: 'flooring' }, brief_source: 'boq' };
const pdf = { drawing_file_path: 'drawings/c/1_plan.pdf', drawing_file_name: 'ZZDEMO_plan.pdf', drawing_redacted_paths: ['redacted/u/page_p1.jpg', 'redacted/u/page_p2.jpg'], boq: { boq: [{ description: 'm2 25.6' }] }, brief_source: 'drawing' };

test('BOQ then drawing: the BOQ stays and the drawing pages are added', () => {
  const m = mergeAttachment(mergeAttachment(null, sheet), pdf);
  assert.equal(m.boq.boq.length, 3);
  assert.equal(m.brief_source, 'boq');
  assert.deepEqual(m.drawing_redacted_paths, pdf.drawing_redacted_paths);
  assert.equal(m.drawing_file_path, pdf.drawing_file_path);
  assert.deepEqual(m.files, ['ZZDEMO_boq.csv', 'ZZDEMO_plan.pdf']);
  assert.equal(m.share_redacted, undefined);
});

test('drawing then BOQ: the BOQ replaces the drawing reading, the pages stay', () => {
  const m = mergeAttachment(mergeAttachment(null, pdf), sheet);
  assert.equal(m.boq.boq.length, 3);
  assert.deepEqual(m.drawing_redacted_paths, pdf.drawing_redacted_paths);
});

test('two drawings: both files\' pages go, without repeats', () => {
  const pdf2 = { ...pdf, drawing_file_name: 'ZZDEMO_plan2.pdf', drawing_redacted_paths: ['redacted/v/page_p1.jpg', 'redacted/u/page_p2.jpg'] };
  const m = mergeAttachment(mergeAttachment(null, pdf), pdf2);
  assert.deepEqual(m.drawing_redacted_paths, ['redacted/u/page_p1.jpg', 'redacted/u/page_p2.jpg', 'redacted/v/page_p1.jpg']);
});

test('a held drawing shares nothing of itself and takes nothing away', () => {
  const held = { ...pdf, drawing_file_name: 'ZZDEMO_held.pdf', drawing_redacted_paths: null, held: true, share_redacted: false };
  const m = mergeAttachment(mergeAttachment(null, pdf), held);
  assert.deepEqual(m.drawing_redacted_paths, pdf.drawing_redacted_paths);
  assert.equal(m.share_redacted, undefined);
  assert.equal(m.held_name, 'ZZDEMO_held.pdf');
  const only = mergeAttachment(null, held);
  assert.equal(only.share_redacted, false);
  // The customer draws boxes on the held file and it now verifies: the hold is lifted.
  const fixed = mergeAttachment(only, { ...held, held: undefined, share_redacted: undefined, drawing_redacted_paths: ['redacted/w/page_p1.jpg'] });
  assert.equal(fixed.held, undefined);
  assert.deepEqual(fixed.drawing_redacted_paths, ['redacted/w/page_p1.jpg']);
});

test('NewRequest keeps every attachment and never marks itself ready without the intake', () => {
  const src = readSource('src/components/me/NewRequest.tsx');
  assert.match(src, /mergeAttachment\(/, 'adopt() must merge, not replace');
  // Ready is the intake's word (status 'ready'), set in exactly one place: runIntake.
  const readies = src.match(/setReady\(true\)/g) || [];
  assert.equal(readies.length, 1, `setReady(true) appears ${readies.length} times; only runIntake may set it`);
  const at = src.indexOf('setReady(true)');
  assert.ok(src.lastIndexOf("r.status === 'ready'", at) > src.lastIndexOf('const runIntake', at), 'setReady(true) is outside runIntake');
});
