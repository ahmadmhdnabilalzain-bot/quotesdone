-- A CATEGORY-SCOPED TASK GETS ITS PACK (6 Sep 2026). Knowledge audit marketplace.md / supply.md: the
-- 1,204 category records (86 routes x 14 files, ops_knowledge.scope_type = 'category', category_key
-- 'NNN_slug') were reachable through fn_agent_context_v3(..., p_category_key, ...) only, and the one
-- run-time path that calls v3 - fn_agent_context(key, max, query) - passed NULL for it on every call.
-- v3 also assembles 'category_knowledge' for that key, and the 3-arg context never rendered it. So a
-- procurement or supply employee working an HVAC inquiry saw the same context as for a joinery one.
--
-- HOW THE KEY IS DERIVED, deterministically, from what the caller already has:
--   1. `inquiry:<uuid>` in the query text -> inquiries.category (the category_specs slug the intake
--      wrote, e.g. 'hvac') -> category_route_map / catalog_supplier_categories -> org_category_identity;
--   2. `run:<id>` in the query text -> workflow_run.trigger_event_id -> company_event with
--      entity_type = 'inquiry' (payload.category, or the inquiry row) - this is what workflow_dispatch
--      now appends, because the step claim carries run_id and the event that started the run names
--      the inquiry;
--   3. a category key written literally ('009_hvac-suppliers');
--   4. a catalogue slug or name present in the text (longest name wins).
-- No inquiry, no category words -> NULL, and the context is byte-identical to before.
--
-- WHERE IT LANDS. "# LAYER 2e - THE CATEGORY PACK FOR THIS TASK" is emitted right after the LAYER 2b
-- marker, BEFORE 2c: fn_agent_context_capped keeps 4,500 characters of the retrieved tail and 2c alone
-- can fill 2,400 of them, so a pack placed after 2c would be cut by the very path it was built for.
-- The 2b marker itself is now always present (a one-line note when the library has no match): the
-- capped wrapper splits head from tail on that string, and without it the whole retrieved tail fell
-- past a positional cut at v_want.
--
-- PROOF: aborted-transaction probe on a ZZ DEMO inquiry (category hvac) in the commit message.
--   node scripts/apply_sql.mjs scripts/sql/a_category_scoped_task_gets_its_pack.sql --apply --ddl

begin;

create or replace function public.fn_category_key_for_slug(p_slug text)
returns text
language sql
stable
set search_path to 'public'
as $function$
  -- category_specs / inquiries.category vocabulary ('hvac', 'aluminium') -> the pack key ('009_hvac-suppliers')
  select i.category_key
    from (
      select m.catalog_num, 1 as pri from public.category_route_map m where m.category = lower(btrim(p_slug))
      union all
      select c.num, 2 from public.catalog_supplier_categories c where c.slug = lower(btrim(p_slug))
      union all
      select c.num, 3 from public.catalog_supplier_categories c
       where c.slug like lower(btrim(p_slug)) || '-%' or c.slug like '%-' || lower(btrim(p_slug)) || '-%' or c.slug like '%-' || lower(btrim(p_slug))
      union all
      select c.num, 4 from public.catalog_supplier_categories c
       where lower(c.name) like '%' || lower(btrim(p_slug)) || '%'
    ) r
    join public.org_category_identity i on i.catalog_num = r.catalog_num
   where coalesce(btrim(p_slug), '') <> ''
   order by r.pri, i.category_key
   limit 1;
$function$;

create or replace function public.fn_category_key_from_text(p_text text)
returns text
language plpgsql
stable
set search_path to 'public'
as $function$
-- SCALARS, NOT A RECORD: a plpgsql record that was never assigned raises "not assigned yet" on its first
-- field reference, so the run-less path would have thrown instead of falling through (caught in rehearsal).
declare v_id uuid; v_run uuid; v_slug text; v_key text; v_lc text;
        v_ev_type text; v_ev_entity text; v_ev_payload jsonb; v_ctx jsonb;
