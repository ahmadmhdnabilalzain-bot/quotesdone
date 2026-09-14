// scripts/e2e/warm_cdn.mjs — request every /_next/static asset the portal and home pages reference,
// once to fill Vercel's edge cache and once more to read x-vercel-cache, so the first real customer
// after a deploy does not pay the cold cost.
//
// Measured 14 Sep 2026: after a production deploy /[locale]/me is prerendered, but 16 of its 26 JS
// chunks were a CDN MISS on first request (0.45-1.33 s each); the page took ~1.2 s cold, ~0.7 s warm.
//
// Measured 15 Sep 2026 from Dubai (edge bom1): a chunk requested on quotesdone.com (MISS) was a HIT
// on its very next request through quotesdone.ae, so both domains share one cache per deployment. The
// default is quotesdone.ae because UAE visitors are served there (TDRA, src/lib/domains.ts). The en
// locale has no prefix: /en/me answers 307 -> /me, so the pages below are the unprefixed ones.
// NOT MEASURED: whether a warm-up from a GitHub runner (US) also warms the UAE edge (bom1). If Vercel's
// edge cache is regional, this warms the runner's region only.
// First run, 15 Sep 2026 from Dubai: 19 assets referenced by the four pages; first pass 18 MISS / 1 HIT,
// second pass 19 HIT. Chunks the browser loads later at runtime are not in the HTML and are not warmed.
//
// Exit 1 only when a page or asset answers non-200 (a broken deploy). A MISS on the second pass is
// logged, never fatal. Counts go to $GITHUB_STEP_SUMMARY when set.
//
// Usage: [QD_WARM_SITE=https://quotesdone.ae] node scripts/e2e/warm_cdn.mjs
import { appendFileSync } from 'node:fs';

const SITE = (process.env.QD_WARM_SITE || 'https://quotesdone.ae').replace(/\/$/, '');
const PAGES = ['/me', '/ar/me', '/', '/ar'];
const TIMEOUT_MS = 20_000;
const CONCURRENCY = 8;

async function get(path) {
  const res = await fetch(SITE + path, { signal: AbortSignal.timeout(TIMEOUT_MS), headers: { 'user-agent': 'quotesdone-it-engineer-warmup' } });
  const body = await res.arrayBuffer(); // read to the end so the edge stores the whole object
  return { path, status: res.status, cache: res.headers.get('x-vercel-cache') || 'none', body };
}

async function pool(items, fn) {
  const out = [];
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, items.length) }, async () => {
    while (i < items.length) { const item = items[i++]; out.push(await fn(item).catch((e) => ({ path: item, status: `error ${e.name}`, cache: 'none' }))); }
  }));
  return out;
}

const tally = (rs) => rs.reduce((t, r) => ((t[r.cache] = (t[r.cache] || 0) + 1), t), {});

const pages = await pool(PAGES, get);
const assets = new Set();
for (const p of pages) {
  if (p.status !== 200) continue;
  // RSC payloads inside the HTML escape their quotes, so stop at a quote or a backslash.
  for (const m of new TextDecoder().decode(p.body).matchAll(/\/_next\/static\/[^"'\\\s)<>]+/g)) assets.add(m[0]);
}
const list = [...assets].sort();
const first = await pool(list, get);
const second = await pool(list, get);

const broken = [...pages, ...first, ...second].filter((r) => r.status !== 200);
const cold = second.filter((r) => r.cache !== 'HIT');
const lines = [
  `### CDN warm-up: ${SITE}`,
  `pages: ${pages.map((p) => `${p.path} ${p.status}`).join(', ')}`,
  `assets: ${list.length}`,
  `first pass x-vercel-cache: ${JSON.stringify(tally(first))}`,
  `second pass x-vercel-cache: ${JSON.stringify(tally(second))}`,
  cold.length ? `not HIT on the second pass (${cold.length}): ${cold.map((r) => `${r.path} ${r.cache}`).join(', ')}` : 'every asset HIT on the second pass',
  broken.length ? `NON-200 (${broken.length}): ${[...new Set(broken.map((r) => `${r.path} ${r.status}`))].join(', ')}` : 'no non-200 responses',
];
console.log(lines.join('\n'));
if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, lines.join('\n\n') + '\n');
if (broken.length) { console.error('::error::CDN warm-up got non-200 responses: the deploy is broken'); process.exit(1); }
if (cold.length) console.log(`::warning::${cold.length} of ${list.length} assets were not a CDN HIT after warming`);
