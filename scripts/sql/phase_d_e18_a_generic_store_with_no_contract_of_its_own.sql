-- E18 — a generic store with no contract of its own
--
-- MEASURED 2026-08-20. `public.phase_d_object_record` carries exactly five constraints: the primary
-- key, the `(object_id, business_key, version)` unique key, the `object_id` foreign key to
-- `phase_b_business_object`, the `superseded_by` self-foreign-key, and `payload_not_empty`.
-- `state` is `text NOT NULL` with no domain of any kind, and no object has a payload contract. 56
-- business objects share one untyped table. Both acceptance audits recorded this unchanged.
--
-- Two things are added, both derived from declarations that already exist and both enforced by a
-- TRIGGER rather than by the write service. The service is not the only door — the table is — and a
-- rule that lives in one caller is a convention, not a contract. This estate has been caught by
-- that difference before.
--
-- ---- 1. A STATE DOMAIN, PER OBJECT, DERIVED FROM ITS POLICY FAMILY ---------------------------
-- `phase_d_business_object_binding.policy_family` is already machine-readable and already assigned
-- to all 56 objects: VERSIONED 10, CASE_RECORD 13, APPEND_ONLY 12, IMMUTABLE_REVISION 12,
-- MUTABLE_CONTROLLED 5, TRANSACTION_RECORD 4. The frozen registry's own `mutation_rule` says what
-- each family does with a record, and the state set follows from it:
--
--   VERSIONED            superseded, never overwritten          open, superseded
--   IMMUTABLE_REVISION   a new revision, never an edit          open, issued, approved, superseded
--   APPEND_ONLY          append-only history                    open, recorded
--   CASE_RECORD          a case that moves and closes           open, in_progress, resolved, closed
--   MUTABLE_CONTROLLED   moves under control                    open, active, closed
--   TRANSACTION_RECORD   money, which settles or does not       open, pending, settled, refunded, failed
--
-- `open` is in every set because `fn_phase_d_object_write` defaults to it, and a default outside its
-- own domain would make the very first write fail. `review_record` additionally carries the three
-- verdicts, because `fn_phase_d_effect_produce` writes `coalesce(state, payload->>'verdict')` for
-- every REVIEW_VERDICT step and those verdicts ARE its states.
--
-- The family-to-states mapping is an engineering judgement and is recorded as such in
-- `derived_from`, per row. What is NOT a judgement is that the domain is now closed: a state outside
-- it is refused at the table, and the refusal names the object, the state and the permitted set.
--
-- ---- 2. A PAYLOAD CONTRACT WITH TEETH --------------------------------------------------------
-- A payload contract that lists the keys the code already writes would pass forever and catch
-- nothing — an expectation typed into the check it guards. So the payload rules here are the ones
-- that can actually fire:
--
--   * `owner_scope` must equal the object's declared `ownership_scope`. The write service reads it
--     from the binding today; the trigger makes that true of every writer.
--   * `owner_ref` must be present and non-empty. Every one of the 56 objects declares an ownership
--     scope of COMPANY, CUSTOMER or SUPPLIER — there is no unowned object — so a record with no
--     owner is a record nobody is accountable for.
--   * A MONEY KEY MAY NOT RIDE IN ON A NON-FINANCIAL OBJECT. The 2026-08-20 audit injected
--     `refund_amount_aed: 999999` into an input payload and it validated true; E16 closed that at
--     the schema, and this closes it at the table, because the payload of a business object is
--     where such a key would have landed. Only TRANSACTION_RECORD objects may carry one, and even
--     there the founder's standing rule — every refund needs him, any amount — is enforced
--     elsewhere and untouched by this.
--
-- The trigger pins its own search_path. A trigger function runs with the WRITER's search_path unless
-- it sets one, which is how a guard ends up reading a shadowed table.
--
-- Name: z40_ prefix, so it fires after the a00_ kernel guards and before z90_ freeze guards.
-- Postgres fires triggers of the same timing in NAME order, which is why the prefixes exist.

create table if not exists public.phase_d_object_state_contract (
  object_id       text primary key references public.phase_b_business_object(object_id),
  policy_family   text not null,
  allowed_states  text[] not null,
  initial_state   text not null,
  derived_from    text not null,
  recorded_at     timestamptz not null default now(),
  constraint phase_d_object_state_contract_initial_is_allowed
    check (initial_state = any (allowed_states)),
  constraint phase_d_object_state_contract_states_not_empty
    check (cardinality(allowed_states) > 0)
);

insert into public.phase_d_object_state_contract
  (object_id, policy_family, allowed_states, initial_state, derived_from)
select b.object_id, b.policy_family,
       case b.policy_family
         when 'VERSIONED'          then array['open','superseded']
         when 'IMMUTABLE_REVISION' then array['open','issued','approved','superseded']
         when 'APPEND_ONLY'        then array['open','recorded']
         when 'CASE_RECORD'        then array['open','in_progress','resolved','closed']
         when 'MUTABLE_CONTROLLED' then array['open','active','closed']
         when 'TRANSACTION_RECORD' then array['open','pending','settled','refunded','failed']
         else array['open']
       end
       || case when b.object_id = 'review_record'
               then array['approved','rejected','changes_requested'] else array[]::text[] end,
       'open',
       format('policy_family %s from phase_d_business_object_binding; mutation_rule %L from the '
              || 'frozen phase_b_business_object. open is in every set because '
              || 'fn_phase_d_object_write defaults to it.%s',
              b.policy_family, coalesce(o.mutation_rule,'(none)'),
              case when b.object_id = 'review_record'
                   then ' review_record also carries the three verdicts, because '
                        || 'fn_phase_d_effect_produce writes coalesce(state, payload->>''verdict'') '
                        || 'for every REVIEW_VERDICT step.' else '' end)
  from public.phase_d_business_object_binding b
  join public.phase_b_business_object o on o.object_id = b.object_id
