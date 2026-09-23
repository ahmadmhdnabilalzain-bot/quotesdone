// reasoned_routing — the routing and CEO decisions that SQL used to take by spotting words, now reasoned.
// Seats: ceo (escalation, refund exclusion, task ownership) and sales_engineer (supplier documents, repeat
// inquiries). 23 Sep 2026, founder_instruction 886-903 (ledger 890: no word matching anywhere).
//
// WHERE THE REASONING HAPPENS. Every one of these decisions is taken inside a SQL routine that no edge
// function calls (fn_decide, fn_ceo_refund_checklist, fn_task_review, fn_supplier_document_home and the
// inquiry trigger — measured 23 Sep 2026, grep of supabase/functions). So the SQL files the question itself
// (public.fn_reason_route_ask, scripts/sql/routing_and_ceo_decisions_are_reasoned_not_word_matched.sql)
// into the owning seat's queue with exactly the request built below, replayHeld (think.ts, run by
// resilience_ping) reasons it the moment a model may run, and fn_reason_held_resolve hands the answer to the
// surface's own fn_reason_apply_<surface>. The SQL reads the reasoned answer by its dedupe key
// (fn_reason_route_answer) and never reads the free text for meaning again.
//
// These functions are the same decisions for a TS caller, and the one place the option ids are defined:
// reasoned_routing.test.ts fails when the SQL's option ids drift from these.
//
// UNDER THE HOLD every one returns value null with the question filed; the SQL treats an unanswered question
// as "waiting" (the escalation is not decided, the refund is neither approved nor declined, the document
// fills no slot, the task's owner is not recorded) — never a keyword guess.
import { think, type ThinkDeps } from './think.ts';
import type { Reasoned } from './reasoned_decisions.ts';

type Opt = { id: string; meaning: string };
const pick = async (deps: ThinkDeps, seat: 'ceo' | 'sales_engineer', surface: string, question: string, options: Opt[],
  dedupeKey: string, subject: Record<string, unknown>): Promise<Reasoned<string>> => {
  const result = await think(deps, { seat, surface, question: question.slice(0, 8000), dedupeKey, subject, context: { audience: 'internal' },
    decision: { name: surface, options } });
  return { value: result.status === 'answered' ? result.decision?.choice ?? null : null, result };
};

// ── ceo.escalation_meaning (sql.fn_should_escalate, sql.fn_decide) ───────────────────────────────
export const ESCALATION_LEGAL = 'legal_matter';
export const ESCALATION_NEITHER = 'neither';
export const ESCALATION_REPEAT = 'repeats_failure_';   // + institutional_memory.id
export function escalationOptions(legalTriggers: string[], candidates: { id: number; headline: string }[]): Opt[] {
  return [
    { id: ESCALATION_LEGAL, meaning: 'the matter itself carries a legal exposure for the company — for example ' + legalTriggers.join(', ') + ' — however it is worded, in any language; merely mentioning such a word as a topic is not enough' },
    ...candidates.map((c) => ({ id: ESCALATION_REPEAT + c.id, meaning: 'it repeats this earlier attempt, which ended worse: ' + c.headline })),
    { id: ESCALATION_NEITHER, meaning: 'neither a legal exposure nor a repeat of an attempt that ended worse' },
  ];
}
export function escalationMeaning(deps: ThinkDeps, o: { text: string; kind: string; actor: string; legalTriggers: string[]; candidates: { id: number; headline: string }[]; dedupeKey: string }) {
  return pick(deps, 'ceo', 'ceo.escalation_meaning', o.text, escalationOptions(o.legalTriggers, o.candidates), o.dedupeKey, { kind: o.kind, actor: o.actor });
}

