// A FAILED EMBEDDING IS NEVER ANSWERED AS OK. Seat: it_engineer. 22 Sep 2026 (instruction 645).
//
// Measured 22 Sep 2026: ai_gateway's {action:'embed'} answered {ok:true, embedding:null} with HTTP 200
// whenever gte-small threw, because embed() returns null on any error and the action passed that null
// straight through. a_catalogue_line_is_understood_by_meaning.test.mjs failed once on exactly that.
// This fails if the null-vector answer ever says ok:true again -- in the pure answer function, and in
// the gateway source, which must route the embed action through it rather than build its own reply.
//
//   node --test scripts/checks/a_failed_embedding_is_never_answered_as_ok.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { functionSource } from '../lib/function_sources.mjs';
import { readFileSync } from 'node:fs';

const ROOT = new URL('../../', import.meta.url);
const { embedAnswer } = await import(new URL('supabase/functions/_shared/embed_answer.ts', ROOT).href);

test('a null, empty or non-string vector is 503 embed_failed, never ok:true', () => {
  for (const v of [null, undefined, '', '[]', 42]) {
    const a = embedAnswer(v);
    assert.equal(a.status, 503, `status for ${JSON.stringify(v)}`);
    assert.equal(a.body.ok, false);
    assert.equal(a.body.error, 'embed_failed');
    assert.equal(a.body.embedding ?? null, null);
  }
});

test('a real vector is 200 ok:true and carries the vector unchanged', () => {
  const a = embedAnswer('[0.1,0.2,0.3]');
  assert.deepEqual(a, { status: 200, body: { ok: true, embedding: '[0.1,0.2,0.3]' } });
});

test("ai_gateway answers the embed action only through embedAnswer", () => {
  const src = functionSource('ai_gateway').replace(/\r\n/g, '\n');
  const start = src.indexOf("body.action === 'embed'");
  assert.ok(start > 0, 'the embed action branch was not found in the ai_gateway function');
  const branch = src.slice(start, src.indexOf('\n    }\n', start));
  assert.match(branch, /embedAnswer\(/, 'the embed branch no longer uses embedAnswer');
  assert.match(branch, /return J\(a\.body, a\.status\)/, 'the embed branch must return embedAnswer\'s status');
  assert.doesNotMatch(branch, /ok:\s*true/, 'the embed branch builds its own ok:true reply again');
  assert.match(src, /import \{ embedAnswer \} from '\.\.\/_shared\/embed_answer\.ts'/);
});
