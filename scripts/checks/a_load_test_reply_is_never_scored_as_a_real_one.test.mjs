// A LOAD-TEST REPLY IS NEVER SCORED AS A REAL ONE (customer_support, 19 Nov 2026). The weekly reply-quality row of 18 Nov
// scored the 11 Nov load run's 1,957 stubbed replies as real: the run-tag stamp dropped every load tag (it asked whether the
// window allows models, which a load window never does), the load teardown matched bare conversation ids against 'v-<id>'
// keys, and the weekly routine had no test-traffic rule. Repository only; the SQL is proved by its own probe.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(fileURLToPath(new URL('.', import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const SQL = read('scripts/sql/a_load_test_reply_is_never_scored_as_a_real_one.sql');
const STUB = read('supabase/functions/_shared/load_stub.ts');

test('the SQL recognises exactly the words the load stub answers with', () => {
  const en = /export const CANNED_TEXT = '([^']+)'/.exec(STUB)?.[1];
  const ar = /export const CANNED_TEXT_AR = '([^']+)'/.exec(STUB)?.[1];
  assert.ok(en && ar, 'load_stub.ts no longer exports its canned texts');
  const prefixes = [...SQL.matchAll(/reply, ''\) like '([^']+)%'/g)].map((m) => m[1]);
  assert.equal(prefixes.length, 2, 'the chat count names both canned texts');
  assert.ok(en.startsWith(prefixes[0]), 'the English canned reply changed: ' + prefixes[0]);
  assert.ok(ar.startsWith(prefixes[1]), 'the Arabic canned reply changed: ' + prefixes[1]);
});

test('the stamp keeps a tag for any open window, and the week leaves test traffic out', () => {
  const stamp = SQL.slice(SQL.indexOf('create or replace function public.fn_ai_cost_log_e2e_run_tag()'), SQL.indexOf('-- 2. THE WEEK'));
  assert.match(stamp, /w\.ended_at is null and w\.expires_at > now\(\)/);
  assert.doesNotMatch(stamp, /models_allowed|fn_e2e_run_tag_open\(/, 'the stamp asks the spend question again');
  assert.match(SQL, /r\.e2e_run_tag is null/);
  assert.match(SQL, /g\.e2e_run_tag is null/);
  assert.equal((SQL.match(/coalesce\(g\.audience, ''\) <> 'supplier_onboard'/g) ?? []).length, 2, 'onboarding turns count as sent chat replies again');
  assert.match(SQL, /v_m := public\.fn_customer_support_reply_quality_metrics\(v_from, now\(\), v_fx\)/);
  assert.match(SQL, /where q\.week_ending = date '2026-11-18'/, 'the 18 Nov row is recomputed');
  for (const sig of ['fn_customer_support_reply_quality_metrics(timestamptz, timestamptz, boolean)', 'fn_customer_support_reply_quality_below(jsonb)',
    'fn_customer_support_reply_quality_week()', 'fn_ai_cost_log_e2e_run_tag()']) {
    assert.ok(SQL.includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), sig + ' is not revoked');
  }
  assert.match(SQL, /select v as verdict from qd_probe_verdict;\s*$/);
});

test('a load run tags its turns and its teardown finds them', async () => {
  const site = read('supabase/functions/site_assistant/index.ts');
  assert.equal((site.match(/\.\.\.\(loadTag \? \{ e2e_run_tag: loadTag \} : \{\}\)/g) ?? []).length, 2, 'both assistant_logs writes carry the load tag');
  const { convKeyList } = await import('../load/chat_load_run.mjs');
  const id = '6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b';
  assert.equal(convKeyList([id]), `'${id}','v-${id}'`, 'the widget stores v-<id>; the teardown must match it');
  assert.equal(convKeyList(['not-a-uuid']), `''`);
  const run = read('scripts/load/chat_load_run.mjs');
  assert.doesNotMatch(run, /conv_id in \(\$\{uuidList/, 'a teardown matches bare ids again');
  assert.match(read('scripts/load/ramp_driver.mjs'), /'user-agent': 'qd-load-driver\/1 \(it_engineer\)',\n/);
});
