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
// The fake-router bite (fn_ai_route answering outside the class's pair) is opt-in, MATRIX_ROUTER_BITE=1, never in CI:
// it renames fn_ai_route under an exclusive lock. Run once by hand 19 Oct 2026 (#1501): it failed with "outside its
// pair" as it must, and fn_ai_route was unchanged afterwards.
//
//   node --test scripts/checks/every_model_class_is_on_the_founders_matrix.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';
import { branchAddedFiles } from '../lib/applies_at_merge.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SQL = join(REPO, 'scripts', 'sql');
const PROBE = 'every_seat_runs_the_founders_model_matrix_probe.sql';
const REF = 'htdblwldjkcgjvmqkbeh';

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  return existsSync(p) ? readFileSync(p, 'utf8').trim() : null;
}

const touchesPolicy = (n) => /update\s+public\.model_policy|insert\s+into\s+public\.model_policy/i.test(readFileSync(join(SQL, n), 'utf8'));
// THE PR'S OWN NEW MANIFEST LINES COME FIRST (it_engineer, 10 Nov 2026). Since #1797 a MANIFEST line applies itself at merge
// (scripts/lib/applies_at_merge.mjs), so on a branch those files are not on production yet. Without them a pending file that
// builds on one (customer_chat_and_the_reviewer_move_once_their_evals_pass.sql names Qwen, which only
// simple_tasks_leave_sonnet_and_every_reply_runs_on_the_model_its_task_needs.sql registers) failed at model_policy's
// registry trigger, and the probe was judged against a production the merge would change. On main the set is empty.
function prPolicyFiles() {
  return branchAddedFiles({ cwd: REPO }).map((f) => f.replace(/^scripts\/sql\//, '')).filter((n) => n !== PROBE && existsSync(join(SQL, n)) && touchesPolicy(n));
}
// pending change files that touch model_policy: what this PR, or a later eval-gated apply, puts on production
function pendingPolicyFiles() {
  return readdirSync(join(SQL, 'pending'))
    .map((n) => n.replace(/\.txt$/, '.sql'))
    .filter((n) => n !== PROBE && existsSync(join(SQL, n)))
    .filter(touchesPolicy)
    .sort();
}
const replayed = () => [...prPolicyFiles(), ...pendingPolicyFiles().filter((n) => !prPolicyFiles().includes(n))];

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
const replay = () => replayed().map((n) => readFileSync(join(SQL, n), 'utf8')).join('\n;\n');
const probe = () => readFileSync(join(SQL, PROBE), 'utf8');

test('a management token is present where the matrix must be verified',
  { skip: process.env.MATRIX_REQUIRE_LIVE !== '1' && 'no MATRIX_REQUIRE_LIVE: the parity job verifies it' }, () => {
  assert.ok(token(), 'SUPABASE_ACCESS_TOKEN is missing: the matrix was NOT verified');
});

test('every active model class has a seat and runs its route (pending model files replayed)', { skip: !token() }, async () => {
  const v = await run(replay() + '\n;\n' + probe());
  console.log('replayed:', replayed().join(', ') || 'none', '|', v);
  assert.match(v, /^PROBE OK /, v);
});

// 12 Oct 2026: luna's failure breaker opened at 14:46:56 UTC (five empty completions) while a PR ran this check, and
// the probe reported 11 review-route "drifts" over an unchanged model_policy. A breaker open for minutes is the
// router working, not a change to the matrix: tripping luna's and Gemini's breakers here must still give PROBE OK.
test('a failure breaker open for minutes is not matrix drift', { skip: !token() }, async () => {
  // A named probe that raises (a_sandbox_success_never_lifts_the_model_hold.test.mjs): the trip runs in the same
  // aborted transaction as the matrix probe, which always raises, and fails loudly if it tripped nothing.
  const trip = `do $trip$ declare n int; begin
  perform set_config('app.change_reason', 'probe:every_model_class_is_on_the_founders_matrix', true);
  update public.llm_route_health set open_until = now() + interval '5 minutes',
    opened_reason = 'zz probe: empty_completion trip', opened_class = 'empty_completion'
   where model_id in ('openai/gpt-6-luna-pro', 'anthropic/claude-sonnet-5.5');
  get diagnostics n = row_count;
  perform set_config('app.change_reason', '', true);
  if n <> 2 then raise exception 'CHK<<PROBE FAILED: the breaker trip touched % routes, not 2>>', n; end if;
end $trip$;`;
  const v = await run(replay() + '\n;\n' + trip + '\n' + probe());
  assert.match(v, /^PROBE OK /, v);
});

test('a new class with no seat in the matrix fails the probe', { skip: !token() }, async () => {
  const v = await run(replay() + `\n;\ninsert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, active)
    values ('zz_probe_unmapped_class', 'medium', 'openai/gpt-6-luna-pro', 'anthropic/claude-sonnet-5.5', 500, true);\n` + probe());
  assert.match(v, /zz_probe_unmapped_class has no seat in the matrix/, v);
});

// 18 Oct 2026 (rulings 1240, 1241): Gemini only hears, and the 5.6 generation is gone. Each bite is proved.
test('Gemini behind a class that does not hear fails the probe', { skip: !token() }, async () => {
  const v = await run(replay() + `
;
update public.model_policy set model_fallback = 'google/gemini-3.8-flash' where task_class = 'summarization';
` + probe());
  assert.match(v, /outside a recording name Gemini/, v);
});

test('a 5.6 model back in the registry fails the probe', { skip: !token() }, async () => {
  const v = await run(replay() + `
;
update public.model_registry set active = true, approved = true where model_id = 'openai/gpt-5.6-sol';
` + probe());
  assert.match(v, /5.6 model or plain luna is still active/, v);
});

// 19 Oct 2026 (it_engineer, #1501; rulings 1241, 1218): each table the router reads is seeded with a bad row, and the
// matrix probe must name it. model_policy itself refuses plain luna at write time (its registry trigger), so plain luna
// is seeded where it can still be written: the seat catch-all and a fallback chain.
const BITES = [
  ['Gemini as the primary of a class that does not hear', `update public.model_policy set model_primary = 'google/gemini-3.8-flash' where task_class = 'summarization';`, /outside a recording name Gemini/],
  ['Gemini behind a seat catch-all', `update public.model_policy_by_identity set fallback_model = 'google/gemini-3.8-flash' where identity_key = 'accountant';`, /outside a recording name Gemini/],
  ['Gemini on a chain that does not hear', `update public.model_fallback_chain set model = 'google/gemini-3.8-flash' where purpose = 'whatsapp_conversation' and rung = 2;`, /outside a recording name Gemini/],
  ['plain luna behind a seat catch-all', `update public.model_policy_by_identity set fallback_model = 'openai/gpt-6-luna' where identity_key = 'accountant';`, /5.6 model or plain luna/],
  ['plain luna on a chain', `update public.model_fallback_chain set model = 'openai/gpt-6-luna' where purpose = 'whatsapp_conversation' and rung = 2;`, /5.6 model or plain luna/],
];
for (const [name, seed, want] of BITES) {
  test(`${name} fails the probe`, { skip: !token() }, async () => {
    const v = await run(replay() + `\n;\nselect set_config('app.change_reason', 'probe:matrix bite', true);\n${seed}\n` + probe());
    assert.match(v, want, v);
  });
}

// fn_ai_route answers every active class with that class's own pair and nothing else, with the breakers shut and
// open, and never names Gemini for a class that does not hear. Raises CHK<<ROUTE OK>> or CHK<<ROUTE FAILED: ...>>.
const ROUTE = `do $route$ declare r record; j jsonb; bad text[] := '{}'; trip int; begin
  for trip in 0..1 loop
    if trip = 1 then
      perform set_config('app.change_reason', 'probe:fn_ai_route pair', true);
      update public.llm_route_health set open_until = now() + interval '5 minutes', opened_reason = 'zz probe', opened_class = 'empty_completion'
       where model_id in ('openai/gpt-6-luna-pro', 'anthropic/claude-sonnet-5.5', 'anthropic/claude-opus-5.5');
    end if;
    for r in select task_class, model_primary p, model_fallback f from public.model_policy
              where active and model_primary <> 'none' and model_primary not like '%:online' and model_primary not like 'perplexity/%' loop
      j := public.fn_ai_route(r.task_class, null, null, null, false, null, null);
      if coalesce(j->>'model', 'none') not in (r.p, coalesce(r.f, r.p), 'none')
         or coalesce(j->>'fallback', 'none') not in (r.p, coalesce(r.f, r.p), 'none') then
        bad := bad || (r.task_class || ' routed ' || coalesce(j->>'model', '-') || '>' || coalesce(j->>'fallback', '-')
                       || ' outside its pair ' || r.p || '>' || coalesce(r.f, '-'));
      end if;
      if r.task_class not in ('speech_transcription', 'marketing_watch')
         and (coalesce(j->>'model', '') || coalesce(j->>'fallback', '')) like '%gemini%' then
        bad := bad || (r.task_class || ' does not hear and routed Gemini');
      end if;
    end loop;
  end loop;
  if cardinality(bad) > 0 then raise exception 'CHK<<ROUTE FAILED: %>>', array_to_string(bad, '; '); end if;
  raise exception 'CHK<<ROUTE OK>>';
end $route$;`;

test('fn_ai_route returns only the class\'s own pair, breakers shut or open', { skip: !token() }, async () => {
  const v = await run(replay() + '\n;\n' + ROUTE);
  assert.match(v, /^ROUTE OK/, v);
});

test('fn_ai_route putting Gemini on a class that does not hear fails', { skip: !token() }, async () => {
  const v = await run(replay() + `\n;\nselect set_config('app.change_reason', 'probe:route bite', true);
update public.model_policy set model_fallback = 'google/gemini-3.8-flash' where task_class = 'summarization';\n` + ROUTE);
  assert.match(v, /summarization does not hear and routed Gemini/, v);
});

// OPT-IN ONLY (MATRIX_ROUTER_BITE=1, never set in CI): renaming fn_ai_route takes an ACCESS EXCLUSIVE lock on it for the
// replay, which would stall every live model call. Run once by hand, 19 Oct 2026 (it_engineer, #1501): the fake router
// answering deepseek/deepseek-v4.1-flash failed the route test with "outside its pair"; fn_ai_route was unchanged after.
test('fn_ai_route answering outside the class\'s pair fails',
  { skip: (!token() || process.env.MATRIX_ROUTER_BITE !== '1') && 'opt-in: MATRIX_ROUTER_BITE=1 (locks fn_ai_route; never in CI)' }, async () => {
  // The live router keeps to the pair even with the pair's registry rows off (it answers 'none'), so the bite swaps in,
  // inside the rolled-back replay only, a router that answers the cheapest-of-the-registry way the 18 Oct fix removed.
  const v = await run(replay() + `\n;\nalter function public.fn_ai_route(text, text, numeric, text, boolean, text[], text) rename to fn_ai_route_zz_probe_real;
create function public.fn_ai_route(text, text, numeric, text, boolean, text[], text) returns jsonb language sql
  as $f$ select jsonb_build_object('model', 'deepseek/deepseek-v4.1-flash', 'fallback', null) $f$;\n` + ROUTE);
  assert.match(v, /outside its pair/, v);
});
