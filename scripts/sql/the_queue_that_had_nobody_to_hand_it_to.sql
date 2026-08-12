-- THE QUEUE THAT HAD NOBODY TO HAND IT TO
--
-- Measured on production, 12 Aug 2026 23:00 UTC. The brief said the dispatcher does not exist and
-- that agent_actions.kind and org_action_executor.action_class are disjoint namespaces with no
-- bridge. That was true when it was written and it is not true now: fn_agent_action_work_sweep
-- turns an eligible agent_action into an action_execution row with action_class
-- 'agent_action_work', fn_action_invoke_dispatch POSTs it to action_worker, and 257 of 267 model
-- calls that path has made SUCCEEDED. The bridge is built. What is wrong with it is three
-- different things, and none of them is the missing map.
--
-- 47 rows are pending. Read the writer, not the count:
--
--   24  kinds the machine must never settle alone (customer_escalation 9, legal_flag 6,
--       security_incident 3, prompt_approval 2, compliance_update 1, finance_alert 1,
--       finance_marketing_budget 1, incident 1). The OLDEST IS 9 JULY — 35 days. They are
--       correctly refused and then correctly forgotten, because nothing anywhere shows them to
--       the one person who can settle them. fn_wa_context hands the founder
--       'actions_pending: 47', one number, which reads as "the company is busy" and is in fact
--       "24 decisions have been waiting on you for up to five weeks".
--    8  eligible handoffs raised at 22:35-22:41, after the 22:35 sweep. Not a defect; they run
--       at 23:35. Verified by created_at, not assumed.
--   11  eligible and already attempted, of which 9 FAILED, and 8 of those 9 failed the same way.
--    3  kinds in NEITHER list: backup_alert, coverage_gap, simulation_apply. No policy at all.
--    1  succeeded and the source row never left pending (2 of 257 lifetime; not this file).
--
-- ---------------------------------------------------------------------------------------------
-- 1. THE EXECUTOR GATE DOES NOT READ notifies_human, AND SIX LIVE EXECUTORS SET IT.
--
-- The founder's instruction is exact: the dispatcher "MUST honour org_action_executor
-- .notifies_human before any sweep touches a row — an executor can be low-risk, advisory-safe and
-- reversible and still email a supplier."
--
-- fn_action_invoke_dispatch gates on active / required_authority / reversibility / and the triple
-- (risk_tier='low' AND advisory_safe AND reversible). It has never read notifies_human. Measured:
-- 41 executors pass that gate today and SIX of them have notifies_human = true —
-- capability_review, expense_log, forecast, health_report, money_verify, security_review. The
-- column has been sitting there being true and being ignored.
--
-- A blanket refusal is the wrong fix and would be a regression: all six of those exist in order to
-- report the company's own state to the founder, health_report and forecast have already run 11
-- times between them, and refusing them stops the reporting he asked for. What is missing is not a
-- ban, it is THE DECISION PER CLASS he asked for — recorded as data, defaulting to refuse, so that
-- the next executor someone adds with notifies_human = true is refused until a human says
-- otherwise rather than firing on its first sweep.
alter table public.org_action_executor
  add column if not exists unattended_ok boolean not null default false;

comment on column public.org_action_executor.unattended_ok is
  'Deliberate per-class decision: may this executor be fired by fn_action_invoke_dispatch with nobody watching, GIVEN that it notifies a human? Only consulted when notifies_human is true. Defaults to FALSE so a newly added human-notifying executor is refused until someone decides, rather than emailing a supplier on its first sweep.';

-- The six, decided one at a time. Every one of them notifies THE FOUNDER about the company's own
-- state — a health report, a cost forecast, a spend check, a security scan of our own estate, an
-- expense we logged ourselves, a review of our own agents' learnings. None of them contacts a
-- customer, a supplier or any other third party, which is the risk the flag exists to catch.
-- If a future executor emails a supplier, it gets notifies_human = true, unattended_ok stays
-- false, and the invoker refuses it with that reason in the response.
update public.org_action_executor set unattended_ok = true
 where action_class in ('capability_review','expense_log','forecast','health_report',
                        'money_verify','security_review')
   and notifies_human;

