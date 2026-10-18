-- Seat: it_engineer (release operator). 6 Oct 2026.
-- #1237 (a_person_can_get_a_copy_...sql) added fn_email_sendable(text, text) and made that file the canonical
-- home of fn_email_sendable, but it does not define the one-argument form, which stays live (invitation
-- eligibility, outreach and scorecard callers). canonical_routine_manifest then reports "1 deployed body not in
-- the canonical file" on main and the release train releases nothing. This file restates BOTH overloads,
-- byte-for-byte the bodies already live (the (text) body from
-- the_invite_composer_calls_a_sendability_check_that_was_retired_under_it.sql, the (text,text) body from #1237),
-- so behaviour does not change; it only gives the routine one canonical file that names every live overload.
-- Both are CREATE OR REPLACE over existing routines (ACL preserved); the revokes are restated for both signatures.
-- Prevented by: scripts/checks/canonical_routine_manifest.mjs (fails while a live overload has no canonical body).

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

create or replace function public.fn_email_sendable(p_email text, p_type text)
returns jsonb
language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_e text; v_pat record; v_dom text;
begin
  v_e := lower(btrim(coalesce(p_email, '')));
  if v_e = '' then return jsonb_build_object('ok', false, 'reason', 'no address'); end if;
  if v_e !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$' then
    return jsonb_build_object('ok', false, 'reason', 'not a valid address shape');
  end if;
  if exists (select 1 from public.email_suppressions s where lower(s.email) = v_e
               and (lower(btrim(coalesce(s.reason, ''))) <> 'unsubscribe' or public.fn_email_type_is_marketing(p_type))) then
    return jsonb_build_object('ok', false, 'reason', 'suppressed');
  end if;
  v_dom := split_part(v_e, '@', 2);
  if exists (select 1 from public.email_domain_mx m
              where m.domain = v_dom and m.has_mx = false and m.kind in ('nxdomain', 'no_records')) then
    return jsonb_build_object('ok', false, 'reason', 'domain does not accept mail');
  end if;
  for v_pat in select pattern, reason from public.email_block_pattern where active loop
    if v_e ~ v_pat.pattern then return jsonb_build_object('ok', false, 'reason', v_pat.reason); end if;
  end loop;
  return jsonb_build_object('ok', true, 'reason', 'sendable');
end $fn$;
revoke execute on function public.fn_email_sendable(text, text) from public, anon, authenticated;
