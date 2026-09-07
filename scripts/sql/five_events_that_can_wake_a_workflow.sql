-- FIVE EVENTS THAT CAN WAKE A WORKFLOW (org audit C6).
--
-- THE GAP, MEASURED. Five company events have ACTIVE subscribers but NO emitter, so the workflows that
-- start from them (W18 support/retention, W20 marketing, and the Office of the CEO) could never wake:
--   content.drafted        -> brand_mgr           customer.churn_signal -> cs_retention
--   customer.complaint     -> cs_support          campaign.published    -> marketing_analyst
--   department.conflict    -> brief (chief of staff)
--
-- THE FIX. Four AFTER triggers on the events' real originating tables, each writing company_event
-- through fn_emit(event_type, entity_type, entity_id, actor, payload) the way fn_emit_invoice_received
-- does. department.conflict has NO originating table (measured: the only conflict tables are payment,
-- inquiry-answer and workstream, none of them cross-department), so it is a DETECTOR: it emits when two
-- agents from DIFFERENT departments reach DIFFERENT decisions on the same kind within a week — a real
-- cross-department conflict read from decision_log — deduplicated to once per kind per week.
--
--   node scripts/apply_sql.mjs scripts/sql/five_events_that_can_wake_a_workflow.sql --apply --ddl

begin;

-- 1. content.drafted — a new content draft is created. (content_drafts has no other triggers.)
create or replace function public.fn_emit_content_drafted()
returns trigger language plpgsql security definer set search_path to 'public' as $fn$
begin
  perform public.fn_emit('content.drafted', 'content_draft', new.id::text, coalesce(new.source,'system'),
    jsonb_build_object('channel', new.channel, 'category', new.category, 'title', new.title,
                       'status', new.status));
  return new;
end $fn$;
drop trigger if exists t_emit_content_drafted on public.content_drafts;
create trigger t_emit_content_drafted after insert on public.content_drafts
  for each row execute function public.fn_emit_content_drafted();

-- 2. customer.churn_signal — churn_risk rises into the danger band (>= 0.7), on the transition only.
create or replace function public.fn_emit_churn_signal()
returns trigger language plpgsql security definer set search_path to 'public' as $fn$
begin
  if new.churn_risk is not null and new.churn_risk >= 0.7
     and (tg_op = 'INSERT' or coalesce(old.churn_risk, 0) < 0.7) then
    perform public.fn_emit('customer.churn_signal', 'customer', new.customer_id::text, 'system',
      jsonb_build_object('customer_id', new.customer_id, 'churn_risk', new.churn_risk,
                         'lifetime_value_aed', new.lifetime_value_aed, 'last_active', new.last_active));
  end if;
  return new;
end $fn$;
drop trigger if exists t_emit_churn_signal on public.customer_score;
create trigger t_emit_churn_signal after insert or update on public.customer_score
  for each row execute function public.fn_emit_churn_signal();

-- 3. customer.complaint — a low rating (1-2) or a complaint-source feedback row.
create or replace function public.fn_emit_customer_complaint()
returns trigger language plpgsql security definer set search_path to 'public' as $fn$
begin
  perform public.fn_emit('customer.complaint', 'feedback', new.id::text, coalesce(new.source,'customer'),
    jsonb_build_object('subject_type', new.subject_type, 'subject_id', new.subject_id,
                       'rating', new.rating, 'source', new.source, 'comment', left(coalesce(new.comment,''),500)));
  return new;
end $fn$;
drop trigger if exists t_emit_customer_complaint on public.feedback;
create trigger t_emit_customer_complaint after insert on public.feedback
  for each row when ((new.rating is not null and new.rating <= 2)
                     or (new.source is not null and lower(new.source) like '%complaint%'))
  execute function public.fn_emit_customer_complaint();

-- 4. campaign.published — a content_campaign Phase D object reaches state 'published'. Tight WHEN so it
-- fires for nothing else on the kernel table; the body emits only on the transition into published.
create or replace function public.fn_emit_campaign_published()
returns trigger language plpgsql security definer set search_path to 'public' as $fn$
begin
  if tg_op = 'INSERT' or coalesce(old.state,'') is distinct from 'published' then
    perform public.fn_emit('campaign.published', 'content_campaign', new.business_key, coalesce(new.created_by,'system'),
      jsonb_build_object('business_key', new.business_key, 'version', new.version,
                         'object_id', new.object_id, 'payload', new.payload));
  end if;
  return new;
end $fn$;
drop trigger if exists t_emit_campaign_published on public.phase_d_object_record;
create trigger t_emit_campaign_published after insert or update on public.phase_d_object_record
  for each row when (new.object_id = 'content_campaign' and new.state = 'published')
  execute function public.fn_emit_campaign_published();

-- 5. department.conflict — a DETECTOR, because no originating table exists. Two agents in DIFFERENT
-- departments reaching DIFFERENT decisions on the same kind inside a week is a cross-department conflict;
-- emit it to the chief of staff, once per kind per week.
create or replace function public.fn_emit_department_conflict()
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare r record; v_emitted int := 0;
begin
  for r in
    with dl as (
      select l.kind, l.decision, ag.department dep
        from public.decision_log l
        join public.org_agents ag
          on ag.agent_key = coalesce(public.fn_org_agent_resolve(l.actor), l.actor) and ag.active
       where l.created_at > now() - interval '7 days' and coalesce(l.decision,'') <> ''
         and ag.department is not null)
    select kind, count(distinct dep) depts, count(distinct decision) decisions,
           string_agg(distinct dep||':'||decision, ' vs ') detail
      from dl group by kind
     having count(distinct dep) > 1 and count(distinct decision) > 1
  loop
    -- dedup: one department.conflict per kind per 7 days
    if not exists (select 1 from public.company_event e
                    where e.event_type = 'department.conflict' and e.entity_id = r.kind
                      and e.occurred_at > now() - interval '7 days') then
      perform public.fn_emit('department.conflict', 'decision_kind', r.kind, 'governance',
        jsonb_build_object('kind', r.kind, 'departments', r.depts, 'decisions', r.decisions,
                           'detail', left(r.detail, 600)));
      v_emitted := v_emitted + 1;
    end if;
  end loop;
  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('department_conflict_scan', now(), now(), 'ok', jsonb_build_object('emitted', v_emitted),
          'Cross-department decision-conflict scan: '||v_emitted||' department.conflict event(s) emitted.');
  return jsonb_build_object('ok', true, 'emitted', v_emitted);
end $fn$;

-- New SECURITY DEFINER functions: revoke the PUBLIC execute grant every CREATE adds.
revoke execute on function public.fn_emit_content_drafted()      from public;
revoke execute on function public.fn_emit_churn_signal()         from public;
revoke execute on function public.fn_emit_customer_complaint()   from public;
revoke execute on function public.fn_emit_campaign_published()   from public;
revoke execute on function public.fn_emit_department_conflict()  from public;

-- The detector runs weekly (a plain pg_cron job, as most jobs here do).
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.

commit;
