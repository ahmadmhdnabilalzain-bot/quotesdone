// THE SCHEDULER AND THE COMPANY SEAL ARE NOT PUBLIC (it_engineer, pre-launch security pass, 6 Oct 2026).
// Each test fails if the cause of finding M2 or M4 returns.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const strip = (s) => s.replace(/^\s*\/\/.*$/gm, '');

test('M2: an anonymous resilience_ping call runs no step and writes no tick row', () => {
  const src = read('supabase/functions/resilience_ping/index.ts');
  const serve = src.slice(src.indexOf('Deno.serve('), src.indexOf('const sweep = observe('));
  // Two shapes carry the same property: the ternary, or (since 12 Oct 2026, #1305, the detached slow steps) a
  // gate that returns liveness for any unauthenticated call BEFORE the handler reads the body, starts a detached
  // run or reaches sweep. Either way the decision is made here, outside observe(), and first.
  const ternary = /\(await tickCaller\(req\)\) \? sweep\(req\) : liveness\(req\)/.test(serve);
  const gate = serve.search(/if \(!\(await tickCaller\(req\)\)\) return liveness\(req\);/);
  assert.ok(ternary || gate > 0, 'the auth decision must sit outside observe()');
  if (!ternary) {
    for (const after of ['req.clone()', 'runDetached(', 'sweep(req)']) {
      const at = serve.indexOf(after);
      assert.ok(at < 0 || at > gate, after + ' must come after the tickCaller gate');
    }
  }
  const live = src.slice(src.indexOf('async function liveness('), src.indexOf('Deno.serve('));
  assert.ok(!/STEP_RUN|runSteps|drain/.test(live), 'liveness must not run a step');
});

test('M4: the stamp and the signature are read from the private bucket', () => {
  const src = read('supabase/functions/pdf_native/index.ts');
  assert.match(src, /SEAL_BUCKET = 'company-seal'/);
  assert.match(src, /storage\.from\(SEAL_BUCKET\)\.download/);
});
