// customer_facing_knowledge.ts — which kb_chunks rows a customer or a supplier may be told (seat: customer_support).
//
// FOUNDER RULING, 27 Oct 2026 (public.founder_instruction 1338). Asked: "1,317 knowledge rows that the AI wrote itself
// (including 'Typical Cost Ranges (AED)' per trade) are currently shown to customers in chat. No one ever opened a
// source page to check them. Your 7 Oct rule says a fact not read on a page actually opened is never stated to a
// customer. Should these rows be withheld from customers?" His answer: "Withhold from customers." Internal seats still
// read them; a row becomes customer-facing only once it is checked against a source page (it then stops being
// 'generated').
//
// MEASURED on production 27 Oct 2026, read-only: kb_chunks holds 54,360 rows by source_kind (standard 28,451, cert 9,765,
// code 4,023, guide 3,125, document 2,826, trade 2,045, regulation 1,914, generated 1,317, company_faq 481, library 174,
// paper 144, memory 53, reference 39, material 3). 'generated' is model-written trade knowledge; 'memory' is agent
// working notes (#1640 review, third round). No row has a null source_kind.
//
// ONE rule, used by every edge path that hands kb_chunks text to a customer or a supplier:
//   - sales_engineer/portal_turn.ts customerSafe (fn_sales_assist records, the portal chat);
//   - inquiry_intake (kb_query passages given to the intake specialist that talks to the customer).
// think() reads kb_chunks through fn_reason_retrieve / fn_reason_retrieve_ml, whose customer branch applies the same
// rule in SQL (scripts/sql/knowledge_the_ai_wrote_itself_is_withheld_from_customers.sql), so it is not repeated here.
// The SQL list and this list must stay equal: scripts/checks/knowledge_the_ai_wrote_itself_is_withheld_from_customers.test.mjs.

/** kb_chunks source kinds that are never told to a customer or a supplier: written by a model or an agent, not read
 *  on a source page that was actually opened. */
export const KB_CHUNKS_NOT_CUSTOMER_FACING: ReadonlySet<string> = new Set(['generated', 'memory']);

/** True only for a kb_chunks row a customer or supplier may be told. FAILS CLOSED: a missing, empty or non-text
 *  source_kind is not trusted. */
export function kbChunkIsCustomerFacing(sourceKind: unknown): boolean {
  return typeof sourceKind === 'string' && sourceKind.trim() !== '' && !KB_CHUNKS_NOT_CUSTOMER_FACING.has(sourceKind.trim());
}
