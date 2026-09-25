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
import { CONTENT, CUSTOMER, FILE_NAME, IDENTITY, zzDwgDb, zzDxf, zzDxfBinary, zzExplodedTitleDxf, zzGlyphSheetDxf, zzLeakyDxf } from './doc_read/zz_demo_drawings.fixtures.ts';

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
  assert(!g.drawn_texts.join('').toLowerCase().includes('kareem'), 'the letter-spaced name was drawn');
});

// ── SECOND REVIEW OF #967 (25 Sep 2026): every probe the reviewer ran is a case here ─────────────────────────────
// Evidence: the reviewer's probe scripts cad_attack.ts, cad2.ts, over.ts, title.ts (scratch, not committed). Each case
// sits on an ordinary plan (rooms, a dimension) that must still be drawn, and the party must not be.
type Q = [number, string | number][];
const A = 5.2 / 6;
const tx = (x: number, y: number, s: string, h = 200, layer = 'A-ANNO', rot = 0): Q => [[0, 'TEXT'], [8, layer], [10, x], [20, y], [30, 0], [40, h], [1, s], ...(rot ? [[50, rot]] as Q : [])];
const mtx = (x: number, y: number, s: string): Q => [[0, 'MTEXT'], [8, 'A-ANNO'], [10, x], [20, y], [30, 0], [40, 200], [71, 1], [1, s]];
const PLAN_WORDS = ['OFFICE 101', 'MEETING ROOM 102', 'CORRIDOR', 'MASTER BEDROOM', 'KITCHEN', 'MAJLIS', 'MAID ROOM', 'TOILET 2', '6000', '4500'];
const plan = (): Q => [
  [0, 'LWPOLYLINE'], [8, 'A-WALL'], [90, 4], [70, 1], [10, 0], [20, 0], [10, 20000], [20, 0], [10, 20000], [20, 14000], [10, 0], [20, 14000],
  ...tx(2000, 12000, 'OFFICE 101'), ...tx(6000, 12000, 'MEETING ROOM 102'), ...tx(10000, 12000, 'CORRIDOR'), ...tx(14000, 12000, 'MASTER BEDROOM'),
  ...tx(2000, 10000, 'KITCHEN'), ...tx(6000, 10000, 'MAJLIS'), ...tx(10000, 10000, 'MAID ROOM'), ...tx(14000, 10000, 'TOILET 2'),
  ...tx(3000, 500, '6000'), ...tx(8000, 500, '4500'),
];
const onPlan = (extra: Q, blocks: Q = []) => renderCadForSupplier(dxfFrom([...dxfSection('HEADER', [[9, '$INSUNITS'], [70, 4]]), ...dxfSection('BLOCKS', blocks), ...dxfSection('ENTITIES', [...plan(), ...extra])]), { seeds, longEdge: 1200 });
const symBlock = (name: string): Q => [[0, 'BLOCK'], [8, '0'], [2, name], [70, 2], [10, 0], [20, 0], [0, 'LINE'], [8, '0'], [10, 0], [20, 0], [11, 100], [21, 0], [0, 'ENDBLK'], [8, '0']];

