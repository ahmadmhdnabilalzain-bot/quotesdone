CREATE OR REPLACE FUNCTION public.fn_phase_d_dispatch_step(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sr public.phase_c_workflow_step_run%rowtype;
  v_step_run bigint := nullif(p_input->>'step_run_id','')::bigint;
  v_actor    text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_kind     text   := coalesce(nullif(btrim(p_input->>'opened_by_kind'),''),'(unstated)');
  v_ref      text   := coalesce(nullif(btrim(p_input->>'opened_by_ref'),''),'(unstated)');
  v_idem     text   := coalesce(nullif(btrim(p_input->>'idempotency_key'),''),'');
  v_wf       text;
  v_on       text;
  v_depth    int;
  v_in       jsonb;
  v_cx       jsonb;
  v_res      jsonb;
  v_unres    text[];
  v_err      text;
  v_bkey     text;   -- E25
  v_owner    text;   -- E25
  v_scope    text;   -- E25
  v_own_rel  text;   -- J06
  v_own_col  text;   -- J07
  v_owner_unfit boolean;   -- J07
  v_owner_fit   text;      -- J07
  v_own_ns   text;   -- J06
  v_code     text;
begin
  if v_step_run is null or v_actor is null then
    raise exception 'fn_phase_d_dispatch_step: step_run_id and actor_role_id are required (got %, %)',
      coalesce(v_step_run::text,'(null)'), coalesce(v_actor,'(null)') using errcode = '22023';
  end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if not found then
    raise exception 'fn_phase_d_dispatch_step: no step run %', v_step_run using errcode = '23503';
  end if;

  if not exists (select 1 from public.phase_d_handler_binding hb where hb.step_id = sr.step_id)
     or not exists (select 1 from public.phase_d_step_effect se where se.step_id = sr.step_id) then
    return jsonb_build_object('dispatched', false, 'outcome', 'NO_BINDING', 'step_id', sr.step_id);
  end if;

  select b2.workflow_id into v_wf from public.phase_d_handler_binding b2 where b2.step_id = sr.step_id;
  if v_idem = '' then v_idem := 'kernel|' || sr.run_id || '|' || sr.step_id; end if;

  v_on    := lower(coalesce(nullif(btrim(current_setting('app.phase_d_dispatch', true)),''), 'on'));
  v_depth := coalesce(nullif(btrim(current_setting('app.phase_d_dispatch_depth', true)),'')::int, 0);

  if v_on = 'off' then
    insert into public.phase_d_dispatch
      (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
       outcome, refusal_code, reason, dispatch_depth)
    values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
            'DISPATCH_OFF', 'pd_dispatch_off',
            'app.phase_d_dispatch is off for this transaction', v_depth);
    return jsonb_build_object('dispatched', false, 'outcome', 'DISPATCH_OFF');
  end if;

  if v_depth >= 64 then
    insert into public.phase_d_dispatch
      (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
       outcome, refusal_code, reason, dispatch_depth)
    values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
            'DEPTH_LIMIT', 'pd_dispatch_depth_limit',
            format('dispatch depth %s reached at step %s', v_depth, sr.step_id), v_depth);
    return jsonb_build_object('dispatched', false, 'outcome', 'DEPTH_LIMIT', 'depth', v_depth);
  end if;

  perform set_config('app.phase_d_dispatch_depth', (v_depth + 1)::text, true);

  begin
    v_in := public.fn_phase_d_step_inputs(v_step_run);
    select array_agg(x) into v_unres
      from jsonb_array_elements_text(coalesce(v_in->'unresolved','[]'::jsonb)) x;
    v_unres := coalesce(v_unres, '{}');

    if cardinality(v_unres) > 0 then
      insert into public.phase_d_dispatch
        (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
         outcome, refusal_code, reason, unresolved_keys, inputs_provenance, dispatch_depth)
      values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
              'INPUTS_UNRESOLVED', 'pd_input_unresolved',
              format('%s of the %s declared input keys resolve from no real source: %s',
                     cardinality(v_unres),
                     jsonb_array_length(coalesce(v_in->'declared_keys','[]'::jsonb)),
                     array_to_string(v_unres, ', ')),
              v_unres, coalesce(v_in->'provenance','{}'::jsonb), v_depth);
      perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
      return jsonb_build_object('dispatched', false, 'outcome', 'INPUTS_UNRESOLVED',
                                'unresolved', to_jsonb(v_unres));
    end if;

    -- D37. The same treatment for what the RULES and GATES read. Unresolved keys are not supplied,
    -- so a rule that needs one refuses instead of passing on a placeholder.
    v_cx := public.fn_phase_d_step_context(v_step_run);

    -- E25. THE DISPATCH WITHHELD THE TWO FIELDS THE WRITE SERVICE REQUIRES, AND IT KNEW BOTH.
    --
    -- fn_phase_d_effect_produce raises pd_effect_owner_or_key_missing for DOMAIN_MUTATION and
    -- VERSIONED_ARTIFACT unless the CALL names business_key and owner_ref. That is the right
    -- behaviour for the routine -- a record written under an owner it chose for itself would be the
    -- auto-vivified account defect in a new place -- but the kernel dispatch passed neither and had
    -- no branch that could. The R3 independent acceptance measured the consequence: 125 of 257 steps
    -- structurally excluded before any rule was consulted, and the only two steps that executed were
    -- KERNEL_ONLY_TRANSITION ones that write no business object at all.
    --
    -- Neither field is invented here. Both are READ, and where they cannot be read the step still
    -- refuses:
    --
    --   owner_ref  COMPANY-scoped object -> phase_c_workflow_step_run.accountable_role_id, which is
    --              the frozen registry's own answer to who is accountable for this step. Not chosen.
    --              CUSTOMER- or SUPPLIER-scoped -> the owner column of the run's OWN business row,
    --              and null when no such row exists. A customer is never conjured to own a record.
    --
    --   business_key  the run's business_object_id, and ONLY when it actually carried the
    --              '<object>:' prefix of the object this step writes -- 'inquiry:<uuid>' is an
    --              identity, 'outbox:195' and a probe label are not. fn_phase_d_step_context reports
    --              key_is_prefixed for exactly this decision.
    --
    -- jsonb_strip_nulls means an underivable field is ABSENT rather than null, so the write service
    -- sees precisely what it saw before and refuses in precisely the same way.
    v_scope := v_cx#>>'{business_object,ownership_scope}';
    if coalesce((v_cx#>>'{business_object,key_is_prefixed}')::boolean, false) then
      v_bkey := nullif(btrim(coalesce(v_cx#>>'{business_object,object_key}','')),'');
    end if;

    -- F13. A STEP THAT WRITES AN OBJECT OTHER THAN ITS RUN'S PRIMARY HAD NO KEY IT COULD EVER GET.
    --
    -- E25 derives business_key from the run's business_object_id and only when it carries the
    -- '<object>:' prefix of the object THIS STEP writes -- which is right, and which means a step
    -- like W01-S07 (run is company_objective:..., step writes the initiative object) can never be prefixed
    -- and refuses with pd_effect_owner_or_key_missing on every drive. That is correct in
    -- production: nothing has told the estate which initiative this is.
    --
    -- Inside a verified Phase D fixture run there IS an answer, and it is a read rather than an
    -- invention: the scenario either already created a record of that object -- in which case this
    -- step mutates THAT record -- or it did not, in which case the key is derived deterministically
    -- from (fixture run, object, run), so the same scenario driven twice produces the same key and
    -- a replay collides with itself instead of creating a second record.
    if v_bkey is null and public.fn_phase_d_fixture_context() is not null then
      -- H05. AN APPEND_ONLY OBJECT IS NEVER WRITTEN UNDER THE SCENARIO'S EXISTING KEY. Its policy is
      -- that a correction is a NEW key, so the scenario's record is not "the record this step
      -- mutates" -- this step appends beside it. The key is derived from the step as well as the
      -- run, so each appending step is its own record and a replay of one step run is one record.
      if exists (select 1 from public.phase_d_business_object_binding bb
                  where bb.object_id = (v_cx#>>'{business_object,object_id}')
                    and bb.policy_family = 'APPEND_ONLY') then
        v_bkey := md5(format('phase_d_fixture:%s:%s:%s:%s',
                             public.fn_phase_d_fixture_context(),
                             v_cx#>>'{business_object,object_id}', sr.run_id, sr.step_id))::uuid::text;
      end if;
    end if;
    if v_bkey is null and public.fn_phase_d_fixture_context() is not null then
      select coalesce(sc.contributed_value, sc.business_key) into v_bkey
        from public.phase_d_scenario_record sc
       where sc.fixture_run_id = public.fn_phase_d_fixture_context()
         and sc.object_id = (v_cx#>>'{business_object,object_id}')
       order by sc.scenario_record_id limit 1;
      if v_bkey is null and (v_cx#>>'{business_object,object_id}') is not null then
        v_bkey := md5(format('phase_d_fixture:%s:%s:%s',
                             public.fn_phase_d_fixture_context(),
                             v_cx#>>'{business_object,object_id}', sr.run_id))::uuid::text;
      end if;
    end if;
    v_owner := nullif(btrim(coalesce(v_cx#>>'{business_object,row_owner_ref}','')),'');
    if v_owner is null and coalesce(v_scope,'COMPANY') = 'COMPANY' then
      v_owner := nullif(btrim(coalesce(sr.accountable_role_id,'')),'');

      -- J07. A ROLE IS NOT ALWAYS WHAT THE OWNER COLUMN HOLDS. E25 made the accountable role the
      -- owner of a COMPANY-scoped write, which is right about WHO is accountable and says nothing
      -- about what the column stores. Measured 23 Aug 2026 on W01-S07: the object is initiative,
      -- the relation public.org_tasks, the owner column dept_key, and
      --
      --   insert or update on table "org_tasks" violates foreign key constraint
      --   "org_tasks_dept_key_fkey"      -- FOREIGN KEY (dept_key) REFERENCES org_departments(dept_key)
      --
      -- because a role id is not a department key. The column's own foreign key settles it: where
      -- the accountable role does not satisfy that key, the answer is the value from this role's
      -- OWN registry row that does. public.org_role.primary_department_id resolves against
      -- public.org_departments for all 180 roles; public.org_agents.department is the same fact
      -- under the runtime key, and is tried second for a role recorded only there.
      --
      -- Nothing is invented and nothing is chosen: two candidates, both read off the role's own
      -- record, each TESTED against the foreign key before it is used. A role whose registry row
      -- satisfies neither leaves the owner exactly as E25 left it, and the write refuses as before.
      select cl3.relname, ns3.nspname, a4.attname
        into v_own_rel, v_own_ns, v_own_col
        from public.phase_d_object_write_map wm3
        join pg_attribute a3 on a3.attrelid = to_regclass(wm3.target_relation)
                            and a3.attname = wm3.owner_column and a3.attnum > 0
        join pg_constraint c3 on c3.conrelid = a3.attrelid and c3.contype = 'f'
                             and a3.attnum = any (c3.conkey)
        join pg_class cl3 on cl3.oid = c3.confrelid
        join pg_namespace ns3 on ns3.oid = cl3.relnamespace
        join pg_attribute a4 on a4.attrelid = c3.confrelid and a4.attnum = c3.confkey[1]
       where wm3.object_id = v_cx#>>'{business_object,object_id}'
         and coalesce(btrim(wm3.owner_column),'') <> ''
       limit 1;

      if v_own_rel is not null and v_owner is not null then
        execute format('select not exists (select 1 from %I.%I where %I::text = $1)',
                       v_own_ns, v_own_rel, v_own_col)
          into v_owner_unfit using v_owner;
        if coalesce(v_owner_unfit, false) then
          execute format(
            'select c.v from (select r.primary_department_id::text v, 1 ord from public.org_role r'
            || ' where r.role_id = $1'
            || ' union all select a.department::text, 2 from public.org_agents a where a.agent_key = $1) c'
            || ' where c.v is not null'
            || '   and exists (select 1 from %I.%I t where t.%I::text = c.v)'
            || ' order by c.ord limit 1',
            v_own_ns, v_own_rel, v_own_col)
            into v_owner_fit using v_owner;
          if v_owner_fit is not null then v_owner := v_owner_fit; end if;
        end if;
      end if;
      v_own_rel := null; v_own_ns := null; v_own_col := null;
    end if;

    -- F37. THE SAME HOLE F13 CLOSED FOR THE KEY, STILL OPEN FOR THE OWNER.
    --
    -- E25 gave a COMPANY-scoped object an owner -- the frozen registry's own accountable role for
    -- the step -- and left CUSTOMER- and SUPPLIER-scoped objects to row_owner_ref, which reads the
    -- owner column of the run's OWN business row. A step that CREATES the first record of such an
    -- object has no such row yet, so the owner is unresolvable by construction and the step refuses
    -- with pd_effect_owner_or_key_missing on every drive. Measured: W10-S01
    -- (supplier_verification_case), W18-S01 (customer_case) and W19-S01 (supplier_retention_case)
    -- are the FIRST handler refusal of their whole workflow, for exactly this.
    --
    -- In production that refusal is right and it stays: a supplier case owned by a supplier this
    -- routine picked would be the auto-vivified account defect one table over.
    --
    -- Inside a verified Phase D fixture run there is a real answer and it is a READ. The scenario
    -- factory created the parent -- a supplier, a customer -- through the canonical services and
    -- recorded it in public.phase_d_scenario_record with its own owner_ref and ownership_scope.
    -- This takes THAT owner, matched on the scope the object declares. It invents nothing, it
    -- cannot fire outside a fixture context, and where the scenario created no parent of that scope
    -- the owner is still null and the step still refuses.
    if v_owner is null
       and coalesce(v_scope,'COMPANY') <> 'COMPANY'
       and public.fn_phase_d_fixture_context() is not null then
      -- J06. WHICH SCENARIO RECORD IS THE OWNER. The block below took the FIRST record of the same
      -- ownership scope, and "same scope" is not an identity. Measured 23 Aug 2026 on one built
      -- scenario, SUPPLIER-scoped records in scenario_record_id order:
      --
      --   supplier_safe_package   owner=9385a4f3-...   <- the INQUIRY's uuid, and the first row
      --   supplier_account        owner=5909be81-...   key=37090
      --   supplier_terms_acceptance owner=37090
      --   supplier_capability     owner=37090
      --   supplier_assignment     owner=37090
      --
      -- so every SUPPLIER-scoped write inherited an inquiry's uuid as its supplier, and
      -- public.supplier_capabilities.supplier_id is bigint: "invalid input syntax for type bigint:
      -- 65d2c329-64dd-0209-1544-e87ef8a30684" -- pd_effect_value_malformed, on W09-S03 and W12-S06.
      --
      -- The owner column already says what it wants, in the schema: it carries a FOREIGN KEY to the
      -- relation that holds the owning party. Read that, find the business object bound to that
      -- relation, and take the key the scenario gave THAT object. Nothing is chosen by position, by
      -- naming convention or by a list of scopes; every step is a read of a record the estate
      -- already holds. Where the owner column carries no foreign key, or the scenario created no
      -- such party, the previous behaviour stands and the step still refuses when it resolves
      -- nothing.
      select cl2.relname, ns2.nspname into v_own_rel, v_own_ns
        from public.phase_d_object_write_map wm2
        join pg_attribute a2 on a2.attrelid = to_regclass(wm2.target_relation)
                            and a2.attname = wm2.owner_column and a2.attnum > 0
        join pg_constraint c2 on c2.conrelid = a2.attrelid and c2.contype = 'f'
                             and a2.attnum = any (c2.conkey)
        join pg_class cl2 on cl2.oid = c2.confrelid
        join pg_namespace ns2 on ns2.oid = cl2.relnamespace
       where wm2.object_id = v_cx#>>'{business_object,object_id}'
         and coalesce(btrim(wm2.owner_column),'') <> ''
       limit 1;

      if v_own_rel is not null then
        select nullif(btrim(coalesce(sc.business_key,'')),'') into v_owner
          from public.phase_d_scenario_record sc
          join public.phase_d_business_object_binding bb on bb.object_id = sc.object_id
         where sc.fixture_run_id = public.fn_phase_d_fixture_context()
           and bb.canonical_relation = v_own_ns || '.' || v_own_rel
           and coalesce(btrim(sc.business_key),'') <> ''
         order by sc.scenario_record_id
         limit 1;
      end if;

      -- L04. AND AN OBJECT THE ESTATE STORES IN public.phase_d_object_record HAS NO WRITE MAP, SO
      -- IT HAS NO OWNER COLUMN AND NO FOREIGN KEY FOR J06 TO READ. All 22 PHASE_D_OBJECT_VIEW
      -- objects fall straight past that block to the positional fallback below -- "the first
      -- scenario record of the same ownership scope" -- which J06 itself recorded is not an
      -- identity. It went unseen because the fixture scenario built those objects too, so nothing
      -- downstream ever had to read one the product had written.
      --
      -- Measured 23 Aug 2026 with the harness withholding the object the workflow under test
      -- produces: W09-S06 wrote the supplier terms acceptance owned by ca99c3de-..., which is the
      -- supplier_safe_package's uuid and the first SUPPLIER-scoped scenario record. The acceptance
      -- therefore belonged to no supplier, "the acceptance this run's party owns" found nothing at
      -- W09-S07, S08 and S09, and BR-025 refused all three from the catalogue.
      --
      -- THE REGISTRY SAYS WHOSE IT IS. The object's governing workflow has a primary object, and
      -- where that primary object is a DIFFERENT object of the SAME ownership scope, that object is
      -- the party. supplier_terms_acceptance is governed by W09 whose primary object is
      -- supplier_account, both SUPPLIER. Nothing is chosen by position. An object that is its own
      -- governing workflow's primary object, or whose governing workflow names none (the two
      -- registered as W16/W27 and W09/W10), resolves nothing here and the fallback below still
      -- runs, so no object loses an owner it had.
      if v_owner is null then
        select nullif(btrim(coalesce(sc.business_key,'')),'') into v_owner
          from public.phase_d_business_object_binding bb
          join public.phase_b_workflow w on w.workflow_id = bb.governing_workflow_id
          join public.phase_d_business_object_binding pb on pb.object_id = w.primary_object
          join public.phase_d_scenario_record sc on sc.object_id = pb.object_id
         where bb.object_id = v_cx#>>'{business_object,object_id}'
           and pb.object_id <> bb.object_id
           and pb.ownership_scope = bb.ownership_scope
           and sc.fixture_run_id = public.fn_phase_d_fixture_context()
           and coalesce(btrim(sc.business_key),'') <> ''
         order by sc.scenario_record_id
         limit 1;
      end if;

      if v_owner is null then
        select nullif(btrim(coalesce(sc.owner_ref,'')),'') into v_owner
          from public.phase_d_scenario_record sc
         where sc.fixture_run_id = public.fn_phase_d_fixture_context()
           and sc.ownership_scope = v_scope
           and coalesce(btrim(sc.owner_ref),'') <> ''
         order by sc.scenario_record_id
         limit 1;
      end if;
    end if;

    v_res := public.fn_phase_d_handler_execute(jsonb_build_object(
      'step_run_id',       v_step_run,
      'actor_role_id',     v_actor,
      'idempotency_key',   v_idem || '|phase_d',
      'inputs',            v_in->'inputs',
      'context',           v_cx->'context',
      'gate_evidence',     v_cx->'context',
      'execution_context', 'production',
      'correlation_id',    p_input->>'correlation_id',
      'causation_id',      'kernel_dispatch:' || v_kind || ':' || v_ref)
      || jsonb_strip_nulls(jsonb_build_object(
      'business_key',      v_bkey,
      'owner_ref',         v_owner)));

    insert into public.phase_d_dispatch
      (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
       outcome, inputs_provenance, effect_id, dispatch_depth)
    values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
            'EXECUTED',
            coalesce(v_in->'provenance','{}'::jsonb) || coalesce(v_cx->'provenance','{}'::jsonb),
            nullif(v_res#>>'{phase_d,business_effect,effect_id}','')::bigint, v_depth);

    perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
    return jsonb_build_object('dispatched', true, 'outcome', 'EXECUTED',
             'handler_id', v_res#>>'{phase_d,handler_id}',
             'effect_id',  v_res#>'{phase_d,business_effect,effect_id}');

  exception
    when others then
      v_err  := SQLERRM;
      -- E26. AN UNCLASSIFIED REFUSAL IS AN INSTRUMENT GAP, NOT A CATEGORY.
      -- Once E25 stopped the dispatch withholding business_key and owner_ref, two steps reached the
      -- real business write for the first time and failed on a NOT NULL column of the target
      -- relation -- public.opportunity.kind. That is a genuine and interesting refusal: the payload
      -- carries an IDENTITY for the record but not its CONTENT, and the content of an opportunity is
      -- a judgement no deterministic handler can make while the reasoning capability is held. It
      -- deserves to be named. Recorded as pd_unclassified it looked like a bug in the dispatch.
      --
      -- A raised Phase D or kernel code still wins; this only names what used to fall through.
      v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1],
        case SQLSTATE
          when '23502' then 'pd_effect_payload_incomplete'   -- not-null column the payload did not fill
          when '23503' then 'pd_effect_reference_unresolved'  -- foreign key the payload pointed nowhere
          when '23505' then 'pd_effect_identity_collision'    -- unique key already taken
          when '23514' then 'pd_effect_check_violated'        -- a check constraint on the target relation
          when '22P02' then 'pd_effect_value_malformed'       -- a value the target column cannot parse
          else 'pd_unclassified' end);
      insert into public.phase_d_dispatch
        (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
         outcome, refusal_code, sqlstate_code, reason, unresolved_keys, inputs_provenance,
         dispatch_depth)
      values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
              -- E19. This column used to say REFUSED whether the handler had judged the evidence
              -- and rejected it, or had never been given any. Those are different events, and the
              -- 2026-08-20 acceptance audit read the second as the first. Both are refusals and
              -- neither is a pass; only the name differs.
              case when v_code = 'pd_evidence_absent' then 'REFUSED_EVIDENCE_ABSENT' else 'REFUSED' end,
              v_code, SQLSTATE, left(v_err, 1000),
              coalesce((select array_agg(x) from jsonb_array_elements_text(
                          coalesce(v_cx->'unresolved','[]'::jsonb)) x), '{}'),
              coalesce(v_cx->'provenance','{}'::jsonb), v_depth);
      perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
      return jsonb_build_object('dispatched', false,
                                'outcome', case when v_code = 'pd_evidence_absent'
                                                then 'REFUSED_EVIDENCE_ABSENT' else 'REFUSED' end,
                                'refusal_code', v_code, 'sqlstate', SQLSTATE);
  end;
end
$function$
