-- =================================================================================================
-- Phase D — D17. The fixture had a second door, and it was HTTP.
--
-- MEASURED FIRST, ON PRODUCTION, IN AN ABORTED TRANSACTION:
--
--     net.http_request_queue  before=0  after=2  delta=2
--       POST https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/dispatch_inquiry
--       POST https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/enrich_capability
--
-- Every single `fn_phase_d_fixture_scenario` build enqueues two outbound HTTP POSTs to production
-- edge functions, and the factory returns `'external_effects', 0` while it happens.
--
-- The factory's own assertion counts `public.notifications` before and after every stage and aborts
-- the whole scenario on any delta. That assertion is real and it works. It is also the wrong
-- subject: it is named for external effects and it measures one table. `net.http_post` is a second
-- door, it was never counted, and one of the two requests is `dispatch_inquiry` — the RFQ dispatch
-- that offers an inquiry to matched suppliers. That is precisely the business-producing automation
-- this phase is required to hold.
--
-- NOTHING WAS EVER SENT, AND THAT IS A MEASUREMENT, NOT A HOPE. pg_net's worker reads COMMITTED
-- rows; every Phase D drive and every scenario build ends in `raise exception`, so the queue rows
-- die with the transaction that made them. The probe above read `before=0` on a database that has
-- had dozens of scenario builds run through it across D9 and this session — an queue that had ever
-- leaked would not read zero. What was wrong was the guard, not the outcome.
--
-- WHY THAT STILL MATTERS ENOUGH TO FIX: the abort is the only thing standing between this factory
-- and a live RFQ dispatch. `mgmtFixture` is a committing door and it exists. A guard that reports
-- "external effects: 0" while two POSTs sit in the queue converts that hazard into confidence,
-- which is the one thing this estate has decided a check must never do.
--
-- THE FIX IS AT THE ROOT, NOT AT THE FIXTURE. Every Phase D write — factory stage, driver effect,
-- handler — goes through `fn_phase_d_object_write`. The count and the refusal live there, so a
-- workflow step that writes an approved supplier is covered by the same guard as a fixture stage.
-- Putting it in the factory would have left the driver writing through the open door.
--
-- THE SCAN FOUND FOUR DOORS, NOT THE TWO THAT FIRED. Writing this file by starting from the two
-- observed POSTs would have registered half the surface and called it complete. The denominator is
-- the live trigger scan, not the probe:
--
--   enrich_capability_on_approve  leads       -> enrich_capability   FIRED, suppressed
--   autodispatch_inquiry          inquiries   -> dispatch_inquiry    FIRED, suppressed
--   trg_sign_customer             customers   -> compliance_archive  silent, unreachable
--   trg_sign_supplier             leads       -> compliance_archive  silent, unreachable
--
-- SUPPRESSION USES EACH TRIGGER'S OWN GUARD. No trigger is disabled, altered or dropped.
--
--   trg_enrich_capability     fires when  approval_status='approved' AND capability_enriched_at IS NULL
--   trg_autodispatch_inquiry  fires when  rfq_ready IS TRUE AND routing->>'dispatched_at' IS NULL
--
-- Both carry an "already done" marker of the product's own design. In Phase D test context the
-- canonical writer sets that marker on the rows it creates, so each trigger declines by its own
-- condition. A demo row that will be rolled back is not waiting to be enriched and is not waiting
-- to be dispatched, so the marker is true rather than convenient. Neither column is read by any
-- Phase D rule, gate contract, or by fn_rfq_score / fn_rfq_required_check — measured, 0 each.
--
-- THE TWO SILENT DOORS ARE RECORDED, NOT IGNORED. Both are AFTER UPDATE ... WHEN triggers keyed on
-- a verification flag no Phase D write map declares, so no Phase D write can move them. That is a
-- CLAIM, so the board checks it two ways: the named column must appear in the trigger's own
-- definition, and it must not appear in the relation's write map. The day someone maps
-- `owner_email_verified` the board goes red — which matters, because
-- fn_leads_derive_owner_email_verified can move that column from an ordinary email write.
--
-- THE DENOMINATOR IS DERIVED. `phase_d_outbound_door` is populated by scanning pg_trigger for
-- trigger functions containing net.http_ on the 25 relations Phase D binds as EXISTING_TABLE. The
-- disposition of each door is the engineering decision and is recorded with the trigger's own guard
-- text as evidence. A deploy-time control refuses this file if the scan and the registry do not
-- cover each other exactly, so a NEW outbound trigger appearing on a Phase D relation turns the
-- board red instead of quietly re-opening the door.
--
-- The guard is proved to FIRE by removing a registry row inside an aborted transaction and
-- confirming the write refuses with the URL named. A guard that has only ever been observed silent
-- cannot tell a live check from a dead one.
-- =================================================================================================

