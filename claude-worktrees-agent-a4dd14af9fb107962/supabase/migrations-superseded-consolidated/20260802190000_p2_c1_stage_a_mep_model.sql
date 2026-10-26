-- P2-C1 STAGE A - THE MEP DATA MODEL. SHARED ANSWERS ARE REFERENCED, NEVER COPIED.
--
-- Implements docs/phases/P2-C1_STAGE_A_DESIGN.md as amended on 2 August 2026. Additive only:
-- no existing table changes shape, no production router is touched, nothing customer-visible moves.
--
-- The one decision everything follows from: an answer is stored ONCE per (group, field identity)
-- and referenced by every workstream that needs it. There is no per-workstream copy, so there is
-- nothing to fall out of step. Completeness is therefore DERIVED - there is no percentage column
-- anywhere in this file, and that is deliberate.
--
-- Two amendments are implemented rather than the original text:
--   1. Field identity is explicit and stable (field_definition.field_id). A shared display label is
--      not evidence of a shared field. The imported corpus proves the point: MEP spells the same
--      concept `required_completion_date` while routes 12/13/14 spell it `required_date`, and
--      `finish_colour` is mandatory in some subcategories and optional in others. A raw field_key
--      is a spelling, not an identity.
--   2. The setter distinguishes corroboration from conflict. A drawing that AGREES with the
--      customer is evidence, not a dispute. Treating it as a conflict would fill the queue with
--      noise, and a queue full of noise is a queue nobody reads.

-- ---------------------------------------------------------------------------------------------
-- 1. Trades, and the routes they come from.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.mep_trade (
  trade_key    text primary key,
  label_en     text not null,
  label_ar     text,
  sort_order   integer not null default 0
);

create table if not exists public.mep_trade_route (
  trade_key    text not null references public.mep_trade(trade_key) on delete cascade,
  catalog_num  integer not null,
  is_primary   boolean not null default false,
  primary key (trade_key, catalog_num)
);

comment on table public.mep_trade is
  'The five MEP trades. hvac/electrical/plumbing are the three that route 8 actually maps; fire and elv have no route-8 subcategory and join a group only when detected (drawings) or asked for.';

-- ---------------------------------------------------------------------------------------------
-- 2. Precedence. An ordered enum plus an explicit rank, because comparing enum labels by their
--    declaration order is a correctness property that should not be implicit.
-- ---------------------------------------------------------------------------------------------

do $mig$ begin
  create type public.answer_precedence as enum (
    'customer_confirmed', 'approved_document', 'document_extracted',
    'deterministic_inference', 'model_inference', 'unknown');
exception when duplicate_object then null; end $mig$;

create or replace function public.fn_answer_precedence_rank(p public.answer_precedence)
returns integer language sql immutable as $fn$
  select case p
    when 'customer_confirmed'      then 1
    when 'approved_document'       then 2
    when 'document_extracted'      then 3
    when 'deterministic_inference' then 4
    when 'model_inference'         then 5
    else 6 end;
$fn$;

-- ---------------------------------------------------------------------------------------------
-- 3. Field identity. Amendment 1.
--    A field may be `shared` only when meaning, unit, validation, evidence rule, regulatory
--    interpretation and applicability are ALL identical. Six conditions; any one failing makes it
--    trade-specific. Deliberately hard to qualify for: wrongly sharing costs a wrong dispatch,
--    wrongly splitting costs one extra question.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.field_definition (
  field_id                  text primary key,
  scope                     text not null check (scope in ('shared','trade_specific','trade_subset')),
  trade_key                 text references public.mep_trade(trade_key),
  label_en                  text not null,
  label_ar                  text,
  unit                      text,
  answer_type               text,
  numeric_tolerance         integer,
  validation_ref            text,
  evidence_rule             text,
  regulatory_interpretation text,
  applies_when              jsonb,
  review_status             text not null default 'approved'
                              check (review_status in ('approved','question_for_founder')),
  review_note               text,
  created_at                timestamptz not null default now(),
  constraint fd_shared_carries_no_trade   check (scope <> 'shared'         or trade_key is null),
  constraint fd_trade_specific_has_trade  check (scope <> 'trade_specific' or trade_key is not null),
  constraint fd_subset_carries_no_trade   check (scope <> 'trade_subset'   or trade_key is null)
);

-- UNIQUE (scope, trade_key, label_en) as designed. Expressed as an index with coalesce because a
-- NULL trade_key would otherwise defeat the constraint for exactly the rows it matters most for -
-- the shared ones, where an accidental second identity is the expensive mistake.
create unique index if not exists field_definition_identity_uidx
  on public.field_definition (scope, coalesce(trade_key,''), label_en);

create table if not exists public.field_definition_trade (
  field_id   text not null references public.field_definition(field_id) on delete cascade,
  trade_key  text not null references public.mep_trade(trade_key) on delete cascade,
  primary key (field_id, trade_key)
);

-- The bridge from the imported corpus to stable identity. The primary key is the guarantee:
-- one raw field_key in one subcategory resolves to exactly one field identity, so the same
-- spelling in plumbing and in fire CANNOT collapse into a single field by accident.
create table if not exists public.field_definition_source (
  subcategory_slug  text not null,
  source_field_key  text not null,
  field_id          text not null references public.field_definition(field_id) on delete cascade,
  primary key (subcategory_slug, source_field_key)
);

