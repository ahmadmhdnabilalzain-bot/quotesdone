// THE CEO'S WEEKLY PLAN IS RETRIED AND FITS THE GATEWAY'S DEADLINE (ceo, agent L1_CEO, 16 Nov 2026; ledger 1448).
// Measured 16 Nov (SELECT): the first weekly plan (ceo_plan_week id 12) was cut at the gateway's 112 s wall with 0 output
// tokens; ceo_agent had asked 8,000 answer tokens + the gateway's 8,000 thinking headroom = 16,000 tokens, 147 s at Opus 5.5's
// measured p50 throughput. The hand-over's two-hour retry then missed the 17:30 tick by 18 s, and a second cut would have held
// the plan for good.
// This fails when: the weekly call is sized past the gateway's wall again; the retry waits two hours again; a cut by our own
// clock counts as the model's answer (held after two) or a plan held by it is never reopened; the hand-over writes; or
// LOCAL (QD_LOCAL_DB_URL, never production) the file's probe stops reading PROBE OK.
//   env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL QD_LOCAL_DB_URL=<local url> node --test scripts/checks/the_ceos_weekly_plan_is_retried_and_fits_the_gateway_deadline.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const NAME = 'the_ceos_weekly_plan_is_retried_and_fits_the_gateway_deadline';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const C = read(FILE).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const fnBody = (name) => { const at = C.indexOf(`create or replace function public.${name}(`); return at < 0 ? '' : C.slice(at, C.indexOf('$fn$;', at)); };
const LOCAL = process.env.QD_LOCAL_DB_URL || '';

test('1. the weekly call is sized to end inside the gateway wall; ceo_agent uses that size', async () => {
  const { PLAN_CALL, PLAN_CALL_BASIS: b, planCallFor } = await import(join(REPO, 'supabase/functions/ceo_agent/plan.ts'));
  const { headroomFor } = await import(join(REPO, 'supabase/functions/_shared/request_shape.ts'));
  const worst = b.promptMs + (PLAN_CALL.weekly.max + headroomFor('high')) / b.opusTokensPerSecondP5 * 1000;
  const wall = PLAN_CALL.weekly.timeoutMs + b.llmDeclaresExtraMs - b.gatewayKeepsMs;
  assert.ok(worst <= wall + 2000, `worst ${Math.round(worst)} ms against the wall ${wall} ms`);
  assert.ok(wall + b.gatewayKeepsMs + 2000 <= b.edgeWallMs, 'the wall is past the edge\'s 150 s');
  assert.deepEqual(planCallFor('ceo_strategic_planning'), PLAN_CALL.weekly);
  const idx = read('supabase/functions/ceo_agent/index.ts');
  assert.match(idx, /const c = planCallFor\(taskClass\);/);
  assert.match(idx, /max: c\.max, timeoutMs: c\.timeoutMs/);
  assert.doesNotMatch(idx, /daily \? 2000 : 8000|daily \? 40000 : 110000/, 'the old sizes are back');
});

test('2. a cut by our own clock is retried at the next tick, three calls at most, and a plan it held is reopened by the duty', () => {
  assert.match(fnBody('fn_ceo_plan_cut_by_our_clock'), /gateway_deadline\|gateway_wall\|client_timeout_\[0-9\]\+ms\|gateway_http_504/);
  assert.match(fnBody('fn_ceo_plan_file'), /p\.attempts < 2 or \(p\.attempts < 3 and public\.fn_ceo_plan_cut_by_our_clock\(p_error\)\)/);
  const ho = fnBody('fn_ceo_plan_handover');
  assert.match(ho, /interval '105 minutes'/);
  assert.doesNotMatch(ho, /interval '2 hours'|update public|insert into|fn_ceo_planning_pack/);
  assert.match(fnBody('fn_ceo_planning_loop_tick'), /fn_ceo_plan_reopen_cut\(now\(\)\)/);
  const re = fnBody('fn_ceo_plan_reopen_cut');
  assert.match(re, /w\.attempts < 3/); assert.match(re, /w\.error not like 'asked again%'/); assert.match(re, /w\.output is null/);
  assert.match(fnBody('fn_ceo_plan_contract'), /at most 2,500 words/);
});

test('3. a file not yet applied has its pending notes and no MANIFEST line', () => {
  const listed = read('scripts/sql/MANIFEST.txt').split('\n').includes(FILE);
  assert.ok(listed !== existsSync(join(REPO, `scripts/sql/pending/${NAME}.txt`)));
  assert.ok(existsSync(join(REPO, PROBE)));
});

test('4. LOCAL: the probe reads PROBE OK', { skip: LOCAL ? false : 'NOT RUN: no QD_LOCAL_DB_URL (never production)' }, () => {
  const r = spawnSync('psql', [LOCAL, '-qAtX', '-f', join(REPO, PROBE)], { encoding: 'utf8' });
  const out = String(r.stdout || '') + String(r.stderr || '');
  assert.match(out, /CHK<<PROBE OK/, out.slice(0, 1500));
});
