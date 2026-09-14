// The UAE-visitors-on-.ae rule (src/lib/domains.ts) and the edge functions' return-URL builder
// (supabase/functions/_shared/site_origins.ts). Pure functions; no network, no filesystem.
import { aeRedirectTarget, type AeRequest } from '../../src/lib/domains.ts';
import { siteReturnBase } from '../../supabase/functions/_shared/site_origins.ts';

const eq = (a: unknown, b: unknown) => { if (a !== b) throw new Error(`expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`); };

const CHROME = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36';
const base: AeRequest = { enabled: true, host: 'quotesdone.com', country: 'AE', pathname: '/ar/services/x', search: '?a=1', userAgent: CHROME };
const go = (o: Partial<AeRequest>) => aeRedirectTarget({ ...base, ...o });

Deno.test('AE visitor on .com is sent to .ae with path and query', () => {
  eq(go({}), 'https://quotesdone.ae/ar/services/x?a=1');
  eq(go({ host: 'www.quotesdone.com', pathname: '/', search: '' }), 'https://quotesdone.ae/');
  eq(go({ host: 'QuotesDone.com:443' }), 'https://quotesdone.ae/ar/services/x?a=1');
});
Deno.test('flag off: never redirect', () => eq(go({ enabled: false }), null));
Deno.test('already on .ae, preview or localhost: no redirect', () => {
  for (const host of ['quotesdone.ae', 'www.quotesdone.ae', 'qd-git-x.vercel.app', 'localhost:3000', null]) eq(go({ host }), null);
});
Deno.test('machinery paths: no redirect', () => {
  for (const pathname of ['/api/x', '/_next/static/a.js', '/icon.png', '/robots.txt', '/sitemap.xml', '/en/opengraph-image', '/ar/opengraph-image']) eq(go({ pathname }), null);
});
Deno.test('crawlers and a missing UA: no redirect', () => {
  for (const userAgent of ['Mozilla/5.0 (compatible; Googlebot/2.1)', 'facebookexternalhit/1.1', 'WhatsApp/2.23', 'curl/8.4', null]) eq(go({ userAgent }), null);
});
Deno.test('non-AE visitors: no redirect', () => {
  for (const country of ['SA', 'US', '', null]) eq(go({ country }), null);
});

const req = (origin?: string) => new Request('https://x.supabase.co/functions/v1/f', { headers: origin ? { origin } : {} });
Deno.test('return base: allowed return_url kept, path included', () => {
  eq(siteReturnBase(req(), 'https://quotesdone.ae/ar/me/'), 'https://quotesdone.ae/ar/me');
  eq(siteReturnBase(req(), 'https://www.quotesdone.com'), 'https://www.quotesdone.com');
  eq(siteReturnBase(req(), 'https://qd-git-x.vercel.app/me'), 'https://qd-git-x.vercel.app/me');
});
Deno.test('return base: foreign or non-https return_url falls to Origin, then .com', () => {
  eq(siteReturnBase(req('https://quotesdone.ae'), 'https://evil.example/me'), 'https://quotesdone.ae');
  eq(siteReturnBase(req('https://evil.example'), 'http://quotesdone.com'), 'https://quotesdone.com');
  eq(siteReturnBase(req(), 'https://quotesdone.ae.evil.example'), 'https://quotesdone.com');
  eq(siteReturnBase(req()), 'https://quotesdone.com');
});
