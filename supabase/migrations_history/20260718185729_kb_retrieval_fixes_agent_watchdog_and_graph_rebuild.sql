-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260718185729   name: kb_retrieval_fixes_agent_watchdog_and_graph_rebuild
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Backfill migration: records changes applied live on 2026-07-18 via execute_sql.
-- Written idempotently: documents current state, does not re-apply destructive work.
-- NOT included (data/ops, already done): demo-data purge (customers/inquiries/quotes/
-- transactions/reviews/projects), regulations rows 17-18, cron unschedule of
-- agent_category_sales_daily, cron schedule of agent_silence_watch_daily.

-- 1. Retrieval key normalisation. kb_chunks used two vocabularies for the same
--    trade ('cat:plumbing' vs 'plumbing'), so category-filtered search could never
--    reach regulation chunks. Additive column; original `category` untouched.
alter table public.kb_chunks
  add column if not exists category_norm text
  generated always as (nullif(regexp_replace(lower(coalesce(category,'')),'^cat:',''),'')) stored;
create index if not exists kb_chunks_category_norm_idx on public.kb_chunks(category_norm);

-- 2. Category aliases: lets a trade inherit regulations already held under another
--    slug, instead of duplicating or generating content.
create table if not exists public.kb_category_aliases (
  category text not null,
  maps_to  text not null,
  rationale text,
  primary key (category, maps_to)
);
revoke all on public.kb_category_aliases from public, anon, authenticated;
grant select on public.kb_category_aliases to service_role;

insert into public.kb_category_aliases(category, maps_to, rationale) values
 ('commercial-retail-fitout','fitout','Same trade, different slug. Inherits Dubai Building Code, DCD fire/life safety, Trakhees, Al Safat, OHS.'),
 ('combined-mep','electrical','MEP = Mechanical + Electrical + Plumbing; inherits DEWA electrical regs.'),
 ('combined-mep','plumbing','MEP composite; inherits DEWA water/plumbing regs.'),
 ('combined-mep','ac-maintenance','MEP mechanical component; inherits HVAC regs.'),
 ('combined-mep','fitout','MEP work triggers building permit + civil defence approvals.')
on conflict do nothing;

-- 3. kb_match. Two fixes vs the prior version:
--    (a) matches on category_norm + aliases, so prefix variants unify;
--    (b) filters BEFORE ranking via a materialized CTE. The HNSW index
--        (ef_search=40) previously ranked globally then filtered, so a 9-row
--        category returned only the ~3 chunks that landed in the global top-40.
--        At ~2k rows exact search is cheap and gives full recall.
create or replace function public.kb_match(query_embedding vector, match_count integer default 8, p_category text default null::text)
 returns table(id bigint, category text, title text, citation text, content text, similarity double precision)
 language sql stable set search_path to 'public','pg_temp'
as $function$
  with want as (
    select nullif(regexp_replace(lower(p_category),'^cat:',''),'') as c
  ), cats as (
    select c as cat from want where c is not null
    union
    select a.maps_to from kb_category_aliases a, want w where a.category = w.c
  ), src as materialized (
    select k.id, k.category, k.title, k.citation, k.content, k.embedding_gte
    from public.kb_chunks k
    where k.embedding_gte is not null
      and ((select c from want) is null or k.category_norm in (select cat from cats))
  )
  select s.id, s.category, s.title, s.citation, s.content,
         1 - (s.embedding_gte <=> query_embedding) as similarity
  from src s
  order by s.embedding_gte <=> query_embedding
  limit match_count;
$function$;

-- 4. Regulation coverage gaps, honouring category_agents.requires_regulation
--    (a pre-existing column the earlier view ignored) and the alias table.
drop view if exists public.v_kb_regulation_gaps;
create view public.v_kb_regulation_gaps as
select c.slug as category, c.name,
       (select count(*) from kb_chunks k
         where k.category_norm = regexp_replace(lower(c.slug),'^cat:','')
           and k.source_kind='trade') as trade_chunks
  from category_agents c
 where c.requires_regulation is true
   and not exists (
     select 1 from kb_chunks k
      where k.source_kind='regulation'
        and k.category_norm in (
          select regexp_replace(lower(c.slug),'^cat:','')
          union
          select a.maps_to from kb_category_aliases a
           where a.category = regexp_replace(lower(c.slug),'^cat:','')))
 order by 1;

