// reg_fetch's SSRF guard must fire on a numeric private address (4 Sep 2026).
//
// The guard existed and could not fire: its IPv4 regex had lost its backslashes and matched the
// letter d, so 127.0.0.1 and the cloud metadata address were "public". This lifts unsafeUrl() out of
// supabase/functions/reg_fetch/index.ts by text and runs it — no deploy, no credential, no network.
//
//   node scripts/checks/reg_fetch_refuses_private_addresses.mjs
import { readFileSync } from 'node:fs';

// optional argv[2]: another copy of the file (e.g. `git show HEAD:…` saved to disk) to show the BEFORE
const src = readFileSync(process.argv[2] || new URL('../../supabase/functions/reg_fetch/index.ts', import.meta.url), 'utf8');
const m = src.match(/function unsafeUrl\(u: string\): string \| null \{[\s\S]*?\n\}/);
if (!m) { console.error('unsafeUrl() not found in reg_fetch/index.ts'); process.exit(1); }
// strip the TypeScript annotations so plain node can evaluate the function body
const js = m[0].replace('(u: string): string | null', '(u)').replace(/let p: URL;/, 'let p;');
const unsafeUrl = new Function(js + '; return unsafeUrl;')();

const cases = [
  ['http://127.0.0.1/x.pdf',              'private_address'],
  ['http://10.0.0.8/x.pdf',               'private_address'],
  ['http://172.16.5.5/x.pdf',             'private_address'],
  ['http://192.168.1.1/x.pdf',            'private_address'],
  ['http://169.254.169.254/latest/meta',  'private_address'],
  ['http://100.64.0.1/x.pdf',             'private_address'],
  ['http://[::1]/x.pdf',                  'private_address'],
  ['http://localhost/x.pdf',              'internal_host'],
  ['http://db.internal/x.pdf',            'internal_host'],
  ['ftp://www.dm.gov.ae/x.pdf',           'scheme_not_http'],
  ['https://www.dm.gov.ae/x.pdf',         null],
  ['https://8.8.8.8/x.pdf',               null],
];
let bad = 0;
for (const [url, want] of cases) {
  const got = unsafeUrl(url);
  const ok = got === want;
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${url.padEnd(40)} -> ${String(got).padEnd(16)} (want ${want})`);
}
process.exit(bad ? 1 : 0);
