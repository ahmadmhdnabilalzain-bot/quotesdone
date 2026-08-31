-- ONLY REFUNDS REACH THE FOUNDER — the agent_actions queue is brought into line with his rule.
--
-- THE FOUNDER'S RULE (his words): "Only refunds should require my APPROVAL." The Phase C layer
-- already enforces this — founder_approval_request is refund-only (fn_founder_approval_refund_only),
-- v_founder_inbox buckets only refund_decision, and fn_kernel_founder_approval_state proves it. But
-- there is an OLDER queue with its OWN vocabulary: public.agent_action_kind_policy marked 10 kinds
-- policy='founder', and fn_founder_queue / fn_founder_brief surface those as "item(s) no agent may
-- settle" — i.e. they BLOCK on him. fn_agent_action_work_sweep skips them (it joins policy='auto').
-- So ten kinds still sit in front of the founder that are not refunds. This closes that.
--
-- THE SPLIT HE ASKED FOR:
--   * The AI/officer DECISIONS are re-routed to the accountable AI authority — prompt_approval,
--     finance_marketing_budget, simulation_apply, compliance_update. They become policy='officer'
--     and the sweep re-addresses each to the authority's runtime employee, out of his queue.
--   * The genuine major-issue ALERTS NOTIFY him without blocking — backup_alert, finance_alert,
--     incident, security_incident, legal_flag, customer_escalation. They become policy='notify'; the
--     sweep fires fn_notify_founder (the founder-notification channel / Stage 4: founder_alerts for
--     the console, plus a queued email + WhatsApp for when the delivery pipeline is on) and hands the
--     RESPONSE to the accountable authority. He is told; he is not the queue.
--
-- STRUCTURAL, NOT JUST DATA. The policy CHECK is narrowed to ('auto','officer','notify'): 'founder'
-- is no longer a legal value for an agent_action kind, so no future migration or agent can put a
-- non-refund item back in front of him through this table. His single routine approval — a specific
-- refund decision — lives on the Phase C path, untouched.
--
-- ZERO INFERENCE. Routing and notification are pure SQL; nothing here calls a model. The officer
-- decisions are OWNED by the authority (addressed to its employee); their eventual settlement is the
-- authority's own work, unchanged and un-accelerated by this file.

begin;

-- ---- 1. Widen the policy vocabulary (drop old check, reclassify, add new check) ------------------
-- Order matters: the rows must be re-valued before the new CHECK, and the old CHECK dropped before
-- the rows, because the old one only permits auto/founder.
alter table public.agent_action_kind_policy
  drop constraint if exists agent_action_kind_policy_policy_check;

alter table public.agent_action_kind_policy
  add column if not exists authority_role text;

-- DECISIONS -> the accountable AI authority (never the founder).
update public.agent_action_kind_policy set policy='officer', authority_role='cto',
  note = note || '  [re-routed 1 Sep 2026: the CTO owns what agents are told to be; not the founder]'
  where kind='prompt_approval';
update public.agent_action_kind_policy set policy='officer', authority_role='chief_revenue_officer',
  note = note || '  [re-routed 1 Sep 2026: the CRO owns marketing spend within budget; not the founder]'
  where kind='finance_marketing_budget';
update public.agent_action_kind_policy set policy='officer', authority_role='chief_operating_officer',
  note = note || '  [re-routed 1 Sep 2026: the COO owns applying an operational change; not the founder]'
  where kind='simulation_apply';
update public.agent_action_kind_policy set policy='officer', authority_role='general_counsel',
  note = note || '  [re-routed 1 Sep 2026: the General Counsel owns a compliance change; not the founder]'
  where kind='compliance_update';

-- ALERTS -> notify the founder, hand the response to the accountable authority.
update public.agent_action_kind_policy set policy='notify', authority_role='cto',
  note = note || '  [notify 1 Sep 2026: a backup gap is a fact he is TOLD; the CTO owns the fix]'
  where kind='backup_alert';
update public.agent_action_kind_policy set policy='notify', authority_role='cfo',
  note = note || '  [notify 1 Sep 2026: he is TOLD; the CFO owns the money response]'
  where kind='finance_alert';
update public.agent_action_kind_policy set policy='notify', authority_role='chief_operating_officer',
  note = note || '  [notify 1 Sep 2026: he is TOLD; the COO owns the operational response]'
  where kind='incident';
