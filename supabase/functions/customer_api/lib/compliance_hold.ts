// A CUSTOMER WITH AN OPEN SANCTIONS-SCREENING HIT IS NOT MATCHED UNTIL THE CEO DECIDES (16 Nov 2026, FAILURES item 3).
//
// The weekly screen and the accountant's daily re-screen screen customers as well as suppliers
// (public.customer_screening_hit); the CEO's reasoning decides each hit within a day (ceo.sanctions_hit). Until then no
// supplier hears of the customer's request. The request waits on the same re-match schedule a matcher outage uses
// (lib/rematch.ts): the routing record says it waits, the sweep asks again on its backoff, and once the hit is decided a
// false positive is matched on the next step; a confirmed customer is banned. Nothing tells the customer why (a
// screening is never explained to the party: that would tip it off); the portal says we are matching his request, which
// is what happens next. An unreadable screen holds the request (fail closed): the next step of the schedule asks again.
import { screeningOpen } from '../../_shared/sanctioned.ts';
import { failedState, type RematchState } from './rematch.ts';

type Admin = { from: (t: string) => any };

/** true when the customer who posted this request has an open (or confirmed) sanctions-screening hit, or it cannot be read. */
export async function customerFrozen(admin: Admin, inquiryId: string): Promise<boolean> {
  try {
    const { data: own, error } = await admin.from('inquiries').select('customer_id').eq('id', inquiryId).maybeSingle();
    if (error) return true;
    if (!own?.customer_id) return false;
    return await screeningOpen(admin, { customerId: String(own.customer_id) });
  } catch (_e) {
    return true;
  }
}

/** The routing record of a request held for the screening decision: waiting, on the re-match schedule, nobody contacted. */
export function heldForComplianceReview(prior: Partial<RematchState> | null, extra: string, now: Date, schedule: readonly number[]): Record<string, unknown> {
  return { matcher_unavailable: true, waiting_for: 'compliance_review', held_for: 'compliance_review', outcome: 'held',
    fanout: 0, rematch: failedState(prior, extra, now, schedule), at: now.toISOString() };
}