begin;

-- -------------------------------------------------------------------------------------------------
-- 1. The registry of outbound doors reachable from a Phase D canonical write.
--
-- THE SCAN FOUND FOUR, NOT TWO. Two fire on a Phase D write and are suppressed through their own
-- already-done guard. The other two are AFTER UPDATE triggers with a WHEN clause that turns on a
-- column no Phase D write map declares, so no Phase D write can reach them:
--
--   trg_sign_customer   WHEN new.email_verified IS TRUE AND old.email_verified IS DISTINCT FROM new...
--   trg_sign_supplier   WHEN new.owner_email_verified IS TRUE AND old... IS DISTINCT FROM new...
--
-- "Not reachable" is a claim, so it is recorded as a CHECKABLE one rather than as a comment:
-- unreachable_because_column names the column, the board proves the trigger definition mentions it
-- AND that the relation's write map does not declare it, and the day a write map gains that column
-- the check goes red. The canonical writer's own count is the backstop underneath all of it — if a
-- door nobody expected to fire fires, the write refuses and names the URL.
-- -------------------------------------------------------------------------------------------------
create table if not exists public.phase_d_outbound_door (
  relation                   text not null,
  trigger_name               text not null,
  function_name              text not null,
  endpoint                   text not null,
  disposition                text not null,
  guard_column               text,
  suppression_sql            text,
  unreachable_because_column text,
  guard_condition            text not null,
  note                       text not null,
  registered_at              timestamptz not null default now(),
  constraint phase_d_outbound_door_pkey primary key (relation, trigger_name),
  constraint phase_d_outbound_door_disposition_check
    check (disposition in ('SUPPRESSED_BY_ITS_OWN_GUARD','NOT_REACHED_BY_ANY_PHASE_D_WRITE_MAP')),
  -- A suppressed door needs a column and an expression; an unreachable one needs the column whose
  -- absence is the reason. Neither may be recorded without its evidence.
  constraint phase_d_outbound_door_evidence_check check (
    (disposition = 'SUPPRESSED_BY_ITS_OWN_GUARD'
       and guard_column is not null and suppression_sql is not null
       and unreachable_because_column is null)
    or
    (disposition = 'NOT_REACHED_BY_ANY_PHASE_D_WRITE_MAP'
       and guard_column is null and suppression_sql is null
       and unreachable_because_column is not null))
);

comment on table public.phase_d_outbound_door is
  'One row per trigger on a Phase D canonical EXISTING_TABLE relation whose function calls net.http_. '
  'SUPPRESSED_BY_ITS_OWN_GUARD rows name the product''s own already-done marker, which '
  'fn_phase_d_object_write sets in Phase D test context so the trigger declines by its own condition. '
  'NOT_REACHED rows name the column whose absence from the write map makes the door unreachable. '
  'No trigger is disabled, altered or dropped by any of this.';

delete from public.phase_d_outbound_door;

-- The scan is the denominator. The four rows below carry the disposition for each door found; the
-- control at the end of this file refuses the file if the scan finds a door this list does not
-- cover, or if this list names a door the scan does not find.
with scanned as (
  select 'public.' || c.relname                          as relation,
         tg.tgname                                       as trigger_name,
         p.proname                                       as function_name,
         coalesce((regexp_match(p.prosrc, 'functions/v1/([a-z_]+)'))[1], '(unresolved)') as endpoint
    from pg_trigger tg
    join pg_proc  p on p.oid = tg.tgfoid
    join pg_class c on c.oid = tg.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where not tg.tgisinternal
     and n.nspname = 'public'
     and p.prosrc ~* 'net\.http_(post|get)'
     and ('public.' || c.relname) in (
           select distinct b.canonical_relation
             from public.phase_d_business_object_binding b
            where b.relation_kind = 'EXISTING_TABLE')
),
decided as (
  select * from (values
    ('enrich_capability_on_approve',
     'SUPPRESSED_BY_ITS_OWN_GUARD',
     'capability_enriched_at',
     'to_jsonb(now())',
     null::text,
     'AFTER INSERT OR UPDATE OF approval_status; fires when approval_status=''approved'' and capability_enriched_at is null',
     'MEASURED FIRING: this door produced one of the two POSTs. A rolled-back demo supplier is not waiting to be enriched, so setting the product''s own enrichment timestamp is true rather than convenient. The trigger is untouched and still fires for every real supplier.'),

    ('autodispatch_inquiry',
     'SUPPRESSED_BY_ITS_OWN_GUARD',
     'routing',
     'jsonb_build_object(''dispatched_at'', now(), ''dispatched_by'', ''phase_d_test_context'', ''phase_d_outbound_suppressed'', true)',
     null::text,
     'AFTER INSERT OR UPDATE OF rfq_ready; fires when rfq_ready is true and routing->>''dispatched_at'' is null',
     'MEASURED FIRING: this door produced the POST to dispatch_inquiry — the RFQ offer to matched suppliers, which is the business-producing automation this phase holds. A rolled-back demo inquiry has no suppliers to reach.'),

    ('trg_sign_customer',
     'NOT_REACHED_BY_ANY_PHASE_D_WRITE_MAP',
     null::text,
     null::text,
     'email_verified',
     'AFTER UPDATE ... WHEN (new.email_verified is true and old.email_verified is distinct from new.email_verified and new.signed_terms_url is null)',
     'MEASURED SILENT: this door did not fire in the probe. It needs a TRANSITION of customers.email_verified and the customer_account write map does not declare that column, so no Phase D write can move it. Recorded rather than ignored, and the writer''s own count refuses if it ever fires.'),

    ('trg_sign_supplier',
     'NOT_REACHED_BY_ANY_PHASE_D_WRITE_MAP',
     null::text,
     null::text,
     'owner_email_verified',
     'AFTER UPDATE ... WHEN (new.owner_email_verified is true and old.owner_email_verified is distinct from new.owner_email_verified and new.signed_terms_url is null and new.claimed_by is not null)',
     'MEASURED SILENT: this door did not fire in the probe. It needs a TRANSITION of leads.owner_email_verified, which the supplier_account write map does not declare. Note that fn_leads_derive_owner_email_verified can move that column from an email write, which is exactly why this is registered with a checkable reason and backed by the writer''s count rather than assumed shut.')
  ) as d(trigger_name, disposition, guard_column, suppression_sql, unreachable_because_column, guard_condition, note)
)
insert into public.phase_d_outbound_door
  (relation, trigger_name, function_name, endpoint, disposition, guard_column, suppression_sql,
   unreachable_because_column, guard_condition, note)