comment on table public.field_definition_source is
  'Maps imported kb_stage.questions.field_key (a spelling, per subcategory) to a stable field identity. Route 8 says required_completion_date where routes 12/13/14 say required_date; both resolve here to shared.required_completion_date.';

-- ---------------------------------------------------------------------------------------------
-- 4. The group and its workstreams.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.inquiry_workstream_group (
  id          bigserial primary key,
  inquiry_id  uuid not null unique,
  rfq_mode    text not null default 'coordinated' check (rfq_mode in ('coordinated','linked')),
  created_at  timestamptz not null default now()
);

create table if not exists public.inquiry_workstream (
  id                bigserial primary key,
  group_id          bigint not null references public.inquiry_workstream_group(id) on delete cascade,
  trade_key         text not null references public.mep_trade(trade_key),
  route_catalog_num integer,
  active            boolean not null default true,
  activated_at      timestamptz not null default now(),
  deactivated_at    timestamptz,
  unique (group_id, trade_key)
);

comment on column public.inquiry_workstream.active is
  'Reactivation flips this flag; it never re-inserts. Inactive means excluded from the roll-up, never deleted - answers and audit rows survive untouched.';

-- ---------------------------------------------------------------------------------------------
-- 5. THE canonical answer store. One live row per (group, field identity). Append-only:
--    a new value supersedes, it never overwrites.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.inquiry_answer (
  id            bigserial primary key,
  group_id      bigint not null references public.inquiry_workstream_group(id) on delete cascade,
  field_id      text not null references public.field_definition(field_id),
  value         text,
  unit          text,
  scope         text not null check (scope in ('inquiry_shared','trade_specific','trade_subset')),
  precedence    public.answer_precedence not null,
  source_kind   text not null check (source_kind in ('customer','document','deterministic','model')),
  confirmed_at  timestamptz,
  confirmed_by  text,
  superseded_by bigint references public.inquiry_answer(id),
  created_at    timestamptz not null default now()
);

create unique index if not exists inquiry_answer_live_uidx
  on public.inquiry_answer (group_id, field_id) where superseded_by is null;
create index if not exists inquiry_answer_group_idx on public.inquiry_answer (group_id, field_id);

comment on table public.inquiry_answer is
  'The single canonical store. A shared answer is stored once here and referenced by every workstream; it is never copied into one. That is why no completeness percentage is stored anywhere - there is one value, so completeness can always be derived and can never be stale.';

-- Which workstreams a trade_specific / trade_subset answer applies to.
-- Absent for inquiry_shared: a shared answer applies to every workstream in the group, by
-- derivation rather than by row, so adding a sixth trade cannot leave a shared answer behind.
create table if not exists public.inquiry_answer_scope (
  answer_id     bigint not null references public.inquiry_answer(id) on delete cascade,
  workstream_id bigint not null references public.inquiry_workstream(id) on delete cascade,
  primary key (answer_id, workstream_id)
);

-- ---------------------------------------------------------------------------------------------
-- 6. Evidence. Three tables, and none of them ever loses a row.
--    - document  : provenance for a document-derived value
--    - corroboration : a lower-precedence source that AGREES (amendment 2)
--    - conflict / conflict_value : sources that DISAGREE, every competing value preserved
-- ---------------------------------------------------------------------------------------------

create table if not exists public.inquiry_answer_document (
  id                    bigserial primary key,
  answer_id             bigint not null references public.inquiry_answer(id) on delete cascade,
  document_id           text not null,
  page_or_sheet         text,
  extraction_confidence numeric,
  original_text         text,
  assigned_scope        text,
  extracted_at          timestamptz not null default now()
);

create table if not exists public.inquiry_answer_corroboration (
  id               bigserial primary key,
  answer_id        bigint not null references public.inquiry_answer(id) on delete cascade,
  value            text,
  normalised_value text,
  precedence       public.answer_precedence not null,
  source_kind      text not null,
  document_id      text,
  recorded_at      timestamptz not null default now()
);

comment on table public.inquiry_answer_corroboration is
  'A lower-precedence source that agrees with the live value on normalised comparison. The answer is now better attested, not disputed. Without this table every agreeing drawing would raise a conflict, and a conflict queue that is mostly agreement is a queue people learn to dismiss.';

create table if not exists public.inquiry_answer_conflict (
  id                bigserial primary key,
  group_id          bigint not null references public.inquiry_workstream_group(id) on delete cascade,
  field_id          text not null references public.field_definition(field_id),
  blocking_scope    text not null check (blocking_scope in ('shared','trade')),
  opened_at         timestamptz not null default now(),
  resolved_at       timestamptz,
  resolved_by       text,
  resolution_reason text,
  constraint iac_resolution_is_explained check (
    resolved_at is null or (coalesce(btrim(resolved_by),'') <> ''
                        and coalesce(btrim(resolution_reason),'') <> ''))
);

create unique index if not exists inquiry_answer_conflict_open_uidx
  on public.inquiry_answer_conflict (group_id, field_id) where resolved_at is null;

