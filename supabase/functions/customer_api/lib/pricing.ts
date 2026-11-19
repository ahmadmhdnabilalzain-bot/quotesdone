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
// The pre-reveal bands live in _shared/pre_reveal_bands.ts since 10 Nov 2026 (quote_compare needs them too).
export { jobsBand, matchBand, ratingBand, reviewCountBand, yearsBand } from '../../_shared/pre_reveal_bands.ts';

// The refund case reference the Terms (§5) and Refund Policy (§3, §6) promise to quote.
export const refundRef = (id: number | string) => 'QD-RF-' + String(id);
