// cad_render — a CAD drawing drawn for a supplier: every tagged element and every room name, dimension and
// legend line on the page, and nothing that names the project, its parties or its people.
// deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/_shared/cad_render.test.ts
//
// 24 Sep 2026, sales_engineer. Founder instructions 32, 580, 703. The fixture is ONE synthetic ZZ DEMO job
// (doc_read/zz_demo_drawings.fixtures.ts) written as ASCII DXF, binary DXF and LibreDWG's DWG JSON, with its
// identity planted in a title-block INSERT's ATTRIBs, the block's own text, a border's plot stamp, a paper-
// space layout, an embedded logo image, $PROJECTNAME / $LASTSAVEDBY, a contact line and a "CONSULTANT:" label
// outside the title block. Offline and deterministic; nothing here reaches a network, a database or a person.
// The encoded JPEG is checked in drawing_redact_page.check.ts (imagescript's Deno build fetches its codec).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { renderCadForSupplier, frameKind, MAX_TITLE_SHARE } from './cad_render.ts';
import { seedTerms } from './anonymise.ts';
import { dwgToDxf } from './doc_read/dwg.ts';
import { dxfFrom, dxfSection } from './doc_read/cad.fixtures.ts';
import { CONTENT, CUSTOMER, FILE_NAME, IDENTITY, zzDwgDb, zzDxf, zzDxfBinary } from './doc_read/zz_demo_drawings.fixtures.ts';

const seeds = seedTerms({ ...CUSTOMER, extra: [FILE_NAME] });
const lower = (s: string) => s.toLowerCase();
const leaks = (texts: string[]) => IDENTITY.filter((id) => texts.some((t) => lower(t).includes(lower(id))));

async function render(input: Uint8Array | string) {
  const g = await renderCadForSupplier(input, { seeds });
  if (!g.ok) throw new Error(`render refused: ${g.reason} ${g.detail}`);
  return g;
}

for (const [name, input] of [['ASCII DXF', () => zzDxf()], ['binary DXF', () => zzDxfBinary()], ['DWG (LibreDWG JSON -> dwgToDxf)', () => dwgToDxf(zzDwgDb()).dxf]] as const) {
  Deno.test(`${name}: every room, dimension, tag and legend line is drawn; no identity string is`, async () => {
    const g = await render(input());
    for (const c of CONTENT) assert(g.drawn_texts.includes(c), `content lost from the supplier's drawing: "${c}" (drawn: ${JSON.stringify(g.drawn_texts)})`);
    assertEquals(leaks(g.drawn_texts), [], 'an identity string was drawn');
    // Seven smoke-detector symbols carry their "SD" label on the plan, and the legend's sample carries one more.
    assertEquals(g.drawn_texts.filter((t) => t === 'SD').length, 8);
    assert(g.withheld.texts >= 3, `the contact line, the label and its value are withheld: ${JSON.stringify(g.withheld)}`);
    assertEquals(g.withheld.regions, 1, 'the title block is one black region');
    assertEquals(g.counts.paper_space_skipped, 1, 'the paper-space layout is not drawn');
  });

  Deno.test(`${name}: the title block is solid black and the drawing is not`, async () => {
    const g = await render(input());
    const bm = g.rgba, W = g.width;
    const titles = g.regions_px.filter((r) => r.kind === 'title');
    assertEquals(titles.length, 1, 'the title block was not painted');
    const title = titles[0];
    // Every pixel of the title region is black: nothing under it can be read.
    let lit = 0;
    for (let y = title.y; y < title.y + title.h; y++) for (let x = title.x; x < title.x + title.w; x++) { const k = (y * W + x) * 4; if (bm[k] > 0 || bm[k + 1] > 0 || bm[k + 2] > 0) lit++; }
    assertEquals(lit, 0, 'a pixel of the title block is not black');
    // The black is a minority of the page, and the drawing outside it has ink: the drawing was not destroyed.
    let black = 0, ink = 0;
    for (let k = 0; k < bm.length; k += 4) { if (bm[k] === 0) black++; else if (bm[k] < 128) ink++; }
    const px = bm.length / 4;
    assert(black / px < MAX_TITLE_SHARE, `${Math.round(100 * black / px)}% of the page is blacked out`);
    assert(ink > 2000, `the drawing has almost no ink (${ink} px)`);
    // The JPEG made from these pixels (no metadata, no identity bytes) is proved in drawing_redact_page.check.ts.
  });
}

Deno.test('ASCII and binary DXF draw the same words, and the DWG path draws the same content', async () => {
  const a = await render(zzDxf()), b = await render(zzDxfBinary()), d = await render(dwgToDxf(zzDwgDb()).dxf);
  assertEquals(a.drawn_texts, b.drawn_texts);
  for (const c of CONTENT) assert(d.drawn_texts.includes(c), c);
});

Deno.test('frame kinds: a title block, logo or revision box is blacked out; a border keeps its lines', () => {
  for (const n of ['ZZ_TITLEBLOCK_A1', 'TB-A1', 'LOGO', 'TITLE BLOCK', 'A-REVS', 'X-XREF']) assertEquals(frameKind(n), 'title', n);
  for (const n of ['BORDER_A1', 'SHEETFRAME', 'VPORT', 'DEFPOINTS']) assertEquals(frameKind(n), 'border', n);
  for (const n of ['SD', 'SKT', 'A-WALL', 'E-FIRE', 'TBL-SCHEDULE']) assertEquals(frameKind(n), null, n);
});

Deno.test('a title-block LAYER that spans the sheet is not blacked out: its words are withheld, its lines drawn', async () => {
  const src = dxfFrom([
    ...dxfSection('HEADER', [[9, '$INSUNITS'], [70, 4]]),
    ...dxfSection('ENTITIES', [
      [0, 'LWPOLYLINE'], [8, 'TITLE'], [90, 4], [70, 1], [10, 0], [20, 0], [10, 10000], [20, 0], [10, 10000], [20, 7000], [10, 0], [20, 7000],
      [0, 'TEXT'], [8, 'TITLE'], [10, 8000], [20, 300], [40, 150], [1, 'ZZ DEMO Harbour Tower'],
      [0, 'TEXT'], [8, 'A-ANNO'], [10, 2000], [20, 3000], [40, 250], [1, 'OFFICE 101'],
    ]),
    [0, 'EOF'],
  ]);
  const g = await render(src);
  assertEquals(g.withheld.regions, 0);
  assert(g.notes.some((n) => /covers \d+% of the sheet/.test(n)), JSON.stringify(g.notes));
  assertEquals(g.drawn_texts, ['OFFICE 101']);
});

Deno.test('too dense for the budget is HELD, never half-drawn; not a DXF is refused', async () => {
  const g = await renderCadForSupplier(zzDxf(), { seeds, maxSegments: 50 });
  assertEquals(g.ok ? 'drawn' : g.reason, 'too_dense');
  const r = await renderCadForSupplier(new TextEncoder().encode('%PDF-1.4 not a drawing'), { seeds });
  assertEquals(r.ok ? 'drawn' : r.reason, 'unreadable');
});