create table if not exists public.inquiry_answer_conflict_value (
  id          bigserial primary key,
  conflict_id bigint not null references public.inquiry_answer_conflict(id) on delete cascade,
  value       text,
  precedence  public.answer_precedence not null,
  source_kind text not null,
  document_id text,
  recorded_at timestamptz not null default now()
);

comment on table public.inquiry_answer_conflict_value is
  'Every competing value, kept forever. This is what makes "the drawing said 12 units, the customer said 8" answerable three months later. DELETE is refused by trigger.';

-- ---------------------------------------------------------------------------------------------
-- 7. Requirements, gates and audit.
-- ---------------------------------------------------------------------------------------------

-- The questions a trade actually owns, materialised on activation.
-- UNIQUE (workstream_id, field_id) is the cross-workstream duplicate prevention, made structural:
-- route 8's eleven subcategories each carry `project_emirate`, and they collapse to one row here.
create table if not exists public.inquiry_workstream_requirement (
  id            bigserial primary key,
  workstream_id bigint not null references public.inquiry_workstream(id) on delete cascade,
  question_id   text,
  field_id      text not null references public.field_definition(field_id),
  mandatory     boolean not null default false,
  applies_when  jsonb,
  unique (workstream_id, field_id)
);

-- Gates that are NOT answers: privacy/redaction and escalations at group level, validations and
-- regulatory triggers at workstream level. They default to absent, and absent reads as failed.
-- Fail-closed is the point: "zero incorrect dispatch_eligible = true" is only achievable if an
-- unasserted gate blocks. Stage A wires no validation or regulatory engine, so at Stage A every
-- one of these must be asserted by hand - which is the honest state of the system today.
create table if not exists public.inquiry_gate_required (
  gate_key text primary key,
  level    text not null check (level in ('group','workstream')),
  note     text
);

insert into public.inquiry_gate_required (gate_key, level, note) values
  ('privacy_redaction','group','Privacy and redaction gates passed for the whole inquiry.'),
  ('escalations','group','Every required escalation is complete.'),
  ('validations','workstream','Field validations pass for this trade.'),
  ('regulatory','workstream','Regulatory triggers for this trade are satisfied.')
on conflict (gate_key) do nothing;

create table if not exists public.inquiry_gate (
  id            bigserial primary key,
  group_id      bigint not null references public.inquiry_workstream_group(id) on delete cascade,
  workstream_id bigint references public.inquiry_workstream(id) on delete cascade,
  gate_key      text not null references public.inquiry_gate_required(gate_key),
  passed        boolean not null default false,
  asserted_by   text,
  asserted_at   timestamptz not null default now()
);
create unique index if not exists inquiry_gate_group_uidx
  on public.inquiry_gate (group_id, gate_key) where workstream_id is null;
create unique index if not exists inquiry_gate_ws_uidx
  on public.inquiry_gate (workstream_id, gate_key) where workstream_id is not null;

create table if not exists public.inquiry_state_audit (
  id            bigserial primary key,
  group_id      bigint,
  workstream_id bigint,
  event         text not null,
  detail        jsonb,
  actor         text,
  at            timestamptz not null default now()
);
create index if not exists inquiry_state_audit_group_idx on public.inquiry_state_audit (group_id, at desc);

-- ---------------------------------------------------------------------------------------------
-- 8. Evidence is not editable. Same trigger pattern as the P2-C5 expectation ledger.
-- ---------------------------------------------------------------------------------------------

create or replace function public.trg_p2c1_append_only()
returns trigger language plpgsql as $fn$
begin
  raise exception '% is append-only: % is not permitted.', tg_table_name, tg_op
    using hint = 'Evidence that can be deleted is evidence nobody can rely on. Record a new row instead.';
end $fn$;

drop trigger if exists inquiry_state_audit_append_only on public.inquiry_state_audit;
create trigger inquiry_state_audit_append_only before update or delete on public.inquiry_state_audit
  for each row execute function public.trg_p2c1_append_only();

drop trigger if exists conflict_value_append_only on public.inquiry_answer_conflict_value;
create trigger conflict_value_append_only before update or delete on public.inquiry_answer_conflict_value
  for each row execute function public.trg_p2c1_append_only();

drop trigger if exists corroboration_append_only on public.inquiry_answer_corroboration;
create trigger corroboration_append_only before update or delete on public.inquiry_answer_corroboration
  for each row execute function public.trg_p2c1_append_only();

drop trigger if exists answer_document_append_only on public.inquiry_answer_document;
create trigger answer_document_append_only before update or delete on public.inquiry_answer_document
  for each row execute function public.trg_p2c1_append_only();

-- inquiry_answer is append-only in the sense that matters: the VALUE of a recorded answer can
-- never change. Only superseded_by may be written, and only once, to point at its replacement.
create or replace function public.trg_inquiry_answer_value_immutable()
returns trigger language plpgsql as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'inquiry_answer rows are never deleted (id %)', old.id
      using hint = 'Supersede the answer instead. The chain is the history.';
  end if;
  if new.value      is distinct from old.value
     or new.field_id   is distinct from old.field_id
     or new.group_id   is distinct from old.group_id
     or new.precedence is distinct from old.precedence
     or new.source_kind is distinct from old.source_kind then
    raise exception 'inquiry_answer % is immutable; supersede it instead of editing it', old.id;
  end if;
  if old.superseded_by is not null and new.superseded_by is distinct from old.superseded_by then
    raise exception 'inquiry_answer % is already superseded by %', old.id, old.superseded_by;
  end if;
  return new;
