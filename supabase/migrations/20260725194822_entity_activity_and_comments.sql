-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260725194822   name: entity_activity_and_comments
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.entity_comments (
  id bigserial primary key,
  entity text not null,
  entity_id text not null,
  author text not null default 'operator',
  body text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_entity_comments_lookup on public.entity_comments(entity, entity_id, created_at desc);
alter table public.entity_comments enable row level security;
-- No policies: only SECURITY DEFINER functions / service role (admin-gated os_api) may read/write.

create or replace function public.fn_entity_comment_add(p_entity text, p_id text, p_author text, p_body text)
returns jsonb language plpgsql security definer set search_path to 'public','pg_catalog' as $$
declare r public.entity_comments%rowtype;
begin
  if coalesce(btrim(p_body),'') = '' then return jsonb_build_object('ok', false, 'error', 'empty'); end if;
  insert into public.entity_comments(entity, entity_id, author, body)
    values (p_entity, p_id, coalesce(nullif(btrim(p_author),''),'operator'), left(p_body, 4000))
    returning * into r;
  return jsonb_build_object('ok', true, 'id', r.id, 'at', r.created_at);
end $$;

create or replace function public.fn_entity_activity(p_entity text, p_id text)
returns jsonb language plpgsql stable security definer set search_path to 'public','pg_catalog' as $$
declare out jsonb := '[]'::jsonb; l public.leads%rowtype;
begin
  -- comments (all entities)
  out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','comment','title','Comment','actor',c.author,'body',c.body,'at',c.created_at)) from public.entity_comments c where c.entity=p_entity and c.entity_id=p_id),'[]'::jsonb);
  -- audit trail (all entities)
  out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','audit','title',a.action,'actor',a.actor,'at',a.at,'ok',a.ok)) from public.os_audit_log a where a.entity_id=p_id and (a.entity=p_entity or (p_entity='supplier' and a.entity in ('leads','supplier','suppliers')))),'[]'::jsonb);
  if p_entity = 'supplier' then
    select * into l from public.leads where id = p_id::bigint;
    if l.id is not null then
      out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','agent','title',coalesce(nullif(btrim(aa.title),''), aa.kind),'actor',aa.agent,'body',aa.recommendation,'at',aa.created_at,'status',aa.status)) from public.agent_actions aa where aa.target_table='leads' and aa.target_id::text = p_id),'[]'::jsonb);
      out := out || coalesce((select jsonb_agg(jsonb_build_object('kind','milestone','title',v.label,'actor','system','at',v.ts)) from (values
        ('Sourced', l.created_at),('Scraped', l.scraped_at),('Invited', l.invited_at),('AI reviewed', l.ai_reviewed_at),
        ('Documents extracted', l.doc_extracted_at),('Capability enriched', l.capability_enriched_at),
        ('Registration submitted', l.registration_submitted_at),('Terms accepted', l.accepted_terms_at),
        ('Terms signed', l.signed_terms_at),('Approved', l.approved_at)
      ) v(label, ts) where v.ts is not null),'[]'::jsonb);
    end if;
  end if;
  return coalesce((select jsonb_agg(e) from (select e from jsonb_array_elements(out) e where (e->>'at') is not null order by (e->>'at') desc limit 80) z),'[]'::jsonb);
end $$;
