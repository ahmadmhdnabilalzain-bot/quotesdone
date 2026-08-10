-- exec_review's timeout was set ABOVE the platform's own ceiling, which is not a timeout at all.
--
-- I raised it to 180 s this afternoon after two dead letters at the old 60 s, having measured
-- exec_agents taking about 130 s for seven officers. The next failure came back as
-- {"code":"IDLE_TIMEOUT","message":"Request idle timeout limit (150s) reached"} — the edge runtime
-- kills the request at 150 s regardless of what the caller asked for, so 180 could never be
-- honoured and the invoker dead-lettered work the PLATFORM had ended.
--
-- 140 s sits inside the ceiling, so a slow run is recorded as the invoker giving up rather than as
-- an unexplained platform kill. The real finding is about exec_agents, not the invoker: seven
-- officers with a model call each is at the edge of what one edge invocation can do, and the run
-- that failed was simply a slower one. It needs to fan out or checkpoint before it can be relied
-- on unattended; recorded rather than patched around.
update public.org_action_executor set timeout_seconds = 140 where action_class = 'exec_review';

update public.dead_letter
   set resolved_at = now(), resolved_by = 'part9_session',
       resolution = 'Edge runtime IDLE_TIMEOUT at 150 s, not a transport failure and not a caller timeout: exec_review had been set to 180 s, above the platform ceiling. Lowered to 140 s. exec_agents runs seven officers with a model call each and is at the limit of a single edge invocation.'
 where kind = 'exec_review' and resolved_at is null;
