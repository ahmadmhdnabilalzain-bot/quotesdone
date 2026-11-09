
import { siteCors } from '../_shared/site_origins.ts';
import { annotate, observe } from '../_shared/observe.ts';
import { probeCaller } from '../_shared/probe_caller.ts';
import { SANCTIONED_REFUSAL, sanctionedEmail, sanctionedLead } from '../_shared/sanctioned.ts';
import { refusalBody, signedInUser } from '../_shared/signed_in_user.ts';
import { dashboardActions } from './actions/dashboard.ts';
import { marketActions } from './actions/market.ts';
import { documentActions } from './actions/documents.ts';
import { eligibilityActions } from './actions/eligibility.ts';
import { type ActionCtx, cors, J, failed, admin } from './context.ts';

// The action groups, in the order the original if-chain ran them, each a chain of its own `if (action === …)` blocks moved
// verbatim that answers undefined when none of its actions is asked. The conditions are distinct string equalities, so no two
// groups can claim one action; an unknown action falls through all four to the 400 below.
const ACTION_GROUPS: readonly ((c: ActionCtx) => Promise<Response | undefined>)[] = [
  dashboardActions, marketActions, documentActions, eligibilityActions,
];

Deno.serve(siteCors(observe('supplier_portal', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  // KEEP-WARM (resilience_ping; 28 Sep 2026 it_engineer, supplier journey). No auth, no DB: the isolate is
  // what needs exercising. See warmPortal() in resilience_ping/index.ts.
  if (req.headers.get('x-qd-warm') === '1') return new Response(null, { status: 204 });
  try {
    // Local refusal first, a bounded auth call, and 503 (not 401) when auth is down — _shared/signed_in_user.ts.
    const who = await signedInUser(admin, req.headers.get('Authorization'));
    // Our own hourly launch-path probe is marked fixture by its credential, never by its say-so (_shared/probe_caller.ts).
    if (!who.ok) return annotate(J(refusalBody(who), who.status), await probeCaller(admin, req, 'supplier_portal'));
    const { email } = who;
    const { data: sup } = await admin.from('leads').select('id,company_name,approval_status,registration_status,license_expiry,name_corrected_from,licence_gate_reason,exception_due_at').eq('claimed_by', email).maybeSingle();
    // `code` IS WHAT THE PORTAL READS (13 Oct 2026, ruling 1230 walk, it_engineer). Without it the shared call()
    // (src/components/portal/supplier/api.ts) stamps every non-2xx answer `load_failed`, so Dashboard never saw
    // no_company and a supplier with no company yet (signed up without an invitation, or whose claim was refused)
    // got "Something went wrong" instead of the registration form. Measured on production, desktop and 375 px.
    // Prevented by scripts/checks/a_supplier_with_no_company_is_shown_the_registration_form.test.mjs.
    if (!sup) return J({ error: 'no_company', code: 'no_company', hint: 'claim your company first' }, 400);
    // A SANCTIONED PARTY CANNOT ACT (founder instruction 516, 18 Sep 2026). One gate, above the
    // action switch, so every screen this function serves is covered by one line rather than
    // forty — including the ones written after today. overview.ts already RENDERS a ban as a
    // banner; a banner is not a refusal, and this is the refusal.
    if (await sanctionedLead(admin, sup.id) || await sanctionedEmail(admin, email)) return J(SANCTIONED_REFUSAL, 403);
    const b = await req.json().catch(() => ({} as any));
    const action = b.action;

    const supId = sup.id;
    const ctx: ActionCtx = { email, sup, supId, b, action };
    for (const group of ACTION_GROUPS) {
      // awaited inside the try, so an action that throws still reaches the catch below
      const answer = await group(ctx);
      if (answer) return answer;
    }


    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return failed('request', 'unexpected_error', 'Something went wrong. Please try again.', e as Error); }
})));
