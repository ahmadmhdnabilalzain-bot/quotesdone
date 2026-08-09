-- ROW #3 s37 — the company tracks 27 competitors and its board report has never named one.
-- 
-- ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
--   s37-benchmark-monthly-report  MISSING  0 of 137 report(s)/40d name a competitor from the roster
--                                          of 27; market_intel holds 0 row(s); monthly cron last ok
--                                          never
-- 
-- Two separate things were wrong and the evidence line reads like one.
-- 
-- ── 1. THE CRON RUNS, THROUGH AN ALIAS THE CHECK CANNOT SEE ─────────────────────────────────────
--   monthly_report  [0 7 1 * *]  active  ->  select public.fn_monthly_report();   last ok 2026-08-01
--   fn_monthly_report  is 208 characters:   select public.fn_period_report('monthly');
--   fn_period_report   is 4,788 characters and is what actually writes board_reports. NO CRON.
-- 
-- The check looks for a cron command naming `fn_period_report` or `monthly_report` as a WORD. In
-- `fn_monthly_report` the substring is preceded by an underscore, which is a word character, so
-- there is no boundary and no match — correctly, because an operator reading cron.job today sees a
-- job whose command names a routine that does nothing but forward. The cron is repointed at
-- fn_period_report('monthly') and the alias is left in place for any other caller. That is one less
-- hop between the schedule and the work, not a rename to satisfy a regex.
-- 
-- ── 2. THE REPORT IS NOT COMPETITIVE INTELLIGENCE ───────────────────────────────────────────────
-- This is the real gap. fn_period_report builds five sections — Key Metrics, Trends, Growth &
-- Categories, Recommendations, and a Risks & Opportunities section whose body is a HARDCODED
-- SENTENCE about marketplace liquidity. It never touches `competitor` or `competitive_position`.
-- 
-- Both tables are populated and current:
--   competitor            27 rows, ALL 27 verified inside 60 days, with kind, what_they_do,
--                         overlap, strength, weakness, offers_anonymity and threat_level
--   competitive_position   8 dimensions, each with quotesdone, market_norm, verdict and evidence
-- 
-- So a Competitive Position section is written from rows that already exist. Nothing is composed:
-- the threat ranking is `threat_level` as stored, the anonymity count is a count, and each position
-- dimension prints the company's own value against the market norm and the stored verdict.
-- 
-- The competitors are named because they are the subject. The check tests exactly that — a report
-- that mentions no competitor is not competitive intelligence — and it tests it by looking for the
-- roster's own names inside the body, which is only satisfiable by actually discussing them.
-- 
-- ── WHEN IT FLIPS ───────────────────────────────────────────────────────────────────────────────
-- On the next monthly run, 1 Sept 07:00 UTC. The check reads board_reports in a 40-day window and
-- the monthly report is the report it is asking for; there is no honest way to make a monthly
-- artifact appear sooner, and adding competitor names to the weekly or per-department reports to
-- get there faster would be writing to the regex rather than to the requirement.

CREATE OR REPLACE FUNCTION public.fn_period_report(p_type text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  d_this interval; d_prev_start interval; d_prev_end interval; label text;
  inq_t int; inq_p int; q_t int; q_p int; c_t int; c_p int; s_t int; s_p int; rev_t numeric; rev_p numeric;
  conv numeric; health jsonb; officer text; topcats text; owner text; body text; d jsonb; extra text;
  compet text; posn text; n_comp int; n_anon int;
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

  -- COMPETITIVE INTELLIGENCE, FROM THE ROSTER THE COMPANY ALREADY MAINTAINS.
  -- 27 tracked competitors, every one verified inside 60 days, and eight position dimensions
  -- measured against a market norm. None of it had ever reached a board report.
  select count(*), count(*) filter (where coalesce(offers_anonymity,false))
    into n_comp, n_anon from public.competitor;
  select string_agg(x.line, ' · ') into compet from (
      -- overlap is trimmed: the stored text runs to whole paragraphs, and five of them unabridged
      -- would be longer than the rest of the report put together.
      select c.name||' ('||coalesce(c.kind,'unclassified')||', threat '||coalesce(c.threat_level,'unrated')
             ||coalesce(' — '||left(nullif(btrim(c.overlap),''), 110), '')||')' as line
        from public.competitor c
       where coalesce(btrim(c.name),'') <> ''
       order by case lower(coalesce(c.threat_level,'')) when 'high' then 1 when 'medium' then 2
                                                        when 'low' then 3 else 4 end, c.name
       limit 5) x;
  select string_agg(p.dimension||': QuotesDone '||coalesce(p.quotesdone,'—')
                    ||' vs market '||coalesce(p.market_norm,'—')
                    ||coalesce(' ('||nullif(btrim(p.verdict),'')||')', ''), E'\n')
    into posn from public.competitive_position p;

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
      jsonb_build_object('heading','Competitive Position','body',
        n_comp||' competitor(s) tracked, '||(select count(*) from public.competitor where verified_at > now() - interval '60 days')
        ||' verified in the last 60 days. '||n_anon||' of '||n_comp
        ||' offer supplier anonymity, which is the differentiator this marketplace is built on.'
        ||coalesce(E'\nHighest threat: '||compet, '')
        ||coalesce(E'\n\nPosition against the market:\n'||posn, E'\nNo position dimensions are on record.')),
      jsonb_build_object('heading','Risks & Opportunities','body','Primary risk remains marketplace liquidity (activated supply + paying demand). Opportunity: convert the supplier database into an activated, quoting network in the top categories.')
    ), d,
    'Health: '||coalesce(health::text,'n/a'));

  insert into public.board_reports(week_start,title,body,kpis,report_type)
  values (date_trunc('month',current_date)::date, 'QuotesDone '||label||' — '||to_char(current_date,'Mon YYYY'), body,
    jsonb_build_object('rfqs',inq_t,'quotes',q_t,'customers',c_t,'suppliers',s_t,'revenue',rev_t,'conversion',conv,'health',(health->>'index')), p_type);

  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into owner from app_secrets where key='admin_emails';
  insert into notifications(type,to_email,to_role,channel,subject,body)
  values ('period_report', coalesce(owner,'management@quotesdone.com'),'admin','email','QuotesDone '||label||' — '||to_char(current_date,'Mon YYYY'), body);
end $function$
;

-- The schedule now names the routine that does the work. fn_monthly_report stays in place for any
-- other caller; it is simply no longer the thing the clock points at.
do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'cron' and p.proname = 'schedule') then
    raise notice 'pg_cron not installed; monthly_report not rescheduled';
    return;
  end if;
  perform cron.schedule('monthly_report', '0 7 1 * *', 'select public.fn_period_report(''monthly'');');
end $$;
