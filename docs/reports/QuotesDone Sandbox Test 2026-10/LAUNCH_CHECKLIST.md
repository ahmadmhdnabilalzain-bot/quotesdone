# QuotesDone launch checklist: measured 19 Oct 2026 (it_engineer)

Production: https://quotesdone.com and Supabase htdblwldjkcgjvmqkbeh. All checks were read-only.

## Site

| Item | Status | Evidence | Fix |
|---|---|---|---|
| Custom 404 page | FAIL | `/zz-nope`, `/ar/zz-nope` and `/about/zz` return 404 with the Next.js default page ("404: This page could not be found."). `src/app/[locale]/not-found.tsx` exists but never renders, because nothing calls notFound() for an unmatched path. | PR #1455 adds `[locale]/[...rest]/page.tsx`. It is with the release operator for review. |
| CTA above the fold | PASS | Playwright at 375, 768, 1024 and 1440 px: "Get quotes" sits at top 14–16 px in the sticky header. | |
| Meta title per page | PASS | 158 sitemap URLs crawled. 0 duplicate titles and 0 missing titles. | |
| Open Graph image | PASS | Measured by the coordinator (1200×630). `[locale]/opengraph-image.tsx`. | |
| Favicon set | PASS | favicon.ico, icon.png and apple-icon.png all return 200 (coordinator). | |
| robots.txt | PASS | Returns 200 (coordinator). | |
| sitemap.xml | PASS | Returns 200 with 158 URLs. www redirects to the apex with a 308. | |
| Alt text on every image | PASS | Crawled all 158 pages. There are 2 `<img>` tags and both have alt text. | |
| Mobile breakpoints 375/768/1024 | PASS | No horizontal overflow at any of the three widths (scrollWidth ≤ innerWidth). | |
| Sticky mobile CTA | PASS | Header is `sticky top-0`. "Get quotes" is still visible after scrolling 2,500 px at 375 px. | |
| Loading states | PARTIAL | No route-level `loading.tsx`. Components handle loading inline: 203 matches for busy, disabled or spinner patterns in `src/components`. | |
| Form error states | PASS (code) | 62 `aria-invalid` / `role="alert"` uses across forms. Not exercised live. | |
| Thank-you after inquiry / contact | PASS (code) | `ContactInner.tsx:52` shows "Thanks — we will be in touch shortly." The complaint form shows a ticket number. | |
| Thank-you after sign-up | PARTIAL | Sign-up is OTP inside the portal, and success lands in the portal. Not walked live, because that would mean creating a production account. | |
| Analytics installed | FAIL (deliberate) | No analytics script in any of the 158 pages and no analytics package. `CookieConsent.tsx:11-12` records that the platform sets no analytics cookie. | Not fixed. Adding analytics changes the cookie and privacy terms, so the CEO / marketing seat has to decide. |

## Security

