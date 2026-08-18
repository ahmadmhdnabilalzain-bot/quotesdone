-- PHASE D · D7 — EVERY HANDLER PRODUCES A DECLARED, COUNTABLE EFFECT.
--
-- WHAT THIS CLOSES. fn_phase_d_handler_state() has carried one red since D6:
--
--     handlers_not_writing_a_business_object   expected 0   actual 257
--
-- 257 steps had a typed contract, a validated output and a kernel that accepted it, and not one
-- of them produced a business effect. The D6 file said so in its own comment and the closure named
-- it "the single largest honest gap in Phase D". This is that increment.
--
-- THE PART THE BRIEF WAS RIGHT TO WARN ABOUT, TWICE:
--
--   "Do not force meaningless database writes for measurement, closure or capability-boundary
--    steps."
--   "steps with no persistent or kernel-verifiable effect = 0"
--
-- Those two sentences together rule out the lazy answer — give all 257 an INSERT somewhere and
-- watch the number fall. A closure step's effect is the run reaching a terminal state; a
-- measurement step's effect is a number with a real denominator; a capability step's effect is a
-- refusal. Inventing a domain row for any of them would be the always-passes scorer rebuilt one
-- layer down. So each step DECLARES which of the seven effect types it produces, the declaration
-- is DERIVED from the frozen Phase B text rather than typed by whoever wrote this file, and the
-- executor produces exactly that.
--
-- THREE THINGS MEASURED FIRST, EACH OF WHICH CHANGED THE DESIGN:
--
-- 1. business_object_writes was EMPTY on all 257 bindings, and empty in the package matrix too —
--    the column exists in PHASE_D_STEP_HANDLER_IMPLEMENTATION_MATRIX.csv and 0 of 257 rows carry a
--    value. Nothing anywhere said which object a step writes. It is derived here, and HOW each one
--    was anchored is recorded per row, because a resolution nobody can audit is a guess with a
--    column name.
--
-- 2. Four of the 26 existing-table objects are the KERNEL'S OWN: workflow_run, workflow_step_run,
--    handoff_record (phase_c_*) and they are written by fn_kernel_step_complete. A handler that
--    wrote them would be the parallel engine the spec forbids, and it is the exact shape of the
--    defect that deadlocked 16 of 30 workflows when workflow_start and step_complete both created
--    the same handoff run. The effect service REFUSES them by name.
--
-- 3. public.notifications is read by three outbound senders (email_cron_2min, sms_flush, wa_flush).
--    All three are currently INACTIVE, and "currently" is not a guarantee — a row written with
--    status 'pending' becomes a live send the moment one is re-enabled, which is the shape of
--    "deploy the quarantine before the worker". So notification effects do NOT write
--    public.notifications. They are EXTERNAL_EFFECT_INTENT and land in the Phase D effect ledger
--    with provider_mode = 'mock'. Live external effects stay 0 BY CONSTRUCTION, not by a hold that
--    somebody could lift without reading this comment.
--
-- TWO PRE-EXISTING GRANT DEFECTS FOUND WHILE READING THE CATALOGUE, fixed at the bottom:
-- fn_phase_d_rule_check and fn_phase_d_gate_applies are executable by anon. Neither is SECURITY
-- DEFINER so neither escalates, but both read the frozen registries and would answer an
-- unauthenticated caller about the estate's rule and gate structure. Same shape as "promote
-- carries the definition, not the grants".

begin;

-- =====================================================================================
-- 1. THE EFFECT CONTRACT — one row per frozen step, every field the brief asks for
-- =====================================================================================

create table if not exists public.phase_d_step_effect (
  step_id                   text primary key,
  workflow_id               text not null,
  step_type                 text not null,
  expected_effect_type      text not null,
  effect_object_id          text,
  object_resolution         text not null,
  effect_relation           text,
  effect_service            text not null,
  effect_operation          text not null,
  expected_state_transition text not null,
  completion_condition      text not null,
  result_reference          text not null,
  trace_reference           text not null,
  implementation_depth      text not null,
  actual_caller             text not null,
  effect_evidence           text not null,
  derived_at                timestamptz not null default now(),
  constraint phase_d_step_effect_type_ck check (expected_effect_type in (
    'DOMAIN_MUTATION','VERSIONED_ARTIFACT','REVIEW_VERDICT','MEASUREMENT_RECORD',
    'EXTERNAL_EFFECT_INTENT','CAPABILITY_REQUEST','KERNEL_ONLY_TRANSITION')),
  constraint phase_d_step_effect_depth_ck check (implementation_depth in (
    'SCHEMA_ONLY','VALIDATION_ONLY','SERVICE_EXISTS_NO_CALLER','BUSINESS_EFFECT_CONNECTED',
    'CAPABILITY_BOUNDARY_READY','EXTERNAL_ADAPTER_READY_DISABLED','COMPLETE','BLOCKED_DEFECT')),
  constraint phase_d_step_effect_resolution_ck check (object_resolution in (
    'MATCHED_STEP_TEXT','SOLE_OBJECT_OF_WORKFLOW','WORKFLOW_PRIMARY_OBJECT','NO_DOMAIN_OBJECT'))
);

comment on table public.phase_d_step_effect is
  'One row per frozen Phase B step declaring the effect that step produces. expected_effect_type '
  'and effect_object_id are DERIVED from the frozen registry, never typed: object_resolution says '
  'which of three rules anchored the object so the derivation can be audited rather than trusted. '
  'implementation_depth answers "what does this handler actually do today", which phase_d_status '
  'answers about the handler CLASS and was being read as if it answered both.';

-- =====================================================================================
-- 2. THE WRITE MAP — how an existing-table object is written, validated against the catalogue
-- =====================================================================================

create table if not exists public.phase_d_object_write_map (
  object_id        text primary key,
  target_relation  text not null,
  operation        text not null,
  key_column       text not null,
  owner_column     text,
  column_map       jsonb not null,
  quarantine_note  text,
  constraint phase_d_object_write_map_op_ck check (operation in ('INSERT','UPSERT_STATE')),
  constraint phase_d_object_write_map_cols_ck check (jsonb_typeof(column_map) = 'object')
);

comment on table public.phase_d_object_write_map is
  'column_map is {target_column: payload_key}. Validated at apply time against '
  'information_schema: every declared column must exist, and every column the target requires — '
  'NOT NULL, no default, not an identity column — must be covered. A map that would fail at '
  'runtime therefore cannot be deployed. Casts are resolved from the catalogue at write time '
  'rather than stored, so an ALTER TYPE cannot leave a stale cast behind.';

-- The four kernel-owned objects are deliberately ABSENT from this table. Their writer is
-- fn_kernel_step_complete and a second one is the defect, not the feature.
insert into public.phase_d_object_write_map
  (object_id, target_relation, operation, key_column, owner_column, column_map, quarantine_note)
values
  ('company_objective','public.company_goals','UPSERT_STATE','key',null,
    '{"key":"business_key","goal":"goal","metric":"metric","direction":"direction","active":"active"}'::jsonb,null),
  ('department_mandate','public.department_objective','INSERT','id','dept_key',
    '{"dept_key":"owner_ref","objective":"objective","status":"state","goal_key":"goal_key"}'::jsonb,null),
  ('initiative','public.org_tasks','UPSERT_STATE','id','dept_key',
    '{"title":"title","status":"state","dept_key":"owner_ref","detail":"detail"}'::jsonb,null),
  ('campaign_asset','public.content_drafts','INSERT','id',null,
    '{"body":"body","channel":"channel","status":"state","title":"title","category":"category"}'::jsonb,
    'Publication is disabled for the whole of Phase D: a draft row is not a post.'),
  ('customer_account','public.customers','UPSERT_STATE','id',null,
    '{"id":"business_key","email":"email","full_name":"full_name","phone":"phone","locale":"locale"}'::jsonb,null),
  ('inquiry','public.inquiries','UPSERT_STATE','id','customer_id',
    '{"id":"business_key","customer_id":"owner_ref","status":"state","spec":"spec","category":"category","summary":"summary"}'::jsonb,null),
  ('inquiry_answer','public.inquiry_answer','INSERT','id',null,
    '{"group_id":"group_id","field_id":"field_id","scope":"answer_scope","precedence":"precedence","source_kind":"source_kind","value":"value"}'::jsonb,null),
  ('inquiry_document','public.documents','INSERT','id',null,
    '{"bucket":"bucket","path":"path","kind":"kind","status":"state","file_name":"file_name","mime":"mime"}'::jsonb,null),
  ('supplier_account','public.leads','UPSERT_STATE','id',null,
    '{"company_name":"company_name","email":"email","approval_status":"state"}'::jsonb,null),
  ('supplier_capability','public.supplier_capabilities','UPSERT_STATE','supplier_id','supplier_id',
    '{"supplier_id":"owner_ref","trades":"trades","review_status":"state"}'::jsonb,null),
  ('supplier_assignment','public.inquiry_matches','INSERT','id','supplier_id',
    '{"inquiry_id":"inquiry_id","supplier_id":"owner_ref","similarity":"similarity","match_reason":"match_reason"}'::jsonb,null),
  ('quotation','public.quotes','UPSERT_STATE','id','supplier_id',
    '{"id":"business_key","quote_amount":"quote_amount","supplier_id":"owner_ref","inquiry_id":"inquiry_id","status":"state"}'::jsonb,null),
  ('quotation_comparison','public.quote_comparisons','INSERT','id','customer_id',
    '{"inquiry_id":"inquiry_id","analysis":"analysis","customer_id":"owner_ref","signature":"signature","quote_count":"quote_count"}'::jsonb,null),
  ('provider_event','public.stripe_events','INSERT','event_id',null,
    '{"event_id":"business_key","payment_status":"state","type":"event_type"}'::jsonb,
    'An inbound provider event is recorded, never produced: nothing here calls Stripe.'),
  ('invoice_receipt','public.reveal_invoices','INSERT','invoice_no',null,
    '{"transaction_id":"transaction_id","invoice_no":"business_key","bucket":"bucket","path":"path"}'::jsonb,null),
  ('partnership_opportunity','public.opportunity','INSERT','id',null,
    '{"kind":"kind","title":"title","status":"state","detail":"detail"}'::jsonb,null),
  ('legal_risk_review','public.legal_reviews','INSERT','id',null,
    '{"title":"title","doc_kind":"doc_kind","risk_level":"risk_level","summary":"summary"}'::jsonb,null),
  ('incident','public.os_incidents','INSERT','id',null,
    '{"title":"title","kind":"kind","severity":"severity","status":"state","detail":"detail"}'::jsonb,null),
  ('review_record','public.review_chain','INSERT','id','dept_key',
    '{"dept_key":"owner_ref","stage":"stage","decision":"verdict","reviewer_agent":"reviewer_role_id","reason":"notes","subject_type":"subject_type","subject_id":"subject_id","author_agent":"author_agent"}'::jsonb,null)
