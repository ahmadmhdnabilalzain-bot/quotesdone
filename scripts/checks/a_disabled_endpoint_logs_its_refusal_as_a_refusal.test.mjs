// A DISABLED ENDPOINT LOGS ITS REFUSAL AS A REFUSAL (28 Sep 2026, it_engineer).
//
// The cause: voice_otp_capture (closed 18 Jul) logs every hit to agent_runs. Its row carried only
// {disabled:true} at status 'error', so the IT detector's run_failure rule read two hits at 12:38 UTC
// as "failed every one of its 2 attempts" and opened a CRITICAL finding. D1 excludes a row whose
// counts.http is a 4xx; the row now carries the status the handler answers.
//
// WHAT FAILS IF THE CAUSE RETURNS: the logged counts stop carrying http, or it stops matching the
// status the Response is built with.
//
//   node --test scripts/checks/a_disabled_endpoint_logs_its_refusal_as_a_refusal.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

test('voice_otp_capture logs counts.http equal to the 4xx it answers', () => {
  const src = readFileSync(join(REPO, 'supabase/functions/voice_otp_capture/index.ts'), 'utf8');
  const logged = src.match(/counts: \{[^}]*\bhttp: (\d{3})/);
  const answered = src.match(/new Response\(HANGUP, \{ status: (\d{3})/);
  assert.ok(logged, 'the agent_runs row carries no counts.http, so the detector reads the refusal as a failure');
  assert.ok(answered, 'the handler response status was not found');
  assert.equal(logged[1], answered[1], 'the logged http does not match the status the handler answers');
  assert.match(logged[1], /^4\d\d$/, 'a refusal must be a 4xx for the detector to exclude it');
});
