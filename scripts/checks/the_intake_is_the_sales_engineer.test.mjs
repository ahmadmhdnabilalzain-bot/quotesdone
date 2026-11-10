// The founder, 14 Sep 2026: "its always the sales agent. no other agent is involved in customer or
// supplier portal. make sure the wiring is made this way."
//
// Before this, inquiry_intake handed the conversation to a category specialist from category_agents
// (a persona name the customer saw in "Handled by …") and the composer introduced itself as a
// generic "intake assistant". This asserts the wiring the ruling asks for, at the source:
//   1. inquiry_intake answers as ACTOR and names no category specialist as the answering agent
//   2. ACTOR is 'sales_engineer', and the stored answers are recorded under it
//   3. the composer introduces the sales engineer in English and Arabic, and the new composer keys
//      exist in both languages
//   4. the edge functions that serve the portal intake are owned by sales_engineer in function_owner
//      is NOT asserted here (it is production data, read by the ownership checks); this change adds
//      no new routine, so it adds no owner row.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { functionSource } from '../lib/function_sources.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => fs.readFileSync(path.join(REPO, p), 'utf8');

test('inquiry_intake answers as the sales engineer and names no other seat', () => {
  const src = functionSource('inquiry_intake');
  assert.match(src, /agent:\s*ACTOR,\s*agent_name:/, 'the response names ACTOR as the agent');
  assert.match(src, /turns\.push\(\{ role: 'assistant', text: [^}]*agent: ACTOR \}\)/, 'every assistant turn is stamped ACTOR');
  assert.doesNotMatch(src, /agent:\s*specialist/, 'no category specialist is the answering agent');
  assert.doesNotMatch(src, /agent_name:\s*specialist/, 'no specialist name is shown to the customer');
});

test('the actor is sales_engineer, and the stored answers are recorded under it', () => {
  const src = read('supabase/functions/_shared/intake_requirements.ts');
  assert.match(src, /export const ACTOR = 'sales_engineer' as const;/);
  assert.match(src, /recorded_by: ACTOR/);
  assert.match(src, /x\.recorded_by !== ACTOR/, 'the post gate refuses answers recorded by anyone else');
});

test('the composer introduces the sales engineer, in both languages', () => {
  const src = read('src/components/me/portalText.ts');
  assert.match(src, /I'm your QuotesDone sales engineer/);
  assert.match(src, /أنا مهندس المبيعات في QuotesDone/);
  assert.doesNotMatch(src, /intake assistant/, 'the generic "intake assistant" name is gone');
  for (const k of ['nr_left', 'nr_req_title', 'nr_req_change', 'nr_req_keep', 'nr_req_invalid', 'nr_posted', 'nr_posted_view', 'nr_posted_none', 'nr_suggested']) {
    assert.equal((src.match(new RegExp(`\\b${k}:`, 'g')) || []).length, 2, `${k} exists in English and Arabic`);
  }
});
