// BROWSER PROOF: who the work is FOR is not a service (sales_engineer, 2 Nov 2026).
//
// Mounts the REAL src/components/portal/supplier/ServicesTab.tsx in headless Chromium and types the supplier
// sentence from the defect into it. The tab's `supplier_api` calls are answered locally from the REAL
// rewriteServices of supabase/functions/_shared/service_rewrite.ts (bundled for Node) over the seeded demo
// vocabulary (service_aliases.json). No account is created and nothing reaches the live site: the only network
// the page makes is intercepted. The meaning layer needs live vectors, so its proposals are answered empty here;
// what this proves is the part the defect lived in - the parts the rewrite sets aside as the supplier's own words.
//
//   QD_REWRITE_SRC   path of the service_rewrite.ts to answer with (default: this checkout's)
//   QD_EXPECT        'fixed' (default) asserts no audience part; 'defect' asserts the audience IS a part (the control)
//   QD_OUT           folder for screenshots + report (default e2e-out)
import { build } from 'esbuild';
import { chromium } from 'playwright';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const ROOT = process.cwd();
const OUT = path.resolve(process.env.QD_OUT || 'e2e-out');
const EXPECT = process.env.QD_EXPECT || 'fixed';
const SRC = path.resolve(process.env.QD_REWRITE_SRC || 'supabase/functions/_shared/service_rewrite.ts');
mkdirSync(OUT, { recursive: true });

// 1. the real rewrite, bundled for Node
const rwFile = path.join(OUT, `rewrite_${EXPECT}.mjs`);
await build({ entryPoints: [SRC], bundle: true, format: 'esm', platform: 'node', outfile: rwFile, logLevel: 'error',
  absWorkingDir: path.dirname(SRC) });
const { rewriteServices } = await import(pathToFileURL(rwFile).href);
const aliases = JSON.parse(readFileSync('supabase/functions/_shared/service_aliases.json', 'utf8'));
const SERVICES = Object.entries(aliases).map(([key, v]) => {
  const i = key.indexOf('.');
  const code = key.slice(i + 1);
  return { trade_code: key.slice(0, i), code, label_en: code.replace(/_/g, ' '), label_ar: 'خدمة ' + code, aliases: [...v.en, ...v.ar] };
});

// 2. the real tab, bundled for the browser
const tabFile = path.join(OUT, 'tab.js');
await build({
  stdin: {
    contents: `import React from 'react'; import { createRoot } from 'react-dom/client'; import Tab from '@/components/portal/supplier/ServicesTab';
      const lang = new URLSearchParams(location.search).get('lang') || 'en';
      createRoot(document.getElementById('root')).render(React.createElement(Tab, { token: 'demo-token', lang }));`,
    resolveDir: ROOT, loader: 'tsx', sourcefile: 'harness.tsx',
  },
  bundle: true, format: 'iife', outfile: tabFile, jsx: 'automatic', logLevel: 'error',
  alias: { '@': path.join(ROOT, 'src') },
  // the app reads process.env.NEXT_PUBLIC_*; a preview with a .invalid target can reach no real project
  banner: { js: 'var process={env:{NODE_ENV:"production",NEXT_PUBLIC_SUPABASE_URL:"https://demo.invalid",VERCEL_ENV:"preview",NEXT_PUBLIC_VERCEL_ENV:"preview"}};' },
  loader: { '.css': 'empty', '.svg': 'dataurl', '.png': 'dataurl' },
});

const STATE = { ok: true, confirmed: false, first_run: true, checklist: [], services_by_trade: {}, selected_services: [], extra_services: [], raw_text: '',
  implied_services: [], removed_services: [], rewritten_at: null, vocabulary: { trades: [], roles: [{ code: 'supplier', label: 'Supplier', label_ar: 'مورّد' }] },
  capability: null, trade_proposals: [], voice: { enabled: false, max_seconds: 60, max_bytes: 1000000 } };

