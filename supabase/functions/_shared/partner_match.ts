// A PARTNER SERVICE IS MATCHED KNOWINGLY (12 Nov 2026, sales_engineer; founder ruling 1647; analysis
// services/REPORT.md 3.7). public.fn_match_capability (scripts/sql/a_partner_service_is_matched_knowingly.sql) returns,
// per supplier, partner_hits: the named services he holds ONLY through a partner (supplier_capabilities.services_partner).
// It orders a supplier whose every hit is through a partner after the own-team ones, and its `why` carries a
// "through a partner: ..." segment. This file is what the callers may do with those rows.
//
//   1. WHO IS INVITED: everyone the matcher returns. A supplier matched only through a partner is invited too (founder
//      ruling of 24 Sep 2026, any number of suppliers may quote, outranks the hold-back the analysis proposed); he is
//      ranked after every own-team supplier by fn_match_capability itself, whatever the scores. Nothing is held back here.
//   2. THE CUSTOMER IS NOT TOLD. The analyst's recommendation, adopted: the customer is not told a quote uses a partner
//      (the supplier contracts and warrants the work either way). The "through a partner" segment is removed from every
//      reason before it is stored in inquiry_matches.match_reason (which a customer reads after reveal) or returned to a
//      customer; partner_hits itself is never copied to a customer-facing row.
// prevented by: _shared/partner_match.test.ts and scripts/checks/a_partner_service_is_matched_knowingly.test.mjs.

export interface PartnerRow { service_hits?: unknown; partner_hits?: unknown }

const list = (v: unknown): string[] => (Array.isArray(v) ? v.map(String).filter(Boolean) : []);

/** The named services this supplier holds only through a partner ([] when none, or when the matcher predates them). */
export const partnerHitsOf = (r: PartnerRow): string[] => list(r.partner_hits);

/** Matched through a partner at all: at least one of his named-service hits is a partner service. */
export const throughPartner = (r: PartnerRow): boolean => partnerHitsOf(r).length > 0;

/** Every named-service hit is through a partner (the matcher orders these last). */
export const partnerOnly = (r: PartnerRow): boolean => {
  const hits = list(r.service_hits), partner = partnerHitsOf(r);
  return hits.length > 0 && partner.length >= hits.length;
};

/** The matcher's reason without its internal "through a partner: ..." segment (segments are joined by " · "). */
export function withoutPartnerWhy(why: unknown): string {
  return String(why ?? '').split(' · ').filter((s) => !/^through a partner\b/i.test(s.trim())).join(' · ');
}
