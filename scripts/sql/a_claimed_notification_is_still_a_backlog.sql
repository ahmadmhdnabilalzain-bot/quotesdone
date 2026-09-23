-- A CLAIMED NOTIFICATION IS STILL A BACKLOG (22 Sep 2026, it_engineer, CONN-03 follow-through).
--
-- THE FAILURE MODE THIS CLOSES, found by independent review of PR #856 before it was applied.
-- fn_notifications_claim (a_queued_notification_is_claimed_before_it_is_sent.sql) moves a row to
-- 'sending' while a sender holds it, and the ONLY thing that requeues an expired claim is that same
-- function — which means a SENDER. So in exactly the case the backlog alarm exists for, a sender that
-- is down, rows accumulate in 'sending', nothing puts them back to 'queued', and every guard that
-- reads `status = 'queued'` counts zero and reports health. The claim would have made the estate's
-- oldest quiet failure — mail piling up with no signal anywhere — invisible again.
--
-- This is the lens the estate already has a name for: zero cannot tell a dead guard from an idle
-- system. The fix is not to weaken the claim; it is to make the guard count a claimed row as what it
-- is — mail that has not gone.
--
-- WHAT CHANGES. One condition in fn_smoke's email_backlog_stuck check. A row is legitimately in
-- 'sending' for the seconds of one send, and fn_notifications_claim requeues any claim older than
-- five minutes, so at the two-hour bar this check uses, 'sending' can only mean stuck. Everything
-- else in fn_smoke is byte-for-byte what it was, including the 6 Sep 2026 email-only narrowing.
--
-- STILL OPEN, named so it is not lost: fn_ops_dashboard's queue_size gauge reads
-- `coalesce(status,'') in ('queued','pending','')` and will under-report by whatever is claimed. It is
-- a display number, not an alarm, so it is a follow-up rather than part of this correction.

create or replace function public.fn_smoke()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_run bigint; v_owner text; v jsonb:='[]'::jsonb; v_fail int:=0; v_sig text;
  a int; b int; c int; d int; e int;
begin
  insert into agent_runs(agent,started_at) values('smoke',now()) returning id into v_run;
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';

  select count(*) into a from quotes q where q.status='revealed' and not exists(select 1 from transactions t where t.quote_id=q.id);
  if a>0 then v:=v||jsonb_build_object('check','revealed_quote_without_transaction','count',a); v_fail:=v_fail+1; end if;

  select count(*) into b from transactions where fee_status='paid' and coalesce(reveal_fee,0)<=0;
  if b>0 then v:=v||jsonb_build_object('check','paid_tx_zero_fee','count',b); v_fail:=v_fail+1; end if;

  -- 6 SEP 2026: EMAIL only. This counted the WhatsApp rows that wait on an unapproved Twilio template
  -- (the founder's input, not a broken write path) and paged him "data-integrity check failed" 20 times.
  -- 22 SEP 2026: 'sending' counts too — see the header. A claimed row whose sender never came back is
  -- the backlog this check exists to find, and it is the one shape it could not see.
  select count(*) into c from notifications where status in ('queued','sending') and channel='email' and created_at < now()-interval '2 hours';
  if c>0 then v:=v||jsonb_build_object('check','email_backlog_stuck','count',c); v_fail:=v_fail+1; end if;

  select count(*) into d from supplier_dues where coalesce(amount_due,0)<0 or amount_due is null;
  if d>0 then v:=v||jsonb_build_object('check','bad_due_amount','count',d); v_fail:=v_fail+1; end if;

  select count(*) into e from inquiries i where i.status='revealed' and not exists(select 1 from transactions t where t.inquiry_id=i.id);
  if e>0 then v:=v||jsonb_build_object('check','revealed_inquiry_without_tx','count',e); v_fail:=v_fail+1; end if;

  if v_fail>0 then
    insert into error_events(source,kind,severity,detail) values('smoke','integrity_violation','high',v);
    select coalesce(string_agg(x->>'check', ',' order by x->>'check'),'') into v_sig from jsonb_array_elements(v) x;
    if v_owner is not null and not exists(
         select 1 from notifications where type='smoke_alert'
           and created_at >= now() - interval '24 hours'
           and body like '%[sig:'||v_sig||']%') then
      insert into notifications(type,to_email,to_role,channel,subject,body)
        values('smoke_alert',v_owner,'admin','email','QuotesDone: data-integrity check failed',
          v_fail||' integrity check(s) failed: '||v::text||'. This usually means a recent change broke a write path. Open the IT agent. [sig:'||v_sig||']');
    end if;
  end if;
  update agent_runs set finished_at=now(),status='ok',counts=jsonb_build_object('checks',5,'failures',v_fail,'detail',v) where id=v_run;
  return jsonb_build_object('checks',5,'failures',v_fail,'detail',v);
end; $function$;

revoke execute on function public.fn_smoke() from public, anon, authenticated;
