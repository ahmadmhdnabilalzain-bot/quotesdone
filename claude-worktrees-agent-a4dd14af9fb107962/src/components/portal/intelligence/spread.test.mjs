// The quote-spread figure is money shown to a paying customer, and the trend chart is the surface
// that must refuse to draw a flat line over an empty year. Both live in stats.ts so they can be
// executed rather than only rendered. Node 24 strips the types, so this runs with no framework and
// no build step:
//
//   node --test src/components/portal/intelligence/spread.test.mjs
//   npm test        (the repository runner discovers *.test.mjs anywhere in the tree)
import test from 'node:test';
import assert from 'node:assert/strict';
import { countByCategory, spreadByCategory, summariseHistory, monthLabel } from './stats.ts';

test('one month of history is "single", never "rising" (audit 21 Sep 2026)', () => {
  assert.equal(summariseHistory(twelve([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2])).direction, 'single');
  assert.equal(summariseHistory(twelve([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2])).direction, 'rising');
});
test('the RPC month label reads in Arabic on an Arabic page and untouched otherwise', () => {
  assert.equal(monthLabel('Sep 26', 'en'), 'Sep 26');
  assert.match(monthLabel('Sep 26', 'ar'), /سبتمبر/);
  assert.equal(monthLabel('M3', 'ar'), 'M3');
});

const twelve = (counts) => counts.map((c, i) => ({ month: 'M' + i, inquiries: c }));

test('an all-zero year is not a trend — production is exactly this case', () => {
  assert.equal(summariseHistory(twelve([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])), null);
});

test('a missing series is also refused', () => {
  assert.equal(summariseHistory(null), null);
  assert.equal(summariseHistory([]), null);
});

test('a real year reports its total, peak and direction', () => {
  const s = summariseHistory(twelve([1, 0, 0, 0, 0, 0, 2, 0, 0, 3, 0, 0]));
  assert.equal(s.total, 6);
  assert.equal(s.direction, 'rising'); // later half 5 vs earlier half 1
  assert.deepEqual(s.peak, { month: 'M9', inquiries: 3 });
  assert.equal(s.points.length, 12);
});

test('direction is steady when both halves match, not silently rising', () => {
  assert.equal(summariseHistory(twelve([2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2])).direction, 'steady');
  assert.equal(summariseHistory(twelve([5, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0])).direction, 'falling');
});

test('a request with one quote contributes nothing — one quote is not a comparison', () => {
  const r = spreadByCategory([{ category: 'Electrical', quotes: [{ price: 10000 }] }], 'Not categorised');
  assert.equal(r.counted, 0);
  assert.equal(r.total, 0);
  assert.deepEqual(r.rows, []);
});

test('spread is highest minus lowest, summed per category', () => {
  const r = spreadByCategory(
    [
      { category: 'Electrical', quotes: [{ price: 10000 }, { price: 14000 }, { price: 12000 }] },
      { category: 'Electrical', quotes: [{ price: 500 }, { price: 1500 }] },
      { category: 'Steel', quotes: [{ price: 90000 }, { price: 100000 }] },
    ],
    'Not categorised',
  );
  assert.equal(r.counted, 3);
  assert.equal(r.total, 15000); // 4000 + 1000 + 10000
  assert.deepEqual(r.rows, [
    { category: 'Steel', spread: 10000, requests: 1 },
    { category: 'Electrical', spread: 5000, requests: 2 },
  ]);
});

test('combined projects contribute through their children, not zero', () => {
  const r = spreadByCategory(
    [
      {
        category: 'Fit-out',
        quotes: [],
        children: [
          { category: 'Electrical', quotes: [{ price: 1000 }, { price: 4000 }] },
          { category: 'Plumbing', quotes: [{ price: 2000 }, { price: 2500 }] },
        ],
      },
    ],
    'Not categorised',
  );
  assert.equal(r.counted, 2);
  assert.equal(r.total, 3500);
});

test('null, zero and non-numeric prices are dropped rather than read as AED 0', () => {
  const r = spreadByCategory(
    [{ category: 'Steel', quotes: [{ price: null }, { price: 0 }, { price: 'x' }, { price: 5000 }] }],
    'Not categorised',
  );
  assert.equal(r.counted, 0); // only one usable price survives, so there is no comparison
});

test('a blank category is labelled, never dropped or shown empty', () => {
  const r = spreadByCategory([{ category: '  ', quotes: [{ price: 100 }, { price: 300 }] }], 'Not categorised');
  assert.deepEqual(r.rows, [{ category: 'Not categorised', spread: 200, requests: 1 }]);
  assert.deepEqual(countByCategory([{ category: null }], 'Not categorised'), [
    { category: 'Not categorised', requests: 1 },
  ]);
});

test('category counts come back biggest first', () => {
  const rows = countByCategory(
    [{ category: 'A' }, { category: 'B' }, { category: 'B' }, { category: 'B' }, { category: 'A' }, { category: 'C' }],
    'Not categorised',
  );
  assert.deepEqual(rows, [
    { category: 'B', requests: 3 },
    { category: 'A', requests: 2 },
    { category: 'C', requests: 1 },
  ]);
});
