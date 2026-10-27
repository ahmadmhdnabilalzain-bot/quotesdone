---
name: error-and-empty-must-not-return-the-same-value
description: "A catch that returns the empty value makes \"the dependency is unreachable\" identical to \"there is nothing there\" — I built this defect while remediating it."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 681a6f7f-1c08-4a22-82b9-fb80cd8c8f0e
  modified: 2026-08-14T14:44:31.143Z
---

Building the V3 tool runtime (14 Aug 2026) I wrote:

```ts
const { data, error } = await admin.rpc('fn_agent_tools', {...});
if (error || !Array.isArray(data)) return [];   // <- the whole defect
```

Then I dropped and recreated `fn_agent_tools` to add a column. PostgREST's schema cache went stale,
every `.rpc()` returned an error, that line answered "this agent has no tools", and **36
consecutive regression cases ran toolless and looked like a model choosing not to call anything.**
Tool calls stopped dead at the minute of the DROP. I was remediating `TOOL_NOT_CONNECTED` and
shipped a fresh instance of it in the same session.

**Why:** the empty value is a *valid business answer* ("none granted", "no rows", "not found").
Returning it on failure collapses two states that need opposite responses — one means proceed, the
other means stop — and the collapsed state is the silent one, so no monitor fires. The same shape
elsewhere in this repo: `ok_empty` vs `error` on tool results, and a 403 that read as "the model
declined".

**How to apply:** any `catch`/error branch that returns `[]`, `{}`, `null`, `0` or `''` is suspect —
ask what a *legitimate* empty result looks like at that call site, and if it is the same value,
split them. Record the failure and rethrow, or return a discriminated result; let the caller fail
closed. Two operational corollaries: after `DROP`+`CREATE` of any function reached over PostgREST,
issue `notify pgrst, 'reload schema'`; and `CREATE OR REPLACE` cannot change a `RETURNS TABLE` row
type (42P13), so adding a column forces a DROP — which also drops the ACL, so the revoke/grant pair
becomes mandatory there. Related: [[a-guard-that-fires-on-the-correct-refusal]],
[[zero-cannot-tell-a-dead-guard-from-an-idle-system]], [[absent-input-scores-as-satisfied]].
