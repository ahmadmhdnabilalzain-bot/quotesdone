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

/** The think() decisions and lanes that set their own effort. `provenLow` is flipped only by a passed side-by-side
 *  (scripts/eval/effort_low_vs_high.mjs writes the verdict; the flip is a reviewed one-line change here). */
export const SURFACES: Readonly<Record<string, { consequence: Consequence; provenLow: boolean; why: string }>> = Object.freeze({
  // whatsappReadings asks three things in this one call: the intent, the menu option AND whether a person is needed. The
  // last is an escalation decision, so the call is not "simple sorting" and stays high whatever a side-by-side shows.
  'wa_inbound.intent_table': { consequence: 'decides', provenLow: false, why: 'the intent, the menu option and whether a person is needed, in one call' },
  'wa_inbound.greeting_state': { consequence: 'sorting', provenLow: false, why: 'which menu option a reply picks' },
  'wa_inbound.problem_state': { consequence: 'sorting', provenLow: false, why: 'which menu option a reply picks' },
  'wa_inbound.needs_a_person': { consequence: 'decides', provenLow: false, why: 'whether a person must take the conversation' },
  'marketing_social.needs_a_person': { consequence: 'decides', provenLow: false, why: 'whether a person must take the comment' },
  'inquiry_intake.trade': { consequence: 'decides', provenLow: false, why: 'which trade the job is: it decides the match' },
  'inquiry_intake.exact_spec': { consequence: 'decides', provenLow: false, why: 'which specs the customer stated: it fills the request' },
  'wa_inbound.status_lane': { consequence: 'conversation', provenLow: false, why: 'a status answer the customer reads' },
  // ruling 1635: which open case a new message continues, or a new case (support_case_memory.ts). Medium, as asked.
  'support.case_match': { consequence: 'sorting', provenLow: false, why: 'which of the person\'s open cases a message continues' },
});

const EFFORTS = new Set(['low', 'medium', 'high']);
const valid = (e: unknown): e is PolicyEffort => EFFORTS.has(String(e));

/** The effort for one task class (unknown: high). */
export function classEffort(taskClass: string | null | undefined): PolicyEffort {
  return EFFORT_BY_CLASS[String(taskClass ?? '')] ?? UNKNOWN_CLASS_EFFORT;
}

/** The effort a think() surface asks for. Sorting is low only where proven; otherwise its consequence decides. */
export function surfaceEffort(surface: string): PolicyEffort {
  const s = SURFACES[surface];
  if (!s) return UNKNOWN_CLASS_EFFORT;
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
