-- Contract: measure_sql is a complete SELECT returning ONE row, ONE numeric column.
-- NULL is a legitimate result and means "no data in the window", not "zero".

update employee_kpi set measure_sql = case metric

  when 'Platform availability' then
    $q$select round(100.0*count(*) filter (where ok)/nullif(count(*),0),2) from health_checks where created_at > now()-interval '7 days'$q$

  when 'RFQs reaching at least one submitted quote' then
    $q$select round(100.0*count(*) filter (where exists(select 1 from quotes q where q.inquiry_id=i.id))/nullif(count(*),0),2) from inquiries i where i.created_at > now()-interval '30 days'$q$
  when 'Inquiries reaching at least one submitted quote' then
    $q$select round(100.0*count(*) filter (where exists(select 1 from quotes q where q.inquiry_id=i.id))/nullif(count(*),0),2) from inquiries i where i.created_at > now()-interval '30 days'$q$

  when 'Customer issues resolved within SLA' then
    $q$select round(100.0*count(*) filter (where sent_at is not null and sent_at-created_at < interval '24 hours')/nullif(count(*),0),2) from notifications where created_at > now()-interval '7 days'$q$
  when 'Responses within the published SLA' then
    $q$select round(100.0*count(*) filter (where sent_at is not null and sent_at-created_at < interval '24 hours')/nullif(count(*),0),2) from notifications where created_at > now()-interval '7 days'$q$

  when 'Output passing brand review first time' then
    $q$select round(100.0*count(*) filter (where decision='approve')/nullif(count(*),0),2) from review_chain where dept_key='marketing' and created_at > now()-interval '30 days'$q$
  when 'Share of published items passing brand review first time' then
    $q$select round(100.0*count(*) filter (where decision='approve')/nullif(count(*),0),2) from review_chain where dept_key='marketing' and created_at > now()-interval '30 days'$q$

  when 'Drafts returned for brand-voice revision' then
    $q$select round(100.0*count(*) filter (where decision<>'approve')/nullif(count(*),0),2) from review_chain where dept_key='marketing' and created_at > now()-interval '30 days'$q$
  when 'Creatives returned for brand-asset breach' then
    $q$select round(100.0*count(*) filter (where decision<>'approve')/nullif(count(*),0),2) from review_chain where dept_key='marketing' and created_at > now()-interval '30 days'$q$

  when 'Quality gate pass rate before ship' then
    $q$select round(100.0*count(*) filter (where passed)/nullif(count(*),0),2) from qa_results where run_at > now()-interval '7 days'$q$

  when 'Compliance checks completed before deadline' then
    $q$select round(100.0*count(*) filter (where present)/nullif(count(*),0),2) from legal_checklist$q$

  when 'Reporting and controls completed on time' then
    $q$select case when count(*)>0 then 100 else 0 end::numeric from finance_reports where created_at > now()-interval '30 days'$q$

  when 'Qualified pipeline created against plan' then
    $q$select round(100.0*count(*) filter (where rfq_ready)/nullif(count(*),0),2) from inquiries where created_at > now()-interval '30 days'$q$

  when 'Employees with complete KPI, authority and knowledge binding' then
    $q$select round(100.0*count(*) filter (where hk and ha and hn)/nullif(count(*),0),2) from (select a.agent_key, exists(select 1 from employee_kpi k where k.agent_key=a.agent_key) hk, exists(select 1 from employee_authority au where au.agent_key=a.agent_key) ha, exists(select 1 from employee_knowledge ek where ek.agent_key=a.agent_key) hn from org_agents a where a.active) x$q$

  when 'Company goals with active work and no red status' then
    $q$select round(100.0*count(*) filter (where exists(select 1 from org_tasks t where t.dept_key=g.owner_dept and t.status<>'done'))/nullif(count(*),0),2) from company_goals g where g.active$q$
  when 'Goals having at least one open initiative' then
    $q$select round(100.0*count(*) filter (where exists(select 1 from org_tasks t where t.dept_key=g.owner_dept and t.status<>'done'))/nullif(count(*),0),2) from company_goals g where g.active$q$

  when 'Trailing 12-month recognised revenue' then
    $q$select coalesce(sum(coalesce(reveal_fee, app_fee, 0)),0)::numeric from transactions where revealed_at > now()-interval '12 months'$q$

  when 'Overdue supplier dues recovered within 30 days' then
    $q$select round(100.0*count(*) filter (where paid_at is not null and paid_at <= due_date_30)/nullif(count(*),0),2) from supplier_dues where reveal_date > now()-interval '30 days'$q$

  when 'Coverage across active supplier categories' then
    $q$select round(avg(n),2) from (select c.slug, count(lc.lead_id) n from catalog_supplier_categories c left join lead_category lc on lc.slug=c.slug group by c.slug) y$q$

  when 'Inquiries attributed to marketing channels' then
    $q$select count(*)::numeric from inquiries where created_at > now()-interval '30 days'$q$

  when 'Campaigns with a goal-linked performance report' then
    $q$select case when count(*)>0 then 100 else 0 end::numeric from marketing_snapshots where created_at > now()-interval '30 days'$q$

  when 'Planned pillars with live content' then
    $q$select count(*)::numeric from blog_posts where published$q$

  when 'Scheduled posts published on plan' then
    $q$select round(100.0*count(*) filter (where status='published')/nullif(count(*),0),2) from social_posts where created_at > now()-interval '7 days'$q$

  else measure_sql
end
where active;

-- Mirror the shared metrics onto the company goals they serve.
update company_goals g set measure_sql = k.measure_sql
from (select distinct on (serves_goal) serves_goal, measure_sql
      from employee_kpi where measure_sql is not null and serves_goal is not null
      order by serves_goal, id) k
where g.key = k.serves_goal and g.measure_sql is null;

comment on column employee_kpi.measure_sql is
  'Complete SELECT returning one row, one numeric column. NULL = no data in the window, not zero. Evaluated by fn_kpi_scoreboard().';