// action_worker — the employee actually does the item in its inbox.
//
// WHY THIS EXISTS. agent_actions is where work addressed to an AI employee lands: 200 rows sat
// `pending`, 89 of them handoffs from one employee to another, every one carrying a
// recommendation and a confidence, and NOTHING consumed the table. cos_execute is a producer of
// these rows, not a consumer; agent_act is the founder's chat surface and puts him in the loop by
// design. So 21 of the 22 kinds had never been drained and the approval-centre check read the
// company as 16.1% founder-paused against a 10% bar.
//
// This does the work rather than closing the row. One item per invocation:
//   1. the addressee's own four-layer context from fn_agent_context — the same brain cos_execute
//      gives a department, so the answer is the employee's, not a generic model's;
//   2. one model call bounded to 1,400 tokens, because a handoff answer is a determination, not
//      an essay, and the balance is finite;
//   3. the deliverable is asserted before anything closes.
//
// THE ASSERTION IS THE POINT. cos_execute learned this the expensive way and its NOT_WORK regex is
// reused verbatim: a department that cannot reach its specialist returns a courteous 60-90
// character sentence, which sails past a bare length check and marks the work DONE with an apology
// stored as the product. A false success is worse than an unresolved item, because an unresolved
// item gets looked at. Anything short, empty, or matching NOT_WORK leaves the row `pending`.
//
// RISK ORDER, the same shape as the HTTP invoker. Only kinds where an AI employee producing a
// written determination IS the work are eligible. customer_escalation, legal_flag,
// security_incident, prompt_approval, compliance_update and anything touching money are refused
// outright and stay in the founder's queue — a drain that empties those is not autonomy, it is
// the mass-closing the standing rules forbid.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';

const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
// THE CEILING WAS 900, NOT THE 1400 SET HERE, AND IT WAS NEVER SONNET (measured 11 Aug 2026).
// action_worker had no fn_task_class row, so ai_gateway defaulted it to general_drafting — medium
// tier, haiku, max_tokens 900 — and min(caller, policy) made 1400 irrelevant. Of the 229 model
// calls this function made in 14 days, 133 returned output_tokens EXACTLY 900. Not a distribution
// with a tail on the ceiling: 58% of every deliverable this function has produced was cut off
// mid-sentence, and MIN_CHARS=400 could not see it because 900 tokens is ~3,000 characters.
//
// The row now exists (agent_reasoning — an AI employee reasoning over its own context to decide,
// which is exactly what this does). max is raised above that policy on purpose so
// ai_gateway's min(caller, policy) always yields the policy, the same shape cos_execute and
// agent_brain already use; deleting it is worse, because llm.ts falls back to `def.max ?? 700`.
const llm = makeLlm(SONNET_FIRST, { fn: 'action_worker', max: 8000, temperature: 0.2, timeoutMs: 70000 });

