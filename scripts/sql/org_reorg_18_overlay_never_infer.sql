-- REORGANISING THE AGENT COMPANY - 18: the rule an overlay most needs and did not have.
--
-- Section 6 requires that a category overlay loads its "never-infer rules". Measured on production,
-- 14 Aug 2026, across all 86 overlays:
--
--   86/86 declare forbidden_decisions, and they are a real contract - dispatching to suppliers,
--         approving or confirming a supplier, exposing customer identity, unsupported legal
--         conclusions, overriding a privacy or regulatory gate, taking over the conversation.
--   86/86 have category knowledge that mentions mandatory/required fields.
--   86/86 have category knowledge that mentions a regulatory or certification gate.
--    0/86 forbid INFERENCE, in the contract or anywhere in the category knowledge. A search of
--         every runtime-eligible category_specialist record for "never infer", "do not infer",
--         "never assume", "do not assume" and "must not assume" returned nothing.
--
-- The forbidden list is a list of forbidden ACTIONS. Inventing a missing fact is not an action, so
-- it fell outside every clause: an overlay could not dispatch an RFQ, but nothing stopped it
-- supplying the specification, quantity, grade or tolerance the customer never stated, and the
-- accountable role would then dispatch that. The single most consequential thing a category
-- specialist can get wrong is the one thing its contract did not mention.
--
-- This is the same shape as the other defects found today and is why it survived: nothing failed.
-- An overlay that quietly fills a gap produces a confident, complete-looking brief.
--
-- One clause is appended to each overlay's forbidden_decisions. It names the specific facts that
-- must come from the customer, because "do not infer" alone is advice and this is a rule.
-- Idempotent: an overlay that already carries the clause is left alone.

begin;

update org_role
   set forbidden_decisions = forbidden_decisions
       || array['inferring an unstated specification, quantity, grade, standard, dimension or '
             || 'tolerance - if the customer has not stated it, ask; never supply it'],
       updated_at = now()
 where status = 'active'
   and runtime_mode = 'knowledge_overlay'
   and forbidden_decisions is not null
   and not (forbidden_decisions::text ~* 'inferring an unstated');

commit;
