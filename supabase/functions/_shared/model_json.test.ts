// The one reader of a model's JSON object (_shared/model_json.ts, 17 Nov 2026): every input case the 43 hand-written readers
// handled, and the proof that each call site moved without changing what it read.
//
// HOW THE PROOF WORKS. The readers as they were on origin/main 09e43394c are copied below, verbatim except for names, one per
// shape (OLD). Each is run against the same corpus as the reader its call sites now use, and the test says exactly where they
// may differ: nowhere for most shapes, and for the rest only on inputs the old reader could not read (or read as a bare array
// or number that its caller then treated as an object with no fields). These copies are evidence, not code anyone calls.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { controlsEscaped, outermostBraces, parseJson } from './model_json.ts';

// ── OLD: the shapes, verbatim ──────────────────────────────────────────────────────────────────────────────────────────
// R: the first '{' to the last '}' — `/\{[\s\S]*\}/` (wa_inbound, job_question, supplier_instruction, inquiry_reading,
// catalogue_model, opt_out_backstop, conversation_plan, ownership_claim) or indexOf/lastIndexOf with a guard
// (supplier_mailbox_reading, stranger_repeat_guard, whatsapp_offer) or without one (lead_sourcing, marketing_articles jsonOf).
const oldRegex = (s: string) => { const m = String(s ?? '').match(/\{[\s\S]*\}/); if (!m) return null; try { return JSON.parse(m[0]); } catch { return null; } };
const oldSliceNoGuard = (answer: string) => { try { return JSON.parse(answer.slice(answer.indexOf('{'), answer.lastIndexOf('}') + 1)); } catch { return null; } };
// doc_extract: the ends' fences stripped, then R
const oldDocExtract = (t0: string) => { const t = String(t0).replace(/^```(json)?/i, '').replace(/```$/, '').trim(); const m = t.match(/\{[\s\S]*\}/); if (m) { try { return JSON.parse(m[0]); } catch { /* */ } } return null; };
// think/validator.ts parseJson (the owner the 16 Nov audit named)
function oldValidator(text: string | null | undefined) {
  if (!text) return null;
  const m = text.trim().match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
  const one = (t: string) => { try { const o = JSON.parse(t); return o && typeof o === 'object' && !Array.isArray(o) ? o : null; } catch (_e) { return null; } };
  const t = m ? m[1] : text.trim(), a = t.indexOf('{'), b = t.lastIndexOf('}');
  return one(t) ?? (a >= 0 && b > a ? one(t.slice(a, b + 1)) : null);
}
// licence_extract.ts parseJson
function oldLicence(t: string) {
  const take = (s: string) => { try { const v = JSON.parse(s); return (v && typeof v === 'object' && !Array.isArray(v)) ? v : null; } catch { return null; } };
  return take(t) ?? (t.match(/\{[\s\S]*\}/) ? take(t.match(/\{[\s\S]*\}/)![0]) : null);
}
// support_case_memory.ts summaryJson
function oldSummary(content: unknown) {
  const text = String(content ?? '').replace(/^\s*```(?:json)?\s*|\s*```\s*$/g, '').trim();
  const take = (t: string) => { try { const v = JSON.parse(t); return v && typeof v === 'object' && !Array.isArray(v) ? v : null; } catch (_e) { return null; } };
  const a = text.indexOf('{'), b = text.lastIndexOf('}');
  return take(text) ?? (a >= 0 && b > a ? take(text.slice(a, b + 1)) : null);
}
// W: the whole reply first, its value handed on whatever it is, else R (drawing_redact, inquiry_intake, quote_extract,
// drawing_boq, resend_inbound, supplier_onboard, confirm, vision_count, drawing_string_reading, drawing_pixel_gate)
function oldWhole(t: string) { try { return JSON.parse(t); } catch { const m = t.match(/\{[\s\S]*\}/); if (m) { try { return JSON.parse(m[0]); } catch { /* */ } } return null; } }
// ceo_agent/plan.ts parsePlan
function oldPlan(content: string | null | undefined) {
  const text = String(content ?? '').trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  if (!text) return null;
  try { const o = JSON.parse(text); return o && typeof o === 'object' && !Array.isArray(o) ? o : null; } catch {
    const a = text.indexOf('{'), b = text.lastIndexOf('}');
    if (a < 0 || b <= a) return null;
    try { const o = JSON.parse(text.slice(a, b + 1)); return o && typeof o === 'object' && !Array.isArray(o) ? o : null; } catch { return null; }
  }
}
// exact: escalation_clock (x2), review_decide, seat_deliberation, provider_signals — seat_deliberation's body
function oldExact(text: string | null) {
  if (!text) return null;
  const m = text.trim().match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
  try { const o = JSON.parse(m ? m[1] : text.trim()); return o && typeof o === 'object' && !Array.isArray(o) ? o : null; } catch (_e) { return null; }
}
// marketing_judgement.ts parseAnswer
function oldMarketing(text: string | null) {
  if (!text) return null;
  try { const v = JSON.parse(text.trim().replace(/^```(?:json)?\s*|\s*```$/g, '')); return v && typeof v === 'object' && !Array.isArray(v) ? v : null; } catch { return null; }
}
// ai_reply.ts json (controlsEscaped is the moved function, unchanged)
function oldAiReply(s: string | null | undefined) {
  const t = String(s ?? '').trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '').trim();
  const obj = t.slice(t.indexOf('{'), t.lastIndexOf('}') + 1);
  for (const c of [t, obj, controlsEscaped(obj)]) { try { const v = JSON.parse(c); if (v && typeof v === 'object') return v; } catch (_e) { /* next */ } }
  return {};
}
// quote_compare: the first ```json block anywhere, then W inside it
function oldQuoteCompare(t: string) { let s = String(t || '').trim(); const f = s.match(/```(?:json)?\s*([\s\S]*?)```/i); if (f) s = f[1].trim(); try { return JSON.parse(s); } catch { /* */ } const m = s.match(/\{[\s\S]*\}/); if (m) { try { return JSON.parse(m[0]); } catch { /* */ } } return null; }
const newQuoteCompare = (t: string) => { const s = String(t || '').trim(); const f = s.match(/```(?:json)?\s*([\s\S]*?)```/i); return parseJson(f ? f[1] : s, { wholeDecides: true }); };

