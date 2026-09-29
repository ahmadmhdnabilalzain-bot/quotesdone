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
// Needs SUPABASE_ACCESS_TOKEN (the parity job has it). Without a token it FAILS rather than passing over nothing.
//
//   node --test scripts/checks/every_model_class_is_on_the_founders_matrix.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

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

async function run(query) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
      method: 'POST', headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query }),
    });
    const text = await res.text();
    if ((res.status === 429 || res.status >= 500) && attempt < 6) { await new Promise((r) => setTimeout(r, 2000 * 2 ** attempt)); continue; }
    const m = text.match(/CHK<<(.*?)>>/s);
    assert.ok(m, `the probe returned no verdict (HTTP ${res.status}): ${text.slice(0, 500)}`);
    return m[1];
  }
}

const replay = () => pendingPolicyFiles().map((n) => readFileSync(join(SQL, n), 'utf8')).join('\n;\n');
const probe = () => readFileSync(join(SQL, PROBE), 'utf8');

test('a management token is present (this check never passes over nothing)', () => {
  assert.ok(token(), 'SUPABASE_ACCESS_TOKEN is missing: the matrix was NOT verified');
});

test('every active model class has a seat and runs its route (pending model files replayed)', { skip: !token() }, async () => {
  const v = await run(replay() + '\n;\n' + probe());
  console.log('replayed:', pendingPolicyFiles().join(', ') || 'none', '|', v);
  assert.match(v, /^PROBE OK /, v);
});

test('a new class with no seat in the matrix fails the probe', { skip: !token() }, async () => {
  const v = await run(replay() + `\n;\ninsert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, active)
    values ('zz_probe_unmapped_class', 'medium', 'google/gemini-3.8-flash', 'deepseek/deepseek-v4.1-flash', 500, true);\n` + probe());
  assert.match(v, /zz_probe_unmapped_class has no seat in the matrix/, v);
});
