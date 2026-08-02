-- PHASE 3 RUNTIME. Three functions, no model call in any of them. All read-only; none of them
-- enables anything. They exist so the corpus can be USED and TESTED before anyone decides to
-- promote it, which is the only way the acceptance tests mean anything.

-- ---------------------------------------------------------------------------------------------
-- 1. HARD-GATE + AUTHORITY CHECK. This is the important one.
-- Production already has org_authority (33 rows, re-tiered 29 Jul) keyed on (dept_key,
-- action_class, max_tier, threshold_aed). The corpus adds 10 hard gates keyed on action_class with
-- a default tier and an approval role. They must agree, and where they disagree the STRICTER answer
-- has to win - a corpus that could widen production authority merely by being imported would be an
-- authority-escalation vector, which the security rules name explicitly.
-- So: strictest wins. A hard gate can only ever tighten.
create or replace function public.fn_ops_authority_check(
  p_dept_key text, p_action_class text, p_amount_aed numeric default null, p_risk text default null)
returns jsonb language plpgsql stable as $$
declare v_prod text; v_thresh numeric; v_gate record; v_tier text; v_reason text;
begin
  select max_tier, threshold_aed into v_prod, v_thresh
  from public.org_authority where dept_key = p_dept_key and action_class = p_action_class;

  select * into v_gate from ops_kb_stage.hard_gates
  where raw->>'action_class' = p_action_class limit 1;

  v_tier := coalesce(v_prod, 'gated');
  v_reason := case when v_prod is null
                   then 'no org_authority row for this department and action class - defaulting to gated'
                   else 'org_authority.max_tier' end;

  if v_gate.record_id is not null then
    if coalesce(v_gate.raw->>'default_tier','gated') = 'gated' and v_tier <> 'gated' then
      v_tier := 'gated';
      v_reason := 'hard gate "' || v_gate.title || '" overrides org_authority (a hard gate may only tighten, never widen)';
    end if;
  end if;

  if v_thresh is not null and p_amount_aed is not null and p_amount_aed > v_thresh then
    v_tier := 'gated';
    v_reason := format('amount %s AED exceeds the department threshold of %s AED', p_amount_aed, v_thresh);
  end if;

  if p_risk = 'critical' and v_tier = 'autonomous' then
    v_tier := 'gated';
    v_reason := 'risk_level=critical is never executed autonomously';
  end if;

  return jsonb_build_object(
    'department', p_dept_key, 'action_class', p_action_class,
    'effective_tier', v_tier,
    'may_act_autonomously', (v_tier = 'autonomous'),
    'requires_approval', (v_tier = 'gated'),
    'hard_gate', case when v_gate.record_id is null then null else jsonb_build_object(
        'title', v_gate.title, 'approval_role', v_gate.raw->>'approval_role',
        'threshold', v_gate.raw->>'threshold', 'rollback', v_gate.raw->>'rollback') end,
    'production_tier', v_prod, 'threshold_aed', v_thresh, 'reason', v_reason,
    'source', 'org_authority + ops_kb_stage.hard_gates (deterministic, no model call)');
end $$;

comment on function public.fn_ops_authority_check(text,text,numeric,text) is
  'Deterministic authority decision for one department and action class. Combines live org_authority with the corpus hard gates under a strictest-wins rule, so importing the corpus can never widen what an agent may do.';

-- ---------------------------------------------------------------------------------------------
-- 2. AGENT CONTEXT ASSEMBLY. Company core + department knowledge + live bindings + authoritative
-- sources + hard gates + recent institutional memory. The point is that it returns a HANDFUL of
-- records rather than a department master: agent_brain currently spends 14,600-22,000 input tokens
-- per call, which is the single largest AI cost in the company.
create or replace function public.fn_ops_department_context(
  p_dept_key text, p_topic text default null, p_limit int default 6)
