// sales_engineer: the request chat's reply is written by the model; a code-written reply only when OpenRouter is down.
// Founder ruling, 27 Oct 2026 ~14:15Z (founder_instruction 1339), verbatim:
//   "the engineer and customer support never replies without llm unless the server of open router is down"
//
// WHAT WAS MEASURED (27 Oct 2026, read from inquiry_intake on main 2f204b792 and on #1646 at c339107d7): code composed
// the customer's text on the normal path while a model was up — replyFromState when the slots or the canonical gate
// disagreed with the model's status, the "Thanks, noted. A few quick questions…" lead before the four sales-engineer
// questions, the drawing confirm question and the CAD ask appended to the reply, HELD_FOR_SPECS and its code list of
// open questions whenever aiReply gave '' (which also means "the model answered and was refused"), the
// held-for-trade notice, and the deterministic interview whenever the model's JSON did not parse.
//
// THE RULES, read from the source with comments stripped (a comment describing a pattern never trips them):
//   R1  no `reply || <code text>` fallback in the intake files without an outage gate on the line;
//   R2  index.ts voices every code draft through intakeVoice (slots.ts) on clock.replyDeadline(), after the last code
//       draft and before the reply is saved, and sends the draft itself only `if (llmDown)`; a guard refusal goes back
//       to the model (voice(replyFromState(…))); the held-for-trade return is voiced too; llmDown is the OpenRouter-down
//       test (_shared/openrouter_down.ts);
//   R3  slots.ts sends its code text (the held list, the intake draft) only when replyDown() says OpenRouter was down.
// Each rule has a KNOWN-BAD CONTROL: the line the code carried before this fix must fail it.
// prevented by: this file, inquiry_intake/slots.test.ts (the 1339 tests), _shared/openrouter_down.test.ts.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => fs.readFileSync(path.join(REPO, 'supabase', 'functions', 'inquiry_intake', p), 'utf8');
const strip = (src) => src.split('\n').map((l) => (/^\s*(\/\/|\*|\/\*)/.test(l) ? '' : l.replace(/\s\/\/\s.*$/, '')));
const GATE = /outage|Outage|llmDown|replyDown|modelOrOutage/;

