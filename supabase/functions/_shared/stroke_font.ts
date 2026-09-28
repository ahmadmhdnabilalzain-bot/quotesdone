// stroke_font — a single-stroke vector font for drawing CAD text onto a raster, with no font file
// (24 Sep 2026, sales_engineer).
//
// WHY. cad_render.ts draws a customer's DXF / DWG as the page a supplier sees. CAD text is itself drawn
// with stroke fonts (AutoCAD's txt.shx / simplex.shx), and the one raster library the edge already runs
// (imagescript) needs a TrueType file to draw text: a font fetched at run time is one more thing that can
// be unreachable, and a font that is not there must not decide whether a room name reaches a supplier.
// So the glyphs are here, as strokes on a 4 x 6 grid (baseline y = 0, cap height y = 6), in the same
// spirit as the SHX fonts the drawing was written with.
//
// WHAT IT COVERS. Printable ASCII, lower case drawn as small capitals (0.75 of the cap height), and the
// CAD symbols %%c / %%d / %%p resolve to (Ø ° ±). Anything else - Arabic among it - is drawn as an empty
// box, one per character, and COUNTED: cad_render reports the count so the page says what it could not
// letter, rather than dropping it silently.
//
// Coordinates: strokes separated by '|', points by spaces, "x,y" in grid units.
const G: Record<string, string> = {
  A: '0,0 2,6 4,0|1,3 3,3', B: '0,0 0,6 3,6 4,5 4,4 3,3 0,3|3,3 4,2 4,1 3,0 0,0', C: '4,5 3,6 1,6 0,5 0,1 1,0 3,0 4,1',
  D: '0,0 0,6 3,6 4,5 4,1 3,0 0,0', E: '4,0 0,0 0,6 4,6|0,3 3,3', F: '0,0 0,6 4,6|0,3 3,3',
  G: '4,5 3,6 1,6 0,5 0,1 1,0 3,0 4,1 4,3 2,3', H: '0,0 0,6|4,0 4,6|0,3 4,3', I: '1,0 3,0|2,0 2,6|1,6 3,6',
  J: '0,1 1,0 3,0 4,1 4,6', K: '0,0 0,6|4,6 0,2|1,3 4,0', L: '0,6 0,0 4,0', M: '0,0 0,6 2,3 4,6 4,0',
  N: '0,0 0,6 4,0 4,6', O: '1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0', P: '0,0 0,6 3,6 4,5 4,4 3,3 0,3',
  Q: '1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0|2,2 4,0', R: '0,0 0,6 3,6 4,5 4,4 3,3 0,3|2,3 4,0',
  S: '4,5 3,6 1,6 0,5 0,4 1,3 3,3 4,2 4,1 3,0 1,0 0,1', T: '0,6 4,6|2,6 2,0', U: '0,6 0,1 1,0 3,0 4,1 4,6',
  V: '0,6 2,0 4,6', W: '0,6 1,0 2,3 3,0 4,6', X: '0,0 4,6|0,6 4,0', Y: '0,6 2,3 4,6|2,3 2,0', Z: '0,6 4,6 0,0 4,0',
  '0': '1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0|0,1 4,5', '1': '1,5 2,6 2,0|1,0 3,0', '2': '0,5 1,6 3,6 4,5 4,4 0,0 4,0',
  '3': '0,5 1,6 3,6 4,5 4,4 3,3 1,3|3,3 4,2 4,1 3,0 1,0 0,1', '4': '3,0 3,6 0,2 4,2',
  '5': '4,6 0,6 0,3 3,3 4,2 4,1 3,0 1,0 0,1', '6': '4,5 3,6 1,6 0,5 0,1 1,0 3,0 4,1 4,2 3,3 0,3', '7': '0,6 4,6 1,0',
  '8': '1,3 0,4 0,5 1,6 3,6 4,5 4,4 3,3 1,3 0,2 0,1 1,0 3,0 4,1 4,2 3,3', '9': '0,1 1,0 3,0 4,1 4,5 3,6 1,6 0,5 0,4 1,3 4,3',
  '.': '2,0 2,0.5', ',': '2,0.5 2,0 1.4,-1', ':': '2,1 2,1.5|2,4 2,4.5', ';': '2,4 2,4.5|2,1 2,0.4 1.4,-0.6',
  '-': '1,3 3,3', _: '0,-0.6 4,-0.6', '+': '0,3 4,3|2,1 2,5', '=': '0,2 4,2|0,4 4,4', '/': '0,0 4,6', '\\': '0,6 4,0',
  '(': '3,6 2,5 1.5,3 2,1 3,0', ')': '1,6 2,5 2.5,3 2,1 1,0', '[': '3,6 1,6 1,0 3,0', ']': '1,6 3,6 3,0 1,0',
  "'": '2,6 2,4.5', '"': '1.3,6 1.3,4.5|2.7,6 2.7,4.5', '#': '1,0 1.6,6|2.6,0 3.2,6|0,2 4,2|0,4 4,4',
  '%': '0,0 4,6|0,6 1,6 1,5 0,5 0,6|3,1 4,1 4,0 3,0 3,1', '&': '4,0 1,4 1,5 2,6 3,5 3,4 0,2 0,1 1,0 2,0 4,2',
  '*': '2,1 2,5|0.5,2 3.5,4|0.5,4 3.5,2', '@': '3,2 3,4 1,4 1,2 3,2 4,3 4,5 3,6 1,6 0,5 0,1 1,0 4,0',
  '!': '2,6 2,2|2,0 2,0.5', '?': '0,5 1,6 3,6 4,5 4,4 2,3 2,2|2,0 2,0.5', '<': '4,6 0,3 4,0', '>': '0,6 4,3 0,0',
  '|': '2,-1 2,7', '~': '0,3 1,4 3,2 4,3', '^': '1,4 2,6 3,4', '`': '1.5,6 2.5,5',
  $: '4,5 3,6 1,6 0,5 0,4 1,3 3,3 4,2 4,1 3,0 1,0 0,1|2,7 2,-1', '{': '3,6 2,5 2,4 1,3 2,2 2,1 3,0',
  '}': '1,6 2,5 2,4 3,3 2,2 2,1 1,0', '°': '1.5,6 2.5,6 2.5,5 1.5,5 1.5,6',
  'Ø': '1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0|0,0 4,6', '±': '0,4 4,4|2,2 2,6|0,0.5 4,0.5', '×': '0.5,1 3.5,5|0.5,5 3.5,1',
  '²': '1,6 3,6 3,5 1,4 3,4', '³': '1,6 3,6 2,5 3,4.5 1,4',
};
const TOFU = '0.5,0 3.5,0 3.5,6 0.5,6 0.5,0';

