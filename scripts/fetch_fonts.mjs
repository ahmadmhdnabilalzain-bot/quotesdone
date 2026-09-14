// Vendor the four font families into public/fonts so the build never fetches them.
//
// WHY THIS EXISTS. src/app/[locale]/layout.tsx imported four families from `next/font/google`, and
// Next fetches every one from Google AT BUILD TIME. Any single failed fetch emits a CSS module
// referencing font files that do not exist and the build dies - which is exactly what happened on
// Vercel between 21:01 and 21:16 UTC on 11 Aug 2026, on `space_grotesk` for one build and
// `plus_jakarta_sans` for another. Different fonts on different builds, on an unchanged src/ tree:
// four network calls per build is the flake, not one bad font.
//
// Run it again only to refresh the files (a Google font version bump). It is NOT part of the build
// and must never become part of it - the whole point is that the build makes no network call.
//
//   node scripts/fetch_fonts.mjs
//
// The URLs are read out of Google's own CSS rather than hardcoded, so what lands on disk is byte
// for byte what the browser was being served, at the same unicode ranges the `subsets:` options
// asked for. Nothing is re-encoded or subsetted here.
import { mkdir, writeFile } from 'node:fs/promises';

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';
const OUT = 'public/fonts';

// Which unicode-range block to keep, identified by a signature that appears only in that block.
const LATIN  = 'U+0000-00FF';
const ARABIC = 'U+0600-06FF';

// Brand direction A "Sealed" (14 Sep 2026): Geist (Latin display + text), Geist Mono (figures, IDs),
// Readex Pro (Arabic). All SIL OFL 1.1, all VARIABLE, so one file per family per script replaces
// the 11 Jakarta/Space Grotesk/JetBrains/Tajawal files. Readex Pro ships two unicode-range files;
// the Latin half carries the digits in "AED 12,400" on Arabic pages, so both are kept.
const FAMILIES = [
  { css: 'https://fonts.googleapis.com/css2?family=Geist:wght@100..900&display=swap',       want: [[LATIN, 'geist-latin.woff2']] },
  { css: 'https://fonts.googleapis.com/css2?family=Geist+Mono:wght@100..900&display=swap',  want: [[LATIN, 'geist-mono-latin.woff2']] },
  { css: 'https://fonts.googleapis.com/css2?family=Readex+Pro:wght@160..700&display=swap',  want: [[ARABIC, 'readex-pro-arabic.woff2'], [LATIN, 'readex-pro-latin.woff2']] },
];

/** Every @font-face block in the sheet, as { url, ranges }. */
function faces(css) {
  return css.split('@font-face').slice(1).map((block) => ({
    url: (block.match(/url\((https:\/\/[^)]+\.woff2)\)/) || [])[1],
    ranges: (block.match(/unicode-range:\s*([^;]+);/) || [])[1] || '',
  })).filter((f) => f.url);
}

await mkdir(OUT, { recursive: true });
let written = 0;
for (const fam of FAMILIES) {
  const css = await fetch(fam.css, { headers: { 'User-Agent': UA } }).then((r) => r.text());
  const all = faces(css);
  for (const [signature, name] of fam.want) {
    const hit = all.find((f) => f.ranges.includes(signature));
    // Loud, not silent. A missing block means Google changed the sheet and the page would render in
    // a fallback face with nothing saying so - the exact failure shape this whole change is about.
    if (!hit) throw new Error(`no @font-face carrying ${signature} in ${fam.css} - cannot write ${name}`);
    const buf = Buffer.from(await fetch(hit.url, { headers: { 'User-Agent': UA } }).then((r) => r.arrayBuffer()));
    if (buf.length < 1000) throw new Error(`${name} came back as ${buf.length} bytes from ${hit.url}`);
    await writeFile(`${OUT}/${name}`, buf);
    console.log(`${name.padEnd(30)} ${String(buf.length).padStart(7)} bytes  <- ${hit.url}`);
    written++;
  }
}
console.log(`\nwrote ${written} file(s) to ${OUT}`);
