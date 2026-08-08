-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706104234   name: weekly_board_report
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ LEVEL 3: standardized report skeleton + weekly board report ============
create table if not exists public.board_reports(
  id bigserial primary key, week_start date, title text, body text, kpis jsonb, created_at timestamptz default now());
alter table public.board_reports enable row level security;
revoke all on public.board_reports from anon, authenticated;

-- standard report template every report can use
create or replace function public.fn_report_skeleton(
  p_title text, p_exec text, p_sections jsonb, p_decisions jsonb, p_appendix text default null)
returns text language plpgsql immutable set search_path=public,pg_temp as $$
declare out text; s jsonb; d text; i int := 0;
begin
  out := p_title||E'\n'||repeat('=',length(p_title))||E'\n\n';
  out := out||'EXECUTIVE SUMMARY'||E'\n'||coalesce(p_exec,'—')||E'\n\n';
  for s in select * from jsonb_array_elements(coalesce(p_sections,'[]')) loop
     out := out||upper(coalesce(s->>'heading',''))||E'\n'||coalesce(s->>'body','')||E'\n\n';
  end loop;
  out := out||'DECISIONS REQUIRED'||E'\n';
  if jsonb_array_length(coalesce(p_decisions,'[]'))=0 then out := out||'None outstanding.'||E'\n';
  else for d in select jsonb_array_elements_text(p_decisions) loop i:=i+1; out := out||i||'. '||d||E'\n'; end loop; end if;
  if p_appendix is not null then out := out||E'\n'||'APPENDIX'||E'\n'||p_appendix||E'\n'; end if;
  return out;
end $$;

create or replace function public.fn_board_report()
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare
  inq_t int; inq_p int; q_t int; q_p int; c_t int; c_p int; s_t int; s_p int;
  rev_t numeric; rev_p numeric; conv numeric; qpr numeric;
  gap int; expired int; crit int; gatepass numeric;
  health jsonb; eval jsonb; officer text; topcats text;
  wtrend text; body text; owner text; d jsonb;
  fmt_delta text;