Deno.test('second review: a sheet drawn one glyph per TEXT is HELD, never reassembled or drawn', async () => {
  const perGlyph = (x: number, y: number, s: string, step = 200 * A, rot = 0): Q => [...s].flatMap((c, i) => (c === ' ' ? [] : tx(rot ? x : x + i * step, rot ? y + i * step : y, c, 200, 'A-ANNO', rot)));
  const cases: [string, Q][] = [
    ['the PDF-converted title block', []],
    ['ORBIT stacked vertically', [...'ORBIT'].flatMap((c, i) => tx(16000, 8000 - i * 260, c))],
    ['ORBIT one letter per TEXT, 2.5 heights apart', [...'ORBIT'].flatMap((c, i) => tx(4000 + i * 700, 7000, c))],
    ['ORBIT one letter per TEXT, rotated 90', perGlyph(16000, 3000, 'ORBIT', 180, 90)],
    ['KAREEM stacked vertically', [...'KAREEM'].flatMap((c, i) => tx(17000, 8000 - i * 260, c))],
    ['KAREEM one letter per TEXT, 3 heights apart', [...'KAREEM'].flatMap((c, i) => tx(4000 + i * 600, 7000, c))],
    ['ZZ ORBIT ENGINEERING per glyph', perGlyph(4000, 7000, 'ZZ ORBIT ENGINEERING')],
    ['DM LIC 123456 per glyph', perGlyph(4000, 7000, 'DM LIC 123456')],
    ['info@orbit.ae per glyph', perGlyph(4000, 7000, 'info@orbit.ae')],
  ];
  for (const [name, ents] of cases) {
    const g = name.startsWith('the PDF') ? await renderCadForSupplier(zzGlyphSheetDxf(), { seeds }) : await onPlan(ents);
    assertEquals(g.ok ? `drawn ${JSON.stringify(g.drawn_texts)}` : g.reason, 'glyph_per_text', name);
  }
  // A structural grid's bubbles (A-H, 1-12: 20 single characters on a busy plan) are not a glyph-per-TEXT sheet.
  const grid = [...'ABCDEFGH', ...Array.from({ length: 12 }, (_, i) => String(i + 1))].flatMap((c, i) => tx(500 + i * 900, 13500, c));
  const busy = Array.from({ length: 60 }, (_, i) => tx(500 + (i % 6) * 3000, 9000 - Math.floor(i / 6) * 800, `OFFICE ${100 + i}`));
  const ok = await onPlan([...grid, ...busy.flat()]);
  assert(ok.ok, `a plan with a 20-bubble grid was held: ${!ok.ok && ok.detail}`);
});

