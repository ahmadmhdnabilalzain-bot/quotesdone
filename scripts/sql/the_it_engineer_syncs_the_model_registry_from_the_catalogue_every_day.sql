-- THE IT ENGINEER SYNCS THE MODEL REGISTRY FROM THE CATALOGUE EVERY DAY.
-- Seat: it_engineer. 5 Oct 2026, follow-up item 28.
--
-- WHY: model_registry and model_rate state prices and context lengths that a third party (OpenRouter) changes
--   without telling us. Until now a person corrected them by hand, one file per move (glm_5_3_flash_costs_what_the_
--   catalogue_now_charges.sql, glm_5_3_flash_is_back_at_the_price_it_was_ruled_at.sql, deepseek_v4_1_flash_costs_
--   what_the_catalogue_now_charges.sql), and the CI check the_registry_prices_are_the_catalogue_s_prices went red on
--   every provider price move in between. MEASURED 5 Oct 2026: the catalogue serves deepseek/deepseek-v4.1-flash at
--   USD 0.003 in / 2.40 out per Mtok against the registry's 0.0198 / 0.396, and perplexity/sonar at 127,072 context
--   against 127,000 - a fourth hand-written file would be due today.
--
-- WHAT THIS ADDS
--   1. public.model_catalogue_change: one row per field (in / out / ctx) that the catalogue and the registry disagree on.
--   2. fn_model_catalogue_decide(registry, matrix, catalogue): PURE, no table read. The rule:
--        * a model in the founder's matrix (ruling 1056: any model an active model_policy, model_policy_by_identity or
--          review_pool row names) -> ANY change is HELD;
--        * any other model -> a drift of at most 20% of the registry's value is AUTO, more than 20% is HELD;
--        * a registry value of null or 0 has no drift to measure -> HELD;
--        * an active model the catalogue does not list (exactly, or by its base id before ':') -> ABSENT.
--   3. fn_model_catalogue_sync(catalogue): the daily duty (it_duty_schedule 'model_catalogue', resilience_ping itlater
--      step model_catalogue fetches GET https://openrouter.ai/api/v1/models - public, no key, not inference). AUTO
--      changes are written to model_registry and model_rate at once, with a note. A HELD change raises a finding
--      (duty:model_catalogue:change:<model>:<field>, through fn_it_duty_settle) and is applied only on a later run
--      once fn_model_catalogue_reason has given it a reason; the finding is then closed with that reason. A catalogue
--      that moves again replaces the held value and clears a reason given for the old one.
--   4. model_rate is now written, so it leaves the no_writer exclusion and is exported; model_catalogue_change is
--      exported too.
--
-- PAUSE: insert into public.duty_pause (duty, reason, paused_by) values ('resilience_ping.model_catalogue', '<why>', '<seat>');
-- GIVE A REASON: select public.fn_model_catalogue_reason(<change id>, '<why the new value is accepted>', '<seat>');
--
-- Pending: scripts/sql/pending/the_it_engineer_syncs_the_model_registry_from_the_catalogue_every_day.txt
-- Proved by: the verdict-row probe at the end of this file (ZZ DEMO model ids, cleaned up).
-- Prevented by: scripts/checks/the_registry_prices_are_the_catalogue_s_prices.test.mjs (the sync is FRESH, and the
--   decision rule replayed on synthetic rows).
-- Idempotent, no begin/commit.

-- ── 1. THE CHANGE LEDGER ────────────────────────────────────────────────────────────────────────────
create table if not exists public.model_catalogue_change (
  id          bigint generated always as identity primary key,
  model_id    text        not null,
  field       text        not null check (field in ('in', 'out', 'ctx')),
  old_value   numeric,
  new_value   numeric     not null,
  drift_pct   numeric,
  matrix      boolean     not null,
  decision    text        not null check (decision in ('auto', 'held')),
  reason      text,
  reasoned_by text,
  reasoned_at timestamptz,
  outcome     text        check (outcome in ('applied', 'withdrawn')),
  closed_at   timestamptz,
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
  ('model_catalogue_change', true, 'model_routing', 'every price or context change the daily catalogue sync applied or held, with its reason (follow-up 28)', 'it_engineer'),
  ('model_rate', true, 'model_routing', 'written by fn_model_catalogue_sync since follow-up 28 (5 Oct 2026): the per-model rate fn_llm_log prices every call from', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

insert into public.it_duty_schedule (duty, every, note, owner_seat) values
  ('model_catalogue', interval '1 day',
   'model_registry and model_rate against the public OpenRouter catalogue (fn_model_catalogue_sync): small drift on a non-matrix model applied, anything else held behind a finding until it has a reason', 'it_engineer')
on conflict (duty) do update set every = excluded.every, note = excluded.note, owner_seat = excluded.owner_seat;

-- ── 2. THE RULE, PURE ───────────────────────────────────────────────────────────────────────────────
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
    select j.id, j.m, f.field, f.o, f.l, j.cid
      from joined j
      cross join lateral (values ('in', j.v_in, j.l_in), ('out', j.v_out, j.l_out), ('ctx', j.v_ctx, j.l_ctx)) f(field, o, l)
     where j.cid is not null
  )
  select p.id, p.field, p.o, p.l,
         case when coalesce(p.o, 0) = 0 then null else round(abs(p.l - p.o) / p.o * 100, 2) end,
         p.m,
         case when p.m then 'held'
              when coalesce(p.o, 0) = 0 then 'held'
              when abs(p.l - p.o) / p.o <= 0.20 then 'auto'
              else 'held' end
    from pairs p
   where p.l is not null and p.o is distinct from p.l
  union all
  select j.id, null, null, null, null, j.m, 'absent' from joined j where j.cid is null
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

-- ── 3. APPLYING ONE FIELD ───────────────────────────────────────────────────────────────────────────
create or replace function public.fn_model_catalogue_apply(p_model text, p_field text, p_value numeric, p_note text)
returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if p_field = 'in' then
    update public.model_registry set in_per_mtok_usd = p_value, updated_at = now() where model_id = p_model;
    update public.model_rate set usd_per_m_prompt = p_value, in_aed_per_mtok = round(p_value * 3.6725, 6),
           verified_at = current_date, source_url = 'https://openrouter.ai/api/v1/models', note = left(p_note, 500)
     where model = p_model;
  elsif p_field = 'out' then
    update public.model_registry set out_per_mtok_usd = p_value, updated_at = now() where model_id = p_model;
    update public.model_rate set usd_per_m_output = p_value, out_aed_per_mtok = round(p_value * 3.6725, 6),
           verified_at = current_date, source_url = 'https://openrouter.ai/api/v1/models', note = left(p_note, 500)
     where model = p_model;
  elsif p_field = 'ctx' then
    update public.model_registry set context_len = p_value::int, updated_at = now() where model_id = p_model;
  else
    raise exception 'fn_model_catalogue_apply: unknown field %', p_field;
  end if;
end $fn$;
revoke execute on function public.fn_model_catalogue_apply(text, text, numeric, text) from public, anon, authenticated;

-- ── 4. THE DAILY SYNC ───────────────────────────────────────────────────────────────────────────────
-- p_only / p_matrix exist for the probe: with p_only set, only those models are read and NO finding is settled and no
-- run is recorded (settling one duty sweeps every open finding of that duty it does not name).
create or replace function public.fn_model_catalogue_sync(p_catalogue jsonb, p_only text[] default null, p_matrix text[] default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_reg jsonb; v_matrix text[]; d record; c public.model_catalogue_change; v_items jsonb := '[]'::jsonb;
  n_auto int := 0; n_held int := 0; n_applied int := 0; n_withdrawn int := 0; n_absent int := 0; v_res jsonb;
  v_note text;
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
    if d.decision = 'absent' then
      n_absent := n_absent + 1;
      v_items := v_items || jsonb_build_object('item', 'absent:' || d.model_id, 'owner_seat', 'it_engineer', 'subject', d.model_id,
        'blast', case when d.matrix then 'customer_facing' else 'internal' end,
        'title', d.model_id || ' is active in model_registry but the OpenRouter catalogue no longer lists it'
                 || case when d.matrix then ' - a route of the founder''s matrix names it, so those calls will fail at the provider' else '' end,
        'evidence', jsonb_build_object('model_id', d.model_id, 'matrix', d.matrix));
      continue;
    end if;

    if d.decision = 'auto' then
      v_note := 'catalogue sync ' || current_date || ': ' || d.field || ' ' || coalesce(d.old_value::text, 'null') || ' -> '
                || d.new_value || ' (' || d.drift_pct || '% drift on a model outside the founder''s matrix, within the 20% line)';
      perform public.fn_model_catalogue_apply(d.model_id, d.field, d.new_value, v_note);
      -- an older held row for this field is superseded by what was just applied
      update public.model_catalogue_change set outcome = 'withdrawn', closed_at = now()
       where model_id = d.model_id and field = d.field and closed_at is null;
      insert into public.model_catalogue_change (model_id, field, old_value, new_value, drift_pct, matrix, decision, reason,
                                                 reasoned_by, reasoned_at, outcome, closed_at)
      values (d.model_id, d.field, d.old_value, d.new_value, d.drift_pct, d.matrix, 'auto', v_note,
              'it_engineer.model_catalogue', now(), 'applied', now());
      n_auto := n_auto + 1;
      continue;
    end if;

    -- HELD: one open row per model and field. A new catalogue value replaces the old one and clears its reason.
    select * into c from public.model_catalogue_change
     where model_id = d.model_id and field = d.field and closed_at is null;
    if not found then
      insert into public.model_catalogue_change (model_id, field, old_value, new_value, drift_pct, matrix, decision)
      values (d.model_id, d.field, d.old_value, d.new_value, d.drift_pct, d.matrix, 'held') returning * into c;
    elsif c.new_value is distinct from d.new_value or c.old_value is distinct from d.old_value then
      update public.model_catalogue_change
         set old_value = d.old_value, new_value = d.new_value, drift_pct = d.drift_pct, matrix = d.matrix, decision = 'held',
             reason = null, reasoned_by = null, reasoned_at = null, last_seen_at = now()
       where id = c.id returning * into c;
    else
      update public.model_catalogue_change set last_seen_at = now() where id = c.id returning * into c;
    end if;

    if c.reason is not null then
      perform public.fn_model_catalogue_apply(d.model_id, d.field, d.new_value,
        'catalogue sync ' || current_date || ': ' || d.field || ' ' || coalesce(d.old_value::text, 'null') || ' -> ' || d.new_value
        || ', held and accepted by ' || c.reasoned_by || ': ' || c.reason);
      update public.model_catalogue_change set outcome = 'applied', closed_at = now() where id = c.id;
      if p_only is null then
        perform public.fn_it_engineer_finding_close('duty:model_catalogue:change:' || d.model_id || ':' || d.field,
          'applied with the reason given by ' || c.reasoned_by || ': ' || c.reason);
      end if;
      n_applied := n_applied + 1;
    else
      n_held := n_held + 1;
      v_items := v_items || jsonb_build_object('item', 'change:' || d.model_id || ':' || d.field, 'owner_seat', 'it_engineer',
        'subject', d.model_id, 'blast', 'internal',
        'title', 'The catalogue changed ' || d.model_id || ' ' || d.field || ' from ' || coalesce(d.old_value::text, 'null') || ' to '
                 || d.new_value || coalesce(' (' || d.drift_pct || '%)', '')
                 || case when d.matrix then ', a model of the founder''s matrix' else ', more than the 20% line' end
                 || ' - held until it has a reason: select public.fn_model_catalogue_reason(' || c.id || ', ''<why>'', ''<seat>'')',
        'evidence', jsonb_build_object('change_id', c.id, 'model_id', d.model_id, 'field', d.field, 'old', d.old_value,
                                       'new', d.new_value, 'drift_pct', d.drift_pct, 'matrix', d.matrix));
    end if;
  end loop;

  -- An open held row the catalogue no longer disagrees on (moved back, or set by hand) is withdrawn.
  with gone as (
    update public.model_catalogue_change m set outcome = 'withdrawn', closed_at = now()
     where m.closed_at is null and m.decision = 'held'
       and (p_only is null or m.model_id = any (p_only))
       and not exists (select 1 from public.fn_model_catalogue_decide(v_reg, v_matrix, p_catalogue) x
                        where x.model_id = m.model_id and x.field = m.field)
    returning 1)
  select count(*) into n_withdrawn from gone;

  v_res := jsonb_build_object('compared', jsonb_array_length(v_reg), 'auto_applied', n_auto, 'held', n_held,
                              'reasoned_applied', n_applied, 'withdrawn', n_withdrawn, 'absent', n_absent, 'items', v_items);
  if p_only is null then
    v_res := v_res || jsonb_build_object('settle', public.fn_it_duty_settle('model_catalogue', v_items));
    perform public.fn_it_duty_ran('model_catalogue', v_res - 'items');
  end if;
  return v_res;
end $fn$;
revoke execute on function public.fn_model_catalogue_sync(jsonb, text[], text[]) from public, anon, authenticated;
grant execute on function public.fn_model_catalogue_sync(jsonb, text[], text[]) to service_role;

-- ── 5. A REASON RELEASES A HELD CHANGE (applied on the next sync) ───────────────────────────────────
create or replace function public.fn_model_catalogue_reason(p_change_id bigint, p_reason text, p_by text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare c public.model_catalogue_change;
begin
  if coalesce(btrim(p_reason), '') = '' or coalesce(btrim(p_by), '') = '' then
    raise exception 'fn_model_catalogue_reason: a reason and the seat giving it are required';
  end if;
  update public.model_catalogue_change set reason = btrim(p_reason), reasoned_by = btrim(p_by), reasoned_at = now()
   where id = p_change_id and closed_at is null and decision = 'held' returning * into c;
  if not found then
    raise exception 'fn_model_catalogue_reason: change % is not an open held change', p_change_id;
  end if;
  return jsonb_build_object('change_id', c.id, 'model_id', c.model_id, 'field', c.field, 'new_value', c.new_value,
                            'applies', 'on the next model_catalogue sync');
end $fn$;
revoke execute on function public.fn_model_catalogue_reason(bigint, text, text) from public, anon, authenticated;
grant execute on function public.fn_model_catalogue_reason(bigint, text, text) to service_role;

-- ── 6. PROBE: ZZ DEMO models, a synthetic catalogue, every branch; cleaned up; returns a verdict row ──
with demo(id, i, o, c) as (values
    ('zz-demo/small-drift', 1.00, 2.00, 100000),   -- non-matrix, 10% in       -> auto
    ('zz-demo/big-jump',    1.00, 2.00, 100000),   -- non-matrix, 50% out      -> held
    ('zz-demo/matrix',      1.00, 2.00, 100000),   -- matrix, 1% ctx           -> held
    ('zz-demo/gone',        1.00, 2.00, 100000))   -- not in the catalogue     -> absent
insert into public.model_registry (model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd, context_len, approved, active, note)
select id, 'zz-demo', 'small', i, o, c, false, true, 'ZZ DEMO probe row, deleted by the same file' from demo
on conflict (model_id) do nothing;

create temporary table zz_model_catalogue_probe on commit drop as
with cat as (
  select jsonb_agg(x) j from (
    select jsonb_build_object('id', 'zz-demo/small-drift', 'context_length', 100000, 'pricing', jsonb_build_object('prompt', '0.0000011', 'completion', '0.000002')) x
    union all select jsonb_build_object('id', 'zz-demo/big-jump', 'context_length', 100000, 'pricing', jsonb_build_object('prompt', '0.000001', 'completion', '0.000003'))
    union all select jsonb_build_object('id', 'zz-demo/matrix', 'context_length', 101000, 'pricing', jsonb_build_object('prompt', '0.000001', 'completion', '0.000002'))
    union all select jsonb_build_object('id', 'zz-demo/filler-' || g, 'context_length', 1, 'pricing', jsonb_build_object('prompt', '0', 'completion', '0'))
      from generate_series(1, 50) g) s)
select (select j from cat) as cat,
       public.fn_model_catalogue_sync((select j from cat), array['zz-demo/small-drift','zz-demo/big-jump','zz-demo/matrix','zz-demo/gone'],
                                      array['zz-demo/matrix']) as first_run;

-- give the big jump a reason, run again: it must apply
select public.fn_model_catalogue_reason((select id from public.model_catalogue_change where model_id = 'zz-demo/big-jump' and closed_at is null),
                                        'ZZ DEMO probe reason', 'it_engineer');
alter table zz_model_catalogue_probe add column second_run jsonb;
update zz_model_catalogue_probe set second_run = public.fn_model_catalogue_sync(cat,
  array['zz-demo/small-drift','zz-demo/big-jump','zz-demo/matrix','zz-demo/gone'], array['zz-demo/matrix']);
alter table zz_model_catalogue_probe add column seen jsonb;
update zz_model_catalogue_probe set seen = jsonb_build_object(
  'small_in', (select in_per_mtok_usd from public.model_registry where model_id = 'zz-demo/small-drift'),
  'big_out',  (select out_per_mtok_usd from public.model_registry where model_id = 'zz-demo/big-jump'),
  'matrix_ctx', (select context_len from public.model_registry where model_id = 'zz-demo/matrix'),
  'matrix_open', (select count(*) from public.model_catalogue_change where model_id = 'zz-demo/matrix' and closed_at is null),
  'findings', (select count(*) from public.it_engineer_finding where issue_key like 'duty:model_catalogue:%zz-demo%'));

delete from public.model_catalogue_change where model_id like 'zz-demo/%';
delete from public.model_registry where model_id like 'zz-demo/%' and provider = 'zz-demo';

select case
  when (first_run->>'auto_applied')::int = 1 and (first_run->>'held')::int = 2 and (first_run->>'absent')::int = 1
   and (second_run->>'reasoned_applied')::int = 1 and (second_run->>'held')::int = 1 and (second_run->>'auto_applied')::int = 0
   and (seen->>'small_in')::numeric = 1.1 and (seen->>'big_out')::numeric = 3 and (seen->>'matrix_ctx')::int = 100000
   and (seen->>'matrix_open')::int = 1 and (seen->>'findings')::int = 0
   and not exists (select 1 from public.model_registry where model_id like 'zz-demo/%')
   and not exists (select 1 from public.model_catalogue_change where model_id like 'zz-demo/%')
  then 'PROBE OK :: small non-matrix drift applied, >20% jump held then applied with a reason, matrix change held, absent model flagged, demo rows gone'
  else 'PROBE FAILED :: ' || jsonb_build_object('first', first_run - 'items', 'second', second_run - 'items', 'seen', seen)::text
end as verdict
from zz_model_catalogue_probe;
