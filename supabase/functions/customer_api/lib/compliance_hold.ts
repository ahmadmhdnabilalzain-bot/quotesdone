// A CUSTOMER WITH AN OPEN SANCTIONS-SCREENING HIT IS NOT MATCHED UNTIL THE CEO DECIDES (16 Nov 2026, FAILURES item 3).
//
// The weekly screen and the accountant's daily re-screen screen customers as well as suppliers
// (public.customer_screening_hit); the CEO's reasoning decides each hit within a day (ceo.sanctions_hit). Until then no
// supplier hears of the customer's request.
//
// ITS OWN WAIT, NOT THE OUTAGE SCHEDULE (review of 16 Nov, residual risk). The request used to ride the matcher-outage
// backoff (lib/rematch.ts): about six days of tries, then `exhausted`, and the 14-day closer could close it telling the
// customer "a fault on our side stopped us matching it". A screening is no fault and has no clock of its own. So the
// routing record still says matcher_unavailable (every reader of a waiting request already treats that as "we are matching
// it": the portal line, the stalled-supplier rescue, the closer), but its rematch state has no next try (next_at null) and
// is never exhausted: the sweep never asks again and the closer never takes it. The CEO's decision releases it:
// public.fn_customer_screening_decide sets next_at to now when the customer's last open hit is decided false_positive, and
// the sweep matches it on its next beat. A confirmed customer is banned and the request stays held (nobody is told why: a
// screening is never explained to the party). An unreadable screen holds the request (fail closed) the same way.
import { screeningOpen } from '../../_shared/sanctioned.ts';
import type { RematchState } from './rematch.ts';

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

/** The routing record of a request held for the screening decision: waiting with no next try and never exhausted, nobody
 *  contacted, until fn_customer_screening_decide releases it. `prior` keeps the first failure time of an earlier outage. */
export function heldForComplianceReview(prior: Partial<RematchState> | null, extra: string, now: Date): Record<string, unknown> {
  const at = now.toISOString();
  const rematch: RematchState & { held_for: string } = { attempts: 0, first_failed_at: String(prior?.first_failed_at || at), failed_at: at,
    next_at: null, exhausted: false, extra, held_for: 'compliance_review' };
  return { matcher_unavailable: true, waiting_for: 'compliance_review', held_for: 'compliance_review', outcome: 'held', fanout: 0, rematch, at };
}