Deno.test('second review: short firm names, split and abutting words, phones, e-mails and look-alikes are never drawn', async () => {
  const cases: [string, Q, Q?][] = [
    ['plain ZZ ORBIT', tx(4000, 7000, 'ZZ ORBIT')], ['lower case', tx(4000, 7000, 'zz orbit')],
    ['DAR', tx(4000, 7000, 'DAR')], ['WSP', tx(4000, 7000, 'WSP')], ['ARUP', tx(4000, 7000, 'ARUP')],
    ['ORB|IT abutting', [...tx(4000, 7000, 'ORB'), ...tx(4000 + 3 * 200 * A, 7000, 'IT')]],
    ['ZZ|ORB|IT abutting', [...tx(4000, 7000, 'ZZ '), ...tx(4000 + 3 * 200 * A, 7000, 'ORB'), ...tx(4000 + 6 * 200 * A, 7000, 'IT')]],
    ['DM LIC 123456', tx(4000, 7000, 'DM LIC 123456')],
    ['050 123 4567', tx(4000, 7000, '050 123 4567')], ['(04) 123-4567', tx(4000, 7000, '(04) 123-4567')], ['04.123.4567', tx(4000, 7000, '04.123.4567')],
    ['0 5 0 1 2 3 4 5 6 7', tx(4000, 7000, '0 5 0 1 2 3 4 5 6 7')], ['050 1234 567', tx(4000, 7000, '050 1234 567')],
    ['phone split on one line', [...tx(4000, 7000, '050 123'), ...tx(4000 + 8 * 200, 7000, '4567')]],
    ['phone split over two lines', [...tx(4000, 7000, 'T 050'), ...tx(4000, 6700, '123 4567')]],
    ['e-mail split on one line', [...tx(4000, 7000, 'al@'), ...tx(4000 + 3 * 173, 7000, 'kx.ae')]],
    ['e-mail split over two lines', [...tx(4000, 7000, 'al@'), ...tx(4000, 6700, 'kx.ae')]],
    ['Makani 12345 67890', tx(4000, 7000, '12345 67890')], ['PLOT NO 345-0123', tx(4000, 7000, 'PLOT NO 345-0123')], ['VILLA 12 JUMEIRAH', tx(4000, 7000, 'VILLA 12 JUMEIRAH')],
    ['Arabic with a firm', tx(4000, 7000, 'ORBIT \u0645\u0643\u062a\u0628')],
    ['MTEXT codes', mtx(4000, 7000, '{\\fArial|b1;ZZ}\\PORB{\\C1;IT}\\PKITCHEN')], ['MTEXT unicode escapes', mtx(4000, 7000, '\\U+004F\\U+0052\\U+0042\\U+0049\\U+0054')],
    ['a name beside a room label', [...tx(2000, 8000, 'KITCHEN'), ...tx(2000 + 7 * 180, 8000, 'ALI')]],
    ['KAREM beside a room label', [...tx(2000, 8000, 'KITCHEN'), ...tx(2000 + 8 * 180, 8000, 'KAREM')]],
    ['tiny ORBIT', tx(4000, 7000, 'ORBIT', 5)], ['tiny DAR', tx(4000, 7000, 'DAR', 5)], ['layer 0 ZZ ORBIT', tx(4000, 7000, 'ZZ ORBIT', 200, '0')],
    ['dimension override BY ZZ ORBIT', [[0, 'DIMENSION'], [8, 'A-DIM'], [2, '*DNONE'], [10, 0], [20, 0], [11, 4000], [21, 7000], [1, 'BY ZZ ORBIT']]],
    ['dimension override <> BY DAR', [[0, 'DIMENSION'], [8, 'A-DIM'], [2, '*DNONE'], [10, 0], [20, 0], [11, 4000], [21, 7000], [1, '<> BY DAR']]],
    ['nested block ORBIT + DAR', [[0, 'INSERT'], [8, 'A-ANNO'], [2, 'OUTER'], [10, 4000], [20, 7000]],
      [[0, 'BLOCK'], [8, '0'], [2, 'INNER'], [70, 0], [10, 0], [20, 0], ...tx(0, 0, 'ORBIT'), ...tx(0, 400, 'DAR'), [0, 'ENDBLK'], [8, '0'],
       [0, 'BLOCK'], [8, '0'], [2, 'OUTER'], [70, 0], [10, 0], [20, 0], [0, 'INSERT'], [8, '0'], [2, 'INNER'], [10, 0], [20, 0], [0, 'ENDBLK'], [8, '0']]],
    ['ATTRIB DAR under a neutral tag', [[0, 'INSERT'], [8, 'A-ANNO'], [2, 'SYM'], [10, 4000], [20, 7000], [66, 1], [0, 'ATTRIB'], [8, 'A-ANNO'], [10, 4000], [20, 7000], [40, 200], [1, 'DAR'], [2, 'TAG1'], [70, 0], [0, 'SEQEND']], symBlock('SYM')],
    ['ATTRIB CLIENT_NAME in ISO_A1', [[0, 'INSERT'], [8, 'A-ANNO'], [2, 'ISO_A1'], [10, 4000], [20, 7000], [66, 1], [0, 'ATTRIB'], [8, 'A-ANNO'], [10, 4000], [20, 7000], [40, 200], [1, 'ZZ OMEGA'], [2, 'CLIENT_NAME'], [70, 0], [0, 'SEQEND']], symBlock('ISO_A1')],
    ['ZZ ORBIT ENGINEERING', tx(4000, 7000, 'ZZ ORBIT ENGINEERING')], ['ORBIT HOLDINGS', tx(4000, 7000, 'ORBIT HOLDINGS')],
    ['K A R E E M', tx(4000, 7000, 'K A R E E M')], ['KAREM', tx(4000, 7000, 'KAREM')], ['RASHEED', tx(4000, 7000, 'RASHEED')], ['RASHEED KARIM', tx(4000, 7000, 'RASHEED KARIM')],
    ['accented ORB\u00cdT', tx(4000, 7000, 'ORB\u00cdT')], ['leet 0RB1T', tx(4000, 7000, '0RB1T')], ['OR BI T', tx(4000, 7000, 'OR BI T')],
  ];
  for (const [name, ents, blocks] of cases) {
    const g = await onPlan(ents, blocks ?? []);
    assert(g.ok, `${name}: held (${!g.ok && g.reason}), the plan should still be drawn`);
    if (!g.ok) continue;
    const extra = g.drawn_texts.filter((t) => !PLAN_WORDS.includes(t));
    assertEquals(extra, [], `${name}: drawn`);
    for (const w of PLAN_WORDS) assert(g.drawn_texts.includes(w), `${name}: the plan lost "${w}"`);
  }
});

