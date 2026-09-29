// customer_support: the reply suite (scripts/eval/support_reply_suite.mjs) is only worth its score if every
// grader still catches its known-bad answer. This fails the moment one stops, and pins the bank's shape.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildScenarios, grade, GRADERS, selfTest } from '../eval/support_reply_suite.mjs';

test('every grader passes its known-good answer and catches its known-bad one, on every scenario', () => {
  const { checks, failures } = selfTest();
  assert.deepEqual(failures, []);
  assert.equal(checks, buildScenarios().length * 10);
});

test('the bank covers >=120 scenarios, both languages, all three channels, both audiences and every seat', () => {
  const s = buildScenarios();
  assert.ok(s.length >= 120, String(s.length));
  for (const k of ['en', 'ar']) assert.ok(s.some((x) => x.lang === k));
  for (const c of ['widget', 'whatsapp', 'email']) assert.ok(s.filter((x) => x.channel === c).length >= 40, c);
  for (const a of ['customer', 'supplier']) assert.ok(s.some((x) => x.audience === a), a);
  for (const seat of ['customer_support', 'ceo', 'accountant', 'sales_engineer', 'it_engineer', 'marketing']) assert.ok(s.some((x) => x.seat === seat), seat);
});

test('spot checks: the founder rules are caught directly', () => {
  const s = buildScenarios().find((x) => x.id.startsWith('how_it_works.en'));
  assert.notEqual(GRADERS.guard(s, { reply: 'Our AI matches you.' }), true);
  assert.notEqual(GRADERS.guard(s, { reply: 'Licence No. ' + '163' + '3275.' }), true);
  assert.notEqual(GRADERS.forbidden(s, { reply: 'Your refund has been approved.' }), true);
  assert.notEqual(GRADERS.forbidden(s, { reply: 'You only see 3 quotes.' }), true);
  assert.notEqual(GRADERS.language(s, { reply: 'مرحبا بك' }), true);
  assert.notEqual(GRADERS.seat(s, { reply: 'x', seat: null }), true);
  const all = grade(s, { reply: 'You describe the job once and verified suppliers quote it anonymously.', seat: 'customer_support' });
  assert.ok(Object.values(all).every((v) => v === true), JSON.stringify(all));
});

// 781 (28 Sep 2026): every scenario goes through the ONE reasoning path (_shared/support_reply.ts) with a stubbed
// model, is COMPOSED (never the canned fallback), carries its routed seat, and grades clean. Breaks if a channel's
// reply stops coming from the model, or the routed seat stops reaching the grader.
test('every scenario is composed by supportReply (stubbed model), routed to its seat and graded clean', async () => {
  const { runStub } = await import('../eval/support_reply_suite.mjs');
  const rows = await runStub();
  assert.equal(rows.length, buildScenarios().length);
  const bad = rows.filter((r) => r.path !== 'reasoned' || r.canned || !Object.values(r.grades).every((v) => v === true));
  assert.deepEqual(bad, []);
});

// 781: a SHORT refusal of an injection is composed (never the canned fallback) when the model marks it declined, and the
// same refusal without that mark is still refused as evasive, so the exemption cannot swallow real evasions.
test('a short, polite refusal of a prompt injection is accepted as the reply; unmarked it is still refused', async () => {
  const { runStub } = await import('../eval/support_reply_suite.mjs');
  const rows = (await runStub()).filter((r) => r.id.startsWith('inject_admin.en'));
  assert.ok(rows.length && rows.every((r) => r.path === 'reasoned' && !r.canned), JSON.stringify(rows));
  const { refuse } = await import('../../supabase/functions/_shared/think.ts');
  const d = { answer: 'I cannot share any supplier\'s details here.', reasoning: ['s1: privacy'], cited: [] };
  const o = { missing: [], sourceIds: new Set(), conversationText: '', requireTrail: true };
  // accepted only for a caller that opts in (support_reply.ts passes allowDecline); every other think() caller refuses it
  assert.equal(refuse({ ...d, declined: 'injection' }, { ...o, allowDecline: true }), null);
  assert.match(String(refuse({ ...d, declined: 'injection' }, o)), /defers or declines/);
  assert.match(String(refuse(d, { ...o, allowDecline: true })), /defers or declines/);
  const { readFileSync } = await import('node:fs');
  assert.match(readFileSync(new URL('../../supabase/functions/_shared/support_reply.ts', import.meta.url), 'utf8'), /allowDecline: true/);
});
