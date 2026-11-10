// The repeat alert keys on a prompt hash every row carries, and spend is watched by class, idle floor and backlog
// (it_engineer, 5 Oct 2026; LLM burn audit "missing or blind" 1-4 and R6). Fails if: the gateway stops sending a prompt
// hash on any fn_llm_log call, or stops naming the claimed caller on its run row; fn_llm_log stops storing it; the
// repeat rule goes back to cache_hit_key (null on all 3,397 rows of 30 days) or counts refusals; or one of the class,
// idle-floor and backlog alerts is removed or turned into a cap (founder_instruction 987). Offline: committed tree.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { functionSource } from '../lib/function_sources.mjs';
import { readFileSync } from 'node:fs';

const FILE = 'scripts/sql/every_model_call_carries_its_prompt_hash_and_spend_is_watched_by_class.sql';
const SQL = readFileSync(FILE, 'utf8');
const GW = functionSource('ai_gateway');
const body = (name) => {
  const i = SQL.search(new RegExp(`create (or replace )?function public\\.${name}\\(`));
  assert.ok(i >= 0, `${name} is defined in ${FILE}`);
  return SQL.slice(i, SQL.indexOf('$fn$;', SQL.indexOf('$fn$', i) + 4));
};

test('every fn_llm_log call in the gateway carries the prompt hash', () => {
  assert.equal((GW.match(/rpcSafe\('fn_llm_log'/g) ?? []).length, 1, 'only the llmLog wrapper calls fn_llm_log directly');
  assert.match(GW, /const llmLog = \(args: Record<string, unknown>\) => rpcSafe\('fn_llm_log', \{ \.\.\.args, p_prompt_hash: promptHash \}\)/);
  assert.ok((GW.match(/llmLog\(\{/g) ?? []).length >= 7, 'every cost row goes through llmLog');
  assert.match(GW, /promptHash = await sha256\(\[fnName, sysStable, sys, JSON\.stringify\(convo\)\]/);
});

test('the gateway names the claimed caller on every run row, refused or not', () => {
  assert.match(GW, /return annotate\(await handle\(req\), claimed\)/);
  for (const k of ['claimed_fn', 'claimed_action', 'claimed_task_class']) assert.ok(GW.includes(k), k);
});

test('fn_llm_log stores the hash; the old 18-argument overload is dropped', () => {
  assert.match(SQL, /drop function if exists public\.fn_llm_log\(text, text, text, text, text, text, text, integer, integer, boolean, text, integer, boolean, numeric, integer, integer, text, numeric\);/);
  assert.match(body('fn_llm_log'), /p_prompt_hash text default null/);
  assert.match(body('fn_llm_log'), /seat_basis, prompt_hash\)/);
});

test('repeats key on prompt_hash over paid rows; class, idle floor and backlog alerts exist and only flag', () => {
  const ms = body('fn_it_engineer_model_spend');
  assert.match(ms, /a\.prompt_hash is not null and a\.model_used <> 'none'/);
  assert.doesNotMatch(ms, /cache_hit_key/);
  for (const item of ["'class_spend:'", "'idle_floor'", "'replay_stalled'", "'replay_slow'", "'replay_retries'"]) assert.ok(ms.includes(item), item);
  assert.match(ms, /fn_it_duty_settle\('model_spend', v_items\)/, 'every rule flags through the duty');
  assert.doesNotMatch(ms, /fn_llm_budget_gate|llm_daily_ceiling/, 'no cap');
});
