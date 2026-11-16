// think/routing.ts — which model class a step is asked as, which questions are our own duty or fixture traffic, and when a plan is late (moved whole from _shared/think.ts).
import { e2eRunTag } from '../e2e_run.ts';
import { rehearsalLetsFixtureThrough } from '../spend_guards.ts';
import type { Phase, ThinkDeps, ThinkRequest } from './types.ts';

/** The held-question surfaces that are a seat's own scheduled work about the company, never about a person's case. */
// 16 Nov 2026 (OPS_LOOPS): a seat's daily backlog review, its calendar plans, the CEO's calendar owners and compliance changes
// are its own scheduled work too. Not it_engineer.incident_impact or ceo.partnership: those judge what real people see or sent.
export const INTERNAL_DUTY_SURFACE = /^[a-z_]+\.(knowledge_refresh|postmortem|root_cause|ceo_revision|management_review|target_forecast|marketing_month_plan|experiment_approval|experiment_verdict|it_finding|overdue_handoff|authority|order_plan|order_status|order_retro|order_answer|order_response|order_next|backlog_review|calendar_plan|calendar_owner|compliance_change)$/;
/** The class a step is asked as: an easy run's own judgement goes on the seat's routine route (see ThinkRequest.easy). */
export function easyClass(taskClass: string, easy: boolean | undefined): string {
  return easy === true && taskClass === 'internal_judgement' ? 'routine_employee_reasoning' : taskClass;
}
/** Held-question surfaces that are routine for their seat: the quarterly knowledge re-check ('<seat>.knowledge_refresh')
 *  confirms an entry against its source. Measured on the CEO's (ceo.knowledge_refresh): Opus, about USD 0.6 a day, and on
 *  3 Nov every second attempt came back an empty completion at 35-38 s, paid twice. prevented by: _shared/think_spend.test.ts */
// ceo.it_finding and ceo.overdue_handoff (ceo, 13 Nov 2026, founder ledger 1688): the CEO's triage of an IT finding or of an
// overdue hand-over among four fixed choices is routine for its seat, so it runs on the seat's routine route (fn_ai_route
// 'routine_employee_reasoning', measured AED 0.0106 a call for the CEO over 30 days), never on the CEO's Opus route
// (internal_judgement, AED 0.42 a call). scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql files them.
// ceo.authority (15 Nov 2026, third review item 4): a seat's question of authority is two fixed choices (allow_once or refuse,
// inside company limits the SQL enforces), priced by the daily cap at the routine unit (AED 0.0106); left off these lists it ran
// on the CEO's Opus route at about AED 0.42 a call, up to 1.09 (30-day production average), 30 a day = AED 12.7 against a cap
// of AED 0.50. prevented by: _shared/ceo_judges_it_findings.test.ts
// AN ORDER IS A CONVERSATION (ceo, 16 Nov 2026, founder: "how do they talk to each other?"; scripts/sql/
// an_order_is_a_conversation_until_its_outcome.sql files them). A seat's turns on an order it received (<seat>.order_plan,
// .order_status, .order_retro) are its own scheduled work about the company: INTERNAL_DUTY, on the seat's own judgement route
// (AED 0.014-0.019 a call, ai_cost_log 30 days to 15 Nov). The CEO's answers on an order (ceo.order_answer, .order_response,
// .order_next) are routine for his seat: EASY, on his routine route (AED 0.0107 a call), never on his Opus route (AED 0.42);
// Opus stays for the weekly plan only. The seats' surfaces are deliberately NOT easy. prevented by: _shared/order_thread_surfaces.test.ts
export const EASY_DUTY_SURFACE = /(\.(knowledge_refresh|it_finding|overdue_handoff|authority)|^ceo\.order_(answer|response|next))$/;
// THE CLASS NAMES WHAT THE STEP IS; THE SEAT PICKS THE MODEL (29 Sep 2026, founder_instruction 1056, which
// superseded the 23 Sep ruling 841/844). Planning (decompose) and reading pages (research) are
// routine_employee_reasoning; a seat's own answer or decision is internal_judgement; a reply a customer, a
// visitor or a supplier reads, and any Arabic reply, keeps its audience class. The model is chosen in the
// database from the seat (sent as `agent`): fn_ai_route takes a seat's own '<seat>__<class>' row where one
// exists (the CEO's judgement on Opus, while its planning runs on luna) and otherwise gives the seat its own
// plan B (google/gemini-3.8-flash for every seat since matrix v2, 5 Oct 2026); the class logged stays
// the one named here (scripts/sql/every_seat_runs_the_founders_model_matrix_and_every_review_stays_cross_family.sql). Verify stays
// knowledge_validation: routed through counterpart_model to a reviewer of ANOTHER family than the author.
// A FIXTURE QUESTION IS NEVER QUEUED (it_engineer, 24 Sep 2026). The gateway stubs a fixture call, but a question
// HELD for a fixture was filed in the seat queue and replayed later without its caller, so the replay paid for it:
// measured 24 Sep, 26 inquiry_intake.trade rows in two days from the e2e journey (scripts/e2e/journeys.mjs, a customer
// at @example.invalid whose intake the harness deletes). A caller that knows its subject is a fixture says so
// (subject.fixture = true) and nothing is filed. Rows whose text carries the ZZ DEMO / @example.invalid convention are
// expired by fn_reason_held_due before any claim (a_held_row_is_tried_three_times_and_the_build_test_backlog_is_expired.sql),
// so they are never replayed either; the unit tests here may keep using fixture text and still see the queue work.
/** The planner ran out of time or the provider failed (not a hold): answer from a one-step plan instead. */
export function planTimedOut(error: unknown): boolean {
  const e = String(error ?? '');
  return !/circuit_open|open-circuit|founder_hold|model_hold/.test(e) && /gateway_deadline|gateway_http_5\d\d|timeout|aborted/i.test(e);
}

export function isFixtureRequest(req: Pick<ThinkRequest, 'subject'>): boolean {
  return !!req.subject && (req.subject as Record<string, unknown>).fixture === true;
}

/** A fixture may reason only for a proven run tag whose rehearsal window the database reports open. */
export async function fixtureInOpenWindow(deps: Pick<ThinkDeps, 'rpc'>): Promise<boolean> {
  const tag = e2eRunTag();
  if (!tag) return false;
  try { const { data, error } = await deps.rpc('fn_e2e_run_tag_open', { p_tag: tag }); return rehearsalLetsFixtureThrough(tag, data, error); }
  catch (_e) { return false; }
}

export function taskClassFor(phase: Phase, audience: string, _deciding: boolean, language = 'en'): string {
  if (phase === 'verify') return 'knowledge_validation';
  if (phase === 'decompose' || phase === 'research') return 'routine_employee_reasoning';
  if (audience === 'customer' || audience === 'visitor') return 'customer_communication';
  if (audience === 'supplier') return 'supplier_communication';
  if (language === 'ar') return 'customer_communication';   // Arabic wording stays on the audience class
  return 'internal_judgement';                              // the seat's own answer or decision
}
