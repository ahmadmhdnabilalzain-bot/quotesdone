-- E40 - the same defect one table over, and a third notation for the same amount
--
-- The R7 acceptance passed seven of eight gates and left two findings. Both are third instances of
-- classes this session already closed elsewhere, which is the point: closing a defect on the table
-- I was looking at is not closing the class.
--
-- F1. THE APPROVER COLUMN ANYBODY COULD FILL, ON THE SIBLING REGISTER.
--
-- E36 guarded `phase_c_freeze_amendment.approved_by`. `public.phase_c_change_request` -- the FK
-- target E23 added, the registry that makes a PCCR reference resolve -- carries the SAME
-- approved_by / approved_at pair, has NO triggers at all, and service_role held full write.
-- Measured by the auditor as service_role:
--
--     update public.phase_c_change_request set approved_by = 'zz-r7-auditor-not-the-founder';
--       -- ACCEPTED, 2 rows
--     update public.phase_c_change_request set approved_by = 'ahmadalzain1993@admin.quotesdone.com';
--       -- ACCEPTED, stored verbatim
--
-- It is not a freeze-board bypass -- the board reads that table for EXISTENCE only, and the red
-- stayed red -- but it is a governance register whose approval field any caller could sign in the
-- founder's name. The guard E36 wrote is now shared by both tables rather than copied, so the next
-- table to carry an approver inherits it by naming it.
--
-- F1b. service_role could INSERT into `public.phase_c_frozen_subject` -- the register of WHAT IS
-- FROZEN. Its only guard, a00_phase_c_frozen_subject_immutable, is a DELETE|UPDATE trigger
-- (tgtype 27), so INSERT was never covered. The auditor added one fake subject and took
-- `frozen_subjects_drifted` from `0 of 25` to `1 of 26`, RED. That direction is red-at-will and
-- cannot turn a red green, so it is a nuisance rather than a breach -- but "a register that its own
-- subject can write is not a register" is E38's own sentence, and it applies here too. Measured
-- first: no routine in the estate writes either table; every row in both was written by a migration
-- applied as the owner.
--
-- F1c. That trigger's refusal message is hard-coded to `public.phase_c_founder_approval` while the
-- trigger sits on `phase_c_frozen_subject`, so it names the wrong table and advises "record a NEW
-- row" -- which was the one door standing open. An instrument naming the wrong subject, in the
-- message a person reads when they are already confused.
--
-- F2. A THIRD NOTATION FOR THE SAME AMOUNT. E24 caught numbers, E27 numeric strings, E35 currency
-- prefixes and scientific notation. The auditor found two more, on a money-shaped key that is not
-- an identifier:
--
--     refund_amount_aed: "0x1F"      ACCEPTED   -- hexadecimal
--     refund_amount_aed: "AED٩٩٩"    ACCEPTED   -- Eastern Arabic numerals, ٩٩٩ = 999
--
-- The second is the one that should not have taken four increments to find. This company sells in
-- the UAE. A currency-prefixed amount written in the digit script of its own market is not an edge
-- case, and every regex in the rule anchors on ASCII [0-9]. The rule now also treats a value
-- carrying Arabic-Indic (U+0660..0669) or Extended Arabic-Indic (U+06F0..06F9) digits as a
-- quantity, and matches hexadecimal.
--
-- The identifier exclusion is untouched, so refund_id, invoice_no and price_ref behave exactly as
-- E27 left them, in every notation.

-- ---- F1: one guard, both registers -------------------------------------------------------------
-- Generalised from E36's, which named its table in the message. TG_TABLE_NAME makes it usable by
-- any table carrying an approved_by that must be the founder's, so the next one inherits the guard
-- by attaching it rather than by someone remembering to copy it.
CREATE OR REPLACE FUNCTION public.fn_phase_c_founder_approver_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.approved_by is null then
    return new;
  end if;

  if not exists (
        select 1 from public.phase_c_founder_identity fi
         where fi.active
           and lower(btrim(fi.identity)) = lower(btrim(new.approved_by))) then
    raise exception '%: approved_by % does not resolve to an active identity in public.phase_c_founder_identity. A governance record is approved by the founder or it is not approved. (pccr_approver_not_the_founder)',
      TG_TABLE_NAME, coalesce(nullif(btrim(new.approved_by),''), '(empty)')
      using errcode = '23514';
  end if;

  return new;
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_c_founder_approver_guard() FROM PUBLIC;

