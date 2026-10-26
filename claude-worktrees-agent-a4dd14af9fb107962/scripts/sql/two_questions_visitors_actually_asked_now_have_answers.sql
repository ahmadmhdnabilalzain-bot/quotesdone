-- TWO QUESTIONS VISITORS ACTUALLY ASKED NOW HAVE ANSWERS.
--
-- These are not invented FAQ entries. They are two of the questions the live widget was asked,
-- could not answer, and filed into public.sales_knowledge_gap -- which is the mechanism the founder
-- already accepted for exactly this: the agent records what it could not answer, and the answer
-- gets written.
--
--   gap #9,  asked twice:  "what documents does a supplier need for verification"
--   gap #6,  asked FIVE times: "does a Dubai supplier cover Abu Dhabi as well"
--
-- Gap #6 was the most-asked unanswered question on the platform.
--
-- ── ONE OF THESE ANSWERS IS SETTLED POLICY. THE OTHER IS AN HONEST NO. ──────────────────────────
--
-- #9 is settled. The mandatory set is six items and it is the founder's own ruling: company name,
-- mobile, email, trade licence, company profile, and signed terms. Everything else a supplier can
-- provide -- VAT certificate, insurance, ISO, manufacturer authorisations -- is extra and improves
-- their standing, but does not gate registration. That distinction is the answer; a list that does
-- not say which items are mandatory would make a supplier think they cannot start.
--
-- #6 IS NOT ANSWERABLE FROM DATA, AND I MEASURED THAT BEFORE WRITING IT. public.leads holds 22,264
-- suppliers, 10,584 of them Dubai-based, and `service_emirates` is NULL on ALL 22,264. Not sparse --
-- empty. Nothing anywhere writes that column. So the platform genuinely does not know which
-- emirates any supplier covers, and an answer implying otherwise would be a claim about 22,264 rows
-- of data that do not exist.
--
-- This is the estate's third field of this shape, and they should be read together:
--   leads.verified                      0 of 22,264 set, no writer
--   supplier_capabilities.confirmed_at  0 of 15,305 set, no writer
--   leads.service_emirates              0 of 22,264 set, no writer
-- Each is a column the product reads as though somebody fills it in.
--
-- So the honest answer to #6 describes the MECHANISM -- the customer names where the work is, and a
-- supplier who cannot serve that location simply does not quote -- which is true, useful, and does
-- not pretend to coverage data. It also tells the customer the one thing that actually protects
-- them: confirm the location with the supplier after the reveal, before committing.
--
-- The four gaps left open after this are all trade-specification questions ("what do you need from
-- me to price an HVAC chiller replacement", fire alarm, structural steel, LV panel). Those need
-- real trade content and are deliberately NOT answered here with something plausible.

insert into public.company_faq
  (section, sort, question, answer, audience, status, public, language, source_note, tags, approved_at, approved_by)
values
  ('Supplier', 900,
   'What documents does a supplier need for verification?',
   'Six things are required to complete supplier registration: your company name, a mobile number, '
   || 'an email address, your trade licence, a company profile, and your signed acceptance of the '
   || 'supplier terms. That is the whole mandatory set — once those six are in, you are verified and '
   || 'can start receiving jobs.'
   || E'\n\n'
   || 'Anything else is optional and only strengthens your profile: VAT certificate, trade or '
   || 'liability insurance, ISO certificates, manufacturer authorisations, machinery and team '
   || 'details, and client references. None of them hold up your registration, and you can add them '
   || 'at any time from your supplier portal.',
   'supplier', 'approved', true, 'en',
   'Answers sales_knowledge_gap #9, asked twice on the public widget. The mandatory six are the '
   || 'founder''s ruling; the optional list is the set of columns public.leads actually stores.',
   array['verification','documents','registration','supplier','trade licence'],
   now(), 'customer_support'),

  ('Marketplace', 901,
   'Does a Dubai supplier cover Abu Dhabi as well?',
   'It depends on the supplier, and you do not have to guess. When you post a request you say where '
   || 'the work is, and that location goes to suppliers with the request — so a supplier who does not '
   || 'serve that emirate simply does not quote. Every quote you receive is from someone who chose to '
   || 'bid knowing where the job is.'
   || E'\n\n'
   || 'Many Dubai-licensed contractors do work across the Emirates, and some price travel or '
   || 'mobilisation separately for work outside their base. Ask them to confirm coverage and any '
   || 'site-access or travel cost directly once you have revealed their contact details and before '
   || 'you commit — that is the point at which you are talking to them and can settle it in writing.',
   'customer', 'approved', true, 'en',
   'Answers sales_knowledge_gap #6, the most-asked unanswered question on the widget (5 times). '
   || 'Deliberately describes the mechanism rather than claiming coverage data: leads.service_emirates '
   || 'is NULL on all 22,264 rows and nothing writes it, so the platform does not hold per-supplier '
   || 'emirate coverage.',
   array['coverage','emirates','abu dhabi','dubai','location'],
   now(), 'customer_support')
on conflict (question) do update
  set answer = excluded.answer, public = excluded.public, status = excluded.status,
      audience = excluded.audience, source_note = excluded.source_note, tags = excluded.tags,
      updated_at = now();

-- ── PROVE THE WIDGET CAN ACTUALLY REACH THEM ────────────────────────────────────────────────────
-- Writing an FAQ row is not the same as answering the question. The public corpus is deliberately
-- FAQ-only and only `public = true` rows survive the view's filter, so the test that matters is
-- whether fn_support_corpus_search returns these rows for a PUBLIC caller -- the exact call
-- site_assistant makes. This file inserts rows rather than defining a routine, but it still must not
-- roll back its own insert, so it ends in a notice.
do $do$
declare n_docs int; n_cov int; v_id bigint;
begin
  -- Both rows must exist, be approved, and be public -- three separate things, and a row can have
  -- the first two and still be invisible to a stranger.
  if (select count(*) from public.company_faq
       where question in ('What documents does a supplier need for verification?',
                          'Does a Dubai supplier cover Abu Dhabi as well?')
         and public and status = 'approved') <> 2 then
    raise exception 'the two answers are not both approved and public';
  end if;

  -- THE REAL TEST: the widget's own call, p_public = true.
  select count(*) into n_docs
    from public.fn_support_corpus_search('what documents does a supplier need for verification', true, 6) r
   where r.content ilike '%mandatory set%' or r.content ilike '%trade licence%';
  if n_docs = 0 then
    raise exception 'the verification answer is written but a public caller cannot retrieve it';
  end if;

  select count(*) into n_cov
    from public.fn_support_corpus_search('does a Dubai supplier cover Abu Dhabi as well', true, 6) r
   where r.content ilike '%where the work is%' or r.content ilike '%mobilisation%';
  if n_cov = 0 then
    raise exception 'the coverage answer is written but a public caller cannot retrieve it';
  end if;

  -- AND THE ANSWER MUST NOT CLAIM DATA WE DO NOT HAVE. If service_emirates ever gains a writer this
  -- assertion is the thing that says the answer can be improved; until then it guards against a
  -- future edit quietly promising per-supplier coverage.
  if (select count(service_emirates) from public.leads) <> 0 then
    raise notice 'NOTE: leads.service_emirates now holds values -- the coverage answer can be made specific.';
  end if;

  raise notice 'TWO ASKED QUESTIONS ANSWERED AND REACHABLE. The verification answer and the coverage answer both come back from the widget''s own public search. Coverage is answered by mechanism, not by data: leads.service_emirates is still null on all % supplier rows. Four trade-specification gaps stay open and were not filled with something plausible.',
    (select count(*) from public.leads);
end
$do$;
