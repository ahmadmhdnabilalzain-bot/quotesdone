// composer_waits_for_the_thread.test.mjs
// node --test src/components/portal/comms/composer_waits_for_the_thread.test.mjs
// Reproduced by hand on production 22 Sep 2026 (ZZ DEMO customer, demo supplier 126512, the chat row
// removed so the first `thread` read opened it, as after a fresh reveal): the textarea first shown was
// "What would you like to ask?"; after the thread answered it was the composer, EMPTY, with Send
// disabled — the typed message was gone. The journey's "Messages after the reveal: write and send"
// recorded the same as "no request in 30 s". The typing area must not exist until the thread answered.
// The journey step (scripts/e2e/journey_audit_buttons.mjs) replays it end to end; this pins the cause.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const src = readFileSync(join(import.meta.dirname, 'CommunicationCenter.tsx'), 'utf8');

test('the compose/ask area renders nothing before the thread has answered', () => {
  const at = src.indexOf("status === 'open' ? (");
  assert.ok(at > 0, 'the compose branch was not found');
  assert.match(src.slice(at - 40, at), /\{!data \? null : $/, 'the compose branch is not gated on the thread having loaded');
});
