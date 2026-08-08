-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706180809   name: os_framework_workspaces
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- QuotesDone OS — workspace data layer. One function per workspace; os_api routes to these.
create or replace function fn_os_nav() returns jsonb language sql security definer stable as $$
  select jsonb_build_object(
    'badges', jsonb_build_object(
      'approvals', (select count(*) from agent_actions where status='pending'),
      'tasks', (select count(*) from crm_tasks where coalesce(status,'') <> 'done'),
      'suppliers_review', (select count(*) from leads where coalesce(approval_status,'') in ('submitted','pending','under_review','pending_review')),
      'notifications', (select count(*) from notifications where coalesce(status,'') not in ('sent','delivered','read')),
      'knowledge_review', (select count(*) from kb_revisions where coalesce(status,'')='pending'),
      'documents_review', (select count(*) from doc_reviews where coalesce(status,'')='pending'),
      'disputes', (select count(*) from transactions where coalesce(refund_status,'') in ('requested','pending')),
      'rfqs_active', (select count(*) from inquiries where coalesce(status,'') not in ('completed','cancelled','closed'))
    ),
    'generated_at', now()
  );
$$;

create or replace function fn_ws_exec() returns jsonb language sql security definer stable as $$
  select jsonb_build_object(
    'command', fn_os_command(),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'priority',priority,'due',due_date,'entity',entity)) from (select * from crm_tasks order by (coalesce(status,'')='done'), created_at desc limit 8) t),'[]'::jsonb),
    'approvals', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'title',title,'kind',kind,'risk',risk,'status',status,'created_at',created_at)) from (select * from agent_actions where status='pending' order by created_at desc limit 6) a),'[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object('actor',actor,'kind',kind,'decision',decision,'confidence',confidence,'route_to',route_to,'created_at',created_at)) from (select * from decision_log order by created_at desc limit 10) d),'[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(jsonb_build_object('type',type,'subject',subject,'status',status,'created_at',created_at)) from (select * from notifications order by created_at desc limit 6) n),'[]'::jsonb)
  );
$$;

create or replace function fn_ws_suppliers(p jsonb default '{}') returns jsonb language plpgsql security definer stable as $$
declare
  v_q text := nullif(trim(coalesce(p->>'q','')),'');
  v_emirate text := nullif(p->>'emirate','');
  v_sector text := nullif(p->>'sector','');
  v_approval text := nullif(p->>'approval','');
  v_limit int := least(coalesce((p->>'limit')::int,50),100);
  v_offset int := greatest(coalesce((p->>'offset')::int,0),0);
  v_rows jsonb; v_total bigint;
begin
  select count(*) into v_total from leads
   where (v_q is null or company_name ilike '%'||v_q||'%' or categories ilike '%'||v_q||'%')
     and (v_emirate is null or emirate=v_emirate)
     and (v_sector is null or sector=v_sector)
     and (v_approval is null or approval_status=v_approval);

  select coalesce(jsonb_agg(r),'[]'::jsonb) into v_rows from (
    select jsonb_build_object('id',id,'company_name',company_name,'sector',sector,'sub_type',sub_type,
      'emirate',emirate,'city',city,'rating',rating,'reviews',reviews,'categories',categories,
      'approval_status',approval_status,'lifecycle_stage',lifecycle_stage,'verified',verified,
      'verification_status',verification_status,'capability_score',capability_score,'invite_status',invite_status,
      'registration_status',registration_status,'license_expiry',license_expiry,'banned',banned,
      'matching_blocked',matching_blocked,'phone',phone,'website',website,'created_at',created_at) as r
    from leads
    where (v_q is null or company_name ilike '%'||v_q||'%' or categories ilike '%'||v_q||'%')
      and (v_emirate is null or emirate=v_emirate)
      and (v_sector is null or sector=v_sector)
      and (v_approval is null or approval_status=v_approval)
    order by capability_score desc nulls last, reviews desc nulls last
    limit v_limit offset v_offset
  ) x;

  return jsonb_build_object(
    'kpis', jsonb_build_object(
      'total',(select count(*) from leads),
      'approved',(select count(*) from leads where approval_status='approved'),
      'pending_review',(select count(*) from leads where coalesce(approval_status,'') in ('submitted','pending','under_review','pending_review')),
      'verified',(select count(*) from leads where verified is true),
      'registered',(select count(*) from leads where registration_paid_at is not null),
      'licenses_expiring',(select count(*) from leads where license_expiry is not null and license_expiry < (now()+interval '30 days')::date and license_expiry >= now()::date),
      'banned',(select count(*) from leads where banned is true),
      'matching_blocked',(select count(*) from leads where matching_blocked is true)
    ),
    'kanban', coalesce((select jsonb_agg(jsonb_build_object('key',stg,'count',c) order by c desc) from (
        select coalesce(nullif(lifecycle_stage,''),'directory') stg, count(*) c from leads group by 1 order by 2 desc limit 8) k),'[]'::jsonb),
    'sectors', coalesce((select jsonb_agg(jsonb_build_object('key',s,'count',c) order by c desc) from (
        select coalesce(nullif(sector,''),'other') s, count(*) c from leads group by 1 order by 2 desc limit 10) s),'[]'::jsonb),
    'emirates', coalesce((select jsonb_agg(jsonb_build_object('key',e,'count',c) order by c desc) from (
        select coalesce(nullif(emirate,''),'—') e, count(*) c from leads group by 1 order by 2 desc limit 10) e),'[]'::jsonb),
    'total', v_total, 'limit', v_limit, 'offset', v_offset, 'rows', v_rows
  );
