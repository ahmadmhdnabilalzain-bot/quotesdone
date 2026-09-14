// arabic_shape.ts — Arabic letters to their joined (presentation) forms, with no font engine.
//
// WHY (14 Sep 2026, agent: ceo). fontkit as served by esm.sh (@pdf-lib/fontkit@1.1.1) throws
// "this.shaper.plan is not a function" the moment it lays out Arabic script. pdf-lib calls that
// layout for every drawText and every width, the renderer's per-draw catch swallowed the throw, and
// so every Arabic run on every QuotesDone PDF was silently left off the page — headings, labels,
// the customer's own Arabic request — while the response said fonts.arabic:true, glyphs_dropped:0.
// Found by rendering the first Arabic sample and looking at it: Chrome's viewer and pdf.js both
// showed the Latin and nothing else, and text extraction held no Arabic at all.
//
// The renderer now does the shaping itself and asks the font only for a glyph per code point. This
// module is the shaping: each letter becomes its isolated, final, initial or medial form from the
// Arabic Presentation Forms-B block (plus the Persian letters from Forms-A), and lam + alef becomes
// the single ligature every Arabic reader expects. The brand face (IBM Plex Sans Arabic) maps all
// 125 code points U+FE80..U+FEFC — measured, not assumed.
//
// Harakat (short-vowel marks, shadda, tanween) are dropped: placing a mark over its letter needs
// GPOS, which this path does not have, and unplaced marks collide with the next letter. Business
// Arabic is written without them; "مقدّمة" reads as "مقدمة".
//
// Output is in LOGICAL order. The caller reverses a right-to-left run into visual order.

// [isolated, final, initial, medial]; right-joining letters have only the first two.
const FORMS: Record<number, number[]> = {
  0x0621: [0xFE80],
  0x0622: [0xFE81, 0xFE82], 0x0623: [0xFE83, 0xFE84], 0x0624: [0xFE85, 0xFE86], 0x0625: [0xFE87, 0xFE88],
  0x0626: [0xFE89, 0xFE8A, 0xFE8B, 0xFE8C], 0x0627: [0xFE8D, 0xFE8E], 0x0628: [0xFE8F, 0xFE90, 0xFE91, 0xFE92],
  0x0629: [0xFE93, 0xFE94], 0x062A: [0xFE95, 0xFE96, 0xFE97, 0xFE98], 0x062B: [0xFE99, 0xFE9A, 0xFE9B, 0xFE9C],
  0x062C: [0xFE9D, 0xFE9E, 0xFE9F, 0xFEA0], 0x062D: [0xFEA1, 0xFEA2, 0xFEA3, 0xFEA4], 0x062E: [0xFEA5, 0xFEA6, 0xFEA7, 0xFEA8],
  0x062F: [0xFEA9, 0xFEAA], 0x0630: [0xFEAB, 0xFEAC], 0x0631: [0xFEAD, 0xFEAE], 0x0632: [0xFEAF, 0xFEB0],
  0x0633: [0xFEB1, 0xFEB2, 0xFEB3, 0xFEB4], 0x0634: [0xFEB5, 0xFEB6, 0xFEB7, 0xFEB8], 0x0635: [0xFEB9, 0xFEBA, 0xFEBB, 0xFEBC],
  0x0636: [0xFEBD, 0xFEBE, 0xFEBF, 0xFEC0], 0x0637: [0xFEC1, 0xFEC2, 0xFEC3, 0xFEC4], 0x0638: [0xFEC5, 0xFEC6, 0xFEC7, 0xFEC8],
  0x0639: [0xFEC9, 0xFECA, 0xFECB, 0xFECC], 0x063A: [0xFECD, 0xFECE, 0xFECF, 0xFED0], 0x0641: [0xFED1, 0xFED2, 0xFED3, 0xFED4],
  0x0642: [0xFED5, 0xFED6, 0xFED7, 0xFED8], 0x0643: [0xFED9, 0xFEDA, 0xFEDB, 0xFEDC], 0x0644: [0xFEDD, 0xFEDE, 0xFEDF, 0xFEE0],
  0x0645: [0xFEE1, 0xFEE2, 0xFEE3, 0xFEE4], 0x0646: [0xFEE5, 0xFEE6, 0xFEE7, 0xFEE8], 0x0647: [0xFEE9, 0xFEEA, 0xFEEB, 0xFEEC],
  0x0648: [0xFEED, 0xFEEE], 0x0649: [0xFEEF, 0xFEF0], 0x064A: [0xFEF1, 0xFEF2, 0xFEF3, 0xFEF4],
  // Persian / Urdu letters UAE text meets in names and brands.
  0x067E: [0xFB56, 0xFB57, 0xFB58, 0xFB59], 0x0686: [0xFB7A, 0xFB7B, 0xFB7C, 0xFB7D], 0x0698: [0xFB8A, 0xFB8B],
  0x06A9: [0xFB8E, 0xFB8F, 0xFB90, 0xFB91], 0x06AF: [0xFB92, 0xFB93, 0xFB94, 0xFB95], 0x06CC: [0xFBFC, 0xFBFD, 0xFBFE, 0xFBFF],
};
const TATWEEL = 0x0640;
// lam + (alef with madda / hamza above / hamza below / plain alef) → [isolated, final]
const LAM_ALEF: Record<number, [number, number]> = { 0x0622: [0xFEF5, 0xFEF6], 0x0623: [0xFEF7, 0xFEF8], 0x0625: [0xFEF9, 0xFEFA], 0x0627: [0xFEFB, 0xFEFC] };
const isMark = (cp: number) => (cp >= 0x064B && cp <= 0x065F) || cp === 0x0670 || (cp >= 0x06D6 && cp <= 0x06ED);
/** Joins to the letter AFTER it: dual-joining letters and the tatweel. */
const joinsNext = (cp: number | undefined) => cp !== undefined && (cp === TATWEEL || (FORMS[cp]?.length === 4));
/** Can be joined FROM the letter before it. */
const joinable = (cp: number | undefined) => cp !== undefined && (cp === TATWEEL || (FORMS[cp] !== undefined && FORMS[cp].length >= 2));

export function shapeArabic(text: string): string {
  const cps = [...String(text ?? '')].map((c) => c.codePointAt(0) as number).filter((cp) => !isMark(cp));
  const out: number[] = [];
  for (let i = 0; i < cps.length; i++) {
    const cp = cps[i], prev = cps[i - 1], next = cps[i + 1];
    const fromPrev = joinsNext(prev);
    if (cp === 0x0644 && next !== undefined && LAM_ALEF[next]) {
      out.push(LAM_ALEF[next][fromPrev ? 1 : 0]); i++; continue;
    }
    const f = FORMS[cp];
    if (!f) { out.push(cp); continue; }
    const toNext = f.length === 4 && joinable(next);
    const canFromPrev = fromPrev && f.length >= 2;
    out.push(canFromPrev && toNext ? f[3] : canFromPrev ? f[1] : toNext ? f[2] : f[0]);
  }
  return String.fromCodePoint(...out);
}
