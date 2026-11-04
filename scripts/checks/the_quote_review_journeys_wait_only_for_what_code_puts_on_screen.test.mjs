// THE QUOTATION-REVIEW JOURNEYS WAIT ONLY FOR WHAT CODE PUTS ON SCREEN (sales_engineer, 3 Nov 2026).
// Since rulings 1195-1197 (#1335, 13 Oct 2026) every engineer bubble in the supplier's quotation chat is written by a
// model, so no sentence of it is fixed. #1566 (19 Oct) made scripts/e2e/supplier_quote_review.mjs wait for
// /is open for your quotation/, a wording no branch of the product ever had, and journey_audit_buttons.mjs waited for
// 'I am the QuotesDone sales engineer' and 'Before it can be submitted' (engineer facts the model rewrites): both timed
// out on every nightly run from 14 Oct to 3 Nov (41598217377). This reads both harnesses and asserts that every text
// they wait for inside the chat — chat.getByText('…'), chat.getByText(/…/), the state badge — is the component's own
// copy (QuoteReviewChat.tsx, quoteReviewApi.ts). Offline, over the source.
//   node --test scripts/checks/the_quote_review_journeys_wait_only_for_what_code_puts_on_screen.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const UI = readFileSync('src/components/portal/supplier/QuoteReviewChat.tsx', 'utf8') + readFileSync('src/components/portal/supplier/quoteReviewApi.ts', 'utf8');
const HARNESSES = ['scripts/e2e/supplier_quote_review.mjs', 'scripts/e2e/journey_audit_buttons.mjs'];
// The first argument of a wait inside the chat: chat.getByText('…' | L('…', …) | /…/), badge('…'), reviewBadge(chat, '…').
const WAIT = /(?:chat\.getByText\(\s*(?:L\(\s*)?|\bbadge\(\s*|reviewBadge\(\s*chat,\s*)(?:'((?:[^'\\]|\\.)*)'|\/((?:[^/\\\n]|\\.)+)\/[a-z]*)/g;

for (const file of HARNESSES) {
  test(`${file}: every text it waits for in the review chat is the component's copy, never the model's words`, () => {
    const src = readFileSync(file, 'utf8');
    const waits = [...src.matchAll(WAIT)];
    assert.ok(waits.length > 0, 'found no waits inside the chat: the pattern no longer reads this harness');
    const foreign = waits.filter(([, lit, re]) => (lit != null ? !UI.includes(lit) : !new RegExp(re).test(UI))).map(([w]) => w);
    assert.deepEqual(foreign, [], 'these waits look for text the chat component never renders (model-written or stale copy)');
  });
}

test("the engineer's bubbles are counted by the label the component gives them", () => {
  assert.match(UI, /engineer: 'Sales engineer'/);
  assert.match(UI, /\{eng \? t\.engineer : t\.you\} · /, "the bubble label is no longer 'Sales engineer · <time>'");
  for (const file of HARNESSES) assert.match(readFileSync(file, 'utf8'), /filter\(\{ hasText: \/\^Sales engineer · \/ \}\)/, `${file} no longer counts the engineer's bubbles by their label`);
});