Deno.test('second review: ordinary room, fixture, MEP and instruction labels are drawn; a title block\'s view title is not a seed', async () => {
  const body = ['OFFICE 101', 'MASTER BEDROOM', 'POWDER ROOM', 'WALK-IN CLOSET', 'ELECTRICAL ROOM', 'LIGHTING', 'LIGHTING SCHEDULE', 'GROUND FLOOR', 'FFL +0.150', 'DB-01', '63A TPN', '12 WAYS', '2x13A', 'L1', 'SKT - DOUBLE SOCKET OUTLET', 'SD - SMOKE DETECTOR', 'LEGEND',
    'ALL SOCKETS AT 300MM AFFL UNLESS OTHERWISE NOTED', 'REFER TO MEP SPECIFICATION', 'CONTRACTOR TO VERIFY ON SITE', 'CABLE SIZE 4C x 16 SQMM XLPE/SWA', 'WATERPROOFING', 'FALSE CEILING', 'EXHAUST FAN 150 CFM', 'FIRE ALARM CONTROL PANEL', 'ACCESS PANEL 600x600', 'KITCHEN HOOD', 'WATER HEATER 80L', 'SPLIT AC 2.5 TR', 'DATA OUTLET CAT6', 'PUSH BUTTON', 'DOOR BELL', 'SHOWER', 'VANITY', 'BATHROOM 2', 'TERRACE', 'LANDSCAPE', 'DRIVEWAY', 'SWIMMING POOL', 'PUMP ROOM', 'SERVANT QUARTER', 'ENTRANCE LOBBY', 'MAIN ENTRANCE', 'NOTES:', '1. ALL DIMENSIONS IN MM', 'DO NOT SCALE', 'TYP.', 'EXISTING WALL TO BE DEMOLISHED', 'NEW BLOCKWORK WALL', 'BALCONY', 'MAID ROOM', 'PANTRY', 'LOBBY'];
  // The sheet's title block (an INSERT of A1_TITLEBLOCK) prints the view title and the discipline beside the firm.
  const blocks: Q = [[0, 'BLOCK'], [8, '0'], [2, 'A1_TITLEBLOCK'], [70, 0], [10, 0], [20, 0], ...tx(0, 0, 'LIGHTING LAYOUT'), ...tx(0, 400, 'GROUND FLOOR'), ...tx(0, 800, 'ELECTRICAL WORKS'), ...tx(0, 1200, 'ZZ ORBIT ENGINEERING'), [0, 'ENDBLK'], [8, '0']];
  const ents: Q = [[0, 'LWPOLYLINE'], [8, 'A-WALL'], [90, 4], [70, 1], [10, 0], [20, 0], [10, 24000], [20, 0], [10, 24000], [20, 16000], [10, 0], [20, 16000],
    ...body.flatMap((s, i) => tx(500 + (i % 3) * 8000, 15000 - Math.floor(i / 3) * 900, s)), [0, 'INSERT'], [8, 'A-ANNO'], [2, 'A1_TITLEBLOCK'], [10, 25000], [20, 0]];
  const g = await renderCadForSupplier(dxfFrom([...dxfSection('BLOCKS', blocks), ...dxfSection('ENTITIES', ents)]), { seeds, longEdge: 1600 });
  assert(g.ok, `held: ${!g.ok && g.reason} ${!g.ok && g.detail}`);
  if (!g.ok) return;
  assertEquals(body.filter((b) => !g.drawn_texts.includes(b)), [], 'ordinary labels were withheld');
  assert(!g.drawn_texts.some((t) => /ORBIT/.test(t)), 'the title block\'s firm was drawn');
  assertEquals(g.withheld.regions, 1, 'the title block is one black region');
});

