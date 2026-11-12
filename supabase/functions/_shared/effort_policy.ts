// _shared/effort_policy.ts — how hard the model thinks, set by the consequence of the call (it_engineer, 11 Nov 2026).
//
// Founder ruling 1630 (11 Nov 2026): "Reasoning effort is set by consequence. HIGH for anything that decides, reads
// documents, prices, matches, or writes on the company's behalf. MEDIUM for conversations with customers and suppliers, but
// a conversation that is not straightforward (a complaint, a dispute, a complicated or multi-part question) must get the
// deeper thinking: a 30 to 40 second wait is acceptable. LOW only for simple sorting (which language, which menu option)",
// and only where a side-by-side on identical inputs shows low answers as high does (ruling 1618).
//
// WHAT WAS THERE (measured 11 Nov 2026). Effort was decided in eight places and by nobody for the rest:
//   - six call sites asked 'low' by literal: the WhatsApp intent table, needs-a-person, the WhatsApp menu, the intake trade
//     choice, the intake spec reader (reasoned_channels/decisions/menus) and the WhatsApp status lane (status_lane.ts);
//   - reask.ts asked 'high';
//   - every other call sent no effort, so Claude ran at request_shape.ts's 'medium' and GPT-6 Luna Pro at its own default.
// Two of the six 'low' sites DECIDE (the intake trade is a match; the spec reader decides which specs the customer stated),
// and none of the six had a side-by-side behind it. So this file is the one place the mapping lives:
//   - EFFORT_BY_CLASS: every model_policy task_class (100 rows on production, 11 Nov), by consequence;
//   - SURFACES: the think() decisions that set their own effort, each labelled by what it does, and `provenLow` only where
//     scripts/eval/effort_low_vs_high.mjs has passed on recorded inputs (none has yet, so none is low);
//   - conversationEffort: medium, deepened to high by a cheap rule (no model) for a complaint, a dispute, a refund, a price
//     challenge or a multi-part question, and for a re-draft after the medium draft failed the reply checks.
// The gateway applies EFFORT_BY_CLASS to every call that names no effort (ai_gateway/handle.ts), so a new call site cannot
// fall back to a model's default by forgetting. scripts/sql/model_policy_states_the_effort_of_every_task_class.sql mirrors
// the same map into the database; scripts/checks/the_effort_policy_is_one_map.test.mjs keeps the two equal.
// prevented by: _shared/effort_policy.test.ts, scripts/checks/the_effort_policy_is_one_map.test.mjs

import type { Effort } from './request_shape.ts';

export type Consequence = 'decides' | 'conversation' | 'sorting';
export type PolicyEffort = Extract<Effort, 'low' | 'medium' | 'high'>;

/** A class nobody has classified yet is treated as one that decides: the deeper thinking is the safe side of a mistake. */
export const UNKNOWN_CLASS_EFFORT: PolicyEffort = 'high';

// The conversations: a reply a customer, supplier or visitor reads. Medium, deepened per turn by conversationEffort.
const CONVERSATION = [
  'conversation_reply', 'customer_communication', 'customer_portal_assistant', 'email_triage', 'inbound_email',
  'inquiry_qualification_conversation', 'resend_inbound', 'status_reply', 'supplier_communication', 'support_ai',
  'visitor_chat', 'voice_draft', 'wa_inbound',
] as const;
// Sorting: which option, which language. Medium until the side-by-side proves low answers the same (ruling 1618).
const SORTING = ['health_ping', 'intent_detection'] as const;
// Everything else in model_policy decides, reads documents, prices, matches, or writes on the company's behalf.
const DECIDES = [
  'accountant_expense_classification', 'accountant_receipt_extraction', 'accountant_weekly_report', 'agent_reasoning',
  'approval_threshold', 'brand_rule_check', 'calendar_scheduling', 'category_classification', 'ceo__internal_judgement',
  'ceo__knowledge_validation', 'ceo_approval_decision', 'ceo_article_review', 'ceo_judgement', 'ceo_strategic_planning',
  'chief_of_staff_decision', 'content_drafting', 'contract_analysis', 'currency_conversion', 'date_calculation',
  'department_planning', 'document_extraction', 'document_extraction_multimodal', 'drawing_and_boq_analysis',
  'drawing_boq_confirm', 'drawing_vision_count', 'duplicate_detection', 'edge_case_escalation', 'engineering_reasoning',
  'executive_report', 'file_operations', 'finance_analysis', 'general_drafting', 'identity_redaction_verify',
  'internal_judgement', 'json_extraction', 'json_extraction_text', 'knowledge_ingestion', 'knowledge_research',
  'knowledge_validation', 'kpi_calculation', 'kpi_measurement', 'legal_analysis', 'marketing_article_draft',
  'marketing_article_revise', 'marketing_copy', 'marketing_evaluate', 'marketing_geo_online', 'marketing_geo_search',
  'marketing_image', 'marketing_plan', 'marketing_plan_defend', 'marketing_quality_review', 'marketing_research',
  'marketing_watch', 'memory_retrieval', 'missing_fields_detection', 'money_state_change', 'note_capture', 'ocr',
  'ocr_cleanup', 'procurement_reasoning', 'quote_comparison', 'redaction_detection', 'reflection_and_learning',
  'rfq_routing', 'routine_employee_reasoning', 'sales_engineer__document_extraction', 'sales_engineer__json_extraction',
  'sales_engineer__knowledge_validation', 'sales_engineer__procurement_reasoning', 'sales_engineer_reasoning',
  'seat_deliberation_blind', 'seat_deliberation_compare', 'security_incident_analysis', 'speech_transcription',
  'summarization', 'supplier_matching', 'supplier_scoring', 'supplier_trade_choice', 'translation', 'translation_general',
  'vat_calculation', 'vision', 'workflow_routing', 'workflow_state_and_permissions',
  // the case model (support_case_memory.ts): the summary records what we promised, the next reply relies on it
  'case_summary',
] as const;