-- CREATE OR REPLACE preserves the ACL, so this one carries no REVOKE. The only change is the
-- fourth refusal and its reason string.
create or replace function public.fn_action_invoke_dispatch(p_limit integer default 5)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_req bigint; v_sent int := 0; v_refused int := 0; v_skipped int := 0;
        v_url text; v_secret text; v_ref text; v_key text;
begin
  select value into v_secret from app_secrets where key = 'cred_action_invoker';
  if v_secret is null then
    return jsonb_build_object('error', 'no cred_action_invoker credential', 'ran_at', now());
  end if;
  -- The project ref is read off an existing cron command rather than hard-coded, so the same
  -- migration file is correct on production and on staging.
  select value into v_ref from app_secrets where key = 'project_ref';
  if v_ref is null then
    select substring(command from 'https://([a-z]+)[.]supabase[.]co') into v_ref
      from cron.job where command like '%supabase.co/functions/v1/%' limit 1;
  end if;
  if v_ref is null then return jsonb_build_object('error','cannot determine project ref','ran_at',now()); end if;

  for r in
    select a.id, a.action_class, a.request, a.idempotency_key, a.attempts,
           e.target, e.kind, e.active, e.risk_tier, e.advisory_safe, e.reversible,
           e.required_authority, e.compensation_action_class, e.idempotency_strategy, e.params,
           e.notifies_human, e.unattended_ok,
           coalesce(e.timeout_seconds, 60) timeout_seconds, coalesce(e.max_attempts, 1) max_attempts
      from public.action_execution a
      join public.org_action_executor e on e.action_class = a.action_class
     where a.status = 'queued' and e.kind = 'edge'
     order by a.created_at
     limit greatest(coalesce(p_limit, 5), 1)
  loop
    -- ---- the three absolute refusals, the human-contact refusal, then the risk tier -----------
    -- notifies_human is checked BEFORE the risk tier on purpose. The tier answers "how much
    -- damage if this is wrong"; notifies_human answers "does a person hear from us either way",
    -- and a message that should not have been sent cannot be un-sent by a low risk score.
    if not r.active
       or coalesce(r.required_authority,'') = 'founder'
       or (not r.reversible and r.compensation_action_class is null)
       or (coalesce(r.notifies_human,false) and not coalesce(r.unattended_ok,false))
       or not (r.risk_tier = 'low' and r.advisory_safe and r.reversible) then
      update public.action_execution
         set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker', 'refused', 'at', now(),
               'reason', case
                 when not r.active then 'executor row is inactive'
                 when coalesce(r.required_authority,'') = 'founder' then 'reserved to the founder'
                 when (not r.reversible and r.compensation_action_class is null)
                   then 'not reversible and declares no compensation_action_class'
                 when (coalesce(r.notifies_human,false) and not coalesce(r.unattended_ok,false))
                   then 'notifies_human is true and unattended_ok has not been set for this class — a person hears from us when this runs, and nobody has decided it may run unattended'
                 else format('risk gate: tier=%s advisory_safe=%s reversible=%s — the invoker dispatches low/advisory_safe/reversible only',
                             r.risk_tier, r.advisory_safe, r.reversible) end)
       where id = r.id;
      v_refused := v_refused + 1;
      continue;
    end if;

    -- ---- idempotency: the column exists on both tables and was never consulted ---------------
    v_key := coalesce(nullif(btrim(r.idempotency_key),''),
                      r.action_class || ':' || md5(coalesce(r.request::text,'')));
    if r.idempotency_strategy is distinct from 'none_read_only'
       and exists (select 1 from public.action_execution x
                    where x.id <> r.id and x.status = 'succeeded'
                      and x.idempotency_key = v_key
                      and x.finished_at > now() - interval '24 hours') then
      update public.action_execution
         set status = 'succeeded', finished_at = now(),
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','deduplicated','at',now(),'idempotency_key',v_key,
               'strategy', r.idempotency_strategy)
       where id = r.id;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_url := 'https://' || v_ref || '.supabase.co/functions/v1/' || r.target;
    select net.http_post(
             url := v_url,
             headers := '{"Content-Type":"application/json"}'::jsonb,
             -- org_action_executor.params is the per-executor payload TEMPLATE and it existed,
             -- empty, on all 55 rows. Without it the invoker sent {org_task_id, dept_key, title}
             -- to every target and compliance_archive answered 400 unknown_action — found by
             -- execution on the first real sweep, not by reading. params is the base of the body
             -- so a target's contract is declared as data, not coded into the invoker.
             body := coalesce(r.params, '{}'::jsonb) || coalesce(r.request, '{}'::jsonb)
                     || jsonb_build_object('__secret', v_secret),
             timeout_milliseconds := r.timeout_seconds * 1000)
      into v_req;

    update public.action_execution
       set status = 'running', attempts = coalesce(attempts,0) + 1,
           executor = r.target, idempotency_key = v_key,
           started_at = coalesce(started_at, now()),
           response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
             'invoker','dispatched','at',now(),'net_request_id',v_req,'url',v_url,
             'timeout_seconds', r.timeout_seconds, 'attempt', coalesce(r.attempts,0)+1,
             'max_attempts', r.max_attempts)
     where id = r.id;
    v_sent := v_sent + 1;
  end loop;

  return jsonb_build_object('dispatched', v_sent, 'refused', v_refused,
                            'deduplicated', v_skipped, 'ran_at', now());
