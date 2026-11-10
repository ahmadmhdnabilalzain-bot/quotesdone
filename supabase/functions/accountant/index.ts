// accountant — the Accountant seat's runtime. The company's FOURTH agent.
//
// WHY IT EXISTS. The founder, 9 September 2026: "now what we need to build is the accountant agent.
// tasks: any financial thing on the platform including refunds. reports to CEO. collects expenses
// from the email expenses@mail.quotesdone.com. create weekly report as pdf and share it with me and
// the CEO. takes approval from CEO on refunds and Meta ads expenses."
//
// NO MODEL CALL, ANYWHERE IN HERE, and every action below was chosen so that is not a limitation.
// All 8 routes in llm_route_health are held under the founder's own hold and
// fn_kernel_paid_provider_gate denies GLOBALLY while any route is held. Bookkeeping is the one seat
// where that costs nothing at all: a ledger balance is arithmetic over source rows, a grant answer
// is a database decision, and a refund this seat may not approve is a routing fact. There is no
// judgement in any of it, which is why none is faked.
//
// THE CREDENTIAL DECIDES THE SEAT, NOT THE CALLER. ceo_agent shipped on 8 Sep reading `body.as` and
// believing it, which let any holder of an in-scope credential present as the CEO — a real
// confused-deputy defect, fixed the same day. This file never reads a seat name off the payload.
//
// WHAT IS DELIBERATELY ABSENT, so nobody mistakes silence for capability: this function does not
// render the weekly report. Naming an absence here is cheaper than discovering later that a zero meant
// "nothing was collected" when it meant "nothing collects".
//
// 14 SEP 2026 — THE SEAT PAYS WHAT THE CEO APPROVED. The founder: "approval from CEO, execution from
// the accountant always whenever it's related to money", and "anything related to payment is under
// the accountant agent". execute_refunds sends to Stripe exactly the refunds whose CEO approval passed
// the process checklist (refunds.refund_decision_id; the z05 guard refuses anything else), stated at
// the amount the customer paid, and the Stripe fixes the CEO's mismatch playbook hands this seat. It
// holds every ordinary refund while the CEO's circuit breaker is on. resilience_ping calls it under
// this seat's own credential.
//
// 9 SEP 2026 — THE SEAT NOW READS ITS OWN MAILBOX. The founder: "once he access the email, let him
// send me a report of all what we spent since day 1 by trailing the whole inbox and that would be a
// test. also such tasks dont require LLM i believe and it can be built in code." He is right, and
// this is that, in code:
//
//   expense_sweep — walks the WHOLE of Resend's inbound history (GET /emails/inbound, paged),
//     keeps the messages addressed to expenses@mail.quotesdone.com, applies the SAME sender
//     allowlist the live webhook applies, and books what it can read through the SAME key
//     (expense_entries.source_msg_id = 'resend:<email_id>'), so the sweep and resend_inbound can
//     never book the same receipt twice. A message it cannot read is HELD and NAMED — never
//     guessed, never zeroed, never estimated.
//   spend_report  — the since-day-1 report over what was booked, with the coverage of the last
//     sweep quoted from agent_runs so a total can be seen to be complete or seen to be short.
//
// WHY THE SWEEP HAD TO EXIST AT ALL (measured 9 Sep 2026): the Resend RECEIVING ROUTE for
// expenses@mail.quotesdone.com does not exist — only info@, supplier@ and docs@mail are wired — so
// the live webhook was never going to be handed this mail. Resend kept the messages anyway. The
// history is the only path by which the founder's own spend can reach the ledger.
//
// THE DOOR AND THE ROOMS (9 Nov 2026). This file is the door: CORS preflight, the caller (whoami), the action
// name, then dispatch. Every action lives in ./actions/<group>.ts, the helpers they share in ./lib/ and ./context.ts.
// Split from one 1,715-line file as a pure move: every statement is the one that was here, byte for byte, and
// actions_contract.test.ts pinned the door, every action's dispatch and the refund guards before the move. Checks
// that read this function as text read the whole folder through scripts/lib/function_sources.mjs
// functionSource('accountant').
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
import { type ActionCtx, CORS, J, admin, run, sec } from './context.ts';
import { seatActions } from './actions/seat.ts';
import { documentActions } from './actions/documents.ts';
import { refundActions } from './actions/refunds.ts';
import { knowledgeActions } from './actions/knowledge.ts';
import { handoffActions } from './actions/handoffs.ts';
import { expenseActions } from './actions/expenses.ts';
import { reportActions } from './actions/reports.ts';
import { dutyActions } from './actions/duties.ts';
import { reconcileActions } from './actions/reconcile.ts';
import { recordActions } from './actions/records.ts';

// The action groups, in the order their first action appeared in the old single if-chain. Each group is that
// chain's own `if (action === …)` blocks, moved verbatim, and answers undefined when none of its actions is asked.
// Every condition is a string equality on the one `action`, and no block runs anything before its own condition
// matches, so no two groups can claim one action and the order between groups cannot change an answer.
const ACTION_GROUPS: readonly ((c: ActionCtx) => Promise<Response | undefined>)[] = [
  seatActions, documentActions, refundActions, knowledgeActions, handoffActions, expenseActions, reportActions,
  dutyActions, reconcileActions, recordActions,
];

// THE ONLY CREDENTIAL THAT IS THIS SEAT. An unrecognised context is refused rather than defaulted,
// and there is no service-caller list because nothing calls this function yet — an empty allowance
// is the honest starting point, and widening it later is a decision somebody has to write down.
const SEAT_BY_CREDENTIAL: Record<string, 'accountant'> = {
  'fn.accountant': 'accountant',
};

type Caller = { kind: 'accountant' | 'founder' } | null;

async function whoami(req: Request, body: Record<string, unknown>): Promise<Caller> {
  if (body?.__secret) {
    const r = await requireInternal(admin, String(body.__secret), 'accountant');
    // ok-but-unrecognised is NOT a fallback to the seat. It is a refusal.
    if (r.ok) return SEAT_BY_CREDENTIAL[r.context] ? { kind: 'accountant' } : null;
  }
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!jwt) return null;
  const { data } = await admin.auth.getUser(jwt).catch(() => ({ data: { user: null } } as never));
  const email = String((data as { user?: { email?: string } })?.user?.email || '').toLowerCase();
  if (!email) return null;
  const allow = (await sec('admin_emails') || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
  return allow.includes(email) ? { kind: 'founder' } : null;
}

Deno.serve(observe('accountant', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const caller = await whoami(req, body);
    if (!caller) return J({ error: 'unauthorized' }, 401);

    const action = String(body.action || '').trim();

    const ctx: ActionCtx = { body, action, caller };
    for (const group of ACTION_GROUPS) {
      // awaited inside the try, so an action that throws still reaches the catch below
      const answer = await group(ctx);
      if (answer) return answer;
    }

    // The document doors were missing from this list until 9 Sep 2026, which made them unreachable
    // to anyone who asked the function what it could do rather than reading its source.
    return J({ error: 'unknown_action', action, actions: ['health', 'grants', 'ledger', 'refund_request', 'expense_sweep', 'spend_report', 'assist', 'document', 'documents', 'refund_document', 'refund_documents', 'revenue_document', 'revenue_documents', 'execute_refunds', 'handoffs', 'complete_handoff', 'duties', 'bank_statement', 'filing_outcome', 'court_step', 'charge_resolve'] }, 400);
  } catch (e) {
    await run('error', 'error', {}, String((e as Error).message || e));
    return J({ error: String((e as Error).message || e) }, 500);
  }
}));
