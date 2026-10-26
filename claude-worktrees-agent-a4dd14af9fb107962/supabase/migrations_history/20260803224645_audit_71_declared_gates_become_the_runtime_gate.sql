-- AUDIT 7.1. The declared hard gates become the runtime gate.
--
-- WHAT WAS WRONG. Two authority models, and the one that ran decided by REGEX OVER THE CLASS NAME:
--
--   if p_action_class ~* 'money|payout|payment|gl_|...|ban' then v_cap := 'gated';
--
-- Measured on the live table, that regex fires on 37 of 153 rows and CHANGES THE ANSWER ON EXACTLY
-- ONE - it/code_deploy, supervised -> gated. The other 36 were already gated. It is not a cap, it is
-- a coincidence. `refund_within_window` contains none of those words, so a refund - money leaving the
-- account - escaped the money cap by not spelling "money".
--
-- Meanwhile fn_ops_authority_check, which reads the ten hard gates the company actually wrote down,
-- had ZERO callers: no edge function, no cron, no other database function. It was also unable to
-- work even if called, because it matched a gate with
--     where raw->>'action_class' = p_action_class
-- and the ten gate names (money_move, production_deploy, ...) are a different vocabulary from the
-- 153 operational classes (refund_within_window, code_selfheal, ...). Nothing could ever match. The
-- missing piece was never the checker; it was the MAPPING between the two vocabularies.
--
-- WHAT THIS DOES.
--   1. public.action_class_gate - the mapping, one reviewed row per operational class. A NULL gate
--      is an explicit "no hard gate applies", with a rationale, not an absence.
--   2. fn_ops_authority_check resolves the gate through that mapping, and REFUSES AUTONOMY TO ANY
--      CLASS THAT HAS NO ROW. Unreviewed can no longer mean unrestricted - that is the whole point
--      of "declared gates win".
--   3. A gate that declares a threshold is honoured when, and only when, the caller states the
--      amount. No amount = no proof it is under the ceiling = gated. This is what lets the founder's
--      AED 2,000 in-window refund authority survive being mapped to money_move.
--   4. fn_dept_authority - the one function anything actually calls (intent_router) - now delegates
--      here instead of running the regex. Its return shape is unchanged so the call site is untouched.
--   5. fn_event_dispatch stops hard-coding tier 'autonomous' and reads the model like everyone else.
--
-- SAFETY. Every change here is in the restrictive direction: classes move from autonomous to gated,
-- never the reverse. agent_autonomy_enabled is 'false' and cos_execute_hourly is disabled, so nothing
-- is executing autonomously today in any case. Reverting is an UPDATE to action_class_gate.
set local app.change_reason = 'Audit 7.1: declare analysis as an explicit reviewed class so fn_event_dispatch can read a tier instead of hard-coding autonomous. Reading and summarising an event is not an action; anything it leads to is filed as its own class with its own gate.';

create table if not exists public.action_class_gate (
  action_class      text primary key,
  gate_action_class text,
  rationale         text not null,
  reviewed_on       date not null default current_date,
  reviewed_by       text not null default 'founder',
  constraint action_class_gate_known_gate check (
    gate_action_class is null or gate_action_class in (
      'ad_spend','authentication_identity','autonomy_framework','destructive_data',
      'legal_commitment','money_move','production_deploy','public_claim_publish',
      'secrets_security','supplier_enforcement'))
);
alter table public.action_class_gate enable row level security;
comment on table public.action_class_gate is
  'Maps an operational action_class to one of the ten declared hard gates, or to NULL meaning "reviewed, no hard gate applies". A class with NO ROW here can never be autonomous - fn_ops_authority_check refuses it. Unreviewed must not mean unrestricted.';

