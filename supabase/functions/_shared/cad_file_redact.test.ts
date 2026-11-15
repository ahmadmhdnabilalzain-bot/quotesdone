// cad_file_redact — the ZZ DEMO drawing as ASCII DXF, binary DXF and DWG (LibreDWG's entity model), redacted as a
// DXF FILE and proved: before and after counts equal (SD x7, SKT x5), geometry pair-for-pair unchanged, no
// identifier string left in the file, and the file still opens in our reader and in cad_render's parser.
//   deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/_shared/cad_file_redact.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { redactCadFile, verifyCadRedaction } from './cad_file_redact.ts';
import { cadStrings } from './drawing_string_reading.ts';
import { readDxf } from './doc_read/cad.ts';
import { dwgToDxf } from './doc_read/dwg.ts';
import { seedTerms } from './anonymise.ts';
import { CAD_COUNTS, CONTENT, CUSTOMER, FILE_NAME, IDENTITY, zzDwgDb, zzDxf, zzDxfBinary } from './doc_read/zz_demo_drawings.fixtures.ts';

const seeds = seedTerms({ ...CUSTOMER, extra: [FILE_NAME] });
// The model that reads every string (drawing_string_reading.ts, 13 Nov 2026), STUBBED: FAITHFUL marks each string that
// carries a planted identity; LAZY marks nothing. Offline: no model is called.
const asText = (b: Uint8Array) => { const t = new TextDecoder('latin1').decode(b.subarray(0, 22)); return t.startsWith('AutoCAD Binary DXF') ? null : new TextDecoder().decode(b); };
const faithful = (b: Uint8Array, dxf?: string) => new Set(cadStrings(dxf ?? asText(b) ?? '').filter((x) => IDENTITY.some((id) => x.toLowerCase().includes(id.toLowerCase()))));

for (const [name, make] of [
  ['ASCII DXF', zzDxf],
  ['binary DXF', zzDxfBinary],
  // The DWG path: LibreDWG's entity model of the same job, through the production dwgToDxf (real DWG bytes are
  // read in dwg_samples.check.ts, which needs the network for LibreDWG's own sample files).
  ['DWG (LibreDWG entities)', () => new TextEncoder().encode(dwgToDxf(zzDwgDb()).dxf)],
] as const) {
  Deno.test(`${name}: redacted as a DXF file — counts equal, geometry unchanged, no identity, still opens`, async () => {
    const lazy = await redactCadFile(make(), seeds, { identity: new Set() });
    assert(lazy.ok, 'held: ' + JSON.stringify(lazy));
    if (!lazy.ok) return;
    const r = await redactCadFile(make(), seeds, { identity: faithful(make(), lazy.before_dxf) });
    assert(r.ok, 'held: ' + JSON.stringify(r));
    if (!r.ok) return;
    const v = await verifyCadRedaction(r.before_dxf, r.dxf, seeds, r, IDENTITY, r.removed);
    assert(v.ok, v.problems.join('\n'));
    assert(v.geometry_pairs[0] > 50 && v.geometry_pairs[0] === v.geometry_pairs[1], `geometry ${v.geometry_pairs}`);
    // The hand count, read off the REDACTED file.
    const after = await readDxf(r.bytes, { filename: 'redacted.dxf', depth: 0 });
    assert(after.ok);
    if (!after.ok) return;
    const q = (b: string) => after.quantities.find((x) => x.description === `block ${b}`)?.qty;
    assertEquals([q('SD'), q('SKT')], [CAD_COUNTS.SD, CAD_COUNTS.SKT]);
    for (const c of CONTENT) assert(after.text.includes(c), `content "${c}" was lost`);
    for (const id of IDENTITY) assert(!r.dxf.toLowerCase().includes(id.toLowerCase()), `"${id}" is still in the file`);
    // The title block's attribute TAGS stay (the entity is kept, its value emptied); its block name is neutral.
    assert(/\n\s*2\r?\nCLIENT\r?\n/.test(r.dxf), 'the CLIENT attribute entity was removed rather than emptied');
    assert(!r.dxf.includes('ZZ_TITLEBLOCK_A1'), 'the title block keeps its firm-named block name');
  });
}

Deno.test('no reading of the strings, no file; a LAZY reading still removes everything the rules know', async () => {
  const none = await redactCadFile(zzDxf(), seeds);
  assertEquals(none.ok ? 'released' : none.held, 'strings_not_read');
  const lazy = await redactCadFile(zzDxf(), seeds, { identity: new Set() });
  assert(lazy.ok);
  if (!lazy.ok) return;
  const v = await verifyCadRedaction(lazy.before_dxf, lazy.dxf, seeds, lazy, [], lazy.removed);
  assert(v.ok, v.problems.join('\n'));
  // What the floor can read is gone with no model at all: the customer, his e-mail and phone, the title block's party.
  for (const id of ['Rashid', 'Kareem', 'example.invalid', '0000017', 'Drafter']) assert(!lazy.dxf.toLowerCase().includes(id.toLowerCase()), `"${id}" left on a lazy reading`);
});

Deno.test('the check fails when the cause returns: the original passed off as redacted, or a moved point, is caught', async () => {
  const before = new TextDecoder().decode(zzDxf());
  const r = await redactCadFile(zzDxf(), seeds, { identity: faithful(zzDxf()) });
  assert(r.ok);
  if (!r.ok) return;
  const same = await verifyCadRedaction(before, before, seeds, r, IDENTITY, r.removed);
  assert(!same.ok && same.identity_left.length > 0, 'an unredacted file passed');
  const moved = r.dxf.replace(/\n 10\r?\n1000\r?\n/, '\n 10\n1001\n');
  assert(moved !== r.dxf, 'the fixture changed: no point to move');
  const bad = await verifyCadRedaction(before, moved, seeds, r, IDENTITY, r.removed);
  assert(bad.problems.some((p) => /geometry/.test(p)), bad.problems.join('\n'));
});

Deno.test('a file that is not CAD is held, never passed on', async () => {
  const r = await redactCadFile(new TextEncoder().encode('%PDF-1.4 not a drawing'), seeds, { identity: new Set() });
  assertEquals(r.ok ? 'published' : r.held, 'not_a_cad_file');
});