// ── ceo.refund_off_platform (sql.fn_ceo_refund_checklist) ─────────────────────────────────────────
export const REFUND_OFF_PLATFORM: Opt[] = [
  { id: 'engaged_off_platform', meaning: 'the note records that the customer dealt with or hired the supplier outside QuotesDone' },
  { id: 'not_off_platform', meaning: 'the note does not record any dealing with the supplier outside QuotesDone' },
];
export function refundOffPlatform(deps: ThinkDeps, o: { transactionId: string; refundId: number | null; note: string; dedupeKey: string }) {
  return pick(deps, 'ceo', 'ceo.refund_off_platform', o.note, REFUND_OFF_PLATFORM, o.dedupeKey, { transaction_id: o.transactionId, refund_id: o.refundId });
}

// ── supplier_documents.subject (sql.fn_supplier_document_home) ───────────────────────────────────
export const DOCUMENT_SUBJECT: Opt[] = [
  { id: 'iso', meaning: 'an ISO management-system certificate (ISO 9001, 14001, 45001 ...)' },
  { id: 'insurance', meaning: 'an insurance policy or certificate (public liability, contractor all-risk, workmen compensation ...)' },
  { id: 'manufacturer_auth', meaning: 'a manufacturer, brand or distributor authorisation / agency letter' },
  { id: 'none', meaning: 'any other document' },
];
export function supplierDocumentSubject(deps: ThinkDeps, o: { documentId: number; leadId: number; label: string; kind: string; dedupeKey: string }) {
  return pick(deps, 'sales_engineer', 'supplier_documents.subject', `A supplier uploaded a company document and labelled it: "${o.label}" (the type they chose: ${o.kind}). Which document is it?`,
    DOCUMENT_SUBJECT, o.dedupeKey, { document_id: o.documentId, lead_id: o.leadId });
}

// ── inquiry.same_request (sql.trg_inquiry_enrich) ────────────────────────────────────────────────
export const SAME_REQUEST: Opt[] = [
  { id: 'same_request', meaning: 'the new request asks for the same job as the earlier one, however differently it is worded' },
  { id: 'different_request', meaning: 'the new request is a different job' },
];
export function sameInquiry(deps: ThinkDeps, o: { inquiryId: string; earlierId: string; earlier: string; current: string; dedupeKey: string }) {
  return pick(deps, 'sales_engineer', 'inquiry.same_request', `Earlier request: ${o.earlier}\nNew request: ${o.current}`, SAME_REQUEST, o.dedupeKey,
    { inquiry_id: o.inquiryId, earlier_id: o.earlierId });
}

// ── ceo.task_responsibility and ceo.task_collaboration_rule (sql.fn_task_review) ──────────────────
export const TASK_RESPONSIBILITY_NONE = 'none';
export function taskResponsibilityOptions(rows: { responsibility: string; os_key: string }[]): Opt[] {
  return [...rows.map((r) => ({ id: r.responsibility, meaning: `the work is ${r.responsibility.replace(/_/g, ' ')} (owned by the ${r.os_key} operating system)` })),
    { id: TASK_RESPONSIBILITY_NONE, meaning: 'none of these responsibilities is what the work is' }];
}
export function taskResponsibility(deps: ThinkDeps, o: { taskId: number; deptKey: string; author: string; text: string; rows: { responsibility: string; os_key: string }[]; dedupeKey: string }) {
  return pick(deps, 'ceo', 'ceo.task_responsibility', o.text, taskResponsibilityOptions(o.rows), o.dedupeKey, { task_id: o.taskId, dept_key: o.deptKey, author: o.author });
}
export function collaborationRuleOptions(situation: string): Opt[] {
  return [
    { id: 'applies', meaning: 'the task is the situation this rule governs: ' + situation },
    { id: 'does_not_apply', meaning: 'the task is not that situation' },
  ];
}
export function taskCollaborationRule(deps: ThinkDeps, o: { taskId: number; ruleId: number; situation: string; text: string; dedupeKey: string }) {
  return pick(deps, 'ceo', 'ceo.task_collaboration_rule', o.text, collaborationRuleOptions(o.situation), o.dedupeKey, { task_id: o.taskId, rule_id: o.ruleId });
}
