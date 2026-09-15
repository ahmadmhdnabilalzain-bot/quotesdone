-- THE INVITE COMPOSER CALLS A SENDABILITY CHECK THAT WAS RETIRED UNDER IT — owner: customer_support
--
-- MEASURED 15 SEP 2026. pg_get_functiondef(enqueue_supplier_invites) still contains
--     and (public.fn_email_sendable(l.email)->>'ok')::boolean
-- and pg_proc has no routine of that name. retire_the_routines_no_seat_can_reach.sql dropped it on
-- 8 Sep as unreachable: "0 edge or app callers ... 0 pg_depend edges". Both were true and neither
-- was the question. A PL/pgSQL body calling a routine records no pg_depend edge, so the one live
-- caller was invisible to the closure. Today the composer exits early because invite_enabled and
-- supplier_outreach_golive are 'false'. The first run after the founder opens outreach would raise
-- 42883 and queue nothing.
--
-- WHAT THIS DOES. It restores the routine exactly as it was last defined, in
-- eight_thousand_domains_nobody_had_ever_asked_whether_they_accept_mail.sql. That was the existing
-- check, not a new one: address shape, email_suppressions, email_domain_mx (fail-open) and
-- email_block_pattern. All three tables are live (measured 15 Sep: 14 suppressions, 8,764 domains,
-- the pattern table present). Its DROPPED.txt line is removed in the same change.
--
-- WHAT THIS DOES NOT DO. It does not open outreach, change enqueue_supplier_invites, or touch
-- either switch. It does not retire the dead copies of the composer that are still in older files.
--
-- CREATE grants EXECUTE to PUBLIC. The routine does not exist today, so this is a CREATE and the
-- revoke below is required. There is one overload: (text).

create or replace function public.fn_email_sendable(p_email text)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_e text; v_pat record; v_dom text;
begin
  v_e := lower(btrim(coalesce(p_email,'')));
  if v_e = '' then
    return jsonb_build_object('ok', false, 'reason', 'no address');
  end if;
  if v_e !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$' then
    return jsonb_build_object('ok', false, 'reason', 'not a valid address shape');
  end if;
  if exists (select 1 from email_suppressions s where lower(s.email) = v_e) then
    return jsonb_build_object('ok', false, 'reason', 'suppressed');
  end if;
  v_dom := split_part(v_e, '@', 2);
  if exists (select 1 from email_domain_mx m
              where m.domain = v_dom and m.has_mx = false
                and m.kind in ('nxdomain','no_records')) then
    return jsonb_build_object('ok', false, 'reason', 'domain does not accept mail');
  end if;
  for v_pat in select pattern, reason from email_block_pattern where active loop
    if v_e ~ v_pat.pattern then
      return jsonb_build_object('ok', false, 'reason', v_pat.reason);
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'reason', 'sendable');
end;
$function$;

revoke execute on function public.fn_email_sendable(text) from public, anon, authenticated;

-- The composer reads it as its owner (SECURITY DEFINER), so the revoke does not stop the one caller.
do $$
begin
  if (public.fn_email_sendable('zz-demo-probe@example.invalid')->>'ok') is null then
    raise exception 'fn_email_sendable did not answer';
  end if;
  if (public.fn_email_sendable('not an address')->>'ok')::boolean then
    raise exception 'fn_email_sendable accepted a malformed address';
  end if;
  raise notice 'fn_email_sendable restored: answers, and refuses a malformed address';
end $$;
