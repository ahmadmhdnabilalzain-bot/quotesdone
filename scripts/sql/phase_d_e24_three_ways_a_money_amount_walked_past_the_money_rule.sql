-- E24 — three ways a money amount walked past the money rule
--
-- The R3 independent acceptance drove eleven probes at the E18 object-record trigger. Nine behaved:
-- a state outside its family's domain, a wrong owner scope, an empty owner, an unregistered object
-- and an empty payload were all refused, and a valid write plus a money amount on a
-- TRANSACTION_RECORD object were both accepted. Three got through where a refusal was expected:
--
--   * `cost_usd: 50000`                      — the name pattern was (amount|price|charge|payout|
--                                              subtotal|total) or `_aed$`. "cost" is in neither, and
--                                              neither is a currency this company does not bill in.
--   * `refund_amount_aed: "999999"` (string) — the guard required jsonb_typeof = 'number'.
--   * `{"nested":{"refund_amount_aed":999999}}` — the guard read top-level keys only.
--
-- The auditor scored these LOW and was right to: the money rule is defence-in-depth over the state,
-- scope and owner contract, which is the part that actually holds, and the nesting limit was
-- disclosed in the trigger's own comment. Disclosed is not the same as adequate, and all three are
-- closed here.
--
-- WHAT THE RULE NOW IS, stated so the next person can argue with it. A payload key is a money amount
-- when its NAME says money and its VALUE is a quantity, at ANY depth:
--   * name:  amount | price | charge | payout | subtotal | total | fee | cost | refund | invoice,
--            as a whole word; or a currency suffix `_aed` / `_usd` / `_eur` / `_gbp`.
--   * value: a JSON number, OR a string that is entirely numeric — "999999" is a quantity written
--            with quotes round it, and a guard that accepts it is a guard with a typo for a door.
-- Both halves are still required, which is what keeps `refund_id: "RF-1"` and `fee_status: "paid"`
-- acceptable on a non-financial object: the first is an identifier and the second is a state, and
-- neither is a quantity. The R3 probe list is the regression suite for exactly that.
--
-- The recursive walk uses jsonb_path_query over `$.**` so a money amount cannot be smuggled one
-- level down inside an otherwise innocent object.
--
-- CREATE OR REPLACE preserves the ACL. No grant changes here.

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

    -- E24. A MONEY AMOUNT MAY NOT RIDE IN ON A NON-FINANCIAL OBJECT, AT ANY DEPTH, IN ANY NOTATION.
    -- Both halves are required — a money NAME and a quantity VALUE — which is what keeps an
    -- identifier (refund_id) and a state (fee_status) acceptable while an amount is not.
    if coalesce(b.policy_family,'') <> 'TRANSACTION_RECORD' then
      select array_agg(distinct k order by k) into v_money
        from jsonb_path_query(new.payload, '$.**') node,
             lateral jsonb_each(case when jsonb_typeof(node) = 'object' then node else '{}'::jsonb end) e(k, v)
       where (k ~* '(^|_)(amount|price|charge|payout|subtotal|total|fee|cost|refund|invoice)(_|$)'
              or k ~* '_(aed|usd|eur|gbp)$')
         and (jsonb_typeof(v) = 'number'
              or (jsonb_typeof(v) = 'string' and v #>> '{}' ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$'));
      if v_money is not null then
        raise exception 'phase_d_object_record: % is a %-family object and its payload carries money amount(s) [%] — a money-shaped key holding a quantity, at any depth. Only a TRANSACTION_RECORD object may. (pd_object_money_key_on_non_financial_object)',
          new.object_id, b.policy_family, array_to_string(v_money, ', ') using errcode = '23514';
      end if;
    end if;
  end if;

  return new;
end $function$;
