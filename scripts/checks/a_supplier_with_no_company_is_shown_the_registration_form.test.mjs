// A SUPPLIER WITH NO COMPANY YET IS SHOWN THE REGISTRATION FORM (13 Oct 2026, it_engineer, founder ruling 1230).
//
// Measured on production the night before the first invitation batch: a supplier signed in with no company - one who
// signed up at /portal without an invitation link, or whose invitation claim was refused - saw only "Something went
// wrong / Try again", on desktop and at 375 px, and could not register at all. supplier_portal's `dashboard` answered
// 400 { error: 'no_company' } with no `code`; since #858 (23 Sep) the shared call() in
// src/components/portal/supplier/api.ts stamps every non-2xx answer without a code as code 'load_failed', and
// Dashboard reads `j.code || j.error`, so it never saw no_company and never mounted Onboarding.
//
// The rule: a server answer that means "no company yet" carries code 'no_company', in every edge function.
// It reads source only (no network, no secret), so it runs in the checks job.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const strip = (s) => s.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, ' ');
const files = (d) => readdirSync(d).flatMap((f) => { const p = join(d, f); return statSync(p).isDirectory() ? files(p) : /\.ts$/.test(f) && !/\.test\.ts$/.test(f) ? [p] : []; });

test("every edge-function answer of error 'no_company' carries code 'no_company'", () => {
  const bad = [];
  for (const f of files(join(ROOT, 'supabase/functions'))) {
    const src = strip(readFileSync(f, 'utf8'));
    for (const m of src.matchAll(/\{[^{}]*error:\s*['"]no_company['"][^{}]*\}/g)) if (!/code:\s*['"]no_company['"]/.test(m[0])) bad.push(`${f.slice(ROOT.length)}: ${m[0].slice(0, 120)}`);
  }
  assert.deepEqual(bad, [], 'these answers reach the portal as code load_failed ("Something went wrong") instead of no_company (the registration form)');
});

test('the portal routes no_company to Onboarding, and call() keeps a server code', () => {
  const portal = strip(readFileSync(join(ROOT, 'src/components/portal/SupplierPortal.tsx'), 'utf8'));
  assert.match(portal, /if \(err === 'no_company'\) return <Onboarding/, 'Dashboard must mount Onboarding on no_company');
  assert.match(portal, /setErr\(\(j && \(j\.code \|\| j\.error\)\)/, 'Dashboard must read the server code first');
  const api = strip(readFileSync(join(ROOT, 'src/components/portal/supplier/api.ts'), 'utf8'));
  assert.match(api, /if \(!j\.code\) j\.code = 'load_failed'/, "call() changed how it fills a missing code - re-check that no_company still reaches Dashboard");
});
