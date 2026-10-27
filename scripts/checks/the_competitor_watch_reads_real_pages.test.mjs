// THE COMPETITOR WATCH READS REAL PAGES (marketing, ledger 1003 MKT-C06, 19 Oct 2026).
// Measured: 31 competitor pages "fetched" averaged 53 characters of text, because the script strip ran GREEDY in
// Postgres (the first quantifier sets the whole pattern's greediness) and deleted the body; and the weekly brief was
// written on 0 pages and 0 posts. This fails if the greedy strip, the one-alternation feed split, or a brief that
// claims findings from no input comes back in the newest definitions.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const manifest = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim())
  .filter((l) => l.endsWith('.sql') && !l.startsWith('#'));
const pending = readdirSync('scripts/sql/pending').filter((f) => f.endsWith('.txt') && !f.endsWith('_probe.txt'))
  .map((f) => `scripts/sql/${f.replace(/\.txt$/, '.sql')}`);
const files = [...manifest, ...pending].filter(existsSync);

function newest(fn) {
  const def = new RegExp(String.raw`create\s+or\s+replace\s+function\s+public\.${fn}\s*\(`, 'i');
  const file = files.filter((f) => def.test(readFileSync(f, 'utf8'))).pop();
  assert.ok(file, `no file defines ${fn}`);
  return { file, body: readFileSync(file, 'utf8').split(def).pop().split(/\$(?:function|fn)\$;/)[0] };
}


test('page text is stripped non-greedily from the first quantifier', () => {
  const { file, body } = newest('fn_competitor_scan_ingest');
  assert.doesNotMatch(body, /'<script\[\^>\]\*>/, `${file}: the greedy script strip is back`);
  assert.match(body, /'<script\[\^>\]\*\?>\.\*\?<\/script>'/, `${file}: scripts are not stripped non-greedily`);
  assert.match(body, /length\(v_text\) < 200/, `${file}: an empty shell can be counted as collected again`);
  assert.match(body, /content_hash like 'v2:%'/, `${file}: a pre-fix shell can be "the last reading"`);
});

test('a competitor feed is split item by item, and posts reach market_intel', () => {
  const { file, body } = newest('fn_competitor_feed_ingest');
  assert.doesNotMatch(body, /'\(<item/, `${file}: a top-level alternation returns every item as one`);
  assert.match(body, /fn_marketing_intel_upsert/, `${file}: feed items are not stored`);
});

test('the weekly brief states its inputs and claims nothing from none', () => {
  const { file, body } = newest('fn_marketing_competitor_refresh_duty');
  assert.match(body, /'claims_findings', v_claims/, `${file}: the brief does not say whether it claims findings`);
  assert.match(body, /v_claims := v_read > 0 or v_posts > 0/, `${file}: claims are not tied to inputs`);
  assert.match(body, /NO INPUT THIS WEEK/, `${file}: a brief on nothing does not say so`);
});

test('a feed link is kept only when it is on the competitor\'s own site (pg_net fetches it from inside the database network)', () => {
  const { file, body } = newest('fn_competitor_public_links');
  assert.match(body, /feed_host = site or right\(feed_host, length\(site\) \+ 1\) = '\.' \|\| site/, `${file}: a feed on another host can be fetched`);
  assert.match(body, /m !~ '\^https:\/\/\[\^\/\?#\]\*@'/, `${file}: a userinfo URL can disguise the host`);
});

test('the scan comes back weekly and retries a failure after a day', () => {
  const { file, body } = newest('fn_marketing_competitor_scan');
  assert.match(body, /z\.requested_at > now\(\) - interval '7 days'/, `${file}: pages wait longer than a week`);
  assert.match(body, /z\.status = 'failed' and z\.requested_at > now\(\) - interval '1 day'/, `${file}: a failed page waits like a good one`);
  assert.match(body, /'feed', x\.social_handles->>'rss'/, `${file}: the competitor's public feed is not read`);
});