/** R1: a code fallback after a model reply, with no outage gate on the line. */
export function fallbackFindings(file, src) {
  return strip(src).flatMap((l, i) =>
    /(?:\b\w+\??\.reply|(?<![.\w])(?:reply|hr|text))\s*\|\|\s*(?:['"`][^'"`\n]{12,}|[A-Z][A-Z0-9_]{3,}\b|`\$\{|(?:replyFromState|heldDraftOf)\()/.test(l) && !GATE.test(l)
      ? [`${file}:${i + 1}: R1 code fallback after a model reply, no outage gate: ${l.trim().slice(0, 140)}`] : []);
}

/** R2: index.ts voices every code draft; the draft only on an outage. */
export function indexFindings(src) {
  const code = strip(src).join('\n');
  const out = [];
  const voiceDef = code.indexOf('const voice = async (draftMsg: string) =>');
  const save = code.search(/for \(let i = turns\.length - 1; i >= 0; i--\) if \(turns\[i\] && turns\[i\]\.role === 'assistant'\) \{ turns\[i\]\.text = out\.assistant_message/);
  if (voiceDef < 0) out.push('R2 the final reply is never voiced by the model (no voice step)');
  if (save < 0) out.push('R2 the reply save loop moved; re-anchor this check');
  if (voiceDef >= 0 && save >= 0 && voiceDef > save) out.push('R2 the voice step runs after the reply is saved');
  if (!/if \(llmDown\) \{ replyBy = 'outage_fallback'; return draftMsg; \}/.test(code)) out.push('R2 the code draft is not gated on llmDown');
  if (!/const v = await intakeVoice\(defaultDeps\(admin, 'inquiry_intake'\), \{[\s\S]{0,400}?deadline: clock\.replyDeadline\(\)/.test(code)) out.push('R2 the voice step is not on the reply deadline');
  if (!/if \(draftMsg && draftMsg !== String\(modelWrote \?\? ''\)\.trim\(\)\) out\.assistant_message = await voice\(draftMsg\);/.test(code)) out.push('R2 a code-composed reply is not voiced');
  if (!/out\.assistant_message = await voice\(replyFromState\(/.test(code)) out.push('R2 a guard refusal is not sent back to the model');
  if (!/const hv = llmDown \?[^;]*: await intakeVoice\(/s.test(code)) out.push('R2 the held-for-trade reply is not voiced by the model');
  if (!/let llmDown = !llmCallOk && isOpenRouterDown\(/.test(code)) out.push('R2 llmDown is not the OpenRouter-down test');
  if (voiceDef >= 0) {
    // every code draft is assigned before the voice step runs; after it only the model's words (voice, the guard's edit)
    const runAt = code.indexOf("if (draftMsg && draftMsg !== String(modelWrote ?? '').trim()) out.assistant_message = await voice(draftMsg);");
    const late = [...code.matchAll(/out\.assistant_message\s*=(?!=)([^;\n]*)/g)]
      .filter((m) => runAt >= 0 && m.index > runAt && !/^\s*(await voice\(|guarded\.text)/.test(m[1]));
    if (late.length) out.push('R2 a code draft is assigned after the voice step: ' + late.map((m) => m[0].slice(0, 80)).join(' | '));
  }
  return out;
}

/** R3: slots.ts returns its code text only when OpenRouter was down. */
export function slotsFindings(src) {
  const code = strip(src).join('\n');
  const out = [];
  if (!/return replyDown\(r\) \? \{ text: heldDraftOf\(/.test(code)) out.push('R3 heldReply returns its code list without replyDown');
  if (!/return replyDown\(r\) \? \{ text: o\.draft, outage: true, by: 'outage_fallback' \}/.test(code)) out.push('R3 intakeVoice returns its draft without replyDown');
  return out;
}

test('1339: no intake reply falls back to code text without an outage gate (R1)', () => {
  assert.deepEqual([...fallbackFindings('index.ts', read('index.ts')), ...fallbackFindings('slots.ts', read('slots.ts'))], []);
});
test('1339: every code-composed intake reply is written by the model; the draft only when OpenRouter is down (R2)', () => {
  assert.deepEqual(indexFindings(read('index.ts')), []);
});
test('1339: slots.ts sends its code text only on an outage (R3)', () => {
  assert.deepEqual(slotsFindings(read('slots.ts')), []);
});

// KNOWN-BAD CONTROLS: the lines main / #1646 carried before this fix.
test('known-bad: the old intake fallbacks are caught', () => {
  assert.equal(fallbackFindings('slots.ts', '  return r.reply || HELD_FOR_SPECS[lang] || HELD_FOR_SPECS.en;\n').length, 1, 'main heldReply');
  assert.equal(fallbackFindings('slots.ts', "  return r.reply || `${HELD_FOR_SPECS[lang] || HELD_FOR_SPECS.en}${open.length ? '\\n- ' + open.join('\\n- ') : ''}`;\n").length, 1, '#1641 heldReply');
  assert.equal(fallbackFindings('index.ts', '        out.assistant_message = rewrite?.reply || replyFromState(status, ask, slotLang);\n').length, 1, '#1646 guard rewrite');
  assert.equal(fallbackFindings('index.ts', '  return modelOrOutage(r, HELD_FOR_SPECS[lang]);\n').length, 0, 'the sanctioned door passes');
  assert.equal(fallbackFindings('index.ts', '  // return r.reply || HELD_FOR_SPECS[lang];\n').length, 0, 'a comment never trips it');
  // #1646 at c339107d7: no voice step; the draft stood whenever the model's sentence was replaced
  const before = "    const guarded = guardSupportReply(String(out.assistant_message || ''), slotLang);\n"
    + "    for (let i = turns.length - 1; i >= 0; i--) if (turns[i] && turns[i].role === 'assistant') { turns[i].text = out.assistant_message || ''; break; }\n";
  const f = indexFindings(before);
  assert.ok(f.some((x) => x.includes('never voiced')) && f.some((x) => x.includes('not gated on llmDown')), f.join('\n'));
  // a code draft added after the voice step is caught
  const late = "    const voice = async (draftMsg: string) => { if (llmDown) { replyBy = 'outage_fallback'; return draftMsg; } };\n"
    + "    if (draftMsg && draftMsg !== String(modelWrote ?? '').trim()) out.assistant_message = await voice(draftMsg);\n"
    + "    out.assistant_message = `${out.assistant_message} If you have the CAD file, attach it.`;\n"
    + "    for (let i = turns.length - 1; i >= 0; i--) if (turns[i] && turns[i].role === 'assistant') { turns[i].text = out.assistant_message || ''; break; }\n";
  assert.ok(indexFindings(late).some((x) => x.includes('assigned after the voice step')));
  assert.ok(slotsFindings('  return r.reply || HELD_FOR_SPECS[lang];\n').length === 2);
});