end $fn$;

drop trigger if exists inquiry_answer_value_immutable on public.inquiry_answer;
create trigger inquiry_answer_value_immutable before update or delete on public.inquiry_answer
  for each row execute function public.trg_inquiry_answer_value_immutable();

-- RLS on every new table. Deny-by-default, service-role only, consistent with the other 294.
do $mig$
declare t text;
begin
  foreach t in array array['mep_trade','mep_trade_route','field_definition','field_definition_trade',
    'field_definition_source','inquiry_workstream_group','inquiry_workstream','inquiry_answer',
    'inquiry_answer_scope','inquiry_answer_document','inquiry_answer_corroboration',
    'inquiry_answer_conflict','inquiry_answer_conflict_value','inquiry_workstream_requirement',
    'inquiry_gate_required','inquiry_gate','inquiry_state_audit']
  loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $mig$;

-- ---------------------------------------------------------------------------------------------
-- 9. Normalisation. Per field_definition: unit, case, numeric tolerance.
--    Comparing "8 bar" against "8.0 BAR" as different values would manufacture conflicts out of
--    formatting, which is the fastest way to train people to ignore the conflict queue.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_field_normalise(p_field_id text, p_value text)
returns text language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_type text; v_tol integer; v_norm text; v_num numeric; v_match text[];
begin
  if p_value is null then return null; end if;
  select answer_type, numeric_tolerance into v_type, v_tol
    from public.field_definition where field_id = p_field_id;

  v_norm := lower(btrim(regexp_replace(p_value, '\s+', ' ', 'g')));

  if coalesce(v_type,'') in ('number','numeric','integer','decimal','quantity') then
    v_match := regexp_match(replace(v_norm, ',', ''), '(-?[0-9]+(?:\.[0-9]+)?)');
    if v_match is not null then
      v_num := v_match[1]::numeric;
      return trim(to_char(round(v_num, coalesce(v_tol, 2)), 'FM99999999999990.99999999'));
    end if;
  end if;

  return v_norm;
end $fn$;

-- ---------------------------------------------------------------------------------------------
-- 10. Activating a trade. Materialises the requirements that trade owns, deduplicated by field
--     identity. Reactivation flips the flag and re-materialises; it never inserts a second row.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_inquiry_workstream_activate(
  p_group_id bigint, p_trade_key text, p_actor text default 'system')
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_ws_id bigint; v_route integer; v_reactivated boolean := false; v_reqs integer;
begin
  if not exists (select 1 from public.mep_trade where trade_key = p_trade_key) then
    return jsonb_build_object('ok', false, 'error', 'unknown_trade', 'trade_key', p_trade_key);
  end if;
  if not exists (select 1 from public.inquiry_workstream_group where id = p_group_id) then
    return jsonb_build_object('ok', false, 'error', 'unknown_group');
  end if;

  select catalog_num into v_route from public.mep_trade_route
   where trade_key = p_trade_key and is_primary order by catalog_num limit 1;

  select id into v_ws_id from public.inquiry_workstream
   where group_id = p_group_id and trade_key = p_trade_key;

  if v_ws_id is null then
    insert into public.inquiry_workstream (group_id, trade_key, route_catalog_num)
    values (p_group_id, p_trade_key, v_route) returning id into v_ws_id;
  else
    update public.inquiry_workstream
       set active = true, activated_at = now(), deactivated_at = null
     where id = v_ws_id and active = false;
    v_reactivated := found;
    update public.inquiry_workstream set active = true where id = v_ws_id;
  end if;

  -- The requirements this trade owns. Shared fields resolve to ONE row even though eleven
  -- subcategories each ask for them; that is the duplicate prevention, enforced by the
  -- unique key rather than by a de-duplication pass that someone can forget to run.
  insert into public.inquiry_workstream_requirement (workstream_id, question_id, field_id, mandatory)
  select v_ws_id, min(q.question_id), s.field_id, bool_or(q.mandatory)
    from public.mep_trade_route tr
    join public.kb_operational_route_map m on m.catalog_num = tr.catalog_num
    join kb_stage.questions q on q.subcategory_slug = m.subcategory_slug
    join public.field_definition_source s
      on s.subcategory_slug = q.subcategory_slug and s.source_field_key = q.field_key
   where tr.trade_key = p_trade_key and q.field_key is not null
   group by s.field_id
  on conflict (workstream_id, field_id) do update
     set mandatory = public.inquiry_workstream_requirement.mandatory or excluded.mandatory;

  get diagnostics v_reqs = row_count;

  insert into public.inquiry_state_audit (group_id, workstream_id, event, detail, actor)
  values (p_group_id, v_ws_id,
          case when v_reactivated then 'workstream_reactivated' else 'workstream_activated' end,
          jsonb_build_object('trade_key', p_trade_key, 'route_catalog_num', v_route,
                             'requirements', v_reqs), p_actor);

  return jsonb_build_object('ok', true, 'workstream_id', v_ws_id, 'trade_key', p_trade_key,
                            'reactivated', v_reactivated, 'requirements', v_reqs);
end $fn$;

