-- E35 - two notations for the same amount that the money rule read as text
--
-- The R4 independent acceptance drove the money rule 18 ways and 15 of 15 declared expectations
-- matched. It then named three residual notes it had found and the builder had not, and scored
-- them LOW because each needs an attacker who controls the key name, on a non-financial object, on
-- a path that cannot execute. Two of the three are the same defect and are closed here:
--
--     refund_amount_aed: "AED 999999"   was ACCEPTED - the string arm wanted a wholly numeric string
--     refund_amount_aed: "1e6"          was ACCEPTED - scientific notation is not [0-9]+(.[0-9]+)?
--
-- Both are quantities on a money-shaped key that is not an identifier. The rule was reading the
-- NOTATION rather than the subject, which is the same shape as a check that reads a key's presence
-- rather than what it refers to - the thing that took thirteen rules to clear in E30 and E31.
--
-- THE THIRD NOTE IS NOT CLOSED AND SAYING SO IS THE POINT. price_code: 999999 is accepted because
-- `_code` is on E27's identifier-exclusion list. E27 exists because my own money rule, widened
-- without that list, refused eleven legitimate workflows on refund_id. The auditor judged the trade
-- correct and I agree with him. It stays a named hole rather than a fixed one.
--
-- The identifier exclusion is untouched, so every case E27 was written to protect behaves exactly
-- as it did: refund_id, invoice_no and price_ref are accepted whatever notation their value takes.
--
-- CREATE OR REPLACE preserves the ACL. This is a trigger function; the trigger itself is unchanged.

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
              or (jsonb_typeof(v) = 'string'
                  and v #>> '{}' ~* '^[[:space:]]*(aed|usd|eur|gbp|\$|€|£)?[[:space:]]*-?[0-9][0-9,]*(\.[0-9]+)?([eE][+-]?[0-9]+)?[[:space:]]*(aed|usd|eur|gbp)?[[:space:]]*$'));
      if v_money is not null then
        raise exception 'phase_d_object_record: % is a %-family object and its payload carries money amount(s) [%] — a money-shaped key that is not an identifier, holding a quantity, at any depth. Only a TRANSACTION_RECORD object may. (pd_object_money_key_on_non_financial_object)',
          new.object_id, b.policy_family, array_to_string(v_money, ', ') using errcode = '23514';
      end if;
    end if;
  end if;

  return new;
end $function$;