Deno.test('second review: a sheet border drawn as four LINEs on the title layer is a border, not a reason to hold', async () => {
  const ln = (x1: number, y1: number, x2: number, y2: number): Q => [[0, 'LINE'], [8, 'TITLE'], [10, x1], [20, y1], [11, x2], [21, y2]];
  const sheet = (border: Q) => dxfFrom(dxfSection('ENTITIES', [
    ...border,
    [0, 'LWPOLYLINE'], [8, 'TITLE'], [90, 4], [70, 1], [10, 7000], [20, 0], [10, 10000], [20, 0], [10, 10000], [20, 2000], [10, 7000], [20, 2000],
    [0, 'CIRCLE'], [8, 'TITLE'], [10, 7400], [20, 1600], [40, 250],
    ...tx(7200, 800, 'ZZ ORBIT', 150, 'TITLE'), ...tx(800, 8000, 'KITCHEN'), ...tx(800, 6000, 'OFFICE 101'),
    [0, 'LWPOLYLINE'], [8, 'A-WALL'], [90, 4], [70, 1], [10, 500], [20, 5000], [10, 3500], [20, 5000], [10, 3500], [20, 9000], [10, 500], [20, 9000],
  ]));
  // Four LINEs, and the same rectangle broken into eight loose segments.
  const four = [...ln(0, 0, 10000, 0), ...ln(10000, 0, 10000, 10000), ...ln(10000, 10000, 0, 10000), ...ln(0, 10000, 0, 0)];
  const eight = [...ln(0, 0, 5000, 0), ...ln(5000, 0, 10000, 0), ...ln(10000, 0, 10000, 5000), ...ln(10000, 5000, 10000, 10000), ...ln(10000, 10000, 5000, 10000), ...ln(5000, 10000, 0, 10000), ...ln(0, 10000, 0, 5000), ...ln(0, 5000, 0, 0)];
  for (const [name, border] of [['four LINEs', four], ['eight segments', eight]] as const) {
    const g = await renderCadForSupplier(sheet(border), { seeds, longEdge: 1000 });
    assert(g.ok, `${name}: held ${!g.ok && g.reason} ${!g.ok && g.detail}`);
    if (!g.ok) continue;
    assertEquals(g.drawn_texts, ['KITCHEN', 'OFFICE 101'], name);
    const t = g.regions_px.filter((r) => r.kind === 'title');
    assertEquals(t.length, 1, `${name}: the title block is one black box`);
    assert(t[0].w * t[0].h < 0.2 * g.width * g.height, `${name}: the black box swallowed the sheet (${JSON.stringify(t[0])})`);
    // The border itself is not drawn: no column carries ink over most of the page's height.
    let tall = 0;
    for (let x = 0; x < g.width; x++) { let n = 0; for (let y = 0; y < g.height; y++) if (g.rgba[(y * g.width + x) * 4] === 32) n++; if (n > 0.8 * g.height) tall++; }
    assertEquals(tall, 0, `${name}: the border was drawn`);
  }
  // A cross of LINEs through the middle of that layer is still not a border: held.
  const cross = await renderCadForSupplier(sheet([...four, ...ln(100, 100, 9900, 9900), ...ln(100, 9900, 9900, 100)]), { seeds });
  assertEquals(cross.ok ? 'drawn' : cross.reason, 'title_unbounded');
});

Deno.test('too dense for the budget is HELD, never half-drawn; not a DXF is refused', async () => {
  const g = await renderCadForSupplier(zzDxf(), { seeds, maxSegments: 50 });
  assertEquals(g.ok ? 'drawn' : g.reason, 'too_dense');
  const r = await renderCadForSupplier(new TextEncoder().encode('%PDF-1.4 not a drawing'), { seeds });
  assertEquals(r.ok ? 'drawn' : r.reason, 'unreadable');
});

// ── THIRD REVIEW OF #967 (25 Sep 2026): every probe is a case ───────────────────────────────────────────────────
// Evidence: the reviewer's cad_exploded.ts, cad3.ts and over3.ts (scratch, not committed). A sheet of 60 ordinary
// labels keeps the single-character share low, as the reviewer's did.
const ROOMS = ['OFFICE 101', 'MEETING ROOM 102', 'CORRIDOR', 'MASTER BEDROOM', 'KITCHEN', 'MAJLIS', 'MAID ROOM', 'TOILET 2', 'STORE', 'LOBBY'];
const sheet60 = (): Q => [[0, 'LWPOLYLINE'], [8, 'A-WALL'], [90, 4], [70, 1], [10, 0], [20, 0], [10, 20000], [20, 0], [10, 20000], [20, 14000], [10, 0], [20, 14000],
  ...Array.from({ length: 60 }, (_, i) => tx(1000 + (i % 6) * 3000, 13000 - Math.floor(i / 6) * 700, ROOMS[i % 10])).flat() as Q];
