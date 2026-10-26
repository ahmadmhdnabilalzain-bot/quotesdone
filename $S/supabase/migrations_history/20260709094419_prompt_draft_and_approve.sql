-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709094419   name: prompt_draft_and_approve
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- author a new prompt version as a DRAFT (does not touch the live active_version)
create or replace function public.fn_prompt_draft(p_key text, p_content text, p_by text default 'ai_trainer')
returns int language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v int;
begin
  insert into public.prompts(key,owner) values(p_key,p_by) on conflict(key) do update set updated_at=now();
  select coalesce(max(version),0)+1 into v from prompt_versions where prompt_key=p_key;
  insert into prompt_versions(prompt_key,version,content,status,rollout_pct,approved_by)
    values(p_key,v,p_content,'draft',0,null);
  return v;
end $$;
revoke all on function public.fn_prompt_draft(text,text,text) from anon, authenticated, public;

-- founder approves a draft -> it becomes the live active version (deprecates the old one)
create or replace function public.fn_prompt_approve_draft(p_key text, p_version int, p_by text default 'founder')
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if not exists(select 1 from prompt_versions where prompt_key=p_key and version=p_version and status='draft') then
    return jsonb_build_object('error','draft_not_found'); end if;
  update prompt_versions set status='deprecated' where prompt_key=p_key and status='active';
  update prompt_versions set status='active', rollout_pct=100, approved_by=p_by where prompt_key=p_key and version=p_version;
  update prompts set active_version=p_version, updated_at=now() where key=p_key;
  update agent_actions set status='approved', decided_at=now(), decided_by=p_by
    where kind='prompt_approval' and detail->>'key'=p_key and (detail->>'version')::int=p_version and status in ('pending','needs_review');
  return jsonb_build_object('ok',true,'active_version',p_version);
end $$;
revoke all on function public.fn_prompt_approve_draft(text,int,text) from anon, authenticated, public;

-- reject a drafted prompt (discard)
create or replace function public.fn_prompt_reject_draft(p_key text, p_version int, p_by text default 'founder')
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  update prompt_versions set status='discarded' where prompt_key=p_key and version=p_version and status='draft';
  update agent_actions set status='rejected', decided_at=now(), decided_by=p_by
    where kind='prompt_approval' and detail->>'key'=p_key and (detail->>'version')::int=p_version and status in ('pending','needs_review');
  return jsonb_build_object('ok',true);
end $$;
revoke all on function public.fn_prompt_reject_draft(text,int,text) from anon, authenticated, public;