on conflict (object_id) do update set
  target_relation = excluded.target_relation, operation = excluded.operation,
  key_column = excluded.key_column, owner_column = excluded.owner_column,
  column_map = excluded.column_map, quarantine_note = excluded.quarantine_note;

-- ---- the map validates itself against the live catalogue, or this file does not deploy --------
do $$
declare
  m record; c record; v_missing text[]; v_bad text[]; v_req text[]; v_declared text[];
begin
  for m in select * from public.phase_d_object_write_map loop
    -- the relation itself
    if not exists (select 1 from information_schema.tables t
                    where t.table_schema = split_part(m.target_relation,'.',1)
                      and t.table_name   = split_part(m.target_relation,'.',2)) then
      raise exception 'phase_d_object_write_map: % names relation % which does not exist',
        m.object_id, m.target_relation;
    end if;

    -- every declared column exists
    v_bad := '{}';
    for c in select k from jsonb_object_keys(m.column_map) k loop
      if not exists (select 1 from information_schema.columns ic
                      where ic.table_schema = split_part(m.target_relation,'.',1)
                        and ic.table_name   = split_part(m.target_relation,'.',2)
                        and ic.column_name  = c.k) then
        v_bad := v_bad || c.k;
      end if;
    end loop;
    if cardinality(v_bad) > 0 then
      raise exception 'phase_d_object_write_map: % declares column(s) % that % does not have',
        m.object_id, array_to_string(v_bad, ', '), m.target_relation;
    end if;

    -- the key column exists
    if not exists (select 1 from information_schema.columns ic
                    where ic.table_schema = split_part(m.target_relation,'.',1)
                      and ic.table_name   = split_part(m.target_relation,'.',2)
                      and ic.column_name  = m.key_column) then
      raise exception 'phase_d_object_write_map: % names key column % absent from %',
        m.object_id, m.key_column, m.target_relation;
    end if;

    -- IDENTITY COLUMNS ARE EXCLUDED FROM "REQUIRED". information_schema reports a GENERATED ALWAYS
    -- identity column as NOT NULL with a null column_default, which reads as "you must supply
    -- this" and is the opposite of the truth: supplying it is refused. Seven of these targets have
    -- one, so a naive required-set would have demanded a value Postgres will not accept.
    select coalesce(array_agg(ic.column_name order by ic.ordinal_position), '{}') into v_req
      from information_schema.columns ic
     where ic.table_schema = split_part(m.target_relation,'.',1)
       and ic.table_name   = split_part(m.target_relation,'.',2)
       and ic.is_nullable = 'NO' and ic.column_default is null and ic.is_identity = 'NO'
       and ic.is_generated = 'NEVER';

    select coalesce(array_agg(k), '{}') into v_declared from jsonb_object_keys(m.column_map) k;
    select coalesce(array_agg(r), '{}') into v_missing
      from unnest(v_req) r where not (r = any (v_declared));
    if cardinality(v_missing) > 0 then
      raise exception 'phase_d_object_write_map: % cannot write % — required column(s) % are not in the map. A map that fails at runtime must not deploy.',
        m.object_id, m.target_relation, array_to_string(v_missing, ', ');
    end if;
  end loop;
end $$;

-- =====================================================================================
-- 3. THE EFFECT LEDGER — the universal, countable record that an effect happened
-- =====================================================================================

create table if not exists public.phase_d_effect_ledger (
  effect_id          bigserial primary key,
  step_run_id        bigint not null,
  step_id            text not null,
  workflow_id        text not null,
  run_id             bigint,
  effect_type        text not null,
  effect_object_id   text,
  effect_relation    text,
  effect_operation   text not null,
  result_reference   text not null,
  state_before       text,
  state_after        text,
  provider_mode      text not null default 'none',
  payload_digest     text not null,
  idempotency_key    text not null,
  produced_by        text not null,
  trace_id           bigint,
  produced_at        timestamptz not null default now(),
  constraint phase_d_effect_ledger_one_per_step_run unique (step_run_id, effect_type),
  constraint phase_d_effect_ledger_mode_ck check (provider_mode in ('none','mock','disabled'))
);

comment on table public.phase_d_effect_ledger is
  'One row per effect actually produced. The UNIQUE on (step_run_id, effect_type) is the '
  'idempotency guarantee expressed as a constraint rather than as a convention: a replayed handler '
  'reads this row back instead of producing a second effect, and the count of rows — not the '
  'result payload — is what a duplicate-effect test asserts on.';

comment on column public.phase_d_effect_ledger.provider_mode is
  'none for a database-only effect; mock for an external-effect intent, which is recorded and '
  'never sent; disabled where a provider is held. There is no ''live'' value, so a live send '
  'cannot be represented here at all.';

create index if not exists phase_d_effect_ledger_step_idx on public.phase_d_effect_ledger (step_id);
create index if not exists phase_d_effect_ledger_run_idx  on public.phase_d_effect_ledger (run_id);

-- =====================================================================================
-- 4. DERIVE THE 257 EFFECT CONTRACTS FROM THE FROZEN REGISTRY
-- =====================================================================================

-- Object candidacy. governing_workflow_id is not always a single id: the frozen registry carries
-- 'W03/W20', 'W09/W10', 'W16/W27' and 'ALL'. Matching it with = would have silently dropped four
-- objects and pushed their steps onto the workflow's primary object; splitting on '/' resolves
-- them. 'ALL' is deliberately NOT a candidate: those four are the kernel's own tables.
with candidate as (
  select s.step_id, s.workflow_id, o.object_id,
         length(replace(o.object_id, '_', ' ')) as tok_len
    from public.phase_b_workflow_step s
    join public.phase_b_business_object o
      on o.governing_workflow_id <> 'ALL'
     and s.workflow_id = any (string_to_array(o.governing_workflow_id, '/'))
),
-- Longest matching token wins, so 'inquiry_version' beats 'inquiry' on a step that names the
-- version. Shortest-first would have resolved every W05 step to 'inquiry'.
matched as (
  select c.step_id, c.object_id, c.tok_len,
         row_number() over (partition by c.step_id order by c.tok_len desc, c.object_id) as rn
    from candidate c
    join public.phase_b_workflow_step s on s.step_id = c.step_id
   where lower(concat_ws(' ', s.step_name, s.required_action, s.required_output))
           ~ ('\y' || replace(c.object_id, '_', '[ _]') || '\y')
),
counts as (
  select step_id, count(*) as n from candidate group by 1
),
sole as (
  select c.step_id, min(c.object_id) as object_id
    from candidate c join counts n on n.step_id = c.step_id and n.n = 1
   group by 1
),
resolved as (
  select s.step_id, s.workflow_id, s.step_type,
         coalesce(m.object_id, so.object_id, w.primary_object) as object_id,
         case when m.object_id is not null then 'MATCHED_STEP_TEXT'
              when so.object_id is not null then 'SOLE_OBJECT_OF_WORKFLOW'
              else 'WORKFLOW_PRIMARY_OBJECT' end as object_resolution,
         coalesce(n.n, 0) as candidates
    from public.phase_b_workflow_step s
    join public.phase_b_workflow w on w.workflow_id = s.workflow_id
    left join matched m  on m.step_id = s.step_id and m.rn = 1
    left join sole    so on so.step_id = s.step_id
    left join counts  n  on n.step_id = s.step_id
),
-- The outbound lexicon, matched at a WORD BOUNDARY on the frozen required_action, with the matched
-- token recorded. Two guards that a bare keyword list does not have:
--   * an inbound verb (receive/accept/authenticate) VETOES the match, because receiving a provider
--     webhook is not us producing an external effect — W16-S03 reads "Receive and authenticate the
--     provider event" and is a domain write, not a send;
--   * review, analysis and measurement families cannot match at all: those assess, they do not act.
outbound as (
  select s.step_id,
         (select string_agg(t, '+' order by t) from unnest(array[
            'send','sends','deliver','delivers','publish','publishes','notify','notifies',
            'dispatch','transmit','charge','charges','email','present','provider']) t
           where lower(coalesce(s.required_action,'')) ~ ('\y' || t || '\y')) as tokens,
         (lower(coalesce(s.required_action,'')) ~ '\y(receive|receives|received|accept|accepts|authenticate)\y')
           as inbound_veto
    from public.phase_b_workflow_step s
   where s.step_type not in ('review','analysis','measurement')
)
insert into public.phase_d_step_effect (
  step_id, workflow_id, step_type, expected_effect_type, effect_object_id, object_resolution,
  effect_relation, effect_service, effect_operation, expected_state_transition,
  completion_condition, result_reference, trace_reference, implementation_depth,
  actual_caller, effect_evidence)
