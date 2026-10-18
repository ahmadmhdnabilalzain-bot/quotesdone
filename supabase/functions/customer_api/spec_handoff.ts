// "NOT SURE" ON A HELD REQUEST'S SPEC OPENS A HANDOFF TO THE SALES ENGINEER (sales_engineer, 5 Oct 2026; review of #1186).
// The customer's "not sure" records no answer (a guess never reaches suppliers). Instead of leaving the request on the
// passive hold, customer_api add_missing_specs opens the estate's one handoff door, public.fn_seat_handoff, kind
// 'spec.not_sure' (customer_support -> sales_engineer, registered in
// scripts/sql/a_not_sure_spec_opens_a_handoff_to_the_sales_engineer.sql). One handoff per request: fn_seat_handoff
// returns the open one for the same type and subject. Checked by spec_handoff.test.ts.

/** The spec keys the customer marked "not sure", cleaned: strings only, at most 40, each at most 80 characters. */
export function notSureKeys(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return [...new Set(raw.slice(0, 40).map((k) => String(k ?? '').trim().slice(0, 80)).filter(Boolean))];
}

/** The fn_seat_handoff arguments for a request with "not sure" specs, or null when there are none. */
export function specHandoffArgs(inquiryId: string, customerId: string, keys: string[]) {
  if (!keys.length || !inquiryId) return null;
  return {
    p_from: 'customer_support', p_to: 'sales_engineer', p_type: 'spec.not_sure',
    p_subject_table: 'inquiries', p_subject_id: inquiryId,
    p_payload: { inquiry_id: inquiryId, customer_id: customerId, not_sure: keys,
      waiting_for: 'sales_engineer to help the customer settle these specs' },
  };
}
