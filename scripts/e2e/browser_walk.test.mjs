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

test('the Arabic journey identity is an Arabic-registered customer (run 2, 19 Oct: C1 en walked /ar/me in English)', () => {
  const S2 = readFileSync(new URL('./stage2.mjs', import.meta.url), 'utf8');
  assert.match(S2, /const qc = alu\?\.cu\?\.cfg\.locale === 'ar' \? alu\.cu : \(fx\.arQuoted \|\| ar\);/);
  assert.equal(S2.match(/fx\.arQuoted = arInq\?\.cu;/g)?.length, 1, 'the Arabic customer with its own quoted request (S10) is handed to S26, once');
  assert.match(S2, /customerAr: who\(qc, 'customer', qc\.cfg\.label\)/);
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
  // Run 71b75b60: the attach step opens New request, then takes the COMPOSER's own file input (not the page's first).
  const attach = SRC.search(/const box = await openNewRequest\(page, lang\);\n(?:\s*\/\/[^\n]*\n)*\s*const input = box\.locator\([^\n]*\)\.locator\('input\[type=file\]'\)/);
  assert.ok(fill > 0 && attach > 0 && attach !== fill);
  assert.doesNotMatch(SRC, /const input = page\.locator\('input\[type=file\]'\)\.first\(\)/, 'never the first file input anywhere on the page');
  assert.doesNotMatch(SRC, /page\.locator\('textarea:visible'\)\.first\(\);\n\s+await box\.fill/);
});

// Run 0a717394 (19 Oct): the quotes step gave up at 20 s; its own screenshot then showed C1's "4 quotes" card.
test('the quotes step waits long enough for the request cards and names a slow list as slow', () => {
  assert.match(SRC, /export const CARDS_WAIT_MS = 60000, CARDS_SLOW_MS = 10000;/);
  assert.match(SRC, /request cards on screen: \$\{seen\.length/, 'a failed quotes step names the request cards the page held');
  assert.match(SRC, /ms: clicked \? Date\.now\(\) - t0 : 0/, 'a blocked press is not reported as a slow load (its 5 s is the click timeout)');
  assert.match(SRC, /await card\.waitFor\(\{ state: 'visible', timeout: CARDS_WAIT_MS \}\)/);
  assert.doesNotMatch(SRC, /await card\.waitFor\(\{ state: 'visible', timeout: 20000 \}\)/);
  assert.match(SRC, /SLOW: the quoted card took \$\{cardsMs\} ms/);
});

// Run 4506ead8 (3 Nov 2026): C1's quoted card was on screen and the filter never matched it - its textContent reads
// "...Dubai·3 quotesOpen request..." (no space between elements), and a trailing \b after "quotes" cannot sit between "s" and "O".
test('the quoted-card filter matches the card text as the page really joins it', () => {
  const m = SRC.match(/export const QUOTED_CARD = \{ en: \/(.+?)\/, ar:/);
  assert.ok(m, 'QUOTED_CARD.en is declared');
  const en = new RegExp(m[1]);
  assert.match('RevealedAluminium163071Dubai·3 quotesOpen requestSupply and install 20 aluminium windows', en);
  assert.match('Matching · Plumbing · 1 quote · editable', en);
  assert.doesNotMatch('MatchingPainting163105Dubai·0 quotes·editable 58mOpen request', en, 'a card with 0 quotes is not the quoted card');
  assert.doesNotMatch('RevealedAluminium163071Dubai·3 quotesOpen request', /\b[1-9]\d* quotes?\b/, 'known-bad: the old filter missed this card');
  assert.equal((SRC.match(/hasText: QUOTED_CARD\[/g) || []).length, 2, 'the quotes step and the reveal step use the one filter');
});

// Run 12eb1c85 (3 Nov 2026): inside the reveal loop `const card = page.locator(...)` shadowed the loop's card NUMBER, so the
// success step typed a locator into Stripe ("locator.fill: value: expected string, got object") the first time the button was found.
test('the reveal steps never shadow the card number they pay with', () => {
  const loop = SRC.slice(SRC.indexOf("for (const [name, card] of [['reveal checkout: test card success'"), SRC.indexOf("// 6. Post-reveal supplier details"));
  assert.ok(loop.length > 100, 'the reveal loop is found');
  assert.doesNotMatch(loop, /\b(const|let|var)\s+card\s*=/, 'no inner binding named card');
  assert.doesNotMatch("for (const [name, card] of x) { const card = page.locator('[id^=\"inq-\"]'); }", /^(?![\s\S]*\b(const|let|var)\s+card\s*=)/, 'known-bad: the old loop body redeclared card');
  assert.match(loop, /fill\(card\)/);
});
