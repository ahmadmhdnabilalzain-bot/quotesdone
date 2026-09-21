// RETIRED 21 SEP 2026 — prove_supplier_negotiation.mjs
//
// WHAT IT PROVED. §12 of the supplier blueprint, the supplier negotiation assistant, executed over
// HTTPS: it signed in as the demo supplier, POSTed supplier_portal{action:'negotiation'} and asserted
// that the arithmetic was exact (quote -> customer price, app fee, three reduction scenarios), that
// the supplier's cost floor was withheld (supplier_cost_known=false, possible_reduction.available=
// false), that a request for indicative rates was NOT mistaken for price pressure, and that the
// drafted reply never named a discount.
//
// WHY IT IS GONE. The founder removed negotiations from BOTH portals on 21 Sep 2026 (instruction
// 527). SupplierNegotiation.tsx and the supplier_portal 'negotiation' action are deleted, so the
// endpoint this script called no longer exists and there is nothing left to prove. The customer-side
// counterpart (NegotiationAssistant.tsx + the negotiation_assistant edge function) went in the same
// change.
//
// WHAT REMAINS. The routine fn_supplier_negotiation (and fn_negotiation_guidance, and the table
// supplier_negotiation_policy) still exist in the database. No surface calls them. They were not
// dropped in this change.
