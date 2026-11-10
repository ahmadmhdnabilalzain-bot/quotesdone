// WHAT "HIRE" DOES ON A REQUEST, GIVEN WHAT IS ALREADY RECORDED (sales_engineer, customer-journey audit 10 Nov 2026).
//
// Two doors record a hire and they wrote different things. The portal's Hire (customer_api complete_inquiry) sets
// status 'completed', outcome 'hired', completed_at and hired_supplier_id, and tells the losing suppliers. The day-3 /
// day-14 follow-up (public.fn_customer_followup_answer, "yes, I hired them") sets hired_supplier_id ONLY. MEASURED on
// origin/main: complete_inquiry awarded only `where hired_supplier_id is null`, so after a follow-up yes the Hire button
// matched no row and answered { ok, already_completed } — the request stayed 'revealed' for good, outcome and
// completed_at never written, the losing suppliers never told; and Hire on a DIFFERENT supplier answered the same ok
// while nothing changed. Now a hire the follow-up recorded is completed by the same press, and another supplier is
// refused with the existing already_hired answer.
// 10 Nov 2026: fn_customer_followup_answer's yes now completes the request itself and tells the losers (scripts/sql/
// a_follow_up_yes_completes_the_request_and_tells_the_losing_suppliers.sql); this press then answers already_completed.
// prevented by: supabase/functions/customer_api/hire.test.ts

export type HireStep =
  | { kind: 'already_hired' }          // another supplier is recorded as hired: refuse
  | { kind: 'already_completed' }      // this supplier, and the request is completed: nothing to do, nothing re-sent
  | { kind: 'award'; from: 'unhired' } // nobody recorded: award, guarded on hired_supplier_id still null
  | { kind: 'award'; from: 'recorded' }; // the follow-up recorded this supplier: complete it, guarded on status not completed

export function hireStep(inq: { status?: unknown; hired_supplier_id?: unknown }, supplierId: unknown): HireStep {
  const hired = inq.hired_supplier_id;
  if (hired != null && Number(hired) !== Number(supplierId)) return { kind: 'already_hired' };
  if (hired != null && String(inq.status || '') === 'completed') return { kind: 'already_completed' };
  return hired == null ? { kind: 'award', from: 'unhired' } : { kind: 'award', from: 'recorded' };
}
