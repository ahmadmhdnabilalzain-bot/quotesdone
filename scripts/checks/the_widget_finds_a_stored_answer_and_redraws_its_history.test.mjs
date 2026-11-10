// THE WIDGET FINDS A STORED ANSWER AND REDRAWS ITS HISTORY (customer_support, 2 Nov 2026; founder ledger 1464: the homepage
// widget, the sales engineer in the portals and customer support must never lose the conversation or start again).
//
// Found by the browser proof (scripts/e2e/conversation_continuity.mjs), read in the code:
//   1. ChatWidget threw on a reply that never arrived (a 504 page is not JSON; a stream cut after some sentences showed the
//      half-written text as the answer) and printed its error line over an answer the server HAD stored. The portal looked for
//      the stored answer (storedAnswer); the widget had no such loop. One loop, lookForStoredAnswer, now serves both.
//   2. ChatWidget marked its history "restored" BEFORE the call, so one failed call (a network blip, a 5xx) left the chat a bare
//      greeting for the whole visit while the server held every turn. It is marked only once the server answered.
//   3. The widget kept its own NDJSON reader, a second copy of portalReply.readReply; it now uses the portal's.
//
// Each rule has a known-bad control: the loop is shown finding the right answer AND refusing the wrong ones, and the source
// check is shown to fail on the pre-fix text of the widget.
//
//   node --test scripts/checks/the_widget_finds_a_stored_answer_and_redraws_its_history.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { lookForStoredAnswer, lookForStoredQuestion } from '../../src/lib/portalReply.ts';
import { readSource } from '../lib/portal_sources.mjs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
// a fake clock: sleeping advances it, so the loop runs in no time
const clock = () => { let t = 0; return { now: () => t, sleep: async (ms) => { t += ms; } }; };

test('the stored answer is found once the server has written it, after the question that asked it', async () => {
  const c = clock(); let reads = 0;
  const turns = () => { reads++; return reads < 3 ? [{ role: 'user', content: 'fee?' }] : [{ role: 'user', content: 'fee?' }, { role: 'assistant', content: 'Free, with a 3% reveal fee.' }]; };
  assert.equal(await lookForStoredAnswer(async () => turns(), 'fee?', { waitMs: 45000, everyMs: 5000, ...c }), 'Free, with a 3% reveal fee.');
  assert.equal(reads, 3);
});

test('KNOWN-BAD CONTROL: an older answer to the same words, or another question\'s answer, is never returned', async () => {
  const c = clock();
  // the question was asked twice; the first was answered, the second was not: the old answer must not be shown for the new ask
  const twice = [{ role: 'user', content: 'fee?' }, { role: 'assistant', content: 'OLD' }, { role: 'user', content: 'fee?' }];
  assert.equal(await lookForStoredAnswer(async () => twice, 'fee?', { waitMs: 20000, everyMs: 5000, ...c }), '');
  const other = [{ role: 'user', content: 'door?' }, { role: 'assistant', content: 'Sliding.' }];
  assert.equal(await lookForStoredAnswer(async () => other, 'fee?', { waitMs: 20000, everyMs: 5000, ...c }), '');
});

test('KNOWN-BAD CONTROL: a history read that fails or answers nothing is survived and ends in "", never a throw', async () => {
  assert.equal(await lookForStoredAnswer(async () => { throw new Error('network'); }, 'fee?', { waitMs: 20000, everyMs: 5000, ...clock() }), '');
  assert.equal(await lookForStoredAnswer(async () => null, 'fee?', { waitMs: 20000, everyMs: 5000, ...clock() }), '');
  assert.equal(await lookForStoredAnswer(async () => [], 'fee?', { waitMs: 20000, everyMs: 5000, ...clock() }), '');
});

test('"saved" is true only of a question the server holds; a blip is looked at twice; KNOWN-BAD: another question, or nothing, is not saved', async () => {
  const sleep = async () => {};
  assert.equal(await lookForStoredQuestion(async () => [{ role: 'user', content: ' door? ' }], 'door?', { sleep }), true);
  assert.equal(await lookForStoredQuestion(async () => [{ role: 'user', content: 'width?' }, { role: 'assistant', content: 'door?' }], 'door?', { sleep }), false, 'an assistant line is not the question');
  assert.equal(await lookForStoredQuestion(async () => [], 'door?', { sleep }), false);
  assert.equal(await lookForStoredQuestion(async () => { throw new Error('net'); }, 'door?', { sleep }), false);
  let n = 0;
  assert.equal(await lookForStoredQuestion(async () => (++n < 2 ? null : [{ role: 'user', content: 'door?' }]), 'door?', { sleep }), true, 'the second look finds it');
});

test('the portal says "saved" only after asking whether the question is stored', () => {
  const src = readSource('src/components/me/PortalShell.tsx');
  assert.match(src, /lookForStoredQuestion\(/);
  assert.match(src, /t\(stored \? 'asst_saved' : 'asst_not_sent'\)/);
});

test('the loop gives up at its time limit (it does not wait forever)', async () => {
  const c = clock(); let reads = 0;
  await lookForStoredAnswer(async () => { reads++; return []; }, 'x', { waitMs: 45000, everyMs: 5000, ...c });
  assert.equal(reads, 9);
});

// ── the widget's source ───────────────────────────────────────────────────────────────────────────────────────────────
export function widgetFaults(src) {
  const f = [];
  if (!/import \{[^}]*readReply[^}]*\} from '@\/lib\/portalReply'/.test(src)) f.push('does not read the reply with the portal\'s readReply');
  if (!/lookForStoredAnswer\(/.test(src)) f.push('does not look for the stored answer when a reply never arrives');
  if (/await r\.json\(\)/.test(src.split('const send')[1] || '')) f.push('send() still parses the reply with r.json(), which throws on a 504 page');
  if (/JSON\.parse\(line\)/.test(src)) f.push('keeps its own NDJSON reader (a second copy of readReply)');
  if (/restored\.current = true;\s*\n\s*fetch\(/.test(src)) f.push('marks the history restored before the server answered');
  if (!/restored\.current = true;/.test(src)) f.push('never marks the history restored');
  return f;
}

test('ChatWidget reads like the portal, looks for a stored answer, and marks history restored only after the server answered', () => {
  assert.deepEqual(widgetFaults(read('src/components/ChatWidget.tsx')), []);
});

test('KNOWN-BAD CONTROL: the pre-fix widget (its own reader, r.json(), restored before the call) is caught on every count', () => {
  const before = `
    const restore = () => {
      if (restored.current || !conv.current) return; restored.current = true;
      fetch(FN, {}).then((r) => r.json());
    };
    const send = async () => {
      const r = await fetch(FN);
      const e = JSON.parse(line);
      const j = await r.json();
    };`;
  const f = widgetFaults(before);
  for (const why of [/portal's readReply/, /stored answer/, /r\.json\(\)/, /own NDJSON reader/, /before the server answered/]) assert.ok(f.some((x) => why.test(x)), `not caught: ${why}`);
});

test('the portal uses the same loop, not a second copy of it', () => {
  const src = readSource('src/components/me/PortalShell.tsx');
  assert.match(src, /lookForStoredAnswer\(/);
  assert.doesNotMatch(src, /answerAfter\(/, 'PortalShell keeps its own copy of the lookup');
});
