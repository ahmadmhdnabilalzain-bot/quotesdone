// A SUPPLIER'S PROFILE AND CATALOGUE REACH STORAGE (27 Oct 2026, it_engineer; stage-2 rerun of run 0a717394).
//
// supaClient() builds an AUTH-ONLY client ({ auth }, src/lib/supaClient.ts, 28 Sep). The supplier portal's uploadDirect
// (#1496, 19 Oct) called SB().storage.from('supplier-docs').uploadToSignedUrl(...) on it: .storage is undefined, so every
// company profile and catalogue threw before upload, the Documents tab stayed on "Uploading..." and registration said
// "Still needed to register: Company profile" for good. Measured on production with a ZZ DEMO supplier (registration
// walk 390dafcc): profile never on file. This fails if any src file reaches for a client part supaClient does not
// build, and pins the request the hand-made upload sends.
//   node --test scripts/checks/a_supplier_document_upload_never_calls_a_client_the_portal_does_not_build.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
// Whole-line // comments only: a block-comment strip would eat 'image/*,...' accept lists across the file (it did).
const code = (p) => readFileSync(root + p, 'utf8').split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n');
const walk = (d) => readdirSync(root + d).flatMap((f) => {
  const p = `${d}/${f}`;
  return statSync(root + p).isDirectory() ? walk(p) : (/\.(ts|tsx)$/.test(f) && !/\.test\./.test(f) ? [p] : []);
});

test('supaClient builds only .auth', () => {
  const s = code('src/lib/supaClient.ts');
  assert.match(s, /type AuthOnly = \{ auth: GoTrueClient \}/, 'if supaClient grows more parts, revisit this check');
});

test('no src file calls .storage / .from / .rpc / .functions on a supaClient-built client', () => {
  const bad = walk('src').filter((f) => {
    const s = code(f);
    const names = [...s.matchAll(/const (\w+) = \(\) => supaClient\(/g)].map((m) => m[1]);
    const direct = /supaClient\([^)]*\)\.(storage|from|rpc|functions|channel)\b/.test(s);
    return direct || names.some((n) => new RegExp(`\\b${n}\\(\\)\\.(storage|from|rpc|functions|channel)\\b`).test(s));
  });
  assert.deepEqual(bad, [], 'these call a part of the client supaClient does not build: ' + bad.join(', '));
});

test('the supplier portal uploads on the signed URL by hand', () => {
  const s = code('src/components/portal/SupplierPortal.tsx');
  assert.match(s, /uploadToSignedUrl\(SUPA_URL, ANON, 'supplier-docs', u\.path, u\.token, file, file\.type\)/);
});

test('the request is the one storage-js sends, and a network failure is returned, not thrown', async () => {
  const { signedUploadRequest, uploadToSignedUrl } = await import('../../src/lib/signedUpload.ts');
  const f = new Blob([new Uint8Array([37, 80, 68, 70])], { type: 'application/pdf' });
  const { url, init } = signedUploadRequest('https://x.supabase.co', 'ANON', 'supplier-docs', 'profiles/42/1_a b.pdf', 'TOK', f, 'application/pdf');
  assert.equal(url, 'https://x.supabase.co/storage/v1/object/upload/sign/supplier-docs/profiles/42/1_a%20b.pdf?token=TOK');
  assert.equal(init.method, 'PUT');
  assert.equal(init.headers.apikey, 'ANON');
  assert.equal(init.headers['x-upsert'], 'false');
  assert.equal(init.headers['Content-Type'], 'application/pdf');
  assert.equal(init.body, f);
  const ok = await uploadToSignedUrl('https://x.supabase.co', 'ANON', 'supplier-docs', 'p', 'T', f, undefined, async () => new Response('{}', { status: 200 }));
  assert.equal(ok.error, null);
  const refused = await uploadToSignedUrl('https://x.supabase.co', 'ANON', 'supplier-docs', 'p', 'T', f, undefined, async () => new Response('bad token', { status: 400 }));
  assert.equal(refused.error.status, 400);
  const down = await uploadToSignedUrl('https://x.supabase.co', 'ANON', 'supplier-docs', 'p', 'T', f, undefined, async () => { throw new TypeError('Failed to fetch'); });
  assert.equal(down.error.status, 0);
});
