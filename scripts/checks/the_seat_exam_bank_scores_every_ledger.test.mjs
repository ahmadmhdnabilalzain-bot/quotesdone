// THE SEAT EXAM BANK SCORES EVERY LEDGER (27 Oct 2026, sales_engineer; founder ledger 893, 894, 899). Offline.
//
// Measured 27 Oct 2026: no exam item tested a trade's product distinctions, and no run reported a score per ledger.
// WHAT FAILS IF THE CAUSE RETURNS
//   * the trade bank names an entry no trade pack holds, an entry that is not served (unverified / low confidence),
//     another trade's entry, or a fact its entry does not hold (an item that could never be answered from knowledge);
//   * a bank item has fewer than two pre-written wordings, or a wording repeats the question (the exam rule: never the
//     same wording twice);
//   * the bank stops covering the trades with the most invited leads (the 20 measured 27 Oct 2026), or a trade deepened
//     that day has no item asked or held; a held item names only served entries (it should be asked) or would fail
//     validation once its entry is verified;
//   * `bank` hands out a wording already asked, or the source question; `score` stops reporting 893/899 for bank items
//     and 894 for seat-exam items.
//
//   node --test scripts/checks/the_seat_exam_bank_scores_every_ledger.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { bankFiles, bankItemsFor, validateBank, freshBankWording, scoreResults, ledgersOf } from '../eval/seat_exam_bank.mjs';
import { readPacks } from '../kb/verified_packs.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const entries = new Map(readPacks(join(REPO, 'knowledge')).filter((p) => p.kind === 'trade')
  .flatMap((p) => p.pack.entries.map((e) => [e.id, e])));

test('every bank item is answerable from a served trade-pack entry', () => {
  const banks = bankFiles();
  assert.ok(banks.length >= 1, 'no exam bank committed');
  for (const b of banks) assert.deepEqual(validateBank(b, entries), [], b.file);
});

// The six packs deepened on 27 Oct were checked against search-result excerpts only, so their new entries are stored
// verified=false (the 7 Oct stating rule: a fact not read on a page actually opened is never stated) and their items
// wait in held_items. Independent review of #1632, 27 Oct 2026.
const DEEPENED_27_OCT = ['joinery', 'flooring', 'cleaning', 'chemicals', 'pest_control', 'solar'];
test('the trade bank covers the top-lead trades, and the six deepened on 27 Oct wait in held_items', () => {
  const trades = new Set(bankItemsFor('sales_engineer').map((i) => i.trade));
  for (const t of ['security_systems', 'fire_fighting', 'steel', 'hvac', 'electrical', 'glazing', 'aluminium', 'gypsum'])
    assert.ok(trades.has(t), `no bank item for ${t}`);
  assert.ok(bankItemsFor('sales_engineer').every((i) => ledgersOf(i).includes(893) && ledgersOf(i).includes(899)));
  const held = bankFiles().flatMap((b) => b.held_items ?? []);
  for (const t of DEEPENED_27_OCT) assert.ok(held.some((i) => i.trade === t) || trades.has(t), `no item, asked or held, for ${t}`);
});

test('a held item waits only on an unverified entry, and is otherwise ready to ask', () => {
  for (const b of bankFiles()) {
    for (const it of b.held_items ?? []) {
      const ids = it.expected_entry_ids ?? [];
      assert.ok(ids.some((id) => entries.get(id)?.verified === false), `${it.id} is held but its entries are served: move it into items`);
      // the same validation as an asked item, with the entries treated as served (what it will be once verified)
      const asIfServed = new Map(ids.map((id) => [id, { ...entries.get(id), verified: true }]));
      assert.deepEqual(validateBank({ items: [it] }, asIfServed), [], it.id);
    }
  }
});

test('bank hands out a fresh wording, never the question or one already asked', () => {
  const it = { q_en: 'Q?', q_ar: 'س؟', q_reworded: 'R one', wordings: ['W two', 'W three'] };
  assert.equal(freshBankWording(it, []), 'R one');
  assert.equal(freshBankWording(it, ['r-one']), 'W two', 'punctuation and case do not make a used wording fresh');
  assert.equal(freshBankWording(it, ['R one', 'W two', 'W three']), null);
  assert.equal(freshBankWording({ q_en: 'Same', q_reworded: 'same' }, []), null);
});

test('score reports 893/899 for bank items and 894 for seat-exam items', () => {
  const items = { a: { ledger: [893, 899] }, b: {} };
  const s = scoreResults([{ id: 'a', seat: 'sales_engineer', pass: true }, { id: 'b', seat: 'sales_engineer', pass: false }], (id) => items[id]);
  assert.deepEqual(s.ledgers['893'], { asked: 1, passed: 1, rate: 1 });
  assert.deepEqual(s.ledgers['894'], { asked: 1, passed: 0, rate: 0 });
  assert.deepEqual(s.seats.sales_engineer, { asked: 2, passed: 1, rate: 0.5 });
});

test('the validator refuses an unanswerable item (control for the first test)', () => {
  const e = new Map([['flooring:x', { body_en: 'porcelain is 0.5%', confidence: 'medium' }]]);
  const ok = { id: 'i', trade: 'flooring', q_en: 'q', q_ar: 'س', wordings: ['a', 'b'], answer_must: ['m'], expected_entry_ids: ['flooring:x'], expected_facts: ['0.5%'] };
  assert.deepEqual(validateBank({ items: [ok] }, e), []);
  assert.match(validateBank({ items: [{ ...ok, expected_facts: ['3%'] }] }, e).join(), /not in its expected entry/);
  assert.match(validateBank({ items: [{ ...ok, expected_entry_ids: ['flooring:nope'] }] }, e).join(), /not in any trade pack/);
  assert.match(validateBank({ items: [{ ...ok, wordings: ['a', 'A'] }] }, e).join(), /repeats/);
  assert.match(validateBank({ items: [ok] }, new Map([['flooring:x', { body_en: 'porcelain is 0.5%', verified: false }]])).join(), /not served/);
});