create or replace function public.fn_inquiry_workstream_deactivate(
  p_group_id bigint, p_trade_key text, p_actor text default 'system')
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_ws_id bigint;
begin
  update public.inquiry_workstream
     set active = false, deactivated_at = now()
   where group_id = p_group_id and trade_key = p_trade_key and active
   returning id into v_ws_id;
  if v_ws_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_active');
  end if;
  insert into public.inquiry_state_audit (group_id, workstream_id, event, detail, actor)
  values (p_group_id, v_ws_id, 'workstream_deactivated',
          jsonb_build_object('trade_key', p_trade_key), p_actor);
  return jsonb_build_object('ok', true, 'workstream_id', v_ws_id);
end $fn$;

-- ---------------------------------------------------------------------------------------------
-- 11. THE SETTER. Four paths, enforced here rather than by convention.
--
--   higher precedence                      -> supersedes; the previous row and its provenance stay
--   lower precedence, same normalised value -> corroboration. NO conflict. Better attested.
--   lower precedence, different value       -> conflict. Canonical value unchanged. Both preserved.
--   model_inference on a mandatory field    -> may never satisfy it alone; it proposes only.
--
-- The word doing the work in "a lower-precedence value may not SILENTLY overwrite a higher-
-- precedence value" is `silently`, and a conflict row is the opposite of silent.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_inquiry_answer_set(
  p_group_id       bigint,
  p_field_id       text,
  p_value          text,
  p_precedence     public.answer_precedence,
  p_source_kind    text,
  p_actor          text default 'system',
  p_unit           text default null,
  p_workstream_ids bigint[] default null,
  p_document       jsonb default null
) returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_fd            public.field_definition%rowtype;
  v_answer_scope  text;
  v_live          public.inquiry_answer%rowtype;
  v_new_id        bigint;
  v_conflict_id   bigint;
  v_norm_new      text;
  v_norm_live     text;
  v_rank_new      integer;
  v_rank_live     integer;
  v_ws            bigint;
  v_bad_ws        bigint[];
  v_action        text;