DROP TRIGGER IF EXISTS a10_change_request_approver_is_the_founder ON public.phase_c_change_request;
CREATE TRIGGER a10_change_request_approver_is_the_founder
  BEFORE INSERT OR UPDATE OF approved_by, approved_at ON public.phase_c_change_request
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_c_founder_approver_guard();

-- The amendment table moves to the shared guard too, so there is one body to reason about rather
-- than two that must be kept in step. E36's trigger name is kept; only the function it calls moves.
DROP TRIGGER IF EXISTS a10_freeze_amendment_approver_is_the_founder
  ON public.phase_c_freeze_amendment;
CREATE TRIGGER a10_freeze_amendment_approver_is_the_founder
  BEFORE INSERT OR UPDATE OF approved_by, approved_at ON public.phase_c_freeze_amendment
  FOR EACH ROW EXECUTE FUNCTION public.fn_phase_c_founder_approver_guard();

-- ---- F1: neither governance register is writable by the role it governs -------------------------
-- PUBLIC first: a grant held through PUBLIC makes a revoke from a named role a silent no-op.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_c_change_request FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_c_change_request FROM anon, authenticated, service_role;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_c_frozen_subject FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.phase_c_frozen_subject FROM anon, authenticated, service_role;

-- ---- F1c: the message names the table it is attached to -----------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_c_founder_approval_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- E40. This message was hard-coded to `public.phase_c_founder_approval` while the trigger sits on
  -- phase_c_frozen_subject as well, so a person hitting it was told the wrong table -- and then
  -- advised to "record a NEW row", which until this file was the one door standing open on that
  -- register. It names what it is actually protecting now.
  raise exception '% is append-only and its rows are permanent: % is refused. A founder approval and the frozen subjects it covers are the record that everything else is measured against, so they are never edited or deleted -- record a new row through a migration applied as the owner. (phase_c_approval_immutable)',
    TG_TABLE_NAME, TG_OP
    using errcode = '23514';
end
$function$;

COMMENT ON TABLE public.phase_c_change_request IS
  'THE REGISTRY OF PHASE C CHANGE REQUESTS. phase_c_freeze_amendment.change_request_ref is a foreign '
  'key to this table, so it is what makes a PCCR reference resolve. E40 revoked '
  'INSERT/UPDATE/DELETE from service_role, anon, authenticated and PUBLIC and put the founder '
  'approver guard on approved_by, after an acceptance auditor signed both rows in the founder''s '
  'name with only service_role. No routine writes this table; every row came from a migration '
  'applied as the owner.';

