// THE SERVICES TAB COUNTS ONCE, KEEPS OWN WORDS, AND REMOVES A TRADE FOR REAL. Seat: it_engineer.
// Audit 21 Sep 2026 (ZZ DEMO Interiors, gypsum):
//   9.  a "kept in your own words" phrase vanished after Update + reload — the tab ignored
//       extra_services and the next Update sent only the preview's words;
//   10. "Remove this trade" came back after Update + reload, and removed instantly with no undo;
//   11. "8 services" after a rewrite whose services were already ticked, "5" after reload.
// The server half of 9 and 10 is replayed in supabase/functions/_shared/supplier_services_save.test.ts;
// this file holds the tab to the same rules. Node strips the types from servicesCopy.ts on import.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const TAB = fs.readFileSync(path.join(ROOT, 'src/components/portal/supplier/ServicesTab.tsx'), 'utf8');
const { countServices, SERVICES_COPY } = await import(new URL('../../src/components/portal/supplier/servicesCopy.ts', import.meta.url).href);
const AR = /[؀-ۿ]/;

test('finding 11: the audit numbers — five ticked, a rewrite repeating them, counts 5 before AND after reload', () => {
  const ticked = ['gypsum.false_ceiling', 'gypsum.partitions', 'gypsum.plastering', 'gypsum.decorative', 'gypsum.acoustic_ceiling'];
  const rwStated = ['gypsum.false_ceiling'];                                   // already ticked
  const rwImplied = ['gypsum.partitions', 'gypsum.acoustic_ceiling', 'gypsum.decorative'];  // already ticked
  const before = countServices([...ticked, ...rwStated, ...rwImplied], []);
  // What the server stores: stated = the union of ticks and the rewrite; implied = implied minus stated.
  const stated = [...new Set([...ticked, ...rwStated])];
  const implied = rwImplied.filter((k) => !stated.includes(k));
  const after = countServices([...stated, ...implied], []);
  assert.equal(before, 5);
  assert.equal(after, before);
});

test('finding 11: own words count once however they are written', () => {
  assert.equal(countServices(['a.b'], ['Pool heating', 'pool  heating', 'POOL HEATING']), 2);
});

test('finding 11: the tab counts through countServices, not by adding list lengths', () => {
  assert.match(TAB, /svcCount = countServices\(/);
  assert.doesNotMatch(TAB, /statedKeys\.length \+ rwImplied\.length/);
  // A plain Update without a rewrite keeps the stored implications instead of sending [].
  assert.match(TAB, /rw \? rw\.implied\.map\(\(i\) => i\.key\) : d\.implied_services/);
});

test('finding 9: saved own words are read from extra_services, shown, and re-sent on save', () => {
  assert.match(TAB, /const savedOwn = d\.extra_services/);
  assert.match(TAB, /savedOwn\.map\(/, 'the saved words are rendered');
  assert.match(TAB, /\[\.\.\.savedOwn, \.\.\.\(rw\?\.own_words \|\| \[\]\)\]/, 'and merged into own_words for the save');
  assert.match(TAB, /sc\(lang, 'under_review'\)/);
});

test('finding 10: removal is held with an Undo and sent as removed_trades', () => {
  assert.match(TAB, /removed_trades: \[\.\.\.removedTrades\]/);
  assert.match(TAB, /trades: activeTrades/);
  assert.match(TAB, /sc\(lang, 'undo'\)/);
  assert.match(TAB, /removeTrade\(code, false\)/, 'the Undo puts the trade back');
});

test('the new words exist in English and in Arabic', () => {
  for (const k of ['trade_removed', 'undo', 'under_review']) {
    assert.ok(SERVICES_COPY.en[k] && !AR.test(SERVICES_COPY.en[k]), `en.${k}`);
    assert.ok(SERVICES_COPY.ar[k] && AR.test(SERVICES_COPY.ar[k]), `ar.${k}`);
  }
});
