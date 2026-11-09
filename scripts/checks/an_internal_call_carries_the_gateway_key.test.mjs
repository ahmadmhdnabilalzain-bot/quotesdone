// AN INTERNAL CALL CARRIES THE GATEWAY KEY.
//
// MEASURED 23 Sep 2026 (it_engineer): finding duty:heartbeat:orphans.wa_templates_watch, seen 82 times,
// "HTTP 401". wa_templates_watch is verify_jwt=true (supabase/config.toml, generated from live), and
// resilience_ping's orphan step called it with {__secret} and no Authorization, so the platform
// gateway refused it before the function's own requireInternal ever ran. The same helper shape had no
// key on 14 internal calls, including ceo_agent (also verify_jwt=true). The file already had the fix
// for the accountant (GATEWAY, 15 Sep); it was never applied to the other helpers.
//
// This fails when:
//   1. any fetch to FN in resilience_ping sends headers without the GATEWAY key — resilience_ping calls
//      slugs chosen at run time, so every one of its internal calls must carry it;
//   2. any edge function fetches FN + '/<slug>' for a slug config.toml marks verify_jwt=true without an
//      Authorization header or GATEWAY in the same call.
//
//   node --test scripts/checks/an_internal_call_carries_the_gateway_key.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { functionFiles, functionSource } from '../lib/function_sources.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FNS = join(REPO, 'supabase', 'functions');
const read = (f) => readFileSync(f, 'utf8');

// The options object of every fetch(FN ...) call: from the call to the first "signal"/"body" line end.
const calls = (src) => [...src.matchAll(/fetch\(FN \+ ('\/' \+ \w+|'\/(\w+)')[\s\S]{0,400}?headers:\s*(\{[^}]*\}|\w+)/g)]
  .map((m) => ({ slug: m[2] || null, headers: m[3], at: src.slice(0, m.index).split('\n').length }));

const jwtRequired = new Set([...read(join(REPO, 'supabase', 'config.toml'))
  .matchAll(/\[functions\.(\w+)\]\s*\nverify_jwt = true/g)].map((m) => m[1]));

test('config.toml still names wa_templates_watch and ceo_agent as JWT-gated (the case this guards)', () => {
  assert.ok(jwtRequired.has('wa_templates_watch') && jwtRequired.has('ceo_agent'));
});

test('every internal call from resilience_ping carries the gateway key', () => {
  const found = calls(functionSource('resilience_ping'));
  assert.ok(found.length >= 10, `expected the internal calls, found ${found.length}`);
  const bare = found.filter((c) => !/GATEWAY|Authorization/.test(c.headers));
  assert.deepEqual(bare.map((c) => `line ${c.at} -> ${c.slug ?? '(dynamic)'}`), []);
});

test('no edge function calls a JWT-gated function without a key', () => {
  const bad = [];
  for (const d of readdirSync(FNS)) {
    if (!existsSync(join(FNS, d, 'index.ts'))) continue;
    // every runtime file of the function, not index.ts alone: a function split into modules keeps its calls there
    for (const f of functionFiles(d)) for (const c of calls(read(join(REPO, f)))) {
      if (c.slug && jwtRequired.has(c.slug) && c.headers.startsWith('{') && !/GATEWAY|Authorization/.test(c.headers)) {
        bad.push(`${f.replace('supabase/functions/', '')}:${c.at} -> ${c.slug}`);
      }
    }
  }
  assert.deepEqual(bad, []);
});
