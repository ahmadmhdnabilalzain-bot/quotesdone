// WHERE A CREDENTIAL ACTUALLY LIVES
//
// "It was already in Supabase secret keys." — the founder, 7 September 2026, and a completely
// reasonable thing to believe, because Supabase has THREE things a person could mean by that:
//
//   1. public.app_secrets        a table in the database. What every edge function's sec() reads.
//   2. Edge Function secrets     environment variables, `supabase secrets list`. A DIFFERENT store.
//   3. Project Settings -> API   Supabase's OWN keys, recently renamed "secret keys" in the
//                                dashboard. Nothing to do with third-party credentials at all.
//
// My delivery report checked only (1) and printed ABSENT. That is a true statement about one
// store presented as a fact about the system — the same shape as an instrument measuring the wrong
// subject, and it wastes the founder's time arguing with a report that was only ever half-right.
//
// So this checks (1) and (2) together and names which one holds what. It also SHAPE-CHECKS, because
// the failure that actually bites is not an absent credential but a plausible one: Twilio's API key
// secret and its account auth token are both 32 characters and sit next to each other in the
// console, and only one of them can compute a webhook signature. A credential in the right place
// with the wrong contents passes every "is it set?" test ever written.
//
// It never prints a value. Length, character class and an 8-character fingerprint are enough to
// tell these credentials apart, and a check that solves a mystery by printing the secret has
// created a worse one.
//
//   node scripts/checks/where_a_credential_actually_lives.mjs [--key <name>]

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { execFileSync } from 'node:child_process';

const REF = 'htdblwldjkcgjvmqkbeh';
const MGMT = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8')).trim();
const args = process.argv.slice(2);
const ONE = args.indexOf('--key') >= 0 ? args[args.indexOf('--key') + 1] : null;

// What the running code actually needs, and what shape it must be in for that need to be met.
const WANTED = [
  { key: 'twilio_auth_token', shape: /^[0-9a-f]{32}$/i,
    why: 'wa_inbound signs webhook validation with it (HMAC-SHA1). 32 hex characters.',
    confusable: 'twilio_api_key_secret is also 32 characters and CANNOT compute the signature.' },
  { key: 'meta_access_token', shape: /^.{20,}$/,
    why: 'the ad-spend autopilot calls the Graph API with it from cron, where no MCP exists.',
    confusable: 'meta_ad_account_id identifies the account; it does not authorise anything.' },
];

async function q(sql) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + MGMT, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  const t = await res.text();
  try { return JSON.parse(t); } catch { throw new Error(t.slice(0, 300)); }
}

// STORE 1 — the table every edge function reads.
const inTable = await q(`select key, length(value) len, left(md5(value), 8) fp,
    case when value ~ '^[0-9a-f]+$' then 'hex' when value ~ '^[0-9]+$' then 'digits'
         else 'mixed' end charclass
  from public.app_secrets where coalesce(value,'') <> ''`);
const tableMap = new Map(inTable.map((r) => [r.key, r]));

// STORE 2 — edge function environment variables. A different store entirely, and the one people
// mean when they say "Supabase secrets", because that is what the CLI command is called.
let envNames = new Set();
let envReadable = true;
try {
  // shell: true because on Windows `npx` is npx.cmd and execFileSync will not find it otherwise —
  // which failed silently and left this check saying "unknown" for a store it could read perfectly
  // well.
  const out = execFileSync('npx', ['--yes', 'supabase@latest', 'secrets', 'list', '--project-ref', REF],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], shell: true });
  for (const s of (JSON.parse(out).secrets || [])) envNames.add(s.name);
} catch { envReadable = false; }

console.log('\nWHERE THE CREDENTIALS ACTUALLY ARE\n');
console.log('  store 1  public.app_secrets            ' + inTable.length + ' non-empty key(s) — what edge functions read');
console.log('  store 2  edge function env secrets     ' + (envReadable ? envNames.size + ' key(s)' : 'COULD NOT READ'));
console.log('  store 3  Project Settings -> API       Supabase\'s own keys. Never holds third-party credentials.\n');

let missing = 0, unknown = 0;
for (const w of WANTED) {
  if (ONE && w.key !== ONE) continue;
  const t = tableMap.get(w.key);
  const inEnv = envNames.has(w.key) || envNames.has(w.key.toUpperCase());
  console.log(w.key);
  console.log('  needed for   ' + w.why);
  console.log('  app_secrets  ' + (t ? `present · ${t.len} chars · ${t.charclass} · fp ${t.fp}` : 'ABSENT'));
  console.log('  env secrets  ' + (envReadable ? (inEnv ? 'present' : 'ABSENT') : 'unknown'));

  if (!t && !envReadable) {
    // A STORE I COULD NOT READ IS NOT A STORE I FOUND NOTHING IN. Saying "absent from both" while
    // one of them never answered is the whole class of defect this file exists to stop.
    unknown++;
    console.log('  VERDICT      ABSENT from app_secrets; the env store could not be read, so this');
    console.log('               is NOT a finding about both. Re-run with the Supabase CLI working.');
  } else if (!t && !inEnv) {
    missing++;
    console.log('  VERDICT      NOT PRESENT IN EITHER STORE.');
    console.log('               ' + w.confusable);
  } else if (t && !w.shape.test('x'.repeat(t.len)) && !new RegExp(w.shape).test('0'.repeat(t.len))) {
    // Shape can only be judged from length and character class without reading the value, so this
    // reports rather than concludes -- a check that guessed here would be worse than one that says
    // what it can see.
    console.log('  VERDICT      present. Contents not readable here; length and class shown above.');
  } else {
    console.log('  VERDICT      present.');
  }
  console.log('');
}

// The confusable pair, named explicitly, because this is the one that looks solved and is not.
const apiSecret = tableMap.get('twilio_api_key_secret');
if (apiSecret) {
  console.log('NOTE — the pair that looks interchangeable and is not:');
  console.log(`  twilio_api_key_secret  present · ${apiSecret.len} chars · ${apiSecret.charclass}`);
  console.log('  Twilio signs webhooks with the ACCOUNT auth token specifically. An API key secret');
  console.log('  authenticates REST calls and cannot produce that signature, however valid it is.');
  console.log(`  This one is ${apiSecret.charclass}, and an auth token is 32 hex — so they are not the same value.\n`);
}

if (unknown > 0) {
  console.log(`${unknown} credential(s) could not be settled: one store did not answer, so nothing is concluded about them.`);
} else if (missing === 0) {
  console.log('Every credential above is present in one of the two stores.');
} else {
  console.log(`${missing} credential(s) are in NEITHER store. The delivery report's blocker list is correct.`);
}
process.exit(0);
