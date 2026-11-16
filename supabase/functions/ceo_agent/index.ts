// ceo_agent — the CEO seat's runtime. The founder's instructions arrive here, and the CEO's
// decisions leave from here.
//
// WHY IT EXISTS. Until now the CEO seat had tools and no runtime: fn_ceo_request_decision,
// fn_ceo_decide_refund, fn_ceo_standing and the rest existed in the database with nothing able to
// call them, and function_owner recorded 0 edge functions owned by 'ceo'. The founder's only way to
// issue a command was os_api's secretary_chat, which belongs to the OS dashboard he has ruled
// irrelevant and which is being deleted. Deleting os_api before this existed would have left him
// with no command channel at all — his WhatsApp fallback already 404s on an agent_brain that is not
// deployed.
//
// Founder, 8 September 2026: "for the new CEO we will build proper tables and edge functions and
// everything. we dont rely on the old structure." So this shares nothing with secretary_act: no
// department dashboards, no ask_agent, no objective routing, no Postiz. Two seats, one website.
//
// NO MODEL CALL, ANYWHERE IN HERE, and that is a design decision rather than a limitation. Every
// route in llm_route_health is open_until 2126 under the founder's own hold, so a model-dependent
// command channel would be a dead one today. More importantly: an instruction from the founder must
// route the same way twice, cost nothing to route, and be explainable by pointing at the row that
// matched. fn_ceo_classify is a pattern table and a rank. The model's judgement belongs in HOW the
// work is done, not in whether he was understood.
//
// SUPERSEDED 23 Sep 2026 (founder_instruction 886-903: "NO word matching anywhere"). The pattern table
// read "check why the refund failed" as 'measure' and "don't build anything yet" as 'build'. Whether he
// was understood is now REASONED (think(), _shared/reasoned_decisions.ts commandIntent) and the command is
// recorded first, so under the hold it waits as 'interpreting' instead of being routed on a word.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { adminCaller, type TwoStepBody } from '../_shared/admin_session.ts';
import { observe } from '../_shared/observe.ts';
import { makeLlmRich } from '../_shared/llm.ts';
import { defaultDeps } from '../_shared/think.ts';
import { commandIntent } from '../_shared/reasoned_decisions.ts';
import { decideOpenReviews } from '../_shared/review_decide.ts';
import { liveReviewIO } from '../_shared/review_request.ts';
import { workEscalationClocks } from '../_shared/escalation_clock.ts';
import { liveClockIO } from '../_shared/escalation_clock_io.ts';
import { recallCases, recallTrace } from '../_shared/case_recall.ts';
import { COVERAGE_ACTIONS, coverageAction } from './coverage.ts';
import { PLAN_ACTIONS, planAction } from './plan.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const J = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

async function sec(k: string): Promise<string | undefined> {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return data?.value as string | undefined;
}

// WHO IS ASKING. Three ways in, and each one is named in the record rather than collapsed into a
// single "authenticated" boolean — a command channel whose log cannot say who spoke is a channel
// that cannot be audited later.
//
//   'founder'  the shared/scoped internal credential, or his admin JWT. He may command.
//   'ceo'      the CEO seat acting on its own behalf (deciding, closing its own tasks).
//   null       refused.
// THE CREDENTIAL DECIDES THE SEAT, NOT THE CALLER. Until 9 Sep 2026 this read
// `body?.as === 'ceo' ? 'ceo' : 'founder'` — the caller declared which seat it spoke for and was
// believed. Any holder of a credential scoped to ceo_agent could therefore present as the CEO and
// use `decide`, which writes ceo_approval. That is the confused-deputy shape: authentication proved
// the caller was internal, and then the caller was allowed to choose its own authority.
//
// The seat is now derived from internal_credential.context, which the caller cannot influence — it
// is looked up in the database from the secret's hash. An unrecognised context is refused rather
// than defaulted, so minting a new credential does not silently grant a seat: it has to be added
// here deliberately.
//
// UNTIL 9 SEP 2026 THIS MAP HELD ONLY THE FOUNDER, and the seat it was supposed to authenticate had
// no credential at all — every other seat has one (fn.accountant, fn.sales_engineer,
// fn.it_engineer). The effect was not that the CEO could not log in. It was that the ONLY entity
// able to reach `decide` was the founder, while the row it wrote hardcoded decided_by 'ceo'. His
// approvals were being recorded as the CEO's, which points his own 8 September ruling backwards.
// fn.ceo_agent is minted in
// scripts/sql/the_ceo_seat_gets_its_own_credential_and_the_tray_its_staff_file_into.sql and its
// value lives in app_secrets.cred_fn_ceo_agent.
const SEAT_BY_CREDENTIAL: Record<string, 'founder' | 'ceo'> = {
  'fn.founder_channel': 'founder', // his WhatsApp, email and API channel
  'fn.ceo_agent': 'ceo', // the seat acting on its own behalf
};

