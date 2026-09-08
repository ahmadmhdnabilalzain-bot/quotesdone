-- THE PUBLIC KNOWLEDGE STOPS TELLING VISITORS THE FOUNDER DECIDES.
--
-- Founder, 8 September 2026: "refunds belong to the CEO from now on" and "all approvals are from
-- CEO. nothing goes to me."
--
-- The database changed the same hour. The KNOWLEDGE did not, and the widget is what a visitor
-- actually reads. Measured after wiring the corpus in, by asking the live endpoint "can I get a
-- refund" and reading what came back:
--
--     "on day 5 our founder makes the final call ... Every refund is the founder's decision"
--
-- That is now false, and it is being told to customers on the home page. Ten public company_faq rows
-- carry it. This corrects all ten.
--
-- WHAT IS AND IS NOT CHANGED. The mechanism the customer cares about is untouched and still true:
-- the 5-working-day ladder, the chase at 3 days with them copied, a full refund of the reveal fee to
-- the original payment method, nothing automatic, 7-14 working days for the bank. Only the identity
-- of the decider changes, and the public wording drops the personal reference entirely — a customer
-- does not need to know which seat inside QuotesDone signs it off, only that a person-level decision
-- is made and it is not a machine acting alone. "We" is the honest public form of that.
--
-- 59 support_knowledge rows and 295 ops_knowledge rows also name the founder as the approver. They
-- are INTERNAL and are not rewritten here, deliberately: rewriting 354 records by regex at 3am is how
-- a corpus gets quietly corrupted. A single authoritative record is inserted instead, stating the
-- current rule with today's date, so the agent retrieving any older statement also retrieves the one
-- that supersedes it. The bulk correction is a separate, reviewable pass.
--
--   node scripts/apply_sql.mjs scripts/sql/the_knowledge_stops_saying_the_founder_decides.sql --apply --ddl

begin;

-- ── THE TEN PUBLIC ROWS ────────────────────────────────────────────────────────────────────────
update public.company_faq set
  answer = replace(answer, 'our founder makes the final call', 'we make the final call'),
  updated_at = now()
where public and answer like '%our founder makes the final call%';

update public.company_faq set
  answer = replace(answer, 'every one is approved by our founder', 'every one is approved by a person here'),
  updated_at = now()
where public and answer like '%every one is approved by our founder%';

update public.company_faq set
  answer = replace(answer, 'every refund is the founder''s decision', 'every refund is decided by a person here'),
  updated_at = now()
where public and answer like '%every refund is the founder''s decision%';

update public.company_faq set
  answer = replace(answer, 'gated to a human (the founder)', 'gated to a person here'),
  updated_at = now()
where public and answer like '%gated to a human (the founder)%';

update public.company_faq set
  answer = replace(answer, 'routes it to the founder for approval', 'routes it for human approval'),
  updated_at = now()
where public and answer like '%routes it to the founder for approval%';

update public.company_faq set
  answer = replace(answer, 'with the founder reviewing the generated knowledge', 'with a person reviewing the generated knowledge'),
  updated_at = now()
where public and answer like '%with the founder reviewing the generated knowledge%';

update public.company_faq set
  answer = replace(answer, 'held for founder review', 'held for human review'),
  updated_at = now()
where public and answer like '%held for founder review%';

update public.company_faq set
  answer = replace(answer, 'with founder approval before that knowledge goes live', 'with human approval before that knowledge goes live'),
  updated_at = now()
where public and answer like '%with founder approval before that knowledge goes live%';

-- ── THE RECORD THAT SUPERSEDES THE INTERNAL ONES ───────────────────────────────────────────────
-- Dated and explicit, so that an agent retrieving one of the 354 older statements retrieves this
-- alongside it and can see which one is current.
--
-- TWO CONSTRAINTS REFUSED THE FIRST VERSION OF THIS INSERT AND BOTH WERE RIGHT.
-- support_knowledge_authority_ck requires authority_effect = 'none': a knowledge record may DESCRIBE
-- where authority sits and may never CARRY it, because authority that lives in prose is authority
-- nobody can enforce. This record documents the CEO's approval power; ceo_identity and the refund
-- triggers are what actually hold it. support_knowledge_version_ck pins pack_version, so a record
-- cannot smuggle itself in claiming to come from a pack version that was never imported.
insert into public.support_knowledge
  (record_id, schema_version, record_version, record_kind, title, domain, tags, language,
   review_status, content_origin, authority_effect, runtime_use, runtime_index_eligible,
   contains_synthetic_example, requires_current_verification, body, pack_id, pack_version, imported_at)
values
  ('policy_approval_authority_2026_09_08', 1, 1, 'policy',
   'Who approves a refund, and who approves anything else (current as of 8 September 2026)',
   'refunds',
   array['refund','approval','authority','ceo','superseding'],
   'en',
   'authored_not_independently_reviewed',
   'founder_ruling',
   'none',
   'internal_advisory',
   true, false, false,
   'CURRENT RULE, 8 September 2026. Every approval in QuotesDone is made by the CEO seat. Refunds '
   || 'included. Nothing is routed to the founder for approval any more.' || chr(10) || chr(10)
   || 'THIS SUPERSEDES the rule of 17 August 2026 that every refund needed the founder personally, at '
   || 'any amount. Any record stating that the founder decides refunds, that a refund waits for '
   || 'founder approval, or that escalation goes to the founder, is out of date and this record '
   || 'replaces it. His words: "refunds belong to the CEO from now on" and "all approvals are from '
   || 'CEO. nothing goes to me."' || chr(10) || chr(10)
   || 'WHAT DID NOT CHANGE. A refund is still never automatic. Money still cannot move without a '
   || 'named, standing decision recorded in public.ceo_approval, made by an active identity in '
   || 'public.ceo_identity, and a superseded decision cannot authorise anything. The refund ladder a '
   || 'customer experiences is unchanged: the supplier has 5 working days from payment to respond, we '
   || 'chase them after 3 with the customer copied, and if they are still silent the reveal fee is '
   || 'refunded in full to the original payment method.' || chr(10) || chr(10)
   || 'SAYING THIS TO A CUSTOMER. Do not name the founder and do not name the CEO seat. Say that we '
   || 'make the decision and that no refund is automatic. Which seat signs it off is not a customer''s '
   || 'business.',
   'policy_corrections', '1.2.0', now())
on conflict (record_id) do update
  set body = excluded.body, imported_at = excluded.imported_at, record_version = excluded.record_version;

insert into public.support_public_override (src, src_id, is_public, decided_by, rationale)
values ('supportkb', 'policy_approval_authority_2026_09_08', true, 'ceo',
        'A customer asking about refunds must not be told a superseded rule. The record itself says '
        || 'not to name any individual when answering them.')
on conflict (src, src_id) do update set is_public = excluded.is_public;

commit;