const CASES = [
  { lang: 'en', text: 'We supply and install aluminium sliding and casement windows, aluminium doors, shopfronts and glass curtain walls for villas and offices',
    audience: /villa|office/i, mustShow: ['Glass curtain walls'] },
  { lang: 'en', text: 'False ceilings and CCTV for hotels and banks and schools', audience: /hotel|bank|school/i, mustShow: [] },
  { lang: 'ar', text: 'الأسقف المعلقة للفلل والمكاتب', audience: /الفلل|المكاتب/, mustShow: [] },
];

const browser = await chromium.launch();
const report = [];
let failed = 0;
for (const [n, c] of CASES.entries()) {
  const page = await browser.newPage({ viewport: { width: 1100, height: 1400 } });
  const seen = [];
  page.on('pageerror', (e) => console.error('page error:', e.message.slice(0, 300)));
  await page.route('**/*', async (route) => {
    const u = route.request().url();
    if (u.startsWith('http://tab.local/page')) return route.fulfill({ contentType: 'text/html', body: '<!doctype html><meta charset=utf-8><div id=root></div><script src="http://tab.local/tab.js"></script>' });
    if (u.startsWith('http://tab.local/tab.js')) return route.fulfill({ contentType: 'text/javascript', body: readFileSync(tabFile, 'utf8') });
    if (/\/functions\/v1\/supplier_api/.test(u)) {
      const body = JSON.parse(route.request().postData() || '{}');
      seen.push(body.action);
      if (body.action === 'services_state') return route.fulfill({ contentType: 'application/json', body: JSON.stringify(STATE) });
      if (body.action === 'services_rewrite') {
        const rw = rewriteServices(String(body.text || ''), SERVICES, {});
        return route.fulfill({ contentType: 'application/json', body: JSON.stringify({ ok: true, raw_text: body.text, items: rw.items, service_keys: rw.service_keys,
          own_words: rw.own_words, summary_en: rw.summary_en, summary_ar: rw.summary_ar, implied: [], pending_taxonomy: rw.own_words,
          supply_only: { proposed: false, applied: false }, meaning: { state: 'on', proposals: [], lines: { candidates: 0, read: 0 } }, source: { kind: 'typed' } }) });
      }
      return route.fulfill({ contentType: 'application/json', body: '{"ok":false,"code":"demo_stub"}' });
    }
    return u.startsWith('http://tab.local') ? route.abort() : route.abort();   // nothing else leaves the machine
  });
  await page.goto(`http://tab.local/page?lang=${c.lang}`);
  await page.locator('textarea').first().fill(c.text);
  await page.getByRole('button', { name: c.lang === 'ar' ? /إعادة صياغة خدماتي/ : /Rewrite my services/ }).click();
  await page.waitForFunction(() => /Sales engineer|مهندس المبيعات/.test(document.body.innerText) && /Services we recognised|Kept in your own words|خدمات تعرّفنا|محفوظة بكلماتكم/.test(document.body.innerText), null, { timeout: 15000 });
  const shown = await page.evaluate(() => document.body.innerText);   // innerText leaves out the textarea, so the typed sentence is not in it
  await page.screenshot({ path: path.join(OUT, `services_audience_${EXPECT}_${n}_${c.lang}.png`), fullPage: true });
  const audienceShown = c.audience.test(shown);
  const missing = c.mustShow.filter((s) => !shown.includes(s));
  const ok = EXPECT === 'defect' ? (n === 0 ? audienceShown : true) : (!audienceShown && !missing.length && seen.includes('services_rewrite'));
  if (!ok) failed++;
  report.push({ n, lang: c.lang, text: c.text, audienceShown, missing, ok });
  await page.close();
}
await browser.close();
writeFileSync(path.join(OUT, `services_audience_${EXPECT}.json`), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
if (failed) { console.error(`${failed} case(s) did not behave as ${EXPECT}`); process.exit(1); }
