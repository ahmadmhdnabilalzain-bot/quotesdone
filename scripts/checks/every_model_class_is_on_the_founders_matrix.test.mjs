// EVERY MODEL CLASS IS ON THE FOUNDER'S MATRIX (29 Sep 2026, marketing; founder_instruction 1056).
//
// #1114 merged after the matrix (#1126) and added three classes on openai/gpt-5.6-sol. The matrix probe caught it
// only when somebody ran it by hand. This runs it on every pull request: the probe
// (scripts/sql/every_seat_runs_the_founders_model_matrix_probe.sql) now names every active model class with its seat
// and route (section 4), so a NEW class with no seat in the matrix, or a class off its route, fails the merge.
//
// ONE aborted transaction per run: every SQL file that still has a note in scripts/sql/pending/ and changes
// model_policy is replayed first (it is what the PR will apply at merge), then the probe, which always raises.
// Nothing survives. A second run adds an unmapped class first and must FAIL - the guard is proved to bite.
//
// Needs SUPABASE_ACCESS_TOKEN. The parity job has it and runs this with MATRIX_REQUIRE_LIVE=1, so there a missing
// token FAILS rather than passing over nothing; the tokenless checks job reports the production tests as skipped.
//
//   node --test scripts/checks/every_model_class_is_on_the_founders_matrix.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SQL = join(REPO, 'scripts', 'sql');
const PROBE = 'every_seat_runs_the_founders_model_matrix_probe.sql';
const REF = 'htdblwldjkcgjvmqkbeh';

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  return existsSync(p) ? readFileSync(p, 'utf8').trim() : null;
}

// pending change files that touch model_policy: what this PR applies at merge
function pendingPolicyFiles() {
  return readdirSync(join(SQL, 'pending'))
    .map((n) => n.replace(/\.txt$/, '.sql'))
    .filter((n) => n !== PROBE && existsSync(join(SQL, n)))
    .filter((n) => /update\s+public\.model_policy|insert\s+into\s+public\.model_policy/i.test(readFileSync(join(SQL, n), 'utf8')))
    .sort();
}

// Through scripts/lib/safe_replay.mjs (30 Sep 2026): a pending file's own COMMIT once ran before this probe's raise
// and applied the file to production. The helper strips a file's transaction lines, refuses what cannot be rolled
// back, always ends in a raise, and checks afterwards that nothing it creates changed.
async function run(query) {
  let text = '';
  try { await replaySql(query, { ref: REF, label: 'the model-matrix replay' }); } catch (e) { if (e.throttled) throw e; text = String(e.body ?? e.message); }
  const m = text.match(/CHK<<(.*?)>>/s);
  assert.ok(m, `the probe returned no verdict: ${text.slice(0, 500)}`);
  return m[1];
}

// The pending files as they are: run() sends them through safe_replay, which drops their own transaction lines
// (the_retired_model_leaves_every_live_routine_and_the_judgement_queue_says_what_it_does.sql carried a pair and was
// applied by this check's older transport, 30 Sep 2026) and refuses ROLLBACK and the rest.
const replay = () => pendingPolicyFiles().map((n) => readFileSync(join(SQL, n), 'utf8')).join('\n;\n');
const probe = () => readFileSync(join(SQL, PROBE), 'utf8');

test('a management token is present where the matrix must be verified',
  { skip: process.env.MATRIX_REQUIRE_LIVE !== '1' && 'no MATRIX_REQUIRE_LIVE: the parity job verifies it' }, () => {
  assert.ok(token(), 'SUPABASE_ACCESS_TOKEN is missing: the matrix was NOT verified');
});

test('every active model class has a seat and runs its route (pending model files replayed)', { skip: !token() }, async () => {
  const v = await run(replay() + '\n;\n' + probe());
  console.log('replayed:', pendingPolicyFiles().join(', ') || 'none', '|', v);
  assert.match(v, /^PROBE OK /, v);
});

// 12 Oct 2026: luna's failure breaker opened at 14:46:56 UTC (five empty completions) while a PR ran this check, and
// the probe reported 11 review-route "drifts" over an unchanged model_policy. A breaker open for minutes is the
// router working, not a change to the matrix: tripping luna's and Gemini's breakers here must still give PROBE OK.
test('a failure breaker open for minutes is not matrix drift', { skip: !token() }, async () => {
  const v = await run(replay() + `\n;\nupdate public.llm_route_health set open_until = now() + interval '5 minutes',
    opened_reason = 'zz probe: empty_completion trip', opened_class = 'empty_completion' where model_id in ('openai/gpt-6-luna', 'google/gemini-3.8-flash');\n` + probe());
  assert.match(v, /^PROBE OK /, v);
});

test('a new class with no seat in the matrix fails the probe', { skip: !token() }, async () => {
  const v = await run(replay() + `\n;\ninsert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, active)
    values ('zz_probe_unmapped_class', 'medium', 'openai/gpt-6-luna', 'google/gemini-3.8-flash', 500, true);\n` + probe());
  assert.match(v, /zz_probe_unmapped_class has no seat in the matrix/, v);
});