| Item | Status | Evidence | Fix |
|---|---|---|---|
| RLS on every public table | PASS | 714 tables, 0 with RLS off. 434 have RLS on and no policy; their only anon/authenticated grant is TRIGGER on 3 tables. | |
| Table grants / user isolation | PASS | anon has SELECT on `blog_posts` and `category_specs` only. authenticated has SELECT on 6 tables. No INSERT, UPDATE or DELETE grants. 0 views granted to clients without security_invoker. | |
| SECURITY DEFINER routines | PASS | 1,508 in total. anon can execute 0. 0 lack a pinned search_path. The 6 that authenticated can execute are all bound to the caller through auth.uid() or a JWT email check. | |
| Storage buckets locked | PARTIAL | 19 buckets, 5 public: site, demo-assets, social-media, brand, ml-models. Storage has 0 policies, so access is service-role only, through signed URLs. `ml-models` (public) and `reports` (private) have no size or MIME limit. | Low risk; tighten in the next round. |
| Secrets in repo and history | PASS | Aikido scan of origin/main febe250 plus a grep for live keys found only the anon key (`src/lib/supaEnv.ts`). See AIKIDO_SCAN.md. | |
| API keys hidden from client bundles | PASS | 26 production JS chunks (/, /portal, /supplier, /contact): 0 hits for sk_live, sk_test, sk-or, whsec, re_ or service_role. The only JWT decodes to role "anon". | |
| Service role kept out of the browser; edge functions check auth | PASS | 27 functions POSTed with no credentials. 24 return 401 or 403; customer_followup returns 400 (link not valid); site_assistant is public by design. role_guard returns 200 by design: it runs before OTP, is rate-limited and sends no membership answer (`role_guard/index.ts:5-24`). | |
| Unauthenticated routes blocked | PASS | Same probe as the row above. | |
| Admin routes locked | PASS | ceo_agent, it_engineer, marketing and accountant have verify_jwt = true (`config.toml`). Internal jobs (backup, send_outbox, email_cron and others) return 403 with no internal credential. | |
| IDOR (customer A asks for B's records) | FIXED (PR #1481, merging) | Full action-by-action audit of every client-facing edge function (customer_api, customer_portal, customer_documents, reveal_invoice, refunds_api, messages_api, project_api, procurement_api, supplier_api, supplier_portal, supplier_pay, supplier_onboard, supplier_ack). Every record read/written by a body id is scoped to the caller's own `customer_id`/`supplier_id`/owned transaction with a 403 on mismatch — EXCEPT one: `supplier_portal` `product_match` passed body `inquiry_id` into `fn_supplier_product_match` with no `inquiry_matches` check, so a signed-in supplier could read any enquiry's category + `raw_input` (unmasked customer detail) and trigger platform-billed model calls. Proven live on ZZ DEMO `@example.invalid` fixtures: an UNMATCHED supplier was returned the enquiry's full want text ("…secret: Ahmed 0501234567…"); fixtures cleaned by exact marker, 0 rows left. | PR #1481 gates the action on `inquiry_matches` membership (same predicate `supplier_api` uses via `matchedInquiry`). Sent to the release operator; edge functions deploy from the main queue on merge. |
| Field tampering (role, price, fee, status) | PASS (code) / HARDENED | Clients cannot write to any table directly (no INSERT/UPDATE/DELETE grants to anon or authenticated). Edge bodies reviewed action by action: `submit_quote` uses an explicit field list with `supplier_id = sup.id` and server-computed price; `project_api`/`customer_portal` set `customer_id` on the server; no `...body` spread in the supplier functions. PR #1481 also hard-codes the `messages_api` chat-attachment bucket to `'uploads'` instead of trusting `body.attachment_bucket` (latent field-tampering vector). | |
| SQL injection on RPC / edge inputs | PARTIAL | Clients call no definer RPC that anon can reach. Edge functions use the supabase-js query builder, which parameterises queries. No live injection run. | |
| All inputs validated | PARTIAL | Code-level only; covered by the rows above. | |
| Sensitive data removed from logs | NOT MEASURED | | |
| Sessions (token expiry, refresh, cookies) | PARTIAL | JWT expiry and refresh rotation live in the dashboard, not in `config.toml`, and could not be read through SQL. | |
| Security headers | PASS | CSP, HSTS (2 years, includeSubDomains), X-Frame-Options DENY, nosniff, Referrer-Policy and Permissions-Policy are all present. | |
| Dependency scan | PASS (prod) / PARTIAL (dev) | `npm audit --omit=dev`: 0 vulnerabilities. Full audit including dev dependencies: 7 (5 high, 2 moderate), which do not ship to the browser. Deno imports not scanned. | |
| Blog body_html rendered unsanitised | LOW | `BlogPost.tsx:132` (Aikido). Only the service role can write it, and the CSP applies. | |
| Workflow dispatch inputs interpolated into `run:` | LOW | `deploy-functions.yml:142` and `release-train.yml:66` (Aikido). Only users with write access can trigger them. | |
| Pen-test pass of the top 10 paths | PARTIAL | Only the unauthenticated sweep in this file was run. No authenticated attack pass. | |

No critical security FAIL was measured.
