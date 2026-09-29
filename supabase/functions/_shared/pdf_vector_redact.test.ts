// pdf_vector_redact — the ZZ DEMO vector sheets redacted AS PDFs and proved: before and after counts equal,
// geometry unchanged, no identifier string left anywhere in the file, and the file still opens.
//   deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/_shared/pdf_vector_redact.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { cutOperators, redactPdfVector, verifyPdfRedaction } from './pdf_vector_redact.ts';
import { linesFromRuns, pdfPages, pdfRedactionView } from './pdf_text_positions.ts';
import { seedTerms } from './anonymise.ts';
import { CONTENT, CUSTOMER, FILE_NAME, IDENTITY, PDF_COUNTS, zzPdfScan, zzPdfSet, zzPdfSheet, zzPdfSheetWithLogo } from './doc_read/zz_demo_drawings.fixtures.ts';

const seeds = seedTerms({ ...CUSTOMER, extra: [FILE_NAME] });

for (const [name, make, sheets] of [['one sheet', zzPdfSheet, 1], ['3-sheet set', zzPdfSet, 3]] as const) {
  Deno.test(`vector PDF (${name}): identity cut, geometry and counts unchanged, nothing left, still opens`, async () => {
    const before = make();
    const r = await redactPdfVector(before, seeds);
    assert(r.ok, 'held: ' + JSON.stringify(r));
    if (!r.ok) return;
    assertEquals(new TextDecoder().decode(r.bytes.subarray(0, 5)), '%PDF-');
    const v = await verifyPdfRedaction(before, r.bytes, seeds, IDENTITY);
    assert(v.ok, v.problems.join('\n'));
    assertEquals(v.pages, [sheets, sheets]);
    assert(v.geometry_ops[0] > 0 && v.geometry_ops[0] === v.geometry_ops[1], `geometry ops ${v.geometry_ops}`);
    // The hand count survives on the redacted file itself.
    const after = await pdfPages(r.bytes);
    const text = linesFromRuns(after);
    const n = (re: RegExp) => after.flatMap((p) => p.runs).filter((x) => re.test(x.text)).length;
    if (sheets === 1) assertEquals([n(/^FD-1$/), n(/^WC-1$/), n(/^FCU-\d$/)], [PDF_COUNTS['FD-1'], PDF_COUNTS['WC-1'], PDF_COUNTS.FCU]);
    assertEquals(v.counts.before, v.counts.after);
    assert(Object.keys(v.counts.before).length > 0, 'no take-off to compare');
    for (const c of CONTENT.filter((c) => !/SD - |SKT - /.test(c))) assert(text.includes(c), `content "${c}" was cut`);
    assert(r.removed_runs >= 9 * sheets, `only ${r.removed_runs} identity runs cut`);
  });
}

Deno.test('the check fails when the cause returns: an identity run left in, or a line moved, is caught', async () => {
  const before = zzPdfSheet();
  // Not redacted at all: identity left.
  const same = await verifyPdfRedaction(before, before, seeds, IDENTITY);
  assert(!same.ok && same.identity_left.length > 0, 'an unredacted sheet passed');
  // Geometry moved: one line endpoint edited.
  const r = await redactPdfVector(before, seeds);
  assert(r.ok);
  if (!r.ok) return;
  const src = new TextDecoder('latin1').decode(before).replace(/ m (\d+\.\d) (\d+\.\d) l S/, (_m, a, b) => ` m ${Number(a) + 5} ${b} l S`);
  const moved = new Uint8Array([...src].map((c) => c.charCodeAt(0)));
  const bad = await verifyPdfRedaction(moved, r.bytes, seeds, IDENTITY);
  assert(bad.problems.some((p) => /geometry/.test(p)), bad.problems.join('\n'));
});

Deno.test('a VECTOR logo in the title strip is cut; every path outside the strip is byte-identical', async () => {
  const before = zzPdfSheetWithLogo();
  const r = await redactPdfVector(before, seeds);
  assert(r.ok, 'held: ' + JSON.stringify(r));
  if (!r.ok) return;
  assertEquals(r.removed_paths >= 2, true, `only ${r.removed_paths} logo paths cut`);
  const v = await verifyPdfRedaction(before, r.bytes, seeds, IDENTITY);
  assert(v.ok, v.problems.join('\n'));
  assertEquals(v.counts.before, v.counts.after);
  // The logo's own operators are gone from the file; a plan wall is still there, character for character.
  const view = await pdfRedactionView(r.bytes);
  const content = view!.pages[0].content;
  assert(/0\.1 0\.3 0\.6 rg [\d.]+ [\d.]+ 259\.2 86\.4 re f/.test(new TextDecoder('latin1').decode(before)), 'the fixture carries no logo badge');
  assert(!/0\.1 0\.3 0\.6 rg [\d.]+ [\d.]+ 259\.2 86\.4 re f/.test(content), 'the logo badge is still drawn');
  assert(content.includes('129.6 1555.2 m 907.2 1555.2 l S'), 'a wall outside the strip was changed');
});

Deno.test('a scanned sheet is held here (scan_redact paints it), never passed through', async () => {
  const r = await redactPdfVector(zzPdfScan(), seeds);
  assertEquals(r.ok ? 'published' : r.held, 'no_text_layer');
});

Deno.test('cutOperators removes an operator with its operands and keeps the line move of a quote operator', () => {
  const src = 'BT /F1 9 Tf 1 0 0 1 10 10 Tm (ZZ DEMO) Tj (keep) Tj 12 TL (gone) \' ET 0 0 m 5 5 l S /Im1 Do';
  // ops: Tf=1 Tm=2 Tj=3 Tj=4 TL=5 '=6 ET=7 m=8 l=9 S=10 Do=11 (BT=0? counted first)
  const ops = [...src.matchAll(/(?:^|\s)(BT|Tf|Tm|Tj|TL|'|ET|m|l|S|Do)(?=\s|$)/g)].map((m) => m[1]);
  const idx = (op: string, nth = 0) => ops.map((o, i) => [o, i + 1] as const).filter(([o]) => o === op)[nth][1];
  const out = cutOperators(src, new Set([idx('Tj', 0), idx("'"), idx('Do')]));
  assert(!out.src.includes('ZZ DEMO') && !out.src.includes('gone') && !out.src.includes('Im1'), out.src);
  assert(out.src.includes('(keep) Tj') && out.src.includes('T*') && out.src.includes('0 0 m 5 5 l S'), out.src);
});