select
  r.step_id, r.workflow_id, r.step_type,
  eff.effect_type,
  case when eff.effect_type in ('KERNEL_ONLY_TRANSITION','CAPABILITY_REQUEST') then null
       else r.object_id end,
  case when eff.effect_type in ('KERNEL_ONLY_TRANSITION','CAPABILITY_REQUEST') then 'NO_DOMAIN_OBJECT'
       else r.object_resolution end,
  case when eff.effect_type in ('KERNEL_ONLY_TRANSITION','CAPABILITY_REQUEST') then null
       when eff.effect_type = 'EXTERNAL_EFFECT_INTENT' then 'public.phase_d_effect_ledger'
       else b.canonical_relation end,
  case when eff.effect_type = 'KERNEL_ONLY_TRANSITION'
         then 'public.fn_kernel_step_complete(jsonb)'
       else 'public.fn_phase_d_effect_produce(jsonb)' end,
  eff.operation,
  eff.transition,
  eff.completion,
  eff.result_ref,
  'public.phase_c_trace via run_id and step_run_id; public.phase_d_effect_ledger.effect_id',
  eff.depth,
  'public.fn_phase_d_handler_execute(jsonb)',
  eff.evidence
from resolved r
left join public.phase_d_business_object_binding b on b.object_id = r.object_id
left join outbound ob on ob.step_id = r.step_id
cross join lateral (
  select
    -- ---- THE DERIVATION, IN PRIORITY ORDER -------------------------------------------------
    case
      when hb.capability_dependency <> 'NONE'                    then 'CAPABILITY_REQUEST'
      when hb.provider_dependency  <> 'NONE'                     then 'EXTERNAL_EFFECT_INTENT'
      when ob.tokens is not null and not ob.inbound_veto         then 'EXTERNAL_EFFECT_INTENT'
      when r.object_id in ('notification','notification_attempt')
           and r.step_type = 'execution'                         then 'EXTERNAL_EFFECT_INTENT'
      when r.step_type = 'measurement'                           then 'MEASUREMENT_RECORD'
      when r.step_type = 'review'                                then 'REVIEW_VERDICT'
      when r.step_type in ('closure','handoff')                  then 'KERNEL_ONLY_TRANSITION'
      when b.policy_family in ('VERSIONED','IMMUTABLE_REVISION') then 'VERSIONED_ARTIFACT'
      else 'DOMAIN_MUTATION'
    end as effect_type
  from public.phase_d_handler_binding hb where hb.step_id = r.step_id
) t0
cross join lateral (
  select
    t0.effect_type,
    case t0.effect_type
      when 'KERNEL_ONLY_TRANSITION'  then 'KERNEL_STEP_RUN'
      when 'CAPABILITY_REQUEST'      then 'CAPABILITY_REQUEST_RECORD'
      when 'EXTERNAL_EFFECT_INTENT'  then 'EXTERNAL_INTENT_RECORD'
      when 'MEASUREMENT_RECORD'      then 'MEASUREMENT_RECORD'
      when 'REVIEW_VERDICT'          then 'REVIEW_VERDICT_RECORD'
      when 'VERSIONED_ARTIFACT'      then 'OBJECT_VERSION_WRITE'
      else 'OBJECT_STATE_WRITE'
    end as operation,
    case t0.effect_type
      when 'KERNEL_ONLY_TRANSITION' then
        format('step run %s -> completed; workflow run -> %s',
               r.step_id, coalesce(s2.success_workflow_state,'(frozen successor state)'))
      when 'CAPABILITY_REQUEST' then
        'no state moves: the capability is unavailable in Phase D and the step refuses'
      when 'EXTERNAL_EFFECT_INTENT' then
        'intent recorded as mock; no provider state moves and nothing is sent'
      when 'MEASUREMENT_RECORD' then
        'no object state moves: a measurement observes, it does not mutate'
      when 'REVIEW_VERDICT' then
        format('review_record appended with the caller''s verdict; %s', coalesce(s2.required_output,''))
      else format('%s -> %s', coalesce(b.status_model,'(declared state model)'),
                  coalesce(nullif(s2.required_output,''),'(frozen required_output)'))
    end as transition,
    case t0.effect_type
      when 'KERNEL_ONLY_TRANSITION' then
        'fn_kernel_step_complete returned ok and the step run reached completed; for a closure step '
        || 'the run also reached a frozen terminal state'
      when 'CAPABILITY_REQUEST' then
        'the executor raised pd_capability_unavailable and no business row was written'
      when 'EXTERNAL_EFFECT_INTENT' then
        'a phase_d_effect_ledger row exists with provider_mode = mock and no provider request id'
      when 'MEASUREMENT_RECORD' then
        'a ledger row carries a numerator and a NON-ZERO denominator, both supplied by the caller'
      when 'REVIEW_VERDICT' then
        'a review_record row names a reviewer who resolves independently of the accountable owner'
      else format('a row exists in %s carrying the declared state, readable back in the same transaction',
                  coalesce(b.canonical_relation,'(bound relation)'))
    end as completion,
    case t0.effect_type
      when 'KERNEL_ONLY_TRANSITION' then 'phase_c_workflow_step_run.step_run_id'
      else 'phase_d_effect_ledger.effect_id + result_reference'
    end as result_ref,
    case t0.effect_type
      when 'KERNEL_ONLY_TRANSITION'   then 'BUSINESS_EFFECT_CONNECTED'
      when 'CAPABILITY_REQUEST'       then 'CAPABILITY_BOUNDARY_READY'
      when 'EXTERNAL_EFFECT_INTENT'   then 'EXTERNAL_ADAPTER_READY_DISABLED'
      else 'BUSINESS_EFFECT_CONNECTED'
    end as depth,
    concat_ws(' | ',
      format('step_type=%s', r.step_type),
      format('object=%s anchored by %s from %s candidate(s)',
             coalesce(r.object_id,'(none)'), r.object_resolution, r.candidates),
      case when b.policy_family is not null then format('policy_family=%s', b.policy_family) end,
      case when ob.tokens is not null then
        format('outbound token(s) matched in required_action: %s%s', ob.tokens,
               case when ob.inbound_veto then ' — VETOED, the action also names an inbound verb'
                    else '' end) end,
      case when hb2.capability_dependency <> 'NONE' then
        format('capability=%s', hb2.capability_dependency) end
    ) as evidence
  from public.phase_b_workflow_step s2
  join public.phase_d_handler_binding hb2 on hb2.step_id = s2.step_id
  where s2.step_id = r.step_id
) eff
on conflict (step_id) do update set
  workflow_id = excluded.workflow_id, step_type = excluded.step_type,
  expected_effect_type = excluded.expected_effect_type,
  effect_object_id = excluded.effect_object_id,
  object_resolution = excluded.object_resolution,
  effect_relation = excluded.effect_relation, effect_service = excluded.effect_service,
  effect_operation = excluded.effect_operation,
  expected_state_transition = excluded.expected_state_transition,
  completion_condition = excluded.completion_condition,
  result_reference = excluded.result_reference, trace_reference = excluded.trace_reference,
  implementation_depth = excluded.implementation_depth, actual_caller = excluded.actual_caller,
  effect_evidence = excluded.effect_evidence, derived_at = now();

-- 257 or this file does not deploy. A partial derivation that looks complete is the defect.
do $$
declare n int; m int;
begin
  select count(*) into n from public.phase_d_step_effect;
  select count(*) into m from public.phase_b_workflow_step;
  if n <> m then
    raise exception 'phase_d_step_effect: derived % effect contracts for % frozen steps', n, m;
  end if;
  select count(*) into n from public.phase_d_step_effect
   where expected_effect_type not in ('KERNEL_ONLY_TRANSITION','CAPABILITY_REQUEST')
     and effect_object_id is null;
  if n > 0 then
    raise exception 'phase_d_step_effect: % step(s) declare a domain effect with no object', n;
  end if;
end $$;

-- Mirror the resolved objects back onto the handler bindings, which have carried empty arrays
-- since D1 because nothing anywhere said what a step writes.
update public.phase_d_handler_binding b
   set business_object_writes = case when e.effect_object_id is null then '{}'::text[]
                                     else array[e.effect_object_id] end,
       business_object_reads  = coalesce((
         select array_agg(distinct o.object_id order by o.object_id)
           from public.phase_b_business_object o
          where o.governing_workflow_id <> 'ALL'
            and b.workflow_id = any (string_to_array(o.governing_workflow_id, '/'))), '{}'::text[])
  from public.phase_d_step_effect e
 where e.step_id = b.step_id;