begin
  select * into v_fd from public.field_definition where field_id = p_field_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unknown_field', 'field_id', p_field_id);
  end if;
  if not exists (select 1 from public.inquiry_workstream_group where id = p_group_id) then
    return jsonb_build_object('ok', false, 'error', 'unknown_group');
  end if;

  v_answer_scope := case v_fd.scope when 'shared' then 'inquiry_shared' else v_fd.scope end;

  -- A trade-specific answer must name its workstreams, and every named workstream must belong to
  -- the trade that owns the field. This is the structural half of "a trade-specific answer cannot
  -- satisfy another trade"; the derivation half is in the completeness views.
  if v_fd.scope <> 'shared' then
    if p_workstream_ids is null or array_length(p_workstream_ids, 1) is null then
      return jsonb_build_object('ok', false, 'error', 'workstream_required',
        'message', 'A trade-specific answer must say which workstream it belongs to.');
    end if;
    select array_agg(w.id) into v_bad_ws
      from public.inquiry_workstream w
     where w.id = any(p_workstream_ids)
       and (w.group_id <> p_group_id
            or (v_fd.scope = 'trade_specific' and w.trade_key <> v_fd.trade_key)
            or (v_fd.scope = 'trade_subset' and not exists (
                  select 1 from public.field_definition_trade t
                   where t.field_id = v_fd.field_id and t.trade_key = w.trade_key)));
    if v_bad_ws is not null then
      return jsonb_build_object('ok', false, 'error', 'trade_mismatch',
        'field_id', p_field_id, 'field_trade', v_fd.trade_key, 'rejected_workstreams', v_bad_ws,
        'message', 'This field belongs to another trade. A trade-specific answer cannot satisfy a workstream that does not own the field.');
    end if;
    if (select count(*) from public.inquiry_workstream
         where id = any(p_workstream_ids)) <> array_length(p_workstream_ids, 1) then
      return jsonb_build_object('ok', false, 'error', 'unknown_workstream');
    end if;
  end if;

  select * into v_live from public.inquiry_answer
   where group_id = p_group_id and field_id = p_field_id and superseded_by is null;

  -- Path 0: nothing live yet. Record it.
  if not found then
    insert into public.inquiry_answer (group_id, field_id, value, unit, scope, precedence,
                                       source_kind, confirmed_at, confirmed_by)
    values (p_group_id, p_field_id, p_value, coalesce(p_unit, v_fd.unit), v_answer_scope,
            p_precedence, p_source_kind,
            case when p_precedence = 'customer_confirmed' then now() end,
            case when p_precedence = 'customer_confirmed' then p_actor end)
    returning id into v_new_id;
    v_action := 'inserted';
  else
    v_rank_new  := public.fn_answer_precedence_rank(p_precedence);
    v_rank_live := public.fn_answer_precedence_rank(v_live.precedence);
    v_norm_new  := public.fn_field_normalise(p_field_id, p_value);
    v_norm_live := public.fn_field_normalise(p_field_id, v_live.value);

    -- Equal precedence normally cannot supersede. The one exception is the customer restating
    -- their own answer: `customer_confirmed` over `customer_confirmed` is the customer's latest
    -- word, not a dispute with themselves. Without this, a customer resolving a conflict by
    -- confirming the drawing's value would open a second conflict against their own first answer.
    if v_rank_new < v_rank_live
       or (v_rank_new = v_rank_live and p_precedence = 'customer_confirmed'
           and v_norm_new is distinct from v_norm_live) then
      -- Path 1: higher precedence supersedes. The old row is kept and pointed at the new one.
      insert into public.inquiry_answer (group_id, field_id, value, unit, scope, precedence,
                                         source_kind, confirmed_at, confirmed_by)
      values (p_group_id, p_field_id, p_value, coalesce(p_unit, v_fd.unit), v_answer_scope,
              p_precedence, p_source_kind,
              case when p_precedence = 'customer_confirmed' then now() end,
              case when p_precedence = 'customer_confirmed' then p_actor end)
      returning id into v_new_id;
      update public.inquiry_answer set superseded_by = v_new_id where id = v_live.id;
      insert into public.inquiry_answer_scope (answer_id, workstream_id)
        select v_new_id, workstream_id from public.inquiry_answer_scope where answer_id = v_live.id
        on conflict do nothing;
      v_action := 'superseded';

    elsif v_norm_new is not distinct from v_norm_live then
      -- Path 2: it AGREES. Evidence, not a dispute.
      v_new_id := v_live.id;
      insert into public.inquiry_answer_corroboration
        (answer_id, value, normalised_value, precedence, source_kind, document_id)
      values (v_live.id, p_value, v_norm_new, p_precedence, p_source_kind, p_document->>'document_id');
      v_action := 'corroborated';

    else
      -- Path 3: it DISAGREES at equal or lower precedence. Canonical value unchanged.
      v_new_id := v_live.id;
      select id into v_conflict_id from public.inquiry_answer_conflict
       where group_id = p_group_id and field_id = p_field_id and resolved_at is null;
      if v_conflict_id is null then
        insert into public.inquiry_answer_conflict (group_id, field_id, blocking_scope)
        values (p_group_id, p_field_id,
                case when v_fd.scope = 'shared' then 'shared' else 'trade' end)
        returning id into v_conflict_id;
        insert into public.inquiry_answer_conflict_value
          (conflict_id, value, precedence, source_kind)
        values (v_conflict_id, v_live.value, v_live.precedence, v_live.source_kind);
      end if;
      insert into public.inquiry_answer_conflict_value
        (conflict_id, value, precedence, source_kind, document_id)
      values (v_conflict_id, p_value, p_precedence, p_source_kind, p_document->>'document_id');
      v_action := 'conflict_opened';
    end if;
  end if;

  -- Scope links, only for answers that actually landed as canonical.
  if v_fd.scope <> 'shared' and v_action in ('inserted','superseded') then
    foreach v_ws in array p_workstream_ids loop
      insert into public.inquiry_answer_scope (answer_id, workstream_id)
      values (v_new_id, v_ws) on conflict do nothing;
    end loop;
  end if;

  -- Document provenance, on every path - including the conflicting one, because the drawing that
  -- disagreed is exactly the drawing someone will want to look at.
  if p_document is not null and v_action in ('inserted','superseded') then
    insert into public.inquiry_answer_document
      (answer_id, document_id, page_or_sheet, extraction_confidence, original_text, assigned_scope)
    values (v_new_id, p_document->>'document_id', p_document->>'page_or_sheet',
            (p_document->>'extraction_confidence')::numeric, p_document->>'original_text',
            v_answer_scope);
  end if;

  insert into public.inquiry_state_audit (group_id, event, detail, actor)
  values (p_group_id, 'answer_' || v_action,
          jsonb_build_object('field_id', p_field_id, 'precedence', p_precedence,
                             'source_kind', p_source_kind, 'answer_id', v_new_id,
                             'conflict_id', v_conflict_id), p_actor);

  return jsonb_build_object('ok', true, 'action', v_action, 'answer_id', v_new_id,
                            'field_id', p_field_id, 'conflict_id', v_conflict_id,
                            'scope', v_answer_scope);
end $fn$;

