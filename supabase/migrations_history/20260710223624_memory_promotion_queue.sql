-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710223624   name: memory_promotion_queue
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.memory_promotions(
  memory_id bigint primary key,
  kb_chunk_id bigint,
  category text,
  promoted_at timestamptz not null default now(),
  promoted_by text);
alter table public.memory_promotions enable row level security;

-- Candidates: high-value agent memories not yet promoted into the canonical KB.
create or replace view public.v_memory_promotion_candidates as
select m.id, m.agent_key, m.kind, m.importance, m.source, m.created_at,
       left(m.content, 240) as preview, length(m.content) as content_len
from public.agent_memory m
where not exists (select 1 from public.memory_promotions p where p.memory_id = m.id)
order by m.importance desc nulls last, m.created_at desc;
revoke all on public.v_memory_promotion_candidates from anon, authenticated;

-- Governed promotion: founder calls this to graduate a memory into kb_chunks (agents then retrieve it).
create or replace function public.fn_promote_memory(p_memory_id bigint, p_category text, p_by text default 'founder')
returns bigint language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare m record; v_chunk_id bigint;
begin
  select * into m from public.agent_memory where id = p_memory_id;
  if not found then raise exception 'memory % not found', p_memory_id; end if;
  if exists (select 1 from public.memory_promotions where memory_id = p_memory_id) then
    raise exception 'memory % already promoted', p_memory_id;
  end if;
  insert into public.kb_chunks(source_kind, source_id, category, title, content, citation, effective_date)
  values('memory', p_memory_id::text, coalesce(nullif(p_category,''),'general'),
         left(m.content, 80), m.content,
         'agent_memory #'||p_memory_id||' ('||coalesce(m.agent_key,'?')||')', current_date)
  returning id into v_chunk_id;
  insert into public.memory_promotions(memory_id, kb_chunk_id, category, promoted_by)
  values(p_memory_id, v_chunk_id, coalesce(nullif(p_category,''),'general'), p_by);
  return v_chunk_id;
end $$;
revoke all on function public.fn_promote_memory(bigint,text,text) from anon, authenticated;