end;
$$;

create or replace function fn_ws_marketplace() returns jsonb language sql security definer stable as $$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'rfqs',(select count(*) from inquiries),
      'active',(select count(*) from inquiries where coalesce(status,'') not in ('completed','cancelled','closed')),
      'quotes',(select count(*) from quotes),
      'avg_value',(select round(avg(expected_value)) from inquiries where expected_value is not null),
      'hired',(select count(*) from inquiries where hired_supplier_id is not null),
      'transactions',(select count(*) from transactions)
    ),
    'kanban', coalesce((select jsonb_agg(jsonb_build_object('key',stg,'count',c) order by c desc) from (
        select coalesce(nullif(pipeline_stage,''),coalesce(nullif(status,''),'new')) stg, count(*) c from inquiries group by 1) k),'[]'::jsonb),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id',id,'category',category,'emirate',emirate,'summary',summary,
        'status',status,'pipeline_stage',pipeline_stage,'deal_owner',deal_owner,'expected_value',expected_value,
        'budget',budget,'rfq_ready',rfq_ready,'created_at',created_at) ) from (select * from inquiries order by created_at desc limit 50) i),'[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id',id,'inquiry_id',inquiry_id,'supplier_id',supplier_id,
        'quote_amount',quote_amount,'customer_price',customer_price,'status',status,'created_at',created_at)) from (select * from quotes order by created_at desc limit 30) q),'[]'::jsonb)
  );
$$;

create or replace function fn_ws_customers() returns jsonb language sql security definer stable as $$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'total',(select count(*) from customers),
      'verified',(select count(*) from customers where phone_verified is true or email_verified is true),
      'banned',(select count(*) from customers where banned is true),
      'with_rfqs',(select count(distinct customer_id) from inquiries where customer_id is not null)
    ),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'full_name',c.full_name,'email',c.email,'phone',c.phone,
        'phone_verified',c.phone_verified,'email_verified',c.email_verified,'banned',c.banned,'created_at',c.created_at,
        'rfqs',(select count(*) from inquiries i where i.customer_id=c.id),
        'projects',(select count(*) from projects p where p.customer_id=c.id))) from (select * from customers order by created_at desc limit 100) c),'[]'::jsonb)
  );
$$;