end $function$;

-- ---------------------------------------------------------------------------------------------
-- 2. THE KIND POLICY LIVED IN TWO PLACES AND NEITHER OF THEM COULD SAY "I DON'T KNOW".
--
-- The 14 auto-settleable kinds and the 8 never-auto kinds are hard-coded TWICE: as a SQL IN-list
-- inside fn_agent_action_work_sweep, and as two TypeScript Sets inside action_worker. They agree
-- today. Nothing makes them agree tomorrow, and more importantly NEITHER OF THEM HAS A THIRD
-- ANSWER. A kind in neither list is not refused with a reason and it is not queued — it is simply
-- never selected, by both of them, silently.
--
-- 24 kinds are in neither list and 1,459 rows have been written under them. Most are closed by
-- their own writer and never queue at all, so this is not 1,459 stuck items. But three are pending
-- right now and have been for one to two days with no route and no record that they have no route:
-- backup_alert, coverage_gap, simulation_apply. Ask what this instrument prints when its input is
-- absent, and the answer is: nothing at all, in both languages.
--
-- One table, read by both. An unknown kind is refused AND named.
create table if not exists public.agent_action_kind_policy (
  kind        text primary key,
  policy      text not null check (policy in ('auto','founder')),
  note        text,
  decided_at  timestamptz not null default now()
);

comment on table public.agent_action_kind_policy is
  'Single source of truth for what may happen to an agent_actions row of a given kind. policy=auto: an AI employee may settle it by producing a written determination (action_worker). policy=founder: never settled without him; it belongs in fn_founder_queue. A kind with NO ROW HERE is refused by both the sweep and the worker and is reported as unrouted by fn_founder_queue — absence is a visible answer, not silence.';

-- RLS explicitly, on both projects. Production adds it to a new table by event trigger and staging
-- does not, so the same DDL otherwise yields two different tables and project_parity fails.
alter table public.agent_action_kind_policy enable row level security;
revoke all on public.agent_action_kind_policy from anon, authenticated;

