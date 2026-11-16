// FIRST TOUCH: which of our links first brought this browser here (marketing + sales_engineer, 23 Sep 2026;
// founder instruction 865). Every link the marketing seat publishes carries
// utm_source=<platform>&utm_medium=social&utm_campaign=<YYYY-MM>&utm_content=<the post's ingest_key>.
//
// PRIVACY POSTURE (cookie policy §2, v1.3): no cookie and no identifier. Only the link's own tags, the path
// and the time are kept, in localStorage 'qd-first-touch', and they leave the browser only inside a supplier
// registration (supplier_api create_company -> fn_marketing_first_touch_record). First touch wins: a later
// visit never overwrites it. Storage refused (private mode) = nothing kept, nothing breaks.
export const FIRST_TOUCH_KEY = 'qd-first-touch';
const TAG = /^[A-Za-z0-9._-]{1,100}$/;

export interface FirstTouch {
  utm_source: string; utm_medium: string | null; utm_campaign: string | null; utm_content: string | null;
  landing_path: string; first_seen_at: string;
}

/** The UTM tags of a URL, or null when it carries no valid utm_source. Malformed tags are dropped. */
export function touchFromUrl(href: string, now: Date = new Date()): FirstTouch | null {
  let u: URL;
  try { u = new URL(href); } catch { return null; }
  const tag = (k: string) => { const v = (u.searchParams.get(k) || '').trim(); return TAG.test(v) ? v : null; };
  const src = tag('utm_source');
  if (!src) return null;
  return { utm_source: src.toLowerCase(), utm_medium: tag('utm_medium'), utm_campaign: tag('utm_campaign'),
           utm_content: tag('utm_content'), landing_path: u.pathname.slice(0, 200), first_seen_at: now.toISOString() };
}

type Store = Pick<Storage, 'getItem' | 'setItem'>;

/** Keeps the first tagged visit; returns what is kept (the older one when there is one).
 *  ONE EXCEPTION (16 Nov 2026, W3_PEOPLE; SUPPLIER #11): a supplier's own referral link (utm_source=referral, from
 *  fn_supplier_referral_link) is a stronger cause than an earlier post, so it replaces a kept non-referral touch and is never itself
 *  replaced. Proven by scripts/checks/a_referral_link_reaches_the_registration.test.mjs. */
export function captureFirstTouch(href: string, store: Store): FirstTouch | null {
  try {
    const kept = readFirstTouch(store);
    const t = touchFromUrl(href);
    if (kept && !(t?.utm_source === 'referral' && kept.utm_source !== 'referral')) return kept;
    if (t) store.setItem(FIRST_TOUCH_KEY, JSON.stringify(t));
    return t;
  } catch { return null; }
}

export function readFirstTouch(store: Store): FirstTouch | null {
  try {
    const j = JSON.parse(store.getItem(FIRST_TOUCH_KEY) || 'null');
    return j && typeof j.utm_source === 'string' && TAG.test(j.utm_source) ? j as FirstTouch : null;
  } catch { return null; }
}