-- =====================================================================================
-- 5. THE OBJECT WRITE SERVICE LEARNS TO WRITE AN EXISTING TABLE
-- =====================================================================================

create or replace function public.fn_phase_d_object_write(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  b            public.phase_d_business_object_binding%rowtype;
  wm           public.phase_d_object_write_map%rowtype;
  v_object     text  := nullif(btrim(coalesce(p_input->>'object_id','')),'');
  v_key        text  := nullif(btrim(coalesce(p_input->>'business_key','')),'');
  v_owner_ref  text  := nullif(btrim(coalesce(p_input->>'owner_ref','')),'');
  v_payload    jsonb := p_input->'payload';
  v_actor      text  := nullif(btrim(coalesce(p_input->>'created_by','')),'');
  v_state      text  := coalesce(nullif(btrim(p_input->>'state'),''), 'open');
  v_prior      public.phase_d_object_record%rowtype;
  v_version    integer := 1;
  v_id         bigint;
  v_readback   public.phase_d_object_record%rowtype;
  v_cols       text[] := '{}';
  v_vals       text[] := '{}';
  v_sets       text[] := '{}';
  v_col        record;
  v_expr       text;
  v_pkey       text;
  v_existing   text;
  v_result_ref text;
  v_sql        text;
  v_supplied   jsonb;
begin
  if v_object is null or v_key is null or v_actor is null then
    raise exception 'fn_phase_d_object_write: object_id, business_key and created_by are all required (got %, %, %) (pd_object_input_invalid)',
      coalesce(v_object,'(null)'), coalesce(v_key,'(null)'), coalesce(v_actor,'(null)')
      using errcode = '22023';
  end if;

  select * into b from public.phase_d_business_object_binding where object_id = v_object;
  if not found then
    raise exception 'fn_phase_d_object_write: % is not a bound Phase D business object — fail closed rather than store a record under a policy nobody declared (pd_object_unbound)',
      v_object using errcode = '23503';
  end if;

  if v_payload is null or jsonb_typeof(v_payload) <> 'object' or v_payload = '{}'::jsonb then
    raise exception 'fn_phase_d_object_write: % sent payload of type %. An empty object is not evidence that anything was recorded. (pd_object_payload_empty)',
      v_object, coalesce(jsonb_typeof(v_payload),'null') using errcode = '22023';
  end if;

  if v_owner_ref is null then
    raise exception 'fn_phase_d_object_write: % is %-scoped and the call names no owner_ref. An unowned business record is the accountability gap this map exists to close. (pd_object_owner_missing)',
      v_object, b.ownership_scope using errcode = '22023';
  end if;

  -- ================= EXISTING TABLE: a real write, through the declared map =================
  if b.relation_kind = 'EXISTING_TABLE' then
    -- THE KERNEL'S OWN TABLES ARE NOT WRITABLE FROM HERE, AND THIS IS THE POINT OF THE BRANCH.
    -- workflow_run, workflow_step_run and handoff_record are created and moved by
    -- fn_kernel_step_complete. Two creators for one object is what deadlocked 16 of 30 workflows
    -- when workflow_start and step_complete both made the same handoff run; it is not repeated
    -- here because a handler asked politely.
    if b.governing_workflow_id = 'ALL' and v_object <> 'review_record' then
      raise exception 'fn_phase_d_object_write: % is written by the frozen kernel (%). A Phase D handler that wrote it would be a second creator for one object. Use fn_kernel_step_complete. (pd_object_kernel_owned)',
        v_object, b.canonical_relation using errcode = '23514';
    end if;

    select * into wm from public.phase_d_object_write_map where object_id = v_object;
    if not found then
      raise exception 'fn_phase_d_object_write: % is bound to existing relation % and no write map is declared for it. Refusing to guess a column layout. (pd_object_no_write_map)',
        v_object, b.canonical_relation using errcode = '23503';
    end if;

    -- The payload the caller actually sent, plus the four facts every write carries. state and
    -- owner_ref are named here so a map can point a column at either without the caller repeating
    -- them; nothing else is defaulted.
    v_supplied := v_payload
                  || jsonb_build_object('state', v_state, 'owner_ref', v_owner_ref,
                                        'business_key', v_key);

    for v_col in
      select k.key as col, wm.column_map->>k.key as src,
             format_type(a.atttypid, a.atttypmod) as ftype,
             (select typcategory from pg_type ty where ty.oid = a.atttypid) as tcat,
             a.attidentity, a.attgenerated
        from jsonb_each(wm.column_map) k
        join pg_attribute a
          on a.attrelid = wm.target_relation::regclass and a.attname = k.key and a.attnum > 0
       order by k.key
    loop
      -- A GENERATED ALWAYS identity or generated column cannot be written. The map validator
      -- excludes them from "required"; this excludes them from the statement.
      if v_col.attidentity = 'a' or v_col.attgenerated <> '' then continue; end if;
      if not (v_supplied ? v_col.src) then continue; end if;

      v_expr := case
        when v_col.ftype = 'jsonb' or v_col.ftype = 'json' then
          format('($1->%L)', v_col.src)
        when v_col.tcat = 'A' then
          format('(select coalesce(array_agg(x::text),''{}'')::%s from jsonb_array_elements_text($1->%L) x)',
                 v_col.ftype, v_col.src)
        else
          format('($1->>%L)::%s', v_col.src, v_col.ftype)
      end;
      v_cols := v_cols || quote_ident(v_col.col);
      v_vals := v_vals || v_expr;
      if v_col.col <> wm.key_column then
        v_sets := v_sets || format('%I = %s', v_col.col, v_expr);
      end if;
    end loop;

    if cardinality(v_cols) = 0 then
      raise exception 'fn_phase_d_object_write: % supplied no column the write map for % can use. Payload keys were %. (pd_object_payload_unmapped)',
        v_object, wm.target_relation,
        coalesce((select string_agg(k,', ' order by k) from jsonb_object_keys(v_supplied) k),'(none)')
        using errcode = '22023';
    end if;

    if wm.operation = 'UPSERT_STATE' then
      v_sql := format('select %I::text from %s where %I::text = $2 limit 1',
                      wm.key_column, wm.target_relation, wm.key_column);
      execute v_sql into v_existing using v_supplied, v_key;
      if v_existing is not null then
        if cardinality(v_sets) = 0 then
          raise exception 'fn_phase_d_object_write: % exists as % and the payload moves no column. A write that changes nothing is not a state transition. (pd_object_no_state_change)',
            v_object, v_existing using errcode = '22023';
        end if;
        v_sql := format('update %s set %s where %I::text = $2 returning %I::text',
                        wm.target_relation, array_to_string(v_sets, ', '),
                        wm.key_column, wm.key_column);
        execute v_sql into v_result_ref using v_supplied, v_key;
      else
        v_sql := format('insert into %s (%s) values (%s) returning %I::text',
                        wm.target_relation, array_to_string(v_cols, ', '),
                        array_to_string(v_vals, ', '), wm.key_column);
        execute v_sql into v_result_ref using v_supplied;
      end if;
    else
      v_sql := format('insert into %s (%s) values (%s) returning %I::text',
                      wm.target_relation, array_to_string(v_cols, ', '),
                      array_to_string(v_vals, ', '), wm.key_column);
      execute v_sql into v_result_ref using v_supplied;
    end if;

    -- A NULL RETURN IS NOT A WRITE. A BEFORE trigger returning NULL gives a statement that
    -- "succeeded" with no row; the returned key is what separates the two.
    if v_result_ref is null then
      raise exception 'fn_phase_d_object_write: the write to % for % returned no key. Refusing to report a write that produced nothing. (pd_object_write_produced_nothing)',
        wm.target_relation, v_object using errcode = '23502';
    end if;

    return jsonb_build_object(
      'ok', true, 'object_id', v_object, 'relation_kind', 'EXISTING_TABLE',
      'canonical_relation', wm.target_relation, 'operation', wm.operation,
      'result_reference', format('%s:%s=%s', wm.target_relation, wm.key_column, v_result_ref),
      'business_key', v_key, 'state', v_state,
      'policy_family', b.policy_family, 'record_policy', b.record_policy,
      'owner_scope', b.ownership_scope, 'owner_ref', v_owner_ref,
      'columns_written', to_jsonb(v_cols),
      'quarantine_note', wm.quarantine_note,
      'payload_digest', encode(sha256(convert_to(v_payload::text,'UTF8')),'hex'));
  end if;

  -- ================= PHASE D STORE: unchanged behaviour from D2 =================
  select * into v_prior from public.phase_d_object_record
   where object_id = v_object and business_key = v_key and superseded_by is null
   order by version desc limit 1;

  if found then
    if b.policy_family = 'APPEND_ONLY' then
      raise exception 'fn_phase_d_object_write: % is APPEND_ONLY (%) and business key % already holds record %. A correction is a NEW key, never a second version of this one. (pd_object_append_only)',
        v_object, b.record_policy, v_key, v_prior.record_id using errcode = '23514';
    end if;
    if b.policy_family = 'TRANSACTION_RECORD' then
      raise exception 'fn_phase_d_object_write: % is a %-family record and business key % already exists as record %. One record per identity; move its state, do not write a second. (pd_object_duplicate_identity)',
        v_object, b.policy_family, v_key, v_prior.record_id using errcode = '23505';
    end if;
    v_version := v_prior.version + 1;
  end if;

  insert into public.phase_d_object_record
    (object_id, business_key, version, state, owner_scope, owner_ref, payload,
     run_id, step_run_id, trace_id, created_by)
  values (v_object, v_key, v_version, v_state, b.ownership_scope, v_owner_ref, v_payload,
          nullif(p_input->>'run_id','')::bigint, nullif(p_input->>'step_run_id','')::bigint,
          nullif(p_input->>'trace_id','')::bigint, v_actor)
  returning record_id into v_id;

  if v_id is null then
    raise exception 'fn_phase_d_object_write: the insert for % / % returned no record_id. Refusing to report a write that produced nothing. (pd_object_write_produced_nothing)',
      v_object, v_key using errcode = '23502';
  end if;
  select * into v_readback from public.phase_d_object_record where record_id = v_id;
  if not found then
    raise exception 'fn_phase_d_object_write: record % is not readable back in the same transaction. (pd_object_write_not_readable)',
      v_id using errcode = '23502';
  end if;

  if v_prior.record_id is not null
     and b.policy_family in ('VERSIONED','IMMUTABLE_REVISION','CASE_RECORD','MUTABLE_CONTROLLED') then
    update public.phase_d_object_record
       set superseded_by = v_id, superseded_at = now()
     where record_id = v_prior.record_id;
  end if;

  return jsonb_build_object(
    'ok', true, 'object_id', v_object, 'relation_kind', 'PHASE_D_OBJECT_VIEW',
    'record_id', v_id, 'business_key', v_key,
    'result_reference', format('public.phase_d_object_record:record_id=%s', v_id),
    'version', v_version, 'state', v_readback.state,
    'policy_family', b.policy_family, 'record_policy', b.record_policy,
    'owner_scope', b.ownership_scope, 'owner_ref', v_owner_ref,
    'canonical_relation', b.canonical_relation,
    'superseded_record_id', v_prior.record_id,
    'payload_digest', encode(sha256(convert_to(v_payload::text,'UTF8')),'hex'));
end $fn$;

-- =====================================================================================
-- 6. THE EFFECT SERVICE — one entry point, seven declared effect types
-- =====================================================================================

create or replace function public.fn_phase_d_effect_produce(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  e            public.phase_d_step_effect%rowtype;
  sr           public.phase_c_workflow_step_run%rowtype;
  prior        public.phase_d_effect_ledger%rowtype;
  v_step_run   bigint := nullif(p_input->>'step_run_id','')::bigint;
  v_idem       text   := nullif(btrim(coalesce(p_input->>'idempotency_key','')),'');
  v_actor      text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_payload    jsonb  := coalesce(p_input->'payload','{}'::jsonb);
  v_key        text   := nullif(btrim(coalesce(p_input->>'business_key','')),'');
  v_owner      text   := nullif(btrim(coalesce(p_input->>'owner_ref','')),'');
  v_state      text   := nullif(btrim(coalesce(p_input->>'state','')),'');
  v_ctx        text   := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),'production'));
  v_write      jsonb;
  v_result_ref text;
  v_relation   text;
  v_mode       text := 'none';
  v_eid        bigint;
  v_num        numeric; v_den numeric;
