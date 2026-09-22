// THE SUPPLIER PORTAL HAS ONE FETCH HELPER AND ONE MONEY FORMAT.
//
// Audit 22 Sep 2026, findings SP-C-05, SP-I-01 and SP-I-10 (seat: customer_support).
//
// WHAT WAS MEASURED. Twelve files under src/components/portal/supplier/ each carried a private,
// byte-identical `async function call(path, body, token?)` whose entire body was `return r.json()`.
// Seven of them then chained `.then(j => …)` with no `.catch`: a gateway 502 whose body is HTML, or
// a dropped mobile leg, rejected that promise, the component's state was never written, and the
// panel sat on "Loading" for as long as the supplier left it open — MarketIntelligence,
// ProductIntelligence, SupplierAdvisor, SupplierDocumentImpact, SupplierInventory,
// SupplierKnowledgeGraph and SupplierTwin. The shared `./api` helper has the timeout, the
// JSON-parse catch, the 401 -> `_expired` mapping and the stable `code` that supplier/PanelState
// renders in Arabic; a thirteenth private copy would silently opt one more panel out of all four.
//
// The same shape had already happened to money: `aed()` in SupplierPortal.tsx, `aedIn()` in
// quoteReviewApi.ts and a hard-coded "AED " + n in SpecHold.tsx wrote the same amount three ways on
// the same screen, and about ten `toLocaleString()` calls named no locale at all, so the group
// separator followed the VIEWER's browser rather than the page — "1.200" for a supplier reading
// /ar in a de-DE browser.
//
// WHY A CHECK AND NOT JUST THE FIX. Both defects arrived by copy-paste from a neighbouring file,
// which is exactly what a reviewer reading one diff cannot see. This fails on the copy, not on the
// consequence.
//
//   node --test scripts/checks/the_supplier_portal_has_one_fetch_helper_and_one_money_format.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const DIR = path.join(REPO, 'src', 'components', 'portal', 'supplier');
const OWNER = 'api.ts';        // the one file allowed to define call()
const MONEY = 'money.ts';      // the one file allowed to define the AED format

const files = () => fs.readdirSync(DIR).filter((f) => /\.(ts|tsx)$/.test(f) && !f.endsWith('.test.ts'));
const read = (f) => fs.readFileSync(path.join(DIR, f), 'utf8');

// `function call(` / `const call = ` / `let call = `, however it is declared, async or not.
const DEFINES_CALL = /(?:^|\n)\s*(?:export\s+)?(?:async\s+)?function\s+call\s*\(|(?:^|\n)\s*(?:export\s+)?(?:const|let)\s+call\s*(?::[^=\n]*)?=/;

test('only supplier/api.ts defines the portal fetch helper', () => {
  const offenders = files().filter((f) => f !== OWNER && DEFINES_CALL.test(read(f)));
  assert.deepEqual(offenders, [],
    'these panels define their own call() instead of importing it from ./api — the shared one owns the '
    + 'timeout, the JSON-parse catch, the 401 -> _expired mapping and the stable error code');
});

// A panel that talks to an edge function must do it through the shared helper, not a bare fetch.
test('no supplier panel calls fetch() at an edge-function URL directly', () => {
  const offenders = files().filter((f) => f !== OWNER && /\bfetch\s*\(\s*fnUrl\s*\(/.test(read(f)));
  assert.deepEqual(offenders, [], 'these files bypass ./api by calling fetch(fnUrl(…)) themselves');
});

// The AED format: "AED " + a number, or the Arabic د.إ suffix, built by hand.
const DEFINES_MONEY = /['"`]AED\s*['"`]\s*\+|\+\s*['"`]\s*د\.إ|['"`]\s*د\.إ['"`]\s*$/m;

test('only supplier/money.ts writes the AED format by hand', () => {
  const offenders = files().filter((f) => f !== MONEY && DEFINES_MONEY.test(read(f)));
  assert.deepEqual(offenders, [],
    'these files build an AED amount themselves instead of importing aed() from ./money — one screen '
    + 'then shows the same figure two ways, and /ar loses its د.إ');
});

// toLocaleString() with no locale takes the VIEWER's browser locale, not the page's.
test('every toLocaleString in the supplier portal names its locale', () => {
  const offenders = [];
  for (const f of files()) {
    const src = read(f);
    src.split('\n').forEach((line, i) => {
      // A locale is the first argument: a quoted tag, or a variable/ternary that resolves to one.
      if (/\.toLocaleString\s*\(\s*\)/.test(line) || /\.toLocaleString\s*\(\s*\{/.test(line)) {
        offenders.push(`${f}:${i + 1}`);
      }
    });
  }
  assert.deepEqual(offenders, [],
    'toLocaleString() with no locale argument follows the browser, not the page — a supplier reading '
    + '/ar in a de-DE browser saw "1.200" where the invoice says "1,200". Pass an explicit locale.');
});