// ── the corpus: every case a reader above was written for, and the ones that broke them ──────────────────────────────
const OBJ = '{"verdict":"answered","answer":"Yes, 2 coats","n":3,"nested":{"k":[1,{"z":null}]},"ar":"نعم، طبقتان"}';
const CORPUS: string[] = [
  OBJ, '  ' + OBJ + '\n', '{}',
  '```json\n' + OBJ + '\n```', '```\n' + OBJ + '\n```', '```json' + OBJ + '```', '\n```json\n' + OBJ + '\n```\n', '```JSON\n' + OBJ + '\n```',
  '```json\n' + OBJ, OBJ + '\n```',                                                   // half fences
  'Here is the JSON: ' + OBJ, OBJ + ' Hope this helps.', 'Sure!\n```json\n' + OBJ + '\n```\nLet me know.',
  '{"a":"a } inside a string"}', 'say {"a":"}"} done',
  'Use {name} like this: ' + OBJ,                                                   // a brace in the prose before the object
  '```json\n{"a":1}\n```\nor\n```json\n{"a":2}\n```',                              // two fenced blocks
  '{"a":1} and {"b":2}',                                                            // two bare objects
  '} reversed {', 'no braces at all', '', '   ',
  '{"a":1,}', '{"a":[1,2,],}',                                                       // trailing commas: no copy tolerated them
  '{"answer":"cut off at the tok',                                                   // truncated
  '{"answer":"line one\nline two"}', 'Reply: {"answer":"a\tb\r\nc"} end',            // raw control characters inside a string
  '{\n  "a": 1,\n  "b": "x"\n}',                                                     // line breaks between keys are whitespace
  '[1,2]', '[{"a":1}]', '```json\n[{"a":1}]\n```', '[]',
  '```json\n[{"a":1}]', '[{"a":1}]\n```', '```JSON\n[{"a":1}]\n```',                // an array behind a half or upper-case fence
  '5', '"text"', '"{\\"a\\":1}"', 'true', 'null',
];

// deno-lint-ignore no-explicit-any
const plain = (v: any) => (v && typeof v === 'object' && !Array.isArray(v) ? v : null);

Deno.test('R (first { to last }): the reader gives exactly what the regex and slice copies gave, on every input', () => {
  for (const s of CORPUS) {
    assertEquals(parseJson(s), oldRegex(s), s);
    assertEquals(parseJson(s), oldSliceNoGuard(s), s);
    assertEquals(parseJson(s), oldDocExtract(s), s);
  }
});

Deno.test('validator, licence_extract and support_case_memory: the reader is the same function', () => {
  for (const s of CORPUS) {
    assertEquals(parseJson(s), oldValidator(s), s);
    assertEquals(parseJson(s), oldLicence(s), s);
    assertEquals(parseJson(s), oldSummary(s), s);
  }
  assertEquals(parseJson(null), oldValidator(null));
  assertEquals(parseJson(undefined), oldSummary(undefined));
});

Deno.test('exact (escalation_clock, review_decide, seat_deliberation, provider_signals): identical, a fence and nothing else', () => {
  for (const s of CORPUS) assertEquals(parseJson(s, { exact: true }), oldExact(s), s);
  assertEquals(parseJson(OBJ, { exact: true }), JSON.parse(OBJ));
  assertEquals(parseJson('```json\n' + OBJ + '\n```', { exact: true }), JSON.parse(OBJ));
  assertEquals(parseJson('Here it is: ' + OBJ, { exact: true }), null, 'a sentence around the object is refused');
  assertEquals(parseJson('```json\n' + OBJ, { exact: true }), null, 'half a fence is refused');
});

