// The SSRF guard must FIRE on a numeric private address.
//
// ── WHY THIS FILE HAS A HISTORY WORTH READING ───────────────────────────────────────────────────
// 4 Sep 2026. The guard existed in reg_fetch and could not fire: its IPv4 regex had lost its
// backslashes and matched the letter d, so 127.0.0.1 and the cloud metadata address were "public".
// This check proved it, before and after.
//
// 8 Sep 2026. reg_fetch was deleted (182308b) in the 137-function sweep. This check was NOT deleted
// with its subject, and it was registered in no workflow — so from that day it read a file that did
// not exist, crashed ENOENT and exited 1 before reaching a single assertion, and nobody saw it,
// because a check in no workflow cannot go red anywhere. A permanently-failing gate that nothing
// runs is worth less than no gate: it looks like coverage and is not.
//
// 9 Sep 2026. The guard is recovered into supabase/functions/_shared/safe_url.ts, so this points
// there, and it is REGISTERED — in the `checks` job of .github/workflows/checks.yml, because it
// reads a committed source file and needs no Supabase token, no network and no deploy. (A check
// that reads PRODUCTION belongs in project-parity.yml, which carries SUPABASE_ACCESS_TOKEN. This
// one reads bytes off disk, so it does not.)
//
// It lifts unsafeUrl() out of the module BY TEXT and runs it under plain node. That is deliberate
// duplication of supabase/functions/_shared/safe_url.test.ts, which imports the same function under
// deno: the deno test is the stronger of the two and catches strictly more, but this one still
// executes if deno is unavailable, and it asserts against the SOURCE FILE rather than a module
// graph — which is the exact shape that caught the eaten backslashes in the first place.
//
//   node scripts/checks/ssrf_guard_refuses_private_addresses.mjs
import { readFileSync } from 'node:fs';

const GUARD = '../../supabase/functions/_shared/safe_url.ts';
// optional argv[2]: another copy of the file (e.g. `git show HEAD:…` saved to disk) to show the BEFORE
const file = process.argv[2] || new URL(GUARD, import.meta.url);
let src;
try { src = readFileSync(file, 'utf8'); }
catch (e) {
  console.error(`cannot read the SSRF guard at ${file}: ${e.message}`);
  console.error('If _shared/safe_url.ts was moved or deleted, this check must move or be retired WITH it.');
  console.error('Do not repoint it at a copy that is not the one the edge functions import.');
  process.exit(1);
}

const m = src.match(/export function unsafeUrl\(u: string\): string \| null \{[\s\S]*?\n\}/);
if (!m) { console.error(`unsafeUrl() not found in ${GUARD}`); process.exit(1); }
// strip the TypeScript annotations so plain node can evaluate the function body
const js = m[0]
  .replace('export function unsafeUrl(u: string): string | null', 'function unsafeUrl(u)')
  .replace(/let p: URL;/, 'let p;');
const unsafeUrl = new Function(js + '; return unsafeUrl;')();

const cases = [
  // the numeric ranges the eaten-backslash regex could never match
  ['http://127.0.0.1/x.pdf',                 'private_address'],
  ['http://10.0.0.8/x.pdf',                  'private_address'],
  ['http://172.16.5.5/x.pdf',                'private_address'],
  ['http://192.168.1.1/x.pdf',               'private_address'],
  ['http://169.254.169.254/latest/meta',     'private_address'],
  ['http://100.64.0.1/x.pdf',                'private_address'],
  ['http://[::1]/x.pdf',                     'private_address'],
  // spelled as an integer / hex / octal - normalised by the URL parser before the guard sees them
  ['http://2130706433/x.pdf',                'private_address'],
  ['http://0x7f000001/x.pdf',                'private_address'],
  // IPv4-mapped IPv6: loopback written as v6. The recovered guard let both of these through.
  ['http://[::ffff:127.0.0.1]/x.pdf',        'private_address'],
  ['http://[::ffff:7f00:1]/x.pdf',           'private_address'],
  // names
  ['http://localhost/x.pdf',                 'internal_host'],
  ['http://db.internal/x.pdf',               'internal_host'],
  ['http://0.0.0.0/x.pdf',                   'internal_host'],
  // schemes - the resend_inbound attachment path could reach file:// before 9 Sep 2026
  ['file:///etc/passwd',                     'scheme_not_http'],
  ['ftp://www.dm.gov.ae/x.pdf',              'scheme_not_http'],
  // and it must still allow the real thing, or it proves nothing
  ['https://www.dm.gov.ae/x.pdf',            null],
  ['https://8.8.8.8/x.pdf',                  null],
];
let bad = 0;
for (const [url, want] of cases) {
  const got = unsafeUrl(url);
  const ok = got === want;
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${url.padEnd(40)} -> ${String(got).padEnd(16)} (want ${want})`);
}
console.log(`\n${cases.length - bad}/${cases.length} passed`);
process.exit(bad ? 1 : 0);
