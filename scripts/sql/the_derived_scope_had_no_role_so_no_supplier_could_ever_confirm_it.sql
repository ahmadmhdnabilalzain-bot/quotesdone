-- THE DERIVED SCOPE HAD NO ROLE, SO NO SUPPLIER COULD EVER CONFIRM IT.
--
-- fn_match_capability gates on `sc.confirmed_at is not null` — "GATE: supplier confirmed their own
-- scope". capability_agent's `confirm` action is the only thing that sets it, and it refuses
-- outright unless the payload carries BOTH trades and roles:
--
--     if (!trades.length || !roles.length) return J({ error: 'need_at_least_one_trade_and_role' }, 400)
--
-- The 5,220 capability records derived earlier today carry trades and an empty roles array. A
-- supplier confirming that scope unchanged would have been refused by the endpoint, so the record
-- could never become matchable and the whole derivation would have stopped one step short of
-- useful.
--
-- roles ARE derivable, and from something the supplier effectively already told us. leads
-- .business_role is populated on 19,860 rows: supplier 16,395, contractor 1,614, manufacturer 946,
-- service 677, retailer 228. taxonomy_role holds consultant, contractor, distributor, installer,
-- maintenance, manufacturer, supplier, turnkey_fitout.
--
-- THE MAPPING IS DELIBERATELY CONSERVATIVE AND ONLY THREE OF THE FIVE ARE EXACT.
--   supplier      -> supplier       exact
--   contractor    -> contractor     exact
--   manufacturer  -> manufacturer   exact
--   retailer      -> supplier       a retailer sells goods it did not make; that is what
--                                   "Supplier / trading" means here
--   service       -> maintenance    the closest single code. It could equally be `installer` and
--                                   for some of those 677 it will be wrong — which is exactly why
--                                   this is a PROPOSAL the supplier corrects, never a confirmation
--                                   made on their behalf. Nothing here sets confirmed_at.
--   anything else -> supplier       the directory's own majority and the least specific claim
--
-- WHAT THIS DOES NOT DO. It does not confirm anything. confirmed_at stays NULL on every derived
-- row, fn_match_capability still refuses all 5,220, and no supplier becomes matchable because of
-- this file. It makes the derived record CONFIRMABLE — so that when a supplier opens the portal and
-- is shown "we have you down as Aluminium and Glazing, as a Supplier / trading, serving Dubai", the
-- confirm button can actually succeed instead of returning 400.

create or replace function public.fn_lead_role_codes(p_business_role text)
returns text[]
language sql
immutable
as $function$
  select case lower(coalesce(nullif(btrim(p_business_role),''), 'supplier'))
           when 'contractor'   then array['contractor']
           when 'manufacturer' then array['manufacturer']
           when 'service'      then array['maintenance']
           when 'retailer'     then array['supplier']
           when 'supplier'     then array['supplier']
           else array['supplier']
         end
$function$;

comment on function public.fn_lead_role_codes(text) is
  'Maps leads.business_role to taxonomy_role codes for the derived capability proposal. A PROPOSAL '
  'the supplier corrects in the portal - it never sets confirmed_at.';

revoke execute on function public.fn_lead_role_codes(text) from public;
grant execute on function public.fn_lead_role_codes(text) to service_role, authenticated;

-- Backfill the 5,220 rows already derived. Only rows this session derived and that nobody has
-- confirmed: `review_status='derived' and confirmed_at is null`, so a real supplier confirmation can
-- never be overwritten by a backfill.
update public.supplier_capabilities sc
   set roles = public.fn_lead_role_codes(l.business_role),
       updated_at = now()
  from public.leads l
 where l.id = sc.supplier_id
   and sc.review_status = 'derived'
   and sc.confirmed_at is null
   and coalesce(array_length(sc.roles,1),0) = 0;
