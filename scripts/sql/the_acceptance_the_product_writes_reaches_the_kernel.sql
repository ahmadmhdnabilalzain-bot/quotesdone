-- THE ACCEPTANCE THE PRODUCT WRITES REACHES THE KERNEL (6 Sep 2026).
--
-- scripts/sql/the_customer_accepts_and_the_step_can_execute.sql built fn_customer_terms_accept: it
-- records the customer's acceptance against the CURRENTLY PUBLISHED customer terms (version + sha256
-- from public.legal_documents) as an append-only customer_terms_acceptance record, and re-dispatches
-- the open W04-S01 through the canonical door (fn_phase_d_dispatch_step) so BR-025 and BR-026 pass
-- and the step reaches EXECUTED with a phase_d_effect_ledger row. Proven in an aborted rehearsal.
--
-- What it still lacked was an ENTRY POINT the product actually uses. The edge function kyc
-- (action accept_terms) writes customers.tos_accepted_at / tos_version / tos_ip and never calls the
-- rpc; the edit that added the call could not be deployed (a sibling function, sanctions_screen,
-- is live with verify_jwt=false and absent from supabase/config.toml, and the deploy script refuses
-- to deploy through that drift -- correctly). A finished capability with no entry point is the
-- lens this estate keeps paying for, so the entry point moves to the one place EVERY writer of an
-- acceptance passes through: the row itself.
--
-- z56_customer_terms_accepted fires AFTER UPDATE OF tos_accepted_at on public.customers, only on
-- the null -> not-null transition (the WHEN clause), and calls fn_customer_terms_accept for that
-- customer. The kyc function as deployed today therefore produces the kernel record and the
-- re-dispatch without a redeploy, and so will any future writer (an admin path, a migration of a
-- legacy account, a second portal). The kyc edit is reverted in the same commit: one path, at the
-- root, instead of two.
--
-- NO RECURSION. fn_customer_terms_accept updates public.customers (tos_version, tos_ip, and
-- tos_accepted_at = coalesce(tos_accepted_at, now())). That nested UPDATE names tos_accepted_at, so
-- the trigger is considered again -- and the WHEN clause sees old.tos_accepted_at already set and
-- does not fire. pg_trigger_depth() is checked too, so a future writer that clears and re-sets the
-- column inside the trigger cannot loop either.
--
-- FAIL-SAFE, BUT NOT SILENT. The customer's acceptance is already on the row when this runs; a
-- kernel fault (a refused dispatch, a missing document) must never turn the customer's "Finish"
-- into an error. The exception is caught and written to public.error_events (source
-- customer_terms_accepted_trg), which the failed-runs watcher and the OS surfaces already read,
-- so a fault is a fact on a ledger rather than a swallowed one.
--
--   node scripts/apply_sql.mjs scripts/sql/the_acceptance_the_product_writes_reaches_the_kernel.sql --apply --ddl

begin;

create or replace function public.fn_customer_terms_accepted_trg()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v jsonb;
begin
  if pg_trigger_depth() > 1 then
    return new;
  end if;
  begin
    v := public.fn_customer_terms_accept(new.id, new.tos_ip);
    if coalesce((v->>'ok')::boolean, false) is not true then
      insert into public.error_events (source, kind, severity, detail)
      values ('customer_terms_accepted_trg', 'acceptance_record_not_written', 'high',
              jsonb_build_object('customer_id', new.id, 'result', v));
    end if;
  exception when others then
    insert into public.error_events (source, kind, severity, detail)
    values ('customer_terms_accepted_trg', 'acceptance_record_failed', 'high',
            jsonb_build_object('customer_id', new.id, 'sqlstate', sqlstate, 'error', left(sqlerrm, 500)));
  end;
  return new;
end $function$;

revoke all on function public.fn_customer_terms_accepted_trg() from public, anon, authenticated;

drop trigger if exists z56_customer_terms_accepted on public.customers;
create trigger z56_customer_terms_accepted
  after update of tos_accepted_at on public.customers
  for each row
  when (old.tos_accepted_at is null and new.tos_accepted_at is not null)
  execute function public.fn_customer_terms_accepted_trg();

-- Ownership ledger follows the manifest (conventions step 4).
insert into public.kernel_routine_ownership
  (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file, justification)
values
  ('public','fn_customer_terms_accepted_trg','','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT',
   'canonical file scripts/sql/the_acceptance_the_product_writes_reaches_the_kernel.sql','MANIFEST',
   'scripts/sql/the_acceptance_the_product_writes_reaches_the_kernel.sql', null)
on conflict (schema_name, routine_name, identity_args) do update set
  ownership_class = excluded.ownership_class, classified_by_rule = excluded.classified_by_rule,
  evidence = excluded.evidence, source_kind = excluded.source_kind, source_file = excluded.source_file,
  justification = excluded.justification;

do $proof$
declare v_when text;
begin
  select pg_get_triggerdef(t.oid) into v_when from pg_trigger t where t.tgname = 'z56_customer_terms_accepted';
  if v_when is null then raise exception 'z56_customer_terms_accepted is not on public.customers'; end if;
  if position('old.tos_accepted_at IS NULL' in v_when) = 0 or position('AFTER UPDATE OF tos_accepted_at' in v_when) = 0 then
    raise exception 'z56 is not the null -> not-null transition trigger: %', v_when;
  end if;
  if has_function_privilege('anon', 'public.fn_customer_terms_accepted_trg()', 'EXECUTE') then
    raise exception 'fn_customer_terms_accepted_trg is executable by anon';
  end if;
  raise notice 'proof: z56_customer_terms_accepted fires once, on the acceptance transition, and anon cannot execute it';
end $proof$;

commit;
