// pre_reveal_bands — what a customer may learn of a supplier's track record BEFORE the reveal. Moved verbatim from
// customer_api/lib/pricing.ts on 10 Nov 2026 (customer_support, supplier-reviews audit) so quote_compare reads the same
// bands: it handed the comparison model the EXACT rating, review count and years trading, the fingerprint below.
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

