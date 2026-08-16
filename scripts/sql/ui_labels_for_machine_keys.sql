-- ---------------------------------------------------------------------------------------------
-- THE FOUNDER IS SHOWN MACHINE KEYS AND ASKED TO DECIDE.
--
-- On the OS home screen, 16 Aug 2026, his decision queue reads:
--     Core legal documents missing            legal · legal flag
--     Auth hardening review                   security · security incident
--     Customer reveal_no_response: ...        followup · customer escalation
-- and the notification bell reads "Resilience Alert", "Ops Alert", "Exception Alert".
--
-- Those are `agent_actions.kind` and `notifications.type` with the underscores taken out. There is
-- no human label anywhere in the payload, so every reader invents its own cosmetic transform and
-- they all still print the developer's vocabulary. A front-end string replace would fix one screen
-- and leave the bell, the escalations page, the WhatsApp digest and the founder email unchanged.
--
-- One table, one function, and each payload carries the label beside the key.
--
-- THE FALLBACK IS THE POINT. fn_ui_label NEVER returns null and never returns empty: an unlabelled
-- key is humanised (initcap, underscores to spaces) rather than dropped. This is deliberate - a
-- previous defect here was an allow-list plus a deny-list that between them covered 22 of 46 kinds
-- and left 24 silently unselectable by either reader. A third answer must always exist.
-- v_ui_label_missing then makes the gap visible instead of silent: it lists every key in live use
-- with no row in ui_label, so a new kind shows up as work to do rather than as a passable guess.
--
-- Counts at authoring time: 46 distinct agent_actions.kind, 39 distinct notifications.type.
-- Every one of those 85 is labelled below.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.ui_label (
  domain     text not null check (domain in ('action_kind', 'notification_type')),
  key        text not null,
  label      text not null check (btrim(label) <> ''),
  updated_at timestamptz not null default now(),
  primary key (domain, key)
);

alter table public.ui_label enable row level security;
revoke all on public.ui_label from anon, authenticated;

comment on table public.ui_label is
  'Human labels for machine keys shown to the founder. Read through fn_ui_label(), never directly '
  'by a renderer - the fallback lives in the function so no surface can print a bare key.';

create or replace function public.fn_ui_label(p_domain text, p_key text)
 returns text
 language sql
 stable
 set search_path to 'public', 'pg_catalog'
as $function$
  select coalesce(
           (select l.label from public.ui_label l
             where l.domain = p_domain and l.key = p_key),
           -- No row: humanise rather than blank. 'supplier_risk_complaints' -> 'Supplier Risk
           -- Complaints'. Worse than a written label, better than showing the founder a key, and
           -- v_ui_label_missing reports that it happened.
           nullif(initcap(replace(coalesce(p_key, ''), '_', ' ')), ''),
           'Unlabelled');
$function$;

-- Which keys are in live use with no written label. Empty is the goal; non-empty is a work list,
-- not a failure - the fallback is already rendering something readable for each of them.
create or replace view public.v_ui_label_missing as
  select 'action_kind' as domain, a.kind as key, count(*) as rows_in_use
    from public.agent_actions a
    left join public.ui_label l on l.domain = 'action_kind' and l.key = a.kind
   where l.key is null and a.kind is not null
   group by a.kind
  union all
  select 'notification_type', n.type, count(*)
    from public.notifications n
    left join public.ui_label l on l.domain = 'notification_type' and l.key = n.type
   where l.key is null and n.type is not null
   group by n.type;