create or replace function fn_ws_operations() returns jsonb language sql security definer stable as $$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'approvals_pending',(select count(*) from agent_actions where status='pending'),
      'high_risk',(select count(*) from agent_actions where status='pending' and coalesce(risk,'') in ('high','critical')),
      'tasks_open',(select count(*) from crm_tasks where coalesce(status,'')<>'done'),
      'decisions_24h',(select count(*) from decision_log where created_at > now()-interval '24 hours'),
      'disputes',(select count(*) from transactions where coalesce(refund_status,'') in ('requested','pending'))
    ),
    'approvals', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'kind',kind,'risk',risk,'title',title,
        'recommendation',recommendation,'status',status,'target_table',target_table,'created_at',created_at)) from (
        select * from agent_actions where status='pending' order by (coalesce(risk,'')='critical') desc, created_at desc limit 30) a),'[]'::jsonb),
    'decisions', coalesce((select jsonb_agg(jsonb_build_object('id',id,'actor',actor,'kind',kind,'decision',decision,
        'confidence',confidence,'route_to',route_to,'created_at',created_at)) from (select * from decision_log order by created_at desc limit 20) d),'[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'priority',priority,'due',due_date,'source',source,'entity',entity)) from (select * from crm_tasks order by (coalesce(status,'')='done'), created_at desc limit 20) t),'[]'::jsonb)
  );
$$;

create or replace function fn_ws_ai() returns jsonb language sql security definer stable as $$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'agents',(select count(*) from category_agents),
      'agents_active',(select count(*) from category_agents where active is true),
      'actions_total',(select count(*) from agent_actions),
      'actions_pending',(select count(*) from agent_actions where status='pending'),
      'runs_24h',(select count(*) from agent_runs where started_at > now()-interval '24 hours'),
      'avg_confidence',(select round(avg(confidence)::numeric,2) from decision_log where confidence is not null)
    ),
    'agents', coalesce((select jsonb_agg(jsonb_build_object('slug',ca.slug,'name',ca.name,'emoji',ca.emoji,'active',ca.active,
        'actions',(select count(*) from agent_actions a where a.agent=ca.slug),
        'pending',(select count(*) from agent_actions a where a.agent=ca.slug and a.status='pending')) order by ca.name) from category_agents ca),'[]'::jsonb),
    'kinds', coalesce((select jsonb_agg(jsonb_build_object('key',k,'count',c) order by c desc) from (
        select coalesce(nullif(kind,''),'other') k, count(*) c from agent_actions group by 1 order by 2 desc limit 12) kk),'[]'::jsonb),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'status',status,'started_at',started_at,'finished_at',finished_at,'note',note)) from (select * from agent_runs order by started_at desc limit 12) r),'[]'::jsonb)
  );
$$;

create or replace function fn_ws_knowledge() returns jsonb language sql security definer stable as $$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'chunks',(select count(*) from kb_chunks),
      'categories',(select count(distinct category) from kb_chunks),
      'legal_docs',(select count(*) from legal_documents),
      'category_specs',(select count(*) from category_specs),
      'revisions_pending',(select count(*) from kb_revisions where coalesce(status,'')='pending')
    ),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('key',cat,'count',c) order by c desc) from (
        select coalesce(nullif(category,''),'general') cat, count(*) c from kb_chunks group by 1 order by 2 desc limit 16) k),'[]'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'category',category,'citation',citation,'effective_date',effective_date,'created_at',created_at)) from (select * from kb_chunks order by created_at desc limit 20) c),'[]'::jsonb),
    'legal', coalesce((select jsonb_agg(jsonb_build_object('slug',slug,'title',title,'category',category,'version',version,'effective_date',effective_date,'updated_at',updated_at)) from (select * from legal_documents order by updated_at desc limit 20) l),'[]'::jsonb),
    'revisions', coalesce((select jsonb_agg(jsonb_build_object('id',id,'entry_kind',entry_kind,'version',version,'status',status,'author',author,'created_at',created_at)) from (select * from kb_revisions order by created_at desc limit 12) rv),'[]'::jsonb)
  );
$$;

create or replace function fn_ws_documents() returns jsonb language sql security definer stable as $$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'documents',(select count(*) from documents),
      'indexed',(select count(*) from documents where indexed is true),
      'reviews_pending',(select count(*) from doc_reviews where coalesce(status,'')='pending'),
      'versions',(select count(*) from doc_versions)
    ),
    'documents', coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'kind',kind,'ref_table',ref_table,'ref_id',ref_id,'status',status,'indexed',indexed,'created_at',created_at)) from (select * from documents order by created_at desc limit 40) d),'[]'::jsonb),
    'reviews', coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'ai_category',ai_category,'ai_summary',ai_summary,'ai_confidence',ai_confidence,'status',status,'created_at',created_at)) from (select * from doc_reviews order by created_at desc limit 20) r),'[]'::jsonb),
    'kinds', coalesce((select jsonb_agg(jsonb_build_object('key',k,'count',c) order by c desc) from (select coalesce(nullif(kind,''),'other') k, count(*) c from documents group by 1) kk),'[]'::jsonb)
  );
