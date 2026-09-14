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
const CTOR = 'create(?:Browser|Server)?Client';
const PKG = `['"]@supabase/(?:supabase-js|ssr)['"]`;

// Every reason one file's text could construct a Supabase client. Empty = clean.
export function offences(text) {
  const out = [];
  if (new RegExp(`\\b${CTOR}\\s*\\(`).test(text)) out.push('calls a client constructor');
  for (const m of text.matchAll(new RegExp(`import\\s+(?:type\\s+)?([^;]*?)\\s+from\\s*${PKG}`, 'g'))) {
    const clause = m[1];
    const named = clause.match(/\{([^}]*)\}/);
    if (named && new RegExp(`(^|[\\s,])${CTOR}\\b`).test(named[1])) out.push('imports a client constructor');
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
  assert.deepEqual(offences(`import { supaClient } from '@/lib/supaClient';\nconst SB = () => supaClient('k');`), []);
});

test('no file in src/ except src/lib/supaClient.ts can construct a Supabase client', () => {
  const hits = [];
  for (const f of readdirSync(SRC, { recursive: true })) {
    if (!/\.[cm]?[jt]sx?$/.test(f)) continue;
    const rel = path.join('src', f);
    if (rel === OWNER) continue;
    for (const why of offences(readFileSync(path.join(SRC, f), 'utf8'))) hits.push(`${rel}: ${why}`);
  }
  assert.deepEqual(hits, [], 'build Supabase clients through supaClient() so nothing runs at import');
});