insert into public.ui_label (domain, key, label) values
  -- agent_actions.kind — what the founder is being asked to look at
  ('action_kind', 'security_alert',                 'Security alert'),
  ('action_kind', 'incident',                       'Incident'),
  ('action_kind', 'handoff',                        'Work handed to another employee'),
  ('action_kind', 'supplier_risk_complaints',       'Supplier risk: complaints'),
  ('action_kind', 'supplier_risk_response_delays',  'Supplier risk: slow to respond'),
  ('action_kind', 'supplier_risk_performance_drops','Supplier risk: performance dropped'),
  ('action_kind', 'supplier_risk',                  'Supplier risk'),
  ('action_kind', 'licence_expiring',               'Trade licence expiring'),
  ('action_kind', 'knowledge_task',                 'Knowledge base update'),
  ('action_kind', 'strategy_rec',                   'Strategy recommendation'),
  ('action_kind', 'ai_improvement',                 'AI improvement proposal'),
  ('action_kind', 'marketing_recommendation',       'Marketing recommendation'),
  ('action_kind', 'ops_recommendation',             'Operations recommendation'),
  ('action_kind', 'report_recommendation',          'Reporting recommendation'),
  ('action_kind', 'hot_lead',                       'Hot lead'),
  ('action_kind', 'sla_review',                     'Service level review'),
  ('action_kind', 'sla_no_supply',                  'Service level missed: no supplier available'),
  ('action_kind', 'improvement_question',           'Question about an improvement'),
  ('action_kind', 'exec_briefing',                  'Executive briefing'),
  ('action_kind', 'coverage_gap',                   'Coverage gap'),
  ('action_kind', 'customer_escalation',            'Customer escalation'),
  ('action_kind', 'finance_alert',                  'Finance alert'),
  ('action_kind', 'finance_marketing_budget',       'Marketing budget decision'),
  ('action_kind', 'objective_step',                 'Objective step'),
  ('action_kind', 'supply_gap',                     'Supply gap'),
  ('action_kind', 'supply_health',                  'Supply health'),
  ('action_kind', 'delete_proposal',                'Proposal to delete something'),
  ('action_kind', 'compliance_update',              'Compliance update'),
  ('action_kind', 'doc_task',                       'Document task'),
  ('action_kind', 'report_task',                    'Report to produce'),
  ('action_kind', 'legal_flag',                     'Legal issue raised'),
  ('action_kind', 'content_review',                 'Content awaiting review'),
  ('action_kind', 'bd_batch',                       'Business development batch'),
  ('action_kind', 'agent_created',                  'New AI employee created'),
  ('action_kind', 'security_incident',              'Security incident'),
  ('action_kind', 'backup_alert',                   'Backup alert'),
  ('action_kind', 'prompt_approval',                'AI instruction change awaiting approval'),
  ('action_kind', 'autonomy_stall',                 'An employee stopped and needs a decision'),
  ('action_kind', 'inbound_review',                 'Inbound message awaiting review'),
  ('action_kind', 'invite_campaign_week',           'Supplier invitation campaign'),
  ('action_kind', 'approve_supplier',               'Supplier awaiting your approval'),
  ('action_kind', 'decision.route_category',        'Category routing decision'),
  ('action_kind', 'supplier_onboard_extract',       'Supplier onboarding details extracted'),
  ('action_kind', 'category_knowledge',             'Category knowledge update'),
  ('action_kind', 'ai_quality_alert',               'AI quality alert'),
  ('action_kind', 'simulation_apply',               'Simulation result to apply'),
  ('action_kind', 'action_gate',                    'Decision held at a policy gate'),

  -- notifications.type — what the bell is telling him
  ('notification_type', 'founder_alert',            'Needs your attention'),
  ('notification_type', 'founder_brief',            'Your briefing'),
  ('notification_type', 'supplier_invite',          'Supplier invitation sent'),
  ('notification_type', 'supplier_registered',      'Supplier registered'),
  ('notification_type', 'supplier_enablement',      'Supplier enablement'),
  ('notification_type', 'registration_received',    'Registration received'),
  ('notification_type', 'invite_paused_bounce',     'Invitations paused: address bounced'),
  ('notification_type', 'resilience_alert',         'System resilience alert'),
  ('notification_type', 'agent_silence',            'An AI employee has gone quiet'),
  ('notification_type', 'ops_alert',                'Operations alert'),
  ('notification_type', 'smoke_alert',              'Automated checks failed'),
  ('notification_type', 'exception_alert',          'Something went wrong'),
  ('notification_type', 'health_alert',             'System health alert'),
  ('notification_type', 'uptime_alert',             'Site availability alert'),
  ('notification_type', 'backup_alert',             'Backup alert'),
  ('notification_type', 'qa_fail',                  'Quality check failed'),
  ('notification_type', 'llm_drift',                'AI behaviour drifted'),
  ('notification_type', 'ai_quality_alert',         'AI quality alert'),
  ('notification_type', 'policy_inconsistency',     'Two policies disagree'),
  ('notification_type', 'money_test_fail',          'Payment safety check failed'),
  ('notification_type', 'expense_logged',           'Expense logged'),
  ('notification_type', 'cost_snapshot',            'Cost snapshot'),
  ('notification_type', 'finance_reminder',         'Finance reminder'),
  ('notification_type', 'cfo_report',               'Finance report'),
  ('notification_type', 'board_report',             'Board report'),
  ('notification_type', 'period_report',            'Period report'),
  ('notification_type', 'weekly_learnings',         'What the company learned this week'),
  ('notification_type', 'chief_of_staff',           'From your Chief of Staff'),
  ('notification_type', 'pending_digest',           'Waiting on you: digest'),
  ('notification_type', 'doc_request',              'Document requested'),
  ('notification_type', 'doc_expiry',               'Document expiring'),
  ('notification_type', 'wa_escalation',            'Escalated over WhatsApp'),
  ('notification_type', 'force_dispatch_used',      'A dispatch was forced through'),
  ('notification_type', 'force_dispatch_refused',   'A forced dispatch was refused'),
  ('notification_type', 'reveal_no_response_notice','Customer revealed a supplier and heard nothing back'),
  ('notification_type', 'supply_health',            'Supply health'),
  ('notification_type', 'agent_created',            'New AI employee created')
on conflict (domain, key) do update set label = excluded.label, updated_at = now();
