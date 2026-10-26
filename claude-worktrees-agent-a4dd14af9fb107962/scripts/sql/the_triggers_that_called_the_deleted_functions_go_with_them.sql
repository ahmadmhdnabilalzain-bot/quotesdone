-- THE TRIGGERS THAT CALLED THE DELETED FUNCTIONS GO WITH THEM
--
-- The founder, 8 September 2026: "if they dont belong to the CEO nor the customer support agent
-- then delete. we are building agents one by one and at that time only we will be able to figure
-- what we need."
--
-- 64 model-calling edge functions are being deleted under that rule. Two of them were reached not
-- by a caller but by a DATABASE TRIGGER, and those triggers must go in the same change:
--
--   autodispatch_inquiry      on public.inquiries -> functions/v1/dispatch_inquiry -> route_inquiry
--   enrich_capability_on_approve on public.leads  -> functions/v1/enrich_capability
--
-- WHY THIS IS NOT OPTIONAL HOUSEKEEPING. This estate has already paid for exactly this: a trigger
-- whose callee was deleted made its table silently unwritable, and 19 tables were affected before
-- anyone noticed, because nothing fails until someone tries to INSERT. Leave these two and the next
-- write to leads or inquiries -- a supplier registering, a customer posting a job -- errors on an
-- HTTP call to a function that no longer exists.
--
-- The trigger FUNCTIONS are dropped too, not just the triggers. A trigger function left behind with
-- no trigger on it is a loaded gun in the catalogue: it reads as live code, it names an endpoint
-- that is gone, and the next person to wire it up gets a failure with no explanation.
--
-- WHAT THIS MEANS FOR THE PRODUCT, said plainly rather than buried. Dropping autodispatch_inquiry
-- means a new inquiry is no longer dispatched to suppliers automatically. That is the founder's
-- decision and it is a coherent one: the marketplace has 0 customers, 0 inquiries, 0 quotes and 0
-- paid reveals, so nothing is being interrupted, and the dispatch will be rebuilt deliberately when
-- the agent that owns it exists. It is recorded here so that when someone later asks why an inquiry
-- sat still, the answer is in the same file as the change.

drop trigger if exists autodispatch_inquiry on public.inquiries;
drop trigger if exists enrich_capability_on_approve on public.leads;

drop function if exists public.trg_autodispatch_inquiry();
drop function if exists public.trg_enrich_capability();
