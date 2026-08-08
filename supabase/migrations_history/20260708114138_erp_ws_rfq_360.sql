-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708114138   name: erp_ws_rfq_360
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_ws_rfq_360(p_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare i public.inquiries%rowtype; j jsonb; docs jsonb := '[]'::jsonb; hired text;
begin
  select * into i from public.inquiries where id=p_id;
  if i.id is null then return jsonb_build_object('error','RFQ not found'); end if;

  if i.drawing_file_path is not null then docs := docs || jsonb_build_object('type','Drawing','name',coalesce(i.drawing_file_name,'drawing'),'path',i.drawing_file_path); end if;
  if i.drawing_redacted_paths is not null then
    docs := docs || coalesce((select jsonb_agg(jsonb_build_object('type','Drawing (redacted)','name','redacted','path',x)) from unnest(i.drawing_redacted_paths) x),'[]'::jsonb);
  end if;

  select company_name into hired from public.leads where id=i.hired_supplier_id;

  j := jsonb_build_object(
    'requirements', jsonb_build_object('category',i.category,'emirate',i.emirate,'role_needed',i.role_needed,
       'summary',i.summary,'spec',i.spec,'boq',i.boq,'boq_confidence',i.boq_confidence,'budget',i.budget,
       'scope_type',i.scope_type,'trades',i.trades,'keywords',i.keywords),
    'status', jsonb_build_object('status',i.status,'pipeline_stage',i.pipeline_stage,'deal_owner',i.deal_owner,
       'expected_value',i.expected_value,'outcome',i.outcome,'lost_reason',i.lost_reason,'completed_at',i.completed_at,
       'project_id',i.project_id,'created_at',i.created_at),
    'ai_qualification', jsonb_build_object('completeness',i.completeness,'rfq_ready',i.rfq_ready,'routing',i.routing,'brief_source',i.brief_source),
    'selected_supplier', case when i.hired_supplier_id is not null then jsonb_build_object('id',i.hired_supplier_id,'company_name',hired) else null end,
    'documents', docs,
    'matching', coalesce((select jsonb_agg(jsonb_build_object('supplier_id',m.supplier_id,'company_name',l.company_name,
       'similarity',m.similarity,'match_reason',m.match_reason,'sent_at',m.sent_at) order by m.similarity desc nulls last)
       from public.inquiry_matches m left join public.leads l on l.id=m.supplier_id where m.inquiry_id=p_id),'[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'supplier_id',q.supplier_id,'company_name',l.company_name,
       'amount',q.quote_amount,'status',q.status,'lead_time',q.lead_time,'validity',q.validity,'quality',q.quality,
       'created_at',q.created_at) order by q.quote_amount asc nulls last)
       from public.quotes q left join public.leads l on l.id=q.supplier_id where q.inquiry_id=p_id),'[]'::jsonb),
    'clarifications', coalesce((select jsonb_agg(jsonb_build_object('question',qn.question,'answer',qn.answer,
       'supplier_id',qn.supplier_id,'asked_at',qn.asked_at,'answered_at',qn.answered_at) order by qn.asked_at desc)
       from public.questions qn where qn.inquiry_id=p_id),'[]'::jsonb),
    'timeline', (select jsonb_agg(e order by e->>'at' desc) from (
        select jsonb_build_object('at',i.created_at,'event','RFQ created') e
        union all select jsonb_build_object('at',m.sent_at,'event','Matched supplier') from public.inquiry_matches m where m.inquiry_id=p_id and m.sent_at is not null
        union all select jsonb_build_object('at',q.created_at,'event','Quote received: AED '||coalesce(q.quote_amount::text,'?')) from public.quotes q where q.inquiry_id=p_id
        union all select jsonb_build_object('at',i.completed_at,'event','Completed'||coalesce(' ('||i.outcome||')','')) where i.completed_at is not null
      ) tl)
  );
  return j;
end $$;

revoke execute on function public.fn_ws_rfq_360(uuid) from anon, authenticated, public;
