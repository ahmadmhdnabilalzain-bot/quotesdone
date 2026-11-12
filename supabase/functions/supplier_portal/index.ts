
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
    // THE E-MAIL BAN IS READ BESIDE THE COMPANY (it_engineer, 12 Nov 2026; regcert run 50123afa J5, portal home 4,638 ms).
    // Its two reads need only the address, so they no longer wait behind the company read and the by-lead ban read. The
    // 03:00:05Z dashboard (edge_logs trace 01a1cdb2b0fb...) went auth -> leads (+137 ms) -> ban by lead (+52 ms) -> ban by
    // e-mail (+40 ms) -> the dashboard's reads: this saves that one hop, ~40-50 ms of a 417 ms handler. The refusal is
    // unchanged: a ban by lead or by e-mail is still a 403 before any action, and an unreadable ban table still throws into
    // the catch below. The 4.6 s step itself was 3.1 s spent BEFORE this handler started (fixes/hourly REPORT.md).
    // Prevented by: supplier_portal/the_email_ban_is_read_beside_the_company.test.ts.
    const emailBanned = sanctionedEmail(admin, email);
    emailBanned.catch(() => {});   // awaited below; this only stops the no_company return leaving it unobserved
    const { data: sup } = await admin.from('leads').select('id,company_name,approval_status,registration_status,license_expiry,name_corrected_from,licence_gate_reason,exception_due_at,registration_submitted_at,source,rejection_reason,accepted_terms_at,signed_terms_at').eq('claimed_by', email).maybeSingle();
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
    if (await sanctionedLead(admin, sup.id) || await emailBanned) return J(SANCTIONED_REFUSAL, 403);
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
