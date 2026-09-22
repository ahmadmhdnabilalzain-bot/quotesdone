// THE 55 EXECUTORS WERE ALL STAMPED "HIGH RISK, IRREVERSIBLE, IDEMPOTENCY UNKNOWN".
//
// That was never a classification — it is the cautious factory default, identical on all 55, and
// its practical effect is that the AI company asks permission for everything and therefore does
// almost nothing on its own. 130 org_tasks have sat at 'proposed' for weeks because of it.
//
// FOUNDER'S GOVERNANCE RULE, 6 Aug 2026, implemented literally:
//   "the only approval is for refunds, nothing else need my approval ... if i wanna give a command
//    on the OS i should be able to do so and the agents/staff will take those orders, otherwise
//    the work as per the brief given and the targets we need to reach"
//
// So exactly ONE action carries required_authority: refund_within_window. Everything else runs
// within its own authority.
//
// THE OUTBOUND-EMAIL RISK IS SOLVED BY ENGINEERING, NOT BY AN APPROVAL GATE. The 20,464 leads are
// the invite campaign; the danger was never a stray email, it is a retry firing the whole list
// twice. idempotency_strategy is exactly the field for that and it was NULL on all 55 — so the
// registry could not say whether a retry was safe, and the honest answer was "nobody knows".
// outreach_send and invite are now external_id / natural_key: a repeat delivers nothing.
//
// risk_tier here means BLAST RADIUS, not "should a human look at it":
//   high   - reaches the outside world irreversibly (money out, mail sent, data erased)
//   medium - changes internal state a human would want explained
//   low    - reads, scores, drafts, reports; nothing leaves the building
// advisory_safe is set true only where risk_tier='low', which also clears the 24 rows that
// simultaneously claimed 'high' and 'advisory_safe' — a contradiction the gaps view flagged and
// nothing resolved.
//
//   node scripts/seed_executor_governance.mjs <staging-ref>
//   node scripts/seed_executor_governance.mjs --print-sql
import { mgmtRead, mgmtWrite, resolveStagingRef } from '../lib/qd_guard.mjs';

// action_class: [risk_tier, reversible, idempotency_strategy, owner_os, required_authority]
export const GOV = {
  // --- the only gated action -----------------------------------------------------------------
  refund_within_window: ['high', false, 'external_id', 'finance', 'founder'],

  // --- reaches a human or the outside world: autonomous, but MUST be replay-safe --------------
  outreach_send: ['high', false, 'external_id', 'commercial', null],  // the invite campaign
  invite: ['high', false, 'natural_key', 'marketplace', null],        // one invite per lead, ever
  pdpl_action: ['high', false, 'natural_key', 'legal_gov', null],     // erasure: gating it misses statutory deadlines
  collections_chase: ['medium', false, 'natural_key', 'finance', null],
  nudge: ['medium', false, 'natural_key', 'operations', null],
  escalate_founder: ['low', false, 'natural_key', 'leadership', null],

  // --- finance: records and analysis, no money moves ------------------------------------------
  dispute_open: ['medium', true, 'natural_key', 'finance', null],
  expense_log: ['low', true, 'request_hash', 'finance', null],
  invoice_review: ['low', true, 'request_hash', 'finance', null],
  ap_duplicate_scan: ['low', true, 'none_read_only', 'finance', null],
  money_verify: ['low', true, 'none_read_only', 'finance', null],
  spend_check: ['low', true, 'none_read_only', 'finance', null],
  forecast: ['low', true, 'none_read_only', 'finance', null],

  // --- marketplace: the revenue path ----------------------------------------------------------
  match_inquiry: ['low', true, 'request_hash', 'marketplace', null],
  route_category: ['low', true, 'request_hash', 'marketplace', null],
  qualify_inquiry: ['low', true, 'request_hash', 'marketplace', null],
  compare_quotes: ['low', true, 'request_hash', 'marketplace', null],
  capability_enrich: ['low', true, 'upsert_on_conflict', 'marketplace', null],
  supplier_approve_clean: ['medium', true, 'natural_key', 'marketplace', null],
  supplier_verify: ['medium', true, 'natural_key', 'marketplace', null],

  // --- commercial: drafts and plans; nothing here sends ---------------------------------------
  content_draft: ['low', true, 'request_hash', 'commercial', null],
  content_revise: ['low', true, 'request_hash', 'commercial', null],
  content_calendar: ['low', true, 'upsert_on_conflict', 'commercial', null],
  seo_produce: ['low', true, 'request_hash', 'commercial', null],
  outreach_draft: ['low', true, 'request_hash', 'commercial', null],
  boost_recommend: ['low', true, 'none_read_only', 'commercial', null],

  // --- knowledge --------------------------------------------------------------------------------
  knowledge_acquire: ['low', true, 'upsert_on_conflict', 'knowledge', null],
  knowledge_fill: ['low', true, 'upsert_on_conflict', 'knowledge', null],
  knowledge_fill_gap: ['low', true, 'upsert_on_conflict', 'knowledge', null],
  capability_exam: ['low', true, 'request_hash', 'knowledge', null],
  qa_gate: ['low', true, 'none_read_only', 'knowledge', null],

  // --- technology --------------------------------------------------------------------------------
  event_dispatch: ['low', true, 'natural_key', 'technology', null],   // the bus must not double-deliver
  code_selfheal: ['medium', true, 'natural_key', 'technology', null],
  incident_fix: ['medium', true, 'natural_key', 'technology', null],
  health_report: ['low', true, 'none_read_only', 'technology', null],
  uptime_verify: ['low', true, 'none_read_only', 'technology', null],
  security_review: ['low', true, 'none_read_only', 'technology', null],
  secops_pattern_test: ['low', true, 'none_read_only', 'technology', null],

  // --- legal & governance -------------------------------------------------------------------------
  legal_review: ['low', true, 'request_hash', 'legal_gov', null],
  compliance_check: ['low', true, 'natural_key', 'legal_gov', null],
  brand_scan: ['low', true, 'none_read_only', 'legal_gov', null],

  // --- leadership / intelligence / evolution --------------------------------------------------------
  coordinate: ['medium', true, 'natural_key', 'leadership', null],
  exec_review: ['low', true, 'none_read_only', 'leadership', null],
  review_submit: ['low', true, 'natural_key', 'leadership', null],
  bi_snapshot: ['low', true, 'upsert_on_conflict', 'intelligence', null],
  metric_alerts: ['low', true, 'natural_key', 'intelligence', null],
  growth_simulate: ['low', true, 'none_read_only', 'intelligence', null],
  recommend: ['low', true, 'none_read_only', 'intelligence', null],
  evolution_scan: ['low', true, 'none_read_only', 'evolution', null],
  idea_submit: ['low', true, 'natural_key', 'evolution', null],

  // --- operations / people ---------------------------------------------------------------------------
  capability_review: ['low', true, 'none_read_only', 'operations', null],
  role_define: ['medium', true, 'natural_key', 'operations', null],
  self_review: ['low', true, 'natural_key', 'operations', null],
  resolve_within_policy: ['medium', true, 'request_hash', 'operations', null],
};