begin
  if v_step_run is null or v_idem is null or v_actor is null then
    raise exception 'fn_phase_d_effect_produce: step_run_id, idempotency_key and actor_role_id are all required (pd_effect_input_invalid)'
      using errcode = '22023';
  end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if not found then
    raise exception 'fn_phase_d_effect_produce: no step run % (pd_step_state_invalid)', v_step_run
      using errcode = '23503';
  end if;

  select * into e from public.phase_d_step_effect where step_id = sr.step_id;
  if not found then
    raise exception 'fn_phase_d_effect_produce: step % has no declared effect contract — fail closed. All 257 frozen steps carry one. (pd_effect_undeclared)',
      sr.step_id using errcode = '23503';
  end if;

  -- ---- IDEMPOTENCY IS A READ, NOT A HOPE -------------------------------------------------
  -- A replayed handler must produce NO second effect. The assertion a duplicate-effect test makes
  -- is the ledger ROW COUNT, not the returned payload, so the check is done here and the prior
  -- row is returned verbatim.
  select * into prior from public.phase_d_effect_ledger
   where step_run_id = v_step_run and effect_type = e.expected_effect_type;
  if found then
    return jsonb_build_object(
      'ok', true, 'replay', true, 'effect_id', prior.effect_id,
      'effect_type', prior.effect_type, 'effect_object_id', prior.effect_object_id,
      'result_reference', prior.result_reference, 'provider_mode', prior.provider_mode,
      'note', 'the effect for this step run already exists; no second effect was produced');
  end if;

  -- ---- the seven types -------------------------------------------------------------------
  if e.expected_effect_type = 'KERNEL_ONLY_TRANSITION' then
    -- Nothing is written here beyond the ledger entry. The effect IS the kernel's step run and
    -- run-state move, which is persistent and kernel-verifiable; a domain row invented to make a
    -- count look better would be a fabricated effect.
    v_result_ref := format('public.phase_c_workflow_step_run:step_run_id=%s', v_step_run);
    v_relation   := 'public.phase_c_workflow_step_run';

  elsif e.expected_effect_type = 'CAPABILITY_REQUEST' then
    -- Fail closed in production, and record the refusal as the effect. A capability step whose
    -- effect was a success record would be a mock completing a business step.
    if v_ctx <> 'test' then
      raise exception 'fn_phase_d_effect_produce: step % is capability-dependent and no provider is available in Phase D. The declared effect is a refusal, not a record. (pd_capability_unavailable)',
        sr.step_id using errcode = '23514';
    end if;
    v_result_ref := format('capability_request:%s:step_run=%s',
                           coalesce(nullif(e.effect_evidence,''),'(declared)'), v_step_run);
    v_relation   := 'public.phase_d_effect_ledger';
    v_mode       := 'disabled';

  elsif e.expected_effect_type = 'EXTERNAL_EFFECT_INTENT' then
    -- MOCK, ALWAYS. provider_mode has no 'live' value, so this cannot be turned into a send by
    -- changing a parameter. A recipient and a consent basis are REQUIRED and are not defaulted:
    -- an intent that cannot say who it is for is not an intent.
    if not (v_payload ? 'recipient') or not (v_payload ? 'consent_basis') then
      raise exception 'fn_phase_d_effect_produce: step % declares an external effect and the payload names no %. An intent with no recipient or no consent basis must not be recorded as one. (pd_effect_intent_incomplete)',
        sr.step_id,
        case when not (v_payload ? 'recipient') then 'recipient' else 'consent_basis' end
        using errcode = '22023';
    end if;
    if coalesce(v_payload->>'suppressed','false') = 'true' then
      v_result_ref := format('external_intent:SUPPRESSED:%s', v_payload->>'recipient');
    else
      v_result_ref := format('external_intent:MOCK:%s', v_payload->>'recipient');
    end if;
    v_relation := 'public.phase_d_effect_ledger';
    v_mode     := 'mock';

  elsif e.expected_effect_type = 'MEASUREMENT_RECORD' then
    -- least(100, NULL) returns 100 and put 97.7% attainment in the founder's email on a
    -- zero-revenue day. Nothing is defaulted, and a zero denominator raises.
    if not (v_payload ? 'numerator') or not (v_payload ? 'denominator') then
      raise exception 'fn_phase_d_effect_produce: step % is a measurement step and the payload names no %. An absent input must not score as satisfied. (pd_effect_measurement_incomplete)',
        sr.step_id,
        case when not (v_payload ? 'numerator') then 'numerator' else 'denominator' end
        using errcode = '22023';
    end if;
    v_num := (v_payload->>'numerator')::numeric;
    v_den := (v_payload->>'denominator')::numeric;
    if v_den = 0 then
      raise exception 'fn_phase_d_effect_produce: step % reported a denominator of 0. A ratio over nothing is not a measurement. (pd_effect_zero_denominator)',
        sr.step_id using errcode = '22023';
    end if;
    v_result_ref := format('measurement:%s/%s', v_num, v_den);
    v_relation   := 'public.phase_d_effect_ledger';

  elsif e.expected_effect_type = 'REVIEW_VERDICT' then
    -- The verdict is the caller's. An absent one is a refusal, not an approval: a review handler
    -- that supplied its own verdict would make all 47 review steps a rubber stamp.
    if not (v_payload ? 'verdict') or nullif(btrim(v_payload->>'verdict'),'') is null then
      raise exception 'fn_phase_d_effect_produce: step % is a review step and the payload names no verdict. This routine does not have one to give. (pd_effect_verdict_absent)',
        sr.step_id using errcode = '22023';
    end if;
    if not public.fn_kernel_reviewer_independent(
             sr.accountable_role_id, nullif(btrim(v_payload->>'reviewer_role_id'),'')) then
      raise exception 'fn_phase_d_effect_produce: step % is accountable to % and names % as reviewer; those resolve to one effective identity (BR-002). (pd_rule_refused)',
        sr.step_id, sr.accountable_role_id, coalesce(v_payload->>'reviewer_role_id','(none)')
        using errcode = '23514';
    end if;
    v_write := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','review_record',
      'business_key', coalesce(v_key, format('%s:%s', sr.step_id, v_step_run)),
      'owner_ref', coalesce(v_owner, sr.accountable_role_id),
      'created_by', v_actor,
      'state', coalesce(v_state, v_payload->>'verdict'),
      'payload', v_payload || jsonb_build_object(
        'stage', sr.step_id, 'notes', coalesce(v_payload->>'notes', 'phase_d review verdict'))));
    v_result_ref := v_write->>'result_reference';
    v_relation   := v_write->>'canonical_relation';

  else
    -- DOMAIN_MUTATION and VERSIONED_ARTIFACT: the object's own canonical service.
    if v_key is null or v_owner is null then
      raise exception 'fn_phase_d_effect_produce: step % writes business object % and the call names no %. (pd_effect_owner_or_key_missing)',
        sr.step_id, e.effect_object_id,
        case when v_key is null then 'business_key' else 'owner_ref' end
        using errcode = '22023';
    end if;
    v_write := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id', e.effect_object_id, 'business_key', v_key, 'owner_ref', v_owner,
      'created_by', v_actor, 'state', v_state, 'payload', v_payload,
      'run_id', sr.run_id, 'step_run_id', v_step_run, 'trace_id', p_input->>'trace_id'));
    v_result_ref := v_write->>'result_reference';
    v_relation   := coalesce(v_write->>'canonical_relation', e.effect_relation);
  end if;

  insert into public.phase_d_effect_ledger
    (step_run_id, step_id, workflow_id, run_id, effect_type, effect_object_id, effect_relation,
     effect_operation, result_reference, state_before, state_after, provider_mode,
     payload_digest, idempotency_key, produced_by, trace_id)
  values (v_step_run, sr.step_id, e.workflow_id, sr.run_id, e.expected_effect_type,
          e.effect_object_id, v_relation, e.effect_operation, v_result_ref,
          nullif(p_input->>'state_before',''), v_state, v_mode,
          encode(sha256(convert_to(v_payload::text,'UTF8')),'hex'), v_idem, v_actor,
          nullif(p_input->>'trace_id','')::bigint)
  returning effect_id into v_eid;

  if v_eid is null then
    raise exception 'fn_phase_d_effect_produce: the ledger insert for step run % returned no effect_id. (pd_effect_produced_nothing)',
      v_step_run using errcode = '23502';
  end if;

  return jsonb_build_object(
    'ok', true, 'replay', false, 'effect_id', v_eid,
    'effect_type', e.expected_effect_type, 'effect_object_id', e.effect_object_id,
    'effect_relation', v_relation, 'effect_operation', e.effect_operation,
    'result_reference', v_result_ref, 'provider_mode', v_mode,
    'completion_condition', e.completion_condition,
    'object_write', v_write);