-- 5. Research (DMS-035-2020; DM/DCD temporary structures) showed these two trades
--    are in fact regulated; flag corrected from false.
update category_agents set requires_regulation = true
 where slug in ('structural-steel-fabrication','tents-and-shade-structures')
   and requires_regulation is distinct from true;

-- 6. Scheduled-job silence watchdog. Keyed on cron.job_run_details, NOT agent_runs:
--    agent_runs is a work log (agents legitimately write no row when idle).
--    Jobs with zero history under their current jobid are treated as UNKNOWN and
--    skipped -- cron.schedule issues a new jobid on reschedule, orphaning old history.
create table if not exists public.agent_expectations (
  agent text primary key,
  max_silence_hours numeric not null,
  on_demand boolean not null default false,
  median_gap_hours numeric,
  runs_observed int,
  note text,
  updated_at timestamptz not null default now()
);
revoke all on public.agent_expectations from public, anon, authenticated;
grant select on public.agent_expectations to service_role;

create or replace function public.fn_agent_silence_watch()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare r record; n int:=0; f int:=0; g int:=0; v_email text;
begin
  select to_email into v_email from notifications
   where type='founder_brief' and to_email is not null order by created_at desc limit 1;

  for r in
    select j.jobid, j.jobname,
           case when split_part(j.schedule,' ',5) <> '*' then 336
                when split_part(j.schedule,' ',3) <> '*' then 1440
                when split_part(j.schedule,' ',2) =  '*' then 6
                else 72 end as thresh_h,
           (select count(*) from cron.job_run_details d where d.jobid=j.jobid) as history_rows,
           (select max(d.start_time) from cron.job_run_details d
             where d.jobid=j.jobid and d.status='succeeded') as last_ok,
           (select count(*) from cron.job_run_details d
             where d.jobid=j.jobid and d.status='failed'
               and d.start_time > now() - interval '24 hours') as fails_24h
      from cron.job j where j.active
  loop
    if r.history_rows = 0 then
      g := g + 1;
      continue;
    end if;

    if r.last_ok is null or r.last_ok < now() - (r.thresh_h||' hours')::interval then
      if not exists (select 1 from founder_alerts where event='cron_silent'
                      and detail like '%"'||r.jobname||'"%'
                      and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level,event,detail,channel)
        values ('high','cron_silent', jsonb_build_object(
          'job',r.jobname,'last_success',coalesce(r.last_ok::text,'no success in retained history'),
          'silent_hours',round(extract(epoch from (now()-r.last_ok))/3600),
          'expected_within_hours',r.thresh_h)::text,'email');
        if v_email is not null then
          insert into notifications(type,to_email,subject,body,status)
          values ('agent_silence',v_email,'Scheduled job stopped: '||r.jobname,
            'Job "'||r.jobname||'" last succeeded '||coalesce(r.last_ok::text,'unknown')||
            '. Expected at least every '||r.thresh_h||' hours.','pending');
        end if;
        n := n + 1;
      end if;
    end if;

    if r.fails_24h > 0 then
      if not exists (select 1 from founder_alerts where event='cron_failing'
                      and detail like '%"'||r.jobname||'"%'
                      and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level,event,detail,channel)
        values ('high','cron_failing',
          jsonb_build_object('job',r.jobname,'failures_24h',r.fails_24h,
                             'last_success',coalesce(r.last_ok::text,'unknown'))::text,'email');
        f := f + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('ran_at',now(),
    'active_jobs',(select count(*) from cron.job where active),
    'skipped_no_history',g,'silent_alerts',n,'failing_alerts',f);
end $$;
revoke all on function public.fn_agent_silence_watch() from public, anon, authenticated;
grant execute on function public.fn_agent_silence_watch() to service_role;

