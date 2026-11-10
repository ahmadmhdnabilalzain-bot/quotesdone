// customer_api — the reveal rate and fee, the rating and pre-reveal bands, and the refund reference.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move).
import { revealCharge } from '../../_shared/reveal_fee.ts';
import { readRevealRate, recordRateUnreadable } from '../../_shared/reveal_rate.ts';
import { admin } from '../context.ts';

type Cfg = { standard_reveal_rate: number; refund_window_working_days: number };
// Never a guessed rate (../_shared/reveal_rate.ts): null when pricing_config cannot be read, and the caller decides.
export async function getCfg(): Promise<Cfg | null> { const r = await readRevealRate(admin); if (r.ok) return r.cfg as Cfg; await recordRateUnreadable(admin, 'customer_api getCfg -> pricing_config', r.error); return null; }
// 6 Sep 2026 (founder): the reveal fee is 3% of the quotation value with NO discount, NO promotional rate
// and NO cap. This copy computes the standard rate and nothing else, the same as public.reveal_fee();
// pricing_config forbids a promo or a cap by constraint (pricing_config_no_discount_no_cap_ck).
export function revealFee(amount: number, cfg: Cfg | null): number | null { if (!cfg) return null; if (!amount || amount <= 0) return 0; return revealCharge(amount, Number(cfg.standard_reveal_rate)).base_fee; }
// A RATING IS EARNED HERE OR IT DOES NOT EXIST (founder, 9 Sep 2026): "supplier rating should be
// from customers after they tried them", "google review shouldnt be counted". This used to fall
// back to leads.rating ?? leads.rating_maps — the Google Maps star of a business QuotesDone has
// never worked with — and label it source:'Google', which the portal then showed as the supplier's
// rating and scored in its value ranking. 4,477 suppliers carry that scraped number and 0 have ever
// been rated by a customer here, so the fallback WAS the rating on every quote ever compared.
// It is gone. app_rating/app_reviews are written by recompute_supplier_rating() from public.reviews
// and nothing else. No platform review means value null and count 0, which the surface renders as
// "not yet rated on QuotesDone" — an honest absence beats a number that means something else.
export function ratingOf(l: Record<string, any>) { const appN = Number(l.app_reviews || 0); const v = (appN > 0 && l.app_rating != null) ? Number(l.app_rating) : null; return { value: v, count: appN, source: v != null ? 'QuotesDone' : null }; }
export function band(n: number) { n = Number(n || 0); if (n < 1000) return '< AED 1k'; if (n < 5000) return 'AED 1–5k'; if (n < 20000) return 'AED 5–20k'; if (n < 50000) return 'AED 20–50k'; return 'AED 50k+'; }
// PRE-REVEAL FINGERPRINT (27 Jul 2026). my_inquiries used to return the supplier's exact rating,
// exact review count, emirate, years-since-founding and win rate on EVERY quote, revealed or not.
// "4.6 stars, 23 reviews, Sharjah, trading since 2011" is a unique fingerprint: one Google Maps
// search finds the company, and the buyer contacts them directly without ever paying the reveal
// fee, which is the only transaction revenue this business has. Unrevealed quotes now carry
// coarse bands that fit hundreds of firms, plus the verified flag (a trust signal that identifies
// nobody). Emirate, win rate and rating source are withheld until a transaction exists.
export function ratingBand(v: unknown): string | null { const n = Number(v); if (v == null || !isFinite(n) || n <= 0) return null; if (n >= 4.5) return '4.5+'; if (n >= 4) return '4.0-4.5'; if (n >= 3.5) return '3.5-4.0'; return 'below 3.5'; }
// 9 Sep 2026: 'under 5' was returned for a count of ZERO, so a supplier nobody has ever rated on
// QuotesDone read as "has a few reviews" instead of "has none". Zero is now null, the same answer
// the band gives for an absent rating, and the portal renders the pair as "not yet rated".
export function reviewCountBand(v: unknown): string | null { const n = Number(v || 0); if (n >= 50) return '50+'; if (n >= 20) return '20-49'; if (n >= 5) return '5-19'; return n > 0 ? 'under 5' : null; }
export function yearsBand(v: unknown): string | null { if (v == null) return null; const n = Number(v); if (!isFinite(n)) return null; if (n >= 10) return '10+ years'; if (n >= 5) return '5-9 years'; return 'under 5 years'; }

// The refund case reference the Terms (§5) and Refund Policy (§3, §6) promise to quote.
export const refundRef = (id: number | string) => 'QD-RF-' + String(id);
