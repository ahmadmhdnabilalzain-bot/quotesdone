// THE SERVED LOCALE DOES NOT REFETCH THE OVERVIEW (28 Sep 2026, it_engineer).
//
// The cause: the customer overview's [lang] effect refetched customer_portal:overview whenever lang
// changed, and adopting the registered locale that my_inquiries serves IS a lang change when the URL
// disagrees with it. The overview is built in customers.locale already, so that second call was a pure
// serial round trip after first paint (measured on production, /ar for an en-registered customer:
// a second customer_portal:overview @846 ms +601 ms).
//
// WHAT FAILS IF THE CAUSE RETURNS: loadInq stops recording the served locale as the language the
// overview was loaded in before it adopts it, or the [lang] effect stops consulting that record.
//
//   node --test scripts/checks/the_served_locale_does_not_refetch_the_overview.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const src = readFileSync(join(REPO, 'src/components/me/CustomerPortal.tsx'), 'utf8');

test('loadInq marks the served locale as loaded before adopting it', () => {
  const body = src.slice(src.indexOf('const loadInq = (first)'), src.indexOf('const loadOv = (first)'));
  const mark = body.indexOf('langLoaded.current = j.locale');
  const adopt = body.indexOf('onServedLocale(j.locale)');
  assert.ok(mark > 0, 'loadInq no longer records the served locale, so adopting it refetches the overview');
  assert.ok(adopt > mark, 'the served locale must be recorded BEFORE onServedLocale changes lang');
  assert.ok(src.indexOf('const langLoaded = useRef(lang)') < src.indexOf('const loadInq = (first)'), 'langLoaded must be declared before loadInq');
});

test('the [lang] effect refetches only when lang differs from what was loaded', () => {
  assert.match(src, /useEffect\(\(\) => \{ if \(langLoaded\.current !== lang\) \{ langLoaded\.current = lang; loadOv\(\); \} \}, \[lang\]\);/);
});
