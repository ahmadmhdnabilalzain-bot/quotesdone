-- THE REGISTERS STOP CALLING voice_otp A DEAD SURFACE (customer_support, 22 Sep 2026, INT-04)
--
-- voice_otp stopped returning HTTP 410 in this change: it now answers 200 TwiML telling a caller
-- the line is WhatsApp-only, in English and then Arabic, on the TDRA host for a UAE caller. That
-- makes it a LIVE CUSTOMER-FACING SURFACE, and three registers said otherwise.
--
-- Two of them are files and are corrected in this commit:
--   supabase/seeds/agent_knowledge.seed.sql   "voice_otp ... all return HTTP 410"
--   scripts/sql/the_write_map_in_the_database.sql  (sms_inbound's writes were also absent)
--
-- The third is the LIVE COPY of that seed. public.agent_knowledge id 10491 (_global, "Asset text:
-- OS.md") carries the same sentence, and it is what a seat retrieves when it asks what voice_otp
-- does — so fixing only the seed file would leave every agent still reading the old answer until
-- somebody re-seeds. An index that points at nothing is the failure this estate keeps paying for;
-- a register that points at the WRONG thing is worse, because it answers confidently.
--
-- replace() on the one sentence, not a rewrite of the row: that document is a 200 KB asset export
-- and this is a four-word correction inside it. The where-clause makes it idempotent — a second
-- apply matches nothing.

update public.agent_knowledge
   set content = replace(
         content,
         '`voice_otp`, `voice_otp_capture`, `dev_login`, `qa_login`, `src_io` all return HTTP 410;',
         '`voice_otp_capture`, `dev_login`, `qa_login`, `src_io` all return HTTP 410 (`voice_otp` STOPPED being one on 22 Sep 2026: it now answers 200 TwiML telling a caller the line is WhatsApp-only, and it is a live customer-facing surface);'),
       updated_at = now()
 where content like '%`voice_otp`, `voice_otp_capture`, `dev_login`, `qa_login`, `src_io` all return HTTP 410;%';
