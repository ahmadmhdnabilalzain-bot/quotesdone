-- Eight thousand domains and nobody had ever asked whether they accept mail
-- =========================================================================
--
-- 19,835 leads are eligible for an invitation across 8,927 distinct domains, and current bounce is
-- 5/62 = 8.06% against an 0.08 brake that has already paused the sender once. fn_email_sendable
-- checks the address SHAPE, the suppression list and a pattern table. Nothing has ever asked DNS
-- whether the domain can receive mail at all - which is most of what a paid verifier does, and it
-- costs nothing.
--
-- This adds the storage and the gate. scripts/mx_sweep.mjs fills it.
--
-- WHAT COUNTS AS DELIVERABLE. An MX record is the normal answer, but RFC 5321 section 5.1 is
-- explicit that a domain with no MX and an A/AAAA record still receives mail at that address - the
-- implicit MX rule. A verifier that demanded MX alone would discard live UAE domains whose mail is
-- served straight off the web host, so has_mx is true for either. Only a domain that resolves to
-- NEITHER is refused, and NXDOMAIN is recorded separately from a timeout because they mean
-- different things: NXDOMAIN is a verdict, a timeout is a missing measurement.
--
-- FAILS OPEN, DELIBERATELY. A domain with no row is sendable. A resolver outage must never quietly
-- empty the invite queue, and an unchecked domain is unknown, not bad. Only a row that positively
-- says has_mx=false blocks, and only when the check actually completed.

create table if not exists public.email_domain_mx (
  domain      text primary key,
  has_mx      boolean not null,
  kind        text not null default 'unknown',   -- mx | a_implicit | nxdomain | no_records | error
  hosts       text[],
  checked_at  timestamptz not null default now()
);

comment on table public.email_domain_mx is
  'DNS deliverability per e-mail domain. has_mx=false only when the lookup COMPLETED and found no MX and no A/AAAA. Absent row = unknown = sendable (fail open).';

create index if not exists email_domain_mx_undeliverable_idx
  on public.email_domain_mx (domain) where has_mx = false;

-- fn_email_sendable gains one check, after suppression and before the pattern loop. The pattern
-- loop is a scan of every active row; the MX lookup is a primary-key hit, so it goes first of the
-- two.
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
