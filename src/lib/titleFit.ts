// No imports, so scripts/checks can load it directly (src/lib/seo.ts applies it in buildMeta).

/**
 * The <title> a search result can show: about 60 characters (~580 px) before it is cut (website audit
 * 10 Nov 2026, marketing). Measured on production: 111 of the 146 sitemap pages had a longer title,
 * almost all of them because of two tails, " | QuotesDone" / " — QuotesDone" and the service pages'
 * " — Get Free Quotes". Only while a title is over the limit, those tails go, brand first: the words that
 * say what the page is stay, and the brand is still the result's site name (og:site_name, WebSite
 * JSON-LD). Social cards keep the full title. A title that is long for its own words is left as written
 * (its rewording is the content owner's, not this function's).
 */
export const TITLE_MAX = 60;
const TITLE_TAILS = [/ (?:—|\|) QuotesDone$/, / — (?:Get Free Quotes|احصل على عروض أسعار مجانية)$/];
export function fitTitle(title: string): string {
  let t = title;
  for (const tail of TITLE_TAILS) if ([...t].length > TITLE_MAX) t = t.replace(tail, '');
  return t;
}
