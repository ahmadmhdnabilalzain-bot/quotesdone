// NO SUPABASE CLIENT IS BUILT AT IMPORT.
//
// 15 Sep 2026: a module-level createClient('') in CustomerPortal.tsx threw during prerender once
// the Preview env vars were deleted, and every Preview build failed. src/lib/supaClient.ts builds
// the client on first use; this fails if any other file in src/ can construct one - a
// createClient( call, or an import of a client constructor from supabase-js or @supabase/ssr under
// any local name (named, aliased, or through a namespace import).
//
//   node --test scripts/checks/no_module_level_supabase_client.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const SRC = path.join(REPO, 'src');
const OWNER = path.join('src', 'lib', 'supaClient.ts');
// GoTrueClient: since 28 Sep 2026 supaClient.ts builds the auth-js client directly (portal bundle cut).
const CTOR = '(?:create(?:Browser|Server)?Client|GoTrueClient)';
const PKG = `['"]@supabase/(?:supabase-js|ssr|auth-js)['"]`;

// Every reason one file's text could construct a Supabase client. Empty = clean.
export function offences(text) {
  const out = [];
  if (new RegExp(`\\b${CTOR}\\s*\\(`).test(text)) out.push('calls a client constructor');
  for (const m of text.matchAll(new RegExp(`import\\s+(type\\s+)?([^;]*?)\\s+from\\s*${PKG}`, 'g'))) {
    // `import type { GoTrueClient }` and an inline `{ type GoTrueClient }` are erased by the compiler: they can name the
    // class as a parameter type and can never construct one (11 Nov 2026: src/lib/adminTwoStep.ts takes the client as an
    // argument and was reported as constructing it). A value import of the same name is still an offence.
    if (m[1]) continue;
    const clause = m[2];
    const named = clause.match(/\{([^}]*)\}/);
    const values = named ? named[1].split(',').map((s) => s.trim()).filter((s) => s && !/^type\s/.test(s)).join(', ') : '';
    if (values && new RegExp(`(^|[\\s,])${CTOR}\\b`).test(values)) out.push('imports a client constructor');
    const ns = clause.match(/\*\s*as\s+([A-Za-z_$][\w$]*)/);
    if (ns && new RegExp(`\\b${ns[1].replace(/\$/g, '\\$')}\\s*\\.\\s*${CTOR}\\b`).test(text)) out.push(`uses ${ns[1]}.<constructor> from a namespace import`);
  }
  return out;
}

test('the detector catches named, aliased and namespace forms, and passes type-only use', () => {
  assert.notDeepEqual(offences(`import { createClient } from '@supabase/supabase-js';`), []);
  assert.notDeepEqual(offences(`import { createClient as cc } from '@supabase/supabase-js';\nconst SB = cc(u, k);`), []);
  assert.notDeepEqual(offences(`import {\n  type SupabaseClient,\n  createBrowserClient as mk,\n} from "@supabase/ssr";\nmk(u, k);`), []);
  assert.notDeepEqual(offences(`import * as S from '@supabase/supabase-js';\nconst SB = S.createClient(u, k);`), []);
  assert.notDeepEqual(offences(`import * as S from '@supabase/ssr';\nconst SB = S.createServerClient(u, k, o);`), []);
  assert.deepEqual(offences(`import type { SupabaseClient } from '@supabase/supabase-js';`), []);
  assert.notDeepEqual(offences(`import { GoTrueClient } from '@supabase/auth-js';\nconst a = new GoTrueClient({ url });`), []);
  assert.deepEqual(offences(`import { supaClient } from '@/lib/supaClient';\nconst SB = () => supaClient('k');`), []);
  // type-only imports of a constructor's name construct nothing; the value forms beside them are still caught
  assert.deepEqual(offences(`import type { Factor, GoTrueClient } from '@supabase/auth-js';\nexport async function f(auth: GoTrueClient) {}`), []);
  assert.deepEqual(offences(`import { type GoTrueClient, type Factor } from '@supabase/auth-js';`), []);
  assert.notDeepEqual(offences(`import { type Factor, GoTrueClient } from '@supabase/auth-js';`), []);
  assert.notDeepEqual(offences(`import type { Factor } from '@supabase/auth-js';\nimport { GoTrueClient } from '@supabase/auth-js';`), []);
});

// A test file is never bundled into a page, so it cannot throw during a prerender, which is the failure this check
// exists for. src/lib/adminTwoStep.test.mjs builds the REAL auth-js client over a stubbed server on purpose (11 Nov
// 2026). Only a `.test.` file name is exempt; isTest() is asserted below so the exemption cannot widen unnoticed.
const isTest = (rel) => /\.test\.[cm]?[jt]sx?$/.test(rel);
test('only a .test. file is exempt from the scan', () => {
  assert.equal(isTest('src/lib/adminTwoStep.test.mjs'), true);
  assert.equal(isTest('src/lib/adminTwoStep.ts'), false);
  assert.equal(isTest('src/components/me/test/Portal.tsx'), false);
  assert.equal(isTest('src/lib/latest.tsx'), false);
});

test('no file in src/ except src/lib/supaClient.ts can construct a Supabase client', () => {
  const hits = [];
  for (const f of readdirSync(SRC, { recursive: true })) {
    if (!/\.[cm]?[jt]sx?$/.test(f)) continue;
    const rel = path.join('src', f);
    if (rel === OWNER || isTest(rel)) continue;
    for (const why of offences(readFileSync(path.join(SRC, f), 'utf8'))) hits.push(`${rel}: ${why}`);
  }
  assert.deepEqual(hits, [], 'build Supabase clients through supaClient() so nothing runs at import');
});