returns jsonb language sql stable as $$
with q as (
  select to_tsquery('simple', nullif(array_to_string(
      array(select w || ':*' from unnest(regexp_split_to_array(lower(coalesce(p_topic,'')), '[^a-z0-9]+')) w
            where length(w) >= 3), ' | '), '')) tsq
)
select jsonb_build_object(
  'department', p_dept_key,
  'company_core', (
    select coalesce(jsonb_agg(jsonb_build_object('title', c.title, 'content', c.body)), '[]'::jsonb)
    from (select r.title, left(r.content,1200) body from ops_kb_stage.records r
          where r.scope_type = 'company' and r.module in ('identity','principles','governance','privacy','language')
            and r.validation_status in ('reviewed','source_verified','approved')
          order by r.record_type limit 8) c),
  'department_knowledge', (
    select coalesce(jsonb_agg(s.x), '[]'::jsonb) from (
      select jsonb_build_object('record_id', r.record_id, 'title', r.title,
                                'content', left(r.content, 1500), 'module', r.module,
                                'implementation_status', r.implementation_status,
                                'authority_tier', r.authority_tier, 'risk_level', r.risk_level,
                                'source_ids', r.source_ids) x
      from ops_kb_stage.records r, q
      where r.scope_type = 'department' and r.scope_key = p_dept_key
        and r.validation_status in ('reviewed','source_verified','approved')
        and (q.tsq is null or to_tsvector('simple', r.title || ' ' || left(r.content,4000)) @@ q.tsq)
      order by ts_rank(to_tsvector('simple', r.title || ' ' || left(r.content,4000)), q.tsq) desc,
               r.implementation_status, r.record_id
      limit greatest(p_limit,1)) s),
  'live_data', (
    select coalesce(jsonb_agg(jsonb_build_object('object', b.object_name, 'kind', b.db_object_kind,
                                                 'purpose', b.read_purpose, 'write_policy', b.write_policy)), '[]'::jsonb)
    from ops_kb_stage.live_bindings b
    where b.department_key = p_dept_key and b.mapping_status = 'mapped'),
  'authoritative_sources', (
    select coalesce(jsonb_agg(jsonb_build_object('source_id', s2.source_id, 'title', s2.title,
                                                 'publisher', s2.publisher, 'url', s2.url_or_path)), '[]'::jsonb)
    from ops_kb_stage.sources s2
    where exists (select 1 from ops_kb_stage.records r
                  where r.scope_key = p_dept_key and s2.source_id = any(r.source_ids))),
  'hard_gates', (
    select coalesce(jsonb_agg(jsonb_build_object('action_class', g.raw->>'action_class',
                                                 'approval_role', g.raw->>'approval_role')), '[]'::jsonb)
    from ops_kb_stage.hard_gates g),
  'institutional_memory', (
    select coalesce(jsonb_agg(jsonb_build_object('headline', m.headline, 'outcome', m.outcome)), '[]'::jsonb)
    from (select headline, outcome from public.institutional_memory order by created_at desc limit 3) m),
  'note', 'staging corpus: nothing here is enabled or approved; implementation_status must be checked before acting'
);
$$;

-- ---------------------------------------------------------------------------------------------
-- 3. SUPPLIER-CORPUS LINK. The pack is explicit that the 86-route supplier corpus stays the source
-- for category expertise and that this corpus links to it by stable key rather than copying it.
-- Four target departments own that boundary.
create or replace view public.v_ops_supplier_corpus_link as
select d.department_key,
       d.name as department_name,
       r.catalog_num,
       c.slug  as live_catalog_slug,
       c.name  as live_catalog_name,
       (select count(*) from public.kb_operational_route_map m where m.catalog_num = r.catalog_num) as mapped_subcategories
from ops_kb_stage.departments d
cross join public.kb_operational_route r
join public.catalog_supplier_categories c on c.num = r.catalog_num
where d.department_key in ('rfq_intelligence','marketplace_operations','supplier_knowledge','document_intelligence');

comment on view public.v_ops_supplier_corpus_link is
  'The join between the company-operations corpus and the 86-route supplier corpus. Linked by catalog_num, never copied: category expertise has exactly one owner.';

grant execute on function public.fn_ops_authority_check(text,text,numeric,text) to service_role;
grant execute on function public.fn_ops_department_context(text,text,int) to service_role;

create index if not exists ops_kb_stage_records_fts_idx
  on ops_kb_stage.records using gin (to_tsvector('simple', title || ' ' || left(content, 4000)));
