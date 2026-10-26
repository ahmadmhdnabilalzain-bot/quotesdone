-- TWO FUNCTIONS HAVE BEEN WRITING THE COMPANY A CUT-OFF DELIVERABLE, AND THE GATEWAY SAID SO.
--
-- ai_gateway routes on fn_task_class, not on the model ladder a caller names in code. A function
-- with no row there is defaulted to `general_drafting` — medium tier, haiku, max_tokens 900 — and
-- because the gateway applies min(caller, policy), a caller asking for SONNET_FIRST at max 1400
-- gets haiku at 900 and is never told in a way anything reads.
--
-- MEASURED ON PRODUCTION 2026-08-11:
--
--   action_worker      229 model calls in 14 days, output_tokens min 376 max 900,
--                      133 of them EXACTLY 900.
--   workflow_dispatch  its first production call: output_tokens exactly 900, model
--                      ~anthropic/claude-haiku-latest against a SONNET_FIRST ladder, the 3,427
--                      character deliverable ending mid-sentence on "the 0 is a calculation error ("
--                      and carrying no OUTCOME: line at all.
--
-- 133 of 229 is not a tail on a ceiling, it is a ceiling: 58% of every determination action_worker
-- has settled an inbox item with was truncated mid-sentence, and its MIN_CHARS=400 assertion could
-- not see it because 900 tokens is roughly 3,000 characters — comfortably "long enough". The
-- OUTCOME: / RESULT: line the work order asks for is the LAST thing written, so truncation removes
-- it first; cos_execute recorded exactly this failure on 6 Aug and the fix never generalised
-- because the cause is a MISSING ROW, not a constant in any one file.
--
-- ai_gateway had already diagnosed it in its own log, every call, unread:
--   "[UNMAPPED function "workflow_dispatch" - defaulted to general_drafting (medium). Add a
--    fn_task_class row to route this properly.] | TRUNCATED: the model stopped at the 900-token
--    ceiling for task_class general_drafting, so the reply is cut off mid-output."
--
-- agent_reasoning is the honest class for both — "An AI employee reasoning over its own context,
-- memory and live numbers to decide and act" — which is literally what each does. sonnet-5, 8000.
-- THIS COSTS MORE PER CALL AND IT SHOULD: the old ceiling bought a cut-off answer, stored it as the
-- company's work product, and in action_worker's case closed the item on it.

insert into public.fn_task_class (fn, task_class, note, active) values
  ('action_worker', 'agent_reasoning',
   'An AI employee settles one item addressed to it in agent_actions by producing the deliverable. Unmapped until 11 Aug 2026, so 133 of its first 229 calls were truncated at the general_drafting 900-token default.',
   true),
  ('workflow_dispatch', 'agent_reasoning',
   'An AI employee performs one step of a company workflow it owns. Same class as agent_brain and cos_execute: an employee reasoning over its own context to decide and act.',
   true)
on conflict (fn) do update
  set task_class = excluded.task_class, note = excluded.note, active = true, updated_at = now();

-- THE ONE STEP THAT WAS SETTLED ON A TRUNCATED DELIVERABLE IS REOPENED, NOT LEFT.
-- workflow_step_run 32 (metric_lifecycle, intel_director, "Instrument it with a measure that
-- runs") was marked done at 21:47 on the cut-off text above, and the run advanced to step 3 on it.
-- Closing a step on a deliverable that stops mid-sentence is the false success this codebase keeps
-- warning about, and it is mine. Both steps go back so the employee redoes step 2 properly.
--
-- Guarded on the exact evidence rather than on the id alone: if a later run has already redone this
-- step and written a complete deliverable, this must not undo it.
update public.workflow_step_run
   set status = 'ready', finished_at = null, output = null,
       error = jsonb_build_object(
         'reopened_at', now(),
         'reason', 'settled on a deliverable truncated at the general_drafting 900-token default; '
                   || 'the text ended mid-sentence and carried no OUTCOME line',
         'reopened_by', 'two_functions_wrote_the_company_a_cut_off_deliverable.sql')
 where id = 32
   and status = 'done'
   and output->>'worked_by' = 'workflow_dispatch'
   and right(output->>'deliverable', 40) like '%is a calculation error (%';

update public.workflow_step_run
   set status = 'queued', started_at = null
 where workflow_run_id = (select workflow_run_id from public.workflow_step_run where id = 32)
   and step_no = 3
   and status = 'ready'
   and exists (select 1 from public.workflow_step_run p where p.id = 32 and p.status = 'ready');

update public.workflow_run
   set current_step = 2, updated_at = now()
 where id = (select workflow_run_id from public.workflow_step_run where id = 32)
   and exists (select 1 from public.workflow_step_run p where p.id = 32 and p.status = 'ready');
