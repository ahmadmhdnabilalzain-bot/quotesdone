-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706115731   name: monthly_quarterly_reports
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.board_reports add column if not exists report_type text default 'weekly';

-- generic period report builder (monthly / quarterly)
create or replace function public.fn_period_report(p_type text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare
  d_this interval; d_prev_start interval; d_prev_end interval; label text;
  inq_t int; inq_p int; q_t int; q_p int; c_t int; c_p int; s_t int; s_p int; rev_t numeric; rev_p numeric;
  conv numeric; health jsonb; officer text; topcats text; owner text; body text; d jsonb; extra text;
begin
  if p_type='monthly' then d_this:='30 days'; d_prev_start:='60 days'; d_prev_end:='30 days'; label:='Monthly Business Report';
  else d_this:='90 days'; d_prev_start:='180 days'; d_prev_end:='90 days'; label:='Quarterly Strategy Report'; end if;

  select count(*) filter (where created_at>=now()-d_this), count(*) filter (where created_at>=now()-d_prev_start and created_at<now()-d_prev_end) into inq_t,inq_p from inquiries;
  select count(*) filter (where created_at>=now()-d_this), count(*) filter (where created_at>=now()-d_prev_start and created_at<now()-d_prev_end) into q_t,q_p from quotes;
  select count(*) filter (where created_at>=now()-d_this), count(*) filter (where created_at>=now()-d_prev_start and created_at<now()-d_prev_end) into c_t,c_p from customers;
  select count(*) filter (where registration_submitted_at>=now()-d_this), count(*) filter (where registration_submitted_at>=now()-d_prev_start and registration_submitted_at<now()-d_prev_end) into s_t,s_p from leads;
  select coalesce(sum(reveal_fee) filter (where revealed_at>=now()-d_this),0), coalesce(sum(reveal_fee) filter (where revealed_at>=now()-d_prev_start and revealed_at<now()-d_prev_end),0) into rev_t,rev_p from transactions where coalesce(refund_status,'')<>'approved';
  select round(100.0*count(distinct t.inquiry_id)/nullif(count(distinct i.id),0),1) into conv from inquiries i left join transactions t on t.inquiry_id=i.id where i.created_at>=now()-d_this;
  begin select public.fn_health_index() into health; exception when others then health:=null; end;
  select string_agg(cat,', ') into topcats from (select coalesce(nullif(category,''),'(uncat)') cat, count(*) n from inquiries where created_at>=now()-d_this group by 1 order by n desc limit 6) z;
  officer := public.fn_officer_recs(10);

  d := jsonb_build_array();
  if rev_t < rev_p then d := d||to_jsonb('Revenue down vs prior period — review demand and conversion'::text); end if;
  if inq_t < inq_p then d := d||to_jsonb('RFQ volume down vs prior period — assess top-of-funnel'::text); end if;
  if p_type='quarterly' then d := d||to_jsonb('Set next-quarter category focus and supply-activation targets'::text); end if;

  extra := 'RFQs '||inq_t||' (prev '||inq_p||') · Quotes '||q_t||' (prev '||q_p||') · New customers '||c_t||' (prev '||c_p||') · New suppliers '||s_t||' (prev '||s_p||') · Revenue AED '||round(rev_t)||' (prev AED '||round(rev_p)||')';

  body := public.fn_report_skeleton(
    'QuotesDone '||label||' — '||to_char(current_date,'Mon YYYY'),
    'Marketplace health '||coalesce(health->>'index','—')||'/100. Period totals: '||inq_t||' RFQs, '||q_t||' quotes, revenue AED '||round(rev_t)||', 30-day conversion '||coalesce(conv::text,'—')||'%.',
    jsonb_build_array(
      jsonb_build_object('heading','Key Metrics','body',extra),
      jsonb_build_object('heading','Trends (period over period)','body','Demand '||inq_t||' vs '||inq_p||' · Revenue AED '||round(rev_t)||' vs '||round(rev_p)||' · Suppliers +'||s_t||' vs +'||s_p),
      jsonb_build_object('heading','Growth & Categories','body','Top categories: '||coalesce(topcats,'—')),
      jsonb_build_object('heading',case when p_type='quarterly' then 'Strategy & Recommendations' else 'Recommendations' end,'body',coalesce(officer,'No officer recommendations yet.')),
      jsonb_build_object('heading','Risks & Opportunities','body','Primary risk remains marketplace liquidity (activated supply + paying demand). Opportunity: convert the supplier database into an activated, quoting network in the top categories.')
    ), d,
    'Health: '||coalesce(health::text,'n/a'));

  insert into public.board_reports(week_start,title,body,kpis,report_type)
  values (date_trunc('month',current_date)::date, 'QuotesDone '||label||' — '||to_char(current_date,'Mon YYYY'), body,
    jsonb_build_object('rfqs',inq_t,'quotes',q_t,'customers',c_t,'suppliers',s_t,'revenue',rev_t,'conversion',conv,'health',(health->>'index')), p_type);

  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into owner from app_secrets where key='admin_emails';
  insert into notifications(type,to_email,to_role,channel,subject,body)
  values ('period_report', coalesce(owner,'management@quotesdone.com'),'admin','email','QuotesDone '||label||' — '||to_char(current_date,'Mon YYYY'), body);
end $$;

create or replace function public.fn_monthly_report() returns void language sql security definer set search_path=public,pg_temp as $$ select public.fn_period_report('monthly'); $$;
create or replace function public.fn_quarterly_report() returns void language sql security definer set search_path=public,pg_temp as $$ select public.fn_period_report('quarterly'); $$;

select cron.schedule('monthly_report','0 7 1 * *', $$select public.fn_monthly_report();$$);
select cron.schedule('quarterly_report','0 8 1 1,4,7,10 *', $$select public.fn_quarterly_report();$$);

select public.fn_monthly_report();
select report_type, left(title,50) title from board_reports order by id desc limit 1;
