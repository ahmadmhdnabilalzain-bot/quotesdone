// THE HOMEPAGE DESCRIPTION SAYS EVERY OTHER QUOTE IS LISTED, BEFORE THE CUT (30 Sep 2026, sales_engineer; founder
// rulings 49 and 51: never claim we show only 3 quotes).
//
// MEASURED: messages/en.json siteDesc was 265 characters. src/lib/seo.ts clampDesc() cuts a description at 158 on a
// word and adds an ellipsis, so the live meta description (and every link preview) read "...the top 3 come levelled in
// a comparison report…" and lost "every other quote is listed too": the one claim ruling 49 forbids.
//
// WHAT FAILS IF THE CAUSE RETURNS: either locale's siteDesc grows past the clamp, or stops saying every other quote is
// listed, or the clamp moves below the description.
//
//   node --test scripts/checks/the_homepage_description_says_every_other_quote_is_listed_before_the_cut.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const max = Number(read('src/lib/seo.ts').match(/function clampDesc\(s: string, max = (\d+)\)/)?.[1]);

test('both locales fit the clamp whole and keep "every other quote is listed"', () => {
  assert.ok(max >= 120, 'clampDesc max not found in src/lib/seo.ts');
  for (const [loc, must] of [['en', /every other quote/i], ['ar', /كل العروض الأخرى/]]) {
    const d = JSON.parse(read(`messages/${loc}.json`)).common?.siteDesc ?? JSON.parse(read(`messages/${loc}.json`)).siteDesc
      ?? Object.values(JSON.parse(read(`messages/${loc}.json`))).find((v) => v && typeof v === 'object' && 'siteDesc' in v)?.siteDesc;
    assert.equal(typeof d, 'string', `${loc}: siteDesc not found`);
    const t = d.replace(/\s+/g, ' ').trim();
    assert.ok(t.length <= max, `${loc}: siteDesc is ${t.length} characters; clampDesc cuts at ${max}, so its end is lost`);
    assert.match(t, must, `${loc}: siteDesc no longer says every other quote is listed`);
  }
});
