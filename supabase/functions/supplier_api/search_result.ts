// The 'search' action's public shape — owner: customer_support.
//
// 15 SEP 2026. The action selected leads.claimed_by (the claiming account's e-mail) and returned every
// selected column with a spread, so any signed-in supplier who typed two letters of a company name was
// handed the e-mail address that manages each matching listing (audit of 14 Sep, "cross-supplier
// identity disclosure"). Nothing on the page needs it: the caller only needs to know whether a listing
// can be claimed. claimed_by is still READ, because claimable is decided with it, but it never leaves
// the function. Each field is named, so a column added to the select later cannot leak by default.
// The select and the type are kept side by side so a column added to one is seen in the other.
export const SEARCH_COLUMNS = 'id,company_name,emirate,business_role,claimed,claimed_by';
export type LeadHit = {
  id: number;
  company_name: string | null;
  emirate: string | null;
  business_role: string | null;
  claimed: boolean | null;
  claimed_by: string | null;
};

export type SearchResult = {
  id: number;
  company_name: string | null;
  emirate: string | null;
  business_role: string | null;
  claimed: boolean;
  claimable: boolean;
};

export function searchResult(r: LeadHit, email: string): SearchResult {
  return {
    id: r.id,
    company_name: r.company_name,
    emirate: r.emirate,
    business_role: r.business_role,
    claimed: !!r.claimed,
    claimable: !r.claimed || (r.claimed_by ?? '').trim().toLowerCase() === email,
  };
}