select s.relation, s.trigger_name, s.function_name, s.endpoint,
       d.disposition, d.guard_column, d.suppression_sql,
       d.unreachable_because_column, d.guard_condition, d.note
  from scanned s
  join decided d on d.trigger_name = s.trigger_name;

revoke all on public.phase_d_outbound_door from anon, authenticated;

-- -------------------------------------------------------------------------------------------------
-- 2. The guard columns become part of the declared write map.
--
-- The writer may only touch a column the map declares. These are real columns of the two objects,
-- so they are declared rather than injected behind the map's back — a suppression the map does not
-- know about would be the canonical service writing a column nobody registered.
-- -------------------------------------------------------------------------------------------------
update public.phase_d_object_write_map
   set column_map = column_map || jsonb_build_object('capability_enriched_at', 'capability_enriched_at')
 where object_id = 'supplier_account';

update public.phase_d_object_write_map
   set column_map = column_map || jsonb_build_object('routing', 'routing')
 where object_id = 'inquiry';

-- -------------------------------------------------------------------------------------------------
-- 3. The canonical writer counts the outbound queue and refuses on any delta in test context.
-- -------------------------------------------------------------------------------------------------
create or replace function public.fn_phase_d_object_write(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
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
  v_existing   text;
  v_result_ref text;
  v_sql        text;
  v_supplied   jsonb;
  -- D17: the outbound door.
  v_testctx    boolean := coalesce(nullif(btrim(current_setting('app.phase_d_test_context', true)),''),'') = 'on';
  v_door       record;
  v_door_val   jsonb;
  v_net_max    bigint;
  v_net_new    bigint;
  v_net_urls   text;
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

    -- D17. OUTBOUND SUPPRESSION, IN TEST CONTEXT ONLY, THROUGH EACH TRIGGER'S OWN GUARD.
    -- In production this loop does not run: a real Phase D handler dispatching a real inquiry is
    -- the intended behaviour and must not be suppressed. Under the Phase D hold the writer sets
    -- the product's own already-done marker, and a caller that supplied one keeps it.
    if v_testctx then
      for v_door in
        select d.guard_column, d.suppression_sql
          from public.phase_d_outbound_door d
         where d.relation = wm.target_relation
           and d.disposition = 'SUPPRESSED_BY_ITS_OWN_GUARD'
      loop
        if not (v_supplied ? v_door.guard_column) then
          execute format('select %s', v_door.suppression_sql) into v_door_val;
          v_supplied := v_supplied || jsonb_build_object(v_door.guard_column, v_door_val);
        end if;
      end loop;
    end if;

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

    -- D17. The high-water mark, taken immediately before the write. Counting rows with a HIGHER id
    -- afterwards rather than differencing two counts is deliberate: pg_net's worker DELETES rows it
    -- has processed, so a plain count delta can be masked to zero by a concurrent drain and report
    -- silence over two real POSTs.
    if v_testctx then
      select coalesce(max(id),0) into v_net_max from net.http_request_queue;
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

    -- D17. THE ASSERTION. A Phase D test write may not leave an outbound request behind it.
    if v_testctx then
      select count(*), string_agg(distinct q.method || ' ' || q.url, ', ')
        into v_net_new, v_net_urls
        from net.http_request_queue q
       where q.id > v_net_max;
      if coalesce(v_net_new,0) > 0 then
        raise exception 'fn_phase_d_object_write: writing % to % enqueued % outbound HTTP request(s): %. A Phase D test write may not leave an outbound request behind it. (pd_object_outbound_request_produced)',
          v_object, wm.target_relation, v_net_new, v_net_urls using errcode = '23514',
          hint = 'A trigger on this relation calls net.http_post. Register it in public.phase_d_outbound_door with the product''s own already-done guard column, or explain why the request is legitimate under the hold.';
      end if;
    end if;

    return jsonb_build_object(
      'ok', true, 'object_id', v_object, 'relation_kind', 'EXISTING_TABLE',
      'canonical_relation', wm.target_relation, 'operation', wm.operation,
      'result_reference', format('%s:%s=%s', wm.target_relation, wm.key_column, v_result_ref),
      'business_key', v_key, 'state', v_state,
      'policy_family', b.policy_family, 'record_policy', b.record_policy,
      'owner_scope', b.ownership_scope, 'owner_ref', v_owner_ref,
      'columns_written', to_jsonb(v_cols),
      'outbound_requests_enqueued', coalesce(v_net_new, 0),
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
end $function$;

-- CREATE OR REPLACE preserves the ACL, so the D2 revoke stands and is not repeated here.

-- -------------------------------------------------------------------------------------------------
-- 3b. The scenario must ABORT on an outbound request, not record it as one blocked stage.
--
-- The per-stage handler in fn_phase_d_fixture_scenario catches everything and records it as a
-- REFUSED stage, re-raising only for pd_fixture_external_effect_produced. Without the same
-- treatment the new refusal would have been swallowed: the scenario would have returned ok=false
-- with a blocked stage, and a caller reading stages_created would never learn that a POST had been
-- attempted. Error and empty must not return the same value.
--
-- The body below is the LIVE definition with three edits and nothing else, generated from
-- pg_get_functiondef rather than retyped, so no increment between D9c and D16 is reverted by this
-- file. That is the failure mode recorded in the D9 closure section 5.
-- -------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_scenario(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  st       public.phase_d_fixture_stage%rowtype;
  v_label  text := nullif(btrim(coalesce(p_input->>'label','')),'');
  v_ctx    text := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),''));
  v_upto   int  := coalesce(nullif(p_input->>'up_to_stage','')::int, 9999);
  v_actor  text := coalesce(nullif(btrim(p_input->>'created_by'),''), 'phase_d_fixture_factory');
  v_refs   jsonb := '{}'::jsonb;
  v_man    jsonb := '[]'::jsonb;
  v_w      jsonb;
  v_pay    jsonb;
  v_key    text;
  v_owner  text;
  v_state  text;
  v_name   text;
  v_missing text[];
  v_ref_n  bigint;
  v_err    text;
  v_ok     int := 0; v_blocked int := 0; v_owned int := 0;
  v_for_wf text := nullif(btrim(coalesce(p_input->>'for_workflow','')),'');
  v_notif_before bigint; v_notif_after bigint;
  v_inbox_before bigint; v_inbox_after bigint;
  v_notif_start  bigint; v_inbox_start  bigint;
  v_net_start    bigint;
