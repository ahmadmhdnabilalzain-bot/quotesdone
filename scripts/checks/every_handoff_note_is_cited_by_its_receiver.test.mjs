// EVERY HANDOFF NOTE STATES ITS FOUR FIELDS AND ITS RECEIVER CITES IT (19 Oct 2026, ceo; founder ledger row 1013).
//
// MEASURED 19 Oct 2026: #1072's note (known / tried / needed / evidence) was live on production, but it named no
// deadline and no decision, and fn_seat_handoff_act stored the handler's answer without naming the note it read:
// a receiver that ignored the note and one that used it left identical rows.
//
// WHAT FAILS IF THE CAUSE RETURNS: fn_handoff_summary stops returning or refusing on any of context / decision /
// open_asks / deadline; the trigger stops rebuilding a note that lacks them; the CHECK stops naming all four;
// the dispatcher or the closer stops stamping cites_note; the measurement routine disappears; a definer loses its
// revoke or pinned search_path. On production: select public.fn_handoff_citation_gaps(<since>) -> uncited_ids = [].
//
//   node --test scripts/checks/every_handoff_note_is_cited_by_its_receiver.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const s = readFileSync(join(REPO, 'scripts/sql/every_handoff_note_states_context_decision_open_asks_and_deadline_and_its_receiver_cites_it.sql'), 'utf8');
// fn_seat_handoff_act has one owner (handoff_kinds_are_data.test.mjs), so its citing body is read from there.
const owner = readFileSync(join(REPO, 'scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql'), 'utf8');
// fn_handoff_citation_gaps is owned by the later file that superseded this one's copy (removed 13 Nov 2026).
const gaps = readFileSync(join(REPO, 'scripts/sql/a_handoff_closes_only_when_its_receiver_cites_the_note_or_says_why_not.sql'), 'utf8');
const body = (fn) => {
  const re = new RegExp(`create or replace function public\\.${fn}\\([\\s\\S]*?\\$(fn|function)\\$;`, 'i');
  const m = s.match(re) ?? owner.match(re) ?? gaps.match(re);
  assert.ok(m, `${fn} is not defined in the file or its owner`);
  return m[0];
};
const FOUR = ['context', 'decision', 'open_asks', 'deadline'];

test('the note returns all four fields and refuses a handoff that cannot state them', () => {
  const b = body('fn_handoff_summary');
  for (const f of FOUR) assert.match(b, new RegExp(`'${f}', v_`), `the note does not return ${f}`);
  assert.match(b, /cannot state its context, decision, open asks and deadline - refused/);
  assert.match(b, /k\.reply_within/, 'the deadline no longer reads the conversation\'s reply window');
});

test('the trigger rebuilds a note missing any of the four, and the CHECK refuses one', () => {
  const trg = s.match(/create (?:or replace )?trigger a01_handoff_carries_its_note[\s\S]*?execute function public\.trg_handoff_carries_its_note\(\);/);
  assert.ok(trg, 'trigger a01_handoff_carries_its_note is not recreated');
  const chk = s.match(/add constraint agent_actions_handoff_note_states_four_fields[\s\S]*?not valid;/);
  assert.ok(chk, 'the CHECK is gone');
  for (const f of FOUR) {
    assert.ok(trg[0].includes(`'${f}'`), `the trigger does not rebuild a note missing ${f}`);
    assert.ok(chk[0].includes(`'${f}'`), `the CHECK does not require ${f}`);
  }
});

test('the dispatcher and every close stamp the citation on the receiver\'s answer', () => {
  assert.match(body('fn_seat_handoff_act'), /'cites_note', public\.fn_handoff_note_citation\(p_id\)/);
  assert.match(body('fn_seat_handoff_complete'), /'cites_note', public\.fn_handoff_note_citation\(p_id\)/);
  assert.match(body('fn_handoff_note_citation'), /'handoff_id', a\.id/);
  assert.match(body('fn_handoff_citation_gaps'), /uncited_ids/);
});