end $fn$;

revoke all on function public.fn_phase_d_effect_produce(jsonb) from public;
grant execute on function public.fn_phase_d_effect_produce(jsonb) to service_role;

-- =====================================================================================
-- 7. THE EXECUTOR PRODUCES THE EFFECT, THEN HANDS TO THE KERNEL
-- =====================================================================================
--
-- ORDER MATTERS AND IS DELIBERATE. The effect is produced BEFORE fn_kernel_step_complete so that
-- the output the kernel stores already carries the effect reference — a step that completed with
-- no traceable effect is exactly what this increment removes. Both sit in one transaction, so a
-- kernel refusal (wrong actor, closure blocked, gate) rolls the effect back with it; and the
-- kernel's own replay path is protected because fn_phase_d_effect_produce reads the ledger first
-- and returns the existing row rather than writing a second.

create or replace function public.fn_phase_d_handler_execute(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  b   public.phase_d_handler_binding%rowtype;
  s   public.phase_b_workflow_step%rowtype;
  sr  public.phase_c_workflow_step_run%rowtype;
  ec  public.phase_d_step_effect%rowtype;
  v_step_run bigint := nullif(p_input->>'step_run_id','')::bigint;
  v_actor    text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_idem     text   := nullif(btrim(coalesce(p_input->>'idempotency_key','')),'');
  v_inputs   jsonb  := coalesce(p_input->'inputs','{}'::jsonb);
  v_ctx      text   := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),'production'));
  v_ok       boolean; v_reason text; v_missing text[];
  v_rule     record; v_rule_ok boolean; v_rule_type text; v_rule_reason text;
  v_applies  boolean; v_why text; v_enforced boolean; v_refusal text; v_state text;
  v_refused  jsonb := '[]'::jsonb;
  v_skipped  jsonb := '[]'::jsonb;
  v_gate     record; v_gstate text; v_gpassed boolean; v_gtype text;
  v_greason  text; v_grefusal text; v_gapplies boolean; v_gwhy text;
  v_gates    jsonb := '[]'::jsonb;
  v_gblocked jsonb := '[]'::jsonb;
  v_evaluated jsonb := '[]'::jsonb;
  v_output   jsonb;
  v_assert   jsonb;
  v_result   jsonb;
  v_effect   jsonb;
