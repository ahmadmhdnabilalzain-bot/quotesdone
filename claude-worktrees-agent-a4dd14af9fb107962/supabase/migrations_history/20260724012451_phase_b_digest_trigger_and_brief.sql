-- Phase B: (a) park routine ops-alert emails into the daily brief instead of drip-emailing;
--          (b) enrich the single morning brief with an autonomy headline + "handled for you".

-- (a) BEFORE INSERT gate on notifications. Exception-safe: never blocks an insert.
create or replace function public.fn_notifications_digest()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare types jsonb;
begin
  if coalesce(NEW.channel,'email') <> 'email' then return NEW; end if;
  if NEW.status is not null and NEW.status not in ('queued','pending') then return NEW; end if;
  if coalesce(NEW.to_role,'') not in ('admin','founder','owner') then return NEW; end if;
  -- HARD EXCLUSIONS: these always send immediately regardless of policy.
  if coalesce(NEW.type,'') ~* 'money|refund|security|legal|fraud|critical|founder_alert|chief_of_staff|founder_brief|verify|otp|reset|password' then return NEW; end if;
  if coalesce(NEW.subject,'') ~* 'critical|urgent|fraud|breach|\mdown\M|failed|failure' then return NEW; end if;
  -- POLICY allowlist of routine types to fold into the brief.
  select value into types from public.decision_policy where key='alert_digest_types';
  if types is not null and types ? coalesce(NEW.type,'') then
    NEW.status := 'digest';
  end if;
  return NEW;
exception when others then
  return NEW;  -- a classifier error must never block a notification insert
end $function$;

drop trigger if exists trg_notifications_digest on public.notifications;
create trigger trg_notifications_digest before insert on public.notifications
  for each row execute function public.fn_notifications_digest();

-- (b) Enriched single morning brief: original content + autonomy headline + handled-for-you drain.
create or replace function public.fn_founder_brief()
returns void
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_owner text; v_run bigint;
  v_reg int; v_cust int; v_inq7 int; v_q7 int; v_deals int; v_rev numeric;
  v_pend int; v_kyc int; v_refunds int; v_reviews int;
  v_hot int; v_gap int; v_newsup int; v_newcust int;
  v_bd_q int; v_bd_sent int; v_chat_open int; v_viol int;
  v_officer text; v_health jsonb;
  v_topcats text; v_qpr numeric; v_conv numeric;
  v_expired int; v_crit int; v_decisions text; v_dn int := 0;
  v_body text; v_subj text;
  v_auto_cleared int; v_auto_appr int; v_handled text;   -- Phase B additions
