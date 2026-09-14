// The site's domains and the UAE rule. One home for both, so the middleware and its test read the
// same list. No imports on purpose: scripts/checks/uae_domain.test.ts runs this file under Deno.
//
// FOUNDER, 14 Sep 2026: "also for us to get the TDRA approval, whoever enters the website from UAE
// ip address need to have .ae domain opening."

/**
 * Flip to `true` ONLY after `curl -I https://quotesdone.ae/` returns 200, not 308.
 *
 * Measured 14 Sep 2026: quotesdone.ae and www.quotesdone.ae resolve to the same Vercel project, but
 * a Vercel domain setting 308-redirects both to https://quotesdone.com/ before the app runs. Turning
 * this on while that redirect exists sends UAE visitors round a loop: .com -> .ae -> .com.
 */
// 14 Sep 2026: the Vercel redirect is gone; `curl -I https://quotesdone.ae/` measured 200 OK.
export const AE_DOMAIN_SERVES_SITE = true;

/** The one canonical site. Search engines are pointed here (see SITE in seo.ts). */
export const CANONICAL_ORIGIN = 'https://quotesdone.com';
export const AE_ORIGIN = 'https://quotesdone.ae';

/** Every origin that serves the site. Keep in step with supabase/functions/_shared/site_origins.ts. */
export const SITE_ORIGINS = [
  'https://quotesdone.com',
  'https://www.quotesdone.com',
  'https://quotesdone.ae',
  'https://www.quotesdone.ae',
] as const;

const COM_HOSTS = new Set(['quotesdone.com', 'www.quotesdone.com']);

// Crawlers, link unfurlers and audit tools see one stable site. Deliberately broad: a false match
// only means a real UAE visitor stays on .com, never a loop or a broken page.
const BOT_UA = /bot|crawl|spider|slurp|mediapartners|facebookexternalhit|facebot|embedly|whatsapp|telegram|skype|preview|lighthouse|pagespeed|headless|curl|wget|python-requests|go-http-client/i;

// Paths that are machinery, not pages: APIs, build assets, anything with a file extension,
// robots/sitemap, and the OG/Twitter image routes.
const NEVER_REDIRECT = /^\/(api|_next|_vercel)(\/|$)|\.[a-z0-9]+$|^\/(robots\.txt|sitemap\.xml)$|\/(opengraph|twitter)-image(\/|$)/i;

export type AeRequest = {
  enabled: boolean;
  host: string | null;
  country: string | null;
  pathname: string;
  search: string;
  userAgent: string | null;
};

/** Where a UAE visitor on .com should go, or null to serve the request as it is. */
export function aeRedirectTarget(r: AeRequest): string | null {
  if (!r.enabled) return null;
  const host = (r.host || '').toLowerCase().split(':')[0];
  if (!COM_HOSTS.has(host)) return null; // .ae already, previews, localhost
  if ((r.country || '').toUpperCase() !== 'AE') return null;
  if (NEVER_REDIRECT.test(r.pathname)) return null;
  if (!r.userAgent || BOT_UA.test(r.userAgent)) return null;
  return AE_ORIGIN + r.pathname + (r.search || '');
}