/** Every task class and its effort. The one map; the SQL file and the gateway read the same values. */
export const EFFORT_BY_CLASS: Readonly<Record<string, PolicyEffort>> = Object.freeze({
  ...Object.fromEntries(DECIDES.map((c) => [c, 'high' as const])),
  ...Object.fromEntries(CONVERSATION.map((c) => [c, 'medium' as const])),
  ...Object.fromEntries(SORTING.map((c) => [c, 'medium' as const])),
});
export const CONSEQUENCE_OF_CLASS: Readonly<Record<string, Consequence>> = Object.freeze({
  ...Object.fromEntries(DECIDES.map((c) => [c, 'decides' as const])),
  ...Object.fromEntries(CONVERSATION.map((c) => [c, 'conversation' as const])),
  ...Object.fromEntries(SORTING.map((c) => [c, 'sorting' as const])),
});

// ── A STEP A PERSON IS WAITING ON (founder ledger 1642, 12 Nov 2026, amending ruling 1630) ───────────────────────────
// "A step a person is waiting on uses the highest effort that finishes inside that wait, measured; thinking that needs longer
// moves off the live reply, or its wait is lengthened where the person is shown progress." Measured on 11 Nov 2026 after
// f78d2e916 raised these surfaces to high without re-measuring the clocks they run under (final audit section 3): the intake
// spec reader finished 0 of 22 times inside the turn at high and production cut 23 of 41 intake readings on 11 Nov against
// 3 of 37 on 10 Nov; the WhatsApp reading's p50 went from 5.3 s (low) to 11.9 s (high) of a reply the founder wants under
// 15 s. `clock` records such a surface: the wait it runs inside, the effort that fits it and the replay that measured it
// (scripts/eval/effort_low_vs_high/replay.ts, run tags in docs/reports/2026-11-11-history-and-effort.md section 7). It is
// the CLOCK's effort, never "proven low": `provenLow` stays false on every one, and the consequence stays what it is.
export interface OnTheClock { effort: PolicyEffort; waitMs: number; measured: string }
/** The think() decisions and lanes that set their own effort. `provenLow` is flipped only by a passed side-by-side
 *  (scripts/eval/effort_low_vs_high.mjs writes the verdict; the flip is a reviewed one-line change here). `clock`: the
 *  surface runs inside a wait a person has, and asks the highest effort the replay measured inside it (ledger 1642). */
