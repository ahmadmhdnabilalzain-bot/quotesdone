-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724075640   name: fn_smoke_returns_jsonb
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- fn_smoke now RETURNS jsonb so callers (qa_suite) can actually gate on the result.
-- Previously void -> PostgREST returned an empty body -> qa_suite's r.json() threw SyntaxError,
-- so payment/data-integrity invariants were never verified. Side effects are unchanged.
DROP FUNCTION IF EXISTS public.fn_smoke();
CREATE OR REPLACE FUNCTION public.fn_smoke()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_run bigint; v_owner text; v jsonb:='[]'::jsonb; v_fail int:=0; v_sig text;
  a int; b int; c int; d int; e int;
begin
  insert into agent_runs(agent,started_at) values('smoke',now()) returning id into v_run;
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';

  select count(*) into a from quotes q where q.status='revealed' and not exists(select 1 from transactions t where t.quote_id=q.id);
  if a>0 then v:=v||jsonb_build_object('check','revealed_quote_without_transaction','count',a); v_fail:=v_fail+1; end if;

  select count(*) into b from transactions where fee_status='paid' and coalesce(reveal_fee,0)<=0;
  if b>0 then v:=v||jsonb_build_object('check','paid_tx_zero_fee','count',b); v_fail:=v_fail+1; end if;

  select count(*) into c from notifications where status='queued' and channel<>'portal' and created_at < now()-interval '2 hours';
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