on conflict (object_id) do update
  set policy_family  = excluded.policy_family,
      allowed_states = excluded.allowed_states,
      initial_state  = excluded.initial_state,
      derived_from   = excluded.derived_from;

CREATE OR REPLACE FUNCTION public.fn_phase_d_object_record_contract()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c public.phase_d_object_state_contract%rowtype;
  b public.phase_d_business_object_binding%rowtype;
  v_money text[];
begin
  select * into c from public.phase_d_object_state_contract where object_id = new.object_id;
  if not found then
    -- FAIL CLOSED. An object with no state contract is a gap in the registry, not a licence.
    raise exception 'phase_d_object_record: object % has no row in phase_d_object_state_contract, so there is no domain to check its state against. Register the object before writing it. (pd_object_no_state_contract)',
      new.object_id using errcode = '23514';
  end if;

  if not (new.state = any (c.allowed_states)) then
    -- RAISE has no %L. It is a format() placeholder, and using it here printed the state followed
    -- by a stray "L" until this line said so.
    raise exception 'phase_d_object_record: % is a %-family object and state "%" is not one of [%]. (pd_object_state_outside_domain)',
      new.object_id, c.policy_family, new.state, array_to_string(c.allowed_states, ', ')
      using errcode = '23514';
  end if;

  select * into b from public.phase_d_business_object_binding where object_id = new.object_id;
  if found then
    if new.owner_scope is distinct from b.ownership_scope then
      raise exception 'phase_d_object_record: % declares ownership_scope % and this record carries %. The scope is the object''s, not the caller''s. (pd_object_owner_scope_mismatch)',
        new.object_id, coalesce(b.ownership_scope,'(none)'), coalesce(new.owner_scope,'(none)')
        using errcode = '23514';
    end if;

    -- Every one of the 56 objects is owned by COMPANY, CUSTOMER or SUPPLIER. There is no unowned
    -- object, so an empty owner_ref is a record nobody is accountable for.
    if coalesce(btrim(coalesce(new.owner_ref,'')),'') = '' then
      raise exception 'phase_d_object_record: % is owned at % scope and this record names no owner_ref. (pd_object_owner_missing)',
        new.object_id, coalesce(b.ownership_scope,'(unstated)') using errcode = '23514';
    end if;

    -- A MONEY KEY ON A NON-FINANCIAL OBJECT. Matched on the key name at the top level of the
    -- payload, which is where an injected key lands: fn_phase_d_handler_execute passes the resolved
    -- input object straight through as the payload.
    if coalesce(b.policy_family,'') <> 'TRANSACTION_RECORD' then
      select array_agg(k order by k) into v_money
        from jsonb_object_keys(new.payload) k
       where k ~* '(^|_)(refund|amount|fee|price|charge|payout|invoice)(_|$)'
          or k ~* '_aed$';
      if v_money is not null then
        raise exception 'phase_d_object_record: % is a %-family object and its payload carries money key(s) [%]. Only a TRANSACTION_RECORD object may. (pd_object_money_key_on_non_financial_object)',
          new.object_id, b.policy_family, array_to_string(v_money, ', ') using errcode = '23514';
      end if;
    end if;
  end if;

  return new;
end $function$;

drop trigger if exists z40_phase_d_object_record_contract on public.phase_d_object_record;
create trigger z40_phase_d_object_record_contract
  before insert or update on public.phase_d_object_record
  for each row execute function public.fn_phase_d_object_record_contract();

-- A trigger function CREATEd in public arrives EXECUTE-to-PUBLIC like any other. It can only be
-- invoked by the trigger, but the grant is still a grant.
revoke execute on function public.fn_phase_d_object_record_contract() from public;
revoke execute on function public.fn_phase_d_object_record_contract() from anon;
revoke execute on function public.fn_phase_d_object_record_contract() from authenticated;

revoke all on public.phase_d_object_state_contract from public;
revoke all on public.phase_d_object_state_contract from anon;
revoke all on public.phase_d_object_state_contract from authenticated;
alter table public.phase_d_object_state_contract enable row level security;

do $$
declare v_objects int; v_contracts int; v_no_initial int;
begin
  select count(*) into v_objects   from public.phase_d_business_object_binding;
  select count(*) into v_contracts from public.phase_d_object_state_contract;
  select count(*) into v_no_initial from public.phase_d_object_state_contract
   where not (initial_state = any (allowed_states));
  if v_contracts <> v_objects then
    raise exception 'E18: % bound business objects but % state contracts. Every object needs one, because the trigger fails closed without it.',
      v_objects, v_contracts;
  end if;
  if v_no_initial > 0 then
    raise exception 'E18: % contracts whose initial_state is outside their own allowed_states', v_no_initial;
  end if;
end $$;