begin
  if v_label is null then
    raise exception 'fn_phase_d_fixture_scenario: label is required; it is what makes the ids deterministic and the residue findable (pd_fixture_label_missing)'
      using errcode = '22023';
  end if;
  if v_ctx <> 'test' then
    raise exception 'fn_phase_d_fixture_scenario: execution_context is %; this factory runs only in test (pd_fixture_not_test_context)',
      coalesce(nullif(v_ctx,''),'(unset)') using errcode = '23514';
  end if;
  if coalesce(nullif(btrim(current_setting('app.phase_d_test_context', true)),''),'') <> 'on' then
    raise exception 'fn_phase_d_fixture_scenario: app.phase_d_test_context is not set to on in this transaction (pd_fixture_no_test_context)'
      using errcode = '23514',
            hint = 'set local app.phase_d_test_context = ''on''; and abort the transaction when finished.';
  end if;
  if current_user in ('anon','authenticated') then
    raise exception 'fn_phase_d_fixture_scenario: % may not build fixtures (pd_fixture_untrusted_caller)',
      current_user using errcode = '42501';
  end if;

  select coalesce(max(id),0) into v_net_start from net.http_request_queue;
  select count(*) into v_notif_start from public.notifications;
  select count(*) into v_inbox_start from public.kernel_trigger_inbox;

  for st in select * from public.phase_d_fixture_stage where stage_no <= v_upto order by stage_no
  loop
    -- A SCENARIO MUST NOT PRE-CREATE THE OBJECT THE WORKFLOW UNDER TEST PRODUCES. W09 writes
    -- supplier_capability, W14 writes quotation, W16 writes payment_transaction; building those
    -- first made the workflow collide with its own output on a unique constraint, and a harness
    -- that seeds the row the step is supposed to create is answering its own question. The set is
    -- read from phase_d_step_effect for that workflow, never listed by hand.
    if v_for_wf is not null and exists (
         select 1 from public.phase_d_step_effect x
          where x.workflow_id = v_for_wf and x.effect_object_id = st.object_id) then
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status', 'SKIPPED_PRODUCED_BY_THE_WORKFLOW_UNDER_TEST', 'detail', v_for_wf));
      v_owned := v_owned + 1;
      continue;
    end if;

    select array_agg(r) into v_missing
      from unnest(st.requires_stages) r
     where not exists (select 1 from jsonb_array_elements(v_man) m
                        where m->>'stage_key' = r and m->>'status' = 'CREATED');
    if v_missing is not null then
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status', 'SKIPPED_PARENT_NOT_CREATED', 'detail', array_to_string(v_missing, ', ')));
      v_blocked := v_blocked + 1;
      continue;
    end if;

    if st.reference_relation is not null then
      execute format('select count(*) from %s', st.reference_relation) into v_ref_n;
      if v_ref_n = 0 then
        v_man := v_man || jsonb_build_array(jsonb_build_object(
          'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
          'status', 'BLOCKED_NO_REFERENCE_DATA', 'detail',
          format('%s holds 0 rows and this factory does not create business reference data',
                 st.reference_relation)));
        v_blocked := v_blocked + 1;
        continue;
      end if;
    end if;

    v_name  := format('ZZ DEMO — %s %s', v_label, st.stage_key);
    v_key   := md5(format('%s:%s', v_label, st.stage_key))::uuid::text;
    v_owner := v_key;
    v_state := 'open';
    v_pay   := jsonb_build_object('fixture_label', v_label, 'stage', st.stage_key,
                                  'phase_d_test_context', true);

    if st.stage_key = 'customer_account' then
      -- NO EMAIL AND NO PHONE. trg_inquiry_received_a queues a customer email for any inquiry whose
      -- customer has an address, and trg_new_quote_sms / trg_reveal_receipt_a do the same on a
      -- phone. The fixture identity carries neither, and the per-stage assertion below is what
      -- proves it rather than this comment.
      v_state := 'active';
      v_pay := v_pay || jsonb_build_object('full_name', v_name, 'locale', 'en');

    elsif st.stage_key = 'customer_terms_acceptance' then
      v_owner := v_refs->>'customer_id'; v_state := 'accepted';
      v_pay := v_pay || jsonb_build_object(
        'terms_version', 'zz-terms-v1',
        'terms_hash', encode(sha256(convert_to('zz-terms-v1','UTF8')),'hex'),
        'accepted_by', v_refs->>'customer_id');

    elsif st.stage_key = 'inquiry' then
      -- The FACTS fn_rfq_score reads, never a readiness flag. rfq_ready is derived by
      -- trg_rfq_complete and the verdict stays the product's own.
      v_owner := v_refs->>'customer_id'; v_state := 'quote_ready';
      v_pay := v_pay || public.fn_phase_d_fixture_inquiry_payload(v_label);

    elsif st.stage_key = 'inquiry_answer' then
      v_owner := v_refs->>'inquiry_id'; v_state := 'recorded';
      v_pay := v_pay || jsonb_build_object(
        'answer_scope','inquiry_shared', 'source_kind','customer', 'precedence', 1,
        'value', to_jsonb('ZZ DEMO — fixture answer'::text),
        'field_id', (select id from public.field_definition order by id limit 1),
        'group_id', (select id from public.inquiry_workstream_group order by id limit 1));

    elsif st.stage_key = 'inquiry_version' then
      v_owner := v_refs->>'inquiry_id'; v_state := 'frozen';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id', 'version', 1);

    elsif st.stage_key = 'inquiry_route_set' then
      v_owner := v_refs->>'inquiry_id'; v_state := 'confirmed';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'route_state','confirmed', 'routes', '["general"]'::jsonb,
                                           'evidence','ZZ DEMO — fixture route evidence');

    elsif st.stage_key = 'inquiry_document' then
      v_owner := v_refs->>'inquiry_id'; v_state := 'validated';
      v_pay := v_pay || jsonb_build_object('kind','boq', 'mime','application/pdf',
                                           'bucket','zz-phase-d-fixtures',
                                           'path', format('zz/%s/%s.pdf', v_label, st.stage_key),
                                           'file_name', format('zz-%s.pdf', v_label));

    elsif st.stage_key = 'document_extraction' then
      v_owner := v_refs->>'document_id'; v_state := 'extracted';
      v_pay := v_pay || jsonb_build_object('document_id', v_refs->>'document_id',
                                           'method','deterministic', 'paid_model_used', false);

    elsif st.stage_key = 'supplier_safe_package' then
      v_owner := v_refs->>'inquiry_id'; v_state := 'approved';
      v_pay := v_pay || jsonb_build_object(
        'inquiry_id', v_refs->>'inquiry_id',
        'safe_package_ref', v_key,
        'safe_package_approved_by', 'compliance_and_privacy_officer',
        'contents','ZZ DEMO — scope and quantities only; no customer identity');

    elsif st.stage_key = 'supplier_account' then
      v_state := 'approved';
      v_pay := v_pay || jsonb_build_object('company_name', v_name, 'verified', true);

    elsif st.stage_key = 'supplier_terms_acceptance' then
      v_owner := v_refs->>'supplier_id'; v_state := 'accepted';
      v_pay := v_pay || jsonb_build_object('terms_version','zz-supplier-terms-v1',
        'terms_hash', encode(sha256(convert_to('zz-supplier-terms-v1','UTF8')),'hex'),
        'supplier_id', v_refs->>'supplier_id');

    elsif st.stage_key = 'supplier_capability' then
      v_owner := v_refs->>'supplier_id'; v_state := 'approved';
      v_pay := v_pay || jsonb_build_object('trades', '["general"]'::jsonb);

    elsif st.stage_key = 'supplier_verification_case' then
      v_owner := v_refs->>'supplier_id'; v_state := 'verified';
      v_pay := v_pay || jsonb_build_object('supplier_id', v_refs->>'supplier_id',
                                           'evidence','ZZ DEMO — fixture verification evidence',
                                           'verified_by','supplier_verification');

    elsif st.stage_key = 'supplier_assignment' then
      v_owner := v_refs->>'supplier_id'; v_state := 'dispatched';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'similarity', 0.9,
                                           'match_reason','ZZ DEMO — fixture assignment');

    elsif st.stage_key = 'quotation' then
      v_owner := v_refs->>'supplier_id'; v_state := 'submitted';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id', 'quote_amount', 1000);

    elsif st.stage_key = 'quotation_revision' then
      v_owner := v_refs->>'supplier_id'; v_state := 'submitted';
      v_pay := v_pay || jsonb_build_object('quote_id', v_refs->>'quote_id',
                                           'quote_revision_ref', v_key, 'platform_edited', false);

    elsif st.stage_key = 'quotation_comparison' then
      v_owner := v_refs->>'customer_id'; v_state := 'published';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'analysis', jsonb_build_object('note','ZZ DEMO — fixture comparison'),
                                           'quote_count', 1,
                                           'signature', encode(sha256(convert_to(v_key,'UTF8')),'hex'));

    elsif st.stage_key = 'customer_selection' then
      v_owner := v_refs->>'customer_id'; v_state := 'selected';
      v_pay := v_pay || jsonb_build_object('comparison_id', v_refs->>'comparison_id',
                                           'selected_quote_id', v_refs->>'quote_id');

    elsif st.stage_key = 'payment_transaction' then
      v_owner := v_refs->>'customer_id'; v_state := 'payment_reconciled';
      v_pay := v_pay || jsonb_build_object('inquiry_id', v_refs->>'inquiry_id',
                                           'quote_id', v_refs->>'quote_id',
                                           'quote_amount', 1000, 'reveal_fee', 100,
                                           'payment_ref', format('zz-pay-%s', v_label));

    elsif st.stage_key = 'provider_event' then
      v_owner := v_refs->>'transaction_id'; v_state := 'succeeded';
      v_key := format('evt_zz_%s', v_label);
      v_pay := v_pay || jsonb_build_object('event_type','checkout.session.completed');

    elsif st.stage_key = 'reconciliation_case' then
      v_owner := v_refs->>'transaction_id'; v_state := 'reconciled';
      v_pay := v_pay || jsonb_build_object('transaction_id', v_refs->>'transaction_id',
                                           'monetary_state','reconciled');

    elsif st.stage_key = 'reveal_transaction' then
      v_key := v_refs->>'transaction_id';
      v_owner := v_refs->>'customer_id'; v_state := 'reveal_authorized';
      v_pay := v_pay || jsonb_build_object('reveal_fee', 100,
                                           'payment_ref', format('zz-pay-%s', v_label),
                                           'revealed_at', now(),
                                           'supplier_id', (v_refs->>'supplier_id')::bigint);

    elsif st.stage_key = 'refund_dispute_case' then
      v_owner := v_refs->>'customer_id'; v_state := 'requested';
      v_pay := v_pay || jsonb_build_object('transaction_id', v_refs->>'transaction_id',
                                           'amount_fils', 10000, 'reason_code','other',
                                           'reason_note','ZZ DEMO — fixture refund case; no refund is executed',
                                           'requested_by', v_refs->>'customer_id');

    elsif st.stage_key = 'review_record' then
      v_state := 'approved';
      v_pay := v_pay || jsonb_build_object('verdict','approved',
                                           'subject_type','phase_d_fixture', 'subject_id', v_label,
                                           'author_agent','customer_onboarding',
                                           'reviewer_role_id','customer_success_director',
                                           'stage', st.stage_key, 'notes','ZZ DEMO — fixture review');
    end if;

    select count(*) into v_notif_before from public.notifications;
    select count(*) into v_inbox_before from public.kernel_trigger_inbox;

    begin
      v_w := public.fn_phase_d_object_write(jsonb_build_object(
        'object_id', st.object_id, 'business_key', v_key, 'owner_ref', v_owner,
        'created_by', v_actor, 'state', v_state, 'payload', v_pay));

      select count(*) into v_notif_after from public.notifications;
      if v_notif_after <> v_notif_before then
        raise exception 'fn_phase_d_fixture_scenario: stage % wrote % row(s) into public.notifications. A fixture may not queue an outbound message. (pd_fixture_external_effect_produced)',
          st.stage_key, v_notif_after - v_notif_before using errcode = '23514';
      end if;

      if st.contributes_ref is not null then
        v_refs := v_refs || jsonb_build_object(st.contributes_ref,
          case when st.stage_key = 'inquiry_route_set' then 'confirmed'
               else split_part(v_w->>'result_reference', '=', 2) end);
      end if;

      select count(*) into v_inbox_after from public.kernel_trigger_inbox;
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status','CREATED', 'relation', v_w->>'canonical_relation',
        'result_reference', v_w->>'result_reference', 'state', v_w->>'state',
        'policy_family', v_w->>'policy_family',
        'notifications_written', v_notif_after - v_notif_before,
        'kernel_trigger_rows_written', v_inbox_after - v_inbox_before,
        'contributes', st.contributes_ref));
      v_ok := v_ok + 1;

    exception when others then
      v_err := SQLERRM;
      if position('pd_fixture_external_effect_produced' in v_err) > 0 then raise; end if;
      -- D17. An outbound HTTP request is not a stage that failed; it is the whole scenario losing
      -- its zero-external-effect property. It aborts the build exactly as a notification does.
      if position('pd_object_outbound_request_produced' in v_err) > 0 then raise; end if;
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status','REFUSED',
        'refused_with', coalesce((regexp_match(v_err,'\((pd_[a-z0-9_]+)\)'))[1],'(none)'),
        'reason', left(v_err, 300)));
      v_blocked := v_blocked + 1;
    end;
  end loop;

  select count(*) into v_notif_after from public.notifications;
  select count(*) into v_inbox_after from public.kernel_trigger_inbox;

  return jsonb_build_object(
    'ok', v_blocked = 0, 'label', v_label,
    'stages_created', v_ok, 'stages_not_created', v_blocked,
    'stages_left_to_the_workflow_under_test', v_owned, 'for_workflow', v_for_wf,
    'stages_declared', (select count(*) from public.phase_d_fixture_stage where stage_no <= v_upto),
    'parent_refs', v_refs,
    -- THE RULE CONTEXT IS WHAT THIS SCENARIO ACTUALLY PERSISTED, not a set of plausible strings.
    -- Every value below is either a key returned by a write above or the exact value that write
    -- recorded on the row. A rule reading one of these is reading the scenario, and a rule whose
    -- key is absent still gets the driver's generated fixture and still refuses.
    'rule_context', v_refs || jsonb_build_object(
      'caller_customer_id',       v_refs->>'customer_id',
      'safe_package_approved_by', 'compliance_and_privacy_officer',
      'supplier_payload',         'ZZ DEMO — scope and quantities only; no customer identity',
      'terms_version',            'zz-terms-v1',
      'terms_hash',               encode(sha256(convert_to('zz-terms-v1','UTF8')),'hex'),
      'acceptance_ref',           v_refs->>'customer_id',
      'monetary_state',           'reconciled',
      'assignment_result',        'delivered',
      'platform_edited',          'false',
      'inquiry_owner',            'rfq_qualification_manager',
      'publishing_revision_ref',  v_refs->>'quote_revision_ref',
      'approved_revision_ref',    v_refs->>'quote_revision_ref'),
    'manifest', v_man,
    'notifications_written_by_this_scenario', v_notif_after - v_notif_start,
    'kernel_trigger_rows_written_by_this_scenario', v_inbox_after - v_inbox_start,
    -- D17. MEASURED, NOT ASSERTED. Before D17 this object said 'external_effects', 0 while every
    -- build enqueued two POSTs to production edge functions, because the only thing counted was
    -- public.notifications. Both doors are now counted and the writer refuses on either.
    'outbound_http_requests_written_by_this_scenario',
      (select count(*) from net.http_request_queue where id > v_net_start),
    'external_effects', 0, 'paid_calls', 0,
    'note', 'every row here was written through fn_phase_d_object_write; abort the transaction to leave nothing behind');
