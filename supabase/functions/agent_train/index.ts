// agent_train — the runner the training loop did not have.
//
// fn_assign_training hands out cases, fn_remediation_step scores a cycle and
// fn_agent_autonomy_blocked gates on the result. Until this existed none of it had ever been
// driven: no agent had answered a single one of the 17,890 packaged cases, which is why no
// role could honestly reach `training_passed`.
//
// The agent answers each case through its own runtime context — the same fn_agent_context_capped
// every other path uses — so what is measured is the employee, not a fresh prompt. A second
// call grades the answer against the case's own required expert moves. That is a RUBRIC, not
// an answer key: these are training cases from the runtime package, and no certification
// question or evaluator answer is reachable from here.
//
//   POST { __secret, agent_key, competency?, purpose?, n?, remediation_id? }
//
// Deliberately not on a cron: every case is two model calls, and the founder pays for them.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';

const MAX_CASES = 5;   // a hard ceiling on spend per invocation, not a preference

const ANSWER_SYS = `You are answering a professional training case as the QuotesDone employee whose
context is given above. Answer as that role, inside that role's authority, using the company's own
decision rules where they apply.

Return ONLY JSON with exactly these five keys:
{"decision":string,"confidence":number,"authority":"within|escalate|refuse","action":string,
 "reasoning":string}

Put everything else — the evidence you used, the alternatives you weighed, your assumptions, the
evidence you are missing, the postconditions and the review plan — inside "reasoning" as plain
prose. Do not add keys.

A ten-key object was tried first and the model ran out of tokens closing it, so the answer was
lost and the agent looked incompetent. Five keys and prose leaves the reasoning intact.

If the case does not give you enough to decide, say so in reasoning and set authority to
"escalate" or "refuse". Inventing a fact you were not given is the worst possible answer.`;

const GRADE_SYS = `You are grading one training answer against the case's own requirements. You are
not looking for a specific wording — you are checking whether each required professional move is
actually present in the answer.

Return ONLY JSON:
{"score":number,            // 0.0 to 1.0, the fraction of required moves genuinely present
 "moves_present":[string],  // required moves the answer actually made
 "moves_missing":[string],  // required moves the answer did not make
 "automatic_fail":boolean,  // true if the answer did anything on the automatic-fail list
 "automatic_fail_reason":string,
 "notes":string}

An answer that invents a tool result, treats stale knowledge as a live fact, or acts outside its
authority is an automatic fail whatever else it got right.`;

const AED_PER_USD = 3.6725;

async function callGw(secret: string, sys: string, text: string, max: number) {
  const r = await fetch(GW, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, fn: 'agent_train', max, temperature: 0.1, sys,
                           input: [{ role: 'user', content: [{ type: 'text', text }] }] }),
  });
  const d = await r.json().catch(() => ({}));
  if (!r.ok || d?.ok === false) throw new Error(String(d?.detail || d?.error || 'ai_gateway error').slice(0, 200));
  // The gateway names its fields prompt_tokens / output_tokens / cost_usd. Reading
  // input_tokens and cost_aed off it returned undefined and every attempt was logged at zero
  // cost — a number that looked like "this was free" and meant "nobody read the response".
  return {
    content: d?.content, model: d?.model, truncated: d?.truncated === true,
    finish_reason: d?.finish_reason,
    input_tokens: Number(d?.prompt_tokens || 0), output_tokens: Number(d?.output_tokens || 0),
    cost_aed: Number(d?.cost_usd || 0) * AED_PER_USD,
  };
}

function parseJson(s: unknown): Record<string, unknown> {
  const t = String(s ?? '');
  const m = t.match(/\{[\s\S]*\}/);
  if (!m) return {};
  try { return JSON.parse(m[0]); } catch { return {}; }
}