export const SURFACES: Readonly<Record<string, { consequence: Consequence; provenLow: boolean; why: string; clock?: OnTheClock }>> = Object.freeze({
  // whatsappReadings asks three things in this one call: the intent, the menu option AND whether a person is needed. The
  // last is an escalation decision, so the call is not "simple sorting" and stays high whatever a side-by-side shows.
  'wa_inbound.intent_table': { consequence: 'decides', provenLow: false, why: 'the intent, the menu option and whether a person is needed, in one call',
    // On the WhatsApp reply's path, cut at wa_inbound/classification.ts CLASSIFY_MS (20 s). High ran past it 3 of 8 times;
    // medium is the highest effort that stays inside it, and it chose as high did 8 of 8 (low 7 of 8).
    clock: { effort: 'medium', waitMs: 20_000, measured: '12 Nov 2026 run evaleff1292fbdc2, 8 recorded messages: low p50 5.8 s, p95 13.8 s; medium p50 9.1 s, p95 16.5 s, max 16.5 s; high p50 10.2 s, p95 30.4 s, 3 of 8 over 20 s' } },
  'wa_inbound.greeting_state': { consequence: 'sorting', provenLow: false, why: 'which menu option a reply picks' },
  'wa_inbound.problem_state': { consequence: 'sorting', provenLow: false, why: 'which menu option a reply picks' },
  'wa_inbound.needs_a_person': { consequence: 'decides', provenLow: false, why: 'whether a person must take the conversation',
    // The check classification.ts runs when the reading above did not answer: the same 20 s clock, after the reading's.
    clock: { effort: 'medium', waitMs: 20_000, measured: '12 Nov 2026 run evaleff1292fbdc2, 8 recorded messages, all three arms 8 of 8 the same: low p50 7.9 s, p95 10.3 s; medium p50 14.0 s, p95 18.0 s; high p50 16.6 s, p95 24.6 s, 2 of 8 over 20 s' } },
  'marketing_social.needs_a_person': { consequence: 'decides', provenLow: false, why: 'whether a person must take the comment' },
  // The two intake readings run inside the customer's chat turn: what is left of the 24 s turn less its 2.5 s reserve
  // (inquiry_intake/turn_clock.ts), inside the portal's 30 s wait. Medium does not fit either (32.9-46.3 s); a cut reading
  // fills nothing and the customer's recorded answers are used instead of asking again (handle.ts, ruling 1631).
  'inquiry_intake.trade': { consequence: 'decides', provenLow: false, why: 'which trade the job is: it decides the match',
    clock: { effort: 'low', waitMs: 21_500, measured: '11 Nov 2026 runs evalefffe3428a49, evaleff0db35eb5c: low 12 of 12 answered, p50 13.2 s, p95 15.4 s; medium p50 31.9 s, p95 37.2 s; high 4 of 12 answered, 32.8-45.8 s' } },
  'inquiry_intake.exact_spec': { consequence: 'decides', provenLow: false, why: 'which specs the customer stated: it fills the request',
    clock: { effort: 'low', waitMs: 21_500, measured: '11 Nov 2026 run evalefff2f6e4c90: low 7 of 7 inside, 16.0-18.9 s (p50 17.9 s, p95 18.9 s); medium 32.9-46.3 s; high 0 of 22 inside the clock' } },
  'wa_inbound.status_lane': { consequence: 'conversation', provenLow: false, why: 'a status answer the customer reads' },
  // The intake chat turn's two reply-writing steps, after the interview call and before the turn's one end (turn_clock.ts
  // REPLY_END_MS); each has at least REPLY_MIN_MS (15 s) below it. Measured with the 15 s deadline the turn gives them
  // (scripts/eval/effort_low_vs_high/held_reply.ts): the held reply at medium answered 0 of 8 inside it (production 9-12 Nov,
  // medium: 16 of 38 cut at 16.7-17.1 s).
  'inquiry_intake.held_reply': { consequence: 'conversation', provenLow: false, why: 'the held request\'s reply, naming the questions still open',
    clock: { effort: 'low', waitMs: 15_000, measured: '12 Nov 2026 run evalheldb26f2d3d, 8 recorded portal conversations: low 8 of 8 model calls answered, p50 11.5 s, p95 14.5 s (the routine, with the eval\'s spend read before each call: p50 13.8 s, p95 17.4 s); medium 0 of 8 inside 15 s, every call cut at 16.2-16.8 s' } },
  'inquiry_intake.voice': { consequence: 'conversation', provenLow: false, why: 'the code-decided sentence of the turn, in the model\'s words',
    clock: { effort: 'low', waitMs: 15_000, measured: '12 Nov 2026 run evalheldb26f2d3d, 8 recorded portal conversations: low model calls p50 3.4 s, p95 6.6 s (8 of 8 answered; the routine p50 5.2 s, p95 9.0 s); medium 5.4-15.7 s' } },
  // ruling 1635: which open case a new message continues, or a new case (support_case_memory.ts). Medium, as asked.
  'support.case_match': { consequence: 'sorting', provenLow: false, why: 'which of the person\'s open cases a message continues' },
});