$$;

create or replace function fn_ws_analytics() returns jsonb language sql security definer stable as $$
  select jsonb_build_object(
    'marketplace', fn_marketplace_analytics(),
    'supplier_funnel', jsonb_build_object(
      'directory',(select count(*) from leads),
      'claimed',(select count(*) from leads where claimed is true),
      'registered',(select count(*) from leads where registration_paid_at is not null),
      'submitted',(select count(*) from leads where coalesce(approval_status,'') in ('submitted','under_review','pending','pending_review')),
      'approved',(select count(*) from leads where approval_status='approved')
    ),
    'top_sectors', coalesce((select jsonb_agg(jsonb_build_object('key',s,'count',c) order by c desc) from (
        select coalesce(nullif(sector,''),'other') s, count(*) c from leads group by 1 order by 2 desc limit 12) x),'[]'::jsonb),
    'top_emirates', coalesce((select jsonb_agg(jsonb_build_object('key',e,'count',c) order by c desc) from (
        select coalesce(nullif(emirate,''),'—') e, count(*) c from leads group by 1 order by 2 desc limit 8) x),'[]'::jsonb)
  );
$$;

create or replace function fn_ws_company() returns jsonb language sql security definer stable as $$
  select jsonb_build_object(
    'departments', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'actions',c,'pending',pend,'last_active',la) order by c desc) from (
        select coalesce(agent,'—') agent, count(*) c,
               count(*) filter (where status='pending') pend, max(created_at) la
        from agent_actions group by 1 order by 2 desc limit 20) d),'[]'::jsonb),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'status',status,'started_at',started_at,'note',note)) from (select * from agent_runs order by started_at desc limit 12) r),'[]'::jsonb),
    'evals', coalesce((select jsonb_agg(jsonb_build_object('snapshot_at',snapshot_at,'window_days',window_days,'kpis',kpis)) from (select * from agent_evals order by snapshot_at desc limit 4) e),'[]'::jsonb)
  );
$$;

create or replace function fn_os_search(p_q text) returns jsonb language sql security definer stable as $$
  select jsonb_build_object(
    'suppliers', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',company_name,'sub',emirate||' · '||coalesce(sector,''))) from (
        select id,company_name,emirate,sector from leads where p_q<>'' and company_name ilike '%'||p_q||'%' order by capability_score desc nulls last limit 6) s),'[]'::jsonb),
    'rfqs', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',coalesce(summary,category),'sub',category)) from (
        select id,summary,category from inquiries where p_q<>'' and (summary ilike '%'||p_q||'%' or category ilike '%'||p_q||'%') order by created_at desc limit 6) r),'[]'::jsonb),
    'customers', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',full_name,'sub',email)) from (
        select id,full_name,email from customers where p_q<>'' and (full_name ilike '%'||p_q||'%' or email ilike '%'||p_q||'%') limit 6) c),'[]'::jsonb)
  );
$$;

create or replace function fn_os_record(p_entity text, p_id text) returns jsonb language plpgsql security definer stable as $$
declare v jsonb;
begin
  if p_entity='supplier' then select to_jsonb(l) into v from leads l where l.id = p_id::bigint;
  elsif p_entity='rfq' then select to_jsonb(i) into v from inquiries i where i.id = p_id::uuid;
  elsif p_entity='customer' then select to_jsonb(c) into v from customers c where c.id = p_id::uuid;
  elsif p_entity='quote' then select to_jsonb(q) into v from quotes q where q.id = p_id::uuid;
  elsif p_entity='agent_action' then select to_jsonb(a) into v from agent_actions a where a.id = p_id::bigint;
  elsif p_entity='task' then select to_jsonb(t) into v from crm_tasks t where t.id = p_id::bigint;
  else v := null; end if;
  return jsonb_build_object('entity',p_entity,'id',p_id,'record',v);
end;
$$;