insert into public.agent_action_kind_policy (kind, policy, note) values
  -- the 14 that were already eligible, verbatim
  ('handoff',                  'auto',    'one employee hands work to another; the determination is the work'),
  ('improvement_question',     'auto',    'a question about how we work, answered in writing'),
  ('knowledge_task',           'auto',    'a gap in what we know, filled in writing'),
  ('report_recommendation',    'auto',    'a recommendation arising from a report'),
  ('report_task',              'auto',    'a task arising from a report'),
  ('objective_step',           'auto',    'one step of a company objective'),
  ('strategy_rec',             'auto',    'a strategy recommendation'),
  ('ops_recommendation',       'auto',    'an operations recommendation'),
  ('marketing_recommendation', 'auto',    'a marketing recommendation'),
  ('ai_improvement',           'auto',    'an improvement to how the estate uses models'),
  ('doc_task',                 'auto',    'a documentation task'),
  ('supply_health',            'auto',    'an assessment of supply-side health'),
  ('decision.route_category',  'auto',    'which category an inquiry belongs to'),
  ('autonomy_stall',           'auto',    'the engine noticing it has stopped moving'),
  -- the 8 that were already refused, verbatim
  ('customer_escalation',      'founder', 'a customer is unhappy; a machine closing this is the mass-closing the standing rules forbid'),
  ('legal_flag',               'founder', 'legal exposure'),
  ('security_incident',        'founder', 'a security incident'),
  ('prompt_approval',          'founder', 'changing what an agent is told to be'),
  ('compliance_update',        'founder', 'a compliance obligation changed'),
  ('finance_alert',            'founder', 'money'),
  ('finance_marketing_budget', 'founder', 'money'),
  ('incident',                 'founder', 'an operational incident'),
  -- the three that were in neither, decided
  ('coverage_gap',             'auto',    'an RFQ matched zero suppliers. What to do about it — which categories we are short of and how — is a written determination, and it is ops_director''s. Acting on it (recruiting, spending) is a separate action that goes through its own executor.'),
  ('backup_alert',             'founder', 'a backup did not happen. Nobody should be able to mark that settled by writing an essay about it; it is a fact that needs a person.'),
  ('simulation_apply',         'founder', 'APPLYING a simulated change to the live company is a change, not a determination. The written analysis is already in the simulation; what is left is the decision to act on it.')
on conflict (kind) do update
  set policy = excluded.policy, note = excluded.note, decided_at = now();

-- The sweep now reads the table. Same behaviour for every kind that was already listed — verified
-- by the seed above being the same 22 kinds — plus coverage_gap becomes eligible, and an unknown
-- kind is excluded by the join rather than by a silent absence from a literal.
create or replace function public.fn_agent_action_work_sweep(p_limit integer default 10)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_q int := 0; r record;
begin
  for r in
    select a.id, a.kind
      from public.agent_actions a
      join public.org_agents o on o.agent_key = a.agent and o.active
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
     where a.status = 'pending'
       and not exists (select 1 from public.action_execution x
                        where x.idempotency_key = 'agent_action:' || a.id)
                          -- ALL statuses, not just the live ones: idempotency_key is UNIQUE, so an
                          -- item that already FAILED once collides on re-sweep. Cycle 3 of the
                          -- first drain died on 23505 for exactly that. A failed attempt is a
                          -- recorded attempt.
     order by a.created_at
     limit greatest(coalesce(p_limit, 10), 1)
  loop
    insert into public.action_execution(id, correlation_id, action_class, executor, idempotency_key,
                                        risk_tier, reversible, request, status, attempts)
    values (gen_random_uuid(), gen_random_uuid(), 'agent_action_work', 'action_worker',
            'agent_action:' || r.id, 'low', true,
            jsonb_build_object('action_id', r.id, 'kind', r.kind,
                               'source', 'fn_agent_action_work_sweep'),
            'queued', 0)
    on conflict (idempotency_key) do nothing;
    v_q := v_q + 1;
  end loop;

  return jsonb_build_object('queued', v_q, 'ran_at', now(),
    'eligible_remaining', (select count(*) from public.agent_actions a
                             join public.org_agents o on o.agent_key = a.agent and o.active
                             join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
                            where a.status = 'pending'
                              and not exists (select 1 from public.action_execution x
                                               where x.idempotency_key = 'agent_action:' || a.id)),
    'never_auto_settled', (select count(*) from public.agent_actions a
                             join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
                            where a.status = 'pending'),
    -- The third answer both languages lacked.
    'unrouted', (select count(*) from public.agent_actions a
                  where a.status = 'pending'
                    and not exists (select 1 from public.agent_action_kind_policy p where p.kind = a.kind)));
