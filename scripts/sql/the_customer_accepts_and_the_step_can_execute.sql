-- THE ACCEPTANCE RECORD THE KERNEL CAN REFERENCE, AND THE RE-DISPATCH THAT LETS W04-S01 EXECUTE
-- (6 Sep 2026).
--
-- When a customer accepts the Terms in the portal, kyc.accept_terms writes customers.tos_accepted_at,
-- tos_version, tos_ip and (via compliance_archive) the signed_terms_* PDF. What it never wrote was an
-- acceptance RECORD the kernel could reference: BR-025 (terms_version + terms_hash) and BR-026
-- (acceptance_ref) both read public.phase_d_object_record, and with no customer_terms_acceptance row
-- W04-S01 refused (pd_rule_refused) on every dispatch. The step therefore sat 'active' forever with
-- no re-entry point -- a finished onboarding the kernel could not certify.
--
-- fn_customer_terms_accept closes both halves, deterministically, owned by cs_onboarding:
--   1. It reads the CURRENTLY PUBLISHED customer terms from public.legal_documents (via the
--      registry public.phase_d_acceptance_document, object customer_terms_acceptance -> slug
--      customer-terms) and takes the version and the sha256 of body_html from there -- so the pair
--      recorded is exactly the pair BR-025 checks against, never a caller-supplied string.
--   2. It writes an APPEND_ONLY customer_terms_acceptance record through the canonical writer
--      fn_phase_d_object_write, owned by the customer, carrying {terms_version, terms_hash, ...}.
--      fn_phase_d_step_context now answers terms_version, terms_hash AND acceptance_ref from that
--      record (see scripts/sql/acceptance_ref_resolves_from_the_record_the_party_owns.sql).
--   3. It re-dispatches the open W04-S01 through the SAME canonical door the kernel uses,
--      public.fn_phase_d_dispatch_step -- not re-implemented -- so the step now reaches EXECUTED and
--      leaves a public.phase_d_effect_ledger row.
--
-- Idempotent: the acceptance record is written once per (customer, version); a second call reuses it.
-- The re-dispatch idempotency key is stable, so fn_phase_d_effect_produce dedupes the effect.
--
--   node scripts/apply_sql.mjs scripts/sql/the_customer_accepts_and_the_step_can_execute.sql --apply --ddl

begin;

