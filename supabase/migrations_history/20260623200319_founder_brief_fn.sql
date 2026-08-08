-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623200319   name: founder_brief_fn
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create or replace function fn_founder_brief() returns void language plpgsql security definer as $$
declare
  v_owner text; v_run bigint;
  v_reg int; v_cust int; v_inq7 int; v_q7 int; v_deals int; v_rev numeric;
  v_pend int; v_kyc int; v_refunds int; v_reviews int;
  v_hot int; v_gap int; v_newsup int; v_newcust int;
  v_bd_q int; v_bd_sent int; v_chat_open int; v_viol int;
  v_body text; v_subj text;
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
  select count(*) into v_pend from agent_actions where status='pending';
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

  v_subj := 'QuotesDone daily brief — '||to_char(now() at time zone 'Asia/Dubai','Dy DD Mon');
  v_body :=
    'Good morning. Here is your QuotesDone snapshot.'||E'\n\n'||
    'NEEDS YOU TODAY'||E'\n'||
    '- Approvals waiting: '||v_pend||' (incl. '||v_kyc||' supplier KYC)'||E'\n'||
    '- Refund requests: '||v_refunds||E'\n'||
    '- Inbound emails to review: '||v_reviews||E'\n'||
    '- Hot leads (quotes in, not revealed): '||v_hot||E'\n'||
    '- Supply gaps (demand, no supplier matched): '||v_gap||E'\n'||
    '- Chat: '||v_chat_open||' open, '||v_viol||' policy flag(s) this week'||E'\n\n'||
    'THIS WEEK'||E'\n'||
    '- New inquiries: '||v_inq7||'  ·  quotes: '||v_q7||E'\n'||
    '- New customers: '||v_newcust||'  ·  new supplier registrations: '||v_newsup||E'\n'||
    '- Deals (reveals) all-time: '||v_deals||'  ·  revenue recognized: AED '||round(v_rev)||E'\n\n'||
    'GROWTH'||E'\n'||
    '- Suppliers registered: '||v_reg||'  ·  BD invites queued: '||v_bd_q||'  ·  sent: '||v_bd_sent||E'\n\n'||
    'Open your dashboard: https://quotesdone.com/admin  (Agents tab to chat any agent).';

  insert into notifications(type,to_email,to_role,channel,subject,body) values ('founder_brief',v_owner,'admin','email',v_subj,v_body);
  update agent_runs set finished_at=now(), status='ok', counts=jsonb_build_object('approvals',v_pend,'hot',v_hot,'gaps',v_gap,'bd_queued',v_bd_q,'kyc',v_kyc) where id=v_run;
end;$$;

