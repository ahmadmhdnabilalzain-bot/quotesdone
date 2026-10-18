// site_error_ingest without SITE_ERROR_INGEST_SECRET must open an it_engineer finding, not answer a
// quiet 503 (it_engineer, 7 Oct 2026, stage-2 run fe7ba9c4 S20). Measured that day: the secret was set
// neither on the function nor on Vercel, error_events held 0 website rows ever, and nothing said so.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const src = readFileSync('supabase/functions/site_error_ingest/index.ts', 'utf8');

test('the not-configured branch raises the finding before it answers', () => {
  const branch = src.split('\n').find((l) => /if \(!WANT\)/.test(l)) || '';
  assert.match(branch, /await raiseNotConfigured\(\)/);
  const fn = src.slice(src.indexOf('async function raiseNotConfigured'));
  assert.match(fn, /fn_it_engineer_finding_upsert/);
  assert.match(fn, /p_raised_by: 'it_engineer'/);
  assert.match(fn, /SITE_ERROR_INGEST_SECRET/);
});
