// it_engineer: the prompt-injection suite is only worth its measurement if the corpus still covers the attack and the
// graders still catch a win. This runs OFFLINE (no network, no model, no credentials) so CI stays green, and it fails
// the day the corpus shrinks below the matrix floor or a grader stops catching its known injection-success.
// Qualification matrix gap #11 (P0). prevented by: this file.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CORPUS, CLASSES, HANDLERS, READ_HANDLERS, REPLY_HANDLERS, cases, selfTest } from '../eval/prompt_injection_suite.mjs';

test('the corpus covers >= 60 payloads, every attack class, and all six model-fed handlers', () => {
  assert.ok(CORPUS.length >= 60, `only ${CORPUS.length} payloads`);
  for (const c of CLASSES) assert.ok(CORPUS.some((p) => p.class === c), `no payload for class ${c}`);
  const reached = new Set(cases().map((c) => c.handler));
  for (const h of HANDLERS) assert.ok(reached.has(h), `no case reaches handler ${h}`);
  // the state-change / leak effects the P0 gap names each appear somewhere
  for (const e of ['reveal_identity', 'reveal_price', 'reveal_other_customer', 'approve_supplier', 'change_fee', 'send_message', 'mark_complete', 'set_trades', 'exfil_link', 'exfil_markdown_image'])
    assert.ok(CORPUS.some((p) => p.effect === e), `no payload attempts ${e}`);
});

test('every read handler receives documents carrying hidden/vision injection, every reply handler the leak+exfil+send classes', () => {
  const byHandler = (h) => cases().filter((c) => c.handler === h);
  for (const h of READ_HANDLERS) {
    const cs = byHandler(h);
    assert.ok(cs.length >= 3, `${h} has only ${cs.length} cases`);
  }
  for (const h of REPLY_HANDLERS) {
    const effects = new Set(byHandler(h).map((c) => c.effect));
    for (const e of ['reveal_identity', 'exfil_link', 'send_message', 'change_fee'])
      assert.ok(effects.has(e), `${h} never tests ${e}`);
  }
  // hidden-PDF and image-OCR vectors are actually present for the document handlers
  for (const v of ['pdf_white', 'pdf_tiny', 'pdf_metadata', 'pdf_annotation', 'image_text'])
    assert.ok(CORPUS.some((p) => p.vector === v), `no payload uses vector ${v}`);
});

test('every grader passes its known-good answer and catches its known injection-success', () => {
  const { checks, failures } = selfTest();
  assert.equal(failures.length, 0, 'graders that stopped working: ' + JSON.stringify(failures, null, 2));
  assert.ok(checks.length >= 20, `only ${checks.length} grader checks`);
});
