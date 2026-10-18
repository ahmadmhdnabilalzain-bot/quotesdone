// THE CEO QUEUE WORKER NEVER TOUCHES A SUPPORT HANDOVER (it_engineer, 19 Oct 2026). #1462's
// fn_ceo_support_handover_duty sends the customer the reply and is the one owner of its handover kind
// (scripts/checks/support_question_handover_has_one_owner.test.mjs). fn_ceo_queue_work therefore acts only on kinds it
// names, and never names that one. Also pins the review fixes: supersession by an applied question for the same item,
// and the worker closing its own overdue tasks. Repository only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const HANDOVER = ['support', 'question', 'handover'].join('_');
const read = (f) => readFileSync(fileURLToPath(new URL(`../sql/${f}`, import.meta.url)), 'utf8');
const src = read('the_ceo_queue_is_worked_closed_or_flagged_overdue.sql');
const probe = read('the_ceo_queue_is_worked_closed_or_flagged_overdue_probe.sql');
// The function body only, comments stripped, so the file's own header cannot satisfy or trip the check.
const body = src.slice(src.indexOf('create or replace function public.fn_ceo_queue_work'), src.lastIndexOf('$fn$'))
  .split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

test('neither the worker nor its probe names the support handover kind', () => {
  assert.ok(!src.includes(HANDOVER), 'the worker file names the support handover kind');
  assert.ok(!probe.includes(HANDOVER), 'the probe names the support handover kind');
});

test('every update acts only on kinds it names', () => {
  const lists = [...body.matchAll(/kind in \(([^)]*)\)/g)].map((m) => m[1]);
  assert.ok(lists.length >= 3, `expected a named kind list on each step, found ${lists.length}`);
  for (const l of lists) for (const k of l.split(',')) {
    assert.ok(["'handoff'", "'held_question'", "'held_question_expired'"].includes(k.trim()), `unexpected kind ${k.trim()}`);
  }
});

test('only an applied question for the same item supersedes', () => {
  assert.match(body, /n\.status = 'applied'/, 'supersession must count only applied questions');
  assert.match(body, /fn_ceo_queue_dedupe_stem\(n\.dedupe_key\) = q\.stem/, 'supersession must match the dedupe_key stem');
  assert.doesNotMatch(body, /'closed'|'answered'/, 'reasoning_held_question has no closed/answered status');
});

test('the dedupe stem strips only the known period of each known prefix', () => {
  const stem = src.slice(src.indexOf('function public.fn_ceo_queue_dedupe_stem'), src.indexOf('create or replace function public.fn_ceo_queue_work'));
  for (const p of ['\\^krefresh:', '\\^ceo_exp_approve:', 'ceo_mreview\\|ceo_forecast']) {
    assert.match(stem, new RegExp(p), `the stem has no branch for ${p}`);
  }
  assert.doesNotMatch(stem, /'g'\)/, 'a global strip can remove an item id, not only the period');
});

test('the worker closes its own overdue tasks', () => {
  assert.match(body, /update public\.ceo_task t\s+set state = 'done'/, 'nothing closes the daily CEO queue overdue task');
  assert.match(body, /t\.title like 'CEO queue overdue %'/, 'the close step must target its own task titles');
});
