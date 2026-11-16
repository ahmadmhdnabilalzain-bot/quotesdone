// WHO SEES WHICH PRE-REVEAL QUESTION (sales_engineer, CUSTOMER_W2, 16 Nov 2026; scratchpad holes/CUSTOMER.md item 6).
// rfq_clarification holds two directions on one table:
//   * a SUPPLIER's question to the customer: the customer sees it; every matched supplier sees it once it is answered (the
//     answer is an addendum to the request), and the asking supplier sees its own before that;
//   * a CUSTOMER's question about ONE supplier's quote (asked_by 'customer'): the customer sees it; that supplier sees it only
//     once the sales engineer relayed it (its English copy); no other supplier ever sees it, answered or not, because a
//     supplier's answer about its own quote is not an addendum to the request and would tell a rival what B offers.
// prevented by: messages_api/a_customer_question_reaches_only_its_supplier.test.ts
export type ClarRow = { kind: string; supplier_id: number | string | null; answer?: string | null; answered_at?: string | null; asked_by?: string | null; relayed_at?: string | null };

export function clarifyVisible(r: ClarRow, isOwner: boolean, supplierId: number | null): boolean {
  const mine = supplierId != null && Number(r.supplier_id) === Number(supplierId);
  if (r.asked_by === 'customer') return isOwner || (mine && !!r.relayed_at);
  return isOwner || (r.kind === 'note' && !!r.answer) || mine || !!r.answered_at;
}
