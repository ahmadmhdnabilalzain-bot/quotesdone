# A held row "failed" with result null means the runner died, not the model (27 Oct 2026)

`fn_reason_held_due` counts a try when it CLAIMS a row. If the worker is killed before `fn_reason_held_resolve`,
nothing is recorded, and after 3 claims `fn_reason_held_sweep` closes the row `failed` with `result` null, even though
`ai_cost_log` shows the model calls `ok`. Look in `function_logs` for that function first: shutdown reason `CPUTime`
(the 2 s edge CPU cap; wall clock is not the limit) and `cpu_time_used` per execution. Join on `execution_id` with
`function_edge_logs` to tell the detached itlater run (HTTP 202) from the tick.

On 27 Oct the replay of 4 `*.ceo_revision` rows was killed every time at 2,091 to 2,160 ms. The cause was in-worker
gte-small (24 runs for 4 rows; 13 ms of everything else). gte-small and e5 go to `embed_ml` from any batch path:
`heartbeatDeps` / `defaultDeps(..., { gte: 'remote' })`. A refile of a failed held question carries the same qhash
and is closed at once for 7 days (`failed_with`), so re-open the failed row itself. PR #1678.
