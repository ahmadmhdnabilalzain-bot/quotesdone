// WCAG AA check over every Sealed text/ground pair (src/lib/brandTokens.ts, mirrored from globals.css).
// Exits 1 on the first pair below its minimum, so it can gate a change to the palette.
//   node scripts/brand_contrast.mjs        (Node >= 22.6 strips the TypeScript types natively)
import { PAIRS, contrast } from '../src/lib/brandTokens.ts';

let fail = 0;
for (const p of PAIRS) {
  const r = contrast(p.fg, p.bg);
  const ok = r >= p.min;
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${r.toFixed(2).padStart(5)}:1  (min ${p.min})  ${p.fg} on ${p.bg}  ${p.use}`);
}
console.log(`\n${PAIRS.length - fail}/${PAIRS.length} pairs meet WCAG AA`);
process.exit(fail ? 1 : 0);
