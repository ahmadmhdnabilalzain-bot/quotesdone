// The Supabase target, resolved in ONE place.
//
// 5 Aug 2026. Five modules each carried `process.env.NEXT_PUBLIC_SUPABASE_URL || '<production
// ref>'` inline. osClient.ts warned when the variable was unset — but the four customer- and
// supplier-facing components did not, and they are the ones a real user touches: the customer
// portal, the supplier portal, the contact form and the site chat widget. A preview deployment
// that forgot the variable therefore drove the LIVE database from all four, silently, with the
// only warning in the admin console module those pages never import.
//
// That is the same defect the deploy tooling already fixed once (decision D1: deploy_functions.ps1
// "was pinned to the production ref in three places, so the only deploy tool in the repo could
// only ever target production"). Here it survived in the frontend.
//
// The fallback is kept DELIBERATELY: an unconfigured production build must behave exactly as it
// does today, and removing it would turn a silent wrong target into a hard outage. What changes is
// that it exists once, and every consumer inherits the warning instead of four of them opting out
// by copy-paste.
// 3 SEP 2026: the fallback stays for a PRODUCTION build (an unconfigured production build must not
// become an outage), but a PREVIEW build with the variable unset now gets NO target instead of the
// live database. Vercel stamps VERCEL_ENV=preview on every branch deployment; there, a blank URL fails
// the first request loudly rather than writing a preview's fixtures into production.
const IS_PREVIEW = process.env.VERCEL_ENV === 'preview' || process.env.NEXT_PUBLIC_VERCEL_ENV === 'preview';
export const SUPA_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || (IS_PREVIEW ? '' : 'https://htdblwldjkcgjvmqkbeh.supabase.co');
// THE PUBLISHABLE KEY, NOT THE LEGACY ANON JWT (it_engineer, 27 Oct 2026; docs/reports/security/
// SECURITY_HARDENING_27_OCT.md item 3, A1). The legacy anon key is a JWT signed with the project's HS256
// secret, which leaked; it can only be revoked once nothing sends it. NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
// (the sb_publishable_ 'default' key, set in Vercel by the Supabase integration) is read first. The legacy
// NEXT_PUBLIC_SUPABASE_ANON_KEY is a TEMPORARY fallback for the zero-downtime move: remove it in the PR that
// follows 24 to 48 h of zero HS256 traffic in the gateway logs (scripts/it/hs256_traffic_since_the_key_move.mjs).
// The gateway was proved to accept the publishable key as apikey and Bearer, verify_jwt=true functions included.
// The hardcoded legacy JWT that used to follow here is gone, and no key literal replaces it:
// scripts/checks/no_source_file_hardcodes_a_legacy_supabase_key.test.mjs fails if one comes back. A production
// build therefore needs one of the two variables set, and Vercel production has both (read back by name, 27 Oct 2026).
export const SUPA_ANON = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
  || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  || '';
export const SUPA_FN = `${SUPA_URL}/functions/v1`;

// EDGE FUNCTIONS RUN NEXT TO THE DATABASE, NOT NEXT TO THE CALLER (21 Sep 2026).
// Supabase runs a function in the edge region nearest the CALLER, but the database is in
// ap-southeast-1 (Singapore) and every function makes several SERIAL hops to it (auth.getUser,
// leads, customers, then the action's own reads). function_edge_logs, 24 h to 21 Sep 2026, the six
// /me overview reads (kyc, customer_api, customer_portal, project_api, messages_api), 200s only,
// p50 execution_time_ms by region: us-east-1 1,943-3,498, us-west-1 1,458-2,388, ap-south-1 (the
// region Dubai callers land in) 639-1,271. The nightly journey and post-merge smoke run on US GitHub
// runners, so every hop crossed the Pacific and "overview data under 2.5 s" failed ~40x per locale
// although all six calls already START in parallel at ~0.2 s (BootPrefetch.tsx). From Dubai a
// one-hop anon read (public_site guarantee_terms) took 853-1,084 ms unpinned (ap-south-1) and
// 286-346 ms pinned (ap-southeast-1), warm. One client-to-Singapore trip costs less than N
// edge-to-database trips from anywhere else.
// The QUERY PARAMETER, not the `x-region` header: a custom header needs every function's CORS
// allow-list to name it, the query string needs no preflight change.
// Checked by scripts/checks/customer_overview_reads_run_in_the_database_region.test.mjs.
export const FN_REGION = 'ap-southeast-1';
export const fnUrl = (name: string) => `${SUPA_FN}/${name}?forceFunctionRegion=${FN_REGION}`;

// A silent fallback is how a staging page ends up writing to production. Say so, loudly, in the
// one place every consumer now shares.
if (typeof window !== 'undefined' && !process.env.NEXT_PUBLIC_SUPABASE_URL) {
  console.warn('[qd] NEXT_PUBLIC_SUPABASE_URL is unset - this page is talking to PRODUCTION.');
}
if (typeof window !== 'undefined' && !SUPA_ANON && SUPA_URL) {
  console.warn('[qd] neither NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY nor NEXT_PUBLIC_SUPABASE_ANON_KEY is set - every Supabase call will be refused.');
}