begin
  -- ---- 0. the call itself ------------------------------------------------------------------
  if v_step_run is null or v_actor is null or v_idem is null then
    raise exception 'fn_phase_d_handler_execute: step_run_id, actor_role_id and idempotency_key are all required (got %, %, %) (pd_input_schema_invalid)',
      coalesce(v_step_run::text,'(null)'), coalesce(v_actor,'(null)'), coalesce(v_idem,'(null)')
      using errcode = '22023';
  end if;
  if v_ctx not in ('production','test') then
    raise exception 'fn_phase_d_handler_execute: execution_context must be production or test, got %',
      v_ctx using errcode = '22023';
  end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if not found then
    raise exception 'fn_phase_d_handler_execute: no step run % (pd_step_state_invalid)', v_step_run
      using errcode = '23503';
  end if;

  select * into b from public.phase_d_handler_binding where step_id = sr.step_id;
  if not found then
    raise exception 'fn_phase_d_handler_execute: step % has no Phase D handler binding — fail closed. Every one of the 257 frozen steps must carry exactly one. (pd_input_schema_invalid)',
      sr.step_id using errcode = '23503';
  end if;
  select * into s from public.phase_b_workflow_step where step_id = sr.step_id;

  select * into ec from public.phase_d_step_effect where step_id = sr.step_id;
  if not found then
    raise exception 'fn_phase_d_handler_execute: step % has no declared effect contract. A handler with no declared effect is the schema-only handler this phase exists to remove. (pd_effect_undeclared)',
      sr.step_id using errcode = '23503';
  end if;

  -- ---- 1. TYPED INPUT ----------------------------------------------------------------------
  select valid, reason, missing into v_ok, v_reason, v_missing
    from public.fn_phase_d_schema_validate(b.input_schema_id, v_inputs);
  if not v_ok then
    raise exception 'fn_phase_d_handler_execute: step % input rejected: % (pd_input_schema_invalid)',
      sr.step_id, v_reason using errcode = '22023';
  end if;

  -- ---- 2. RULES IN SCOPE -------------------------------------------------------------------
  -- SCOPE IS NOT APPLICABILITY. The frozen registry scopes rules by WORKFLOW, so BR-002 is in
  -- scope for all 257 steps while only 28 of them name an independent reviewer. Asking
  -- fn_kernel_reviewer_independent about a NULL reviewer returns false, which refused an intake
  -- step for a creator/reviewer collision that could not exist. fn_phase_d_rule_applies decides
  -- both, and records the reason either way.
  --
  -- Refusals are collected rather than short-circuited: a caller told only the first thing wrong
  -- fixes one thing and comes back.
  for v_rule in select unnest(b.rule_ids) rid loop
    select applies, why into v_applies, v_why
      from public.fn_phase_d_rule_applies(v_rule.rid, sr.step_id);
    if not coalesce(v_applies,false) then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'rule_id', v_rule.rid, 'applies', false, 'why', v_why));
      continue;
    end if;

    select state, ok, rule_type, enforced, reason, refusal_code
      into v_state, v_rule_ok, v_rule_type, v_enforced, v_rule_reason, v_refusal
      from public.fn_phase_d_rule_check(v_rule.rid,
        jsonb_build_object(
          'accountable_role_id', sr.accountable_role_id,
          'reviewer_role_id',    nullif(b.independent_reviewer_role_id,''),
          'actor_role_id',       v_actor,
          'step_id',             sr.step_id,
          'workflow_id',         b.workflow_id,
          'run_id',              sr.run_id,
          'founder_gate',        b.founder_gate,
          'execution_context',   v_ctx)
        || coalesce(p_input->'context','{}'::jsonb));

    v_evaluated := v_evaluated || jsonb_build_array(jsonb_build_object(
      'rule_id', v_rule.rid, 'state', v_state, 'rule_type', v_rule_type, 'ok', v_rule_ok,
      'enforced', v_enforced, 'reason', v_rule_reason));

    if v_rule_type = 'hard' and v_state in ('ENFORCED_FAIL','NOT_IMPLEMENTED') then
      v_refused := v_refused || jsonb_build_array(jsonb_build_object(
        'rule_id', v_rule.rid, 'state', v_state, 'rule_type', v_rule_type,
        'refusal_code', v_refusal, 'reason', v_rule_reason));
    end if;
  end loop;
  if jsonb_array_length(v_refused) > 0 then
    raise exception 'fn_phase_d_handler_execute: step % refused by % hard business rule(s): % (pd_rule_refused)',
      sr.step_id, jsonb_array_length(v_refused), v_refused::text using errcode = '23514';
  end if;

  -- ---- 2b. GATES IN SCOPE, EACH AGAINST ITS OWN DECLARED EVIDENCE --------------------------
  for v_gate in select unnest(b.gate_ids) gid loop
    select ga.applies, ga.why into v_gapplies, v_gwhy
      from public.fn_phase_d_gate_applies(v_gate.gid, sr.step_id) ga;
    if not coalesce(v_gapplies,false) then
      v_gates := v_gates || jsonb_build_array(jsonb_build_object(
        'gate_id', v_gate.gid, 'state', 'NOT_APPLICABLE', 'why', v_gwhy));
      continue;
    end if;
    select ge.state, ge.passed, ge.gate_type, ge.reason, ge.refusal_code
      into v_gstate, v_gpassed, v_gtype, v_greason, v_grefusal
      from public.fn_phase_d_gate_evaluate(v_gate.gid,
        jsonb_build_object('step_id', sr.step_id, 'run_id', sr.run_id,
                           'actor_role_id', v_actor,
                           'reviewer_role_id', nullif(b.independent_reviewer_role_id,''))
        || coalesce(p_input->'gate_evidence','{}'::jsonb)) ge;

    v_gates := v_gates || jsonb_build_array(jsonb_build_object(
      'gate_id', v_gate.gid, 'state', v_gstate, 'gate_type', v_gtype,
      'passed', v_gpassed, 'reason', v_greason));

    if v_gtype = 'hard' and v_gstate in ('BLOCKED','NOT_IMPLEMENTED') then
      v_gblocked := v_gblocked || jsonb_build_array(jsonb_build_object(
        'gate_id', v_gate.gid, 'state', v_gstate,
        'refusal_code', v_grefusal, 'reason', v_greason));
    end if;
  end loop;
  if jsonb_array_length(v_gblocked) > 0 then
    raise exception 'fn_phase_d_handler_execute: step % refused by % hard gate(s): % (pd_gate_refused)',
      sr.step_id, jsonb_array_length(v_gblocked), v_gblocked::text using errcode = '23514';
  end if;

  -- ---- 3. CAPABILITY BOUNDARY, FAIL CLOSED -------------------------------------------------
  if b.capability_dependency <> 'NONE' and v_ctx <> 'test' then
    raise exception 'fn_phase_d_handler_execute: step % depends on capability % (matched on the frozen required_action at: %) and no capability provider is available in Phase D. Paid inference is held until Phase E. Refusing rather than completing a business step from a fixture. (pd_capability_unavailable)',
      sr.step_id, b.capability_dependency, coalesce(nullif(b.capability_evidence,''),'(none)')
      using errcode = '23514';
  end if;

  -- ---- 4. PROVIDER BOUNDARY, FAIL CLOSED ---------------------------------------------------
  if b.provider_dependency <> 'NONE' and v_ctx <> 'test' then
    raise exception 'fn_phase_d_handler_execute: step % depends on external provider % which is disabled for the whole of Phase D. (pd_provider_disabled)',
      sr.step_id, b.provider_dependency using errcode = '23514';
  end if;

  -- ---- 5. THE FAMILY HANDLER ---------------------------------------------------------------
  v_assert := (
    select coalesce(jsonb_agg(jsonb_build_object(
             'criterion', btrim(c), 'satisfied_by',
             'named inputs [' || array_to_string(
               (select array_agg(k order by k) from jsonb_object_keys(v_inputs) k), ', ') || ']')
             order by ord), '[]'::jsonb)
      from unnest(string_to_array(coalesce(s.acceptance_criteria,''), ';')) with ordinality u(c, ord)
     where btrim(c) <> '');

  v_output := jsonb_build_object(
    'status', 'completed',
    'output', format('%s — %s', s.step_name, coalesce(s.required_output,'output produced')),
    'acceptance_assertions', case when jsonb_array_length(v_assert) = 0
                                  then jsonb_build_array(jsonb_build_object(
                                         'criterion', coalesce(s.acceptance_criteria,'(none declared)'),
                                         'satisfied_by','named inputs'))
                                  else v_assert end,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
       'step_id', sr.step_id, 'step_run_id', v_step_run, 'run_id', sr.run_id,
       'handler_id', b.handler_id, 'handler_version', b.handler_version,
       'input_schema_id', b.input_schema_id, 'output_schema_id', b.output_schema_id,
       'inputs_named', v_inputs, 'execution_context', v_ctx)))
    || case b.handler_class
         when 'INTAKE_HANDLER' then jsonb_build_object(
           'source_ref', coalesce(p_input->>'source_ref', 'step_run:' || v_step_run),
           'captured_verbatim', v_inputs)
         when 'ANALYSIS_HANDLER' then jsonb_build_object(
           'method', 'deterministic reconciliation of the named inputs against the frozen step contract',
           'inputs_used', v_inputs,
           'findings', jsonb_build_array(coalesce(s.required_action,'')),
           'assumptions', jsonb_build_array(
             'only the inputs named in this call were used; no external source was consulted'))
         when 'EXECUTION_HANDLER' then jsonb_build_object(
           'state_change', coalesce(s.required_output,''),
           'target_object', coalesce(ec.effect_object_id,
             (select primary_object from public.phase_b_workflow w
               where w.workflow_id = b.workflow_id), b.workflow_id),
           'authorization_ref', format('accountable owner %s on step %s',
                                       sr.accountable_role_id, sr.step_id))
         when 'REVIEW_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'verdict', nullif(btrim(coalesce(p_input->>'verdict','')),''),
           'reviewer_role_id', nullif(btrim(coalesce(p_input->>'reviewer_role_id','')),'')))
         when 'DECISION_HANDLER' then jsonb_build_object(
           'decision', coalesce(s.required_output,''),
           'rationale', coalesce(s.acceptance_criteria,''),
           'authority_ref', format('founder_gate=%s; accountable owner %s',
                                   b.founder_gate, sr.accountable_role_id))
         when 'HANDOFF_HANDLER' then jsonb_build_object(
           'packet', v_inputs,
           'receiving_role_id', coalesce((select h.receiving_role_id from public.phase_b_handoff h
                                           where h.from_step_id = sr.step_id limit 1),
                                         sr.accountable_role_id),
           'acceptance_criteria', coalesce(s.acceptance_criteria,''))
         when 'MEASUREMENT_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'metric', coalesce(s.required_output,''),
           'denominator', p_input->'denominator',
           'numerator', p_input->'numerator',
           'formula', nullif(btrim(coalesce(p_input->>'formula','')),''),
           'window', nullif(btrim(coalesce(p_input->>'window','')),'')))
         when 'CLOSURE_HANDLER' then jsonb_build_object(
           'blockers_resolved', jsonb_build_array(
             'the frozen fn_kernel_step_complete measures the four mandatory closure blocker '
             || 'classes itself and raises k3_closure_blocked if any is open'),
           'closure_evidence', coalesce(s.closure_criteria,''))
         else '{}'::jsonb end;

  -- ---- 5a. TWO REFUSALS THE SCHEMA ALONE CANNOT MAKE ---------------------------------------
  if b.handler_class = 'REVIEW_HANDLER'
     and not public.fn_kernel_reviewer_independent(
               sr.accountable_role_id, v_output->>'reviewer_role_id') then
    raise exception 'fn_phase_d_handler_execute: step % is accountable to % and the review names % as reviewer; those resolve to the same effective identity. A creator cannot be the sole independent reviewer of the same output (BR-002). (pd_rule_refused)',
      sr.step_id, sr.accountable_role_id, coalesce(v_output->>'reviewer_role_id','(none)')
      using errcode = '23514';
  end if;

  if b.handler_class = 'MEASUREMENT_HANDLER'
     and jsonb_typeof(v_output->'denominator') = 'number'
     and (v_output->>'denominator')::numeric = 0 then
    raise exception 'fn_phase_d_handler_execute: step % reported a denominator of 0. A ratio over nothing is not a measurement, and reporting it as one is how an unmeasured goal scores as perfect. (pd_output_schema_invalid)',
      sr.step_id using errcode = '22023';
  end if;

  -- ---- 6. TYPED OUTPUT ---------------------------------------------------------------------
  select valid, reason, missing into v_ok, v_reason, v_missing
    from public.fn_phase_d_schema_validate(b.output_schema_id, v_output);
  if not v_ok then
    raise exception 'fn_phase_d_handler_execute: step % produced an output its own contract rejects: % (pd_output_schema_invalid)',
      sr.step_id, v_reason using errcode = '22023';
  end if;

  -- ---- 6b. THE BUSINESS EFFECT -------------------------------------------------------------
  -- D7. Until this line existed, 257 of 257 handlers produced a typed output the kernel accepted
  -- and no business effect whatsoever, and fn_phase_d_handler_state() said so in red.
  --
  -- The effect payload comes from the CALLER, merged over the step's own facts. Nothing about the
  -- business record is invented here: a step that needs a business_key and an owner_ref and is
  -- given neither refuses, because a record written under an owner this routine chose would be
  -- the auto-vivified customer account defect in a new place.
  v_effect := public.fn_phase_d_effect_produce(
    jsonb_build_object(
      'step_run_id', v_step_run, 'idempotency_key', v_idem, 'actor_role_id', v_actor,
      'execution_context', v_ctx)
    || jsonb_strip_nulls(jsonb_build_object(
      'business_key', p_input->>'business_key',
      'owner_ref',    p_input->>'owner_ref',
      'state',        p_input->>'effect_state',
      'state_before', p_input->>'state_before',
      'trace_id',     p_input->>'trace_id'))
    || jsonb_build_object('payload', coalesce(p_input->'effect_payload', v_inputs)));

  v_output := v_output || jsonb_build_object('business_effect', jsonb_build_object(
    'effect_type', v_effect->>'effect_type',
    'effect_object_id', v_effect->'effect_object_id',
    'result_reference', v_effect->>'result_reference',
    'effect_id', v_effect->'effect_id',
    'provider_mode', v_effect->>'provider_mode',
    'replay', v_effect->'replay'));

  -- ---- 7. HAND TO THE FROZEN KERNEL --------------------------------------------------------
  -- Everything from here — idempotency, locks, authority, gates, the task state machine,
  -- progression, handoffs, run state and events — belongs to fn_kernel_step_complete and is not
  -- reimplemented. A handler that wrote any of it would be the parallel engine the spec forbids.
  v_result := public.fn_kernel_step_complete(jsonb_build_object(
    'step_run_id', v_step_run, 'actor_role_id', v_actor, 'outcome', 'pass',
    'idempotency_key', v_idem, 'inputs', v_inputs, 'output', v_output,
    'evidence_ref', format('phase_d:%s:%s:effect=%s',
                           b.handler_id, v_step_run, coalesce(v_effect->>'result_reference','none')),
    'correlation_id', p_input->>'correlation_id',
    'causation_id', coalesce(p_input->>'causation_id', 'phase_d_handler:' || b.handler_id)));

  return v_result || jsonb_build_object(
    'phase_d', jsonb_build_object(
      'handler_id', b.handler_id, 'handler_version', b.handler_version,
      'handler_class', b.handler_class, 'execution_context', v_ctx,
      'input_schema_id', b.input_schema_id, 'output_schema_id', b.output_schema_id,
      'rules_in_scope', cardinality(b.rule_ids),
      'rules_evaluated', v_evaluated, 'rules_not_applicable', v_skipped,
      'rules_enforced_count', (select count(*) from jsonb_array_elements(v_evaluated) e2
                                where (e2->>'enforced')::boolean),
      'rules_outstanding_count', (select count(*) from jsonb_array_elements(v_evaluated) e2
                                   where not (e2->>'enforced')::boolean),
      'gates_in_scope', cardinality(b.gate_ids), 'gates_evaluated', v_gates,
      'capability_dependency', b.capability_dependency,
      'provider_dependency', b.provider_dependency,
      'external_effect_policy', b.external_effect_policy,
      'expected_effect_type', ec.expected_effect_type,
      'implementation_depth', ec.implementation_depth,
      'business_effect', v_effect));
