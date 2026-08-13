-- THE ONE SCREEN HE OPENS DID NOT SHOW THE 27 DECISIONS WAITING ON HIM.
--
-- 13 Aug 2026. The founder has said twice - 10 Aug and again in this session's brief - that the OS
-- dashboard is "still basic", and that his judgement of that screen outranks its score. Opened at
-- 1440 signed in as him, the Command Console is: a run-on grey line of ten figures at 11px, then
-- roughly 650px of empty canvas, then a text box asking HIM what he wants. Nothing on it says what
-- needs him.
--
-- MEASURED AT THE SAME MOMENT, from fn_founder_queue, which already existed:
--
--   waiting_on_you_total   27
--   oldest_days            36
--     Approve improved prompt: quote_review.system (v2)        ai_architect   36 days
--     Core legal documents missing                             legal          36 days
--     Suppliers have not accepted current terms                legal          36 days
--     Customers have not accepted current terms                legal          36 days
--     Regulatory change may affect your terms/policies         legal          36 days
--     Auth hardening review                                    security       36 days
--     Open fraud flags                                         security       29 days
--     5 x Customer reveal_no_response escalations              followup    29-34 days
--
-- fn_founder_queue's OWN COMMENT named the gap: "Nothing surfaces them. Not the OS dashboard, not
-- an email, not the command channel. They were correctly refused by action_worker and then
-- correctly forgotten by everything else, which is the most expensive kind of correct." It has
-- since reached the WhatsApp channel through fn_wa_context. The dashboard is the half that was
-- still missing - the finished capability with no entry point, one more time.
--
-- No new query and no new figures: this registers the function that already computes the answer as
-- a read-only os_api action so the console can render it.
--
-- BOTH GATES, IN STEP. os_api classifies actions in its own code AND public.control_mode_action
-- classifies them in the database. An action present in one and absent from the other is what made
-- eleven read-only screens demand a phone code on 12 Aug. Adding it here and in index.ts together
-- is the whole point of this file existing rather than the change being TypeScript-only.

-- requires_control is a GENERATED column derived from classification, so it is not written here.
-- That is the right shape and worth leaving alone: it makes it impossible to register an action as
-- read_only and simultaneously demand a control-mode challenge for it, which is exactly the drift
-- that put a phone-code prompt in front of eleven read-only screens.
insert into public.control_mode_action (action, description, risk, classification)
values ('ws.founder_queue',
        'Returns the decisions waiting on the founder, ranked oldest first, from fn_founder_queue. Reads agent_actions joined to agent_action_kind_policy where policy = founder. Writes nothing.',
        'low', 'read_only')
on conflict (action) do update
  set description = excluded.description,
      risk = excluded.risk,
      classification = excluded.classification;

-- fn_founder_queue is SECURITY DEFINER and returns the founder's own decision queue. os_api reaches
-- it with the service role; nothing anonymous may call it. CREATE OR REPLACE preserves an existing
-- ACL, so this is stated for the case where the routine is created fresh on a new project.
revoke all on function public.fn_founder_queue(integer) from public, anon;