const on60 = (extra: Q, blocks: Q = [], s = seeds) => renderCadForSupplier(dxfFrom([...dxfSection('HEADER', [[9, '$INSUNITS'], [70, 4]]), ...dxfSection('BLOCKS', blocks), ...dxfSection('ENTITIES', [...sheet60(), ...extra])]), { seeds: s, longEdge: 1600 });
const extraDrawn = (g: Awaited<ReturnType<typeof on60>>) => (g.ok ? g.drawn_texts.filter((t) => !ROOMS.includes(t)) : []);

Deno.test('third review: words exploded to linework HOLD the page (vector_text); ordinary linework does not', async () => {
  const g = await renderCadForSupplier(zzExplodedTitleDxf(), { seeds });
  assertEquals(g.ok ? `drawn ${JSON.stringify(g.drawn_texts)}` : g.reason, 'vector_text');
  // Each exploded line alone is enough.
  for (const w of [[15300, 10500, 'CLIENT: ZZ OMEGA', 300, '0'], [15300, 9100, 'TEL 04 123 4567', 300, '0'], [15300, 8400, 'RASHID KAREEM', 300, 'A-ANNO']] as [number, number, string, number, string][]) {
    const one = await renderCadForSupplier(zzExplodedTitleDxf([w]), { seeds });
    assertEquals(one.ok ? 'drawn' : one.reason, 'vector_text', w[2]);
  }
  // A plan of rooms, door swings, a row of identical chairs, device symbols and a dimension is not text.
  const ln = (x1: number, y1: number, x2: number, y2: number): Q => [[0, 'LINE'], [8, 'A-FURN'], [10, x1], [20, y1], [11, x2], [21, y2]];
  const chair = (x: number, y: number): Q => [...ln(x, y, x + 450, y), ...ln(x + 450, y, x + 450, y + 450), ...ln(x + 450, y + 450, x, y + 450), ...ln(x, y + 450, x, y)];
  const door = (x: number, y: number): Q => [[0, 'ARC'], [8, 'A-DOOR'], [10, x], [20, y], [40, 900], [50, 0], [51, 90], ...ln(x, y, x + 900, y)];
  const devices: Q = Array.from({ length: 12 }, (_, i) => [[0, 'INSERT'], [8, 'E-FIRE'], [2, 'SD'], [10, 2000 + i * 1200], [20, 3000]] as Q).flat() as Q;
  const plan = await on60([...Array.from({ length: 8 }, (_, i) => chair(2000 + i * 600, 1000)).flat() as Q, ...door(9000, 5000), ...door(12000, 5000), ...devices],
    [[0, 'BLOCK'], [8, '0'], [2, 'SD'], [70, 0], [10, 0], [20, 0], [0, 'CIRCLE'], [8, '0'], [10, 0], [20, 0], [40, 150], [0, 'ENDBLK'], [8, '0']]);
  assert(plan.ok, `an ordinary plan was held: ${!plan.ok && plan.reason} ${!plan.ok && plan.detail}`);
});

