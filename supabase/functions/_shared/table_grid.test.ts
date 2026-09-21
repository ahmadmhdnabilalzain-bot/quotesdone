// table_grid on synthetic pages: a ruled schedule must be found with its merged header and its
// empty cells; a floor plan (double walls, a full-width corridor, rooms with labels) must not be.
import { assertEquals, assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { detectTables, isEmptyCell, type GrayImage } from './table_grid.ts';

const page = (w: number, h: number): GrayImage => ({ data: new Uint8Array(w * h).fill(255), w, h });
const fill = (g: GrayImage, x: number, y: number, w: number, h: number) => {
  for (let j = y; j < y + h; j++) for (let i = x; i < x + w; i++) g.data[j * g.w + i] = 0;
};
const hline = (g: GrayImage, x0: number, x1: number, y: number) => fill(g, x0, y, x1 - x0 + 1, 2);
const vline = (g: GrayImage, x: number, y0: number, y1: number) => fill(g, x, y0, 2, y1 - y0 + 1);
// "text": three 3x12 strokes, like a short word
const word = (g: GrayImage, x: number, y: number) => { for (let k = 0; k < 3; k++) fill(g, x + k * 6, y, 3, 12); };

// A 3000x2000 page: the schedule at (200,200), 6 columns x 200 px, a title row, a header row whose
// first cell spans columns 0-2, then 6 data rows of 30 px; row 5 column 4 left empty.
function schedule(g: GrayImage) {
  const X = [200, 400, 600, 800, 1000, 1200, 1400];
  const Y = [200, 240, 270, 300, 330, 360, 390, 420, 450];
  for (const y of Y) hline(g, X[0], X[6], y);
  vline(g, X[0], Y[0], Y[8]); vline(g, X[6], Y[0], Y[8]);
  for (let c = 1; c < 6; c++) vline(g, X[c], c <= 2 ? Y[2] : Y[1], Y[8]); // title row unsplit; header cols 0-2 merged
  word(g, 700, 215); // title
  for (let r = 1; r < 8; r++) for (let c = 0; c < 6; c++) {
    if (r === 1 && (c === 1 || c === 2)) continue; // covered by the merged header cell
    if (r === 5 && c === 4) continue;              // the empty cell
    word(g, X[c] + 20, Y[r] + 9);
  }
}

// A floor plan at (1600,300): double outer walls (10 px apart), a corridor bounded by two full-width
// double walls, partition walls between rooms, a label in every room.
function plan(g: GrayImage) {
  const x0 = 1600, x1 = 2800, y0 = 300, y1 = 1500;
  for (const d of [0, 10]) {
    hline(g, x0 + d, x1 - d, y0 + d); hline(g, x0 + d, x1 - d, y1 - d);
    vline(g, x0 + d, y0 + d, y1 - d); vline(g, x1 - d, y0 + d, y1 - d);
  }
  for (const y of [700, 710, 860, 870]) hline(g, x0 + 10, x1 - 10, y); // corridor walls, full width
  for (const x of [2000, 2010, 2400, 2410]) { vline(g, x, y0 + 10, 700); vline(g, x, 870, y1 - 10); }
  for (const [x, y] of [[1750, 500], [2150, 500], [2550, 500], [1750, 1150], [2150, 1150], [2550, 1150], [2200, 780]]) word(g, x, y);
}

Deno.test('a ruled schedule is found, with its merged header and its empty cell', () => {
  const g = page(3000, 2000);
  schedule(g); plan(g);
  const t = detectTables(g);
  assertEquals(t.length, 1, 'exactly the schedule; the floor plan is refused');
  const [s] = t;
  assert(Math.abs(s.bbox.x - 200) <= 2 && Math.abs(s.bbox.y - 200) <= 2 && Math.abs(s.bbox.w - 1200) <= 3 && Math.abs(s.bbox.h - 250) <= 3);
  assertEquals(s.rowsY.length - 1, 8);
  assertEquals(s.colsX.length - 1, 6);
  const title = s.cells.find((c) => c.r === 0 && c.c === 0)!;
  assertEquals([title.rs, title.cs], [1, 6]);
  const head = s.cells.find((c) => c.r === 1 && c.c === 0)!;
  assertEquals([head.rs, head.cs], [1, 3]);
  assertEquals(s.cells.length, 1 + 4 + 6 * 6);
  const empty = s.cells.filter((c) => isEmptyCell(g, c, 4));
  assertEquals(empty.map((c) => [c.r, c.c]), [[5, 4]]);
});

Deno.test('a floor plan alone is not a table', () => {
  const g = page(3000, 2000);
  plan(g);
  assertEquals(detectTables(g).length, 0);
});