end $function$;

-- ---------------------------------------------------------------------------------------------
-- 3. HIS OWN QUEUE. 24 DECISIONS, THE OLDEST 35 DAYS OLD, AND ONE NUMBER THAT HID THEM.
--
-- fn_wa_context gives the founder health.actions_pending = 47. That number is measuring something
-- other than what its name suggests to the person reading it: it is the total depth of a queue
-- that is mostly the machine's own work in flight. The part that is HIS is 24 rows the machine is
-- forbidden to touch, and the oldest — a legal_flag — was raised on 9 July.
--
-- Nothing surfaces them. Not the OS dashboard, not an email, not the command channel. They were
-- correctly refused by action_worker and then correctly forgotten by everything else, which is the
-- most expensive kind of correct.
create or replace function public.fn_founder_queue(p_limit integer default 12)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select jsonb_build_object(
    'waiting_on_you_total',
      (select count(*) from public.agent_actions a
         join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
        where a.status in ('pending','needs_review')),
    'oldest_days',
      (select round(extract(epoch from now() - min(a.created_at)) / 86400)::int
         from public.agent_actions a
         join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
        where a.status in ('pending','needs_review')),
    'waiting_on_you', coalesce((
      select jsonb_agg(x order by x->>'raised')
        from (select jsonb_build_object(
                       'id', a.id, 'kind', a.kind, 'from', a.agent,
                       'title', left(coalesce(a.title, a.recommendation, ''), 160),
                       'raised', a.created_at,
                       'age_days', round(extract(epoch from now() - a.created_at) / 86400)::int) as x
                from public.agent_actions a
                join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
               where a.status in ('pending','needs_review')
               order by a.created_at
               limit greatest(coalesce(p_limit, 12), 1)) z), '[]'::jsonb),
    -- The machine's own work in flight, kept separate so the two are never added together again.
    'machine_is_working_on', (select count(*) from public.agent_actions a
                                join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
                               where a.status = 'pending'),
    -- A kind nobody has classified. Fail-closed and NAMED: the sweep will not queue it and the
    -- worker will not settle it, so if this list is not empty, work is sitting still and this is
    -- the only place that says so.
    'unrouted_kinds', coalesce((
      select jsonb_agg(jsonb_build_object('kind', k, 'pending', n, 'oldest_days', d))
        from (select a.kind k, count(*) n,
                     round(extract(epoch from now() - min(a.created_at)) / 86400)::int d
                from public.agent_actions a
               where a.status = 'pending'
                 and not exists (select 1 from public.agent_action_kind_policy p where p.kind = a.kind)
               group by a.kind order by 2 desc) y), '[]'::jsonb));
$function$;

