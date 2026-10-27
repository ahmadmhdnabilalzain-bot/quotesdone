---
name: quotesdone2-is-the-live-publishable-key
description: "27 Oct 2026: the Vercel app's publishable Supabase key is the one named quotesdone2; fn_gateway_client_key() (#1655) is the single source. Never revoke quotesdone2."
metadata:
  type: project
  modified: 2026-10-27
---

The Supabase publishable key the production web app (Vercel) uses is **quotesdone2**. Since #1655,
`fn_gateway_client_key()` is the only place server-side code reads the publishable key from.

**Why:** revoking or rotating the wrong publishable key takes the public site and every portal call down at once.

**How to apply:** never revoke or disable quotesdone2. Retire the legacy HS256/anon keys only after two days of
clean logs showing no legacy-key traffic, and only with the founder. Never print key values. Refer to them by name.
