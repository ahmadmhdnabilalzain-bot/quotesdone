-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802165328   name: p2_c1_stage_a_mep_model
-- SHA-256 of the applied SQL: bab7ed095c948e1f4c5f9ded77b47e7ccf7ef3e87962899a80c7faa646e4f0f9
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE A - THE MEP DATA MODEL. SHARED ANSWERS ARE REFERENCED, NEVER COPIED.
-- See docs/phases/P2-C1_STAGE_A_DESIGN.md (as amended 2 Aug 2026). Additive only.

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

create unique index if not exists field_definition_identity_uidx
  on public.field_definition (scope, coalesce(trade_key,''), label_en);

create table if not exists public.field_definition_trade (
  field_id   text not null references public.field_definition(field_id) on delete cascade,
  trade_key  text not null references public.mep_trade(trade_key) on delete cascade,
  primary key (field_id, trade_key)
);

create table if not exists public.field_definition_source (
  subcategory_slug  text not null,
  source_field_key  text not null,
  field_id          text not null references public.field_definition(field_id) on delete cascade,
  primary key (subcategory_slug, source_field_key)
);

comment on table public.field_definition_source is
  'Maps imported kb_stage.questions.field_key (a spelling, per subcategory) to a stable field identity. Route 8 says required_completion_date where routes 12/13/14 say required_date; both resolve here to shared.required_completion_date.';

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

create table if not exists public.inquiry_answer_scope (
  answer_id     bigint not null references public.inquiry_answer(id) on delete cascade,
  workstream_id bigint not null references public.inquiry_workstream(id) on delete cascade,
  primary key (answer_id, workstream_id)
);

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
  'A lower-precedence source that agrees with the live value on normalised comparison. The answer is now better attested, not disputed.';

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

create table if not exists public.inquiry_workstream_requirement (
  id            bigserial primary key,
  workstream_id bigint not null references public.inquiry_workstream(id) on delete cascade,
  question_id   text,
  field_id      text not null references public.field_definition(field_id),
  mandatory     boolean not null default false,
  applies_when  jsonb,
  unique (workstream_id, field_id)
);

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

create or replace function public.trg_inquiry_answer_value_immutable()
returns trigger language plpgsql as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'inquiry_answer rows are never deleted (id %)', old.id
      using hint = 'Supersede the answer instead. The chain is the history.';
  end if;
  if new.value       is distinct from old.value
     or new.field_id    is distinct from old.field_id
     or new.group_id    is distinct from old.group_id
     or new.precedence  is distinct from old.precedence
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
;