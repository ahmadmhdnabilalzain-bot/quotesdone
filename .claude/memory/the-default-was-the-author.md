---
name: the-default-was-the-author
description: "artifact_review defaulted its reviewer to marketing_design — the Visual Design Director's own runtime key — so the designer reviewed its own work by default, and the raw-string guard could not see it."
metadata: 
  node_type: memory
  type: project
  originSessionId: 951680f6-998d-4578-b818-e62f587f57e4
  modified: 2026-08-15T02:17:44.583Z
---

When a routine **defaults** an identity, check whose identity the default is.

15 Aug 2026, `supabase/functions/artifact_review/index.ts`:

```ts
const reviewerAgent = String(body.reviewer_agent || 'marketing_design');
if (authorAgent && authorAgent === reviewerAgent) { /* 409 */ }
```

`marketing_design` is the **runtime agent_key of the Visual Design Director**, whose `role_id` is
`visual_design`. So the default reviewer of every rendered artifact was the agent that draws the
artifact — and the self-review guard could not see it, because `'visual_design' !==
'marketing_design'` as strings while `fn_org_agent_resolve` maps both to one employee.

Two questions to carry:

1. **Whose identity is the default?** A default reviewer, approver or assignee that happens to be
   the producer defeats a separation-of-duties guard silently, at every call nobody parameterised.
2. **Which sibling paths never got the fix?** `review_chain` got the resolving trigger on 14 Aug;
   `artifact_review` — the same decision, one table over — did not. Diff what each path RESOLVES,
   per [[a-sibling-path-that-never-got-the-lexicon]].

Fifth instance of the root cause in [[addressed-to-an-identity-nobody-models]]. Related:
[[a-picker-not-told-who-wrote-it]].
