// ONE CONTRACTOR OR SEPARATE QUOTES IS PRESELECTED FROM THE PLACEMENT, NEVER BY DEFAULT (sales_engineer; evidence run of
// 10 Nov 2026, ledger 1604, finding c). The PVC wall-panel brief named two trades and was sent as 'turnkey' by default.
//   node --test src/components/me/newRequest/combineDefault.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { combineDefaultOf } from './helpers.ts';
import { t as text } from '../portalText.ts';

test('separate quotes per trade unless the brief is a whole fit-out', () => {
  assert.equal(combineDefaultOf({ trades: ['interior-design', 'carpentry-joinery'] }), 'multi', 'the evidence run: two trades, not a whole fit-out');
  assert.equal(combineDefaultOf({ trades: ['hvac', 'electrical'], whole_scope: false }), 'multi');
  assert.equal(combineDefaultOf({ trades: ['fitout', 'gypsum', 'electrical', 'hvac'], whole_scope: true }), 'turnkey', 'a whole office fit-out');
  assert.equal(combineDefaultOf(null), 'multi');
});

test('both choices are explained in plain words, in English and formal Arabic, with no default label', () => {
  for (const lang of ['en', 'ar']) {
    const t = new Proxy({}, { get: (_o, k) => text(lang, String(k)) });
    for (const k of ['nr_multi_q', 'nr_multi_sep_h', 'nr_multi_sep_b', 'nr_multi_tk_h', 'nr_multi_tk_b', 'nr_posted_fallback', 'nr_posted_partial']) assert.ok(String(t[k] || '').trim(), `${lang}.${k}`);
    assert.doesNotMatch(t.nr_multi_tk_h + t.nr_multi_sep_h, /default|recommended|الافتراضي|موصى/, `${lang}: a choice is labelled as the default`);
    assert.match(t.nr_posted_fallback, /\{n\}/);
    assert.match(t.nr_posted_partial, /\{list\}/);
  }
});
