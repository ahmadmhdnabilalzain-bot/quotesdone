-- PROBE: an unsubscribe stops the nudge of an unopened invitation, and nothing transactional (28 Oct 2026, sales_engineer;
-- ledger 1401 audit, S6). Pure probe, no DDL: run it AFTER a_supplier_who_says_not_interested_is_never_mailed_again.sql,
-- or with it in ONE rolled-back request (scripts/lib/safe_replay.mjs). It always ends in raise exception 'CHK<<...>>', so
-- nothing it does survives. It writes nothing at all, and reads no person: only the list and the rule.
-- PROBE OK only if: the list names the four cold-outreach types; an unsubscribe stops each of them; it stops none of the
-- transactional types a registered supplier must still receive; a bounce still stops everything.
do $probe$
declare v_fail text := ''; t text;
begin
  if not (public.fn_opt_out_types() @> array['supplier_invite', 'supplier_invite_nudge', 'supplier_registration_reminder', 'supplier_rfq_widened_invite']
          and cardinality(public.fn_opt_out_types()) = 4) then
    v_fail := v_fail || ' list=' || array_to_string(public.fn_opt_out_types(), ',');
  end if;
  foreach t in array array['supplier_invite', 'supplier_invite_nudge', 'supplier_registration_reminder', 'supplier_rfq_widened_invite'] loop
    if not public.fn_suppression_stops('unsubscribe', t) then v_fail := v_fail || ' unsubscribe does not stop ' || t || ';'; end if;
  end loop;
  foreach t in array array['new_inquiry', 'rfq_quote_reminder', 'rfq_short_of_quotes', 'reveal_outcome_check', 'registration_received', 'supplier_approved'] loop
    if public.fn_suppression_stops('unsubscribe', t) then v_fail := v_fail || ' unsubscribe stops transactional ' || t || ';'; end if;
    if not public.fn_suppression_stops('hard_bounce:permanent', t) then v_fail := v_fail || ' a bounce does not stop ' || t || ';'; end if;
  end loop;
  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK an unsubscribe stops supplier_invite_nudge and the three cold types, and no transactional mail'
                                   else 'PROBE FAILED:' || v_fail end;
end $probe$;
