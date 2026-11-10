// THE FOUNDER HEARS BEFORE THE AI CREDIT RUNS OUT (accountant, 10 Nov 2026).
//
// On 10 Nov 2026 the OpenRouter balance reached USD 1.28 and about half of all model calls then failed with 402; the
// homepage widget told visitors "something went wrong". The meter was read ~14 times a day and nothing warned anyone.
// scripts/sql/the_founder_hears_before_the_ai_credit_runs_out.sql built the warning.
//
// This fails if the hourly job is unscheduled, if the thresholds (USD 10 low, USD 2 critical) move or a missing reading
// counts as fine, if the warning stops going through fn_notify_founder with the allowed kind finance_reminder, or if it
// is no longer once a day per band. It reads the schema mirror together with the MANIFEST-listed SQL, code only.
//
//   node --test scripts/checks/the_founder_hears_before_the_ai_credit_runs_out.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const ROOT = join(import.meta.dirname, '..', '..');
const manifest = readFileSync(join(ROOT, 'scripts/sql/MANIFEST.txt'), 'utf8').split('\n').map((l) => l.trim())
  .filter((l) => l && !l.startsWith('#')).map((l) => (l.startsWith('scripts/') ? l : `scripts/sql/${l}`));
const applied = manifest.filter((f) => existsSync(join(ROOT, f))).map((f) => readFileSync(join(ROOT, f), 'utf8')).join('\n');
const code = (readSchemaMirror() + '\n' + applied).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

const lastDefinition = (name) => {
  const all = [...code.matchAll(new RegExp(`create or replace function public\\.${name}\\([^]*?\\n\\$(fn|function)\\$;?`, 'gi'))];
  return all.length ? all[all.length - 1][0] : null;
};

test('openrouter_low_balance_hourly is scheduled hourly and names its seat', () => {
  assert.match(code, /cron\.schedule\('openrouter_low_balance_hourly',\s*'23 \* \* \* \*',\s*\$CRON\$select public\.fn_openrouter_low_balance_tick\(\);\$CRON\$\)/);
  assert.doesNotMatch(code, /cron\.unschedule\('openrouter_low_balance_hourly'\)/, 'the warning is unscheduled by a later file');
  assert.match(code, /\('cron_job', 'openrouter_low_balance_hourly', 'accountant'/, 'the job must name its seat in writer_seat');
});

test('the band: under USD 2 critical, under USD 10 low, no reading is unknown (never ok)', () => {
  const band = lastDefinition('fn_openrouter_balance_band');
  assert.ok(band, 'fn_openrouter_balance_band is not defined');
  assert.match(band, /when p_balance_usd is null then 'unknown'/);
  assert.match(band, /when p_balance_usd < 2 then 'critical'/);
  assert.match(band, /when p_balance_usd < 10 then 'low'/);
});

test('the warning goes to the founder once a day per band, with an allowed kind', () => {
  const tick = lastDefinition('fn_openrouter_low_balance_tick');
  assert.ok(tick, 'fn_openrouter_low_balance_tick is not defined');
  assert.match(tick, /from public\.v_openrouter_position/);
  assert.match(tick, /v_key := 'openrouter_low:' \|\| v_band \|\| ':' \|\| to_char\(now\(\) at time zone 'Asia\/Dubai', 'YYYY-MM-DD'\)/, 'once a day per band');
  assert.match(tick, /exists \(select 1 from public\.founder_alerts f where f\.dedupe_key = v_key and f\.channel = 'email'\)/, 'no second email the same day');
  assert.match(tick, /public\.fn_notify_founder\([^;]*p_kind => 'finance_reminder'[^;]*p_owner_agent => 'accountant'\)/);
  assert.match(code, /revoke execute on function public\.fn_openrouter_low_balance_tick\(\) from public, anon, authenticated/);
  assert.match(code, /revoke execute on function public\.fn_openrouter_balance_band\(numeric\) from public, anon, authenticated/);
});
