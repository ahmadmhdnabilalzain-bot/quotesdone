// scripts/e2e/inquiry_box_visible.mjs — the customer's inquiry box is SEEN, not merely present.
//
// Founder, 18 Oct 2026: on the signed-in create-inquiry page "the box where you type your inquiry is
// hidden". The S26 browser walk had passed: openNewRequest() waited for `#qd-intake-input` to be
// Playwright-"visible", which only means a non-empty bounding box and no visibility:hidden. A textarea
// clipped to nothing by an ancestor's overflow:hidden, or sitting under another element, is still
// "visible" to that test. This check asserts what a person needs instead, at every viewport and in
// both languages:
//   - the box lies inside the window and is not clipped by any overflow ancestor;
//   - it is at least two text lines tall;
//   - the element at its centre (and at its four inner corners) is the box itself: nothing on top;
//   - it takes focus and what is typed lands in it.
//
//   node scripts/e2e/inquiry_box_visible.mjs            # own ZZ DEMO customers, cleaned up after
//   node scripts/e2e/inquiry_box_visible.mjs <ids.json> # the S26 walk's identities (customer + customerAr)
// Screenshots + computed styles: QD_WALK_OUT (default the Desktop sandbox folder)/inquiry_box/.
import { SANDBOX_OUT } from '../lib/sandbox_out.mjs';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { launch, signedInPage, SITE, measureInquiryBox } from './browser.mjs';
import { openNewRequest, demoSessionFactory } from './browser_walk.mjs';

export const BOX_VIEWPORTS = [
  { width: 1440, height: 900 }, { width: 1366, height: 768 }, { width: 1280, height: 720 },
  { width: 768, height: 1024 }, { width: 375, height: 812 },
];
const OUT = join(process.env.QD_WALK_OUT || join(SANDBOX_OUT, 'browser'), 'inquiry_box');

/** The whole assertion for one page: open New request, measure, focus, type. Returns { ok, facts }. */
export async function assertBoxUsable(page, lang) {
  // openNewRequest throws on an unusable box; here the full facts are wanted, so measure regardless.
  await openNewRequest(page, lang).catch((e) => { if (!/not usable/.test(String(e.message))) throw e; });
  const box = page.locator('#qd-intake-input');
  // A person scrolls the PAGE to the panel; that is allowed. What is measured is whether the box is then
  // whole: not cut by the panel's own overflow, not under anything, not a sliver.
  // 'nearest' honours the box's scroll-margin (it clears the phone's fixed tab bar), as focusing it does.
  await box.evaluate((el) => el.scrollIntoView({ block: 'nearest' })).catch(() => {});
  await page.waitForTimeout(400);
  await page.waitForTimeout(600);   // let the panel settle (fonts, concierge steps, motion)
  const facts = await page.evaluate(measureInquiryBox);
  const probe = lang === 'ar' ? 'نافذة ألمنيوم' : 'ZZ DEMO box check';
  let typed = false;
  if (!facts.problems.length) {
    await box.click({ timeout: 5000, trial: false }).catch((e) => facts.problems.push('click failed: ' + String(e.message).split('\n')[0]));
    const focused = await page.evaluate(() => document.activeElement?.id === 'qd-intake-input');
    if (!focused) facts.problems.push('the box did not take focus');
    await page.keyboard.type(probe);
    typed = (await box.inputValue()).includes(probe);
    if (!typed) facts.problems.push('typed text did not land in the box');
    await box.fill('');
  }
  return { ok: facts.problems.length === 0, facts };
}

async function run(identities) {
  mkdirSync(OUT, { recursive: true });
  const browser = await launch();
  const results = [];
  try {
    for (const { lang, email } of identities) {
      const newSession = await demoSessionFactory(email);
      for (const vp of BOX_VIEWPORTS) {
        const name = `${vp.width}x${vp.height}_${lang}`;
        const { ctx, page } = await signedInPage(browser, { kind: 'customer', email, newSession }, { lang, viewport: vp });
        try {
          await page.goto(SITE + (lang === 'ar' ? '/ar' : '') + '/me', { waitUntil: 'load' });
          await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
          const { ok, facts } = await assertBoxUsable(page, lang).catch((e) => ({ ok: false, facts: { problems: ['could not open New request: ' + String(e.message).split('\n')[0]] } }));
          await page.screenshot({ path: join(OUT, name + '.png') }).catch(() => {});
          writeFileSync(join(OUT, name + '.json'), JSON.stringify(facts, null, 2));
          results.push({ step: name, status: ok ? 'PASS' : 'FAIL', issues: facts.problems.map((what) => ({ what })) });
          console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${ok ? '' : ' — ' + facts.problems.join(' | ').slice(0, 300)}`);
        } finally { await ctx.close(); }
      }
    }
  } finally { await browser.close(); }
  // One level up, beside the walk's other step files: stage2 S26 reads every <name>.json there as a PASS/FAIL list.
  writeFileSync(join(OUT, '..', 'inquiry_box.json'), JSON.stringify(results, null, 2));
  return results;
}

if (process.argv[1]?.replace(/\\/g, '/').endsWith('scripts/e2e/inquiry_box_visible.mjs')) {
  const idsFile = process.argv[2];
  let identities, fx = null, fxRun = null;
  if (idsFile) {
    const ids = JSON.parse(readFileSync(idsFile, 'utf8'));
    identities = [{ lang: 'en', email: ids.customer.email }, { lang: 'ar', email: (ids.customerAr || ids.customer).email }];
  } else {
    fx = await import('./fixtures.mjs');
    fxRun = await fx.openRun();
    const en = await fx.makeDemoCustomer(fxRun, { locale: 'en', label: 'BoxEN' });
    const ar = await fx.makeDemoCustomer(fxRun, { locale: 'ar', label: 'BoxAR' });
    identities = [{ lang: 'en', email: en.email }, { lang: 'ar', email: ar.email }];
  }
  let results = [];
  try { results = await run(identities); }
  finally { if (fx) { const c = await fx.closeRun(fxRun); console.log('cleanup', JSON.stringify(c.leftovers?.summary ?? c.leftovers ?? c.removed?.summary)); } }
  const bad = results.filter((r) => r.status !== 'PASS');
  console.log(`${results.length - bad.length}/${results.length} viewports usable`);
  process.exit(bad.length || !results.length ? 1 : 0);
}
