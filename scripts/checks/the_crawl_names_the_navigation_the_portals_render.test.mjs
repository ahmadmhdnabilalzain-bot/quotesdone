// The e2e crawl names the navigation the portals actually render (18 Sep 2026, sales_engineer).
//
// WHY THIS EXISTS. scripts/e2e/journeys.mjs journey f keeps a list of every destination both portals
// offer, in English and Arabic, because a crawl that only clicks what it finds cannot notice a
// destination that disappeared. That list is a SECOND COPY of words whose home is elsewhere
// (src/components/me/portalText.ts and src/components/portal/supplier/workspaceCopy.ts), and on
// 15 September the supplier portal was rebuilt (#722, #723) without it: "Get matched" was removed,
// RFQs became "Inquiries received", Quotes became "Quotations submitted", Projects stopped being a
// destination, "My scope" became Services, and Profile/Billing/Settings moved into an Account menu.
// Eight labels then waited out an 8-second click timeout in each of four matrices, every night, and
// the nightly run was CANCELLED at its 30-minute wall on 15, 16 and 17 September. A cancelled job
// writes no heartbeat, so the estate read three dead nights as "it never ran".
//
// The copy is still the right design — but nothing tied it to the original. This is that tie, and it
// costs no network: rename a tab and this fails in CI, in seconds, instead of costing a night.
//
// It reads source only. journeys.mjs is NOT imported: importing it loads scripts/e2e/fixtures.mjs,
// which reads the Supabase management token at module load and would make this check need a secret.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = process.cwd();
const JOURNEYS = readFileSync(join(ROOT, 'scripts/e2e/journeys.mjs'), 'utf8');
const SHELL = readFileSync(join(ROOT, 'src/components/me/PortalShell.tsx'), 'utf8');
const SUPPLIER = readFileSync(join(ROOT, 'src/components/portal/SupplierPortal.tsx'), 'utf8');
const { t } = await import(pathToFileURL(join(ROOT, 'src/components/me/portalText.ts')).href);
const { ws } = await import(pathToFileURL(join(ROOT, 'src/components/portal/supplier/workspaceCopy.ts')).href);

/** Read one `const <name> = { … };` object literal out of a source file, by matching its braces. */
function literal(src, name, where) {
  const at = src.indexOf(`const ${name} = {`);
  assert.notEqual(at, -1, `${where} no longer declares ${name}`);
  let i = src.indexOf('{', at), depth = 0, end = -1;
  for (let j = i; j < src.length; j++) {
    if (src[j] === '{') depth++;
    else if (src[j] === '}' && --depth === 0) { end = j + 1; break; }
  }
  assert.notEqual(end, -1, `${where}: ${name} is not closed`);
  return new Function('return (' + src.slice(i, end) + ')')();
}

const NAV = literal(JOURNEYS, 'NAV', 'journeys.mjs');
const ACCOUNT_MENU = literal(JOURNEYS, 'ACCOUNT_MENU', 'journeys.mjs');

test('the crawl names the customer portal\'s destinations, in both languages', () => {
  // NAV_GROUPS is the shell's own order; each item names a key in portalText.
  const keys = [...SHELL.matchAll(/\{ id: '[a-z]+',\s+icon: \w+,\s+label: '(\w+)'/g)].map((m) => m[1]);
  assert.ok(keys.length >= 10, `read ${keys.length} destinations out of PortalShell NAV_GROUPS`);
  for (const lang of ['en', 'ar']) {
    assert.deepEqual(NAV.customer[lang], keys.map((k) => t(lang, k)),
      `journey f's customer ${lang} list is not what PortalShell renders`);
  }
});

test('the crawl names the supplier portal\'s tabs and its Account menu, in both languages', () => {
  const main = JSON.parse(SUPPLIER.match(/const MAIN_TABS = (\[[^\]]+\]);/)[1].replace(/'/g, '"'));
  const acct = JSON.parse(SUPPLIER.match(/const ACCOUNT_TABS = (\[[^\]]+\]);/)[1].replace(/'/g, '"'));
  for (const lang of ['en', 'ar']) {
    assert.deepEqual(NAV.supplier[lang], main.map((k) => ws(lang, 'tab_' + k)),
      `journey f's supplier ${lang} tabs are not what SupplierPortal renders`);
    assert.equal(ACCOUNT_MENU[lang].menu, ws(lang, 'account_menu'), `the ${lang} Account menu is named wrong`);
    assert.deepEqual(ACCOUNT_MENU[lang].items, acct.map((k) => ws(lang, 'acct_' + k)),
      `journey f's supplier ${lang} Account menu is not what SupplierPortal renders`);
  }
  // Journey b opens two of those tabs by name through supplierTab(lang, key), which indexes
  // NAV.supplier by this list. If MAIN_TABS is reordered and this is not, journey b silently drives
  // the wrong tab — the same fault as the stale /^RFQs/ it replaced, one layer along.
  const jb = JSON.parse(JOURNEYS.match(/const SUPPLIER_TABS = (\[[^\]]+\]);/)[1].replace(/'/g, '"'));
  assert.deepEqual(jb, main, "journey b's SUPPLIER_TABS is not SupplierPortal's MAIN_TABS order");
});

test('the destinations retired on 15 September are not crawled for any more', () => {
  // Retired WITH their subject, not deleted from coverage: Projects is now the revealed-jobs list
  // inside Messages (TAB_ALIAS projects -> messages), "My scope" is Services, and "Get matched" is
  // the registration checklist that heads Documents. Each is still crawled, under its new home.
  assert.match(SUPPLIER, /TAB_ALIAS = \{[^}]*projects: 'messages'[^}]*\}/, 'Projects no longer folds into Messages');
  // Matched on the pair, not on the whitespace between them: #736 renamed `tab` to `shownTab` here
  // while this branch was open, and a check that asserts a layout rather than a fact is a check that
  // fails for the wrong reason.
  assert.match(SUPPLIER, /Tab === 'documents' && <>[\s\S]{0,40}<GetMatched\b/i, 'Get matched no longer heads Documents');
  for (const gone of ['Get matched', 'My scope', 'RFQs']) {
    assert.ok(!NAV.supplier.en.includes(gone), `journey f still crawls the retired destination "${gone}"`);
  }
});

test('journey f sets the account locale, because the portals follow it and not the URL', () => {
  // Founder, 14 Sep 2026: "if someone registered while the language was arabic then arabic follows
  // through the whole workflow". Measured on production 18 Sep: an en-registered fixture opening
  // /ar/portal gets dir=ltr lang=en. Without this the two Arabic passes crawl an English screen.
  assert.match(JOURNEYS, /update public\.customers set locale = \$\{q\(lang\)\}/, 'the crawl does not set customers.locale');
  assert.match(JOURNEYS, /update public\.leads set locale = \$\{q\(lang\)\}/, 'the crawl does not set leads.locale');
  // 12 Oct 2026 (founder ruling 1008): the supplier portal is always English and adopts no locale;
  // scripts/checks/the_supplier_portal_is_always_english.test.mjs owns that rule.
  assert.match(SUPPLIER, /const lang: string = 'en';/, 'the supplier portal must render English only');
});
