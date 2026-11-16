// VERCEL WEB ANALYTICS, without the @vercel/analytics package (marketing, 15 Nov 2026; docs/runbooks/vercel_web_analytics.md).
// Page views by path, referrer and country, cookieless: Vercel's script sets no cookie and keeps no identifier across days,
// which is the posture of the cookie policy (§2). It renders NOTHING until NEXT_PUBLIC_WEB_ANALYTICS is 'on', which is set
// only after Web Analytics is enabled on the Vercel project (until then the script path answers 404 and the API "not found").
// The script is same-origin (/_vercel/insights/script.js), so the CSP in next.config.mjs needs no new host.
import Script from 'next/script';

export const WEB_ANALYTICS_ON = process.env.NEXT_PUBLIC_WEB_ANALYTICS === 'on';

export function WebAnalytics() {
  if (!WEB_ANALYTICS_ON) return null;
  return (
    <>
      <Script id="va-queue" strategy="afterInteractive">{'window.va = window.va || function () { (window.vaq = window.vaq || []).push(arguments); };'}</Script>
      <Script src="/_vercel/insights/script.js" strategy="afterInteractive" />
    </>
  );
}
