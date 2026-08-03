-- Legal acceptance versioning: one source of truth, and acceptance records that stop rewriting themselves.
--
-- BEFORE: qd_norm_supplier_ver set accepted_terms_version := 'v4' and qd_norm_customer_ver set
-- tos_version := 'v3' — hardcoded constants, applied unconditionally on INSERT *and* UPDATE. Three
-- consequences: (a) the supplier constant was wrong — suppliers accept the agreement in
-- app_secrets.supplier_terms_html, which self-describes as Version 5, so every acceptance would have
-- been recorded against a version the supplier never saw; (b) any later UPDATE to the row — a phone
-- number, a licence renewal — re-stamped the version, so the record tracked the trigger rather than
-- the acceptance; (c) a version supplied by the caller was silently discarded.
--
-- AFTER: the version in force is resolved from a single place (app_secrets.terms_version /
-- customer_terms_version) via fn_terms_version(), and a recorded acceptance is treated as evidence:
-- it is only ever written when the acceptance itself is new, and never rewritten otherwise.
--
-- Also: both trigger functions previously existed on production in NO migration file. This migration
-- puts them under version control.
--
-- Verified on staging branch jmufplujtmnikxplrano, 11/11 behavioural assertions passing.

create or replace function public.fn_terms_version(p_kind text)
returns text
language sql stable security definer set search_path to 'public','pg_temp' as $$
  select coalesce(nullif((select a.value from public.app_secrets a
      where a.key = case lower(p_kind) when 'supplier' then 'terms_version'
                                       when 'customer' then 'customer_terms_version' end), ''), 'unversioned');
$$;
revoke execute on function public.fn_terms_version(text) from public, anon, authenticated;

create or replace function public.qd_norm_supplier_ver() returns trigger
language plpgsql set search_path to 'public','pg_temp' as $function$
begin
  if TG_OP = 'UPDATE' then
    -- Not a new acceptance: the recorded version is evidence and is never rewritten.
    if NEW.accepted_terms_at is not distinct from OLD.accepted_terms_at then
      NEW.accepted_terms_version := OLD.accepted_terms_version;
      return NEW;
    end if;
    -- A genuine re-acceptance. If this statement did not explicitly set a version,
    -- resolve the one actually in force now rather than carrying the stale value forward.
    if NEW.accepted_terms_version is not distinct from OLD.accepted_terms_version then
      NEW.accepted_terms_version := public.fn_terms_version('supplier');
      return NEW;
    end if;
  end if;
  if NEW.accepted_terms_at is not null and coalesce(NEW.accepted_terms_version,'') = '' then
    NEW.accepted_terms_version := public.fn_terms_version('supplier');
  end if;
  return NEW;
end $function$;

create or replace function public.qd_norm_customer_ver() returns trigger
language plpgsql set search_path to 'public','pg_temp' as $function$
begin
  if TG_OP = 'UPDATE' then
    if NEW.tos_accepted_at is not distinct from OLD.tos_accepted_at then
      NEW.tos_version := OLD.tos_version;
      return NEW;
    end if;
    if NEW.tos_version is not distinct from OLD.tos_version then
      NEW.tos_version := public.fn_terms_version('customer');
      return NEW;
    end if;
  end if;
  if NEW.tos_accepted_at is not null and coalesce(NEW.tos_version,'') = '' then
    NEW.tos_version := public.fn_terms_version('customer');
  end if;
  return NEW;
end $function$;

drop trigger if exists trg_norm_supplier_ver on public.leads;
create trigger trg_norm_supplier_ver before insert or update on public.leads
  for each row execute function public.qd_norm_supplier_ver();

drop trigger if exists trg_norm_customer_ver on public.customers;
create trigger trg_norm_customer_ver before insert or update on public.customers
  for each row execute function public.qd_norm_customer_ver();;
