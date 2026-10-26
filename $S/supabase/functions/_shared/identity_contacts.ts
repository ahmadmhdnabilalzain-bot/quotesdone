// identity_contacts.ts — contact details that are NOT UAE-shaped, in one place (21 Sep 2026, sales_engineer).
//
// MEASURED 21 Sep 2026 on two real US bid sets (the drawing baseline for founder instruction 580): the
// title blocks carry "(970) 460-7400", "970.673.8248", "G2CE.COM", "MARKLEYDESIGNS.COM",
// "1039 MAIN STREET", "WINDSOR, CO 80550", "4209 COUNTY ROAD 24 1/2", "LONGMONT, COLORADO 80504".
// Every scrubber in the estate matched none of them: phones were UAE-only (+971 / 05x), a web address
// needed http:// or www., and street patterns wanted Title Case ("Main Street", never "MAIN STREET").
// A customer can upload a consultant's drawing from anywhere, and a supplier who reads a phone number
// or a web address off it can go round the reveal fee. So these sit beside the UAE patterns, used by:
//   * drawing_boq/boq_from_text.ts scrubIdentity (every BOQ line a supplier reads)
//   * _shared/anonymise.ts GENERIC_ID (redaction of text and the residual scan that holds a page)
// Each is written so the ordinary words of a BOQ do not trip it: a street needs a house number AND at
// least one name word before the street word ("2 ROAD CROSSINGS" is not an address), a web address
// needs a known top-level domain, a North-American phone needs the 3-3-4 grouping with separators.

/** (970) 460-7400, 970.673.8248, 970-460-7400, +1 970 460 7400 */
export const PHONE_NANP = /(?:\+1[\s.-]?)?(?<![\d.\/])(?:\(\d{3}\)\s?|\b\d{3}[\s.-])\d{3}[\s.-]\d{4}\b(?![.\/]\d)/g;
/** G2CE.COM, markleydesigns.com, studio.example.ae — a host name with a known top-level domain, no scheme needed. */
// Never the domain of an email address: taking "acme.ae" out of "info@acme.ae" left "info@" behind and the
// email scrubber after it no longer matched (caught by supplier_api/quote_review.test.ts, 21 Sep 2026).
export const WEB_HOST = /(?<![@\w.-])\b(?:[A-Za-z0-9-]{0,30}[A-Za-z][A-Za-z0-9-]{0,30}\.)+(?:com|net|org|ae|io|co|us|biz|info|gov|edu|uk|sa|qa|om|bh|kw|eg|in|de|fr)\b(?![.@\w-])/gi;
/** 1039 MAIN STREET, 4209 COUNTY ROAD 24 1/2, 2329 115TH AVE, 12 Al Wasl Road */
export const STREET_ADDRESS = /\b\d{1,6}\s+(?:[NSEW]\.?\s+)?(?:[A-Za-z0-9][A-Za-z0-9'.-]*\s+){1,4}(?:STREET|AVENUE|AVE\.?|ROAD|BOULEVARD|BLVD\.?|DRIVE|LANE|PARKWAY|PKWY|HIGHWAY|HWY|WAY|COURT)(?![A-Za-z])(?:\s+\d{1,5}(?:\s+\d\/\d)?)?/gi;
/** WINDSOR, CO  80550 / LONGMONT, COLORADO 80504 — a place, a state, a ZIP. */
export const CITY_ZIP = /\b(?:[A-Z][A-Za-z.'-]*\s){0,2}[A-Z][A-Za-z.'-]*,\s*[A-Za-z]{2,20}\s+\d{5}(?:-\d{4})?\b/g;

/** Named, so a residual scan can say which one it found. */
export const CONTACT_PATTERNS: [string, RegExp][] = [
  ['phone_nanp', PHONE_NANP], ['web_host', WEB_HOST], ['street_address', STREET_ADDRESS], ['city_zip', CITY_ZIP],
];

/** Remove every non-UAE contact detail from a string (used by scrubIdentity). */
export function scrubContacts(s: string): string {
  let t = String(s ?? '');
  for (const [, re] of CONTACT_PATTERNS) t = t.replace(re, '');
  return t;
}
