// No text in a legal PDF may sit on top of other text, and no page after the first may be mostly empty.
//   node --test scripts/checks/legal_pdfs_have_no_overlapping_text.test.mjs
//
// 14 Sep 2026, agent: accountant. The founder saw text overlapping around "9% per annum" in the
// supplier-charge recovery documents (the totals row: six of fourteen overlapped by up to 42.6pt), then
// Reminder 2 put its totals alone on an 80%-empty page 2. Both are fixed; this keeps them fixed.
//
// The measuring runs in Deno (scripts/legal/check_legal_pdf_layout.ts): it renders all 14 documents EN + AR
// through the real renderer with the brand fonts and reads every text box back out of each PDF with pdf.js
// (npm:pdfjs-dist@4.10.38, the version package-lock.json already pins). The checks job runs `npm test` with
// no `npm ci`, so a Node import of pdfjs-dist cannot resolve there; Deno fetches the pinned package itself.
// Not skipped when the fonts are unreachable: that is a failure (the Arabic pages would be empty).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
// --node-modules-dir=none, not =auto (11 Nov 2026): =auto relinked the repository's pdfjs-dist 6.5.438 to the 4.10.38
// scripts/legal/pdf_layout.ts imports, so a next build after this check bundled a pdfjs the lockfile never named.
import { DENO_NPM_FLAGS } from '../lib/deno_npm.mjs';

test('the fourteen supplier-charge documents: no overlapping text, no mostly-empty page', () => {
  const r = spawnSync('deno', ['run', ...DENO_NPM_FLAGS, '--allow-net=htdblwldjkcgjvmqkbeh.supabase.co',
    'scripts/legal/check_legal_pdf_layout.ts'], { encoding: 'utf8', timeout: 300_000 });
  assert.ok(!(r.error && r.error.code === 'ENOENT'), 'deno is not on PATH; run.mjs requires it');
  assert.equal(r.status, 0, (r.stderr || '') + (r.stdout || ''));
  assert.match(r.stdout, /14\/14: no overlapping text, no mostly-empty page/);
});
