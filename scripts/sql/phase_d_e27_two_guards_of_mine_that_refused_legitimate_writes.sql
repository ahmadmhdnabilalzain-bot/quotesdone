-- E27 — two guards of mine that refused legitimate writes
--
-- Both defects are my own, both were introduced this session, and both were caught by regenerating
-- the workflow deliverable after E25/E26 and reading the numbers instead of the exit code:
-- business effects fell from 104 to 39 and deterministic closure from 7 of 30 back to 2 of 30. A
-- guard that blocks real work is not a stricter guard, it is an outage.
--
-- ---- 1. `refund_id` CAUGHT AGAIN — E24 UNDID THE CONTROL E18 ADDED ---------------------------
-- E18's money rule matched any key containing "refund" and refused a `growth_program` payload
-- carrying `refund_id`. I narrowed it to a money NAME plus a numeric VALUE and added a committed
-- control for exactly that case. Then E24, closing three real bypasses the R3 acceptance found,
-- widened the name list to include `refund` again AND allowed a numeric STRING as a quantity — and
-- the fixture context supplies `refund_id` as a numeric string, so it matched both halves. Eleven
-- workflows stopped at their first step.
--
-- My control did not catch it because I wrote the payload as `refund_id: 'RF-1'`, which is not
-- numeric. The control tested the case I had in mind rather than the case the estate produces.
--
-- The rule the whole thing was missing: **an IDENTIFIER is never an amount, whatever it looks
-- like.** A key ending `_id`, `_ref`, `_no`, `_key` or `_code` names a thing, not a quantity of
-- money, and no value it holds changes that. That exclusion is checked first and settles it.
-- Both R3 bypasses that motivated E24 — `cost_usd: 50000` and `refund_amount_aed: "999999"` —
-- survive it untouched, because neither is an identifier.
--
-- ---- 2. THE FAMILY STATE SETS WERE TOO NARROW ------------------------------------------------
-- E18 gave each policy family a state domain and its own header called the family-to-states mapping
-- an engineering judgement. It was, and it was wrong in four places. A full driven probe refused:
--
--   supplier_terms_acceptance   `accepted`   APPEND_ONLY had only open, recorded
--   supplier_verification_case  `verified`   CASE_RECORD had only open, in_progress, resolved, closed
--   quotation_revision          `submitted`  IMMUTABLE_REVISION had only open, issued, approved, superseded
--   customer_selection          `selected`   APPEND_ONLY again
--
-- Every one of those is a legitimate state of its object's lifecycle. I checked whether the estate
-- declares the answer anywhere before choosing again: `phase_d_business_object_binding.status_model`
-- reads, for all four, *"state on public.phase_d_object_record; open by default, moved only where
-- the family allows"*, and `phase_d_step_effect.expected_state_transition` repeats the same
-- sentence. Three of 56 bindings carry a parseable enumeration. So the FAMILY genuinely is the
-- declared authority and the words in each set are mine — which is what `derived_from` says, and it
-- now also records that the sets were corrected here and why.
--
-- The domain still constrains: `ADMIN_OVERRIDE` and `NOT_A_STATE` are still refused, and the
-- committed regression suite drives both directions.
--
-- CREATE OR REPLACE preserves the ACL.

update public.phase_d_object_state_contract c
   set allowed_states = case c.policy_family
         when 'VERSIONED'          then array['open','active','superseded','published']
         when 'IMMUTABLE_REVISION' then array['open','issued','submitted','approved','rejected','superseded']
         when 'APPEND_ONLY'        then array['open','recorded','accepted','selected','logged']
         when 'CASE_RECORD'        then array['open','in_progress','verified','resolved','closed','rejected']
         when 'MUTABLE_CONTROLLED' then array['open','active','suspended','closed']
         when 'TRANSACTION_RECORD' then array['open','pending','settled','refunded','failed','reconciled']
         else array['open']
       end
       || case when c.object_id = 'review_record'
               then array['changes_requested'] else array[]::text[] end,
       derived_from = c.derived_from
         || ' | E27, 2026-08-20: the set was WIDENED after a full driven probe refused four '
         || 'legitimate states — accepted (supplier_terms_acceptance), verified '
         || '(supplier_verification_case), submitted (quotation_revision) and selected '
         || '(customer_selection). status_model for all four says only "open by default, moved '
         || 'only where the family allows", and just 3 of 56 bindings carry a parseable '
         || 'enumeration, so the family is the declared authority and the words are an '
         || 'engineering judgement — one that was too narrow and is corrected here.';

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
              or (jsonb_typeof(v) = 'string' and v #>> '{}' ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$'));
      if v_money is not null then
        raise exception 'phase_d_object_record: % is a %-family object and its payload carries money amount(s) [%] — a money-shaped key that is not an identifier, holding a quantity, at any depth. Only a TRANSACTION_RECORD object may. (pd_object_money_key_on_non_financial_object)',
          new.object_id, b.policy_family, array_to_string(v_money, ', ') using errcode = '23514';
      end if;
    end if;
  end if;

  return new;
end $function$;
