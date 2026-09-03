-- THE PARENT-DELETE GUARD ASKS THE SAME QUESTION THE ORPHANED-WORK BOARD ASKS.
--
-- a00_kernel_parent_delete_guard (BEFORE DELETE on customers, inquiries, leads, os_incidents,
-- quotes, refunds, transactions) closes every live kernel run about the row before the row goes,
-- through fn_kernel_cancel in the same transaction — so a deleted parent never leaves an orphan.
-- It searched for those runs as `<object_id>:<primary_identity of OLD>`, i.e. payment_transaction:<id>.
-- But W16 writes its subject as payment_transaction:<transactions.payment_ref> (measured 27 Aug 2026
-- and recorded in fn_kernel_business_subject_resolve, which was taught the tolerant, truer question:
-- IS THERE A ROW THIS RUN IS ABOUT, by whichever column the producer used). The board got that
-- resolver; the delete guard did not. So on 3 Sep 2026 three demo-rehearsal transactions were deleted
-- under active W16 runs the guard could not see — no notice, no cancel — and fn_kernel_orphaned_work
-- correctly went red with 3 active runs whose business parent was gone. They were closed by hand
-- through fn_kernel_cancel; this file makes the guard close them itself.
--
-- Now, for each business object bound to the table, every live run under that object prefix is
-- resolved through fn_kernel_business_subject_resolve; a run whose identity value is in the row being
-- deleted — under the binding's identity column OR any other column, because the resolver reports
-- identity_column='id' even when it matched payment_ref — is cancelled, and the postcondition is asserted with the same
-- resolver. One vocabulary for the board and the guard. CREATE OR REPLACE keeps the seven triggers
-- attached and the ACL intact.
--
--   node scripts/apply_sql.mjs scripts/sql/parent_delete_guard_matches_how_producers_key_the_subject.sql --apply --ddl

create or replace function public.fn_kernel_business_parent_delete_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare b record; v_pk text; v_run record; v_res record; v_left int;
begin
  for b in select bo.object_id, bo.primary_identity
             from public.phase_d_business_object_binding bo
            where bo.canonical_relation = TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME
              and coalesce(btrim(bo.primary_identity), '') <> '' loop
    v_pk := to_jsonb(OLD) ->> b.primary_identity;
    if v_pk is null then continue; end if;

    -- Every live run under this business object, matched the way the orphaned-work board matches:
    -- resolve the run's subject; if it points at THIS row (by whichever column the producer keyed —
    -- id, payment_ref, ...), close it before the row goes.
    for v_run in select r.run_id, r.workflow_id, r.business_object_id
                   from public.phase_c_workflow_run r
                  where r.business_object_id like b.object_id || ':%'
                    and r.state not in ('cancelled', 'superseded', 'completed', 'failed')
                  order by r.run_id loop
      select * into v_res from public.fn_kernel_business_subject_resolve(v_run.business_object_id) limit 1;
      if v_res.resolution is distinct from 'RESOLVED' or v_res.identity_column is null then continue; end if;
      -- The resolver reports the BINDING's identity column ('id') even when it matched under another
      -- column (its resolved_in says so in prose). So the question is: is the identity value in THIS
      -- row — under the primary identity, or under any other column, exactly as the resolver searched?
      if (to_jsonb(OLD) ->> v_res.identity_column) is distinct from v_res.identity_value
         and not exists (select 1 from jsonb_each_text(to_jsonb(OLD)) kv where kv.value = v_res.identity_value) then
        continue;
      end if;
      raise notice 'kernel: closing % run % before %.% % = % is deleted (subject % is keyed by %)',
        v_run.workflow_id, v_run.run_id, TG_TABLE_SCHEMA, TG_TABLE_NAME, b.primary_identity, v_pk,
        v_run.business_object_id, v_res.identity_column;
      perform public.fn_kernel_cancel(jsonb_build_object(
        'subject_kind', 'workflow_run',
        'subject_ref',  v_run.run_id::text,
        'op',           'cancel',
        'actor',        'system.workflow_engine',
        'reason',       'PARENT_DELETED: ' || TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME || ' '
                        || b.primary_identity || '=' || v_pk || ' (business object ' || v_run.business_object_id
                        || ', keyed by ' || v_res.identity_column || ') was deleted, so this run has nothing '
                        || 'left to be about. Closed by a00_kernel_parent_delete_guard through the canonical '
                        || 'cancellation path, in the same transaction as the delete, before the parent row went.'));
    end loop;

    -- THE POSTCONDITION, ASSERTED WITH THE SAME RESOLVER: no live run may still resolve to this row.
    select count(*) into v_left
      from public.phase_c_workflow_run r
      cross join lateral (select * from public.fn_kernel_business_subject_resolve(r.business_object_id) limit 1) x
     where r.business_object_id like b.object_id || ':%'
       and r.state not in ('cancelled', 'superseded', 'completed', 'failed')
       and x.resolution = 'RESOLVED' and x.identity_column is not null
       and ((to_jsonb(OLD) ->> x.identity_column) is not distinct from x.identity_value
            or exists (select 1 from jsonb_each_text(to_jsonb(OLD)) kv where kv.value = x.identity_value));
    if v_left > 0 then
      raise exception 'public.%: % live workflow run(s) still resolve to this row (business object %:%) after the compensation loop, so deleting it would orphan them. (kernel_parent_delete_has_live_work)',
        TG_TABLE_NAME, v_left, b.object_id, v_pk
        using errcode = '23503',
              hint = 'Close them first: select public.fn_kernel_cancel(jsonb_build_object('
                     || '''subject_kind'',''workflow_run'',''subject_ref'',''<run_id>'',''op'',''cancel'','
                     || '''actor'',''<who>'',''reason'',''<why>'')); then delete the parent.';
    end if;
  end loop;
  return OLD;
end $function$;
