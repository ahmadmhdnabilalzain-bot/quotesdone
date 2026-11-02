// error_text.ts: an error's own words are kept, cut, and never carry a credential. No network, no env.
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert';
import { errorText } from './error_text.ts';

Deno.test('the message survives, with its error name', () => {
  assertEquals(errorText(new TypeError('error sending request for url (https://x.supabase.co/functions/v1/ai_gateway): connection closed')),
    'TypeError: error sending request for url (https://x.supabase.co/functions/v1/ai_gateway): connection closed');
});

Deno.test('a credential in the text is replaced, and the text is cut', () => {
  // Built at run time from its parts (as scripts/checks/no_source_file_hardcodes_a_legacy_supabase_key.test.mjs does):
  // a service_role-shaped literal in a tracked file is refused by that check even when its signature is fake.
  const b64 = (o: unknown) => btoa(JSON.stringify(o)).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
  const jwt = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ role: 'service_role', iat: 1700000000 })}.${'c2lnbmF0dXJl'.repeat(3)}`;
  const t = errorText(new Error(`refused: Authorization: Bearer ${jwt} secret=hunter2-very-secret apikey: sk-or-v1-0123456789abcdef0123456789abcdef`), 400);
  assert(!t.includes('hunter2'), t);
  assert(!t.includes('eyJhbGci'), t);
  assert(!t.includes('0123456789abcdef0123'), t);
  assertStringIncludes(t, 'refused');
  assertEquals(errorText('word '.repeat(100), 50).length, 50);
});

// review of #1688: three shapes the first version let through
Deno.test('a query-string token, a JSON client secret and a short sb_secret_ key are replaced', () => {
  const q = errorText(new Error('GET https://login.example.invalid/cb?access_token=zzDemoTok123&state=ok failed'), 400);
  assert(!q.includes('zzDemoTok123'), q);
  assertStringIncludes(q, 'state=ok');
  const j = errorText('bad request {"client_id":"zz-demo","client_secret":"zzDemoShh"}', 400);
  assert(!j.includes('zzDemoShh'), j);
  assertStringIncludes(j, 'zz-demo');
  const k = errorText('refused key sb_secret_zzDemo1 for this call', 400);
  assert(!k.includes('zzDemo1'), k);
  assertStringIncludes(k, 'refused');
});
