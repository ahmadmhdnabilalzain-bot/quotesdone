# Frontend, API, Storage and Security

Every UI/API path must use the same server-side business service.

For every mutation validate authenticated subject, canonical identity, resource ownership, workflow/step authority and actor/system actor.

RLS/grants must deliberately protect all customer/supplier/admin data. SECURITY DEFINER routines set safe search_path and verify callers.

Storage requires owner-scoped path, admin access, size/MIME/magic-byte validation, safe names, quarantine/scan state, authorized short-lived URLs and immutable approved revisions. No bucket-wide authenticated access.

Every launch-facing feature must prove:

```text
component → client method → endpoint → Edge Function/service → database service → state/object result → visible UI
```

Loading, empty, success, refusal, retry, permission, stale-version, Arabic/RTL and mobile states must be handled.
