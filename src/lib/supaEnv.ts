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
export const SUPA_ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  || (IS_PREVIEW ? '' : 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh0ZGJsd2xkamtjZ2p2bXFrYmVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA3ODU1NDYsImV4cCI6MjA5NjM2MTU0Nn0.cF9ZR_Qo1YBhLvhTLS8aANlYb6c9rTsuQS6kLxGw_Bo');
export const SUPA_FN = `${SUPA_URL}/functions/v1`;

// A silent fallback is how a staging page ends up writing to production. Say so, loudly, in the
// one place every consumer now shares.
if (typeof window !== 'undefined' && !process.env.NEXT_PUBLIC_SUPABASE_URL) {
  console.warn('[qd] NEXT_PUBLIC_SUPABASE_URL is unset - this page is talking to PRODUCTION.');
}