type Stroke = [number, number][];
const parse = (s: string): Stroke[] => s.split('|').map((st) => st.trim().split(/\s+/).map((p) => p.split(',').map(Number) as [number, number]));
const CACHE = new Map<string, Stroke[]>();
function glyph(ch: string): { strokes: Stroke[]; known: boolean; small: boolean } {
  if (ch === ' ') return { strokes: [], known: true, small: false };
  const up = ch.toUpperCase();
  const small = ch !== up && G[up] !== undefined;
  const key = G[ch] !== undefined ? ch : small ? up : null;
  const src = key ? G[key] : TOFU;
  const k = key ?? '\u0000';
  if (!CACHE.has(k)) CACHE.set(k, parse(src));
  return { strokes: CACHE.get(k)!, known: key !== null, small };
}

/** Advance per character, in cap heights: 4 grid units of glyph + 1.2 of spacing, over a 6-unit cap. */
export const ADVANCE = 5.2 / 6;

/** CAD symbol codes as the glyphs they mean. */
export const cadSymbols = (s: string) => s.replace(/%%[cC]/g, 'Ø').replace(/%%[dD]/g, '°').replace(/%%[pP]/g, '±').replace(/%%%/g, '%').replace(/%%[uUoO]/g, '');

/**
 * The strokes of one line of text, in text space: origin at the left end of the baseline, x along the
 * line, one unit = the cap height. `unknown` counts characters drawn as a box.
 */
export function textStrokes(text: string, widthFactor = 1): { strokes: Stroke[]; width: number; unknown: number } {
  const out: Stroke[] = [];
  let x = 0, unknown = 0;
  const u = 1 / 6;
  for (const ch of cadSymbols(text)) {
    const g = glyph(ch);
    if (!g.known) unknown++;
    const k = g.small ? 0.75 : 1;
    for (const st of g.strokes) out.push(st.map(([gx, gy]) => [(x + gx * u * k * widthFactor), gy * u * k] as [number, number]));
    x += ADVANCE * widthFactor * (g.small ? 0.85 : 1);
  }
  return { strokes: out, width: Math.max(0, x - (1.2 / 6) * widthFactor), unknown };
}