// Reused verbatim from cos_execute. See the header.
const NOT_WORK = /(could not reach|couldn't reach|unable to reach|not reachable|ai_unreachable|ai (service|is) (unavailable|unreachable)|try again in a moment|no ai key|ai not reachable|service unavailable)/i;
const MIN_CHARS = 400;

// Kinds an AI employee may settle by producing a written determination.
const WORKABLE = new Set([
  'handoff', 'improvement_question', 'knowledge_task', 'report_recommendation', 'report_task',
  'objective_step', 'strategy_rec', 'ops_recommendation', 'marketing_recommendation',
  'ai_improvement', 'doc_task', 'supply_health', 'decision.route_category', 'autonomy_stall',
]);
// Kinds that are never auto-settled, whatever their risk tier says.
const NEVER = new Set([
  'customer_escalation', 'legal_flag', 'security_incident', 'prompt_approval',
  'compliance_update', 'finance_alert', 'finance_marketing_budget', 'incident',
]);

const nowIso = () => new Date().toISOString();

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const auth = await requireInternal(admin, body?.__secret, 'action_worker');
    if (!auth.ok) return J({ error: 'unauthorized' }, 401);

    // Either a named row, or the oldest eligible one.
    let row: Record<string, unknown> | null = null;
    if (body?.action_id) {
      const { data } = await admin.from('agent_actions')
        .select('id,agent,kind,status,risk,title,recommendation,detail,confidence,created_at')
        .eq('id', Number(body.action_id)).maybeSingle();
      row = data ?? null;
    } else {
      const { data } = await admin.from('agent_actions')
        .select('id,agent,kind,status,risk,title,recommendation,detail,confidence,created_at')
        .eq('status', 'pending').in('kind', [...WORKABLE]).order('created_at').limit(1);
      row = (data && data[0]) ?? null;
    }
    if (!row) return J({ ok: true, worked: 0, note: 'nothing eligible is pending' });

    const kind = String(row.kind ?? '');
    if (String(row.status) !== 'pending') return J({ ok: true, worked: 0, note: 'not pending', action_id: row.id });
    if (NEVER.has(kind) || !WORKABLE.has(kind)) {
      return J({ ok: true, worked: 0, refused: true, kind, action_id: row.id,
                 note: 'this kind is never settled without the founder' });
    }

    const agentKey = String(row.agent ?? '');
    const title = String(row.title ?? '');
    const rec = String(row.recommendation ?? '');

    // The employee's own context, keyed on the item so the query-aware layers retrieve for it.
    let brain = '';
    try {
      const { data } = await admin.rpc('fn_agent_context',
        { p_agent_key: agentKey, p_max_chars: 6000, p_query: (title + ' ' + rec).slice(0, 400) });
      brain = data ? String(data) : '';
    } catch (_e) { /* an employee with no context still has to answer */ }

    const sys = 'You are ' + agentKey + ' at QuotesDone, a UAE B2B anonymous quotation marketplace. '
      + 'An item addressed to YOU is open in your queue and you are settling it now. Produce the WORK, '
      + 'not a status update: the determination, the answer, the decision and its reasoning, and what '
      + 'you have concluded. Be specific and use the company facts below; never invent one of our own '
      + 'records, numbers, files or policies — if something you need is genuinely not there, say what '
      + 'is missing and what you concluded without it. Do not ask the founder anything and do not say '
      + 'you will do it later; this is the deliverable. End with a line "OUTCOME:" and one sentence '
      + 'stating what is now true.\n\nYOUR CONTEXT:\n' + brain.slice(0, 9000);

    const user = 'ITEM ' + row.id + ' (' + kind + ', raised ' + String(row.created_at).slice(0, 10) + ')\n'
      + 'TITLE: ' + title + '\n'
      + 'WHAT WAS ASKED OF YOU: ' + rec + '\n'
      + 'DETAIL: ' + JSON.stringify(row.detail ?? {}).slice(0, 1500);

    // SET TWICE, THE DOCUMENTED SHAPE: this per-call third argument overrides makeLlm's `max`, so
    // raising only the constructor above would have changed nothing. Both are now above the policy.
    const out = await llm(sys, user, 8000);
    const deliverable = (out ?? '').trim();

    if (!deliverable || deliverable.length < MIN_CHARS || NOT_WORK.test(deliverable)) {
      // Left PENDING on purpose. An unresolved item gets looked at; a false success never does.
      return J({ ok: false, worked: 0, action_id: row.id, chars: deliverable.length,
                 reason: !deliverable ? 'the model returned nothing'
                        : NOT_WORK.test(deliverable) ? 'the reply is an apology, not a deliverable'
                        : 'deliverable shorter than ' + MIN_CHARS + ' characters' });
    }

    // The LAST OUTCOME line, not the first. Measured on the first real deliverable (item 1723,
    // legal, 3,508 chars): the model used the word mid-document inside a schema block and the
    // first-match regex stored that instead of the closing sentence, so the human-skimmable field
    // was a fragment of code.
    const outMatches = [...deliverable.matchAll(/^\s*(?:\*\*)?OUTCOME:?(?:\*\*)?\s*(.+)$/gm)];
    const outcome = (outMatches.length ? outMatches[outMatches.length - 1][1] : deliverable.slice(-200)).trim();
    const detail = { ...(row.detail as Record<string, unknown> ?? {}),
      deliverable: deliverable.slice(0, 20000),
      outcome: outcome.slice(0, 400),
      worked_by: 'action_worker',
      worked_at: nowIso(),
      brain_chars: brain.length };

    const { error } = await admin.from('agent_actions')
      .update({ status: 'done', decided_at: nowIso(), decided_by: 'action_worker:' + agentKey, detail })
      .eq('id', row.id).eq('status', 'pending');
    if (error) return J({ ok: false, worked: 0, action_id: row.id, reason: error.message }, 500);

    return J({ ok: true, worked: 1, action_id: row.id, agent: agentKey, kind, chars: deliverable.length, outcome: outcome.slice(0, 200) });
  } catch (e) {
    return J({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
