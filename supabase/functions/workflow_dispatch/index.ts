// workflow_dispatch — the EMPLOYEE SIDE of the workflow engine.
//
// WHY THIS EXISTS. fn_workflow_step_sweep is the executor side: it queues a ready step only when a
// registered low-risk reversible EDGE executor can run it without notifying a human. Measured on
// production 2026-08-11: 195 workflow runs in flight, 195 ready steps, ZERO of them eligible for
// that path — and 5 runs completed in the engine's lifetime against 195 parked. The parked steps
// are not executor work. They name an EMPLOYEE ("Instrument it with a measure that runs" ->
// intel_director; "Verify the mobile number by OTP" -> Customer Support Specialist), and nothing
// in the company routed a ready step to the employee who owns it.
//
// This is that route, and it is deliberately the same shape as action_worker, which solved the
// identical problem one queue over:
//   1. fn_workflow_step_claim marks the step 'running' and hands it over in the same statement, so
//      two invocations cannot work the same step;
//   2. the employee answers with its OWN four-layer context from fn_agent_context — the step is
//      performed by the person who owns it, not by a generic model;
//   3. the deliverable is ASSERTED before anything advances. cos_execute and action_worker both
//      learned this the expensive way and the NOT_WORK regex is reused verbatim: a courteous
//      "could not reach the AI service" is 60-90 characters and sails past a length check, marking
//      the step done with an apology stored as the work product.
//
// WHAT IT WILL NOT TOUCH, enforced in fn_workflow_step_claim rather than here so the refusal is a
// property of the queue and not of this caller:
//   - employee_task runs. They mirror an org_task that cos_execute already performs and
//     fn_task_review already reviews; their trigger_event is 'task.assigned', so creating work per
//     step would start another 17-step run per step. They follow their own task instead
//     (fn_workflow_run_follow_task).
//   - gate = 'founder'. The four absolute gates — Stripe refund, invoice payment, campaign
//     publish, complaint remedy. Nothing here can pass one.
//   - a step a real executor can genuinely run. That is the sweep's row; a real side effect beats
//     an advisory note and the two halves must not race for it.
//
// THIS PRODUCES ADVISORY WORK, AND SAYS SO. agent_brain is advisory by construction: it reasons,
// determines and hands off; it moves no money, approves no supplier and sends nothing. The step
// output carries mode:'advisory' so a reader is never told a side effect happened when a
// determination was written.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';

const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });

// A FACTORY, NOT A CONSTANT, AND THE CEILING IS SET ABOVE THE POLICY. Both learned on this
// function's FIRST production call, 2026-08-11 21:47, and the gateway diagnosed both itself:
//
//   "[UNMAPPED function "workflow_dispatch" - defaulted to general_drafting (medium). Add a
//    fn_task_class row to route this properly.] | TRUNCATED: the model stopped at the 900-token
//    ceiling for task_class general_drafting, so the reply is cut off mid-output."
//
// output_tokens was exactly 900, the model was haiku rather than the SONNET_FIRST asked for here,
// and the 3,427-character deliverable ended mid-sentence on "the 0 is a calculation error (" —
// with no OUTCOME: line, because the line the prompt asks for is the LAST thing written and
// truncation removes it first. Routing is decided by fn_task_class, not by the ladder named here;
// the row now exists (agent_reasoning, sonnet-5, 8000). max is set ABOVE that policy on purpose so
// ai_gateway's min(caller, policy) always yields the policy — the house rule cos_execute and
// agent_brain already follow. Deleting it is worse: llm.ts falls back to `def.max ?? 700`.
//
// makeLlm binds def.agent at CONSTRUCTION, so a module-scope constant would stamp every row in
// ai_cost_log with the same identity — agent_brain's measured defect, AED 51.08 billed to 'ceo'
// while the reasoning rotated. One factory call per step, carrying that step's employee.
const llmAs = (employee: string) =>
  makeLlm(SONNET_FIRST, { fn: 'workflow_dispatch', agent: employee, max: 8000, temperature: 0.2, timeoutMs: 70000 });

