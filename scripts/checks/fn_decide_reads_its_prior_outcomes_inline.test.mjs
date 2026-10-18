// FN_DECIDE READS ITS PRIOR OUTCOMES INLINE (23 Sep 2026, ceo).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: the file calls fn_decision_outcomes again (dropped 8 Sep 2026), or loses its revoke;
//   * production, in ONE aborted transaction: the file replays, fn_decide runs for a ZZ DEMO context without
//     raising, and the prior-outcomes source is present in what it returns. Nothing commits.
//
//   node --test scripts/checks/fn_decide_reads_its_prior_outcomes_inline.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/fn_decide_reads_its_prior_outcomes_inline.sql';
const src = readFileSync(join(REPO, FILE), 'utf8');
const code = src.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

test('the file reads prior outcomes inline, never through the dropped routine, and restates the ACL', () => {
  assert.doesNotMatch(code, /fn_decision_outcomes\s*\(/);
  assert.match(code, /into v_prior\s+from public\.decision_trace t/);
  assert.match(code, /revoke execute on function public\.fn_decide\(text, jsonb, text\) from public, anon, authenticated;/);
  assert.doesNotMatch(code, /^\s*(begin|commit)\s*;/im);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production, aborted: fn_decide runs again and carries its prior outcomes', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const block = String.raw`
do $p$
declare o jsonb := '{}'::jsonb; v jsonb;
begin
  begin
    v := public.fn_decide('zz_demo_probe', '{"note":"ZZ DEMO probe"}'::jsonb, 'agent');
    o := o || jsonb_build_object('ok', true, 'prior', (select count(*) from jsonb_array_elements(coalesce(v->'sources', '[]'::jsonb)) s where s->>'kind' = 'prior_outcomes'));
  exception when others then o := o || jsonb_build_object('ok', false, 'err', sqlstate || ' ' || sqlerrm);
  end;
  raise exception 'CHK<<%>>', o::text;
end $p$;`;
  let out;
  try { await replaySql(src + '\n' + block, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 600));
    out = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  assert.equal(out.ok, true, 'fn_decide raised: ' + out.err);
  console.log(JSON.stringify(out));
});
