// ONE CONTRACTOR OR SEPARATE QUOTES IS ASKED, NEVER SILENT (sales_engineer; evidence run of 10 Nov 2026, ledger 1604,
// finding c). The PVC wall-panel brief named two trades and was sent as 'turnkey' without the customer seeing the choice.
// Both choices are shown; one contractor is preselected (standing rulings 1021, 1025).
//   node --test src/components/me/newRequest/combineDefault.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { combineDefaultOf } from './helpers.ts';
import { t as text } from '../portalText.ts';

test('one contractor is preselected for every multi-trade brief (ruling 1025), whatever the placement', () => {
  for (const b of [{ trades: ['interior-design', 'carpentry-joinery'] }, { trades: ['hvac', 'electrical'], whole_scope: false }, { trades: ['fitout', 'gypsum'], whole_scope: true }, null])
    assert.equal(combineDefaultOf(b), 'turnkey');
});

test('both choices are explained in plain words, in English and formal Arabic, with no default label', () => {
  for (const lang of ['en', 'ar']) {
    const t = new Proxy({}, { get: (_o, k) => text(lang, String(k)) });
    for (const k of ['nr_multi_q', 'nr_multi_sep_h', 'nr_multi_sep_b', 'nr_multi_tk_h', 'nr_multi_tk_b', 'nr_posted_partial', 'nr_separate_ask', 'nr_separate_yes', 'nr_separate_done', 'nr_separate_fail']) assert.ok(String(t[k] || '').trim(), `${lang}.${k}`);
    assert.doesNotMatch(t.nr_multi_tk_h + t.nr_multi_sep_h, /default|recommended|الافتراضي|موصى/, `${lang}: a choice is labelled as the default`);
    assert.match(t.nr_separate_ask, /\{n\}/);
    assert.match(t.nr_posted_partial, /\{list\}/);
  }
});
