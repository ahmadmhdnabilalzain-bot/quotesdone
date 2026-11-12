// The prompt diet's paid round (scripts/eval/prompt_diet_eval.mjs) stays under its USD 1.50 budget, refuses to spend without
// --paid, and anonymises what it replays (it_engineer, 11 Nov 2026; rulings 1619/1618; docs/reports/2026-11-11-prompt-diet.md).
// Offline: no database, no model.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { anonymiseRequest, anonymiseText, CAP_USD, PASS_RULES, plan, SURFACES } from '../eval/prompt_diet_eval.mjs';

const SCRIPT = fileURLToPath(new URL('../eval/prompt_diet_eval.mjs', import.meta.url));

test('the expected cost of every part together stays under the USD 1.50 budget', () => {
  const p = plan();
  assert.equal(p.parts.length, 5);
  assert.ok(p.total > 0.5 && p.total <= CAP_USD, `total USD ${p.total}`);
  assert.ok(PASS_RULES.some((r) => /95%/.test(r)) && PASS_RULES.some((r) => /ZERO rule violations/.test(r)));
});

test('the run refuses to spend without --paid, and refuses a cap above the budget', () => {
  const a = spawnSync(process.execPath, [SCRIPT, 'run', '--cases', '/nonexistent.json'], { encoding: 'utf8' });
  assert.equal(a.status, 2); assert.match(a.stderr, /REFUSED/);
  const b = spawnSync(process.execPath, [SCRIPT, 'run', '--cases', '/nonexistent.json', '--paid', '--cap', '5'], { encoding: 'utf8' });
  assert.equal(b.status, 2); assert.match(b.stderr, /cap/);
});

test('what leaves the machine carries no real address, number or subject; the question and its context survive', () => {
  const t = anonymiseText('Ask Ahmed at ahmed.k@realco.ae or +971 50 123 4567; ZZ DEMO is zz@example.invalid; 3 quotes, AED 4,500');
  assert.ok(!/realco|123 4567/.test(t), t);
  assert.match(t, /zz@example\.invalid/); assert.match(t, /AED 4,500/); assert.match(t, /3 quotes/);
  const r = anonymiseRequest({ seat: 'it_engineer', surface: 'it_engineer.postmortem', question: 'Why did mail to x@realco.ae bounce?', dedupeKey: 'k:971501234567',
    subject: { phone: '+971501234567' }, context: { audience: 'internal', conversation: [{ role: 'founder', text: 'call me on 0501234567' }] } });
  assert.deepEqual(r.subject, { fixture: true }); assert.equal(r.dedupeKey, undefined);
  assert.ok(!JSON.stringify(r).includes('realco') && !JSON.stringify(r).includes('1234567'));
  assert.equal(r.context.audience, 'internal');
  // a date is not a phone number: the duties replayed reason about dates, and 752 of 752 replacements on the first sample were dates
  const d = anonymiseText('ends 2026-11-30, read at 2026-11-10T03:37:12.123456+00:00; call 0501234567 or 04-2026-1110 or +971 4 2026 1110');
  assert.match(d, /ends 2026-11-30,/); assert.match(d, /2026-11-10T03:37:12\.123456\+00:00/);
  assert.ok(!/0501234567|04-2026-1110|2026 1110/.test(d), d);
  for (const s of SURFACES) assert.ok(!/document|supplier_|customer|wa_inbound|site_assistant/.test(s), s + ' must be an internal duty surface');
});