end $function$
;



-- -------------------------------------------------------------------------------------------------
-- 4. The board. Every check below is derived; none of the numbers is typed.
-- -------------------------------------------------------------------------------------------------
-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_outbound_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke all on function public.fn_phase_d_outbound_state() from public, anon, authenticated;

-- -------------------------------------------------------------------------------------------------
-- 5. DEPLOY-TIME CONTROLS. This file refuses to land if the thing it claims is not true.
-- -------------------------------------------------------------------------------------------------
do $ctl$
declare
  v_scanned int;
  v_registered int;
  v_red int;
  v_probe_urls text;
  v_net_max bigint;
  v_new int;
  v_fired boolean := false;
begin
  -- (a) the scan and the registry cover each other exactly
  select count(*) into v_scanned
    from pg_trigger tg
    join pg_proc  p on p.oid = tg.tgfoid
    join pg_class c on c.oid = tg.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where not tg.tgisinternal and n.nspname='public'
     and p.prosrc ~* 'net\.http_(post|get)'
     and ('public.' || c.relname) in (
           select distinct b.canonical_relation from public.phase_d_business_object_binding b
            where b.relation_kind='EXISTING_TABLE');
  select count(*) into v_registered from public.phase_d_outbound_door;
  if v_scanned <> v_registered then
    raise exception 'D17 control: the trigger scan found % outbound door(s) on Phase D relations and the registry holds %. A door nobody registered is a door nobody closed.',
      v_scanned, v_registered;
  end if;
  if v_registered = 0 then
    raise exception 'D17 control: the registry is empty. The measured state before this file was two POSTs per scenario build, so an empty registry means the scan stopped working, not that the doors closed.';
  end if;

  -- (b) the board is green
  select count(*) into v_red from public.fn_phase_d_outbound_state() where state <> 'GREEN';
  if v_red > 0 then
    raise exception 'D17 control: fn_phase_d_outbound_state() has % red check(s).', v_red;
  end if;

  perform set_config('app.phase_d_test_context','on', true);

  -- (c) THE GUARD MUST FIRE. Empty the registry so nothing is suppressed, build the lineage, and
  --     confirm the canonical writer refuses naming the URL. The subtransaction rollback restores
  --     the registry AND discards every fixture row the attempt created.
  begin
    delete from public.phase_d_outbound_door;
    perform public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','d17-positive-control','execution_context','test'));
  exception
    when sqlstate '23514' then
      if position('pd_object_outbound_request_produced' in SQLERRM) = 0 then raise; end if;
      v_fired := true;
    when others then
      raise;
  end;
  if not v_fired then
    raise exception 'D17 control: with the registry emptied the scenario completed without refusing. The outbound assertion is not firing, which means it cannot tell a closed door from an open one.';
  end if;
  if (select count(*) from public.phase_d_outbound_door) <> v_registered then
    raise exception 'D17 control: the positive control did not restore the registry (% of % rows).',
      (select count(*) from public.phase_d_outbound_door), v_registered;
  end if;

  -- (d) WITH the registry in place, a full scenario build must enqueue NOTHING.
  --     The build is deliberately aborted by its own raise so that this deploy leaves no fixture
  --     row behind; PL/pgSQL variables are not transactional, so the counts survive the rollback.
  --     That is the same aborted-transaction probe every Phase D measurement uses.
  begin
    select coalesce(max(id),0) into v_net_max from net.http_request_queue;
    perform public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','d17-negative-control','execution_context','test'));
    select count(*), string_agg(distinct url, ', ') into v_new, v_probe_urls
      from net.http_request_queue where id > v_net_max;
    raise exception 'PHASE_D_D17_NEGATIVE_CONTROL_ROLLBACK';
  exception
    when others then
      if SQLERRM <> 'PHASE_D_D17_NEGATIVE_CONTROL_ROLLBACK' then raise; end if;
  end;
  if coalesce(v_new,0) <> 0 then
    raise exception 'D17 control: a full scenario build still enqueued % outbound request(s): %',
      v_new, coalesce(v_probe_urls,'(none recorded)');
  end if;

  raise notice 'D17: % outbound door(s) registered; guard fires; a full scenario build enqueues 0 requests.', v_registered;
end $ctl$;

commit;
