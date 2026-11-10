// EVERY MATCHER THAT HAS A BRIEF PASSES ITS SERVICES (22 Sep 2026, sales_engineer, finding SP-F-01).
//
// WHAT WENT WRONG. public.fn_match_capability grew a ninth argument, p_services, on 15 Sep 2026 —
// the founder's "cross matching main source": when the inquiry names a service, only a supplier
// whose CONFIRMED service list covers one of them is a candidate. MEASURED 22 Sep 2026: not one
// caller passed it. Every production call sent 8 arguments, p_services defaulted to '{}', the gate
// never fired once, and matching stayed at trade level while the Services tab looked like it was
// deciding something. A capability with no caller is a capability that does not exist.
//
// WHAT THIS FAILS ON. A call to fn_match_capability from an edge function that does NOT pass
// p_services and is not one of the two calls that have no brief to read services from. Those two
// are named below with the reason, so adding a third is a deliberate act and not an omission.
//
//   node --test scripts/checks/every_matcher_that_has_a_brief_passes_its_services.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FUNCTIONS = join(REPO, 'supabase', 'functions');
const walk = (d) => readdirSync(d).flatMap((f) => {
  const p = join(d, f);
  return statSync(p).isDirectory() ? walk(p) : /\.tsx?$/.test(f) && !/\.test\.tsx?$/.test(f) ? [p] : [];
});

// THE CALLS WITH NO BRIEF. Neither has a customer's words to read services from, so both are
// trade-level by design:
//   public_site      the public category page counts "suppliers in this trade" for a visitor who
//                    has not written anything yet.
//   customer_api     the `discover` search is a free-text TRADES box; the customer names trades,
//                    not a job, and the endpoint exists to answer "who does this trade".
//
// EXEMPTED PER CALL, NOT PER FILE (review of #859, 23 Sep 2026). Keying this on the file name would
// have let a SECOND fn_match_capability call inside customer_api — one that does read an inquiry —
// pass in silence, which is the very shape of the defect this check exists for. The exemption is now
// a marker the call itself must carry, on the line before it or inside its arguments:
const TRADE_LEVEL_MARKER = 'trade-level by design: no brief';

/** Every fn_match_capability rpc call in a file: its argument object, and the comment above it. */
const MARKER_LOOKBACK = 9;
function callsIn(src) {
  const out = [];
  for (const m of src.matchAll(/\.rpc\(\s*['"`]fn_match_capability['"`]\s*,\s*\{/g)) {
    const open = m.index + m[0].length - 1;
    let depth = 0, i = open;
    for (; i < src.length; i++) {
      if (src[i] === '{') depth++;
      else if (src[i] === '}' && --depth === 0) break;
    }
    const before = src.slice(0, m.index).split('\n').slice(-MARKER_LOOKBACK).join('\n');
    out.push({ args: src.slice(open, i + 1), before, line: src.slice(0, m.index).split('\n').length });
  }
  return out;
}

test('every edge-function matcher with a brief passes p_services', () => {
  const missing = [];
  let seen = 0;
  for (const file of walk(FUNCTIONS)) {
    const rel = file.slice(FUNCTIONS.length + 1).replace(/\\/g, '/');
    const src = readFileSync(file, 'utf8');
    for (const c of callsIn(src)) {
      seen++;
      if (/\bp_services\s*:/.test(c.args)) continue;
      if (c.before.includes(TRADE_LEVEL_MARKER) || c.args.includes(TRADE_LEVEL_MARKER)) continue;
      missing.push(`${rel}:${c.line}`);
    }
  }
  assert.ok(seen >= 4, `fn_match_capability is called ${seen} time(s); this check has lost its subject`);
  assert.deepEqual(missing, [], 'these matchers read an inquiry and still match at trade level only');
});

test('the dispatching matcher derives the keys with the one shared reader, and stores only a whole reading', () => {
  const src = functionSource('sales_engineer');
  assert.match(src, /serviceKeysOf\(/, 'sales_engineer no longer derives the inquiry services');
  assert.match(src, /from '(?:\.\.\/)+_shared\/service_vocabulary\.ts'/, 'the reader is no longer the shared one');
  // Since 29 Sep 2026 (ruling 890, decision point 93) the reader is exact-or-meaning, all or nothing: a text it
  // could not read whole must not be stored as '{}' ("names no service"), or the inquiry is never read again.
  assert.match(src, /if \(sk\.complete\) await admin\.from\('inquiries'\)\.update\(\{ service_keys: serviceKeys \}\)/,
    'an incomplete reading is stored as if the inquiry named no service');
  // ONE READER. service_vocabulary.ts owns both the vocabulary select and the inquiry read, so the inquiry
  // side and the Services tab cannot drift apart into two answers.
  const shared = readFileSync(join(FUNCTIONS, '_shared', 'supplier_services.ts'), 'utf8');
  assert.match(shared, /from '\.\/service_vocabulary\.ts'/, 'the Services tab kept its own copy of the vocabulary read');
});

test('the column the keys are stored in is declared and carried by the MANIFEST', () => {
  const sql = readFileSync(join(REPO, 'scripts', 'sql', 'an_inquiry_carries_the_services_it_names.sql'), 'utf8');
  assert.match(sql, /alter table public\.inquiries add column if not exists service_keys text\[\]/);
  const manifest = readFileSync(join(REPO, 'scripts', 'sql', 'MANIFEST.txt'), 'utf8');
  assert.ok(manifest.includes('scripts/sql/an_inquiry_carries_the_services_it_names.sql'), 'the change file has no MANIFEST line');
});