// Reused verbatim from cos_execute and action_worker. See the header.
const NOT_WORK = /(could not reach|couldn't reach|unable to reach|not reachable|ai_unreachable|ai (service|is) (unavailable|unreachable)|try again in a moment|no ai key|ai not reachable|service unavailable)/i;
const MIN_CHARS = 300;          // a workflow step is a determination, shorter than an inbox item
const BATCH = 2;                // claimed ONE AT A TIME inside the loop — see the claim call below
// The budget is checked BEFORE starting a call, so the real ceiling is this plus one call's
// timeoutMs. 80s + 70s = 150s, which is the edge wall; 110s here (cos_execute's number, with its
// 75s calls) would let the last call run past it and lose a deliverable already paid for.
const TIME_BUDGET_MS = 80000;

Deno.serve(async (req: Request) => {
  const started = Date.now();
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const auth = await requireInternal(admin, body?.__secret, 'workflow_dispatch');
    if (!auth.ok) return J({ error: 'unauthorized' }, 401);

    // The kill switch the rest of the AI layer honours. A dispatcher that keeps spending while the
    // founder has frozen execution is the one thing a freeze switch exists to stop.
    const { data: frozen } = await admin.from('app_secrets').select('key,value')
      .in('key', ['cos_frozen', 'ai_kill_switch']);
    if ((frozen || []).some((r: { value: string }) => String(r.value) === 'true')) {
      return J({ ok: true, frozen: true, worked: 0, note: 'AI execution is frozen; no step dispatched.' });
    }

    const want = Math.max(1, Math.min(Number(body?.limit) || BATCH, 10));
    const worked: unknown[] = [];
    const refused: unknown[] = [];
    let capped: Record<string, unknown> | null = null;

    for (let i = 0; i < want; i++) {
      if (Date.now() - started > TIME_BUDGET_MS) break;

      // ONE AT A TIME, ON PURPOSE. Claiming the whole batch up front and then timing out mid-way
      // would leave the unworked remainder marked 'running' with nothing holding them — parked
      // again, and this time invisibly, which is the exact defect this function exists to remove.
      const { data: claimData, error: claimErr } = await admin.rpc('fn_workflow_step_claim', { p_limit: 1 });
      if (claimErr) return J({ ok: false, worked: worked.length, reason: claimErr.message }, 500);
      // fn_workflow_step_claim returns an ARRAY of steps, or an OBJECT when the day's ceiling is
      // spent. Named rather than left to `!batch.length` on a non-array: a silent break would make
      // "capped" and "nothing to do" identical from outside, which is #218's defect exactly.
      if (claimData && !Array.isArray(claimData)) {
        capped = claimData as Record<string, unknown>;
        break;
      }
      const batch = (claimData ?? []) as Record<string, unknown>[];
      if (!batch.length) break;
      const s = batch[0];

      const stepRunId = Number(s.step_run_id);
      const employee = String(s.employee ?? '');
      const stepText = String(s.step ?? '');
      const wfName = String(s.workflow ?? s.workflow_key ?? '');

      // The employee's own context, keyed on the step so the query-aware layers retrieve for it.
      // fn_agent_context ignores any p_max_chars under 22,000 — always the _capped wrapper.
      let brain = '';
      try {
        const { data } = await admin.rpc('fn_agent_context_capped',
          { p_agent_key: employee, p_max_chars: 6000, p_query: (wfName + ' ' + stepText).slice(0, 400) });
        brain = data ? String(data) : '';
      } catch (_e) { /* an employee with no context still has to answer */ }

      const sys = 'You are ' + employee + ' at QuotesDone, a UAE B2B anonymous quotation marketplace. '
        + 'You own one step of a company process that is running right now, and you are performing it. '
        + 'Produce the WORK the step names — the determination, the analysis, the decision and its '
        + 'reasoning — not a description of what you would do and not a status update. Be specific to '
        + 'QuotesDone and the UAE market. Never invent one of our own records, numbers, files or '
        + 'policies: if something you need is genuinely not there, say what is missing, raise it as a '
        + 'gap, and state what you concluded without it. You are advisory — you may decide and '
        + 'recommend within your authority, but you do not move money, approve a supplier, publish, '
        + 'or send anything to a customer. End with a line "OUTCOME:" and one sentence stating what is '
        + 'now true.\n\nYOUR CONTEXT:\n' + brain.slice(0, 9000);

      const user = 'PROCESS: ' + wfName + '\n'
        + 'STEP ' + String(s.step_no) + ': ' + stepText + '\n'
        + (s.gate && s.gate !== 'none' ? 'THIS STEP IS GATED (' + String(s.gate) + '): your output is a '
            + 'recommendation for that gate, not the decision itself.\n' : '')
        + (s.addressed_as && s.addressed_as !== employee
            ? 'The process names this step\'s owner as "' + String(s.addressed_as) + '"; that is you.\n' : '')
        + 'WHAT TRIGGERED THIS RUN: ' + JSON.stringify(s.context ?? {}).slice(0, 1500);

      const out = await llmAs(employee)(sys, user, 8000);
      const deliverable = (out ?? '').trim();

      if (!deliverable || deliverable.length < MIN_CHARS || NOT_WORK.test(deliverable)) {
        const reason = !deliverable ? 'the model returned nothing'
          : NOT_WORK.test(deliverable) ? 'the reply is an apology, not a deliverable'
          : 'deliverable shorter than ' + MIN_CHARS + ' characters';
        // Back to 'ready', never left 'running'. A false success is worse than an unworked step
        // because an unworked step is still counted by fn_workflow_actor_coverage.
        await admin.rpc('fn_workflow_step_release', { p_step_run_id: stepRunId, p_reason: reason });
        refused.push({ step_run_id: stepRunId, employee, reason, chars: deliverable.length });
        continue;
      }

      // The LAST OUTCOME line, not the first — action_worker measured a model using the word
      // mid-document and storing a code fragment as the human-skimmable field.
      const m = [...deliverable.matchAll(/^\s*(?:\*\*)?OUTCOME:?(?:\*\*)?\s*(.+)$/gm)];
      const outcome = (m.length ? m[m.length - 1][1] : deliverable.slice(-200)).trim();

      const { data: adv, error: doneErr } = await admin.rpc('fn_workflow_step_done', {
        p_run: String(s.run_id),
        p_step_no: Number(s.step_no),
        p_output: {
          mode: 'advisory',
          employee,
          addressed_as: s.addressed_as ?? null,
          deliverable: deliverable.slice(0, 20000),
          outcome: outcome.slice(0, 400),
          worked_by: 'workflow_dispatch',
          brain_chars: brain.length,
        },
        p_status: 'done',
      });
      if (doneErr) {
        await admin.rpc('fn_workflow_step_release', { p_step_run_id: stepRunId, p_reason: doneErr.message });
        refused.push({ step_run_id: stepRunId, employee, reason: doneErr.message });
        continue;
      }

      worked.push({ step_run_id: stepRunId, run_id: s.run_id, step_no: s.step_no, employee,
                    workflow: wfName, chars: deliverable.length, advanced: adv,
                    outcome: outcome.slice(0, 200) });
    }

    // One agent_runs row per invocation, status 'error' when nothing could be worked but work was
    // waiting. #218's lesson: a sweep that computes an accurate diagnosis and returns it to cron —
    // which discards the value — is indistinguishable from a healthy one from the outside.
    const { data: cov } = await admin.rpc('fn_workflow_actor_coverage');
    const stillReady = Number((cov as Record<string, unknown> | null)?.ready_dispatchable ?? 0);
    const bad = worked.length === 0 && refused.length > 0;
    await admin.from('agent_runs').insert({
      agent: 'workflow_dispatch',
      status: bad ? 'error' : 'ok',
      counts: { worked: worked.length, refused: refused.length,
                ready_dispatchable_after: stillReady, capped },
      note: bad
        ? 'DISPATCH FAILED: ' + refused.length + ' step(s) claimed and none produced a deliverable — '
          + String((refused[0] as Record<string, unknown>)?.reason ?? '')
        : capped
        ? 'daily ceiling spent: ' + String(capped.worked_today) + '/' + String(capped.cap)
          + ' steps worked today, ' + stillReady + ' still ready'
        : 'worked ' + worked.length + ', refused ' + refused.length + ', ' + stillReady + ' still ready',
      started_at: new Date(started).toISOString(),
      finished_at: new Date().toISOString(),
    });

    return J({ ok: true, worked: worked.length, refused: refused.length, capped,
               ready_dispatchable_after: stillReady, detail: { worked, refused } });
  } catch (e) {
    return J({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
