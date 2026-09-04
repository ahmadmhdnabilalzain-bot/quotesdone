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
//   - gate = 'founder'. The four absolute gates — Stripe refund, invoice payment, campaign
//     publish, complaint remedy. Nothing here can pass one.
//   - a step a real executor can genuinely run. That is the sweep's row; a real side effect beats
//     an advisory note and the two halves must not race for it.
//
// THE ORG_TASK LANE (4 Sep 2026, MASTER_PLAN §4.3). This function used to refuse employee_task runs
// outright, because "they mirror an org_task that cos_execute already performs and fn_task_review
// already reviews". cos_execute-on-org_tasks was RETIRED on 3 Sep (cron 124 off, §5.1), so that
// deferral outlived its executor and 35 runs sat on step 1 with 605+ tasks behind them. The claim now
// hands such a step over with lane='org_task' and the OWNING TASK's subject attached, because the work
// is the task, not the generic loop step it is recorded under ("Understand request" retrieves nothing).
// The lane is DETERMINISTIC ONLY: it applies a corroborated company playbook and closes through
// fn_org_task_deterministic_done (fn_task_review publishes), or it releases with the applier's own
// numbers and parks after three attempts. It never reaches for the model — the model executor for this
// lane is the one that was retired, and what an uncovered task waits for is authored knowledge.
//
// THIS PRODUCES ADVISORY WORK, AND SAYS SO. agent_brain is advisory by construction: it reasons,
// determines and hands off; it moves no money, approves no supplier and sends nothing. The step
// output carries mode:'advisory' so a reader is never told a side effect happened when a
// determination was written.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
import { paidProviderGate } from '../_shared/paid_gate.ts';

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

    // INFERENCE HELD = IDLE, NOT FAILURE. Every step this dispatcher works ends in a model call that
    // writes the deliverable. While the founder's paid-provider hold is in force (OpenRouter off until
    // launch) that call only ever comes back empty, so claiming a step here just marks it 'running'
    // and then releases it with "the model returned nothing" — a deliberate config state logged as an
    // error on every tick. Ask the ONE paid gate first: if inference is held, claim nothing and return
    // a clean idle result. The per-minute cron stays enabled and resumes the moment the hold lifts, so
    // the loop is ready for launch without spending the interval erroring.
    // Deterministic-first still runs while the model is held (founder doctrine: internal work is ~95%
    // code + knowledge). Only the ~5% model FALLBACK is gated — so we claim and work steps regardless,
    // and merely record whether the fallback is available.
    const infGate = await paidProviderGate(admin, SONNET_FIRST[0]);
    const modelHeld = !infGate.allowed;

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
      // THE ORG_TASK LANE. `lane` and the org_task_* fields come from fn_workflow_step_claim.
      const isTaskLane = s.lane === 'org_task' && s.org_task_id != null;
      const taskId = isTaskLane ? Number(s.org_task_id) : null;
      const taskTitle = String(s.org_task_title ?? '');
      const taskDetail = String(s.org_task_detail ?? '');
      // The corroboration text the claim computed: the title with opaque identifiers removed, plus the
      // task's own routing words. See fn_org_task_subject for why an id is not a corroboratable term.
      const taskSubject = String(s.org_task_subject ?? '');

      // The employee's own context, keyed on the step so the query-aware layers retrieve for it.
      // fn_agent_context ignores any p_max_chars under 22,000 — always the _capped wrapper.
      // The org_task lane never prompts a model, so it never needs the prompt's context block.
      let brain = '';
      if (!isTaskLane) {
        try {
          const { data } = await admin.rpc('fn_agent_context_capped',
            { p_agent_key: employee, p_max_chars: 6000, p_query: (wfName + ' ' + stepText).slice(0, 400) });
          brain = data ? String(data) : '';
        } catch (_e) { /* an employee with no context still has to answer */ }
      }

      const sys = 'You are ' + employee + ' at QuotesDone, a UAE B2B anonymous quotation marketplace. '
        + 'You own one step of a company process that is running right now, and you are performing it. '
        + 'Produce the WORK the step names — the determination, the analysis, the decision and its '
        + 'reasoning — not a description of what you would do and not a status update. Be specific to '
        + 'QuotesDone and the UAE market. Never invent one of our own records, numbers, files or '
        + 'policies: if something you need is genuinely not there, say what is missing, raise it as a '
        + 'gap, and state what you concluded without it. You are advisory — you may decide and '
        + 'recommend within your authority, but you do not move money, approve a supplier, publish, '
        + 'or send anything to a customer. End with a line "OUTCOME:" and one sentence stating what is '
        + 'now true, then on the FINAL line compact JSON {"confidence":<0.0-1.0>} — how sure you are '
        + 'that what you just produced is correct and complete on the evidence you actually had. 0.9+ '
        + 'means you had the facts and the expertise; 0.5 means you reasoned from partial information; '
        + 'below 0.4 means you were guessing and this step needs a specialist or a source. Be honest '
        + 'and discriminating: a confidence that is always high tells the company nothing, and it is '
        + 'what routes the next step to a stronger or a cheaper model.'
        + '\n\nYOUR CONTEXT:\n' + brain.slice(0, 9000);

      // WHAT THIS RUN HAS ALREADY CONCLUDED (11 Aug 2026). Without it the process does not
      // accumulate: on the first metric_lifecycle run, forecast_analyst answered step 3 with no
      // sight of what intel_director had just concluded in step 2, and six independent essays about
      // one metric is not a process. fn_workflow_step_claim supplies the last three finished steps
      // — conclusion only, not the 4,000-character body — so this applies to any caller of the
      // queue rather than to this function alone.
      const prior = Array.isArray(s.prior_steps) ? s.prior_steps as Record<string, unknown>[] : [];
      const priorText = prior.length
        ? 'WHAT THIS PROCESS HAS ALREADY CONCLUDED, in order — build on it, do not repeat it, and '
          + 'say so plainly if you disagree with a colleague\'s conclusion:\n'
          + prior.map((p) => '  step ' + String(p.step_no) + ' (' + String(p.by) + ') "'
              + String(p.step) + '" → ' + String(p.outcome)).join('\n') + '\n'
        : 'You are the first step of this process to produce anything.\n';

      const user = 'PROCESS: ' + wfName + '\n'
        + 'STEP ' + String(s.step_no) + ': ' + stepText + '\n'
        + priorText
        + (s.gate && s.gate !== 'none' ? 'THIS STEP IS GATED (' + String(s.gate) + '): your output is a '
            + 'recommendation for that gate, not the decision itself.\n' : '')
        + (s.addressed_as && s.addressed_as !== employee
            ? 'The process names this step\'s owner as "' + String(s.addressed_as) + '"; that is you.\n' : '')
        + 'WHAT TRIGGERED THIS RUN: ' + JSON.stringify(s.context ?? {}).slice(0, 1500);

      // DETERMINISTIC-FIRST (founder doctrine: internal work is ~95% code + linked knowledge, no model).
      // Work the step by APPLYING the nearest company playbook/rule to it BY MEANING — no model call.
      // Only a step with no confident knowledge match falls through to the model path below (the ~5%:
      // genuine novelty, marketing reading live data, content generation — held now, live at launch).
      let deliverable = '';
      let outcome = '';
      let selfConfidence: number | null = null;
      let workedBy = 'deterministic';
      // What the applier said when it did NOT match — carried into the release reason so the step
      // records "best match 0.31 below the floor", never a bare "no playbook".
      let noMatchWhy = '';
      // deno-lint-ignore no-explicit-any
      let playbook: any = null;
      try {
        // The step, its process and what triggered the run — the trigger context is what makes
        // "Detect from health, drift or a failed gate" retrieve the health playbook, not a generic one.
        // On the org_task lane the unit of work is the TASK: its title and its detail (the event that
        // raised it, who subscribes and why, and what it asks for). The generic loop step it is
        // recorded under — "Understand request" — describes the ceremony, not the work.
        const need = isTaskLane
          ? (taskTitle + ' — ' + taskDetail).slice(0, 1200)
          : (wfName + ' — ' + stepText + ' — ' + JSON.stringify(s.context ?? {})).slice(0, 1200);
        // deno-lint-ignore no-explicit-any
        const emb = await (new (globalThis as any).Supabase.ai.Session('gte-small'))
          .run(need, { mean_pool: true, normalize: true }) as number[];
        // Cosine alone cannot tell a determination from noise (random in-scope pairs: median 0.837,
        // p90 0.872 — measured 4 Sep 2026), so fn_apply_playbook also demands keyword corroboration
        // from the step's own text and an ACTIONABLE record kind. See apply_playbook_needs_corroboration.sql.
        const { data: det, error: detErr } = await admin.rpc('fn_apply_playbook',
          { p_agent_key: employee, p_query_embedding: '[' + emb.join(',') + ']',
            // Corroboration counts the STEP's own words (process + step), not the trigger JSON — a
            // context blob adds dozens of lexemes and made "8 of 28 terms" fail a step whose own text
            // was fully covered. The embedding above still carries the context for meaning.
            p_query_text: isTaskLane ? taskSubject : wfName + ' ' + stepText,
            p_min_similarity: 0.85, p_k: 20 });
        // deno-lint-ignore no-explicit-any
        const d = det as any;
        if (detErr) noMatchWhy = 'fn_apply_playbook error: ' + String(detErr.message);
        else if (d && d.matched === true && typeof d.determination === 'string' && d.determination.length >= MIN_CHARS) {
          deliverable = String(d.determination);
          outcome = String(d.outcome || deliverable.slice(-200)).trim();
          selfConfidence = typeof d.confidence === 'number' ? d.confidence : null;
          playbook = d;
        } else if (d && d.matched === true) {
          noMatchWhy = 'matched "' + String(d.title ?? '') + '" but its content is ' + String(d.determination ?? '').length + ' chars, under the ' + MIN_CHARS + ' floor';
        } else {
          noMatchWhy = String(d?.reason ?? 'no match');
        }
      } catch (e) { noMatchWhy = 'deterministic path failed: ' + String((e as Error)?.message ?? e); }

      // Only reach for the model when the deterministic engine found no company knowledge for the step,
      // AND the model is available (the ~5% path; skipped while the founder holds it — the step is then
      // released cleanly rather than erroring). A step the claim flagged deterministic_only never does.
      // The org_task lane never reaches for the model: its model executor was the retired one.
      if (!deliverable && !modelHeld && s.deterministic_only !== true && !isTaskLane) {
        workedBy = 'model';
        const out = await llmAs(employee)(sys, user, 8000);
        const raw = (out ?? '').trim();
        // The confidence tail is the gateway's business (it parses `out` itself and writes
        // ai_cost_log.confidence); it is not part of the work product the founder reads.
        const confTail = raw.match(/\{\s*"confidence"\s*:\s*[0-9.]+\s*\}\s*$/);
        selfConfidence = confTail ? Number(confTail[0].replace(/[^0-9.]/g, '')) : null;
        deliverable = confTail ? raw.slice(0, confTail.index).trim() : raw;
        // The LAST OUTCOME line, not the first — action_worker measured a model using the word
        // mid-document and storing a code fragment as the human-skimmable field.
        const m = [...deliverable.matchAll(/^\s*(?:\*\*)?OUTCOME:?(?:\*\*)?\s*(.+)$/gm)];
        outcome = (m.length ? m[m.length - 1][1] : deliverable.slice(-200)).trim();
      }

      if (!deliverable || deliverable.length < MIN_CHARS || NOT_WORK.test(deliverable)) {
        // The release reason is the step's readable state: distinct from success, and it says WHY
        // (the applier's own words — "best match 0.31 is below the apply floor 0.42"). After three
        // such attempts fn_workflow_step_release parks the step as awaiting_model.
        const reason = workedBy === 'deterministic'
          ? 'no company playbook or rule confidently covers this '
            + (isTaskLane ? 'task (org_task ' + taskId + ': ' + taskTitle.slice(0, 80) + ') (' : 'step (')
            + noMatchWhy.slice(0, 300) + ')'
            + (isTaskLane
                ? '; the org_task lane is deterministic only, so it waits for authored knowledge in this department'
                : '; it waits for a specialist, a source, or the ~5% model path' + (modelHeld ? ' (held)' : ''))
          : (!deliverable ? 'the model returned nothing'
             : NOT_WORK.test(deliverable) ? 'the reply is an apology, not a deliverable'
             : 'deliverable shorter than ' + MIN_CHARS + ' characters');
        // Back to 'ready', never left 'running'. A false success is worse than an unworked step
        // because an unworked step is still counted by fn_workflow_actor_coverage.
        const { data: rel } = await admin.rpc('fn_workflow_step_release', { p_step_run_id: stepRunId, p_reason: reason });
        refused.push({ step_run_id: stepRunId, employee, reason, chars: deliverable.length, release: rel ?? null });
        continue;
      }

      const output = {
        mode: 'advisory',
        employee,
        self_confidence: selfConfidence,
        addressed_as: s.addressed_as ?? null,
        deliverable: deliverable.slice(0, 20000),
        outcome: outcome.slice(0, 400),
        worked_by: 'workflow_dispatch',
        brain_chars: brain.length,
        used_llm: workedBy === 'model',
        stranded_reason: s.stranded_reason ?? null,
        lane: isTaskLane ? 'org_task' : 'workflow_step',
        org_task_id: taskId,
      };

      // deno-lint-ignore no-explicit-any
      let adv: any = null;
      let doneErr: { message: string } | null = null;
      if (isTaskLane) {
        // ONE SPINE. The determination closes the TASK, and fn_workflow_run_follow_task closes the
        // mirroring run in one act — the trigger's own words. fn_org_task_deterministic_done re-checks
        // the substance (playbook id and kind, cosine floor, corroboration, length), writes the
        // deliverable, lets fn_task_review PUBLISH it, seals the trace and queues the review. Anything
        // short of {ok:true} — including a reviewer who returned it for revision — releases the step
        // with the routine's own reason.
        const { data: det, error: detErr } = await admin.rpc('fn_org_task_deterministic_done', {
          p_task_id: taskId,
          p_step_run_id: stepRunId,
          p_output: {
            ...output,
            playbook_record_id: playbook?.record_id ?? null,
            playbook_title: playbook?.title ?? null,
            playbook_record_type: playbook?.record_type ?? null,
            similarity: playbook?.similarity ?? null,
            terms_matched: playbook?.terms_matched ?? null,
            terms_total: playbook?.terms_total ?? null,
            candidates: playbook?.candidates ?? [],
          },
        });
        // deno-lint-ignore no-explicit-any
        const dd = det as any;
        if (detErr) doneErr = { message: 'fn_org_task_deterministic_done: ' + detErr.message };
        else if (!dd || dd.ok !== true) {
          // A review that returns the work for revision is NOT "no playbook" — it must not count
          // towards the awaiting-knowledge park, so the reason deliberately does not start with the
          // park phrase fn_workflow_step_release keys on.
          doneErr = { message: 'org_task close refused: ' + String(dd?.reason ?? 'no ok') };
        } else adv = dd;
      } else if (workedBy === 'deterministic') {
        // A deterministic determination closes ONLY through fn_workflow_step_deterministic_done: it
        // re-checks the substance (playbook id, similarity floor, length), seals the decision_trace,
        // queues the review row, supersedes the parked executor attempt, then advances. Anything short
        // of {ok:true} releases the step with the routine's own reason — never a step marked done on
        // a determination the database refused to record.
        const { data: det, error: detErr } = await admin.rpc('fn_workflow_step_deterministic_done', {
          p_step_run_id: stepRunId,
          p_output: {
            ...output,
            playbook_record_id: playbook?.record_id ?? null,
            playbook_title: playbook?.title ?? null,
            playbook_layer: playbook?.layer ?? null,
            playbook_record_type: playbook?.record_type ?? null,
            similarity: playbook?.similarity ?? null,
            // the corroboration key: a close without it predates the calibrated applier
            terms_matched: playbook?.terms_matched ?? null,
            terms_total: playbook?.terms_total ?? null,
            candidates: playbook?.candidates ?? [],
            basis: playbook?.basis ?? null,
          },
        });
        // deno-lint-ignore no-explicit-any
        const dd = det as any;
        if (detErr) doneErr = { message: 'fn_workflow_step_deterministic_done: ' + detErr.message };
        else if (!dd || dd.ok !== true) doneErr = { message: 'deterministic close refused: ' + String(dd?.reason ?? 'no ok') };
        else adv = dd;
      } else {
        const r = await admin.rpc('fn_workflow_step_done', {
          p_run: String(s.run_id), p_step_no: Number(s.step_no), p_output: output, p_status: 'done',
        });
        adv = r.data; doneErr = r.error ? { message: r.error.message } : null;
      }
      if (doneErr) {
        await admin.rpc('fn_workflow_step_release', { p_step_run_id: stepRunId, p_reason: doneErr.message });
        refused.push({ step_run_id: stepRunId, employee, reason: doneErr.message });
        continue;
      }

      worked.push({ step_run_id: stepRunId, run_id: s.run_id, step_no: s.step_no, employee,
                    lane: isTaskLane ? 'org_task' : 'workflow_step', org_task_id: taskId,
                    workflow: wfName, chars: deliverable.length, advanced: adv, worked_by: workedBy,
                    playbook: playbook ? { record_id: playbook.record_id, title: playbook.title, similarity: playbook.similarity } : null,
                    outcome: outcome.slice(0, 200) });
    }

    // One agent_runs row per invocation, status 'error' when nothing could be worked but work was
    // waiting. #218's lesson: a sweep that computes an accurate diagnosis and returns it to cron —
    // which discards the value — is indistinguishable from a healthy one from the outside.
    const { data: cov } = await admin.rpc('fn_workflow_actor_coverage');
    const stillReady = Number((cov as Record<string, unknown> | null)?.ready_dispatchable ?? 0);
    // While the model is held, a tick that worked nothing and only released steps with no deterministic
    // match is IDLE, not a failure — those steps are waiting for the ~5% model path (live at launch).
    const bad = worked.length === 0 && refused.length > 0 && !modelHeld;
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