test('every definer pins search_path and new ones are revoked', () => {
  for (const fn of ['fn_handoff_summary', 'fn_handoff_note_citation', 'fn_seat_handoff_act', 'fn_seat_handoff_complete', 'fn_handoff_citation_gaps']) {
    assert.match(body(fn), /security definer\s+set search_path to 'public', 'pg_temp'/i, `${fn} has no pinned search_path`);
  }
  for (const sig of ['fn_handoff_summary(jsonb, text, text, text, text, text, bigint)', 'fn_handoff_note_citation(bigint)', 'fn_handoff_citation_gaps(timestamptz)']) {
    assert.ok((s + gaps).includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), `${sig} is not revoked`);
  }
});

// Release-operator review of #1516 (19 Oct 2026): an UPDATE of an older row never fails on the note, and no
// e-mail address or phone number reaches a note.
test('an UPDATE falls back to a legacy note instead of raising; INSERT stays strict', () => {
  const b = body('trg_handoff_carries_its_note');
  assert.match(b, /if tg_op = 'INSERT' then\s+v_note := public\.fn_handoff_summary/);
  assert.match(b, /exception when others then[\s\S]*'legacy', true/);
  for (const f of FOUR) assert.ok(b.includes(`'${f}'`), `the legacy note lacks ${f}`);
});

test('the note is redacted and contact keys are not facts', () => {
  assert.match(body('fn_handoff_summary'), /return public\.fn_handoff_redact\(jsonb_build_object\(/);
  assert.match(body('fn_handoff_summary'), /e\.key !~\* '\(mail\|phone\|mobile\|whatsapp/);
  assert.match(body('fn_handoff_redact_text'), /'\[email\]'[\s\S]*'\[phone\]'/);
  // UAE local forms (05x xxx xxxx, 04 xxx xxxx) as well as + and 00 (review of fd5ee1a); neither starts on a digit that
  // follows a digit or a dot (13 Nov 2026: the decimals of an amount are not a phone number)
  assert.ok(body('fn_handoff_redact_text').includes(String.raw`'(?<![0-9.])\m0[1-9]([ -]?[0-9]){7,8}\M', '[phone]'`), 'local UAE numbers are not redacted');
  // review 4 (6d): 00 may be followed by one space or dash ("00 971 50 ..."), and needs 10-14 digits after it, so a
  // reference such as "PO 0012345678" is not a phone
  assert.ok(body('fn_handoff_redact_text').includes(String.raw`'(?<![0-9.])([+][0-9][0-9 -]{5,}[0-9]|\m00[ -]?[1-9]([ -]?[0-9]){9,13})', '[phone]'`), 'international numbers are not redacted');
  // 13 Nov 2026 (review 3, item 4): the value is walked, keys and strings redacted, numbers never text to the patterns;
  // review 4 (6d): two keys that redact alike keep both values, and a phone stored as a number is redacted
  assert.match(body('fn_handoff_redact'), /jsonb_object_agg\(case when x\.n = 1 then x\.k else x\.k \|\| ' \(' \|\| x\.n \|\| '\)' end, x\.v\)/);
  assert.match(body('fn_handoff_redact'), /row_number\(\) over \(partition by public\.fn_handoff_redact_text\(e\.key\) order by e\.key\)/);
  assert.match(body('fn_handoff_redact'), /e\.key ~\* '\(phone\|mobile\|whatsapp\|msisdn\|fax\|\\mtel\)'/);
  assert.match(body('fn_handoff_redact'), /when 'string' then\s+v := to_jsonb\(public\.fn_handoff_redact_text\(p #>> '\{\}'\)\)/);
  assert.ok(!/p::text/.test(body('fn_handoff_redact')), 'fn_handoff_redact runs the patterns over JSON text again');
  for (const sig of ['fn_handoff_redact(jsonb)', 'fn_handoff_redact_text(text)', 'trg_handoff_carries_its_note()', 'fn_seat_handoff_act(bigint)', 'fn_seat_handoff_complete(bigint, jsonb)']) {
    assert.ok((s + owner).includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), `${sig} is not revoked`);
  }
});
