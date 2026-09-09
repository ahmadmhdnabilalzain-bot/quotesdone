-- customer_api ASKS THE SALES ENGINEER TO MATCH
--
-- The founder, 9 September 2026: "match capability is the sales engineer task."
--
-- customer_api's scoped credential (context fn.customer_api) is scoped to call `route_inquiry`,
-- which was DELETED in 182308b and is deployed nowhere — so that entry has authorised nothing for
-- weeks while the fetch behind it 404'd and the caller silently degraded to keyword matching.
-- The scope follows the work: `sales_engineer` in, `route_inquiry` out.
--
-- SCOPE IS NOT SEAT. fn_internal_auth only decides whether this credential may CALL that function;
-- sales_engineer/index.ts maps context -> caller kind separately and admits fn.customer_api as a
-- SERVICE caller restricted to the single `match` action. Widening this array does not hand
-- customer_api the seat, the grant ledger or the sector catalogue.

update public.internal_credential
   set scope = array(
         select distinct s
           from unnest(scope || array['sales_engineer']) s
          where s <> 'route_inquiry'
          order by s)
 where context = 'fn.customer_api'
   and active
   and retired_at is null;

-- fn.to_route_inquiry existed only to call the deleted function. It is left in place rather than
-- retired here: retiring a credential is its own decision with its own ledger, and this file is
-- about one caller reaching one new callee.
