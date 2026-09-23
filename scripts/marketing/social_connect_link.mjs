// THE FOUNDER'S ONE LINK PER PLATFORM (marketing, 23 Sep 2026; instructions 919-920).
//
// Prints a single-use, 24-hour connect link for YouTube and/or the LinkedIn company page. Refuses while the
// platform's OAuth client is not stored (the link would only show "not ready"). The raw token exists only in this
// output; the database keeps its SHA-256 (fn_marketing_social_connect_link).
//
//   node scripts/marketing/social_connect_link.mjs youtube linkedin
//   node scripts/marketing/social_connect_link.mjs --status      # which clients and tokens are stored (no values)
import { readFileSync } from 'node:fs';
import { PROD_REF } from '../lib/qd_guard.mjs';

const mgmt = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
async function sql(query) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + mgmt, 'Content-Type': 'application/json' }, body: JSON.stringify({ query }),
  });
  const t = await r.text();
  if (!r.ok) throw new Error('management API ' + r.status + ': ' + t.slice(0, 200));
  return JSON.parse(t);
}
const CLIENT = { youtube: ['google_oauth_client_id', 'google_oauth_client_secret'], linkedin: ['linkedin_oauth_client_id', 'linkedin_oauth_client_secret'] };
const KEYS = [...Object.values(CLIENT).flat(), 'youtube_oauth', 'linkedin_oauth', 'youtube_channel_id', 'linkedin_organization_id'];

const present = new Set((await sql(`select key from public.app_secrets where key in (${KEYS.map((k) => `'${k}'`).join(',')}) and btrim(coalesce(value,'')) <> ''`)).map((r) => r.key));
if (process.argv.includes('--status')) {
  for (const k of KEYS) console.log((present.has(k) ? 'SET    ' : 'absent ') + k);
} else {
const want = process.argv.slice(2).filter((a) => a === 'youtube' || a === 'linkedin');
if (!want.length) { console.error('name youtube and/or linkedin'); process.exitCode = 2; }
let bad = 0;
for (const p of want) {
  const missing = CLIENT[p].filter((k) => !present.has(k));
  // LinkedIn's page is never discovered (that would need r_organization_admin): its id is pinned first.
  if (p === 'linkedin' && !present.has('linkedin_organization_id')) missing.push('linkedin_organization_id');
  if (missing.length) { console.error(`${p}: not ready — store ${missing.join(' and ')} in app_secrets first.`); bad++; continue; }
  const [{ t }] = await sql(`select public.fn_marketing_social_connect_link('${p}') as t`);
  console.log(`${p}: https://${PROD_REF}.supabase.co/functions/v1/marketing_social_connect/${p}/start?t=${t}`);
}
process.exitCode = bad ? 1 : (process.exitCode ?? 0);
}
