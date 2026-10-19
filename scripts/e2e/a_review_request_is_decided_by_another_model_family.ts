// a_review_request_is_decided_by_another_model_family — ledger 1152, seat ceo. The sandbox proof that a request for
// human review is DECIDED, with a real model call, by a model family other than the original decision's.
//
// It runs the SAME decision path the ceo_agent heartbeat runs (_shared/review_decide.ts decideOpenReviews and its
// prompt and parser) against the production ai_gateway, inside a tagged rehearsal window (models_allowed, cap USD 15,
// 60 minutes, closed in finally), with the run tag and its internal proof on the call. The requester is a ZZ DEMO
// address of this run (qd-<tag>-...@example.invalid). The SQL half (open, conclude: verdict, seat action, reply) runs
// in ONE aborted transaction with the pending file replayed, so nothing is committed and nothing is sent to anyone.
//
//   QD_FIXTURES=1 deno run -A --no-lock --node-modules-dir=auto scripts/e2e/a_review_request_is_decided_by_another_model_family.ts
import { newRun, keys, internalCred, BASE, REF, closeRehearsalWindow } from '../lib/demo_factory.mjs';
import { mgmtFixture, mgmtRead } from '../lib/qd_guard.mjs';
import { replaySql } from '../lib/safe_replay.mjs';
import { decideOpenReviews, REVIEW_TASK_CLASS, type DueReview, type Verdict } from '../../supabase/functions/_shared/review_decide.ts';

const FILE = 'scripts/sql/a_request_for_human_review_goes_to_the_seat_that_owns_the_decision.sql';
const run = newRun({});
const TAG = run.tag;
const REQUESTER = `qd-${TAG}-review@example.invalid`;
const ORIGINAL_MODEL = 'anthropic/claude-sonnet-5.5';
const q = (s: string) => "'" + s.replace(/'/g, "''") + "'";
const founderRows = async () => (await mgmtRead(REF, `select (select count(*) from public.founder_alerts where created_at >= now() - interval '2 hours'
  and (detail ilike '%${TAG}%' or event ilike '%review request%'))::int a,
  (select count(*) from public.notifications where to_role = 'founder' and created_at >= now() - interval '2 hours'
  and (body ilike '%${TAG}%' or subject ilike '%review request%'))::int n`))[0];

const { SERVICE } = await keys();
const xcred = await internalCred();
const gw = (await mgmtRead(REF, `select value from public.app_secrets where key='cred_fn_ceo_agent'`))[0]?.value;
if (!gw) throw new Error('no ceo_agent gateway credential');

const due: DueReview = {
  id: 0, owner_seat: 'accountant', decision_type: 'refunds', meaning: 'a refund that was granted, declined or delayed',
  channel: 'email', requester: REQUESTER, original_seat: 'accountant', original_family: 'anthropic', counterpart_model: ORIGINAL_MODEL,
  reviewer_model_hint: 'openai/gpt-6-luna-pro', subject_table: null, subject_id: null,
  request_text: 'ZZ DEMO: I paid the reveal fee for my inquiry and the supplier never answered me in five working days. Your system declined my refund automatically. Please have a person review it.',
  evidence: { reveal_fee_aed: 150, reveal_paid_at: '2026-10-08', supplier_replied: false, working_days_without_reply: 7,
              refund_policy: 'the reveal fee is refunded in full when the revealed supplier does not respond within 5 working days' },
  original_decision: { actor: 'accountant', kind: 'refund_check', decision: 'declined',
                       reasons: ['the refund request arrived more than 7 days after the reveal'] },
};

const before = await founderRows();
await mgmtFixture(REF, `insert into public.rehearsal_window (run_tag, opened_by, models_allowed, cap_usd, expires_at)
  values ('qd_run:${TAG}', 'a_review_request_is_decided_by_another_model_family', true, 15, now() + interval '60 minutes')`, 'rehearsal window');
let proof: Record<string, unknown> | null = null; let answer: { model: string | null; ms: number; error?: string | null } | null = null;
try {
  const out = await decideOpenReviews({
    due: () => Promise.resolve([due]),
    ask: async (_r, system, input) => {
      const t0 = Date.now();
      const r = await fetch(`${BASE}/functions/v1/ai_gateway`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + SERVICE, 'x-qd-e2e-run': TAG, 'x-qd-e2e-secret': xcred },
        body: JSON.stringify({ __secret: gw, fn: 'ceo_agent', task_class: REVIEW_TASK_CLASS, agent: due.owner_seat, sys: system, input, max: 700,
          cache_ttl_min: 0, response_format: { type: 'json_object' }, caller_ladder: [due.reviewer_model_hint],
          subject: { email: REQUESTER }, counterpart_model: due.counterpart_model }),
        signal: AbortSignal.timeout(90_000),
      });
      const j = await r.json().catch(() => ({}));
      answer = { model: j?.model ?? null, ms: Date.now() - t0, error: j?.error ?? (r.ok ? null : 'HTTP ' + r.status) };
      return { content: j?.content ?? null, model: j?.model ?? null, error: answer.error };
    },
    conclude: async (_id: number, v: Verdict, model: string) => {
      // the SQL half, aborted: the pending file, the ZZ DEMO request, the verdict as the model gave it, and the counts
      const probe = `do $p$ declare v_open jsonb; v_c jsonb; v_id bigint; r public.decision_review_request; begin
        v_open := public.fn_review_request_open('refunds', 'email', ${q(REQUESTER)}, ${q(due.request_text)}, null, null, 'accountant', ${q(ORIGINAL_MODEL)});
        v_id := (v_open ->> 'id')::bigint;
        v_c := public.fn_review_request_conclude(v_id, ${q(v.verdict)}, ${q(v.reasons)}, ${q(model)}, ${q(v.reply)});
        select * into r from public.decision_review_request where id = v_id;
        raise exception 'CHK<<%>>', jsonb_build_object('landed_seat', r.owner_seat, 'status', r.status, 'verdict', r.verdict,
          'original_family', r.original_family, 'reviewer_model', r.reviewer_model, 'reviewer_family', r.reviewer_family,
          'seat_decision_log', (select count(*) from public.decision_log where id = r.seat_decision_log_id and actor = 'accountant'),
          'reply_recorded', r.reply_text is not null, 'reply_handoff', r.reply_handoff_id,
          'founder_alerts', (select count(*) from public.founder_alerts where created_at = now()),
          'founder_notifications', (select count(*) from public.notifications where created_at = now() and to_role = 'founder'))::text;
      end $p$;`;
      try { await replaySql(Deno.readTextFileSync(FILE) + '\n' + probe, { retry: false, label: 'review e2e' }); }
      catch (e) {
        const m = String((e as Error).message).replace(/\\"/g, '"').match(/CHK<<(\{.*\})>>/s);
        if (!m) throw e;
        proof = JSON.parse(m[1]);
      }
      return proof ?? { ok: false };
    },
    failed: (id, err) => Promise.resolve(console.log('FAILED', id, err)),
  }, 1);
  const after = await founderRows();
  console.log(JSON.stringify({ run: TAG, answer, decided: out, proof,
    founder_rows_for_this_run: { before, after } }, null, 1));
} finally {
  await closeRehearsalWindow(TAG);
}
