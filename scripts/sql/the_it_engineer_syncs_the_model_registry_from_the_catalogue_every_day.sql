-- THE IT ENGINEER COMPARES THE MODEL REGISTRY WITH THE CATALOGUE EVERY DAY, AND RECORDS WHAT MOVED.
-- Seat: it_engineer. 5 Oct 2026, follow-up item 28; reshaped 18 Oct 2026 on independent review (rulings 1217/1218).
--
-- WHY: model_registry and model_rate state prices and context lengths that a third party (OpenRouter) changes
--   without telling us. Until now a move was only noticed when the CI price check went red, and a person wrote a
--   correcting file (four times between 30 Sep and 12 Oct).
--
-- A RECORD, NEVER A WRITE. Model prices and the model matrix are the founder's (rulings 1217, 1218). This file
--   changes NO price, NO context length and NO registry or model_rate row, ever. A move the catalogue makes is
--   recorded and raised as a finding; the correction stays what it was: a reviewed SQL file, merged by PR.
--   1. public.model_catalogue_change: one open row per model and field (in / out / ctx / absent) the catalogue and
--      the registry disagree on, with the drift and whether the founder's matrix names the model. It closes by itself
--      ('resolved') once the two agree again - after a reviewed correction, or the catalogue moving back.
--   2. fn_model_catalogue_decide(registry, matrix, catalogue): PURE, no table read. Lists every disagreement:
--      'changed' (a price or context the catalogue serves differently; ':online' priced as its base model) or
--      'absent' (an active model the catalogue does not list).
--   3. fn_model_catalogue_sync(catalogue): the daily duty (it_duty_schedule 'model_catalogue'; resilience_ping
--      itlater step model_catalogue fetches GET https://openrouter.ai/api/v1/models - public, no key, not inference).
--      Records the rows above and raises one it_engineer finding per open row (duty:model_catalogue:change:<model>:
--      <field>, duty:model_catalogue:absent:<model>) through fn_it_duty_settle, which closes it once the row resolves.
--
-- PAUSE: insert into public.duty_pause (duty, reason, paused_by) values ('resilience_ping.model_catalogue', '<why>', '<seat>');
--
-- Pending: scripts/sql/pending/the_it_engineer_syncs_the_model_registry_from_the_catalogue_every_day.txt
-- Proved by: scripts/sql/the_it_engineer_syncs_the_model_registry_from_the_catalogue_every_day_probe.sql (ZZ DEMO
--   rows; it ends in raise exception, so the whole replay rolls back; sent through scripts/lib/safe_replay.mjs).
-- Prevented by: scripts/checks/the_registry_prices_are_the_catalogue_s_prices.test.mjs (strict per-model comparison
--   with the catalogue, the sync is fresh, and the probe replayed).
-- Idempotent, no begin/commit.

-- 1. THE CHANGE LEDGER
create table if not exists public.model_catalogue_change (
  id            bigint generated always as identity primary key,
  model_id      text        not null,
  field         text        not null check (field in ('in', 'out', 'ctx', 'absent')),
  old_value     numeric,
  new_value     numeric,
  drift_pct     numeric,
  matrix        boolean     not null,
  outcome       text        check (outcome in ('resolved')),
  closed_at     timestamptz,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now()
);
create unique index if not exists model_catalogue_change_one_open
  on public.model_catalogue_change (model_id, field) where closed_at is null;

alter table public.model_catalogue_change enable row level security;
drop policy if exists model_catalogue_change_service_role_only on public.model_catalogue_change;
create policy model_catalogue_change_service_role_only on public.model_catalogue_change
  as permissive for all to public using (false) with check (false);
revoke all on public.model_catalogue_change from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('model_catalogue_change', true, 'model_routing', 'every price, context or listing the catalogue serves differently from model_registry, recorded by the daily sync (follow-up 28); the sync writes no price', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

insert into public.it_duty_schedule (duty, every, note, owner_seat) values
  ('model_catalogue', interval '1 day',
   'model_registry against the public OpenRouter catalogue (fn_model_catalogue_sync): every disagreement recorded and raised as a finding; the sync never changes a price or a registry row', 'it_engineer')
on conflict (duty) do update set every = excluded.every, note = excluded.note, owner_seat = excluded.owner_seat;

-- 2. THE COMPARISON, PURE
-- p_registry  [{model_id, in, out, ctx}]  (USD per Mtok, tokens)
-- p_matrix    the model ids of the founder's matrix
-- p_catalogue [{id, context_length, pricing:{prompt, completion}}]  (USD per token, as OpenRouter serves it)
create or replace function public.fn_model_catalogue_decide(p_registry jsonb, p_matrix text[], p_catalogue jsonb)
returns table (model_id text, field text, old_value numeric, new_value numeric, drift_pct numeric, matrix boolean, decision text)
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  with reg as (
    select r->>'model_id' as id, (r->>'in')::numeric as v_in, (r->>'out')::numeric as v_out, (r->>'ctx')::numeric as v_ctx,
           (r->>'model_id') = any (coalesce(p_matrix, '{}')) as m
      from jsonb_array_elements(coalesce(p_registry, '[]')) r
  ), cat as (
    select c->>'id' as id,
           round(nullif(c->'pricing'->>'prompt', '')::numeric * 1000000, 4)     as l_in,
           round(nullif(c->'pricing'->>'completion', '')::numeric * 1000000, 4) as l_out,
           nullif(c->>'context_length', '')::numeric                             as l_ctx
      from jsonb_array_elements(coalesce(p_catalogue, '[]')) c
  ), joined as (
    -- exact id first; a variant such as ':online' is priced as its base model
    select reg.*, coalesce(e.id, b.id) as cid,
           coalesce(e.l_in, b.l_in) l_in, coalesce(e.l_out, b.l_out) l_out, coalesce(e.l_ctx, b.l_ctx) l_ctx
      from reg
      left join cat e on e.id = reg.id
      left join cat b on e.id is null and b.id = split_part(reg.id, ':', 1)
  ), pairs as (
    select j.id, j.m, f.field, f.o, f.l
      from joined j
      cross join lateral (values ('in', j.v_in, j.l_in), ('out', j.v_out, j.l_out), ('ctx', j.v_ctx, j.l_ctx)) f(field, o, l)
     where j.cid is not null
  )
  select p.id, p.field, p.o, p.l,
         case when coalesce(p.o, 0) = 0 then null else round(abs(p.l - p.o) / p.o * 100, 2) end,
         p.m, 'changed'
    from pairs p
   where p.l is not null and p.o is distinct from p.l
  union all
  select j.id, 'absent', null, null, null, j.m, 'absent' from joined j where j.cid is null
$fn$;
revoke execute on function public.fn_model_catalogue_decide(jsonb, text[], jsonb) from public, anon, authenticated;
grant execute on function public.fn_model_catalogue_decide(jsonb, text[], jsonb) to service_role;

-- The founder's matrix, read from the routing tables themselves so it never needs a second copy.
create or replace function public.fn_model_catalogue_matrix()
returns text[]
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(array_agg(distinct m) filter (where m is not null), '{}') from (
    select model_primary m from public.model_policy where active
    union all select model_fallback from public.model_policy where active
    union all select primary_model from public.model_policy_by_identity
    union all select fallback_model from public.model_policy_by_identity
    union all select model_id from public.review_pool where active
  ) x
$fn$;
revoke execute on function public.fn_model_catalogue_matrix() from public, anon, authenticated;
grant execute on function public.fn_model_catalogue_matrix() to service_role;

-- 3. THE DAILY SYNC: RECORD AND RAISE, NEVER WRITE A PRICE
-- p_only / p_matrix exist for the probe: with p_only set, only those models are read, and NO finding is settled and
-- no run is recorded (settling one duty sweeps every open finding of that duty it does not name).
create or replace function public.fn_model_catalogue_sync(p_catalogue jsonb, p_only text[] default null, p_matrix text[] default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_reg jsonb; v_matrix text[]; d record; c public.model_catalogue_change; v_items jsonb := '[]'::jsonb;
  n_open int := 0; n_new int := 0; n_resolved int := 0; v_res jsonb;
begin
  if jsonb_typeof(p_catalogue) is distinct from 'array' or jsonb_array_length(p_catalogue) < 50 then
    raise exception 'fn_model_catalogue_sync: the catalogue is not an array of at least 50 models (got %), so nothing is compared',
      coalesce(jsonb_typeof(p_catalogue), 'null') || case when jsonb_typeof(p_catalogue) = 'array' then ' of ' || jsonb_array_length(p_catalogue) else '' end;
  end if;
  v_matrix := coalesce(p_matrix, public.fn_model_catalogue_matrix());
  select coalesce(jsonb_agg(jsonb_build_object('model_id', r.model_id, 'in', r.in_per_mtok_usd, 'out', r.out_per_mtok_usd,
                                               'ctx', r.context_len)), '[]')
    into v_reg from public.model_registry r
   where r.active and (p_only is null or r.model_id = any (p_only));

  for d in select * from public.fn_model_catalogue_decide(v_reg, v_matrix, p_catalogue) loop
    select * into c from public.model_catalogue_change
     where model_id = d.model_id and field = d.field and closed_at is null;
    if not found then
      insert into public.model_catalogue_change (model_id, field, old_value, new_value, drift_pct, matrix)
      values (d.model_id, d.field, d.old_value, d.new_value, d.drift_pct, d.matrix) returning * into c;
      n_new := n_new + 1;
    else
      update public.model_catalogue_change
         set old_value = d.old_value, new_value = d.new_value, drift_pct = d.drift_pct, matrix = d.matrix, last_seen_at = now()
       where id = c.id returning * into c;
    end if;
    n_open := n_open + 1;
    v_items := v_items || case when d.decision = 'absent' then
      jsonb_build_object('item', 'absent:' || d.model_id, 'owner_seat', 'it_engineer', 'subject', d.model_id,
        'blast', case when d.matrix then 'customer_facing' else 'internal' end,
        'title', d.model_id || ' is active in model_registry but the OpenRouter catalogue no longer lists it'
                 || case when d.matrix then ' - a route of the founder''s matrix names it, so those calls will fail at the provider' else '' end,
        'evidence', jsonb_build_object('change_id', c.id, 'model_id', d.model_id, 'matrix', d.matrix))
    else
      jsonb_build_object('item', 'change:' || d.model_id || ':' || d.field, 'owner_seat', 'it_engineer',
        'subject', d.model_id, 'blast', 'internal',
        'title', 'The catalogue serves ' || d.model_id || ' ' || d.field || ' at ' || d.new_value || ', the registry states '
                 || coalesce(d.old_value::text, 'null') || coalesce(' (' || d.drift_pct || '%)', '')
                 || case when d.matrix then ', a model of the founder''s matrix' else '' end
                 || '. Nothing was changed: a correction is a reviewed SQL file.',
        'evidence', jsonb_build_object('change_id', c.id, 'model_id', d.model_id, 'field', d.field, 'old', d.old_value,
                                       'new', d.new_value, 'drift_pct', d.drift_pct, 'matrix', d.matrix))
    end;
  end loop;

  -- An open row the catalogue and the registry agree on again is resolved.
  with gone as (
    update public.model_catalogue_change m set outcome = 'resolved', closed_at = now()
     where m.closed_at is null
       and (p_only is null or m.model_id = any (p_only))
       and not exists (select 1 from public.fn_model_catalogue_decide(v_reg, v_matrix, p_catalogue) x
                        where x.model_id = m.model_id and x.field = m.field)
    returning 1)
  select count(*) into n_resolved from gone;

  v_res := jsonb_build_object('compared', jsonb_array_length(v_reg), 'open', n_open, 'new', n_new,
                              'resolved', n_resolved, 'items', v_items);
  if p_only is null then
    v_res := v_res || jsonb_build_object('settle', public.fn_it_duty_settle('model_catalogue', v_items));
    perform public.fn_it_duty_ran('model_catalogue', v_res - 'items');
  end if;
  return v_res;
end $fn$;
revoke execute on function public.fn_model_catalogue_sync(jsonb, text[], text[]) from public, anon, authenticated;
grant execute on function public.fn_model_catalogue_sync(jsonb, text[], text[]) to service_role;