-- ---------------------------------------------------------------------------------------------
-- 12. Confirmation. The customer settles a conflict. Nothing is deleted: the competing values
--     stay in inquiry_answer_conflict_value, the superseded answers stay in the chain, and the
--     resolution carries a person and a reason or the check constraint refuses it.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_inquiry_answer_confirm(
  p_group_id bigint, p_field_id text, p_value text,
  p_confirmed_by text, p_reason text, p_workstream_ids bigint[] default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_res jsonb; v_conflict_id bigint; v_kept integer;
begin
  if coalesce(btrim(p_confirmed_by),'') = '' or coalesce(btrim(p_reason),'') = '' then
    return jsonb_build_object('ok', false, 'error', 'who_and_why_required');
  end if;

  select id into v_conflict_id from public.inquiry_answer_conflict
   where group_id = p_group_id and field_id = p_field_id and resolved_at is null;

  v_res := public.fn_inquiry_answer_set(p_group_id, p_field_id, p_value, 'customer_confirmed',
             'customer', p_confirmed_by, null, p_workstream_ids, null);
  if not (v_res->>'ok')::boolean then return v_res; end if;

  if v_conflict_id is not null then
    -- The confirmed value joins the evidence too, so the record shows what was chosen and
    -- against what. Then the conflict is resolved - never deleted.
    insert into public.inquiry_answer_conflict_value (conflict_id, value, precedence, source_kind)
    values (v_conflict_id, p_value, 'customer_confirmed', 'customer');
    update public.inquiry_answer_conflict
       set resolved_at = now(), resolved_by = p_confirmed_by, resolution_reason = p_reason
     where id = v_conflict_id;
    select count(*) into v_kept from public.inquiry_answer_conflict_value where conflict_id = v_conflict_id;
  end if;

  insert into public.inquiry_state_audit (group_id, event, detail, actor)
  values (p_group_id, 'conflict_resolved_by_confirmation',
          jsonb_build_object('field_id', p_field_id, 'conflict_id', v_conflict_id,
                             'reason', p_reason, 'evidence_values_kept', v_kept), p_confirmed_by);

  return jsonb_build_object('ok', true, 'action', v_res->>'action', 'conflict_id', v_conflict_id,
                            'evidence_values_kept', v_kept);
end $fn$;

-- ---------------------------------------------------------------------------------------------
-- 13. Derived views. Nothing below is stored. This is the whole argument of the design: because
--     a shared answer is one row joined by group_id, updating it changes every workstream's view
--     in the same statement. There is no propagation step, so there is no propagation bug.
-- ---------------------------------------------------------------------------------------------

create or replace view public.v_workstream_answer as
select w.id as workstream_id, w.group_id, w.trade_key, w.active,
       a.id as answer_id, a.field_id, a.value, a.unit, a.scope, a.precedence, a.source_kind,
       a.confirmed_at,
       (a.value is not null and btrim(a.value) <> ''
        and a.precedence not in ('model_inference','unknown')) as satisfies_mandatory
  from public.inquiry_workstream w
  join public.inquiry_answer a
    on a.group_id = w.group_id and a.superseded_by is null
 where a.scope = 'inquiry_shared'
    or exists (select 1 from public.inquiry_answer_scope s
                where s.answer_id = a.id and s.workstream_id = w.id);

comment on view public.v_workstream_answer is
  'Every live answer visible to every workstream. A shared answer is joined by group_id and appears for all of them from a single row - which is why one UPDATE changes five workstream views at once, and why no workstream copy can go stale.';

-- Which unresolved conflicts block which workstream. A shared-field conflict blocks all of them;
-- a trade field blocks only the trade that owns it.
create or replace view public.v_workstream_conflict as
select w.id as workstream_id, w.group_id, w.trade_key, c.id as conflict_id, c.field_id,
       c.blocking_scope, c.opened_at
  from public.inquiry_workstream w
  join public.inquiry_answer_conflict c on c.group_id = w.group_id and c.resolved_at is null
  join public.field_definition fd on fd.field_id = c.field_id
 where fd.scope = 'shared'
    or (fd.scope = 'trade_specific' and fd.trade_key = w.trade_key)
    or (fd.scope = 'trade_subset' and exists (
          select 1 from public.field_definition_trade t
           where t.field_id = fd.field_id and t.trade_key = w.trade_key));

create or replace view public.v_workstream_completeness as
select w.id as workstream_id, w.group_id, w.trade_key, w.active,
       count(*) filter (where r.mandatory) as required_mandatory,
       count(*) filter (where r.mandatory and va.satisfies_mandatory) as answered_mandatory,
       count(*) filter (where not r.mandatory) as required_optional,
       count(*) filter (where not r.mandatory and va.satisfies_mandatory) as answered_optional,
       coalesce(array_agg(r.field_id order by r.field_id)
                filter (where r.mandatory and not coalesce(va.satisfies_mandatory,false)),
                '{}'::text[]) as missing_mandatory,
       coalesce((select array_agg(distinct vc.field_id order by vc.field_id)
                   from public.v_workstream_conflict vc where vc.workstream_id = w.id),
                '{}'::text[]) as blocked_by
  from public.inquiry_workstream w
  left join public.inquiry_workstream_requirement r on r.workstream_id = w.id
  left join public.v_workstream_answer va on va.workstream_id = w.id and va.field_id = r.field_id
 group by w.id, w.group_id, w.trade_key, w.active;

create or replace view public.v_workstream_dispatch as
select c.workstream_id, c.group_id, c.trade_key, c.active,
       c.required_mandatory, c.answered_mandatory, c.missing_mandatory, c.blocked_by,
       (cardinality(c.missing_mandatory) = 0) as mandatory_complete,
       (cardinality(c.blocked_by) = 0)        as no_unresolved_conflict,
       not exists (
         select 1 from public.inquiry_gate_required gr
          where gr.level = 'workstream'
            and not exists (select 1 from public.inquiry_gate g
                             where g.workstream_id = c.workstream_id
                               and g.gate_key = gr.gate_key and g.passed)) as gates_passed,
       (c.active
        and cardinality(c.missing_mandatory) = 0
        and cardinality(c.blocked_by) = 0
        and not exists (
          select 1 from public.inquiry_gate_required gr
           where gr.level = 'workstream'
             and not exists (select 1 from public.inquiry_gate g
                              where g.workstream_id = c.workstream_id
                                and g.gate_key = gr.gate_key and g.passed))) as dispatch_eligible
  from public.v_workstream_completeness c;

comment on view public.v_workstream_dispatch is
  'A missing required gate row reads as failed, not as absent. Fail-closed: "zero incorrect dispatch_eligible = true" is only reachable if an unasserted gate blocks.';

-- Shared fields at group level: those required by at least one ACTIVE workstream.
create or replace view public.v_group_completeness as
select g.id as group_id, g.inquiry_id, g.rfq_mode,
       count(*) filter (where sr.mandatory) as shared_required_mandatory,
       count(*) filter (where sr.mandatory and a.id is not null) as shared_answered_mandatory,
       coalesce(array_agg(sr.field_id order by sr.field_id)
                filter (where sr.mandatory and a.id is null), '{}'::text[]) as shared_missing_mandatory,
       (select count(*) from public.inquiry_workstream w where w.group_id = g.id and w.active) as active_workstreams,
       (select count(*) from public.inquiry_answer_conflict c
         join public.field_definition fd on fd.field_id = c.field_id
        where c.group_id = g.id and c.resolved_at is null and fd.scope = 'shared') as open_shared_conflicts
  from public.inquiry_workstream_group g
  left join lateral (
    select r.field_id, bool_or(r.mandatory) as mandatory
      from public.inquiry_workstream_requirement r
      join public.inquiry_workstream w on w.id = r.workstream_id
      join public.field_definition fd on fd.field_id = r.field_id
     where w.group_id = g.id and w.active and fd.scope = 'shared'
     group by r.field_id
  ) sr on true
  left join public.inquiry_answer a
    on a.group_id = g.id and a.field_id = sr.field_id and a.superseded_by is null
   and a.value is not null and btrim(a.value) <> ''
   and a.precedence not in ('model_inference','unknown')
 group by g.id, g.inquiry_id, g.rfq_mode;

-- v_group_dispatch is an AND over ACTIVE workstreams. One complete trade can never carry an
-- incomplete one, and a group with no active workstream is not "vacuously ready" - it is not ready.
create or replace view public.v_group_dispatch as
select gc.group_id, gc.inquiry_id, gc.rfq_mode, gc.active_workstreams,
       gc.shared_missing_mandatory,
       (cardinality(gc.shared_missing_mandatory) = 0) as shared_complete,
       (gc.open_shared_conflicts = 0)                 as no_unresolved_shared_conflict,
       coalesce((select bool_and(wd.dispatch_eligible) from public.v_workstream_dispatch wd
                  where wd.group_id = gc.group_id and wd.active), false) as all_active_workstreams_eligible,
       coalesce((select array_agg(wd.trade_key order by wd.trade_key) from public.v_workstream_dispatch wd
                  where wd.group_id = gc.group_id and wd.active and not wd.dispatch_eligible),
                '{}'::text[]) as blocking_trades,
       not exists (
         select 1 from public.inquiry_gate_required gr
          where gr.level = 'group'
            and not exists (select 1 from public.inquiry_gate g
                             where g.group_id = gc.group_id and g.workstream_id is null
                               and g.gate_key = gr.gate_key and g.passed)) as group_gates_passed,
       (gc.active_workstreams > 0
        and cardinality(gc.shared_missing_mandatory) = 0
        and gc.open_shared_conflicts = 0
        and coalesce((select bool_and(wd.dispatch_eligible) from public.v_workstream_dispatch wd
                       where wd.group_id = gc.group_id and wd.active), false)
        and not exists (
          select 1 from public.inquiry_gate_required gr
           where gr.level = 'group'
             and not exists (select 1 from public.inquiry_gate g
                              where g.group_id = gc.group_id and g.workstream_id is null
                                and g.gate_key = gr.gate_key and g.passed))) as overall_dispatch_eligible
  from public.v_group_completeness gc;

-- ---------------------------------------------------------------------------------------------
-- 14. Legacy inquiries: no row is created by reading. An existing single-route inquiry has no
--     group and gets one only if a second trade is genuinely added. The compatibility identity is
--     computed, never stored - so nothing is backfilled and nothing is written merely because a
--     view was queried.
-- ---------------------------------------------------------------------------------------------

create or replace view public.v_inquiry_workstream_identity as
select i.id as inquiry_id, g.id as group_id,
       (g.id is not null) as has_group,
       coalesce((select count(*) from public.inquiry_workstream w where w.group_id = g.id and w.active), 1)
         as effective_workstreams,
       case when g.id is null then 'implicit_single_workstream' else 'multi_workstream' end as shape
  from public.inquiry_intake i
  left join public.inquiry_workstream_group g on g.inquiry_id = i.id;

comment on view public.v_inquiry_workstream_identity is
  'Reading this view writes nothing. An inquiry with no group reports one implicit workstream, which is exactly how the system behaves today.';

revoke all on function public.fn_inquiry_answer_set(bigint, text, text, public.answer_precedence, text, text, text, bigint[], jsonb) from public, anon, authenticated;
revoke all on function public.fn_inquiry_answer_confirm(bigint, text, text, text, text, bigint[]) from public, anon, authenticated;
revoke all on function public.fn_inquiry_workstream_activate(bigint, text, text) from public, anon, authenticated;
revoke all on function public.fn_inquiry_workstream_deactivate(bigint, text, text) from public, anon, authenticated;
revoke all on function public.fn_field_normalise(text, text) from public, anon, authenticated;