begin
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';
  if v_owner is null then v_owner := 'management@quotesdone.com'; end if;
  insert into agent_runs(agent, started_at) values ('brief', now()) returning id into v_run;

  begin select coalesce(registered_supplier_count(),0) into v_reg; exception when others then v_reg := 0; end;
  select count(*) into v_cust from customers;
  select count(*) into v_inq7 from inquiries where created_at >= now()-interval '7 days';
  select count(*) into v_q7 from quotes where created_at >= now()-interval '7 days';
  select count(*) into v_deals from transactions;
  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where coalesce(fee_status,'')<>'refunded' and coalesce(refund_status,'')<>'approved';
  select count(*) into v_pend from agent_actions where status in ('pending','held_for_review','proposed','open','needs_review');
  select count(*) into v_kyc from leads where approval_status='pending';
  select count(*) into v_refunds from transactions where refund_status='requested';
  select count(*) into v_reviews from inbound_messages where needs_review=true;
  select count(distinct i.id) into v_hot from inquiries i join quotes q on q.inquiry_id=i.id left join transactions t on t.inquiry_id=i.id where t.id is null and i.status not in ('completed','accepted','closed','cancelled');
  select count(*) into v_gap from inquiries i where i.status not in ('completed','accepted','closed','cancelled') and not exists (select 1 from inquiry_matches m where m.inquiry_id=i.id);
  select count(*) into v_newsup from leads where registration_submitted_at >= now()-interval '7 days';
  select count(*) into v_newcust from customers where created_at >= now()-interval '7 days';
  select count(*) into v_bd_q from outreach where status='queued';
  select count(*) into v_bd_sent from outreach where status='sent';
  select count(*) into v_chat_open from chat_threads where status='open';
  select count(*) into v_viol from chat_violations where created_at >= now()-interval '7 days';

  begin select public.fn_health_index() into v_health; exception when others then v_health := null; end;

  begin
    select string_agg(cat,', ') into v_topcats from (
      select coalesce(nullif(category,''),'(uncategorized)') cat, count(*) n
      from inquiries where created_at>=now()-interval '7 days'
      group by 1 order by n desc limit 3) z;
  exception when others then v_topcats := null; end;

  begin
    select round(avg(qc),1) into v_qpr from (
      select count(*) qc from quotes q join inquiries i on i.id=q.inquiry_id
      where i.created_at>=now()-interval '30 days' group by q.inquiry_id) z;
  exception when others then v_qpr := null; end;
  begin
    select round(100.0*count(distinct t.inquiry_id)/nullif(count(distinct i.id),0),1) into v_conv
    from inquiries i left join transactions t on t.inquiry_id=i.id
    where i.created_at>=now()-interval '30 days';
  exception when others then v_conv := null; end;

  begin select count(*) into v_expired from leads where license_expiry is not null and license_expiry < current_date and coalesce(approval_status,'')='approved'; exception when others then v_expired:=0; end;
  select count(*) into v_crit from founder_alerts where level='critical' and created_at>=now()-interval '24 hours';

  begin
    select string_agg('- ['||label||'] '||act, E'\n')
    into v_officer
    from (
      select case er.officer
               when 'strategy' then 'Strategy' when 'operations' then 'Ops'
               when 'procurement_quality' then 'Quality' when 'data_science' then 'Data'
               when 'product_ux' then 'Product' when 'competitive' then 'Compete' else er.officer end as label,
             left(coalesce(rec->>'action',''),160) as act,
             case lower(coalesce(rec->>'impact','')) when 'high' then 0 when 'medium' then 1 else 2 end as ord
      from (select distinct on (officer) officer, recommendations, created_at from exec_reports order by officer, created_at desc) er,
           lateral jsonb_array_elements(er.recommendations) rec
      where coalesce(rec->>'action','') <> ''
      order by ord, label limit 5
    ) z;
  exception when others then v_officer := null; end;

  -- Phase B: what the Chief of Staff handled autonomously in the last 24h.
  select count(*) into v_auto_cleared from agent_actions
    where decided_by='chief_of_staff (auto)' and decided_at >= now()-interval '24 hours';
  begin
    select count(*) into v_auto_appr from leads
      where approval_decided_by='chief_of_staff (auto)' and approved_at >= now()-interval '24 hours';
  exception when others then v_auto_appr := 0; end;
  begin
    select string_agg('- '||type||': '||n, E'\n' order by n desc)
      into v_handled
    from (select type, count(*) n from notifications
          where status='digest' and created_at >= now()-interval '24 hours'
          group by type) z;
  exception when others then v_handled := null; end;

  v_decisions := '';
  if v_kyc > 0 then v_dn:=v_dn+1; v_decisions := v_decisions||v_dn||'. Approve/deny '||v_kyc||' supplier KYC application(s)'||E'\n'; end if;
  if v_refunds > 0 then v_dn:=v_dn+1; v_decisions := v_decisions||v_dn||'. Resolve '||v_refunds||' refund request(s)'||E'\n'; end if;
  if v_expired > 0 then v_dn:=v_dn+1; v_decisions := v_decisions||v_dn||'. Review '||v_expired||' supplier(s) with EXPIRED trade licence'||E'\n'; end if;
  if v_crit > 0 then v_dn:=v_dn+1; v_decisions := v_decisions||v_dn||'. Address '||v_crit||' critical alert(s) raised in last 24h'||E'\n'; end if;
  if v_dn = 0 then v_decisions := 'None outstanding.'||E'\n'; end if;

  v_subj := 'QuotesDone daily brief — '||to_char(now() at time zone 'Asia/Dubai','Dy DD Mon');
  v_body :=
    'Good morning. Here is your QuotesDone snapshot.'||E'\n\n'||
    'HANDLED FOR YOU (last 24h): auto-cleared '||v_auto_cleared||' routine item(s)'||
      case when v_auto_appr>0 then ', auto-approved '||v_auto_appr||' licence-clean supplier(s)' else '' end||'.'||
      case when v_handled is not null then E'\n'||v_handled else '' end||E'\n\n'||
    'MARKETPLACE HEALTH: '||coalesce(v_health->>'index','—')||'/100 ('||coalesce(v_health->>'band','no data')||')'||
      case when coalesce(v_health->>'note','')<>'' then '  — '||(v_health->>'note') else '' end||E'\n\n'||
    'NEEDS YOU TODAY'||E'\n'||
    '- Approvals waiting: '||v_pend||' (incl. '||v_kyc||' supplier KYC)'||E'\n'||
    '- Refund requests: '||v_refunds||E'\n'||
    '- Inbound emails to review: '||v_reviews||E'\n'||
    '- Hot leads (quotes in, not revealed): '||v_hot||E'\n'||
    '- Supply gaps (demand, no supplier matched): '||v_gap||E'\n'||
    '- Chat: '||v_chat_open||' open, '||v_viol||' policy flag(s) this week'||E'\n\n'||
    'THIS WEEK'||E'\n'||
    '- New inquiries: '||v_inq7||'  ·  quotes: '||v_q7||E'\n'||
    '- Avg quotes/RFQ (30d): '||coalesce(v_qpr::text,'—')||'  ·  Conversion (30d): '||coalesce(v_conv::text,'—')||'%'||E'\n'||
    '- New customers: '||v_newcust||'  ·  new supplier registrations: '||v_newsup||E'\n'||
    '- Deals (reveals) all-time: '||v_deals||'  ·  revenue recognized: AED '||round(v_rev)||E'\n'||
    '- Top categories (7d): '||coalesce(v_topcats,'—')||E'\n\n'||
    'GROWTH'||E'\n'||
    '- Suppliers registered: '||v_reg||'  ·  BD invites queued: '||v_bd_q||'  ·  sent: '||v_bd_sent||E'\n'||
    case when v_officer is not null and v_officer <> '' then E'\n'||'OFFICER PRIORITIES (from weekly analysis)'||E'\n'||v_officer||E'\n' else '' end ||
    E'\n'||'DECISIONS NEEDED'||E'\n'||v_decisions||
    E'\n'||'Open your dashboard: https://quotesdone.com/os  (Ops for live status; Governance for officer reports).';

  insert into notifications(type,to_email,to_role,channel,subject,body) values ('founder_brief',v_owner,'admin','email',v_subj,v_body);

  -- drain the parked ops-alerts now that they are reported in this brief
  update notifications set status='digested' where status='digest' and created_at <= now();

  update agent_runs set finished_at=now(), status='ok', counts=jsonb_build_object('approvals',v_pend,'hot',v_hot,'gaps',v_gap,'bd_queued',v_bd_q,'kyc',v_kyc,'health',(v_health->>'index'),'decisions',v_dn,'auto_cleared_24h',v_auto_cleared) where id=v_run;
end;$function$;

-- (c) One morning brief: retire the redundant second daily digest email.
-- fn_autonomy_dispose still runs hourly (autonomy_dispose_hourly); fn_chief_of_staff stays callable on demand.
select cron.unschedule('chief_of_staff_daily');
