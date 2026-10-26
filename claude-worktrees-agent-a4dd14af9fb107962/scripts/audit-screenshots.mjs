// Capture every major QuotesDone route at desktop and mobile size.
//
// Written during the Phase 0 audit because the audit environment (a cloud sandbox with an egress
// allowlist) could not reach quotesdone.com - every navigation returned ERR_CONNECTION_RESET. The
// requirement asks for a screenshot set covering responsive and mobile behaviour, so rather than
// claim coverage that was never captured, the capture is committed as one command.
//
//   npx playwright install chromium
//   node scripts/audit-screenshots.mjs                       # against production
//   BASE=http://localhost:3000 node scripts/audit-screenshots.mjs   # against a local dev server
//
// Writes docs/audit/screenshots/{desktop,mobile}__<route>.png and docs/audit/route_probe.json.
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';

const BASE = process.env.BASE || 'https://quotesdone.com';
const OUT = 'docs/audit/screenshots';

// Application routes first - they are the ones the upgrade touches.
const ROUTES = [
  ['os', '/os'], ['portal', '/portal'], ['me', '/me'],
  ['me-ar', '/ar/me'], ['portal-ar', '/ar/portal'], ['os-ar', '/ar/os'],
  ['home', '/'], ['home-ar', '/ar'],
  ['services', '/services'], ['service-detail', '/services/waterproofing-suppliers'],
  ['about', '/about'], ['faq', '/faq'], ['contact', '/contact'], ['blog', '/blog'],
  ['terms', '/terms'], ['privacy', '/privacy'], ['supplier-agreement', '/supplier-agreement'],
];

const VIEWPORTS = [
  ['desktop', 1440, 900, undefined],
  ['mobile', 390, 844,
   'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'],
];

mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch();
const probe = [];

for (const [vp, width, height, userAgent] of VIEWPORTS) {
  const ctx = await browser.newContext({ viewport: { width, height }, userAgent, isMobile: vp === 'mobile' });
  for (const [name, path] of ROUTES) {
    const page = await ctx.newPage();
    const consoleErrors = [];
    page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 160)); });
    let status = null, title = '', error = '';
    try {
      const res = await page.goto(BASE + path, { waitUntil: 'domcontentloaded', timeout: 45000 });
      status = res?.status() ?? null;
      await page.waitForTimeout(3000);           // let client components mount and fetch
      title = await page.title();
      await page.screenshot({ path: `${OUT}/${vp}__${name}.png`, fullPage: true });
    } catch (e) { error = String(e.message).slice(0, 160); }
    probe.push({ viewport: vp, name, path, status, title, error, consoleErrors });
    console.log(`${vp.padEnd(7)} ${path.padEnd(38)} ${status ?? 'ERR'} ${error}`);
    await page.close();
  }
  await ctx.close();
}

await browser.close();
writeFileSync('docs/audit/route_probe.json', JSON.stringify(probe, null, 1));
const bad = probe.filter(p => p.status !== 200);
console.log(`\n${probe.length} captures, ${bad.length} non-200.`);
if (bad.length) console.log(bad.map(b => `  ${b.viewport} ${b.path} -> ${b.status ?? b.error}`).join('\n'));