Deno.test('third review: a phone or number split by angle, gap or line is withheld whole; a dimension is not', async () => {
  const H = 200, cw = H * A;
  const cases: [string, Q][] = [
    ['050|123|4567 at 0.9/1.1/0.9 degrees', [...tx(4000, 7000, '050', H, 'A-ANNO', 0.9), ...tx(4000 + 4 * cw, 7000, '123', H, 'A-ANNO', 1.1), ...tx(4000 + 8 * cw, 7000, '4567', H, 'A-ANNO', 0.9)]],
    ['"050 123"|"4567" at 0.9/1.1 degrees', [...tx(4000, 7000, '050 123', H, 'A-ANNO', 0.9), ...tx(4000 + 8 * cw, 7000, '4567', H, 'A-ANNO', 1.1)]],
    ['one digit per TEXT, alternating angle', [...'0501234567'].flatMap((c, i) => tx(4000 + i * cw, 7000, c, H, 'A-ANNO', i % 2 ? 1.1 : 0.9))],
    ['three runs 3.1 heights apart', [...tx(4000, 7000, '050'), ...tx(4000 + 3 * cw + 3.1 * H, 7000, '123'), ...tx(4000 + 6 * cw + 6.2 * H, 7000, '4567')]],
    ['stacked "050 123" / "4567" at 2.5 heights', [...tx(4000, 7000, '050 123'), ...tx(4000, 7000 - 2.5 * H, '4567')]],
    ['stacked "050" / "123" / "4567" at 1.7 heights', [...tx(4000, 7000, '050'), ...tx(4000, 7000 - 1.7 * H, '123'), ...tx(4000, 7000 - 3.4 * H, '4567')]],
    ['bare 345-0123, 123456, "12345 678"', [...tx(4000, 7000, '345-0123'), ...tx(4000, 5000, '123456'), ...tx(4000, 3000, '12345 678')]],
    ['the customer\'s own phone split by angle', [...tx(4000, 7000, '050 000', H, 'A-ANNO', 0.9), ...tx(4000 + 8 * cw, 7000, '0017', H, 'A-ANNO', 1.1)]],
  ];
  for (const [name, ents] of cases) {
    const g = await on60(ents);
    assert(g.ok, `${name}: held ${!g.ok && g.reason}`);
    assertEquals(extraDrawn(g), [], name);
  }
  // A dimension's own text of 6 digits (1504,68 in LibreDWG's example_2018.dxf) is a measurement and is drawn.
  const dim = await on60([[0, 'DIMENSION'], [8, 'A-DIM'], [10, 0], [20, 0], [11, 4000], [21, 7000], [1, '1504,68']]);
  assert(dim.ok && dim.drawn_texts.includes('1504,68'), 'a dimension of 6 digits was withheld');
});

Deno.test('third review: a two-letter code alone, even at logo size, is withheld; beside a device, in a legend row or a bubble it is drawn', async () => {
  for (const s of ['DP', 'EL', 'DB', 'SS', 'MS', 'HD', 'AL', 'MZ', 'TP', 'SP', 'GL', 'SK', 'AL BAR']) {
    for (const h of [200, 600]) assertEquals(extraDrawn(await on60(tx(4000, 7000, s, h))), [], `"${s}" at ${h} was drawn alone`);
  }
  const block: Q = [[0, 'BLOCK'], [8, '0'], [2, 'SKT'], [70, 0], [10, 0], [20, 0], [0, 'CIRCLE'], [8, '0'], [10, 0], [20, 0], [40, 100], [0, 'ENDBLK'], [8, '0']];
  const beside = await on60([[0, 'INSERT'], [8, 'E-POWR'], [2, 'SKT'], [10, 4000], [20, 7000], ...tx(4200, 6900, 'DB')], block);
  assertEquals(extraDrawn(beside), ['DB'], 'a code beside its device symbol was withheld');
  const legend = await on60([...tx(4000, 7000, 'SD'), ...tx(4000 + 3 * 200 * A, 7000, '- SMOKE DETECTOR')]);
  assertEquals(extraDrawn(legend), ['SD', '- SMOKE DETECTOR'], 'a legend row lost its code');
  const bubble = await on60([[0, 'CIRCLE'], [8, 'S-GRID'], [10, 4100], [20, 7100], [40, 300], ...tx(4000, 7000, 'GL')]);
  assertEquals(extraDrawn(bubble), ['GL'], 'a code inside its bubble was withheld');
  // At logo size, even beside a device, it is not a device label.
  assertEquals(extraDrawn(await on60([[0, 'INSERT'], [8, 'E-POWR'], [2, 'SKT'], [10, 4000], [20, 7000], ...tx(4200, 6900, 'DB', 600)], block)), [], 'a logo-size code beside a device was drawn');
});