-- THE OWNER OF A CUSTOMER ACCOUNT IS ITS OWN ID. The customer_account write map carried
-- owner_column = NULL, so fn_phase_d_step_context returned row_owner_ref = null, so
-- fn_phase_d_dispatch_step could derive no owner_ref for a CUSTOMER-scoped write and W04-S01 refused
-- one layer past the terms rules with pd_effect_owner_or_key_missing ("writes customer_account and
-- the call names no owner_ref"). A customer owns their own account: the owner IS the row's identity,
-- public.customers.id. Naming it makes the owner resolvable for every W04 step that writes the
-- account, without touching a single function. Measured: with this set, W04-S01 re-dispatch reaches
-- EXECUTED and leaves a phase_d_effect_ledger row (public.customers:id=<uuid>).
update public.phase_d_object_write_map set owner_column = 'id'
 where object_id = 'customer_account' and coalesce(btrim(owner_column),'') = '';

create or replace function public.fn_customer_terms_accept(p_customer_id uuid, p_ip text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  c            public.customers%rowtype;
  v_slug       text;
  v_version    text;
  v_digest     text;
  v_bkey       text;
  v_owner      text := p_customer_id::text;
  v_existing   text;
  v_write      jsonb;
  v_acc_ref    text;
  v_run        bigint;
  v_step_run   bigint;
  v_actor      text;
  v_disp       jsonb := null;
  v_effect     bigint := null;
begin
  select * into c from public.customers where id = p_customer_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no such customer ' || p_customer_id);
  end if;

  -- The document this acceptance object accepts, and its published version + digest (never trusted
  -- from the caller). This is the same relation and pair BR-025 judges against.
  select a.document_slug into v_slug
    from public.phase_d_acceptance_document a where a.object_id = 'customer_terms_acceptance';
  v_slug := coalesce(v_slug, 'customer-terms');
  -- The currently published document: newest effective_date wins (version is a label, not an order).
  select d.version, encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex')
    into v_version, v_digest
    from public.legal_documents d where d.slug = v_slug
    order by d.effective_date desc nulls last, d.version desc limit 1;
  if v_version is null then
    return jsonb_build_object('ok', false, 'reason', 'no published document for slug ' || v_slug);
  end if;

  -- Keep the product's own fast-path columns in step, idempotently.
  update public.customers
     set tos_accepted_at = coalesce(tos_accepted_at, now()),
         tos_version = v_version,
         tos_ip = coalesce(nullif(btrim(p_ip),''), tos_ip)
   where id = p_customer_id;

  -- One acceptance record per (customer, version). APPEND_ONLY refuses a second write to a key that
  -- already holds a record, so reuse the current one rather than let that surface as an error.
  v_bkey := v_owner || ':' || v_version;
  select o.business_key into v_existing
    from public.phase_d_object_record o
   where o.object_id = 'customer_terms_acceptance' and o.business_key = v_bkey
     and o.superseded_by is null
   order by o.record_id desc limit 1;

  if v_existing is not null then
    v_acc_ref := v_existing;
  else
    v_write := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id',   'customer_terms_acceptance',
      'business_key', v_bkey,
      'owner_ref',    v_owner,
      'state',        'accepted',
      'created_by',   'customer_onboarding',
      'payload', jsonb_build_object(
        'terms_version', v_version,
        'terms_hash',    v_digest,
        'accepted_at',   to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'ip',            nullif(btrim(p_ip),''),
        'document_slug', v_slug,
        'source',        'kyc.accept_terms')));
    v_acc_ref := coalesce(v_write->>'business_key', v_bkey);
  end if;

  -- Re-dispatch the open W04-S01 for this customer through the canonical door. The kernel opened it
  -- on registration; nothing re-entered it after the refusal. With the acceptance now on record,
  -- terms_version, terms_hash and acceptance_ref all resolve and the step can execute.
  select r.run_id into v_run
    from public.phase_c_workflow_run r
   where r.workflow_id = 'W04'
     and r.business_object_id = 'customer_account:' || v_owner
     and r.state not in ('closed','cancelled','failed','completed')
   order by r.run_id desc limit 1;

  if v_run is not null then
    select sr.step_run_id, sr.accountable_role_id into v_step_run, v_actor
      from public.phase_c_workflow_step_run sr
     where sr.run_id = v_run and sr.step_id = 'W04-S01' and sr.state = 'active'
     order by sr.step_run_id desc limit 1;

    if v_step_run is not null then
      v_disp := public.fn_phase_d_dispatch_step(jsonb_build_object(
        'step_run_id',   v_step_run,
        'actor_role_id', coalesce(v_actor, 'customer_onboarding'),
        'opened_by_kind','terms_accepted',
        'opened_by_ref', 'fn_customer_terms_accept:' || v_owner,
        'idempotency_key','W04-accept:' || v_run || ':W04-S01'));
      v_effect := nullif(v_disp->>'effect_id','')::bigint;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'acceptance_ref', v_acc_ref,
    'terms_version', v_version,
    'terms_hash', v_digest,
    'run_id', v_run,
    'step_run_id', v_step_run,
    'dispatch_outcome', v_disp->>'outcome',
    'effect_id', v_effect,
    'dispatch', v_disp);
end $function$;

revoke all on function public.fn_customer_terms_accept(uuid, text) from public, anon, authenticated;
grant execute on function public.fn_customer_terms_accept(uuid, text) to service_role;

insert into public.kernel_routine_ownership
  (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file, justification)
values
  ('public','fn_customer_terms_accept','p_customer_id uuid, p_ip text','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT',
   'canonical file scripts/sql/the_customer_accepts_and_the_step_can_execute.sql','MANIFEST',
   'scripts/sql/the_customer_accepts_and_the_step_can_execute.sql', null)
on conflict (schema_name, routine_name, identity_args) do update set
  ownership_class = excluded.ownership_class, classified_by_rule = excluded.classified_by_rule,
  evidence = excluded.evidence, source_kind = excluded.source_kind, source_file = excluded.source_file,
  justification = excluded.justification;

do $proof$
declare v text;
begin
  select owner_column into v from public.phase_d_object_write_map where object_id = 'customer_account';
  if coalesce(btrim(v),'') <> 'id' then
    raise exception 'customer_account write map owner_column is % (expected id) — the effect owner will not resolve', coalesce(v,'(null)');
  end if;
  raise notice 'proof: customer_account owner_column = id; fn_customer_terms_accept present';
end $proof$;

commit;