-- ---- F2: the money rule reads three more notations ---------------------------------------------
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

    -- A MONEY AMOUNT MAY NOT RIDE IN ON A NON-FINANCIAL OBJECT, AT ANY DEPTH, IN ANY NOTATION.
    -- Three conditions, and the FIRST is the one E27 added: an IDENTIFIER is never an amount.
    -- `refund_id`, `invoice_no`, `price_ref` name things; whether their value happens to be numeric
    -- is irrelevant, and E24 got this wrong by allowing a numeric string without excluding them.
    if coalesce(b.policy_family,'') <> 'TRANSACTION_RECORD' then
      select array_agg(distinct k order by k) into v_money
        from jsonb_path_query(new.payload, '$.**') node,
             lateral jsonb_each(case when jsonb_typeof(node) = 'object' then node else '{}'::jsonb end) e(k, v)
       where k !~* '_(id|ref|no|key|code)$'
         and (k ~* '(^|_)(amount|price|charge|payout|subtotal|total|fee|cost|refund|invoice)(_|$)'
              or k ~* '_(aed|usd|eur|gbp)$')
         and (jsonb_typeof(v) = 'number'
              -- E35. THE STRING ARM REQUIRED A WHOLLY NUMERIC STRING, so two notations for the
              -- same amount walked past it and the R4 acceptance named both:
              --     refund_amount_aed: "AED 999999"   ACCEPTED - a currency prefix
              --     refund_amount_aed: "1e6"          ACCEPTED - scientific notation
              -- Neither is an identifier and neither was ever going to be one: they are quantities
              -- written the way a person and a JSON serialiser respectively write them. A rule that
              -- reads a number but not the same number with AED in front of it is testing the
              -- notation, not the subject.
              --
              -- The identifier exclusion above still settles those cases first and is unchanged, so
              -- refund_id, invoice_no and price_ref are as accepted as they were after E27 -
              -- whatever notation their value takes.
              --
              -- The third residual note the audit raised, price_code: 999999, is NOT closed here
              -- and I am not pretending it is. `_code` is on the identifier-exclusion list by
              -- deliberate choice in E27, the auditor judged that trade correct, and widening the
              -- money side to reach it would put every *_code key back in front of the rule that
              -- blocked eleven legitimate workflows. It is a named hole, and it stays named.
              -- E40. A THIRD AND FOURTH NOTATION, AND THE SECOND ONE SHOULD NOT HAVE TAKEN FOUR
              -- INCREMENTS TO FIND. E24 caught numbers, E27 numeric strings, E35 currency prefixes
              -- and scientific notation; the R7 acceptance found two more on a money-shaped
              -- non-identifier key:
              --     refund_amount_aed: "0x1F"      ACCEPTED -- hexadecimal
              --     refund_amount_aed: "AED٩٩٩"    ACCEPTED -- ٩٩٩ is 999
              -- This company sells in the UAE. An amount written in the digit script of its own
              -- market is not an edge case, and every arm of this rule anchored on ASCII [0-9].
              or (jsonb_typeof(v) = 'string'
                  and (v #>> '{}' ~* '^[[:space:]]*(aed|usd|eur|gbp|\$|€|£)?[[:space:]]*-?[0-9][0-9,]*(\.[0-9]+)?([eE][+-]?[0-9]+)?[[:space:]]*(aed|usd|eur|gbp)?[[:space:]]*$'
                       or v #>> '{}' ~* '^[[:space:]]*(aed|usd|eur|gbp|\$|€|£)?[[:space:]]*0x[0-9a-f]+[[:space:]]*$'
                       -- Arabic-Indic U+0660..0669 and Extended Arabic-Indic U+06F0..06F9. A
                       -- money-shaped key that is not an identifier, carrying digits in any script,
                       -- is carrying a quantity.
                       or v #>> '{}' ~ '[٠-٩۰-۹]')));
      if v_money is not null then
        raise exception 'phase_d_object_record: % is a %-family object and its payload carries money amount(s) [%] — a money-shaped key that is not an identifier, holding a quantity, at any depth. Only a TRANSACTION_RECORD object may. (pd_object_money_key_on_non_financial_object)',
          new.object_id, b.policy_family, array_to_string(v_money, ', ') using errcode = '23514';
      end if;
    end if;
  end if;

  return new;
end $function$;

-- ---- E37's lesson, again, because a new trigger makes a table ENFORCING -------------------------
-- E37 existed because E36's trigger moved phase_c_freeze_amendment into the population
-- fn_kernel_truncate_protection_state watches. The trigger this file puts on
-- phase_c_change_request does the same thing: 80 watched -> 81, and
-- enforcing_tables_without_a_truncate_guard went red at 1 of 81 within the same measurement.
--
-- Same remedy, same statements the estate runs over the other 80. The TRUNCATE grant is already
-- revoked above; this attaches the guard. Not disclosed as a gap: a governance register anybody can
-- TRUNCATE is the hole this file exists to close, and emptying phase_c_change_request would break
-- the foreign key that makes every amendment's PCCR reference resolve.
DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_c_change_request;
CREATE TRIGGER z00_kernel_truncate_guard
  BEFORE TRUNCATE ON public.phase_c_change_request
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();