insert into public.action_class_gate (action_class, gate_action_class, rationale) values
  ('refund_within_window','money_move','A refund is money leaving the account. Autonomy applies only inside transactions.refund_deadline AND at or below org_authority.threshold_aed (AED 2,000, founder decision 4 Aug 2026); the caller must state the amount to claim it.'),
  ('content_publish','public_claim_publish','Publishes live to LinkedIn, X, Facebook and Instagram through Postiz. The gate names social content and advertising explicitly.'),
  ('content_calendar','public_claim_publish','Schedules the same publication. Scheduling a claim is publishing it later.'),
  ('code_selfheal','production_deploy','Promotes code to production via resilience_ping. The gate allows emergency self-heal only as supervised work inside an approved runbook.'),
  ('incident_fix','production_deploy','os_incidents can change production configuration in response to an incident.'),
  ('role_define','autonomy_framework','agent_autogen creates new agents. The gate covers changes to the ability of agents to act, which creating one plainly is.'),
  ('analysis',null,'Reading an event and writing a summary. Any action that follows is filed as its own class with its own gate.'),
  ('nudge',null,'A reminder to a party who already has a relationship with us. No state change.'),
  ('resolve_within_policy',null,'A support reply inside the published policy. Anything outside it is a different class.'),
  ('coordinate',null,'Routes existing work between departments; creates no external effect.'),
  ('initiative_create',null,'Creates internal tasks only. Each resulting task is gated on its own class.'),
  ('expense_log',null,'Records an expense already incurred. Recording is not committing - an actual payout is money_move and is a different class. FLAGGED FOR REVIEW: the money_move text does mention journal postings that change reported position.'),
  ('forecast',null,'Read-only projection.'),
  ('capability_review',null,'Reads agent performance data.'),
  ('intake_change',null,'Adjusts the questions customers are asked at intake. FLAGGED FOR REVIEW: shapes the customer experience without touching a declared gate.'),
  ('knowledge_acquire',null,'Adds material to the knowledge corpus, which is separately gated by the publish and lint pipeline.'),
  ('knowledge_fill',null,'Fills a declared knowledge gap through the same lint and convergence controls.'),
  ('content_draft',null,'The public_claim_publish gate states that agents may draft and flag; only publication is gated.'),
  ('invite',null,'Invites a supplier company to register. Subject to the outbound send caps.'),
  ('match_inquiry',null,'The core marketplace function. Matching is gated by fn_is_matchable, not by an authority tier.'),
  ('supplier_approve_clean',null,'Auto-approval of a clean supplier registration is an explicit founder setting (pricing_config.auto_approve_suppliers = true). FLAGGED FOR REVIEW: the authentication_identity gate names supplier identity changes.'),
  ('supplier_coaching',null,'Advice to a supplier on their own quote quality.'),
  ('outreach_draft',null,'Drafting only, as the gate allows.'),
  ('outreach_send',null,'Sends supplier outreach. Bounded by the outbound send caps rather than by a hard gate. FLAGGED FOR REVIEW.'),
  ('pipeline_review',null,'Reads the sales pipeline.')
on conflict (action_class) do nothing;

insert into public.org_authority (dept_key, action_class, max_tier, threshold_aed)
select distinct dept_key, 'analysis'::text, 'autonomous'::text, null::numeric from public.org_authority
on conflict do nothing;

create or replace function public.fn_ops_authority_check(
  p_dept_key text, p_action_class text, p_amount_aed numeric default null, p_risk text default null)
returns jsonb language plpgsql stable
as $function$
declare v_prod text; v_thresh numeric; v_map record; v_gate record; v_tier text; v_reason text;
begin
  select max_tier, threshold_aed into v_prod, v_thresh
    from public.org_authority where dept_key = p_dept_key and action_class = p_action_class;

  select * into v_map from public.action_class_gate where action_class = p_action_class;

  select * into v_gate from ops_kb_stage.hard_gates
   where raw->>'action_class' = coalesce(v_map.gate_action_class, p_action_class) limit 1;

  v_tier := coalesce(v_prod, 'gated');
  v_reason := case when v_prod is null
                   then 'no org_authority row for this department and action class - defaulting to gated'
                   else 'org_authority.max_tier' end;

  -- DECLARED GATES WIN. An action class nobody has reviewed cannot be autonomous. This is the rule
  -- that closes 7.1: previously an autonomous org_authority row with no matching gate sailed through,
  -- which is exactly how refund_within_window, content_publish, code_selfheal and role_define ran
  -- outside the gates that name them.
  if v_map.action_class is null and v_tier <> 'gated' then
    v_tier := 'gated';
    v_reason := 'action class "' || p_action_class || '" has no row in action_class_gate. Unreviewed is not unrestricted: '
             || 'map it to a hard gate, or to NULL with a stated rationale, before it can act on its own.';
  end if;

  if v_gate.record_id is not null and coalesce(v_gate.raw->>'default_tier','gated') = 'gated' and v_tier <> 'gated' then
    if v_thresh is not null and p_amount_aed is not null and p_amount_aed <= v_thresh then
      v_reason := format('hard gate "%s" applies but %s AED is within the delegated threshold of %s AED',
                         v_gate.title, p_amount_aed, v_thresh);
    else
      v_tier := 'gated';
      v_reason := 'hard gate "' || v_gate.title || '" overrides org_authority (a hard gate may only tighten, never widen)'
               || case when v_thresh is not null and p_amount_aed is null
                       then '; a delegated threshold of ' || v_thresh || ' AED exists but no amount was stated'
                       else '' end;
    end if;
  end if;

  if v_thresh is not null and p_amount_aed is not null and p_amount_aed > v_thresh then
    v_tier := 'gated';
    v_reason := format('amount %s AED exceeds the department threshold of %s AED', p_amount_aed, v_thresh);
  end if;

  if p_risk = 'critical' and v_tier = 'autonomous' then
    v_tier := 'gated';
    v_reason := 'risk_level=critical is never executed autonomously';
  end if;

  return jsonb_build_object(
    'department', p_dept_key, 'action_class', p_action_class,
    'effective_tier', v_tier,
    'may_act_autonomously', (v_tier = 'autonomous'),
    'requires_approval', (v_tier = 'gated'),
    'reviewed', (v_map.action_class is not null),
    'hard_gate', case when v_gate.record_id is null then null else jsonb_build_object(
        'title', v_gate.title, 'approval_role', v_gate.raw->>'approval_role',
        'threshold', v_gate.raw->>'threshold', 'rollback', v_gate.raw->>'rollback') end,
    'production_tier', v_prod, 'threshold_aed', v_thresh, 'reason', v_reason,
    'source', 'org_authority + action_class_gate + ops_kb_stage.hard_gates (deterministic, no model call)');
