-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727025829   name: institutional_memory_recall_into_agent_context
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- The Layer-4 run found that ZERO functions read institutional_memory: lessons were
-- written down and never recalled. Layer 4 of the employee context read agent_knowledge
-- and agent_memory but not the company's own institutional record.
create or replace function public.fn_agent_institutional_memory(p_agent_key text, p_limit integer default 6)
returns text language plpgsql stable security definer set search_path = public as $fn$
declare v_dept text; v_cat text; out text := ''; r record;
begin
  if p_agent_key is null then return ''; end if;

  select department into v_dept from org_agents where agent_key = p_agent_key;
  if p_agent_key like 'cat:%' then v_cat := replace(p_agent_key, 'cat:', ''); end if;

  for r in
    select m.kind, m.headline, m.detail, m.outcome, m.money_aed, m.category_slug, m.confidence
    from institutional_memory m
    where (m.visible_to is null
           or array_length(m.visible_to,1) is null
           or 'all' = any(m.visible_to)
           or v_dept = any(m.visible_to)
           or p_agent_key = any(m.visible_to))
      and (m.category_slug is null or m.category_slug = v_cat)
    order by coalesce(m.confidence,0) desc, coalesce(m.occurred_at, m.created_at) desc
    limit greatest(coalesce(p_limit,6), 1)
  loop
    out := out || '## lesson (' || coalesce(r.kind,'note') || ')' || E'\n'
        || coalesce(r.headline,'') || E'\n'
        || left(coalesce(r.detail,''), 600)
        || case when r.outcome is not null then E'\n' || 'What changed as a result: ' || left(r.outcome, 300) else '' end
        || case when coalesce(r.money_aed,0) <> 0 then ' (AED ' || r.money_aed || ' at stake)' else '' end
        || E'\n\n';
  end loop;

  return out;
end; $fn$;

revoke execute on function public.fn_agent_institutional_memory(text,integer) from anon, authenticated, public;

-- Patch fn_agent_context in place so the recall actually reaches the employee,
-- rather than adding another function nobody calls.
do $patch$
declare src text; patched text;
begin
  src := pg_get_functiondef('public.fn_agent_context(text,integer)'::regprocedure);
  if position('fn_agent_institutional_memory' in src) > 0 then
    raise notice 'already patched'; return;
  end if;
  patched := replace(src,
    'if v_l4 <> '''' then',
    'v_l4 := v_l4 || coalesce(public.fn_agent_institutional_memory(p_agent_key, 6), '''');
    if v_l4 <> '''' then');
  if patched = src then
    raise exception 'patch anchor not found in fn_agent_context - refusing to guess';
  end if;
  execute patched;
end $patch$;