Deno.test('third review: a phrase at more than twice the usual text height is withheld unless it is a room or a view title', async () => {
  const names = ['NORTH GATE', 'FIRST POINT', 'EAST GATE', 'GULF LIGHTING', 'AL NOOR ELECTRICAL', 'MASTER POWER', 'ACCESS POINT', 'SITE WORKS', 'THE GARDEN', 'OPEN PLAN', 'CORE', 'SMART', 'POWER LINE', 'NORTH STAR', 'GREEN', 'BLUE WATER', 'STEEL LINE', 'MAIN STREET', 'NORTH POINT ELECTRICAL WORKS', 'FIRE AND SAFETY', 'CLEAR WATER'];
  for (const n of names) assertEquals(extraDrawn(await on60(tx(4000, 7000, n, 800))), [], `"${n}" at logo size was drawn`);
  for (const t of ['MASTER BEDROOM 1', 'GROUND FLOOR PLAN', 'SECTION A-A', 'LIGHTING LAYOUT', 'LEGEND']) assertEquals(extraDrawn(await on60(tx(4000, 7000, t, 800))), [t], `"${t}" at title size was withheld`);
});

Deno.test('third review: an unknown large word withholds itself only, not every label within 3 of its heights', async () => {
  const g = await on60([...tx(4000, 7200, 'ZQXV', 900), ...tx(4000 + 4 * 900, 7200, 'KITCHEN'), ...tx(4000, 6300, 'PANTRY')]);
  assert(g.ok);
  if (g.ok) assertEquals(extraDrawn(g), ['PANTRY'], 'the labels beside a large unknown word were withheld with it');
  if (g.ok) assert(g.drawn_texts.filter((t) => t === 'KITCHEN').length === 7, 'the KITCHEN beside the large word was withheld');
});

Deno.test('third review: grid bubbles and switching letters beside light fittings are drawn and do not hold the sheet', async () => {
  const lum: Q = [[0, 'BLOCK'], [8, '0'], [2, 'LUM'], [70, 0], [10, 0], [20, 0], [0, 'CIRCLE'], [8, '0'], [10, 0], [20, 0], [40, 120], [0, 'ENDBLK'], [8, '0']];
  const fittings: Q = Array.from({ length: 48 }, (_, i) => { const x = 1000 + (i % 12) * 1500, y = 5000 - Math.floor(i / 12) * 1100; return [[0, 'INSERT'], [8, 'E-LITE'], [2, 'LUM'], [10, x], [20, y], ...tx(x + 200, y + 150, 'abc'[i % 3], 150)] as Q; }).flat() as Q;
  const bubbles: Q = [...'ABCDEF'].flatMap((c, i) => [[0, 'CIRCLE'], [8, 'S-GRID'], [10, 1100 + i * 3000], [20, 13900], [40, 250], ...tx(1000 + i * 3000, 13800, c, 200)] as Q);
  const nums: Q = [...'123456'].flatMap((c, i) => [[0, 'CIRCLE'], [8, 'S-GRID'], [10, 19700], [20, 1100 + i * 2000], [40, 250], ...tx(19600, 1000 + i * 2000, c, 200)] as Q);
  const g = await on60([...fittings, ...bubbles, ...nums], lum);
  assert(g.ok, `held: ${!g.ok && g.reason} ${!g.ok && g.detail}`);
  if (!g.ok) return;
  for (const c of [...'ABCDEF123456']) assert(g.drawn_texts.includes(c), `grid ${c} was withheld`);
  assertEquals(['a', 'b', 'c'].map((c) => g.drawn_texts.filter((t) => t === c).length), [16, 16, 16], 'switching letters were withheld');
  // Without the fittings, 48 lone lower-case letters are exactly the glyph-per-TEXT shape: held.
  const bare = await on60(Array.from({ length: 48 }, (_, i) => tx(1000 + (i % 12) * 1500, 5000 - Math.floor(i / 12) * 1100, 'abc'[i % 3], 150)).flat() as Q);
  assertEquals(bare.ok ? 'drawn' : bare.reason, 'glyph_per_text');
});
