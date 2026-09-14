// scripts/e2e/warm_cdn.mjs — request every /_next/static asset the portal and home pages load,
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
//
// Which assets: the HTML names only the chunks needed to boot the page (17-19 of them). Chunks the
// page loads later (next/dynamic, route segments) are named inside those chunks, as "static/chunks/…"
// strings the Turbopack runtime resolves at run time; Next 16 + Turbopack serves no _buildManifest.js
// for the app router. So every fetched JS chunk is scanned for further chunk names, up to 3 rounds.
// Each is requested with the page's ?dpl= deployment id, the same URL the browser asks for.
//
// Exit 1 only when a page or asset answers non-200 (a broken deploy). A MISS on the second pass is
// logged, never fatal. Counts go to $GITHUB_STEP_SUMMARY when set.
//
// Usage: [QD_WARM_SITE=https://quotesdone.ae] node scripts/e2e/warm_cdn.mjs [--first-pass-only]
//   --first-pass-only requests each asset once and prints its x-vercel-cache: it measures whether
//   something else (another region's warm-up) already filled this edge, without warming it first.
import { appendFileSync } from 'node:fs';

const SITE = (process.env.QD_WARM_SITE || 'https://quotesdone.ae').replace(/\/$/, '');
const PAGES = ['/me', '/ar/me', '/', '/ar'];
const FIRST_ONLY = process.argv.includes('--first-pass-only');
const TIMEOUT_MS = 20_000;
const CONCURRENCY = 8;
const ROUNDS = 3;

async function get(path) {
  const res = await fetch(SITE + path, { signal: AbortSignal.timeout(TIMEOUT_MS), headers: { 'user-agent': 'quotesdone-it-engineer-warmup' } });
  const body = await res.arrayBuffer(); // read to the end so the edge stores the whole object
  const edge = (res.headers.get('x-vercel-id') || '').split('::')[0] || '?';
  return { path, status: res.status, cache: res.headers.get('x-vercel-cache') || 'none', edge, body };
}

async function pool(items, fn) {
  const out = [];
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, items.length) }, async () => {
    while (i < items.length) { const item = items[i++]; out.push(await fn(item).catch((e) => ({ path: item, status: `error ${e.name}`, cache: 'none', edge: '?' }))); }
  }));
  return out;
}

const tally = (rs) => rs.reduce((t, r) => ((t[r.cache] = (t[r.cache] || 0) + 1), t), {});
const text = (r) => (r.body ? new TextDecoder().decode(r.body) : '');
const bare = (p) => p.split('?')[0];

const pages = await pool(PAGES, get);
let dpl = '';
const fromHtml = new Set();
for (const p of pages) {
  if (p.status !== 200) continue;
  // RSC payloads inside the HTML escape their quotes, so stop at a quote or a backslash.
  for (const m of text(p).matchAll(/\/_next\/static\/[^"'\\\s)<>]+/g)) {
    fromHtml.add(m[0]);
    dpl ||= (m[0].match(/[?&]dpl=([\w-]+)/) || [])[1] || '';
  }
}

// First pass: the HTML's assets, then whatever chunks those chunks name, round by round.
const seen = new Set([...fromHtml].map(bare));
const first = [];
let batch = [...fromHtml].sort();
for (let round = 0; round <= ROUNDS && batch.length; round++) {
  const got = await pool(batch, get);
  for (const r of got) r.round = round;
  first.push(...got);
  const next = [];
  for (const r of got) {
    if (r.status !== 200 || !bare(r.path).endsWith('.js')) continue;
    for (const m of text(r).matchAll(/static\/chunks\/[\w.~-]+\.(?:js|css)/g)) {
      const p = `/_next/${m[0]}`;
      if (seen.has(p)) continue;
      seen.add(p);
      next.push(dpl ? `${p}?dpl=${dpl}` : p);
    }
  }
  batch = next.sort();
}
const second = FIRST_ONLY ? [] : await pool(first.map((r) => r.path), get);

const byRound = first.reduce((t, r) => ((t[r.round] = (t[r.round] || 0) + 1), t), {});
const broken = [...pages, ...first, ...second].filter((r) => r.status !== 200);
const cold = second.filter((r) => r.cache !== 'HIT');
const lines = [
  `### CDN warm-up: ${SITE}${FIRST_ONLY ? ' (first pass only)' : ''}`,
  `edge: ${[...new Set([...pages, ...first].map((r) => r.edge))].join(', ')}`,
  `pages: ${pages.map((p) => `${p.path} ${p.status}`).join(', ')}`,
  `assets: ${first.length} (in the HTML: ${byRound[0] || 0}; named by chunks: ${first.length - (byRound[0] || 0)})`,
  `first pass x-vercel-cache: ${JSON.stringify(tally(first))}`,
  ...(FIRST_ONLY ? [] : [
    `second pass x-vercel-cache: ${JSON.stringify(tally(second))}`,
    cold.length ? `not HIT on the second pass (${cold.length}): ${cold.map((r) => `${bare(r.path)} ${r.cache}`).join(', ')}` : 'every asset HIT on the second pass',
  ]),
  broken.length ? `NON-200 (${broken.length}): ${[...new Set(broken.map((r) => `${bare(r.path)} ${r.status}`))].join(', ')}` : 'no non-200 responses',
];
console.log(lines.join('\n'));
console.log('per asset, first pass (round cache edge path):');
for (const r of first.sort((a, b) => a.round - b.round || a.path.localeCompare(b.path))) console.log(`  ${r.round} ${r.cache} ${r.edge} ${bare(r.path)}`);
if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, lines.join('\n\n') + '\n');
if (broken.length) { console.error('::error::CDN warm-up got non-200 responses: the deploy is broken'); process.exit(1); }
if (cold.length) console.log(`::warning::${cold.length} of ${first.length} assets were not a CDN HIT after warming`);
