// THE REQUEST TRACKER READS EACH STAGE FROM THE SERVER'S OWN FIELDS (T2, sales_engineer, 5 Oct 2026).
// Executes src/components/me/requestTracker.ts against the shapes customer_api my_inquiries serves.
// Fails if a stage is claimed without its fact, a held request is shown as sent, a reveal is shown
// as a hire, a timestamp is invented, a supplier name can enter a label, or the portal stops
// rendering it as an ordered list with aria-current="step".
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { trackerOf } from '../../src/components/me/requestTracker.ts';

const keyOf = (tr) => tr.stages[tr.current]?.key ?? 'complete';

test('a fresh sent request is waiting on quotes, with the match count and the posted time only', () => {
  const tr = trackerOf({ status: 'sent', rfq_ready: true, matched_suppliers: 4, created_at: '2026-10-01T08:00:00Z', stage_changed_at: '2026-10-02T08:00:00Z' }, [], 'en');
  assert.equal(keyOf(tr), 'quotes');
  assert.equal(tr.stages.find((s) => s.key === 'sent').label, 'Sent to 4 matching suppliers');
  assert.equal(tr.stages[0].at, '2026-10-01T08:00:00Z');
  assert.ok(tr.stages.slice(1).every((s) => s.at === null), 'a timestamp was invented for a stage the server did not record');
  assert.match(tr.next, /quotes/);
});

test('a request held for specs stops at the specs stage and says what to do', () => {
  const tr = trackerOf({ status: 'sent', rfq_ready: false, matched_suppliers: 3 }, [], 'en');
  assert.equal(keyOf(tr), 'specs');
  assert.equal(tr.held, true);
  assert.equal(tr.stages[1].label, 'Held for specs');
  assert.equal(tr.stages.find((s) => s.key === 'sent').done, false, 'a held request is shown as sent');
});

test('one quote is not a comparison; two are', () => {
  assert.equal(keyOf(trackerOf({ status: 'quoted' }, [{}], 'en')), 'compare');
  const two = trackerOf({ status: 'quoted' }, [{}, {}], 'en');
  assert.equal(keyOf(two), 'revealed');
  assert.equal(two.stages.find((s) => s.key === 'quotes').label, 'Quotes received (2)');
});

test('a reveal lights Revealed with its own time and is not a hire', () => {
  const tr = trackerOf({ status: 'quoted' }, [{ revealed: true, revealed_at: '2026-10-03T10:00:00Z' }, {}], 'en');
  assert.equal(keyOf(tr), 'done');
  assert.equal(tr.stages.find((s) => s.key === 'revealed').at, '2026-10-03T10:00:00Z');
});

test('a single quote that is revealed and hired is not stalled at Compare (#761 with one quote)', () => {
  const rev = trackerOf({ status: 'quoted' }, [{ revealed: true }], 'en');
  assert.equal(rev.stages.find((s) => s.key === 'revealed').done, true);
  const hired = trackerOf({ status: 'completed', hired_supplier_id: 'x' }, [{ revealed: true }], 'en');
  assert.equal(keyOf(hired), 'complete');
});

test('a request with quotes is never shown as held for specs', () => {
  const tr = trackerOf({ status: 'quoted', rfq_ready: false }, [{}], 'en');
  assert.equal(tr.held, false);
  assert.equal(keyOf(tr), 'compare');
});

test('hire then review completes the tracker', () => {
  const hired = trackerOf({ status: 'completed', hired_supplier_id: 'x', pipeline_stage: 'won', stage_changed_at: '2026-10-04T00:00:00Z' }, [{ revealed: true }, {}], 'en');
  assert.equal(keyOf(hired), 'complete');
  assert.equal(hired.stages[6].at, '2026-10-04T00:00:00Z');
  assert.match(hired.next, /rate/);
  const rated = trackerOf({ status: 'completed', hired_supplier_id: 'x' }, [{ revealed: true, rated: true }, {}], 'en');
  assert.equal(rated.stages[6].label, 'Job done · Reviewed');
});

test('a cancelled request says it is closed; Arabic is served in Arabic', () => {
  assert.equal(trackerOf({ status: 'cancelled' }, [], 'en').closed, true);
  const ar = trackerOf({ status: 'sent', matched_suppliers: 2 }, [], 'ar');
  assert.match(ar.stages[0].label, /[؀-ۿ]/);
  assert.match(ar.next, /[؀-ۿ]/);
});

test('no quote field can put a supplier name into a stage label', () => {
  const tr = trackerOf({ status: 'quoted' }, [{ revealed: true, supplier_name: 'ZZ DEMO Glass LLC', label: 'Supplier A' }, {}], 'en');
  assert.ok(!JSON.stringify(tr).includes('ZZ DEMO'), 'a supplier name reached the tracker');
});

test('the portal renders it as an ordered list with aria-current="step"', () => {
  const src = readFileSync(new URL('../../src/components/me/CustomerPortal.tsx', import.meta.url), 'utf8');
  const fn = src.match(/function RequestTracker\(([\s\S]*?)\n\}\n/);
  assert.ok(fn, 'RequestTracker not found');
  assert.match(fn[1], /<ol\b/);
  assert.match(fn[1], /aria-current=\{st\.current \? 'step'/);
  assert.match(src, /<RequestTracker inq=\{inq\} quotes=\{quotes\}/);
});