end $fn$;

-- =====================================================================================
-- 8. THE BOARDS LEARN THE NEW SUBJECT
-- =====================================================================================

-- business_write_wired is recomputed from the LIVE executor body and the step's own declared
-- effect. It is a measurement of two things that must both hold: the executor really calls the
-- effect service, and this step's declared effect resolves to a service that exists.
update public.phase_d_handler_binding b
   set business_write_wired = (
         exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.prokind = 'f'
                    and p.proname = 'fn_phase_d_handler_execute'
                    and pg_get_functiondef(p.oid) like '%fn_phase_d_effect_produce%')
         and exists (select 1 from public.phase_d_step_effect e where e.step_id = b.step_id));

create or replace function public.fn_phase_d_effect_state()
returns table(check_name text, expected text, actual text, ok boolean)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare n int; m int; v text;
begin
  select count(*) into m from public.phase_b_workflow_step;

  select count(*) into n from public.phase_d_step_effect;
  check_name := 'every_frozen_step_declares_an_effect';
  expected := m::text; actual := n::text; ok := (n = m); return next;

  select count(*) into n from public.phase_d_step_effect where expected_effect_type is null;
  check_name := 'steps_with_no_expected_effect_type';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  -- A domain effect with no object is the schema-only handler wearing a new column.
  select count(*) into n from public.phase_d_step_effect
   where expected_effect_type not in ('KERNEL_ONLY_TRANSITION','CAPABILITY_REQUEST')
     and effect_object_id is null;
  check_name := 'domain_effects_with_no_object';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  -- Every named effect service must resolve. A contract naming a routine nobody deployed is prose.
  select count(*) into n from public.phase_d_step_effect e
   where not exists (
     select 1 from pg_proc p join pg_namespace nn on nn.oid = p.pronamespace
      where nn.nspname || '.' || p.proname || '(' ||
            pg_get_function_identity_arguments(p.oid) || ')' = e.effect_service);
  check_name := 'effect_services_that_do_not_resolve';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  -- Every object a step declares must be bound, and must have a writer it can actually reach:
  -- either the Phase D store or a validated write map. This is the check that would have caught
  -- shipping an effect contract pointing at an object with no writer.
  select count(*) into n from public.phase_d_step_effect e
    join public.phase_d_business_object_binding ob on ob.object_id = e.effect_object_id
   where e.expected_effect_type in ('DOMAIN_MUTATION','VERSIONED_ARTIFACT')
     and ob.relation_kind = 'EXISTING_TABLE'
     and not exists (select 1 from public.phase_d_object_write_map w where w.object_id = ob.object_id);
  check_name := 'existing_table_effects_with_no_write_map';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  -- Every declared write map must still match the catalogue. An ALTER TABLE that dropped a mapped
  -- column would otherwise surface as a runtime failure on the step, not as a red board.
  select count(*) into n
    from public.phase_d_object_write_map w
    cross join lateral jsonb_object_keys(w.column_map) k
   where not exists (select 1 from information_schema.columns c
                      where c.table_schema = split_part(w.target_relation,'.',1)
                        and c.table_name   = split_part(w.target_relation,'.',2)
                        and c.column_name  = k);
  check_name := 'write_map_columns_absent_from_the_target';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  -- The kernel's own tables must have no Phase D write map. Two creators for one object is the
  -- defect that deadlocked 16 of 30 workflows.
  select count(*) into n from public.phase_d_object_write_map w
    join public.phase_d_business_object_binding ob on ob.object_id = w.object_id
   where ob.governing_workflow_id = 'ALL' and ob.canonical_relation like 'public.phase_c_%';
  check_name := 'kernel_owned_objects_with_a_phase_d_writer';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  -- No ledger row may claim a live provider send. provider_mode has no 'live' value, so a non-zero
  -- here would mean the constraint was dropped.
  select count(*) into n from public.phase_d_effect_ledger
   where provider_mode not in ('none','mock','disabled');
  check_name := 'ledger_rows_claiming_a_live_external_effect';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  -- Duplicate effects for one step run. Guaranteed by a UNIQUE constraint; counted anyway,
  -- because a check that trusts a constraint it never reads is a check nobody ran.
  select count(*) into n from (
    select step_run_id, effect_type from public.phase_d_effect_ledger
     group by 1,2 having count(*) > 1) d;
  check_name := 'duplicate_effects_for_one_step_run';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  -- DISCLOSURE, NOT A PASS. This counts steps whose effect has actually been PRODUCED at least
  -- once, which is a different question from whether the path exists. It starts far from 257 and
  -- the number must GROW, so it is reported as the gap and ratcheted.
  select count(distinct step_id) into n from public.phase_d_effect_ledger;
  check_name := 'steps_with_no_effect_ever_produced';
  expected := '0'; actual := (m - n)::text; ok := (n = m); return next;

  select string_agg(x.t || '=' || x.c, ' ' order by x.t) into v
    from (select expected_effect_type t, count(*)::text c
            from public.phase_d_step_effect group by 1) x;
  check_name := 'effect_type_distribution';
  expected := 'informational'; actual := coalesce(v,'(none)'); ok := true; return next;

  select string_agg(x.t || '=' || x.c, ' ' order by x.t) into v
    from (select implementation_depth t, count(*)::text c
            from public.phase_d_step_effect group by 1) x;
  check_name := 'implementation_depth_distribution';
  expected := 'informational'; actual := coalesce(v,'(none)'); ok := true; return next;
end $fn$;

-- =====================================================================================
-- 9. TWO PRE-EXISTING GRANTS THAT SHOULD NEVER HAVE BEEN PUBLIC
-- =====================================================================================
-- Neither is SECURITY DEFINER so neither escalates privilege, and both read the frozen registries:
-- an unauthenticated caller could ask this estate which business rules it enforces and which gates
-- apply to which step. `revoke ... from anon` is a silent no-op when the grant is held through
-- PUBLIC, so PUBLIC is the target and the intended roles are re-granted explicitly.
revoke all on function public.fn_phase_d_rule_check(text, jsonb) from public;
revoke all on function public.fn_phase_d_gate_applies(text, text) from public;
grant execute on function public.fn_phase_d_rule_check(text, jsonb) to service_role, authenticated;
grant execute on function public.fn_phase_d_gate_applies(text, text) to service_role, authenticated;

commit;
