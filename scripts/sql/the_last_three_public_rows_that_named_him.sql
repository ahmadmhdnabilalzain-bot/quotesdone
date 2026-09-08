-- THE LAST THREE PUBLIC ROWS THAT STILL NAMED HIM.
--
-- The previous file corrected eight phrasings and the widget was re-asked "can I get a refund". It
-- came back with "on day 5 we make the final call" — the correction had landed — and then, one
-- sentence later, "Every refund is the founder's decision". The replace had matched a lower-case
-- "every" and the text carries a capital one.
--
-- That is worth recording rather than quietly patching: a literal `replace()` over prose corrects the
-- instances you happened to look at, and prose says the same thing many ways. Three rows survived in
-- three different phrasings — "Every refund is the founder's decision", "the founder makes the final
-- call", "the founder is notified for the final call". This file uses a case-insensitive regexp and
-- then ASSERTS the count is zero, so the fix is verified by the database rather than by re-reading
-- the answer and hoping.
--
--   node scripts/apply_sql.mjs scripts/sql/the_last_three_public_rows_that_named_him.sql --apply --ddl

begin;

update public.company_faq set
  answer = regexp_replace(answer, '[Ee]very refund is the founder''s decision',
                          'every refund is decided by a person here', 'g'),
  updated_at = now()
where public and answer ~* 'every refund is the founder''s decision';

update public.company_faq set
  answer = regexp_replace(answer, 'the founder makes the final call', 'we make the final call', 'gi'),
  updated_at = now()
where public and answer ~* 'the founder makes the final call';

update public.company_faq set
  answer = regexp_replace(answer, 'the founder is notified for the final call',
                          'it comes to us for the final call', 'gi'),
  updated_at = now()
where public and answer ~* 'the founder is notified for the final call';

-- AND THE REPLACEMENT HAS TO READ LIKE A SENTENCE. Substituting a lower-case phrase for one that
-- began a sentence left the customer-facing answer reading '... to show it. every refund is decided
-- by a person here'. Correcting a fact and introducing a typo in the same edit is not a correction.
update public.company_faq set
  answer = replace(answer, '. every refund is decided by a person here', '. Every refund is decided by a person here'),
  updated_at = now()
where public and answer like '%. every refund is decided by a person here%';

-- ASSERT IT, do not assume it. A correction that silently missed a phrasing is the defect this file
-- exists because of.
do $check$
declare n int;
begin
  select count(*) into n from public.company_faq where public and answer ~* 'founder';
  if n > 0 then
    raise exception 'STILL % public FAQ row(s) name the founder as the approver', n
      using hint = 'The founder ruled on 8 Sep 2026 that all approvals are the CEO''s. A visitor must '
                || 'not be told otherwise. Read them and add the phrasing to this file.';
  end if;
end
$check$;

commit;
