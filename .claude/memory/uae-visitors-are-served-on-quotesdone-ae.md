---
name: uae-visitors-are-served-on-quotesdone-ae
description: "TDRA rule — UAE-IP visitors to quotesdone.com are 308'd to quotesdone.ae; depends on a Vercel domain setting AND a code flag"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-14T07:42:51.496Z
---

Founder, 14 Sep 2026 (for TDRA approval): UAE-IP visitors must get the .ae domain. Live and confirmed by him from Dubai the same day.

Two halves, both required:
- Vercel project quotesdone-next → Domains: quotesdone.ae = "Connect to Production" (was 308 → .com until 14 Sep); www.quotesdone.ae = 308 → quotesdone.ae.
- Code: `AE_DOMAIN_SERVES_SITE = true` in src/lib/domains.ts; middleware uses `aeRedirectTarget()` (x-vercel-ip-country AE, skips /api, assets, bots, previews). Canonical SEO origin stays quotesdone.com.

**Why:** if the Vercel .ae domain is ever set back to redirect to .com while the flag is on, UAE visitors loop .com → .ae → .com.
**How to apply:** change either half only together with the other; verify with `curl -I https://quotesdone.ae/` (expect 200). Stripe return URLs accept .ae via supabase/functions/_shared/site_origins.ts.
