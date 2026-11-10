-- THE INQUIRY INTERVIEW MOVES TO THE MODEL EVAL B PASSES (part 3 of 3: the T3a sales interview).
-- Seat: it_engineer (cost). 10 Nov 2026. Founder rulings 1572 (the interview reasons like an expert, holds Gulf, Egyptian and
-- Levantine Arabic and slang, up to 100 messages with nothing from message 2 forgotten; "use a cheaper model if it holds the
-- quality"), 1571, 1218. Design: docs/reports/2026-11-10-design-model-routing.md section 5a, step 6.
--
-- GATED on eval B (scripts/eval/model_routing/eval_b.ts: 7 scripted inquiries incl. one of 100 messages with facts planted at
-- turn 2 and 8 expert probes). Eval B has NOT run: the intake flow it tests is being rebuilt (10 Nov 2026). Applied only once it
-- passes, never at merge (scripts/sql/pending/ carries the note). Needs part 1 (Terra Pro registered, inactive).
--
-- AS WRITTEN it moves the interview to openai/gpt-6-luna-pro (candidate 1, USD 0.10/0.50). If Luna Pro fails eval B and Terra Pro
-- passes, change the two marked lines to 'openai/gpt-6.1-terra-pro' (USD 1.00/5.00) and keep the activation statement; if both
-- fail, this file is not applied and the interview stays on Sonnet 5.5. The probe asserts whichever model the file names.
--
-- MEASURED (production, 30 days to 10 Nov 2026): inquiry_qualification_conversation 651 calls, USD 9.70, all Sonnet 5.5; 4,725 in
-- and 859 out a call. Re-priced: USD 0.46 on Luna Pro, USD 4.49 on Terra Pro (design section 4a).
--
-- Prevented by: the matrix probe's section 4 (inquiry_qualification_conversation on the 'interview' route) and the verdict row.
--   after eval B passes: node scripts/apply_sql.mjs scripts/sql/the_inquiry_interview_moves_to_the_model_eval_b_passes.sql --apply --ddl --seat it_engineer

-- Terra Pro is activated only when it is the model this file names (the router may then choose it).
update public.model_registry set active = true, updated_at = now()
 where model_id = 'openai/gpt-6.1-terra-pro' and not active
   and 'openai/gpt-6-luna-pro' = 'openai/gpt-6.1-terra-pro';   -- marked line 1: the model eval B passed

update public.model_policy
   set model_primary = 'openai/gpt-6-luna-pro',               -- marked line 2: the model eval B passed
       model_fallback = 'anthropic/claude-sonnet-5.5',
       rationale = coalesce(rationale || ' | ', '') || '10 Nov 2026, rulings 1572 and 1571 on eval B (docs/reports/2026-11-10-model-routing-evals.md): the interview runs on the cheapest model that held the expert, dialect and 100-message bar; Sonnet 5.5 the second rung.'
 where task_class = 'inquiry_qualification_conversation'
   and (model_primary, model_fallback) = ('anthropic/claude-sonnet-5.5', 'openai/gpt-6-luna-pro');

select case when (select (model_primary, model_fallback) = ('openai/gpt-6-luna-pro', 'anthropic/claude-sonnet-5.5')
                    from public.model_policy where task_class = 'inquiry_qualification_conversation')
             and coalesce(public.fn_ai_route('inquiry_qualification_conversation', null, null, 'inquiry_intake', false, null, null)->>'model', '-')
                 = 'openai/gpt-6-luna-pro'
            then 'PROBE OK: the interview runs on ' || 'openai/gpt-6-luna-pro' || ' > Sonnet 5.5'
            else 'PROBE FAILED: inquiry_qualification_conversation routes '
                 || coalesce(public.fn_ai_route('inquiry_qualification_conversation', null, null, 'inquiry_intake', false, null, null)->>'model', '-') end as verdict;
