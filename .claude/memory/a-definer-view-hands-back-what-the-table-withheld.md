---
name: a-definer-view-hands-back-what-the-table-withheld
description: "A view without security_invoker reads as its owner, so a grant on the view returns exactly the rows the grant on its base table was written to withhold — 30 of them in one file."
metadata: 
  node_type: memory
  type: project
  originSessionId: ba4ede58-946f-4477-8042-69cef19ee057
  modified: 2026-08-20T03:41:53.689Z
---

20 Aug 2026, found while auditing my own E4 work rather than by looking for it.
`scripts/sql/phase_d_d2_business_object_map.sql` contains both halves:

```
:722  revoke all on public.phase_d_object_record from public, anon, authenticated;
:723  grant select on public.phase_d_object_record to service_role;
      -- "The store is written only through the service, which is SECURITY DEFINER."
:474  execute format('grant select on public.v_obj_%s to service_role, authenticated', …);
```

Thirty `v_obj_*` views are `select … from public.phase_d_object_record where object_id = '<x>'`.
None carries `security_invoker = true` — **210 of 210 views in `public` are definer views** — so each
reads as its owner and hands `authenticated` the rows line 722 withheld, through PostgREST, past an
RLS policy set that is deny-all (RLS enabled, zero policies). It also defeated `d43`, which had
revoked the *function* door (`fn_phase_d_object_read`) to the same data for exactly that reason.

Nothing had leaked because the store held 0 rows — [[zero-cannot-tell-a-dead-guard-from-an-idle-system]].

**Why:** a permission review that enumerates FUNCTIONS stops one object short. `pg_proc` is the
obvious catalogue; `pg_class` with `relkind in ('v','m')` is the one nobody opens, and a definer view
is a SECURITY DEFINER routine wearing a different hat.

**How to apply:** after any function-grant sweep, run the same query over views —
`reloptions` for `security_invoker`, `has_table_privilege('anon'/'authenticated', oid, 'SELECT')`.
And measure the bound rather than the surface: anon can SELECT **2 of 574** relations in `public`
(`blog_posts`, `category_specs`), which is what makes 284 anon-executable SECURITY INVOKER routines
harmless — they run as their caller. Pin that two-name set in a check; a third widens all 284 at once.
Related: [[a-mention-is-not-a-call]], [[the-read-back-covers-bodies-not-grants]],
[[promote-carries-the-definition-not-the-grants]].