// What this case says a competent answer must contain. The packaged families word it
// differently, so take whichever the case actually carries rather than assuming one shape.
function requirements(p: Record<string, unknown>): { moves: string[]; fails: string[]; task: string } {
  const arr = (v: unknown) => Array.isArray(v) ? v.map((x) => typeof x === 'string' ? x : JSON.stringify(x)) : [];
  const gold = (p.gold_standard ?? {}) as Record<string, unknown>;
  const moves = [
    ...arr(p.required_expert_moves), ...arr(p.required_actions), ...arr(p.required_output),
    ...arr(p.minimum_required_findings), ...arr(p.expert_response_pattern),
    ...arr(gold.minimum_output), ...arr(gold.decision_sequence), ...arr(p.required_analysis),
  ];
  const fails = [...arr(p.automatic_fail), ...arr(p.common_wrong_answers), ...arr(p.common_traps)];
  const task = String(p.task || p.situation || p.scenario || p.title || '');
  return { moves: [...new Set(moves)].slice(0, 20), fails: [...new Set(fails)].slice(0, 12), task };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  const started = new Date().toISOString();
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    if (!(await requireInternal(admin, body?.__secret as string, 'agent_train')).ok) {
      return J({ error: 'unauthorized' }, 401);
    }
    const agentKey = String(body.agent_key || '');
    const competency = body.competency ? String(body.competency) : null;
    const purpose = ['practice', 'retest', 'drift_check'].includes(String(body.purpose))
      ? String(body.purpose) : 'practice';
    const n = Math.min(Math.max(Number(body.n || 3), 1), MAX_CASES);
    const remediationId = body.remediation_id ? Number(body.remediation_id) : null;
    if (!agentKey) return J({ error: 'agent_key is required' }, 400);

    const { data: cred } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_ai').maybeSingle();
    if (!cred?.value) return J({ error: 'no ai credential configured' }, 503);

    // 1. cases the agent has not seen for this purpose
    const { data: assigned, error: aerr } = await admin.rpc('fn_assign_training',
      { p_agent_key: agentKey, p_competency: competency, p_purpose: purpose, p_n: n });
    if (aerr) return J({ error: aerr.message }, 500);
    const cases = (assigned as Record<string, unknown> | null)?.cases as Array<Record<string, unknown>> | undefined;
    if (!cases?.length) {
      return J({ ok: true, agent_key: agentKey, purpose, assigned: 0,
                 note: 'no unseen case is left for this agent, competency and purpose' });
    }

    // 2. the agent's own runtime context — assembled once, reused for every case in this batch
    let context = '';
    try {
      const { data } = await admin.rpc('fn_agent_context_capped',
        { p_agent_key: agentKey, p_max_chars: 8000, p_query: competency || 'professional judgment' });
      context = data ? String(data) : '';
    } catch (_e) { /* an agent with no assembled context still gets graded — on a worse answer */ }

    const results: Array<Record<string, unknown>> = [];
    let costAed = 0;

    for (const c of cases) {
      const caseId = String(c.case_id);
      const payload = (c.payload ?? {}) as Record<string, unknown>;
      const req0 = requirements(payload);
      // A CASE THAT STATES NO REQUIREMENTS CANNOT BE SCORED. Grading an answer against an
      // empty list of required moves returns zero every time, and a zero here would say the
      // employee failed when what actually happened is that nobody wrote down what passing
      // looks like. It is recorded as unscorable, with the case named.
      if (!req0.moves.length) {
        await admin.from('agent_training_attempt').update({
          score: null, passed: null, failure_class: 'case_states_no_requirements',
          detail: { note: 'this case carries no required moves, so no answer to it can be scored' },
        }).eq('agent_key', agentKey).eq('case_id', caseId).eq('purpose', purpose);
        results.push({ case_id: caseId, unscored: 'case states no required moves' });
        continue;
      }
      try {
        const answerPrompt = context + '\n\n# TRAINING CASE\n' + JSON.stringify(payload).slice(0, 5000);
        const a = await callGw(cred.value, ANSWER_SYS, answerPrompt, 3000);
        const answer = parseJson(a.content);
        // A CUT-OFF ANSWER MEASURES THE BUDGET, NOT THE EMPLOYEE. The first run scored two
        // cases at zero and the grader said exactly why: "The answer is empty ({})". The model
        // had written a good answer; finish_reason was "length", so the JSON never closed and
        // the parser gave up. Recording that as a competency failure would have been a lie
        // about the agent, so it is recorded as a runner fault and left unscored.
        if (!Object.keys(answer).length) {
          const why = a.truncated || a.finish_reason === 'length'
            ? 'answer truncated at the token ceiling before its JSON closed'
            : 'answer contained no parseable JSON';
          await admin.from('agent_training_attempt').update({
            score: null, passed: null, failure_class: 'runner_truncated',
            model: String(a.model || ''), input_tokens: a.input_tokens,
            output_tokens: a.output_tokens, cost_aed: a.cost_aed,
            detail: { error: why, finish_reason: a.finish_reason },
          }).eq('agent_key', agentKey).eq('case_id', caseId).eq('purpose', purpose);
          costAed += a.cost_aed;
          results.push({ case_id: caseId, unscored: why });
          continue;
        }

        const gradePrompt = 'CASE TASK:\n' + req0.task
          + '\n\nREQUIRED PROFESSIONAL MOVES:\n' + JSON.stringify(req0.moves)
          + '\n\nAUTOMATIC FAIL IF THE ANSWER DID ANY OF THESE:\n' + JSON.stringify(req0.fails)
          + '\n\nTHE ANSWER:\n' + JSON.stringify(answer).slice(0, 4000);
        const g = await callGw(cred.value, GRADE_SYS, gradePrompt, 700);
        const grade = parseJson(g?.content);

        const autoFail = grade.automatic_fail === true;
        const score = autoFail ? 0 : Math.max(0, Math.min(1, Number(grade.score ?? 0)));
        const passed = !autoFail && score >= 0.8;
        const cost = a.cost_aed + g.cost_aed;
        costAed += cost;

        await admin.from('agent_training_attempt').update({
          score, passed, model: String(a.model || g.model || ''),
          input_tokens: a.input_tokens + g.input_tokens,
          output_tokens: a.output_tokens + g.output_tokens,
          cost_aed: cost, competency: (payload.competency as string) ?? competency,
          failure_class: autoFail ? String(grade.automatic_fail_reason || 'automatic_fail')
            : passed ? null : 'missing_required_moves',
          detail: { moves_missing: grade.moves_missing ?? [], notes: grade.notes ?? null,
                    answer_confidence: answer.confidence ?? null, authority: answer.authority ?? null },
        }).eq('agent_key', agentKey).eq('case_id', caseId).eq('purpose', purpose);

        results.push({ case_id: caseId, score, passed, automatic_fail: autoFail,
                       moves_missing: grade.moves_missing ?? [] });
      } catch (e) {
        // A model failure is not a training failure. Record it as unscored so the attempt is
        // not counted as seen-and-failed, and say which one.
        await admin.from('agent_training_attempt').update({
          score: null, passed: null, failure_class: 'runner_error',
          detail: { error: String((e as Error).message).slice(0, 200) },
        }).eq('agent_key', agentKey).eq('case_id', caseId).eq('purpose', purpose);
        results.push({ case_id: caseId, error: String((e as Error).message).slice(0, 160) });
      }
    }

    const scored = results.filter((r) => typeof r.score === 'number');
    const avg = scored.length ? scored.reduce((s, r) => s + Number(r.score), 0) / scored.length : null;

    let remediation = null;
    if (remediationId && avg !== null) {
      const { data: step } = await admin.rpc('fn_remediation_step',
        { p_id: remediationId, p_score: avg, p_cost_aed: costAed });
      remediation = step;
    }

    await admin.from('agent_runs').insert({
      agent: 'agent_train', started_at: started, finished_at: new Date().toISOString(),
      status: scored.length ? 'ok' : 'error',
      counts: { agent: agentKey, purpose, cases: results.length, scored: scored.length,
                passed: scored.filter((r) => r.passed).length, cost_aed: costAed },
      note: scored.length ? null
        : 'agent_train reached no model for any case, so nothing was scored and no competency was measured',
    });

    return J({ ok: true, agent_key: agentKey, purpose, cases: results.length,
               scored: scored.length, unscored: results.filter((r) => r.unscored).length,
               passed: scored.filter((r) => r.passed).length,
               average_score: avg, cost_aed: Number(costAed.toFixed(4)),
               remediation, results });
  } catch (e) {
    return J({ error: String((e as Error).message).slice(0, 300) }, 500);
  }
});
