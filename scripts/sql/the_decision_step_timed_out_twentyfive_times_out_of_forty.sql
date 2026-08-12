-- THE ENGINE'S OWN DECISION STEP TIMED OUT 25 TIMES OUT OF 40.
--
-- Found because the employee-side dispatcher made it visible: a workflow_run that used to park for
-- ever on a step now reaches a terminal state, so `strategic_review` step 4 - "Decide and record
-- rationale", actor ceo, gate authority - started showing up as FAILED instead of as RUNNING.
--
-- MEASURED ON PRODUCTION 2026-08-12:
--
--   action_execution, action_class='exec_review'      25 failed · 15 succeeded
--   every failure                                     "Timeout of 140000 ms reached"
--   org_action_executor.exec_review timeout_seconds   140
--   org_action_executor.exec_review max_attempts      1   <- one timeout kills the run
--
-- AND THE FIRST TWO READINGS WERE BOTH WRONG, so they are written down rather than quietly dropped:
--
--   "It never got past DNS." pg_net reports the whole elapsed time as DNS time when a request times
--   out - "DNS time: 140002 ms, TCP/SSL handshake time: 0.000000 ms". That is a reporting artefact
--   of the timeout, not evidence about name resolution. Every other net.http_post to the same host
--   the same night resolved and returned 200.
--
--   "exec_agents is slow." It is not. 344 model calls in 14 days, median 16.4s, MAXIMUM 31.5s, zero
--   over 140s, zero failures. No single call is anywhere near the wall.
--
--   A third near-miss: action_execution.finished_at - started_at is ~420s for BOTH successes and
--   failures. That is the invoker's dispatch-then-collect cycle (two crons five minutes apart), not
--   the function's runtime. Reading it as runtime would have "proven" a seven-minute function.
--
-- THE ACTUAL CAUSE, which only shows up when the calls are grouped per invocation:
--
--   calls per invocation   4.9 average, 17 maximum
--   model time summed      84.8s average, 289.8s maximum
--   invocations over 140s  12 of 70
--
-- exec_review dispatches action='run_all', and run_all ran all SIX officers SEQUENTIALLY in one
-- HTTP request - each officer one model call, plus a second when the JSON does not parse. Six
-- officers in series against a timeout sized for one.
--
-- THE FIX IS IN THE FUNCTION, NOT IN THIS NUMBER. The officers are independent - each reads its own
-- metrics rpc and writes its own rows - so run_all now runs them with Promise.allSettled and the
-- wall time is the slowest officer (~35s) instead of the sum (~204s). This file only gives the
-- executor headroom to match the two classes that already carry it, and it is deliberately NOT the
-- remedy: if the parallel change were reverted, 180s would still be under the 289.8s worst case.
--
-- max_attempts is deliberately LEFT AT 1. Retrying run_all re-runs all six officers and writes six
-- more exec_reports rows for the same officer and period, so a retry buys a duplicate report rather
-- than a recovered one. The right cure for a timeout here is not timing out.

update public.org_action_executor
   set timeout_seconds = 180,
       note = coalesce(note,'') ||
              case when coalesce(note,'') = '' then '' else ' ' end ||
              '[2026-08-12] timeout 140s -> 180s. 25 of 40 dispatches had been failing on the 140s '
              || 'wall because run_all ran six officers in series; the officers now run in parallel '
              || 'and this is headroom, not the fix.'
 where action_class = 'exec_review'
   and timeout_seconds = 140;