update public.agent_action_kind_policy set policy='notify', authority_role='cto',
  note = note || '  [notify 1 Sep 2026: he is TOLD; the CTO owns the technical response]'
  where kind='security_incident';
update public.agent_action_kind_policy set policy='notify', authority_role='general_counsel',
  note = note || '  [notify 1 Sep 2026: he is TOLD; the General Counsel owns the legal response]'
  where kind='legal_flag';
update public.agent_action_kind_policy set policy='notify', authority_role='customer_success_director',
  note = note || '  [notify 1 Sep 2026: he is TOLD; Customer Success owns the customer, never mass-closed]'
  where kind='customer_escalation';

alter table public.agent_action_kind_policy
  add constraint agent_action_kind_policy_policy_check
  check (policy = any (array['auto'::text, 'officer'::text, 'notify'::text]));

-- ---- 2. The founder-notification channel (Stage 4) as a pure-SQL helper --------------------------
-- Writes the always-on console surface (founder_alerts) AND queues email + WhatsApp the same shape
-- the alert_founder edge function uses, so the existing send_outbox / send_whatsapp pollers deliver
-- them when that pipeline is enabled. It NEVER blocks: it is a notification, not an approval.
create or replace function public.fn_notify_founder(p_event text, p_detail text, p_level text default 'high')
returns void
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $fn$
declare v_email text; v_phone text;
begin
  select nullif(split_part(coalesce(value,''),',',1),'') into v_email
    from public.app_secrets where key='admin_emails';
  v_email := coalesce(v_email, 'management@quotesdone.com');
  select nullif(btrim(value),'') into v_phone from public.app_secrets where key='admin_mfa_phone';

  -- the console log — read by the OS and by fn_founder_brief; this surface is always on.
  insert into public.founder_alerts(level, event, detail, channel)
    values (coalesce(nullif(btrim(p_level),''),'high'), p_event, p_detail, 'os');

  -- the email queue (send_outbox / Resend).
  insert into public.notifications(type, to_email, to_role, subject, body, status, channel)
    values ('founder_alert', v_email, 'founder', '[Attention] '||p_event, p_detail, 'queued', 'email');

  -- WhatsApp for severe levels (send_whatsapp / Twilio); trg_wa_fanout does NOT fan out founder rows.
  if v_phone is not null and lower(coalesce(p_level,'')) in ('critical','urgent','high','danger') then
    insert into public.notifications(type, to_phone, to_role, subject, body, status, channel)
      values ('founder_alert', v_phone, 'founder', p_event,
              'QuotesDone ['||p_level||']: '||p_event, 'queued', 'whatsapp');
  end if;
end $fn$;

revoke execute on function public.fn_notify_founder(text, text, text) from public;

