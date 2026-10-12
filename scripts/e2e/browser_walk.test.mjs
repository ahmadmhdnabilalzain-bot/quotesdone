// The browser walk's own defects from run f4294be8 (12 Oct 2026, it_engineer), held offline over the source.
// Each of these made the walk report a product defect that the product did not have:
//   - the portal walk judged /ar/me as Arabic for an English-registered customer (the account's language wins once
//     signed in, src/lib/documentLocale.ts adoptLocale) -> "Arabic page not RTL";
//   - it pressed hidden nav items (the desktop sidebar on a phone, the phone tab bar on a desktop) and reported the
//     click timeout as "could not be pressed" plus a 5.3 s / 35 s "slow load";
//   - it resized a desktop window instead of emulating a phone (phantom 18 px overflow on the supplier portal);
//   - it counted the closed Account / bell <details> menus as unnamed controls;
//   - the journey typed into a request box that only exists after "New request" is pressed.
//   node --test scripts/e2e/browser_walk.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const SRC = readFileSync(new URL('./browser_walk.mjs', import.meta.url), 'utf8');

// The other cases read the walk as text, so they would pass over a file that does not parse (#1321 shipped
// `export export` once). This one makes node parse it.
test('the walk parses', async () => {
  const { spawnSync } = await import('node:child_process');
  const { fileURLToPath } = await import('node:url');
  const r = spawnSync(process.execPath, ['--check', fileURLToPath(new URL('./browser_walk.mjs', import.meta.url))], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
});

test('a signed-in customer portal is judged in the registered language, and the URL must follow it', () => {
  assert.match(SRC, /const want = who\.kind === 'customer' \? await registeredLocale\(who\.email\) : 'en';/);
  assert.match(SRC, /judge\(f, \{ lang: want, audience: who\.kind/);
  assert.match(SRC, /registered language \$\{want\} but the URL stayed/);
});

test('only visible nav items are pressed, on a real phone context, with the sheet opened only when needed', () => {
  assert.match(SRC, /const navSel = 'nav a:visible, nav button:visible';/);
  assert.match(SRC, /signedInPage\(browser, who, \{ lang, viewport: view \}\)/);
  assert.doesNotMatch(SRC, /setViewportSize\(VIEWS\.mobile/);
  assert.match(SRC, /#qd-nav-more \[role=group\] button:visible/, 'the sheet\'s language / sign-out buttons are not tabs');
});

test('content of a closed <details> is not on screen', () => {
  assert.match(SRC, /el\.closest\('details:not\(\[open\]\) > :not\(summary\)'\)\) return false;/);
});

test('the journey opens "New request" before it types or attaches', () => {
  const fill = SRC.indexOf('const box = await openNewRequest(page, lang);');
  const attach = SRC.indexOf("await openNewRequest(page, lang);\n    const input = page.locator('input[type=file]')");
  assert.ok(fill > 0 && attach > 0);
  assert.doesNotMatch(SRC, /page\.locator\('textarea:visible'\)\.first\(\);\n\s+await box\.fill/);
});