const q = (v) => (v === null ? 'null' : `'${String(v).replace(/'/g, "''")}'`);
const rows = Object.entries(GOV)
  .map(([k, [risk, rev, idem, os, auth]]) =>
    `(${q(k)}, ${q(risk)}, ${rev}, ${q(idem)}, ${q(os)}, ${auth === null ? 'null::text' : q(auth)})`)
  .join(',\n    ');

export const SQL = `update public.org_action_executor e set
    risk_tier = v.risk_tier,
    reversible = v.reversible,
    idempotency_strategy = v.idem,
    owner_os = v.owner_os,
    required_authority = v.required_authority,
    advisory_safe = (v.risk_tier = 'low')
  from (values\n    ${rows}\n  ) as v(action_class, risk_tier, reversible, idem, owner_os, required_authority)
  where e.action_class = v.action_class;`;

// THE VIEW'S FOURTH CONDITION HAD NEVER ONCE FIRED, AND CLASSIFYING IS WHAT WOKE IT.
// v_executor_registry_gaps flags `reversible AND compensation_action_class IS NULL` — "you say this
// can be undone; by what?". While all 55 rows said reversible=false that branch was structurally
// unreachable and its 0 was vacuous, exactly like the two dead branches in demo_factory's teardown.
// Marking 48 rows honestly reversible made it fire for the first time, which is the gate working,
// not a regression. Answered per row rather than silenced: a pure read changes nothing so nothing
// needs reversing, and everything else is undone by a person, because no automated inverse exists
// in this registry today. 'manual_reversal' is a true statement about the company; inventing an
// inverse action_class that nothing implements would not be.
export const COMPENSATION_SQL = `update public.org_action_executor set compensation_action_class =
    case when idempotency_strategy = 'none_read_only' then 'none_required_read_only'
         else 'manual_reversal' end
  where active and reversible and compensation_action_class is null;`;

if (process.argv.includes('--print-sql')) { console.log(SQL + '\n\n' + COMPENSATION_SQL); process.exit(0); }

const REF = resolveStagingRef(process.argv[2]);
console.log(`classifying ${Object.keys(GOV).length} executor(s) on ${REF}`);
await mgmtWrite(REF, SQL, 'seed executor governance');
await mgmtWrite(REF, COMPENSATION_SQL, 'seed executor compensation');

const m = (await mgmtRead(REF, `
  select count(*)::int total,
         count(*) filter (where idempotency_strategy is null)::int idem_null,
         count(*) filter (where owner_os is null)::int os_null,
         count(*) filter (where required_authority is not null)::int gated,
         count(*) filter (where risk_tier='high' and coalesce(advisory_safe,false))::int contradictions,
         count(*) filter (where risk_tier='high')::int high,
         count(*) filter (where risk_tier='medium')::int medium,
         count(*) filter (where risk_tier='low')::int low
    from public.org_action_executor where active`))[0];
const gaps = (await mgmtRead(REF, `select count(*)::int n from public.v_executor_registry_gaps`))[0].n;
const gatedList = (await mgmtRead(REF,
  `select string_agg(action_class, ', ' order by action_class) s from public.org_action_executor
    where active and required_authority is not null`))[0].s;

console.log(`\nrisk: ${m.high} high / ${m.medium} medium / ${m.low} low  (of ${m.total})`);
console.log(`idempotency undeclared: ${m.idem_null}   owner_os undeclared: ${m.os_null}`);
console.log(`high-risk-but-advisory-safe contradictions: ${m.contradictions}`);
console.log(`requires founder approval: ${m.gated} -> ${gatedList || 'none'}`);
console.log(`v_executor_registry_gaps: ${gaps} row(s)`);

const ok = m.idem_null === 0 && m.os_null === 0 && m.contradictions === 0
  && m.gated === 1 && gatedList === 'refund_within_window' && gaps === 0;
console.log(ok
  ? `\nOK - every executor classified; refunds alone require approval; the gaps view is genuinely empty`
  : `\nINCOMPLETE - see the counters above`);
process.exitCode = ok ? 0 : 1;
