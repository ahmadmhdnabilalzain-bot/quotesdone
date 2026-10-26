-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706120703   name: feature_flags_and_experiments
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ FEATURE FLAG PLATFORM ============
create table if not exists public.feature_flags(
  key text primary key, enabled boolean default false, rollout_pct int default 100,
  audience jsonb default '{}',   -- {"country":["AE"],"category":["security"],"role":["beta"],"beta":true,"enterprise":true}
  description text, updated_at timestamptz default now());
alter table public.feature_flags enable row level security;
revoke all on public.feature_flags from anon, authenticated;

-- deterministic flag evaluation for a subject/context
create or replace function public.fn_flag(p_key text, p_ctx jsonb default '{}')
returns boolean language plpgsql stable security definer set search_path=public,pg_temp as $$
declare f record; aud jsonb; h int; subj text;
begin
  select * into f from feature_flags where key=p_key;
  if f is null or not f.enabled then return false; end if;
  aud := coalesce(f.audience,'{}');
  -- audience gates
  if aud ? 'country' and not (upper(coalesce(p_ctx->>'country','')) = any(select upper(jsonb_array_elements_text(aud->'country')))) then return false; end if;
  if aud ? 'category' and not (lower(coalesce(p_ctx->>'category','')) = any(select lower(jsonb_array_elements_text(aud->'category')))) then return false; end if;
  if aud ? 'role' and not (lower(coalesce(p_ctx->>'role','')) = any(select lower(jsonb_array_elements_text(aud->'role')))) then return false; end if;
  if coalesce((aud->>'enterprise')::boolean,false) and not coalesce((p_ctx->>'enterprise')::boolean,false) then return false; end if;
  -- percentage rollout, deterministic by subject
  subj := coalesce(p_ctx->>'subject', p_ctx->>'email', p_ctx->>'id', 'anon');
  h := (abs(('x'||substr(md5(p_key||':'||subj),1,8))::bit(32)::int) % 100);
  return h < coalesce(f.rollout_pct,100);
end $$;

insert into public.feature_flags(key,enabled,rollout_pct,audience,description) values
 ('structured_quote_form', false, 100, '{"role":["supplier"]}', 'Native structured BOQ quote entry in supplier portal'),
 ('ai_grounding_hard_gate', false, 100, '{}', 'Reject ungrounded AI answers (enforce citations)'),
 ('ksa_market', false, 100, '{"country":["SA"]}', 'Saudi Arabia market surfaces'),
 ('enterprise_procurement', false, 100, '{"enterprise":true}', 'Enterprise procurement workspace features')
on conflict (key) do nothing;

-- ============ EXPERIMENT / A-B PLATFORM ============
create table if not exists public.experiments(
  key text primary key, status text default 'running', metric text,
  variants jsonb not null,   -- [{"name":"A","weight":50},{"name":"B","weight":50}]
  started_at timestamptz default now(), stopped_at timestamptz);
create table if not exists public.experiment_assignments(
  experiment text references public.experiments(key), subject text, variant text,
  assigned_at timestamptz default now(), primary key(experiment,subject));
create table if not exists public.experiment_events(
  id bigserial primary key, experiment text, subject text, variant text, event text, value numeric, ts timestamptz default now());
do $$ begin
  execute 'alter table public.experiments enable row level security'; execute 'revoke all on public.experiments from anon, authenticated';
  execute 'alter table public.experiment_assignments enable row level security'; execute 'revoke all on public.experiment_assignments from anon, authenticated';
  execute 'alter table public.experiment_events enable row level security'; execute 'revoke all on public.experiment_events from anon, authenticated'; end $$;

-- deterministic weighted assignment
create or replace function public.fn_experiment_assign(p_key text, p_subject text)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare e record; existing text; roll int; acc int:=0; v jsonb; chosen text;
begin
  select * into e from experiments where key=p_key and status='running';
  if e is null then return null; end if;
  select variant into existing from experiment_assignments where experiment=p_key and subject=p_subject;
  if existing is not null then return existing; end if;
  roll := (abs(('x'||substr(md5(p_key||':'||p_subject),1,8))::bit(32)::int) % 100);
  for v in select * from jsonb_array_elements(e.variants) loop
    acc := acc + coalesce((v->>'weight')::int,0);
    if roll < acc then chosen := v->>'name'; exit; end if;
  end loop;
  chosen := coalesce(chosen, (e.variants->0->>'name'));
  insert into experiment_assignments(experiment,subject,variant) values(p_key,p_subject,chosen) on conflict do nothing;
  return chosen;
end $$;

create or replace function public.fn_experiment_record(p_key text, p_subject text, p_event text, p_value numeric default 1)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v text;
begin
  select variant into v from experiment_assignments where experiment=p_key and subject=p_subject;
  insert into experiment_events(experiment,subject,variant,event,value) values(p_key,p_subject,v,p_event,p_value);
end $$;

create or replace function public.fn_experiment_results(p_key text)
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
  select jsonb_object_agg(variant, stats) from (
    select a.variant,
      jsonb_build_object(
        'subjects', count(distinct a.subject),
        'conversions', count(distinct e.subject) filter (where e.event='convert'),
        'conv_rate_pct', round(100.0*count(distinct e.subject) filter (where e.event='convert')/nullif(count(distinct a.subject),0),1)
      ) stats
    from experiment_assignments a left join experiment_events e on e.experiment=a.experiment and e.subject=a.subject
    where a.experiment=p_key group by a.variant) z;
$$;

insert into public.experiments(key,metric,variants) values
 ('homepage_cta','reveal_conversion','[{"name":"A","weight":50},{"name":"B","weight":50}]'),
 ('supplier_invite_count','quotes_per_rfq','[{"name":"three","weight":50},{"name":"five","weight":50}]')
on conflict (key) do nothing;

select public.fn_experiment_assign('homepage_cta','visitor-123') as variant;
