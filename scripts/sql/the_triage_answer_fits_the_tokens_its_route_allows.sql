-- THE EMAIL TRIAGE ANSWER FITS THE TOKENS ITS ROUTE ALLOWS.
--
-- Assigned: it_engineer (the job is customer_support's inbox). 22 Sep 2026. Founder instruction 705: a bug
-- that would cost us something, or repeat work, is fixed before the paid routes open.
--
-- MEASURED (22 Sep 2026, production + origin/main):
--   * email_triage asks for 800 output tokens (supabase/functions/email_triage/index.ts, llm(SYS, ..., 800)).
--   * fn_task_class maps email_triage -> intent_detection, and model_policy.intent_detection.max_tokens = 300.
--     ai_gateway sends min(caller, policy) = 300.
--   * The answer contract is ONE JSON object: category, a one-sentence summary AND a drafted reply signed
--     'The QuotesDone Team'. It is not a label. Measured on the three fixtures in
--     scripts/checks/the_triage_answer_fits_its_route.test.mjs (an English supplier document, an English
--     customer question, an Arabic customer question) the answers are ~180, ~229 and ~291 tokens: the
--     Arabic one at 97% of the 300 ceiling, so any longer real email is cut (estimate = UTF-8 bytes / 3; no
--     tokenizer and no model was used). No real triage answer exists to measure: 0 drafted replies in
--     inbound_messages, and ai_cost_log holds no email_triage row since the 8 Sep purge.
--   * WHAT THE MISMATCH COSTS: a reply cut at 300 is finish_reason 'length'; _shared/llm.ts makeLlm then makes
--     its one controlled repair call, which can be cut again; the caller gets null and marks the message
--     triaged with no draft. Two paid requests for nothing on every message that needs more than a line.
--
-- WHAT THIS CHANGES: model_policy.intent_detection.max_tokens 300 -> 800, the ceiling the job needs. A ceiling
-- is not spend: a provider bills the tokens it writes, and a classifier that writes 40 is billed for 40.
-- resend_inbound, the other intent_detection caller, asks for 500 and now gets 500 instead of 300.
--
-- WHAT THIS DOES NOT CHANGE: the model, the fallback, the tier or the route mapping (model choice per seat is
-- the founder's coming LLM-per-seat decision), and no money cap (instruction 639).

update public.model_policy
   set max_tokens = 800
 where task_class = 'intent_detection' and active and max_tokens < 800;

select case when (select max_tokens from public.model_policy where task_class = 'intent_detection' and active) >= 800
            then 'PROBE OK' else 'PROBE FAILED' end as verdict,
       'intent_detection max_tokens = ' || coalesce((select max_tokens from public.model_policy where task_class = 'intent_detection' and active)::text, 'no active row')
       || ', email_triage asks for 800' as detail;