-- ---- 3. The sweep now drains three vocabularies, not one ----------------------------------------
-- auto  : unchanged — queue an action_execution for the addressed employee (the worker settles it).
-- officer: re-address the item to the accountable authority's employee, out of the founder's queue.
-- notify : notify the founder once (Stage 4) and hand the response to the authority's employee.
-- Both officer and notify are idempotent on detail->>'routed_at', so an hourly re-run does neither
-- twice. trg_page_high_agent_action is AFTER INSERT only, so re-addressing via UPDATE never pages.
create or replace function public.fn_agent_action_work_sweep(p_limit integer DEFAULT 10)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_q int := 0; v_officer int := 0; v_notify int := 0; r record; v_key text;
begin
  for r in
    select a.id, a.kind,
           (select count(*) from public.action_execution x
             where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
               and x.status = 'failed') as failures
      from public.agent_actions a
      join public.org_agents o on o.agent_key = a.agent and o.active
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
     where a.status = 'pending'
       -- Nothing live and nothing already settled for this item...
       and not exists (select 1 from public.action_execution x
                        where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
                          and x.status in ('queued','running','succeeded'))
       -- ...and fewer than two attempts have failed. Equality, not LIKE: `_` is a single-character
       -- wildcard in LIKE and 'agent_action:' is full of them, so `like 'agent_action:'||id` would
       -- also match keys this function never wrote.
       and (select count(*) from public.action_execution x
             where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
               and x.status = 'failed') < 2
     order by a.created_at
     limit greatest(coalesce(p_limit, 10), 1)
  loop
    v_key := 'agent_action:' || r.id || case when r.failures >= 1 then '#2' else '' end;
    insert into public.action_execution(id, correlation_id, action_class, executor, idempotency_key,
                                        risk_tier, reversible, request, status, attempts)
    values (gen_random_uuid(), gen_random_uuid(), 'agent_action_work', 'action_worker',
            v_key, 'low', true,
            jsonb_build_object('action_id', r.id, 'kind', r.kind,
                               'source', 'fn_agent_action_work_sweep',
                               'attempt', r.failures + 1),
            'queued', 0)
    on conflict (idempotency_key) do nothing;
    v_q := v_q + 1;
  end loop;

  -- OFFICER decisions: route to the accountable AI authority, never the founder. The determination
  -- itself is the authority's own work; this only makes the authority the owner and removes the
  -- founder as the bottleneck.
  for r in
    select a.id, p.authority_role,
           coalesce(ro.runtime_agent_key, p.authority_role) as authority_agent
      from public.agent_actions a
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'officer'
      left join public.org_role ro on ro.role_id = p.authority_role and ro.status = 'active'
     where a.status in ('pending','needs_review','held_for_review','proposed','open')
       and (a.detail->>'routed_at') is null
  loop
    update public.agent_actions
       set agent = coalesce(r.authority_agent, agent),
           escalated = true,
           escalation_reason =
             case when coalesce(escalation_reason,'') = '' then '' else escalation_reason || ' | ' end
             || 'routed to accountable AI authority ' || coalesce(r.authority_role,'(unset)')
             || ' — only refunds require the founder',
           detail = coalesce(detail,'{}'::jsonb) || jsonb_build_object(
                      'routed_at', now(),
                      'routed_to', coalesce(r.authority_agent, r.authority_role),
                      'route_basis', 'officer_policy')
     where id = r.id;
    v_officer := v_officer + 1;
  end loop;

  -- NOTIFY alerts: tell the founder (Stage 4), non-blocking, and hand the response to the authority.
  for r in
    select a.id, a.kind, a.title, a.recommendation, a.risk, a.agent, p.authority_role,
           coalesce(ro.runtime_agent_key, p.authority_role) as authority_agent
      from public.agent_actions a
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'notify'
      left join public.org_role ro on ro.role_id = p.authority_role and ro.status = 'active'
     where a.status in ('pending','needs_review','held_for_review','proposed','open')
       and (a.detail->>'routed_at') is null
  loop
    perform public.fn_notify_founder(
      coalesce(nullif(r.title,''), r.kind),
      coalesce(nullif(r.recommendation,''), nullif(r.title,''), r.kind)
        || E'\n\nRaised by ' || coalesce(r.agent,'?')
        || '. Handling owner: ' || coalesce(r.authority_role,'(unset)')
        || '. This is a notification — open the OS to review; no approval is required of you.',
      case when lower(coalesce(r.risk,'')) in ('high','critical') then 'high' else 'warn' end);
    update public.agent_actions
       set agent = coalesce(r.authority_agent, agent),
           detail = coalesce(detail,'{}'::jsonb) || jsonb_build_object(
                      'routed_at', now(),
                      'routed_to', coalesce(r.authority_agent, r.authority_role),
                      'route_basis', 'notify_policy',
                      'founder_notified_at', now())
     where id = r.id;
    v_notify := v_notify + 1;
  end loop;

  return jsonb_build_object('queued', v_q, 'officer_routed', v_officer, 'notify_sent', v_notify,
    'ran_at', now(),
    'eligible_remaining', (select count(*) from public.agent_actions a
                             join public.org_agents o on o.agent_key = a.agent and o.active
                             join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
                            where a.status = 'pending'
                              and not exists (select 1 from public.action_execution x
                                               where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
                                                 and x.status in ('queued','running','succeeded'))
                              and (select count(*) from public.action_execution x
                                    where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
                                      and x.status = 'failed') < 2),
    -- Named separately so "we have stopped trying" is never counted as "we are working on it".
    'exhausted_two_attempts', (select count(*) from public.agent_actions a
                                 join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
                                where a.status = 'pending'
                                  and (select count(*) from public.action_execution x
                                        where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
                                          and x.status = 'failed') >= 2),
    -- No kind routes to the founder any more; this is retained as a tripwire and must read 0.
    'never_auto_settled', (select count(*) from public.agent_actions a
                             join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
                            where a.status = 'pending'),
    'unrouted', (select count(*) from public.agent_actions a
                  where a.status = 'pending'
                    and not exists (select 1 from public.agent_action_kind_policy p where p.kind = a.kind)));
end $function$;

commit;
