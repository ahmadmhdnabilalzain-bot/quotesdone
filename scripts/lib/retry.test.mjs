// A blip is retried; a real failure is not; a subject that stays broken still fails.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { withRetry, isTransientDeployFailure } from './retry.mjs';

const noSleep = async () => {};

test('withRetry: a miss then a success returns the success', async () => {
  let n = 0;
  assert.equal(await withRetry(async () => { if (++n < 3) throw new Error('HTTP 503'); return 'rows'; }, 3, 1, noSleep), 'rows');
  assert.equal(n, 3);
});

test('withRetry: still unreadable after 3 attempts rethrows the last error (the gate stays red)', async () => {
  let n = 0;
  await assert.rejects(withRetry(async () => { n++; throw new Error(`edge_logs unreadable: HTTP 500 #${n}`); }, 3, 1, noSleep),
    /HTTP 500 #3/);
  assert.equal(n, 3);
});

test('deploy: the 21 Sep email_cron registry timeout is transient', () => {
  // Verbatim from main run 35619142770.
  assert.equal(isTransientDeployFailure("unexpected deploy status 400: Failed to bundle the function (reason: JSR package manifest for '@supabase/supabase-js' failed to load. Fetch 'https://jsr.io/@supabase/supabase-js/meta.json' timed out after 10s"), true);
  for (const t of ['read ECONNRESET', 'connect ETIMEDOUT 1.2.3.4:443', 'unexpected deploy status 502: Bad Gateway',
    'unexpected deploy status 504', 'error sending request for url (https://esm.sh/zod@3): connection closed']) {
    assert.equal(isTransientDeployFailure(t), true, t);
  }
});

test('deploy: a real error in our code is never retried, even when it names a registry', () => {
  for (const t of [
    'error: TS2304 [ERROR]: Cannot find name \'foo\'. at file:///supabase/functions/email_cron/index.ts:3:1',
    'unexpected deploy status 400: Failed to bundle the function (reason: Relative import path "x" not prefixed with / or ./ or ../)',
    'error: Module not found "https://deno.land/std@0.0.0/nope.ts" (timed out waiting is not the reason)',
    'The module\'s source code could not be parsed: Unexpected token `}`',
    'unexpected deploy status 400: Failed to bundle the function',
    '',
  ]) {
    assert.equal(isTransientDeployFailure(t), false, t);
  }
});
