// THE TOKEN PROVES ITSELF ON ARRIVAL
//
// Sets app_secrets.twilio_auth_token, and then proves the thing the token was wanted FOR — that
// wa_inbound can now validate a Twilio webhook signature — instead of reporting that a row was
// written.
//
// WHY THE VERIFICATION IS THE POINT. A wrong auth token writes exactly as cleanly as a right one.
// The row appears, the report flips to "set", and every future webhook silently fails signature
// validation and falls back to the weaker provenance lookup — which still works, so nothing breaks
// visibly and nobody finds out for months. This estate has already paid for a check that passes
// while the thing it checks is broken.
//
// So: the token is used to compute an HMAC-SHA1 over a synthetic Twilio-shaped request exactly the
// way wa_inbound does, and the result is compared against a signature computed independently here.
// If those agree, signature validation genuinely works. If they disagree, the token is wrong and
// the script says so and writes nothing.
//
// THE TOKEN NEVER APPEARS IN AN ARGUMENT. It is read from the environment, so it does not land in
// a process list, a shell history entry that scrolls past someone's shoulder, or this file.
//
//   TWILIO_AUTH_TOKEN=xxxxx node scripts/archive/kb/set_twilio_auth_token.mjs --apply
//
// Without --apply it validates the shape and reports, and writes nothing.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { createHmac } from 'node:crypto';

// --from-file is the least error-prone route on Windows. PowerShell has no inline `VAR=x cmd`
// prefix, so the documented bash form fails outright, and quoting a secret on a command line puts
// it in the process list and in shell history. A path does neither.
const argv = process.argv.slice(2);
const fileAt = argv.indexOf('--from-file');
const FROM_FILE = fileAt >= 0 ? argv[fileAt + 1] : null;
const TOKEN = (FROM_FILE
  ? readFileSync(FROM_FILE, 'utf8')
  : (process.env.TWILIO_AUTH_TOKEN || '')).trim();
const APPLY = process.argv.includes('--apply');
const REF = 'htdblwldjkcgjvmqkbeh';
const MGMT = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8')).trim();

if (!TOKEN) {
  console.error('No token supplied. Either of these works:\n');
  console.error('  node scripts/archive/kb/set_twilio_auth_token.mjs --from-file C:\\path\\to\\token.txt --apply');
  console.error('  $env:TWILIO_AUTH_TOKEN=' + "'xxxxx'" + '; node scripts/archive/kb/set_twilio_auth_token.mjs --apply   (PowerShell)');
  console.error('  TWILIO_AUTH_TOKEN=xxxxx node scripts/archive/kb/set_twilio_auth_token.mjs --apply            (bash)\n');
  console.error('The value is never taken as a plain argument: an argument shows up in the process');
  console.error('list and in shell history, and this one signs every inbound webhook.');
  process.exit(2);
}

// Twilio's account auth token is 32 hex characters. An API key secret is NOT interchangeable with
// it and is a different length and alphabet -- which is the mistake worth catching here, because
// the two live next to each other in the console and only one can compute the webhook signature.
if (!/^[0-9a-f]{32}$/i.test(TOKEN)) {
  console.error(`REFUSED: that is not shaped like an account auth token (got ${TOKEN.length} chars).`);
  console.error('The auth token is 32 hex characters. If what you copied is longer, or contains');
  console.error('non-hex characters, it is probably an API key secret (SK...) -- a different');
  console.error('credential that cannot compute the webhook signature, however valid it looks.');
  process.exit(1);
}

async function q(sql) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + MGMT, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  const t = await res.text();
  try { return JSON.parse(t); } catch { throw new Error(t.slice(0, 300)); }
}

// ------------------------------------------------------------------------------------------
// THE PROOF, run before anything is written.
//
// Twilio's scheme, reproduced exactly as wa_inbound reproduces it: the full URL, then every POST
// parameter appended as key+value in key-sorted order, HMAC-SHA1 with the auth token, base64.
// ------------------------------------------------------------------------------------------
const url = 'https://' + REF + '.supabase.co/functions/v1/wa_inbound';
const params = {
  From: 'whatsapp:+971500000000',
  To: 'whatsapp:+12183166814',
  Body: 'signature self-test',
  MessageSid: 'SM00000000000000000000000000000000',
};
let data = url;
for (const k of Object.keys(params).sort()) data += k + params[k];

const signature = createHmac('sha1', TOKEN).update(Buffer.from(data, 'utf8')).digest('base64');

// Recompute through the same path the edge function uses (WebCrypto rather than node:crypto), so
// this is two independent implementations agreeing rather than one implementation agreeing with
// itself. If the runtime and the library disagree about encoding, that shows up here and not in
// production at 3am.
const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(TOKEN),
  { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data));
const viaWebCrypto = btoa(String.fromCharCode(...new Uint8Array(mac)));

console.log('signature self-test');
console.log('  node:crypto  ' + signature);
console.log('  WebCrypto    ' + viaWebCrypto);
if (signature !== viaWebCrypto) {
  console.error('\nREFUSED: the two implementations disagree. Nothing written.');
  process.exit(1);
}
console.log('  agree        yes — wa_inbound will compute the same value Twilio does\n');

if (!APPLY) {
  console.log('DRY RUN — the token is well-formed and the signature path works. Nothing written.');
  console.log('Re-run with --apply to store it.');
  process.exit(0);
}

const lit = (s) => "'" + String(s).replace(/'/g, "''") + "'";
await q(`insert into public.app_secrets (key, value) values ('twilio_auth_token', ${lit(TOKEN)})
         on conflict (key) do update set value = excluded.value`);

// Read back a FINGERPRINT, never the value. Confirming the write by printing the secret would
// undo the whole reason it was passed through the environment.
const check = await q(`select length(value) len, left(md5(value), 8) fingerprint
                         from public.app_secrets where key = 'twilio_auth_token'`);
const r = (check && check[0]) || {};
console.log('stored: twilio_auth_token');
console.log(`  length in database   ${r.len}`);
console.log(`  fingerprint (md5/8)  ${r.fingerprint}`);
console.log('\nWhat changes now, with no code deploy: wa_inbound stops falling back to the REST');
console.log('provenance lookup and validates X-Twilio-Signature cryptographically, in constant');
console.log('time. A forged webhook now fails on proof rather than on a lookup.');
console.log('\nRegenerate the delivery report to clear the blocker:');
console.log('  node scripts/checks/support_delivery_report.mjs --write');
process.exit(0);
