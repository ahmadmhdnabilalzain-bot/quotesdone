-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706104613   name: ops_dashboard_data
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ LEVEL 1: live ops dashboard data ============
create or replace function public.fn_ops_dashboard()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
  active_rfqs int; rfqs_today int; done_today int; ttfq numeric; qpr numeric;
  accept_rate numeric; conv numeric;
  rev_today numeric; rev_month numeric; pending_fees numeric; outstanding_inv int; cash_recv numeric;
  ai_conf numeric; waiting int; onboard_q int; disputes int; escalations int;
  uptime numeric; queue_size int; failed int; last_backup timestamptz; api_lat numeric;
  health jsonb;
begin
  -- MARKETPLACE
  select count(*) into active_rfqs from inquiries where status not in ('completed','accepted','closed','cancelled');
  select count(*) into rfqs_today from inquiries where created_at::date=current_date;
  select count(*) into done_today from inquiries where (completed_at::date=current_date) or (status in ('completed','accepted') and stage_changed_at::date=current_date);
  select round(avg(extract(epoch from (fq - ic))/3600.0),1) into ttfq from (
    select i.created_at ic, min(q.created_at) fq from inquiries i join quotes q on q.inquiry_id=i.id
    where i.created_at>=now()-interval '30 days' group by i.id) z where fq is not null;
  select round(avg(qc),1) into qpr from (select count(*) qc from quotes q join inquiries i on i.id=q.inquiry_id where i.created_at>=now()-interval '30 days' group by q.inquiry_id) z;
  select round(avg(nullif(rv_response_rate,0)) ,1) into accept_rate from leads where coalesce(rv_reveals,0)>0;
  select round(100.0*count(distinct t.inquiry_id)/nullif(count(distinct i.id),0),1) into conv
    from inquiries i left join transactions t on t.inquiry_id=i.id where i.created_at>=now()-interval '30 days';

  -- REVENUE
  select coalesce(sum(reveal_fee),0) into rev_today from transactions where revealed_at::date=current_date and coalesce(refund_status,'')<>'approved';
  select coalesce(sum(reveal_fee),0) into rev_month from transactions where date_trunc('month',revealed_at)=date_trunc('month',now()) and coalesce(refund_status,'')<>'approved';
  begin select coalesce(sum(amount_due),0) into pending_fees from supplier_dues where coalesce(status,'')<>'paid'; exception when others then pending_fees:=0; end;
  begin select count(*) into outstanding_inv from reveal_invoices ri left join transactions t on t.id=ri.transaction_id where coalesce(t.fee_status,'')<>'paid'; exception when others then outstanding_inv:=0; end;
  select coalesce(sum(reveal_fee),0) into cash_recv from transactions where coalesce(fee_status,'')='paid';

  -- OPERATIONS
  begin select public.fn_health_index() into health; exception when others then health:=null; end;
  select round(100.0*count(*) filter (where nullif(quality->>'score','')::numeric>=60)/nullif(count(*) filter (where quality is not null),0),1) into ai_conf
    from quotes where created_at>=now()-interval '7 days';
  select count(*) into waiting from inquiries where status in ('clarify','clarifying','awaiting_customer','needs_info');
  select count(*) into onboard_q from leads where approval_status='pending';
  select count(*) into disputes from transactions where refund_status='requested';
  select (select count(*) from agent_actions where status='pending')
        + (select count(*) from founder_alerts where level='critical' and created_at>=now()-interval '24 hours') into escalations;

  -- INFRASTRUCTURE
  select round(100.0*count(*) filter (where ok)/nullif(count(*),0),1) into uptime from health_checks where created_at>=now()-interval '24 hours';
  select count(*) into queue_size from notifications where coalesce(status,'')in('queued','pending','');
  begin select count(*) into failed from agent_runs where status='error' and coalesce(finished_at,started_at)>=now()-interval '24 hours'; exception when others then failed:=0; end;
  select max(updated_at) into last_backup from storage.objects where bucket_id='backups' and name like '%/_manifest.json';
  select round(avg(latency_ms),0) into api_lat from health_checks where created_at>=now()-interval '1 hour' and latency_ms is not null;

  return jsonb_build_object(
    'as_of', now(),
    'marketplace', jsonb_build_object('active_rfqs',active_rfqs,'rfqs_today',rfqs_today,'completed_today',done_today,
        'avg_hours_to_first_quote',ttfq,'avg_quotes_per_rfq',qpr,'supplier_acceptance_pct',accept_rate,'conversion_pct',conv),
    'revenue', jsonb_build_object('today_aed',rev_today,'month_aed',rev_month,'pending_fees_aed',pending_fees,
        'outstanding_invoices',outstanding_inv,'cash_received_aed',cash_recv),
    'operations', jsonb_build_object('ai_confidence_pct',ai_conf,'rfqs_waiting_clarification',waiting,
        'onboarding_queue',onboard_q,'disputes',disputes,'escalations',escalations),
    'infrastructure', jsonb_build_object('uptime_pct',uptime,'queue_size',queue_size,'failed_jobs_24h',failed,
        'backup_age_hours', case when last_backup is null then null else round(extract(epoch from (now()-last_backup))/3600.0,1) end,
        'api_latency_ms',api_lat),
    'health_index', coalesce(health->>'index',null));
end $$;

select jsonb_pretty(public.fn_ops_dashboard());