-- 7. fn_graph_rebuild. Broke 2026-07-15 with "ON CONFLICT DO UPDATE command cannot
--    affect row a second time": the category insert proposed the same (kind,ref_id)
--    once per inquiry sharing that category. Fixed with DISTINCT, plus the same
--    latent defect deduped on the `quoted` and `reviewed` edges (a supplier may
--    hold several quote rows per RFQ; a customer may review a supplier twice).
create or replace function public.fn_graph_rebuild()
 returns jsonb language plpgsql set search_path to 'public','pg_temp'
as $function$
declare n_nodes int; n_edges int;
begin
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select distinct 'category', category, category, '{}'::jsonb, now()
    from inquiries where category is not null
    on conflict (kind,ref_id) do update set updated_at=now();
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'rfq', id::text, coalesce(summary,category), jsonb_build_object('status',status,'stage',pipeline_stage,'emirate',emirate,'budget',budget), now() from inquiries
    on conflict (kind,ref_id) do update set label=excluded.label, props=excluded.props, updated_at=now();
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'customer', c.id::text, coalesce(c.full_name,c.email), '{}'::jsonb, now()
    from customers c where c.id in (select distinct customer_id from inquiries where customer_id is not null)
    on conflict (kind,ref_id) do update set updated_at=now();
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'supplier', l.id::text, l.company_name, jsonb_build_object('emirate',l.emirate), now()
    from leads l where l.id in (
      select supplier_id from inquiry_matches where supplier_id is not null
      union select supplier_id from quotes where supplier_id is not null
      union select hired_supplier_id from inquiries where hired_supplier_id is not null)
    on conflict (kind,ref_id) do update set label=excluded.label, updated_at=now();
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'regulation', id::text, coalesce(title, doc_ref, 'regulation '||id),
           jsonb_build_object('authority',authority,'status',status,'version',version,'effective_date',effective_date,'doc_ref',doc_ref), now()
    from regulations
    on conflict (kind,ref_id) do update set label=excluded.label, props=excluded.props, updated_at=now();
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select distinct 'category', c, c, '{}'::jsonb, now()
    from regulations r, unnest(r.categories) c where c is not null and c<>''
    on conflict (kind,ref_id) do update set updated_at=now();

  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'customer', customer_id::text, 'created', 'rfq', id::text, '{}'::jsonb, now() from inquiries where customer_id is not null
    on conflict do nothing;
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'rfq', id::text, 'in_category', 'category', category, '{}'::jsonb, now() from inquiries where category is not null
    on conflict do nothing;
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'rfq', inquiry_id::text, 'invited', 'supplier', supplier_id::text, '{}'::jsonb, now() from inquiry_matches where supplier_id is not null
    on conflict do nothing;
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'supplier', q.supplier_id::text, 'quoted', 'rfq', q.inquiry_id::text,
           jsonb_build_object('amount',q.quote_amount), now()
    from (select distinct on (supplier_id, inquiry_id) supplier_id, inquiry_id, quote_amount
            from quotes where supplier_id is not null
           order by supplier_id, inquiry_id) q
    on conflict (src_kind,src_ref,rel,dst_kind,dst_ref) do update set props=excluded.props, updated_at=now();
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'rfq', id::text, 'hired', 'supplier', hired_supplier_id::text, '{}'::jsonb, now() from inquiries where hired_supplier_id is not null
    on conflict do nothing;
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'customer', rv.customer_id::text, 'reviewed', 'supplier', rv.supplier_id::text,
           jsonb_build_object('rating',rv.rating), now()
    from (select distinct on (customer_id, supplier_id) customer_id, supplier_id, rating
            from reviews where supplier_id is not null and customer_id is not null
           order by customer_id, supplier_id) rv
    on conflict (src_kind,src_ref,rel,dst_kind,dst_ref) do update set props=excluded.props, updated_at=now();
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select distinct 'regulation', r.id::text, 'applies_to', 'category', c, '{}'::jsonb, now()
    from regulations r, unnest(r.categories) c where c is not null and c<>''
    on conflict do nothing;
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'regulation', id::text, 'supersedes', 'regulation', supersedes_id::text, '{}'::jsonb, now()
    from regulations where supersedes_id is not null
    on conflict do nothing;

  select count(*) into n_nodes from graph_nodes;
  select count(*) into n_edges from graph_edges;
  return jsonb_build_object('nodes',n_nodes,'edges',n_edges);
end $function$;