begin
  -- this week vs prior week
  select count(*) filter (where created_at>=now()-interval '7 days'),
         count(*) filter (where created_at>=now()-interval '14 days' and created_at<now()-interval '7 days')
    into inq_t, inq_p from inquiries;
  select count(*) filter (where created_at>=now()-interval '7 days'),
         count(*) filter (where created_at>=now()-interval '14 days' and created_at<now()-interval '7 days')
    into q_t, q_p from quotes;
  select count(*) filter (where created_at>=now()-interval '7 days'),
         count(*) filter (where created_at>=now()-interval '14 days' and created_at<now()-interval '7 days')
    into c_t, c_p from customers;
  select count(*) filter (where registration_submitted_at>=now()-interval '7 days'),
         count(*) filter (where registration_submitted_at>=now()-interval '14 days' and registration_submitted_at<now()-interval '7 days')
    into s_t, s_p from leads;
  select coalesce(sum(reveal_fee) filter (where revealed_at>=now()-interval '7 days'),0),
         coalesce(sum(reveal_fee) filter (where revealed_at>=now()-interval '14 days' and revealed_at<now()-interval '7 days'),0)
    into rev_t, rev_p from transactions where coalesce(refund_status,'')<>'approved';

  select round(100.0*count(distinct t.inquiry_id)/nullif(count(distinct i.id),0),1) into conv
    from inquiries i left join transactions t on t.inquiry_id=i.id where i.created_at>=now()-interval '30 days';
  select round(avg(qc),1) into qpr from (select count(*) qc from quotes q join inquiries i on i.id=q.inquiry_id where i.created_at>=now()-interval '30 days' group by q.inquiry_id) z;
  select count(*) into gap from inquiries i where i.status not in ('completed','accepted','closed','cancelled') and not exists(select 1 from inquiry_matches m where m.inquiry_id=i.id);
  begin select count(*) into expired from leads where license_expiry<current_date and coalesce(approval_status,'')='approved'; exception when others then expired:=0; end;
  select count(*) into crit from founder_alerts where level='critical' and created_at>=now()-interval '7 days';
  select round(100.0*count(*) filter (where nullif(quality->>'score','')::numeric>=60)/nullif(count(*) filter (where quality is not null),0),1) into gatepass
    from quotes where created_at>=now()-interval '7 days';
  begin select public.fn_health_index() into health; exception when others then health:=null; end;
  begin select public.fn_eval_snapshot(30) into eval; exception when others then eval:=null; end;
  select string_agg(cat,', ') into topcats from (select coalesce(nullif(category,''),'(uncat)') cat, count(*) n from inquiries where created_at>=now()-interval '7 days' group by 1 order by n desc limit 5) z;
  begin
    select string_agg('- ['||er.officer||'] '||left(coalesce(rec->>'action',''),150), E'\n') into officer
    from (select distinct on (officer) officer, recommendations from exec_reports order by officer, created_at desc) er,
         lateral jsonb_array_elements(er.recommendations) rec
    where coalesce(rec->>'action','')<>'' limit 8;
  exception when others then officer:=null; end;

  wtrend :=
    '- RFQs: '||inq_t||' (prev '||inq_p||')'||E'\n'||
    '- Quotes: '||q_t||' (prev '||q_p||')'||E'\n'||
    '- New customers: '||c_t||' (prev '||c_p||')'||E'\n'||
    '- New supplier registrations: '||s_t||' (prev '||s_p||')'||E'\n'||
    '- Revenue: AED '||round(rev_t)||' (prev AED '||round(rev_p)||')';

  d := jsonb_build_array();
  if expired>0 then d := d||to_jsonb('Review '||expired||' supplier(s) with expired trade licence'::text); end if;
  if crit>0 then d := d||to_jsonb('Address '||crit||' critical alert(s) from this week'::text); end if;
  if gap>0 then d := d||to_jsonb('Decide sourcing for '||gap||' unmatched demand item(s)'::text); end if;

  body := public.fn_report_skeleton(
    'QuotesDone Weekly Board Report — '||to_char(current_date,'DD Mon YYYY'),
    'Marketplace health '||coalesce(health->>'index','—')||'/100 ('||coalesce(health->>'band','no data')||'). '||
      inq_t||' RFQs and '||q_t||' quotes this week; revenue AED '||round(rev_t)||'; 30-day conversion '||coalesce(conv::text,'—')||'%.',
    jsonb_build_array(
      jsonb_build_object('heading','Key Metrics (this week)','body',
        'RFQs '||inq_t||' · Quotes '||q_t||' · Avg quotes/RFQ (30d) '||coalesce(qpr::text,'—')||' · Conversion (30d) '||coalesce(conv::text,'—')||'% · Revenue AED '||round(rev_t)||' · Quote-gate pass '||coalesce(gatepass::text,'—')||'%'),
      jsonb_build_object('heading','Trends (WoW)','body',wtrend),
      jsonb_build_object('heading','Growth','body','Top categories: '||coalesce(topcats,'—')),
      jsonb_build_object('heading','AI Performance','body','Health index '||coalesce(health->>'index','—')||'/100; eval sample '||coalesce(eval->'samples'->>'quotes','0')||' quotes, gate pass '||coalesce(gatepass::text,'—')||'%.'),
      jsonb_build_object('heading','Issues','body','Supply gaps: '||gap||' · Expired licences: '||expired||' · Critical alerts (7d): '||crit),
      jsonb_build_object('heading','Recommendations (officers)','body',coalesce(officer,'No officer recommendations available yet.'))
    ),
    d,
    'Health: '||coalesce(health::text,'n/a')||E'\n'||'Eval: '||coalesce(eval::text,'n/a'));

  insert into public.board_reports(week_start, title, body, kpis)
  values (date_trunc('week',current_date)::date,
          'QuotesDone Weekly Board Report — '||to_char(current_date,'DD Mon YYYY'),
          body,
          jsonb_build_object('rfqs',inq_t,'quotes',q_t,'customers',c_t,'suppliers',s_t,'revenue',rev_t,'conversion',conv,'gate_pass',gatepass,'health',(health->>'index')));

  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into owner from app_secrets where key='admin_emails';
  insert into notifications(type,to_email,to_role,channel,subject,body)
  values ('board_report', coalesce(owner,'management@quotesdone.com'),'admin','email',
          'QuotesDone Weekly Board Report — '||to_char(current_date,'DD Mon'), body);
end $$;

select cron.schedule('board_report_weekly','0 7 * * 1', $$select public.fn_board_report();$$);
select public.fn_board_report();
select left(body, 700) as sample from public.board_reports order by id desc limit 1;
