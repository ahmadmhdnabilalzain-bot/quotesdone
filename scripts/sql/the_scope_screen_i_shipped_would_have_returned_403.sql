-- THE SCOPE SCREEN I SHIPPED WOULD HAVE RETURNED 403.
--
-- The supplier capability-confirmation panel added earlier today calls capability_agent directly
-- with the supplier's JWT. capability_agent does not accept a JWT. Its entire gate is
--
--     const __auth = await requireInternal(admin, body?.__secret, 'capability_agent');
--     if (!__auth.ok) return J({ error: 'forbidden' }, 403);
--
-- with no user-token branch, and it reads `supplier_id` straight from the request body. So the
-- screen would have 403'd on every supplier, and the fix is emphatically NOT to hand the browser an
-- internal secret: a client-supplied supplier_id on a public surface lets any signed-in supplier
-- read and CONFIRM another company's scope. That is the enumeration defect claim_lookup was
-- hardened against on 19 Jul, reintroduced one layer up.
--
-- Caught by measurement, not by reading: calling capability_agent with a credential returned
-- HTTP 403, and internal_credential shows why - of the fifteen active contexts, only `db.internal`
-- carries capability_agent in its scope. `fn.supplier_api` is scoped to exactly four callees:
-- license_extract, profile_ai, quote_extract, supplier_review.
--
-- THE PORTAL GOES THROUGH supplier_api, WHICH IS WHERE THE IDENTITY ALREADY LIVES. supplier_api
-- authenticates the supplier's JWT and resolves them by `claimed_by = email` to THEIR OWN lead id -
-- the id never comes from the client. It then calls capability_agent internally with that id. This
-- widening is one function on one credential, recorded here rather than done by hand in the
-- dashboard, and it is the minimum: capability_agent still refuses every other caller.
update public.internal_credential
   set scope = (select array_agg(distinct s order by s)
                  from unnest(scope || array['capability_agent']) s)
 where context = 'fn.supplier_api'
   and active and retired_at is null
   and not ('capability_agent' = any(coalesce(scope,'{}')));

-- Assert it landed. A silent no-op here leaves the scope screen returning 403 to every supplier
-- while this migration reports success, which is the failure mode the whole session has been about.
do $$
declare v_ok boolean;
begin
  select 'capability_agent' = any(scope) into v_ok
    from public.internal_credential where context = 'fn.supplier_api' and active and retired_at is null;
  if not coalesce(v_ok, false) then
    raise exception 'fn.supplier_api credential does NOT carry capability_agent in scope after the update';
  end if;
end $$;