end $function$;

create or replace function public.fn_dept_authority(p_dept text, p_action_class text, p_amount_aed numeric default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_catalog'
as $function$
declare v jsonb;
begin
  v := public.fn_ops_authority_check(p_dept, p_action_class, p_amount_aed, null);
  return jsonb_build_object(
    'dept', p_dept,
    'action_class', p_action_class,
    'tier', v->>'effective_tier',
    'threshold_aed', (v->>'threshold_aed')::numeric,
    'capped', coalesce(v->>'production_tier', 'gated') is distinct from (v->>'effective_tier'),
    'reviewed', (v->>'reviewed')::boolean,
    'reason', v->>'reason');
end $function$;

create or replace function public.fn_event_dispatch(p_lookback_minutes integer default 1440)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_delivered integer := 0; v_tasks integer := 0; v_gated integer := 0;
        r record; v_task bigint; v_dept text; v_tier text;
begin
  for r in
    select e.id as event_id, e.event_type, e.entity_type, e.entity_id, e.actor, e.occurred_at, s.agent_key, s.reason
    from company_event e
    join event_subscription s on s.active and s.event_type = e.event_type
    left join event_delivery d on d.event_id = e.id and d.agent_key = s.agent_key
    where d.id is null
      and e.occurred_at > now() - make_interval(mins => greatest(p_lookback_minutes, 1))
      and s.agent_key <> coalesce(e.actor, '')
    order by e.id
  loop
    select department into v_dept from org_agents where agent_key = r.agent_key;
    v_task := null;

    -- 7.3 PRECONDITION. This used to hard-code tier 'autonomous', so a subscriber was granted
    -- autonomy by the dispatcher rather than by the authority model. It reads the tier now.
    if v_dept is not null then
      v_tier := coalesce(public.fn_dept_authority(v_dept, 'analysis')->>'tier', 'gated');
      if v_tier <> 'autonomous' then v_gated := v_gated + 1; end if;
      insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, decided_by)
      values (v_dept,
              left(r.event_type || ' on ' || r.entity_type || ' ' || coalesce(r.entity_id,''), 200),
              format('Event %s (%s %s) raised by %s at %s. You subscribe to this because: %s. Act on it or close it with a reason.',
                     r.event_type, r.entity_type, coalesce(r.entity_id,'-'), coalesce(r.actor,'system'), r.occurred_at, coalesce(r.reason,'subscription')),
              case when v_tier = 'autonomous' then 'assigned' else 'proposed' end,
              v_tier, v_tier <> 'autonomous', 'analysis', 'fn_event_dispatch')
      returning id into v_task;
      v_tasks := v_tasks + 1;
    end if;

    insert into event_delivery (event_id, agent_key, event_type, task_id)
    values (r.event_id, r.agent_key, r.event_type, v_task)
    on conflict do nothing;
    v_delivered := v_delivered + 1;
  end loop;

  return jsonb_build_object('delivered', v_delivered, 'tasks_created', v_tasks,
                            'tasks_awaiting_a_human', v_gated,
                            'lookback_minutes', p_lookback_minutes);
end; $function$;

revoke all on function public.fn_ops_authority_check(text,text,numeric,text) from public, anon, authenticated;
revoke all on function public.fn_dept_authority(text,text,numeric) from public, anon, authenticated;
revoke all on function public.fn_event_dispatch(integer) from public, anon, authenticated;;