begin
  if coalesce(p_text, '') = '' then return null; end if;
  v_lc := lower(p_text);

  -- 1. an explicit inquiry reference
  begin
    v_id := substring(p_text from '(?i)inquiry[:=# ]\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')::uuid;
  exception when others then v_id := null; end;

  -- 2. a workflow run reference: the event that started the run names the inquiry
  if v_id is null then
    begin
      v_run := substring(p_text from '(?i)\mrun[:=#]\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')::uuid;
    exception when others then v_run := null; end;
    if v_run is not null then
      select e.entity_type, e.entity_id, e.payload, r.context into v_ev_type, v_ev_entity, v_ev_payload, v_ctx
        from public.workflow_run r
        left join public.company_event e on e.id = r.trigger_event_id
       where r.id = v_run;
      if coalesce(v_ctx, '{}'::jsonb) ? 'inquiry_id' then
        begin v_id := (v_ctx->>'inquiry_id')::uuid; exception when others then v_id := null; end;
      end if;
      if v_id is null and v_ev_type = 'inquiry' then
        begin v_id := v_ev_entity::uuid; exception when others then v_id := null; end;
      end if;
    end if;
  end if;

  if v_id is not null then
    select i.category into v_slug from public.inquiries i where i.id = v_id;
  end if;
  if v_slug is null and v_ev_payload is not null then v_slug := v_ev_payload->>'category'; end if;
  if v_slug is not null then
    v_key := public.fn_category_key_for_slug(v_slug);
    if v_key is not null then return v_key; end if;
  end if;

  -- 3. a category key named literally
  v_key := substring(p_text from '\m([0-9]{3}_[a-z0-9-]+)\M');
  if v_key is not null and exists (select 1 from public.org_category_identity where category_key = v_key) then
    return v_key;
  end if;

  -- 4. a catalogue slug or name in the text; the longest name wins
  select i.category_key into v_key
    from public.catalog_supplier_categories c
    join public.org_category_identity i on i.catalog_num = c.num
   where v_lc like '%' || lower(c.slug) || '%' or v_lc like '%' || lower(c.name) || '%'
   order by length(c.name) desc, i.category_key
   limit 1;
  return v_key;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_agent_context(p_agent_key text, p_max_chars integer, p_query text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out text; v_dept text; lib text := ''; ops text := ''; r record; r2 record; v_cat text; catx text := '';
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  out := public.fn_agent_context(p_agent_key, p_max_chars);
  if p_agent_key is null or coalesce(p_query,'') = '' then return out; end if;
  select a.department into v_dept from org_agents a where a.agent_key = p_agent_key;
  -- THE CATEGORY, derived from the task itself (inquiry / run reference, a key, or a catalogue name).
  v_cat := public.fn_category_key_from_text(p_query);

  for r in
    with hits as (
      select 1 as ord, s.* from public.fn_dept_library_search(v_dept, p_query, 4) s
      union all
      select 2 as ord, s.* from public.fn_dept_library_search('company', p_query, 2) s
    ), uniq as (
      select distinct on (id) id, title, content, ord, rank from hits order by id, ord
    )
    select title, content from uniq order by ord, rank desc
  loop
    exit when length(lib) > 2600;
    lib := lib || '## ' || coalesce(r.title,'') || E'\n' || left(coalesce(r.content,''), 700) || E'\n\n';
  end loop;
  -- THE MARKER IS ALWAYS EMITTED. fn_agent_context_capped splits the standing head from the retrieved
  -- tail on '# LAYER 2b'; when the library had no match there was no marker, and the whole retrieved
  -- tail fell past a positional cut instead of being kept inside the 4,500-character reserve.
  if lib <> '' then
    out := out || E'\n' ||
      '# LAYER 2b - YOUR DEPARTMENT REFERENCE LIBRARY (retrieved from dept_library for this task; cite the title in [brackets] when you use it)' ||
      E'\n\n' || lib;
  else
    out := out || E'\n' || '# LAYER 2b - YOUR DEPARTMENT REFERENCE LIBRARY: no dept_library row matched this task.' || E'\n\n';
  end if;

  -- LAYER 2d/2e/2f/2g: the V3 delivery, now WITH the category key when the task names one.
  declare v3 jsonb; sec text := ''; itm jsonb; begin
    v3 := public.fn_agent_context_v3(p_agent_key, null, p_query, v_cat, 9000);

    -- LAYER 2e first: the category pack has to sit inside the reserve the capped path keeps.
    if v_cat is not null and v3 ? 'category_knowledge' then
      for itm in select * from jsonb_array_elements(coalesce(v3->'category_knowledge','[]'::jsonb)) loop
        exit when length(catx) > 1800;
        catx := catx || '## ' || coalesce(itm->>'title','') || ' [' || coalesce(itm->>'record_id','') || ']' || E'\n'
              || left(regexp_replace(coalesce(itm->>'content',''), '\s+', ' ', 'g'), 600) || E'\n\n';
      end loop;
      if catx <> '' then
        out := out || E'\n' ||
          '# LAYER 2e - THE CATEGORY PACK FOR THIS TASK (' || v_cat || '): the route''s qualification playbook, ' ||
          'field and question bank, quality gate and comparison contract. This task is category-scoped; these records ' ||
          'decide what to ask, what may never be inferred and how quotes in this route are compared. Cite the [record_id].' ||
          E'\n\n' || catx;
      end if;
    end if;

    for r2 in
      select title, content, record_type, authority_tier, implementation_status, rank
        from public.fn_ops_knowledge_search(v_dept, p_query, 5)
       order by rank desc
    loop
      exit when length(ops) > 2400;
      ops := ops || '## [' || coalesce(r2.record_type,'record') || ' · authority: ' ||
             coalesce(r2.authority_tier,'?') || ' · ' || coalesce(r2.implementation_status,'?') || '] ' ||
             coalesce(r2.title,'') || E'\n' || left(coalesce(r2.content,''), 700) || E'\n\n';
    end loop;
    if ops <> '' then
      out := out || E'\n' ||
        '# LAYER 2c - HOW THIS COMPANY OPERATES (your department''s own SOPs, decision rules, exception playbooks and KPI definitions). ' ||
        'These OVERRIDE generic practice. Respect the authority tier on each: gated means it needs approval, ' ||
        'supervised means a human reviews it, autonomous means you may act. A record marked target_state describes ' ||
        'a capability the company has NOT built yet — plan around it, do not assume it exists.' ||
        E'\n\n' || ops;
    end if;

    if v3 ? 'role_knowledge' then
      for itm in select * from jsonb_array_elements(v3->'role_knowledge') loop
        exit when length(sec) > 2400;
        sec := sec || '## ' || coalesce(itm->>'title','') || ' [' || coalesce(itm->>'record_id','') || ']' || E'\n'
            || left(coalesce(itm->>'content',''), 700) || E'\n\n';
      end loop;
      if sec <> '' then
        out := out || E'\n' ||
          '# LAYER 2d - YOUR PROFESSIONAL ROLE KNOWLEDGE (the packaged role identity you hold: purpose, ' ||
          'competencies, expert decision checklist and evidence contract). Cite the [record_id] you use.'
          || E'\n\n' || sec;
      end if;
    end if;

    sec := '';
    for itm in select * from jsonb_array_elements(coalesce(v3->'deterministic_rules','[]'::jsonb)) loop
      exit when length(sec) > 2000;
      sec := sec || '- [' || coalesce(itm->>'record_id','') || ' · ' || coalesce(itm->>'layer','') ||
             ' · authority ' || coalesce(itm->>'authority_tier','?') || '] ' || coalesce(itm->>'title','') || E'\n';
    end loop;
    if sec <> '' then
      out := out || E'\n' ||
        '# LAYER 2f - DETERMINISTIC RULES THAT BIND YOU (authority, policy, decision playbooks, KPI ' ||
        'definitions). These are looked up as structured records, never inferred from similarity. If a ' ||
        'rule here contradicts anything above, the rule wins.' || E'\n\n' || sec;
    end if;

    sec := '';
    for itm in select * from jsonb_array_elements(coalesce(v3->'live_data_required','[]'::jsonb)) loop
      exit when length(sec) > 900;
      sec := sec || '- ' || coalesce(itm->>'title','') || E'\n';
    end loop;
    if sec <> '' then
      out := out || E'\n' ||
        '# LAYER 2g - FACTS YOU MUST FETCH, NOT REMEMBER. For each of these the current value comes from ' ||
        'a live authorised tool. Answering one of them from the text above is a wrong answer, however ' ||
        'confident it reads.' || E'\n\n' || sec;
    end if;
    -- The trace has to be able to name what was read. Recorded here because this is where
    -- the assembled context and its record ids are both in scope. A STABLE function may not
    -- execute an INSERT, which is why this one and its caller are now VOLATILE.
    perform public.fn_record_context_retrieval(
      p_agent_key, null, null,
      (select array_agg(x) from jsonb_array_elements_text(coalesce(v3->'knowledge_ids','[]'::jsonb)) x),
      p_max_chars, length(out));
  end;
  return out;
end
$function$;

commit;
