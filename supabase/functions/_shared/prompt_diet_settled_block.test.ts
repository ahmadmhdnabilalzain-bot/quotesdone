// The settled facts ride as the block every seat shares plus the seat's own card (think/settled.ts splitSettled, think/deps.ts
// cachedHalves; prompt diet 'settled_facts_ride_as_one_shared_cache_block'). Structural: the bytes sent are unchanged.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { settledFacts, splitSettled } from './think/settled.ts';
import { cachedHalves } from './think/deps.ts';
import { approxTokens } from './company_brief.ts';
import { SEATS } from './think/types.ts';

Deno.test('shared + stable is byte-identical to the settled facts, for every seat and audience', () => {
  for (const a of ['internal', 'founder', 'customer', 'supplier', 'visitor']) for (const s of [...SEATS, null]) {
    const f = settledFacts(a, s);
    const h = splitSettled(f);
    assertEquals(h.shared + h.stable, f, a + '/' + s);
    assert(h.shared.length > 0, 'a settled-facts prefix always has a shared head');
  }
});

Deno.test('every seat shares ONE head; only the card is the seat\'s own, and it is the smaller part', () => {
  const heads = new Set(SEATS.map((s) => splitSettled(settledFacts('internal', s)).shared));
  assertEquals(heads.size, 1, 'one shared block for every seat');
  const head = [...heads][0];
  for (const s of SEATS) {
    const card = splitSettled(settledFacts('internal', s)).stable;
    assert(approxTokens(card) < approxTokens(head), s + ': the card is smaller than the shared head');
  }
  // the founder's rulings and the company facts live in the shared head: they reach every seat's prompt
  for (const fact of ['Mashreq', 'AED 375,000', 'decided by the CEO seat']) assert(head.includes(fact), fact);
  // an outside audience gets its own shared head, and never the internal one
  assertEquals(splitSettled(settledFacts('customer')).stable, '');
  assert(!splitSettled(settledFacts('customer')).shared.includes('Mashreq'));
});

Deno.test('the switch decides how the halves travel; a caller that names its own shared block is left alone', () => {
  const f = settledFacts('internal', 'it_engineer');
  const on = cachedHalves({ sysStable: f, taskClass: 'internal_judgement' }, {});
  assert(on.sysShared && on.sysShared.length > 0);
  assertEquals((on.sysShared ?? '') + on.sysStable, f);
  const off = cachedHalves({ sysStable: f }, { settled_facts_ride_as_one_shared_cache_block: false });
  assertEquals(off, { sysStable: f }, 'switched off: one block, as before');
  const brief = cachedHalves({ sysStable: 'the trade pack', sysShared: 'the core brief' }, {});
  assertEquals(brief, { sysShared: 'the core brief', sysStable: 'the trade pack' });
  assertEquals(cachedHalves({ sysStable: 'some other stable text' }, {}), { sysStable: 'some other stable text' });
  assertEquals(cachedHalves({}, {}), { sysStable: '' });
});
