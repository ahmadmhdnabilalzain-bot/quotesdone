// NO SOURCE FILE HARDCODES A LEGACY SUPABASE KEY (it_engineer, 27 Oct 2026).
//
// The legacy anon and service_role keys are JWTs signed with the project's HS256 secret, and that secret leaked
// (docs/reports/security/SECURITY_HARDENING_27_OCT.md item 3). The secret can be revoked only once nothing sends a
// token it signed, and two of the senders were literals in the source: the site's production fallback in
// src/lib/supaEnv.ts and the anon JWT in supabase/functions/stripe_setup_page/index.ts. A literal is the one kind
// of consumer the gateway logs show only after it has shipped, so this fails the build first.
//
// FAILS when any file git tracks contains a JWT-shaped string (three base64url parts, the first two starting
// `eyJ`) whose payload decodes to JSON with role 'anon' or 'service_role'. That is the shape of every Supabase
// legacy key whichever project it belongs to, so a staging key, a pasted key from another project, or a key in a
// doc all count: once a key is in git it is in every clone. The finding names the file, the line and the role,
// never the value. A user's session token (role 'authenticated') and the new sb_publishable_ / sb_secret_ keys
// are not this check's subject.
//
// Known-bad control: a legacy-shaped key is BUILT AT RUN TIME (so this file carries no literal) and must be found;
// a role 'authenticated' JWT and an sb_publishable_ string must not be. A scanner that finds nothing in a planted
// key would pass everything.
//
//   node --test scripts/checks/no_source_file_hardcodes_a_legacy_supabase_key.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../..', import.meta.url));
const JWT = /eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g;
const LEGACY_ROLES = new Set(['anon', 'service_role']);
const MAX_BYTES = 8 * 1024 * 1024;

/** Every legacy Supabase key in a text, as { line, role }. Never returns the value. */
export function legacyKeysIn(text) {
  const out = [];
  for (const m of String(text).matchAll(JWT)) {
    let payload;
    try { payload = JSON.parse(Buffer.from(m[0].split('.')[1], 'base64url').toString('utf8')); } catch { continue; }
    if (payload && LEGACY_ROLES.has(payload.role)) {
      out.push({ line: text.slice(0, m.index).split('\n').length, role: payload.role });
    }
  }
  return out;
}

/** The tracked files of the repository (git ls-files), text only. */
function trackedFiles() {
  const list = execFileSync('git', ['ls-files', '-z'], { cwd: ROOT, maxBuffer: 256 * 1024 * 1024 }).toString('utf8').split('\0').filter(Boolean);
  return list.filter((f) => {
    try { const s = statSync(join(ROOT, f)); return s.isFile() && s.size <= MAX_BYTES; } catch { return false; }   // deleted in the work tree
  });
}

export function scanRepository() {
  const findings = [];
  let scanned = 0;
  for (const f of trackedFiles()) {
    const buf = readFileSync(join(ROOT, f));
    if (buf.includes(0)) continue;   // binary
    scanned++;
    const text = buf.toString('utf8');
    if (!text.includes('eyJ')) continue;
    for (const k of legacyKeysIn(text)) findings.push(`${f}:${k.line} (role ${k.role})`);
  }
  return { findings, scanned };
}

// Built at run time from its parts: this file must not itself hold a key-shaped literal.
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const forge = (role) => `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ iss: 'supabase', ref: 'zzcontrolref', role, iat: 1, exp: 2 })}.${'Q'.repeat(43)}`;

test('known-bad control: a planted legacy key is found, and only the legacy roles are', () => {
  const planted = `export const A = 'x';\nconst ANON = '${forge('anon')}';\nconst S = "${forge('service_role')}";\n`;
  assert.deepEqual(legacyKeysIn(planted), [{ line: 2, role: 'anon' }, { line: 3, role: 'service_role' }]);
  assert.deepEqual(legacyKeysIn(`Bearer ${forge('authenticated')}`), [], 'a session token is not a legacy key');
  assert.deepEqual(legacyKeysIn('sb_publishable_zzcontrolNOTAKEY0000000000'), [], 'a new-format key is not a legacy key');
  assert.deepEqual(legacyKeysIn('eyJnot.eyJbase64.at-all'), [], 'a malformed token is skipped, not thrown on');
});

test('no tracked file hardcodes a legacy anon or service_role key', () => {
  const { findings, scanned } = scanRepository();
  assert.ok(scanned > 1000, `the scan read only ${scanned} files; it is not looking at the repository`);
  assert.deepEqual(findings, [], 'remove these keys; read the new key from the environment instead '
    + '(the site: NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY; an edge function: SUPABASE_ANON_KEY, which the runtime sets to the '
    + 'publishable key; a script: scripts/lib/supabase_keys.mjs pickApiKey())');
});
