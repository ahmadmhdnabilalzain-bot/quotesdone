-- AUDIT 6.5(f), and a bigger hazard found while fixing it.
--
-- match_suppliers_kw has two overloads with an IDENTICAL return signature, and Postgres picks by
-- argument count at call time. The 7-argument one carries the whole exclusion set - banned,
-- matching_blocked, permanently_closed, rejected, and now action_required. The 6-argument one
-- carries NONE of them. Every caller passing six arguments - and the repo has many - was matching
-- against suppliers the 7-arg version would have excluded, including BANNED ones.
--
-- That is not a 6.5 defect. It is a supplier-safety hole that 6.5 happened to expose, and copying
-- the filter list across would just recreate two implementations to drift apart again.
--
-- So the 6-arg overload stops being an implementation and becomes a shim. p_multi=false preserves
-- the historic single-match behaviour for existing callers. Defaults are reproduced exactly as they
-- were, because dropping them would break any caller relying on a positional omission.
create or replace function public.match_suppliers_kw(
  p_keywords text[] default '{}'::text[],
  p_category text default null,
  p_emirate text default null,
  p_role text default null,
  p_min_rating numeric default null,
  p_limit integer default 8)
returns table(id bigint, company_name text, emirate text, business_role text, products text,
              services text, phone text, email text, whatsapp text, website text, rating numeric,
              reviews integer, capability_summary text, match_score integer, in_emirate boolean)
language sql stable
as $$
  select * from public.match_suppliers_kw(p_keywords, p_category, p_emirate, p_role,
                                          p_min_rating, p_limit, false);
$$;
comment on function public.match_suppliers_kw(text[], text, text, text, numeric, integer) is
  'Compatibility shim. Delegates to the 7-argument matcher so the supplier exclusion set is decided '
  'in exactly one place. It used to be a second implementation with none of the exclusions - a '
  'six-argument call could match banned, blocked, permanently closed, rejected and action_required '
  'suppliers.';;
