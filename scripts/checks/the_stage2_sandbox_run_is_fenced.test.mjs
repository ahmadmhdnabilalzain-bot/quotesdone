// The stage-2 sandbox run (scripts/e2e/stage2.mjs, ledger 1119) spends real model money on production
// past the hold, for its own tagged calls only (the hold itself never changes: a_sandbox_success_never_lifts_the_model_hold). These are the fences that keep it from costing more than the founder allowed,
// from reaching a real person, from taking a live card, and from leaving anything a seat could learn from.
//   node --test scripts/checks/the_stage2_sandbox_run_is_fenced.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { classify, TESTED, JUSTIFIED } from '../e2e/stage2_coverage.mjs';

const src = readFileSync(new URL('../e2e/stage2.mjs', import.meta.url), 'utf8');
const dry = src.slice(src.indexOf("if (MODE === '--dry-run')"), src.indexOf('// --run'));

test('the script cap defaults to USD 4, never above 15, and is checked before and after every scenario', () => {
  assert.match(src, /Number\(val\('--cap-usd'\) \|\| 4\)/);
  assert.match(src, /CAP_USD > 15\)/);
  assert.match(src, /spentUsd \+ est > CAP_USD/);
  assert.match(src, /spentUsd > CAP_USD\) \{ aborted = `HARD ABORT/);
});

test('the dry run calls no edge function and so no model', () => {
  assert.doesNotMatch(dry, /\bcall\(/);
  assert.doesNotMatch(dry, /realRun\(/);
});

test('the real run refuses while a precondition fails, and refuses a live Stripe key', () => {
  assert.match(src, /if \(!pre\.ok\) \{ console\.error\('\\nREFUSED/);
  assert.match(src, /startsWith\('sk_test_'\)\) throw new Error\('REFUSED/);
});

test('cleanup is scoped by the run tag and never purges the founder demo account', () => {
  assert.match(src, /tag === 'founderdemo'/);
  assert.match(src, /\^\[a-z0-9\]\{4,16\}\$/);
  // ai_cost_log: exactly the run's rows, by the tag the trigger stamps, never a time window.
  assert.match(src, /delete from public\.ai_cost_log where e2e_run_tag = /);
  assert.doesNotMatch(src, /delete from public\.ai_cost_log where id/);
  // the spend the cap counts is the run's own, never real traffic in the same minutes
  assert.match(src, /and e2e_run_tag = \$\{q\(RUN_TAG\)\}/);
});

test('a duty probe can never commit: it raises after measuring', () => {
  const d = readFileSync(new URL('../e2e/stage2_duties.mjs', import.meta.url), 'utf8');
  assert.match(d, /raise exception 'CHK<<%>>'/);
  assert.match(d, /the probe did not raise: it may have COMMITTED/);
});

const sql = readFileSync(new URL('../sql/a_sandbox_run_is_tagged_capped_and_let_through_only_inside_its_window.sql', import.meta.url), 'utf8');
const gate = sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION public.fn_kernel_paid_provider_gate'), sql.indexOf('end $function$;'));

test('a sandbox tag counts only for an open, unexpired, model-enabled window', () => {
  assert.match(sql, /w\.run_tag = 'qd_run:' \|\| p_tag and w\.ended_at is null and w\.models_allowed and w\.expires_at > now\(\)/);
  assert.match(sql, /check \(expires_at <= started_at \+ interval '2 hours 1 minute'\)/);
  assert.match(sql, /check \(cap_usd > 0 and cap_usd <= 15\)/);
  assert.match(sql, /add column if not exists models_allowed boolean not null default false/);
  for (const f of ['fn_e2e_run_tag_open(text)', 'fn_e2e_run_tag_current()', 'fn_ai_cost_log_e2e_run_tag()']) {
    assert.ok(sql.includes(`revoke execute on function public.${f} from public, anon, authenticated`), f);
  }
});

test('the gate: untagged traffic is untouched, tagged traffic is capped and passes only the hold', () => {
  // block 0 runs only for a tag; untagged calls never reach the cap or the window
  assert.match(gate, /if v_tag is not null then\s+if not coalesce\(public\.fn_e2e_run_tag_open\(v_tag\), false\)/);
  assert.match(gate, /'rule', 'rehearsal_cap'/);
  // the founder's hold still refuses everything that is not this run
  assert.match(gate, /if v_held > 0 and not v_rehearsal then/);
  // the no_paid_ai switch and a real (short) breaker still refuse a tagged call
  assert.doesNotMatch(gate.slice(gate.indexOf('-- 1. the explicit switch'), gate.indexOf('-- 2.')), /v_rehearsal/);
  assert.match(gate, /and not \(v_rehearsal and v_open > now\(\) \+ interval '365 days'\)/);
  // the file proves all four answers and must print PROBE OK at apply
  assert.match(sql, /PROBE OK: untagged=/);
});

test('the tag alone gets a public caller nothing: it needs the service role or the internal secret', async () => {
  const { resolveE2eRun } = await import('../../supabase/functions/_shared/e2e_run.ts');
  const SK = 'service-role-key-xyz', SECRET = 'internal-secret-abc';
  const ask = (h) => resolveE2eRun(new Headers(h), SK, async () => SECRET);
  assert.equal(await ask({ 'x-qd-e2e-run': 'ab12cd34' }), null, 'a bare tag is ignored');
  assert.equal(await ask({ 'x-qd-e2e-run': 'ab12cd34', authorization: 'Bearer some-user-jwt' }), null, 'a signed-in user is not internal');
  assert.equal(await ask({ 'x-qd-e2e-run': 'ab12cd34', 'x-qd-e2e-secret': 'internal-secret-abd' }), null, 'a wrong secret is ignored');
  assert.equal(await ask({ 'x-qd-e2e-run': 'AB;drop', 'x-qd-e2e-secret': SECRET }), null, 'a malformed tag is ignored');
  assert.deepEqual(await ask({ 'x-qd-e2e-run': 'ab12cd34', 'x-qd-e2e-secret': SECRET }), { tag: 'ab12cd34', secret: SECRET });
  assert.deepEqual(await ask({ 'x-qd-e2e-run': 'ab12cd34', authorization: 'Bearer ' + SK }), { tag: 'ab12cd34', secret: null });
  assert.equal(await resolveE2eRun(new Headers({ 'x-qd-e2e-run': 'ab12cd34', 'x-qd-e2e-secret': 'x' }), null, async () => null), null, 'no secret configured: nothing passes');
  // the database applies the same rule to a header that reaches PostgREST directly
  assert.match(sql, /->> 'role' = 'service_role'\s+then nullif\(nullif\(current_setting\('request\.headers', true\)/);
  assert.match(sql, /PROBE OK: .*public-header=/);
  assert.match(sql, /public-header-was-let-through/);
  // and observe() only sets the tag through the resolver
  const obs = readFileSync(new URL('../../supabase/functions/_shared/observe.ts', import.meta.url), 'utf8');
  assert.match(obs, /await resolveE2eRun\(req\.headers, envOr\('SUPABASE_SERVICE_ROLE_KEY'\), internalSecret\)/);
});

// Run 1be65ab2: the browser walk's own customer was refused every model although its window was open.
test('the run\'s own VERIFIED identity in its open window is let through; nothing else is', async () => {
  const { resolveE2eRunByIdentity, runTagOfEmail } = await import('../../supabase/functions/_shared/e2e_run.ts');
  const jwt = (email) => 'h.' + Buffer.from(JSON.stringify({ email })).toString('base64url') + '.s';
  const OWN = 'qd-ab12cd34-cust1@example.invalid';
  const U = (email, app, user) => ({ email, app_metadata: app, user_metadata: user });
  const FLAGGED = U(OWN, { e2e_run: 'ab12cd34' });
  const ask = (claimed, verified, open = true, secret = 'S') => resolveE2eRunByIdentity(
    new Headers({ authorization: 'Bearer ' + jwt(claimed) }), async () => verified,
    typeof open === 'function' ? open : async (t) => open && t === 'ab12cd34', async () => secret);
  assert.deepEqual(await ask(OWN, FLAGGED), { tag: 'ab12cd34', secret: 'S' });
  assert.equal(await ask(OWN, U(OWN, {})), null, 'self-signed-up with the right email but no flag: nothing');
  assert.equal(await ask(OWN, U(OWN, {}, { e2e_run: 'ab12cd34' })), null, 'flag only in user-writable user_metadata: nothing');
  assert.equal(await ask(OWN, U(OWN, { e2e_run: 'ffff0000' })), null, 'a flag for another run: nothing');
  assert.equal(await ask(OWN, FLAGGED, false), null, 'window closed or models off: nothing');
  assert.equal(await ask(OWN, FLAGGED, async () => { throw new Error('db down'); }), null, 'window lookup error: nothing');
  assert.equal(await ask(OWN, FLAGGED, async () => 'true'), null, 'only a literal true opens it');
  assert.equal(await resolveE2eRunByIdentity(new Headers({ authorization: 'Bearer ' + jwt(OWN) }), async () => { throw new Error('auth outage'); }, async () => true, async () => 'S'), null, 'auth outage: nothing');
  assert.equal(await ask(OWN, U('someone@gmail.com', { e2e_run: 'ab12cd34' })), null, 'a forged payload the auth server does not confirm: nothing');
  assert.equal(await ask(OWN, null), null, 'an unverifiable token: nothing');
  assert.equal(await ask('real@customer.ae', U('real@customer.ae', { e2e_run: 'ab12cd34' })), null, 'a real customer: nothing');
  assert.equal(await ask('qd-ab12cd34-x@gmail.com', U('qd-ab12cd34-x@gmail.com', { e2e_run: 'ab12cd34' })), null, 'only the reserved example.invalid domain');
  assert.equal(await ask(OWN, FLAGGED, true, null), null, 'no internal secret configured: nothing');
  assert.equal(await resolveE2eRunByIdentity(new Headers({ 'x-qd-e2e-run': 'ab12cd34' }), async () => FLAGGED, async () => true, async () => 'S'), null,
    'the tag header alone, with no signed-in identity: nothing');
  const fac = readFileSync(new URL('../lib/demo_factory.mjs', import.meta.url), 'utf8');
  assert.match(fac, /app_metadata: \{ e2e_run:/, 'the harness creates its users with the service-role-only flag');
  let calls = 0;
  await resolveE2eRunByIdentity(new Headers({ authorization: 'Bearer ' + jwt('real@customer.ae') }), async () => { calls++; return null; }, async () => true, async () => 'S');
  assert.equal(calls, 0, 'ordinary traffic never pays the auth round-trip');
  assert.equal(runTagOfEmail('QD-AB12CD34-C@EXAMPLE.INVALID'), 'ab12cd34');
  const obs = readFileSync(new URL('../../supabase/functions/_shared/observe.ts', import.meta.url), 'utf8');
  assert.match(obs, /resolveE2eRunByIdentity\(req\.headers,[\s\S]{0,200}auth\.getUser\(jwt\)[\s\S]{0,200}fn_e2e_run_tag_open/);
});

test('the harness enables models for its own tag only, and always turns them off', () => {
  assert.match(src, /set models_allowed = true, cap_usd = \$\{Number\(CAP_USD\)\}, expires_at = now\(\) \+ interval '2 hours'/);
  assert.match(src, /finally \{\s+\/\/ ALWAYS: models off/);
  assert.match(src, /set models_allowed = false where run_tag/);
  // the script never touches the founder's hold
  assert.doesNotMatch(src, /update public\.llm_route_health/);
});

test('the coverage classifier never calls an unknown feature tested', () => {
  const out = classify([{ kind: 'action', id: 'no_such_function.no_such_action' }, { kind: 'notice', id: 'no_such_notice' }]);
  assert.deepEqual(out.map((o) => o.status), ['uncovered', 'uncovered']);
  for (const [, , reason] of JUSTIFIED) assert.ok(reason.length > 40, 'every justification is a written reason');
  assert.ok(TESTED.every(([, , s]) => /^S\d\d$/.test(s)));
});
