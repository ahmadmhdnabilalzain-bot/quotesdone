-- MY OWN CRON WAS THE UNDOCUMENTED ONE.
--
-- Row #3 went 136/152 -> 135/152 within an hour of deploying agent_context_head, and
-- s38-manual-always-current named the reason exactly: "1 active cron job(s) are undocumented".
-- That job is `agent_context_head_refresh`, scheduled by
-- turn_the_prompt_cache_on_now_that_the_prefix_holds_still.sql and never added to cron_registry.
--
-- The check is right and the score should have dropped. s38 compares cron.job against
-- public.cron_registry precisely so that a schedule cannot be added without the manual learning
-- about it, and it caught this inside one scorer run. Registering the row is the fix; weakening
-- the check, or leaving the red and explaining it in a hand-over, would both be worse.
--
-- SAME CHANGE ON BOTH PROJECTS, because cron.job carries it on both.

insert into cron_registry (jobname, human_name, category, purpose)
values ('agent_context_head_refresh',
        'Employee Context Prefix Refresh',
        'AI',
        'fn_agent_context_head_refresh() — rebuilds the byte-stable prefix of each active '
        'employee''s standing context into agent_context_head every six hours, so the Anthropic '
        'prompt cache can hit it. Before this existed the prefix was reassembled per call and '
        'drifted four times in forty-five minutes, so every call bought a 1.25x cache write and '
        'read none of it back. If this job stops, agent_context_head ages past its three-hour '
        'staleness bound and fn_agent_context_capped falls back to live assembly — employees are '
        'unaffected, the cache simply stops paying.')
on conflict (jobname) do update
  set human_name = excluded.human_name,
      category   = excluded.category,
      purpose    = excluded.purpose;
