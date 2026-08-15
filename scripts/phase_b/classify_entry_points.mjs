// For every edge function with no internal caller, decide whether it has an EXTERNAL entry
// point or no entry point at all.
//
// "No caller in our repo" is not "dead": a public page, a provider webhook and an OAuth
// callback are all invoked from outside this codebase.  Conflating the two would report the
// customer portal as dead code.  So the entry surface is read out of the function's own
// source rather than guessed from its name.
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { REPO } from './lib/package.mjs';

const FN_DIR = join(REPO, 'supabase', 'functions');

/** Ordered: the first pattern that matches wins, most specific first. */
const SURFACES = [
  ['provider_webhook', [
    /stripe\.webhooks|constructEvent|Stripe-Signature|stripe-signature/i,
    /svix-id|svix-signature/i,
    /x-twilio-signature|X-Twilio-Signature/i,
    /resend|webhook.*secret/i,
    /hub\.challenge|X-Hub-Signature/i,
  ]],
  ['oauth_callback', [/oauth|authorization_code|redirect_uri|code_verifier/i]],
  ['public_html_page', [/text\/html/i]],
  ['public_json_api', [/Access-Control-Allow-Origin/i]],
];

const rows = [];
for (const d of readdirSync(FN_DIR, { withFileTypes: true })) {
  if (!d.isDirectory() || d.name.startsWith('_')) continue;
  const idx = join(FN_DIR, d.name, 'index.ts');
  if (!existsSync(idx)) { rows.push({ slug: d.name, surface: 'no_index_ts', bytes: 0 }); continue; }
  const src = readFileSync(idx, 'utf8');
  let surface = 'internal_only';
  for (const [name, pats] of SURFACES) {
    if (pats.some(p => p.test(src))) { surface = name; break; }
  }
  rows.push({
    slug: d.name,
    surface,
    bytes: src.length,
    serves_get: /req\.method\s*===\s*['"]GET['"]|method\s*==\s*['"]GET['"]/.test(src),
    uses_llm: /_shared\/llm|openrouter|OPENROUTER/i.test(src),
  });
}
rows.sort((a, b) => a.slug.localeCompare(b.slug));
console.log(JSON.stringify({ total: rows.length, functions: rows }, null, 1));
