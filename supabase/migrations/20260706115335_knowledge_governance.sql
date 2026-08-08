-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706115335   name: knowledge_governance
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ KNOWLEDGE GOVERNANCE: versioning + review + AI validation ============
create table if not exists public.kb_revisions(
  id bigserial primary key,
  entry_kind text not null,           -- 'agent_knowledge' | 'regulation' | 'checklist'
  entry_ref text not null,            -- id or agent_key/topic
  version int not null,
  content text,
  status text not null default 'published',  -- draft|in_review|approved|published|rejected
  author text, reviewer text, review_notes text,
  ai_validation jsonb,
  created_at timestamptz default now(), decided_at timestamptz,
  unique(entry_kind, entry_ref, version));
create index if not exists idx_kbrev on public.kb_revisions(entry_kind, entry_ref, version desc);
alter table public.kb_revisions enable row level security;
revoke all on public.kb_revisions from anon, authenticated;

create or replace function public._kb_next_ver(k text, r text) returns int
language sql stable security definer set search_path=public,pg_temp as
$$ select coalesce(max(version),0)+1 from public.kb_revisions where entry_kind=k and entry_ref=r $$;

-- deterministic AI-validation checks (flags entries needing human/LLM review)
create or replace function public.fn_kb_validate(p_content text)
returns jsonb language plpgsql immutable set search_path=public,pg_temp as $$
declare flags text[]:='{}'; ok boolean:=true;
begin
  if length(coalesce(p_content,'')) < 40 then flags:=array_append(flags,'too_short'); ok:=false; end if;
  if p_content !~* '(source|per |according to|standard|code|regulation|SIRA|DCD|DEWA|ISO|IEC|BS |EN |NFPA|Estidama|ESMA|[0-9])' then
     flags:=array_append(flags,'no_citation_or_specifics'); ok:=false; end if;
  if p_content ~* '(always|never|guaranteed|100%|best in the world)' then flags:=array_append(flags,'absolute_claim_review'); end if;
  return jsonb_build_object('passed',ok,'flags',to_jsonb(flags),'checked_at',now());
end $$;

-- auto-version agent_knowledge on change (published history)
create or replace function public.trg_kb_version() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if TG_OP='INSERT' or NEW.content is distinct from OLD.content then
    insert into public.kb_revisions(entry_kind,entry_ref,version,content,status,author,ai_validation)
    values ('agent_knowledge', NEW.agent_key||' :: '||NEW.topic, public._kb_next_ver('agent_knowledge',NEW.agent_key||' :: '||NEW.topic),
            NEW.content,'published','system', public.fn_kb_validate(NEW.content))
    on conflict do nothing;
  end if;
  return NEW;
end $$;
drop trigger if exists kb_version on public.agent_knowledge;
create trigger kb_version after insert or update of content on public.agent_knowledge
  for each row execute function public.trg_kb_version();

-- governed edit workflow (for regulations / curated knowledge)
create or replace function public.fn_kb_submit_revision(p_kind text, p_ref text, p_content text, p_author text default 'agent')
returns bigint language plpgsql security definer set search_path=public,pg_temp as $$
declare id bigint;
begin
  insert into public.kb_revisions(entry_kind,entry_ref,version,content,status,author,ai_validation)
  values (p_kind,p_ref, public._kb_next_ver(p_kind,p_ref), p_content, 'in_review', p_author, public.fn_kb_validate(p_content))
  returning id into id;
  return id;
end $$;

create or replace function public.fn_kb_approve(p_revision bigint, p_reviewer text, p_notes text default null, p_publish boolean default true)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare r record;
begin
  select * into r from public.kb_revisions where id=p_revision;
  if r is null then return jsonb_build_object('error','revision not found'); end if;
  update public.kb_revisions set status=case when p_publish then 'published' else 'approved' end,
    reviewer=p_reviewer, review_notes=p_notes, decided_at=now() where id=p_revision;
  -- apply to live agent_knowledge when publishing that kind
  if p_publish and r.entry_kind='agent_knowledge' and position(' :: ' in r.entry_ref)>0 then
    update agent_knowledge set content=r.content
     where agent_key=split_part(r.entry_ref,' :: ',1) and topic=split_part(r.entry_ref,' :: ',2);
  end if;
  return jsonb_build_object('ok',true,'revision',p_revision,'status',case when p_publish then 'published' else 'approved' end);
end $$;

-- backfill: snapshot current agent_knowledge as v-history baseline (published)
insert into public.kb_revisions(entry_kind,entry_ref,version,content,status,author,ai_validation)
select 'agent_knowledge', agent_key||' :: '||topic, 1, content, 'published','baseline', public.fn_kb_validate(content)
from public.agent_knowledge
on conflict (entry_kind,entry_ref,version) do nothing;

select count(*) as revisions, count(*) filter (where not (ai_validation->>'passed')::boolean) as flagged_for_review
from public.kb_revisions;