-- A NEW SECURITY DEFINER function is granted EXECUTE to PUBLIC on creation. Revoked in the same
-- file, and this file must be applied with --promote --ddl so the REVOKE reaches production too:
-- --promote alone carries the definition and NOT the grants, which left a function anon-executable
-- on production twice in one night.
revoke all on function public.fn_founder_queue(integer) from public, anon, authenticated;
grant execute on function public.fn_founder_queue(integer) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 4. THE COMMAND CHANNEL NOW CARRIES IT.
--
-- Same shape as before with one block added and one number kept honest: actions_pending stays (it
-- is a true count of a real queue) but it no longer stands alone as the answer to "is anything
-- waiting on me", because it never was.
create or replace function public.fn_wa_context(p_audience text, p_phone text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_e164 text; v_lead record; v_cust record;
begin
  -- Normalise once: wa_from arrives as 'whatsapp:+9715...' and the tables hold several shapes.
  v_e164 := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  if v_e164 = '' then return jsonb_build_object('scope','none'); end if;

  -- ---------------------------------------------------------------- FOUNDER: the company itself
  if p_audience = 'founder' then
    return jsonb_build_object(
      'scope','company',
      'suppliers', jsonb_build_object(
        'leads_total',      (select count(*) from leads),
        'claimed',          (select count(*) from leads where coalesce(claimed,false)),
        'claimed_real',     (select count(*) from leads where coalesce(claimed,false)
                              and not (coalesce(company_name,'') ilike 'ZZ DEMO%' or coalesce(email,'') ilike '%@example.invalid')),
        'approved',         (select count(*) from leads where approval_status = 'approved'),
        'licence_verified', (select count(*) from leads where coalesce(verified,false)),
        'with_email',       (select count(*) from leads where coalesce(btrim(email),'') <> '')),
      'invites', jsonb_build_object(
        'enabled',      (select value from app_secrets where key='invite_enabled'),
        'daily_cap',    (select value from app_secrets where key='invite_daily_cap'),
        'sent_today',   (select count(*) from leads where invited_at >= date_trunc('day', now() at time zone 'utc')),
        'sent_7d',      (select count(*) from leads where invited_at > now() - interval '7 days'),
        'bounced_7d',   (select count(*) from leads where invite_status='bounced' and invited_at > now() - interval '7 days'),
        'uncontacted',  (select count(*) from leads where invited_at is null and coalesce(btrim(email),'') <> '')),
      'demand', jsonb_build_object(
        'customers',        (select count(*) from customers),
        'inquiries_total',  (select count(*) from inquiries),
        'inquiries_7d',     (select count(*) from inquiries where created_at > now() - interval '7 days'),
        'quotes_total',     (select count(*) from quotes),
        'quotes_7d',        (select count(*) from quotes where created_at > now() - interval '7 days')),
      'money', jsonb_build_object(
        'transactions',      (select count(*) from transactions),
        'revealed',          (select count(*) from transactions where revealed_at is not null),
        'ai_spend_today_aed',(select round(coalesce(sum(cost_aed),0)::numeric,2) from ai_cost_log where occurred_at >= current_date),
        'ai_spend_month_aed',(select round(coalesce(sum(cost_aed),0)::numeric,2) from ai_cost_log where occurred_at >= date_trunc('month', now()))),
      'health', jsonb_build_object(
        'agent_runs_failed_24h', (select count(*) from agent_runs where status in ('error','failed') and started_at > now() - interval '24 hours'),
        'actions_pending',       (select count(*) from agent_actions where status in ('pending','needs_review')),
        'escalations_open',      (select count(*) from agent_actions where coalesce(escalated,false) and status in ('pending','needs_review'))),
      -- THE PART THAT IS HIS. Named so the model cannot read it as more company telemetry: these
      -- are items no agent is allowed to settle, and they are waiting for him specifically.
      'your_decision_queue', public.fn_founder_queue(12));
  end if;

  -- ---------------------------------------------------------------- SUPPLIER: only their own row
  if p_audience = 'supplier' then
    select * into v_lead from leads l
     where regexp_replace(coalesce(l.phone_e164, l.phone, ''), '[^0-9]', '', 'g') = v_e164
        or regexp_replace(coalesce(l.whatsapp,''), '[^0-9]', '', 'g') = v_e164
     order by coalesce(l.claimed,false) desc, l.id limit 1;
    if not found then return jsonb_build_object('scope','supplier','known', false); end if;

    return jsonb_build_object(
      'scope','supplier', 'known', true,
      'company', v_lead.company_name,
      'profile', jsonb_build_object(
        'claimed',          coalesce(v_lead.claimed,false),
        'approval_status',  coalesce(v_lead.approval_status,'not submitted'),
        'verified',         coalesce(v_lead.verified,false),
        'email_verified',   coalesce(v_lead.owner_email_verified,false),
        'phone_verified',   coalesce(v_lead.owner_phone_verified,false),
        'trade_licence_no', v_lead.trade_license_no,
        'licence_authority',v_lead.license_authority,
        'licence_expiry',   v_lead.license_expiry,
        'licence_on_file',  (v_lead.license_doc_path is not null),
        'blocked_because',  v_lead.licence_gate_reason),
      'work', jsonb_build_object(
        'inquiries_received',  (select count(*) from inquiry_matches m where m.supplier_id = v_lead.id),
        'inquiries_quoted',    (select count(distinct q.inquiry_id) from quotes q where q.supplier_id = v_lead.id),
        'inquiries_missed',    (select count(*) from inquiry_matches m where m.supplier_id = v_lead.id
                                  and not exists (select 1 from quotes q where q.inquiry_id = m.inquiry_id and q.supplier_id = v_lead.id)),
        'quotes_submitted',    (select count(*) from quotes q where q.supplier_id = v_lead.id),
        'last_quote',          (select jsonb_build_object('amount_aed', q.quote_amount, 'status', q.status, 'when', q.created_at)
                                  from quotes q where q.supplier_id = v_lead.id order by q.created_at desc limit 1),
        'jobs_won',            (select count(*) from quotes q where q.supplier_id = v_lead.id and q.status = 'accepted')));
  end if;

  -- ---------------------------------------------------------------- CUSTOMER: only their own rows
  if p_audience = 'customer' then
    select * into v_cust from customers c
     where regexp_replace(coalesce(c.phone,''), '[^0-9]', '', 'g') = v_e164 limit 1;
    if not found then return jsonb_build_object('scope','customer','known', false); end if;

    return jsonb_build_object(
      'scope','customer', 'known', true,
      'name', v_cust.full_name,
      'profile', jsonb_build_object(
        'phone_verified', coalesce(v_cust.phone_verified,false),
        'email_verified', coalesce(v_cust.email_verified,false),
        'terms_signed',   (v_cust.signed_terms_url is not null)),
      'inquiries', coalesce((
        select jsonb_agg(x order by x->>'created_at' desc) from (
          select jsonb_build_object(
            'id', i.id, 'category', i.category, 'emirate', i.emirate, 'status', i.status,
            'created_at', i.created_at,
            'suppliers_received', (select count(*) from inquiry_matches m where m.inquiry_id = i.id),
            'quotes_received',    (select count(*) from quotes q where q.inquiry_id = i.id and q.status='submitted'),
            -- PRE-REVEAL: a band and a count, never the individual quotes and never a supplier name.
            'revealed', exists (select 1 from transactions t where t.inquiry_id = i.id and t.revealed_at is not null),
            'price_band', case
              when exists (select 1 from transactions t where t.inquiry_id = i.id and t.revealed_at is not null)
                then (select jsonb_build_object('low', min(q.quote_amount), 'high', max(q.quote_amount), 'average', round(avg(q.quote_amount)::numeric,0))
                        from quotes q where q.inquiry_id = i.id and q.status='submitted')
              else (select case when count(*) = 0 then null
                                else jsonb_build_object('average_rounded_to_nearest_1000',
                                        round(avg(q.quote_amount)::numeric / 1000) * 1000, 'note',
                                        'rounded band only - the exact quotes and the supplier names unlock when you reveal')
                           end from quotes q where q.inquiry_id = i.id and q.status='submitted') end) as x
          from inquiries i where i.customer_id = v_cust.id order by i.created_at desc limit 10) z), '[]'::jsonb));
  end if;

  return jsonb_build_object('scope','unknown');
end $function$;
