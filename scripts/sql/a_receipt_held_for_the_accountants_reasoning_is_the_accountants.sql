-- A RECEIPT HELD FOR THE ACCOUNTANT'S REASONING IS THE ACCOUNTANT'S (24 Sep 2026; seat: accountant).
-- the_books_and_the_knowledge_are_read_by_meaning_not_by_words.sql (#892) made what an expenses-mailbox email IS a
-- reasoned reading. Under the model hold the reading waits in the accountant's queue (reasoning_held_question,
-- accountant.document_kind / accountant.receipt_vendor), and resend_inbound skipped the bookkeeper hand-off that
-- sets owner_role, so the email's inbound row carried no owner and read as the founder's
-- (receipts_never_wait_on_the_founder: row 161, the Anthropic receipt of 23 Sep 23:37 UTC). resend_inbound now
-- writes owner_role 'accountant' on such a row; this names the rows already waiting. Only rows whose email is in
-- the accountant's held queue are touched; nothing is booked, nothing is sent.
--   node scripts/apply_sql.mjs scripts/sql/a_receipt_held_for_the_accountants_reasoning_is_the_accountants.sql --apply --ddl --seat accountant
update public.inbound_messages m
   set owner_role = 'accountant'
 where m.owner_role is null and m.needs_review and m.replied_at is null
   and exists (select 1 from public.reasoning_held_question h
                where h.surface in ('accountant.document_kind', 'accountant.receipt_vendor') and h.status = 'held'
                  and h.subject->>'provider_email_id' = m.provider_email_id);
select case when exists (select 1 from public.inbound_messages m join public.reasoning_held_question h
                           on h.subject->>'provider_email_id' = m.provider_email_id
                          where h.surface in ('accountant.document_kind', 'accountant.receipt_vendor') and h.status = 'held'
                            and m.owner_role is null and m.needs_review)
            then 'PROBE FAILED: a held receipt still has no owner' else 'PROBE OK' end as verdict;
