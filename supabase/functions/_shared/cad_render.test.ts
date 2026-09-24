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
import { CONTENT, CUSTOMER, FILE_NAME, IDENTITY, zzDwgDb, zzDxf, zzDxfBinary, zzLeakyDxf } from './doc_read/zz_demo_drawings.fixtures.ts';

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

// Review of #967: a title layer that spans the sheet (the border is on it) had its LINES drawn, so a vector logo
// and SHX-exploded text reached the supplier. Now nothing on a title layer is drawn: everything inside the border
// is blacked out tight, and a title layer that is most of the sheet even inside its border is HELD.
type P = [number, string | number][];
const titleSheet = (logo: boolean, extra: P = []) => dxfFrom([
  ...dxfSection('HEADER', [[9, '$INSUNITS'], [70, 4]]),
  ...dxfSection('ENTITIES', [
    [0, 'LWPOLYLINE'], [8, 'TITLE'], [90, 4], [70, 1], [10, 0], [20, 0], [10, 10000], [20, 0], [10, 10000], [20, 7000], [10, 0], [20, 7000],
    ...(logo ? [[0, 'LWPOLYLINE'], [8, 'TITLE'], [90, 5], [70, 1], [10, 8500], [20, 300], [10, 9500], [20, 300], [10, 9000], [20, 1300], [10, 8700], [20, 700], [10, 9300], [20, 700]] as P : []),
    [0, 'TEXT'], [8, 'TITLE'], [10, 8000], [20, 1500], [40, 150], [1, 'ZZ DEMO Harbour Tower'],
    [0, 'TEXT'], [8, 'A-ANNO'], [10, 2000], [20, 3000], [40, 250], [1, 'OFFICE 101'],
    ...extra,
  ]),
  [0, 'EOF'],
]);
Deno.test('a title LAYER spanning the sheet: its logo linework is never drawn, everything inside the border is black', async () => {
  const withLogo = await render(titleSheet(true)), noLogo = await render(titleSheet(false));
  assertEquals(withLogo.drawn_texts, ['OFFICE 101']);
  const title = withLogo.regions_px.filter((r) => r.kind === 'title');
  assertEquals(title.length, 1, 'the title layer was not blacked out');
  const t = title[0];
  const inT = (i: number) => { const x = (i / 4) % withLogo.width, y = Math.floor(i / 4 / withLogo.width); return x >= t.x && x < t.x + t.w && y >= t.y && y < t.y + t.h; };
  // Outside the title box, the page with the logo and the page without it are the same pixels: the logo drew nothing.
  let differ = 0;
  for (let i = 0; i < withLogo.rgba.length; i += 4) if (!inT(i) && withLogo.rgba[i] !== noLogo.rgba[i]) differ++;
  assertEquals(differ, 0, 'the logo linework reached the page outside the black box');
  for (let i = 0; i < withLogo.rgba.length; i += 4) if (inT(i)) assertEquals(withLogo.rgba[i], 0, 'a pixel of the title box is not black');
  // The border itself (on the title layer, framing the page) is not drawn either: no column carries a line
  // running most of the page's height.
  const tall = [];
  for (let x = 0; x < withLogo.width; x++) { let n = 0; for (let y = 0; y < withLogo.height; y++) if (withLogo.rgba[(y * withLogo.width + x) * 4] === 32) n++; if (n > 0.8 * withLogo.height) tall.push(x); }
  assertEquals(tall, [], 'the title layer\'s border linework was drawn');
  // The same layer reaching across the sheet inside its border (a cross of long lines) is held, not guessed at.
  const held = await renderCadForSupplier(titleSheet(true, [[0, 'LINE'], [8, 'TITLE'], [10, 100], [20, 100], [11, 9900], [21, 6900], [0, 'LINE'], [8, 'TITLE'], [10, 100], [20, 6900], [11, 9900], [21, 100]]), { seeds });
  assertEquals(held.ok ? 'drawn' : held.reason, 'title_unbounded');
});

// Review of #967: every one of these reached a supplier's page through the first version. The default is now
// withhold (drawing_text_policy.ts), runs on a line are read together, and the drawn page is re-read before it goes.
Deno.test('parties no rule used to recognise are withheld; rooms and dimensions are still drawn', async () => {
  const src = zzLeakyDxf();
  const g = await render(src);
  for (const c of ['OFFICE 101', 'MEETING ROOM 102', 'CORRIDOR', '6000']) assert(g.drawn_texts.includes(c), `content lost: ${c} (drawn ${JSON.stringify(g.drawn_texts)})`);
  const drawn = g.drawn_texts.join(' | ');
  for (const bad of [/ORBIT/i, /HARBOUR/i, /HOLDINGS/i, /123456/, /R\s*A\s*S\s*H\s*I\s*D/i, /SHEET 4/, /GROUND FLOOR/]) assert(!bad.test(drawn), `${bad} was drawn: ${drawn}`);
  assert(!g.drawn_texts.join('').toLowerCase().includes('kareem'), 'the name split one letter per TEXT was drawn');
  assert(!g.drawn_texts.some((t) => /^[KAREM]$/.test(t)), `a letter of the split name was drawn: ${drawn}`);
});

Deno.test('too dense for the budget is HELD, never half-drawn; not a DXF is refused', async () => {
  const g = await renderCadForSupplier(zzDxf(), { seeds, maxSegments: 50 });
  assertEquals(g.ok ? 'drawn' : g.reason, 'too_dense');
  const r = await renderCadForSupplier(new TextEncoder().encode('%PDF-1.4 not a drawing'), { seeds });
  assertEquals(r.ok ? 'drawn' : r.reason, 'unreadable');
});