Deno.test('wholeDecides (W copies): the same object whenever the old copy gave an object; a bare non-object is no object', () => {
  for (const s of CORPUS) {
    const was = oldWhole(s), now = parseJson(s, { wholeDecides: true });
    if (plain(was)) assertEquals(now, was, s);
    // the old copy handed a bare array, number, string or boolean on as if it were the object; it is now null
    else if (was !== null && !plain(was)) assertEquals(now, null, s);
    // the old copy read nothing: neither does this one (an array fenced as a whole is in the first branch: the old copy's
    // whole-reply parse failed on the fence and its regex took the object inside, and so does this one)
    else assertEquals(now, null, s);
  }
  // the drawing redaction gates read a bare array as no verdict, as before
  assertEquals(parseJson('[{"clean":true,"addressed":false}]', { wholeDecides: true }), null);
  assertEquals(oldWhole('[{"clean":true,"addressed":false}]').clean, undefined);
});

Deno.test('ceo plan: the same plan whenever the old reader read one; also an array fenced as a whole is read for its object', () => {
  for (const s of CORPUS) {
    const was = oldPlan(s), now = parseJson(s, { wholeDecides: true });
    if (was !== null) assertEquals(now, was, s);
    else if (now !== null) assert(s.includes('```') && s.includes('[{'), 'the plan reader now reads only an array behind a fence: ' + s);
  }
});

Deno.test('marketing_judgement: every answer it read is read the same; a sentence around the object is now read too', () => {
  for (const s of CORPUS) { const was = oldMarketing(s); if (was !== null) assertEquals(parseJson(s), was, s); }
  assertEquals(oldMarketing('Here it is: ' + OBJ), null);
  assertEquals(parseJson('Here it is: ' + OBJ), JSON.parse(OBJ));
});

Deno.test('ai_reply: the same object, the same {} for nothing, raw line breaks inside the answer still escaped', () => {
  const now = (s: string) => parseJson(s, { wholeDecides: true, escapeControls: true }) ?? {};
  for (const s of CORPUS) {
    const was = oldAiReply(s);
    if (Array.isArray(was)) {
      // a bare array: no answer before, no answer now; an array fenced as a whole: the object inside is now the answer
      if (s.includes('```')) assertEquals(now(s), { a: 1 }, s); else assertEquals(now(s), {}, s);
    } else assertEquals(now(s), was, s);
  }
  assertEquals(now('{"answer":"Call us on\n+971 4 000 0000"}'), { answer: 'Call us on\n+971 4 000 0000' });
  assertEquals(parseJson('{"answer":"Call us on\n+971 4 000 0000"}'), null, 'only escapeControls repairs a raw line break');
  assertEquals(now('{"answer":"cut off at the tok'), {}, 'a truncated answer is never sent');
});

Deno.test('quote_compare: its first-fenced-block rule is kept at the call site; the object read is the same', () => {
  for (const s of CORPUS) {
    const was = oldQuoteCompare(s), now = newQuoteCompare(s);
    if (plain(was)) assertEquals(now, was, s); else assertEquals(now, null, s);
  }
  assertEquals(newQuoteCompare('```json\n{"a":1}\n```\nor\n```json\n{"a":2}\n```'), { a: 1 });
});

Deno.test('the cases themselves: what is read, and what is never guessed', () => {
  const o = JSON.parse(OBJ);
  assertEquals(parseJson(OBJ), o);
  assertEquals(parseJson('```json\n' + OBJ + '\n```'), o);
  assertEquals(parseJson('Sure!\n```json\n' + OBJ + '\n```\nLet me know.'), o);
  assertEquals(parseJson('say {"a":"}"} done'), { a: '}' });
  assertEquals((parseJson(OBJ) as { ar: string }).ar, 'نعم، طبقتان', 'Arabic comes through untouched');
  for (const s of ['{"a":1,}', '{"answer":"cut off at the tok', '[1,2]', '5', '"text"', 'true', 'null', '', 'no braces at all',
    '{"a":1} and {"b":2}', 'Use {name} like this: {"a":1}', '} reversed {']) {
    assertEquals(parseJson(s), null, s);
    assertEquals(parseJson(s, { escapeControls: true }), null, s);
  }
  assertEquals(parseJson('[{"a":1}]'), { a: 1 }, 'the default reads the outermost object, as R always did');
  assertEquals(parseJson({ a: 1 }), null, 'a value that is not text is not a reply');
  assertEquals(outermostBraces('x {a} y {b} z'), '{a} y {b}');
  assertEquals(outermostBraces('} {'), '');
  assert(controlsEscaped('{"a":"x\ny"}\n').endsWith('}\n'), 'a line break outside a string is left alone');
});