async function whoami(req: Request, body: Record<string, unknown>): Promise<'founder' | 'ceo' | TwoStepBody | null> {
  if (body?.__secret) {
    const r = await requireInternal(admin, String(body.__secret), 'ceo_agent');
    if (r.ok) return SEAT_BY_CREDENTIAL[r.context] ?? null;
  }
  // The JWT half goes through the one admin door (_shared/admin_session.ts): admin_emails AND an aal2 session. An
  // admin whose session has one factor is answered 403 naming the step (security audit 10 Nov 2026, item 1).
  const a = await adminCaller(admin, sec, req.headers.get('Authorization'));
  if (a.kind === 'two_step_required') return a.body;
  return a.kind === 'admin' ? 'founder' : null;
}

Deno.serve(observe('ceo_agent', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const whoOrStep = await whoami(req, body);
    if (!whoOrStep) return J({ error: 'unauthorized' }, 401);
    if (typeof whoOrStep === 'object') return J(whoOrStep, 403);   // an admin with one factor: name the step
    const who = whoOrStep;

    const action = String(body.action || '').trim();

    // ── COMMAND ────────────────────────────────────────────────────────────────────────────────
    // The founder says something; it is classified, recorded, and becomes work if it asks for work.
    // He is never asked to confirm it, and never asked to phrase it differently: an instruction the
    // pattern table does not recognise still creates a task, because unrecognised is a reason for
    // the seat to think rather than a reason to stop.
    if (action === 'command') {
      if (who !== 'founder') return J({ error: 'only the founder issues commands' }, 403);
      const text = String(body.text || body.message || '').trim();
      if (!text) return J({ error: 'empty_instruction' }, 400);
      const channel = ['whatsapp', 'email', 'api', 'console'].includes(String(body.channel))
        ? String(body.channel) : 'api';
      const { data, error } = await admin.rpc('fn_ceo_command_submit', {
        p_channel: channel, p_from: 'founder', p_body: text,
      });
      if (error) return J({ error: error.message }, 500);
      const r = Array.isArray(data) ? data[0] : data;
      // WHAT HE MEANT IS REASONED, NOT MATCHED (23 Sep 2026, founder_instruction 886-903). The command is
      // recorded first ('interpreting'); think() chooses its intent among ceo_command_intent's meanings and
      // fn_ceo_command_interpret applies it. Under the hold it stays 'interpreting' in the ceo queue and is
      // applied by the replay the moment the hold lifts — never by the old pattern table (fn_ceo_classify, dropped).
      const { data: intents } = await admin.from('ceo_command_intent').select('intent_id,meaning');
      const reasoned = await commandIntent(defaultDeps(admin, 'ceo_agent'), { body: text, intents: intents ?? [], commandId: Number(r?.command_id) });
      if (reasoned.value) {
        const { data: applied, error: aErr } = await admin.rpc('fn_ceo_command_interpret', {
          p_command_id: r?.command_id, p_intent: reasoned.value, p_why: reasoned.result.answer.slice(0, 1000) });
        if (aErr) return J({ error: aErr.message, command_id: r?.command_id }, 500);
        return J({ ok: true, command_id: r?.command_id, intent: applied?.intent, state: applied?.state, reasoning: reasoned.result.steps });
      }
      return J({ ok: true, command_id: r?.command_id, intent: r?.intent_id, state: r?.state, held: reasoned.result.held_id ?? null,
                 note: 'recorded; what it means is reasoned the moment the model hold lifts (' + (reasoned.result.reason ?? 'held') + ')' });
    }

    // ── CONTEXT ────────────────────────────────────────────────────────────────────────────────
    // THE CEO SEAT COULD NOT READ ITS OWN PACK, OR THE COMPANY'S FACTS. Measured 9 Sep 2026: this
    // file called exactly one routine, fn_ceo_command_submit. public.ceo_knowledge and the two
    // routines written to read it -- fn_ceo_context and fn_ceo_knowledge_search -- had no caller
    // anywhere in the deployed estate. Founder, the same day: "the company knowledge is literally
    // connected to every seat automatically. Any seat that we made, the company knowledge should be
    // there. Otherwise, those agents wouldn't know where they work or what they do or what is our
    // company about."
    //
    // fn_ceo_context now pins public.fn_company_context() into its return, so this one call carries
    // both: the CEO pack's advisory records, and the company block -- identity, what we sell, the
    // hard rules, the licence and tax position, the seats, the founder's standing decisions and the
    // active targets, every figure read from its own table at call time.
    if (action === 'context') {
      const query = String(body.query || body.text || '').trim();
      if (!query) return J({ error: 'query_required' }, 400);
      // BY MEANING (23 Sep 2026, founder_instruction 886-903): the pack is ranked by gte-small distance (free, in-region),
      // never by which words of the query it shares. No embedding: no records, and the signal says so.
      const { embedLine } = await import('../_shared/gte_embed.ts');
      const vec = await embedLine(query);
      const { data, error } = await admin.rpc('fn_ceo_context', {
        p_query: query, p_embedding: vec ? '[' + vec.join(',') + ']' : null,
        p_max_chars: Number.isFinite(Number(body.max_chars)) ? Number(body.max_chars) : 18000,
        p_limit: Number.isFinite(Number(body.limit)) ? Number(body.limit) : 8,
      });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, seat: 'ceo', ...(data || {}) });
    }

    // ── INBOX ──────────────────────────────────────────────────────────────────────────────────
    // What the seat is carrying. Open work, open commands, and the refunds waiting on a decision.
    //
    // AND THE TRAY ITS STAFF FILE INTO. Until 9 Sep 2026 this read three sources and none of them
    // was support_ceo_report — the table fn_ceo_request_decision, fn_support_report_to_ceo and
    // fn_accountant_weekly_report_deliver all deliver into. Two rows sat in it status='sent',
    // accepted_at=null, one of them the accountant's weekly financial report, while
    // fn_support_open_reports and fn_ceo_accept_support_report existed with no caller anywhere in
    // the estate. A manager whose inbox does not show what his staff sent him is not a manager who
    // is behind; he is a manager who never received it.
    if (action === 'inbox') {
      const [cmds, tasks, refunds, reports] = await Promise.all([
        admin.from('ceo_command')
          .select('command_id,received_at,channel,body,intent_id,state')
          .not('state', 'in', '("completed","failed","cancelled","superseded","refused")')
          .order('received_at', { ascending: false }).limit(25),
        admin.from('ceo_task')
          .select('task_id,command_id,title,state,blocked_reason,created_at')
          .in('state', ['open', 'working', 'blocked'])
          .order('created_at', { ascending: true }).limit(50),
        admin.from('refunds')
          .select('id,amount_fils,reason_code,requested_by,requested_at,within_auto_window')
          .eq('status', 'requested').order('requested_at', { ascending: true }).limit(25),
        admin.rpc('fn_support_open_reports'),
      ]);
      return J({
        ok: true,
        commands: cmds.data || [],
        tasks: tasks.data || [],
        refunds_awaiting_decision: refunds.data || [],
        // Severity-ordered by the database, oldest first within a severity. The seat is told when
        // the read itself failed rather than being shown an empty tray, because an empty tray and
        // an unreadable one look identical and mean opposite things.
        reports_from_staff: reports.data || [],
        reports_error: reports.error?.message ?? null,
      });
    }

    // ── ACCEPT ─────────────────────────────────────────────────────────────────────────────────
    // Taking ownership of a report a subordinate seat filed. The database refuses an acceptance
    // with no receipt — "an acceptance with no receipt is the accepting party's assumption, not
    // their agreement" — and that refusal is returned verbatim rather than smoothed over.
    // ── THE SEAT BOARD ────────────────────────────────────────────────────────────────────────
    // The founder, 9 Sep 2026: "support and CEO need to be connected so that the CEO is aware of
    // all his tasks and achievement." The inbox shows what a seat CHOSE to escalate; this shows
    // what every seat is ordinarily doing, what it has produced, and what is sitting unanswered on
    // its desk — including the reports waiting on the CEO's own acceptance, which is its backlog
    // rather than anyone else's. Read-only, and open to the founder as well as the seat: he is the
    // one person entitled to see the whole company without asking it for permission.
    if (action === 'board' || action === 'seats') {
      const days = Number(body.days ?? 7);
      const { data, error } = await admin.rpc('fn_ceo_seat_board', { p_days: Number.isFinite(days) ? days : 7 });
      // No run() here: this function is wrapped in observe(), which writes the fn:ceo_agent row.
      if (error) return J({ error: 'board_failed', detail: error.message }, 500);
      return J({ ok: true, board: data });
    }

    if (action === 'accept') {
      if (who !== 'ceo') {
        return J({
          error: 'only the ceo accepts its own reports',
          detail: 'These reports are addressed to the CEO seat. Present the fn.ceo_agent credential.',
        }, 403);
      }
      const reportId = Number(body.report_id);
      if (!Number.isFinite(reportId)) return J({ error: 'report_id_required' }, 400);
      const receipt = String(body.receipt || '').trim();
      if (!receipt) return J({ error: 'receipt_required', detail: 'say what you are accepting, in a sentence' }, 400);
      const { data, error } = await admin.rpc('fn_ceo_accept_support_report', {
        p_report_id: reportId, p_receipt: receipt,
        p_note: body.note === undefined ? null : String(body.note || ''),
      });
      if (error) return J({ ok: false, refused: error.message }, 400);
      const r = data as { ok?: boolean; reason?: string };
      if (r?.ok !== true) return J({ ok: false, refused: r?.reason ?? 'refused' }, 400);
      return J({ ok: true, accepted: data });
    }

    // ── TASK ───────────────────────────────────────────────────────────────────────────────────
    // The database refuses a task marked done without evidence, or blocked without a reason. That
    // refusal is not caught and smoothed over here: it is returned verbatim, because the whole point
    // of the constraint is that the seat cannot quietly close its own work.
    if (action === 'task') {
      const id = Number(body.task_id);
      if (!Number.isFinite(id)) return J({ error: 'task_id_required' }, 400);
      const patch: Record<string, unknown> = {};
      if (body.state) patch.state = String(body.state);
      if (body.evidence !== undefined) patch.evidence = String(body.evidence || '');
      if (body.blocked_reason !== undefined) patch.blocked_reason = String(body.blocked_reason || '');
      if (patch.state === 'done' || patch.state === 'abandoned') patch.closed_at = new Date().toISOString();
      if (!Object.keys(patch).length) return J({ error: 'nothing_to_change' }, 400);
      const { data, error } = await admin.from('ceo_task').update(patch).eq('task_id', id)
        .select('task_id,state,evidence,blocked_reason').maybeSingle();
      if (error) return J({ ok: false, refused: error.message }, 400);
      return J({ ok: true, task: data });
    }

    // ── DECIDE ─────────────────────────────────────────────────────────────────────────────────
    // Founder ruling, 8 September 2026: "all approvals are from CEO. nothing goes to me." So this is
    // the CEO deciding, not the founder being asked. The decision is written to ceo_approval and, for
    // a refund, the refund row is pointed at it — the guards on public.refunds refuse the money
    // moving any other way, so this endpoint cannot approve a payment by itself even if it wanted to.
    //
    // AND THE SEAT THAT DECIDES IS THE SEAT THAT IS RECORDED. Until 9 Sep 2026 there was no
    // fn.ceo_agent credential, so the founder was the only caller who could reach here — and the
    // row written said decided_by 'ceo'. The register named a decider who had not decided. The
    // founder is now refused by name instead: his ruling was that approvals leave him, and a
    // channel that quietly relabels him as the CEO honours the letter of it while inverting it.
    //
    // He is deliberately NOT added to ceo_identity to let decided_by read 'founder' honestly —
    // that table is what the refund guards check, so the honest record would have handed back the
    // authority he gave away. He commands; the seat decides.
    if (action === 'decide') {
      if (who !== 'ceo') {
        return J({
          error: 'only the ceo decides',
          detail: 'Founder ruling, 8 September 2026: "all approvals are from CEO. nothing goes to '
            + 'me." Issue action=command instead; the seat decides and is recorded as having done so.',
        }, 403);
      }
      const kind = String(body.subject_kind || 'refund');
      const subject = String(body.subject_id || '').trim();
      const decision = String(body.decision || '').trim();
      const rationale = String(body.rationale || '').trim();
      if (!subject) return J({ error: 'subject_id_required' }, 400);
      if (decision !== 'approved' && decision !== 'refused') return J({ error: 'decision_must_be_approved_or_refused' }, 400);
      // A decision with no reasoning is a rubber stamp, and a register full of rubber stamps cannot
      // be reviewed later. The seat asks here first; since 29 Sep 2026 the database refuses one too
      // (a04_ceo_approval_carries_its_reasons: six words at least, not the same few repeated).
      if (rationale.length < 12) return J({ error: 'rationale_required', detail: 'say why, in a sentence' }, 400);
      // The database's own rule, asked BEFORE the checklist records evidence for an approval it would then refuse.
      const { data: reasonless } = await admin.rpc('fn_ceo_reasons_problem', { p_reasons: rationale });
      if (typeof reasonless === 'string' && reasonless) return J({ error: 'rationale_required', detail: reasonless }, 400);

      // THE CEO IS THE FOUNDER'S EYES (14 Sep 2026): "ceo approval on refund was made so that the CEO
      // make sure that the process was fully done correctly." Before a refund approval is written, the
      // whole process is checked and the evidence recorded (refund_ceo_check). The database refuses the
      // same approval anyway (a05_ceo_refund_approval_checks_the_process); running it here first is what
      // leaves the evidence behind for a refused attempt, which the trigger's rollback cannot.
      if (kind === 'refund' && decision === 'approved') {
        const { data: rf } = await admin.from('refunds').select('id,transaction_id').eq('id', Number(subject)).maybeSingle();
        if (!rf?.transaction_id) return J({ ok: false, refused: 'subject_id names no refund on a payment' }, 400);
        const { data: chk, error: chkErr } = await admin.rpc('fn_ceo_refund_checklist', { p_transaction_id: rf.transaction_id, p_phase: 'approve', p_record: true });
        if (chkErr) return J({ ok: false, refused: 'checklist_unavailable', detail: chkErr.message }, 503);
        // deno-lint-ignore no-explicit-any
        if ((chk as any)?.ok !== true) return J({ ok: false, refused: 'the process checklist failed', failed: (chk as any)?.failed ?? [] }, 409);
      }

      // WE DECIDED SOMETHING LIKE THIS BEFORE (23 Sep 2026). The CEO's past decisions and every seat's
      // finalised cases, by meaning. Where a finalised one exists the rationale names it (#id) or the
      // caller says why this one differs; a decision that ignores its own precedent is not written.
      const memory = await recallCases(admin, { seat: 'ceo', path: 'decide', situation: `${kind} ${decision}: ${rationale}` });
      const finalised = memory.cases.filter((c) => c.finalised);
      const differs = String(body.differs_because || '').trim();
      if (finalised.length && !finalised.some((c) => rationale.includes('#' + c.case_id)) && differs.length < 12) {
        return J({ ok: false, refused: 'precedent_not_referenced', rule: memory.rule, precedent: memory,
          detail: 'Name the finalised case in the rationale (#id), or pass differs_because saying why this case is different.' }, 409);
      }

      const { data: dec, error: decErr } = await admin.from('ceo_approval').insert({
        subject_kind: kind, subject_id: subject, decision, decided_by: who,
        amount_aed: body.amount_aed ?? null,
        rationale: differs && finalised.length ? `${rationale} (differs from ${finalised.map((c) => '#' + c.case_id).join(', ')}: ${differs})` : rationale,
      }).select('decision_id').maybeSingle();
      if (decErr) return J({ ok: false, refused: decErr.message }, 400);

      let refundLinked: unknown = null;
      if (kind === 'refund' && decision === 'approved' && body.refund_id) {
        const { data: rf, error: rfErr } = await admin.from('refunds')
          .update({ refund_decision_id: dec?.decision_id, decided_by: who, decided_at: new Date().toISOString() })
          .eq('id', Number(body.refund_id)).select('id,status,refund_decision_id').maybeSingle();
        // Surfaced, never swallowed: if the refund guards refuse the link, the decision still stands
        // as a record and the caller is told exactly what refused it.
        refundLinked = rfErr ? { refused: rfErr.message } : rf;
        // THE ONE DECISION (29 Sep 2026): the refund becomes approved only through fn_refund_decide, which runs
        // the second-seat check. Before the window opens it answers window_not_open and the accountant asks again.
        if (!rfErr) {
          const { data: fin, error: finErr } = await admin.rpc('fn_refund_decide', { p_refund_id: Number(body.refund_id), p_approve: true, p_decided_by: who });
          refundLinked = { ...(rf ?? {}), decide: finErr ? { refused: finErr.message } : fin };
        }
      }
      return J({ ok: true, decision_id: dec?.decision_id, refund: refundLinked, precedent: recallTrace(memory) });
    }

    // ── REVIEW_REFUND ──────────────────────────────────────────────────────────────────────────
    // The CEO's review loop on one refund (fn_ceo_refund_review): every check passes -> approved; a
    // check that cannot be fixed -> declined with the reason; otherwise rejected with one task per
    // owning seat (accountant: money; sales engineer: the ladder and the messages), re-checked when
    // the last task closes. Every outcome is a round in public.ceo_decision_round; after four rejections the
    // CEO owes a replace-or-withdraw with reasons (ceo.decision_owed), never the founder (founder_instruction 1059).
    if (action === 'review_refund') {
      if (who !== 'ceo') return J({ error: 'only the ceo decides' }, 403);
      const { data, error } = await admin.rpc('fn_ceo_refund_review', { p_refund_id: Number(body.refund_id), p_trigger: 'ceo_agent' });
      if (error) return J({ ok: false, error: error.message }, 400);
      return J({ ok: true, seat: 'ceo', review: data });
    }

    // ── REVIEW REQUESTS (ledger 1152) ──────────────────────────────────────────────────────────────
    // A request to review an automated decision is DECIDED here, on the owning seat's model of another
    // family than the original decision (_shared/review_decide.ts). Driven by the resilience_ping heartbeat (step
    // review_requests); the CEO seat runs it because routing is its, the verdict is the owning seat's.
    // EVERY ESCALATION CARRIES A CLOCK (16 Nov 2026, rulings 1696/1706/1710; _shared/escalation_clock.ts). The heartbeat first puts
    // every payer the live Stripe hold stopped on a clock (the switch is READ there, never written), then works the due clocks: the
    // CEO's model decides, customer_support's model tells the person the decision or an honest status, and only what the CEO names a
    // law for reaches the founder.
    if (action === 'escalation_clocks') {
      if (who !== 'ceo') return J({ error: 'only the ceo seat runs the escalation clocks' }, 403);
      const { data: held, error: heldErr } = await admin.rpc('fn_held_payers_sync');
      const worked = await workEscalationClocks(liveClockIO(admin), Math.min(5, Number(body.limit) || 3));
      return J({ ok: true, held_payers: heldErr ? { error: heldErr.message } : held, worked });
    }

    if (action === 'review_requests') {
      if (who !== 'ceo') return J({ error: 'only the ceo seat runs the review heartbeat' }, 403);
      const id = Number(body.id) > 0 ? Number(body.id) : undefined;
      return J({ ok: true, decided: await decideOpenReviews(liveReviewIO(admin), Math.min(5, Number(body.limit) || 3), id) });
    }

    // ── JUDGEMENT (plan A/B) — REMOVED 16 Nov 2026 (ceo, wave D; founder ledgers 1714/1715). The daily request was built
    // by fn_ceo_plan_tick and never sent: app_secrets.ceo_model_slot does not exist, so 0 of 56 daily plans were answered.
    // The CEO reasons on a model in its weekly plan instead (action 'plan', fn_ceo_plan_due / fn_ceo_plan_contract; rulings
    // 1696, 1705, 1708). scripts/sql/the_ceos_unsent_daily_judgement_request_is_retired.sql.

    // `task` is deliberately open to BOTH seats and carries no guard of its own. whoami returns
    // only 'founder', 'ceo' or null, the null is already refused above, and both remaining seats
    // legitimately touch ceo_task — the CEO working it, the founder unblocking or cancelling work
    // his own command created. A `who !== 'ceo' && who !== 'founder'` check here would be a
    // condition that cannot occur, which reads as protection and provides none.
    // ── THE OBJECTIVE AND THE LIMITS (15 Nov 2026, founder ledger 1701 and 1696; coverage.ts): coverage against target,
    // the funnel and the limits for the founder and the CEO to read; the CEO alone changes a limit or a target, with a reason.
    const cov = await coverageAction({ rpc: (fn, args) => admin.rpc(fn, args),
      recentDecisions: (limit) => admin.from('ceo_supply_decision').select('decided_on,kind,subject,reason,handoff_id,created_at').order('id', { ascending: false }).limit(limit) },
      who, action, body);
    if (cov) return J(cov.body, cov.status);

    // ── THE PLANNING LOOP (15 Nov 2026, founder ledger 1696/1701/1705/1709; plan.ts): the CEO answers the plan fn_ceo_plan_due
    // opened, on the request's own task class (the weekly plan on ceo_strategic_planning, his hard route; the daily review on
    // routine_employee_reasoning), and code files it (fn_ceo_plan_file). At most two model calls a plan.
    const plan = await planAction({
      rpc: (fn, args) => admin.rpc(fn, args),
      model: async (system, user, taskClass) => {
        const daily = taskClass === 'routine_employee_reasoning';
        const llm = makeLlmRich(undefined, { json: true, fn: 'ceo_agent', agent: 'ceo', taskClass, max: daily ? 2000 : 8000,
          timeoutMs: daily ? 40000 : 110000, temperature: 0.2 });
        const r = await llm(system, user, daily ? 2000 : 8000);
        return { content: r.content ?? null, error: r.error ?? (r.content ? null : r.outcome ?? 'no answer'), truncated: !!r.truncated, model: r.model ?? null };
      },
      recentPlans: (limit) => admin.from('ceo_plan_week').select('id,kind,period,status,model,error,refusals,created_at,filed_at,ceo_plan_bet(id,revision,ord,channel,seat,what,measure,target,due_at,status,refusal,actual)')
        .order('id', { ascending: false }).limit(limit),
      detach: (work) => {
        // deno-lint-ignore no-explicit-any
        const rt = (globalThis as any).EdgeRuntime;
        if (typeof rt?.waitUntil !== 'function') return false;
        rt.waitUntil(work);
        return true;
      },
    }, who, action, body);
    if (plan) return J(plan.body, plan.status);

    return J({ error: 'unknown_action', actions: ['command', 'context', 'inbox', 'task', 'decide', 'review_refund', 'accept', ...COVERAGE_ACTIONS, ...PLAN_ACTIONS] }, 400);
  } catch (e) {
    return J({ error: String((e as Error)?.message || e) }, 500);
  }
}));
