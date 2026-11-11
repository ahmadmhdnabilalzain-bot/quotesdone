// sales_engineer — the Sales Engineer seat's runtime. The company's third agent, and the first one
// that has a health route.
//
// WHY IT EXISTS. The founder, 9 September 2026: "Sales Engineer and Customer Support report directly
// to the actual new CEO." This seat owns customer intake, document interpretation, technical scope,
// quote readiness, supplier identity and capability verification, supplier-safe RFQ construction,
// matching and dispatch — and keeps ownership until the outcome is VERIFIED.
//
// NO MODEL CALL, ANYWHERE IN HERE, and every action below was chosen so that is not a limitation.
// Measured 9 Sep 2026: all 8 routes in llm_route_health carry open_until = 2126-08-15 under the
// founder's own hold, and fn_kernel_paid_provider_gate denies GLOBALLY while any route is held. So a
// model-dependent runtime would be a dead one today.
//
// That constraint turned out to be clarifying rather than costly. The build prompt is explicit:
// "Use deterministic code for arithmetic, units, schema validation, permissions, budget
// reservations, state transitions and mandatory exclusions." An intake obligation set is exactly
// that — which of a sector's questions remain unresolved is a set difference over a field catalogue,
// not a judgement. The model's judgement belongs in interpreting a drawing and weighing conflicting
// evidence, which is the half that waits for the hold to lift. What is here does not.
//
// WHAT IS DELIBERATELY ABSENT, so nobody mistakes silence for capability: this function does not
// dispatch, does not email, does not write a supplier's verification state, and does not match. Each
// of those needs a capability the estate does not currently have (see `capability` below, which
// reports the honest per-format status the build prompt demands rather than a list of intentions).
//
// Split from one 1,214-line file on 9 Nov 2026 (it_engineer) as a pure move: every statement is the one that was here,
// byte for byte. This file is the door: it knows the caller, keeps a service caller to its actions, then dispatches. Each
// action lives in ./actions/<group>.ts, the helpers they share in ./lib/ and ./context.ts. Checks that read this function
// as text read the whole folder through scripts/lib/function_sources.mjs functionSource('sales_engineer').
import { observe } from '../_shared/observe.ts';
import { langOf } from '../_shared/chat_answers.ts';
import { STATUS, streamReply, wantsStream } from '../_shared/stream_reply.ts';
import { CORS, J, EMITTERS, type ActionCtx } from './context.ts';
import { SERVICE_ACTIONS, whoami } from './lib/caller.ts';
import { run } from './lib/run.ts';
import { dutiesActions } from './actions/duties.ts';
import { portalActions } from './actions/portal.ts';
import { recordsActions } from './actions/records.ts';
import { operatorActions } from './actions/operator.ts';

// The action groups, in the order their first action appeared in the old single if-chain. Each group is that chain's own
// `if (action === …)` blocks, moved verbatim, and answers undefined when none of its actions is asked. The conditions are
// distinct string equalities, so no two groups can claim one action; the customer cutoff that sat between `ask_accountant`
// and `handoffs` stays first in operator.ts with every route it guards, so it still runs after every earlier action, and the compile-time
// proof in `match` (the cutoff narrows `caller`) still has the cutoff and the route in one function.
const ACTION_GROUPS: readonly ((c: ActionCtx) => Promise<Response | undefined>)[] = [
  dutiesActions, portalActions, recordsActions, operatorActions,
];

const plain = observe('sales_engineer', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  // KEEP-WARM (11 Nov 2026): the customer overview now reads assist_history at sign-in (BootPrefetch.tsx), so a deploy must
  // warm this function like the other overview reads (scripts/lib/warm_functions.mjs). No auth, no DB, before anything else.
  if (req.headers.get('x-qd-warm') === '1') return new Response(null, { status: 204 });
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const caller = await whoami(req, body);
    if (!caller) return J({ error: 'unauthorized' }, 401);
    if (caller.kind === 'two_step_required') return J(caller.body, 403);   // an admin with one factor: name the step

    const action = String(body.action || '').trim();
    if (caller.kind === 'service' && !SERVICE_ACTIONS.has(action)) {
      return J({ error: 'forbidden', action, caller: caller.context, allowed: [...SERVICE_ACTIONS] }, 403);
    }

    const ctx: ActionCtx = { req, body, caller, action };
    for (const group of ACTION_GROUPS) {
      // awaited inside the try, so an action that throws still reaches the catch below
      const answer = await group(ctx);
      if (answer) return answer;
    }

    return J({ error: 'unknown_action', action }, 400);
  } catch (e) {
    await run('error', 'error', {}, String((e as Error).message || e));
    return J({ error: String((e as Error).message || e) }, 500);
  }
});

// THE PORTAL ANSWER STREAMS (27 Oct 2026, the same contract as the website widget: _shared/stream_reply.ts). A portal
// `assist` call that sends `Accept: application/x-ndjson` gets a status line at once (so the edge's 150 s idle wall can
// never fire on a turn that is working), then each checked sentence as the model writes it, then `done` with the same
// object the JSON answer carries. Every other action, and any caller without that header, is answered exactly as before.
// One handler answers both, so the observe row and every side effect are identical for either caller.
Deno.serve(async (req) => {
  if (req.method !== 'POST' || !wantsStream(req)) return plain(req);
  const raw = await req.text();
  let b: { action?: unknown; message?: unknown; lang?: unknown } = {};
  try { b = JSON.parse(raw); } catch (_e) { b = {}; }
  const inner = new Request(req.url, { method: 'POST', headers: req.headers, body: raw });
  if (b.action !== 'assist') return plain(inner);
  const lang = langOf(String(b.message || ''), String(b.lang || '').toLowerCase().startsWith('ar') ? 'ar' : 'en');
  return new Response(streamReply(STATUS[lang], (emit) => { EMITTERS.set(inner, emit); return plain(inner).then((r) => r.json()) as Promise<Record<string, unknown>>; }),
    { headers: { 'Content-Type': 'application/x-ndjson; charset=utf-8', 'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no', ...CORS } });
});
