// EVERY SEAT CARD COMES FROM ITS PACK (ceo, ledger 1003 stage 2, 19 Oct 2026). knowledge/brief/seats/<seat>.md is the
// seat's operating-facts card that think() puts in the cached prefix of every INTERNAL call (compile_brief.mjs). It
// must be (1) what the pack compiles to now, byte for byte, so it caches and never drifts from the pack; (2) every
// line a verbatim sentence of the entry it names, so no fact enters a card that the pack does not hold (an exam answer
// pasted into a card fails here); (3) within budget; (4) internal only -- the public brief never carries a card.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { CARD_BUDGET, SEATS, cardSentences, isOwnEntry, renderModule, compileBrief, seatCard, writeSeatCards } from '../kb/compile_brief.mjs';

const REPO = join(import.meta.dirname, '..', '..');
const pack = (s) => JSON.parse(readFileSync(join(REPO, 'knowledge/seats', s + '.json'), 'utf8'));

test('each card is what its pack compiles to, and compiling twice gives the same bytes', () => {
  assert.deepEqual(writeSeatCards(true), [], 'stale card: run node scripts/kb/compile_brief.mjs');
  for (const s of SEATS) assert.equal(seatCard(s).text, seatCard(s).text, s);
});

test('every card line is a sentence of the own-fact entry it names, and the card fits the budget', () => {
  for (const s of SEATS) {
    const byId = new Map(pack(s).entries.map((e) => [e.id, e]));
    const text = seatCard(s).text;
    assert.ok(text.length <= CARD_BUDGET, `${s}: ${text.length} chars`);
    const lines = text.split('\n').slice(1);
    assert.equal(new Set(lines).size, lines.length, s + ': duplicate line');
    for (const l of lines) {
      const m = l.match(/^- (.+) \[([^\]]+)\]$/);
      assert.ok(m, `${s}: untraceable line: ${l}`);
      const e = byId.get(m[2]);
      assert.ok(e && isOwnEntry(e), `${s}: ${m[2]} is not an own-fact entry of the pack`);
      assert.ok(cardSentences(e.body_en).includes(m[1]), `${s}: not a sentence of ${m[2]}: ${m[1]}`);
    }
  }
});

test('a fact the pack does not hold never reaches a card', () => {
  const fake = { entries: [{ id: 'x:1', kind: 'company', body_en: 'The Resend cap is 50000 emails a month.' }, { id: 'x:2', kind: 'law', body_en: 'VAT is due every quarter at 5%.' }] };
  assert.equal(seatCard('x', fake).text.split('\n').length, 2, 'only the company entry is carried');
  assert.equal(seatCard('x', { entries: [] }).text, '');
});

test('the it_engineer card carries the cap the after-exam said was "not established"', () => {
  assert.match(seatCard('it_engineer').text, /cap_resend_emails_month 50000.*\[it_engineer:otp-usage-provider-watch\]/);
});

test('the external brief carries no card; only SEAT_CARDS does', () => {
  const mod = renderModule(compileBrief());
  const ext = JSON.parse(mod.match(/export const SEAT_FACTS_EXTERNAL: string = (".*");\n/)[1]);
  // since 3 Nov 2026 the public brief is the core (BRIEF_TEXT), the supplier part and the trade-pack parts: all three are checked
  const brief = [JSON.parse(mod.match(/export const BRIEF_TEXT: string = (".*");\n/)[1]), JSON.parse(mod.match(/export const BRIEF_SUPPLIER: string = (".*");\n/)[1]),
    ...JSON.parse(mod.match(/export const BRIEF_PART_TEXT: string\[\] = (.*);\n/)[1])].join('\n');
  for (const s of SEATS) {
    const first = seatCard(s).text.split('\n')[1];
    if (!first) continue;
    assert.ok(!ext.includes(first) && !brief.includes(first), s + ': a card line leaked into a public brief');
  }
});
