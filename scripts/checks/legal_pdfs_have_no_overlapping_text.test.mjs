// No text in a legal PDF may sit on top of other text.
//   node --test scripts/checks/legal_pdfs_have_no_overlapping_text.test.mjs
//
// 14 Sep 2026, agent: accountant. The founder saw text overlapping around "9% per annum" in the
// supplier-charge recovery documents. Measured: the totals row drew a long label and its figure on
// one line with no wrapping, and six of the fourteen samples overlapped by up to 42.6pt. The fix is
// in pdf_native/render.ts (totals). This check renders all fourteen documents, EN and AR, through the
// real renderer and reads every text box back out of each PDF with pdf.js: no two may overlap.
// The brand fonts come from the public brand bucket (read-only); without the network the renderer
// falls back to Helvetica, which cannot draw Arabic, so the check says it was skipped rather than
// passing over empty Arabic pages.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { overlapsIn } from '../legal/pdf_text_overlaps.mjs';

test('the fourteen supplier-charge documents render with no overlapping text', async (t) => {
  const out = mkdtempSync(join(tmpdir(), 'qd-legal-pdf-'));
  try {
    const r = spawnSync('deno', ['run', '--no-lock', '--node-modules-dir=auto', '--allow-net=htdblwldjkcgjvmqkbeh.supabase.co',
      `--allow-write=${out}`, 'scripts/legal/render_supplier_charge_samples.ts', out], { encoding: 'utf8', timeout: 240_000 });
    if (r.error?.code === 'ENOENT') return t.skip('deno is not on PATH');
    assert.equal(r.status, 0, 'the renderer refused a document:\n' + r.stderr + r.stdout);
    if (!/"arabic":true/.test(r.stdout)) return t.skip('brand fonts unreachable; Arabic pages would be empty');
    const pdfs = readdirSync(out).filter((f) => f.endsWith('.pdf')).sort();
    assert.equal(pdfs.length, 14, 'expected 14 documents, got ' + pdfs.length);
    const bad = [];
    for (const f of pdfs) for (const o of await overlapsIn(readFileSync(join(out, f)))) bad.push(`${f} p${o.page}: "${o.a}" × "${o.b}" (${o.w}×${o.h}pt)`);
    assert.deepEqual(bad, [], 'overlapping text:\n' + bad.join('\n'));
  } finally { rmSync(out, { recursive: true, force: true }); }
});
