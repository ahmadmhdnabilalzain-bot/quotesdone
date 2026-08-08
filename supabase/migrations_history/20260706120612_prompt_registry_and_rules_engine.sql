-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706120612   name: prompt_registry_and_rules_engine
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ PROMPT REGISTRY ============
create table if not exists public.prompts(
  key text primary key, owner text, description text,
  active_version int default 1, updated_at timestamptz default now());
create table if not exists public.prompt_versions(
  id bigserial primary key, prompt_key text references public.prompts(key),
  version int not null, content text not null, status text default 'active', -- draft|active|deprecated
  rollout_pct int default 100, eval_score numeric, approved_by text,
  created_at timestamptz default now(), unique(prompt_key, version));
do $$ begin execute 'alter table public.prompts enable row level security'; execute 'revoke all on public.prompts from anon, authenticated';
  execute 'alter table public.prompt_versions enable row level security'; execute 'revoke all on public.prompt_versions from anon, authenticated'; end $$;

create or replace function public.fn_prompt_publish(p_key text, p_content text, p_owner text default 'agent', p_rollout int default 100)
returns int language plpgsql security definer set search_path=public,pg_temp as $$
declare v int;
begin
  insert into public.prompts(key,owner) values(p_key,p_owner) on conflict(key) do update set updated_at=now();
  select coalesce(max(version),0)+1 into v from prompt_versions where prompt_key=p_key;
  insert into prompt_versions(prompt_key,version,content,status,rollout_pct,approved_by) values(p_key,v,p_content,'active',p_rollout,p_owner);
  update prompt_versions set status='deprecated' where prompt_key=p_key and version<v and status='active';
  update prompts set active_version=v, updated_at=now() where key=p_key;
  return v;
end $$;

create or replace function public.fn_prompt_get(p_key text)
returns text language sql stable security definer set search_path=public,pg_temp as $$
  select content from prompt_versions pv join prompts p on p.key=pv.prompt_key
  where pv.prompt_key=p_key and pv.version=p.active_version limit 1;
$$;

create or replace function public.fn_prompt_rollback(p_key text, p_to_version int, p_by text default 'agent')
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not exists(select 1 from prompt_versions where prompt_key=p_key and version=p_to_version) then
     return jsonb_build_object('error','version not found'); end if;
  update prompt_versions set status='deprecated' where prompt_key=p_key and status='active';
  update prompt_versions set status='active', approved_by=p_by where prompt_key=p_key and version=p_to_version;
  update prompts set active_version=p_to_version, updated_at=now() where key=p_key;
  return jsonb_build_object('ok',true,'active_version',p_to_version);
end $$;

-- seed a couple of core prompts from live personas as registry baselines
select public.fn_prompt_publish('intake.system',
  'You are QuotesDone''s procurement intake specialist. Guide the buyer to a complete, comparable RFQ using the category''s engineered qualification checklist. Keep asking focused questions until the RFQ completeness score reaches 70+. Retrieve category/regulation/material knowledge before advising; cite sources; never invent specifications.', 'founder');
select public.fn_prompt_publish('quote_review.system',
  'You are QuotesDone''s quotation reviewer. Score each quote against the hard evaluation standard (BOQ, brand/model, specs, labour, warranty, lead time, payment terms, exclusions, validity). Block sub-threshold quotes and tell the supplier exactly what to add. Never reveal supplier identity. Base every judgement on the quotation content and category standards.', 'founder');

-- ============ BUSINESS RULES ENGINE ============
create table if not exists public.business_rules(
  id bigserial primary key, name text, category text, priority int default 100,
  when_json jsonb not null, then_json jsonb not null, active boolean default true,
  created_at timestamptz default now());
alter table public.business_rules enable row level security;
revoke all on public.business_rules from anon, authenticated;

-- evaluator: match rules against a context, aggregate required actions
create or replace function public.fn_rules_eval(p_ctx jsonb)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare r record; matched jsonb:='[]'; reqs text[]:='{}'; ok boolean; k text; cond jsonb; want text; got text;
begin
  for r in select * from business_rules where active order by priority loop
    ok := true;
    for k in select jsonb_object_keys(r.when_json) loop
      cond := r.when_json->k;
      if jsonb_typeof(cond)='object' and cond ? 'gt' then
        if coalesce(nullif(p_ctx->>k,'')::numeric,0) <= (cond->>'gt')::numeric then ok:=false; end if;
      elsif jsonb_typeof(cond)='object' and cond ? 'gte' then
        if coalesce(nullif(p_ctx->>k,'')::numeric,0) < (cond->>'gte')::numeric then ok:=false; end if;
      elsif jsonb_typeof(cond)='object' and cond ? 'in' then
        if not (lower(coalesce(p_ctx->>k,'')) = any(select lower(jsonb_array_elements_text(cond->'in')))) then ok:=false; end if;
      else
        if lower(coalesce(p_ctx->>k,'')) <> lower(cond#>>'{}') then ok:=false; end if;
      end if;
      exit when not ok;
    end loop;
    if ok then
      matched := matched || jsonb_build_object('rule',r.name,'then',r.then_json);
      if r.then_json ? 'require' then
        reqs := reqs || array(select jsonb_array_elements_text(r.then_json->'require'));
      end if;
    end if;
  end loop;
  return jsonb_build_object('matched',matched,'required',to_jsonb((select array_agg(distinct x) from unnest(reqs) x)));
end $$;

insert into public.business_rules(name,category,priority,when_json,then_json) values
 ('High-value fire safety','fire',10,
  '{"category":"fire","amount_aed":{"gt":1000000}}',
  '{"require":["ISO 9001","Civil Defence approval","Professional indemnity insurance","Manufacturer authorization"],"escalate":true}'),
 ('Security requires SIRA','security',20,
  '{"category":{"in":["security","cctv-security"]}}',
  '{"require":["SIRA approval","EN 62676 compliance"]}'),
 ('Electrical requires DEWA','electrical',20,
  '{"category":"electrical"}',
  '{"require":["DEWA/authority NOC","BS 7671 compliance"]}'),
 ('Large project needs references','all',50,
  '{"amount_aed":{"gt":500000}}',
  '{"require":["Client references","Completed similar projects"]}')
on conflict do nothing;

select public.fn_rules_eval('{"category":"fire","amount_aed":1500000}'::jsonb) as fire_1_5m;