const EFFORTS = new Set(['low', 'medium', 'high']);
const valid = (e: unknown): e is PolicyEffort => EFFORTS.has(String(e));

/** The effort for one task class (unknown: high). */
export function classEffort(taskClass: string | null | undefined): PolicyEffort {
  return EFFORT_BY_CLASS[String(taskClass ?? '')] ?? UNKNOWN_CLASS_EFFORT;
}

/** The effort a think() surface asks for. On a person's clock, the effort measured to fit it (ledger 1642); otherwise sorting
 *  is low only where proven, and the consequence decides. */
export function surfaceEffort(surface: string): PolicyEffort {
  const s = SURFACES[surface];
  if (!s) return UNKNOWN_CLASS_EFFORT;
  if (s.clock) return s.clock.effort;
  if (s.consequence === 'decides') return 'high';
  if (s.consequence === 'sorting' && s.provenLow) return 'low';
  return 'medium';
}

/** What the gateway sends. A caller's explicit effort stands, except that a 'low' on a class that decides is raised: a
 *  decision is never made at low effort, whoever asks (ruling 1630). No effort named: the class's. */
export function effortFor(taskClass: string | null | undefined, callerEffort?: string | null): PolicyEffort {
  const own = classEffort(taskClass);
  if (!valid(callerEffort)) return own;
  if (callerEffort === 'low' && CONSEQUENCE_OF_CLASS[String(taskClass ?? '')] === 'decides') return own;
  return callerEffort;
}

// ── A CONVERSATION THAT IS NOT STRAIGHTFORWARD (ruling 1630) ─────────────────────────────────────────────────────────
// A cheap rule, no model: the signals that a reply needs deeper thinking. A false positive costs some seconds of thinking
// (the founder accepts 30-40 s); a false negative is answered at medium as every turn was before.
const COMPLAINT = /\b(complain\w*|unhappy|disappoint\w*|not happy|terrible|awful|unacceptable|frustrat\w*|angry|scam\w*|fraud\w*|cheat\w*|mistake|incorrect|wrong|still waiting|never (got|received|arrived|responded|replied|answered)|no ?one (has )?(responded|replied|answered|called)|did ?n[o']?t (get|receive|arrive|respond|reply)|escalat\w*|manager)\b|شكو|اشتكي|غير راض|زعلان|خطأ|غلط|نصب|احتيال|مدير|ما رد|لم يرد|ما وصل|لم يصل/i;
const DISPUTE = /\b(disput\w*|chargeback|lawyer|legal action|court|sue|breach)\b|نزاع|اعتراض|محامي|محكمة|قضية/i;
const REFUND = /\b(refund\w*|money back|reimburs\w*|repay\w*)\b|استرداد|استرجاع|ارجاع (المبلغ|الفلوس)|رجعوا|فلوسي/i;
const PRICE = /\b(too (expensive|high|much)|over ?charg\w*|cheaper|better price|lower price|discount|why (is|does) it cost|you quoted|quoted (me )?(the )?wrong|wrong (price|quote|quotation|amount))\b|غالي|مرتفع|ارخص|أرخص|خصم|تخفيض/i;

export type DepthReason = 'complaint' | 'dispute' | 'refund' | 'price_challenge' | 'multi_part' | 'redraft' | 'flagged';

/** Why this turn deserves the deeper thinking, or null when it is straightforward. */
export function depthReason(message: string, o: { priorProblems?: readonly string[] | null; flagged?: boolean } = {}): DepthReason | null {
  const m = String(message ?? '');
  if (o.priorProblems?.some((p) => String(p || '').trim())) return 'redraft';   // the medium draft failed the reply checks
  if (o.flagged) return 'flagged';                                                // a classifier or reviewer already flagged it
  if (DISPUTE.test(m)) return 'dispute';
  if (REFUND.test(m)) return 'refund';
  if (PRICE.test(m)) return 'price_challenge';
  if (COMPLAINT.test(m)) return 'complaint';
  const questions = (m.match(/[?؟]/g) ?? []).length;
  const listed = (m.match(/^\s*(\d+[.)]|[-*•])\s+\S/gm) ?? []).length;
  if (questions >= 2 || listed >= 2 || (m.length > 600 && questions >= 1)) return 'multi_part';
  return null;
}

/** A conversation turn's effort: medium, or high when it is not straightforward. */
export function conversationEffort(message: string, o: { priorProblems?: readonly string[] | null; flagged?: boolean } = {}): PolicyEffort {
  return depthReason(message, o) ? 'high' : 'medium';
}
