# CWE audit: SSRF, session fixation, trust boundary, buffer overflow
Seat: it_engineer. Date: 19 Oct 2026. Base: origin/main. Proofs used only ZZ DEMO subjects, @example.invalid and *.example.invalid hosts, and fake fetches. Nothing was sent over the network to an external or metadata target.

| CWE | Verdict |
|---|---|
| CWE-918 SSRF | FIXED, PR #1506 |
| CWE-384 Session fixation | FIXED, PR #1507 |
| CWE-501 Trust boundary | PASS (sampled, see scope) |
| CWE-120 Buffer overflow | N/A |

## CWE-918 SSRF: FIXED (#1506)
Every server-side fetch whose URL can come from a user, supplier, email or model goes through `_shared/safe_url.ts` `safeFetch`. That covers:
- resend_inbound attachment URLs;
- accountant document links;
- marketing lead_sourcing (supplier websites and robots.txt).

`safeFetch` allows only http and https. It blocks loopback, RFC1918, 169.254/16 (which includes the metadata address 169.254.169.254), CGNAT, multicast and reserved ranges, IPv6 ULA and link-local addresses, IPv4-mapped IPv6, and internal hostnames. It also enforces a timeout and a byte cap while the body streams.

The remaining dynamic fetches take their URLs from sources we control or trust:
- Resend and CloudConvert API responses: doc_extract, cad_convert, it_scheduled_readings, conversation_archive, dropbox_backup.
- sanctions_screen: limited to an https host allowlist (`uaeCandidateUrls`).
- marketing platform_spec_source: a table that only the service role can write (RLS).
- resilience-ping: fixed origins, with `redirect: 'manual'`.

pdf.js is called with `getDocument({ data })`, so it never makes a remote fetch.

**The gap that was fixed:** `safeFetch` used `redirect: 'follow'` and only checked the final URL. A public URL that redirects to 169.254.169.254 or loopback had therefore already sent the internal request before the check ran (a blind SSRF). Redirects are now followed by hand, at most 5, and each hop is checked before it is requested. The regression test in `safe_url.test.ts` asserts that the internal hop is never requested (10 of 10 tests pass).

**Residual:** DNS rebinding. A public hostname that resolves to a private IP is not caught, because Deno does not expose the resolved address. This is already documented in the file.

## CWE-384 Session fixation: FIXED (#1507)
**Finding:** both portals call `takeAuthFragment()` on mount, and a session in the URL fragment overrides the stored one. Anyone can craft `/portal#access_token=<attacker>&refresh_token=<attacker>`, and it silently moved a signed-in customer or supplier into the attacker's account (login fixation).

**Which flows deliver a session in the URL:** none in the product. Sign-in is OTP codes only: login_otp mints the link on the server, verifies its token_hash itself and returns the session as JSON. There is no signUp, OAuth sign-in or password-reset return. So no PKCE or email-template change is needed.

**Fix:** both portals strip any session in the URL from the address bar (replaceState) and never adopt it. That closes the gap for every browser, including one with nobody signed in. Supplier sign-out now also removes `qd-chat-conv`. The tests are in `src/lib/authFragment.test.mjs` (5 of 5 pass).

**Internal tooling only:** admin-generated magic links no longer sign anyone in. The nightly journey_audit step has been updated to expect that. The founder demo links from founder_demo_tour.mjs (--link, --verify) will now land signed out.

Other checks:
- **Fresh session at sign-in:** sign-in goes through OTP and Supabase `setSession`, so the server issues the tokens. There is no pre-set token that the server would honour.
- **Sign-out:** both portals remove the token and refresh keys, then call `auth.signOut()` (server revoke).
  - Customer portal: #1451, which is still open, also drops `qd-chat-conv`. Verified in the diff.
  - Supplier portal: fixed in #1507, its sign-out now drops `qd-chat-conv`.
- **#1438 chat adoption:** the visitor id must be a full UUID v4 (`crypto.randomUUID`, 122 random bits). Adoption needs a signed-in caller plus the explicit `adopt` flag, and it happens only once, because the rows are re-keyed and a second account adopts 0 (asserted in `chat_history.test.ts`). Nothing reads the id from the URL, so an attacker cannot pre-set it from another origin. The only way to hijack a conversation is to know the victim's UUID, and it cannot be guessed. PASS.
- **Refresh-token rotation:** measured on production, auth.refresh_tokens over 30 days: 55 tokens, 13 with a parent (rotated), 12 revoked parents. Rotation is on.

## CWE-501 Trust boundary: PASS (sampled)
- **Client-sent fields:**
  - `messages_api` derives the caller's role from the JWT and checks it against the reveal before acting.
  - `project_api` scopes rows by `customer_id` taken from the session, and `status` must be one of `active`, `completed` or `archived`.
  - `supplier_api` `submit_quote` takes the amount from the supplier, which is that supplier's own price. It checks the inquiry state and registration on the server.

  No `role`, `customer_id`, `supplier_id` or `verified` value from the client was accepted as authoritative.
- **Verified flags:** these are set only after an OTP is checked (login_otp, kyc, mobile_otp).
- **Email provenance:** wa_inbound marks provenance only after verifying the signature. #1498 covers the email-header case.
- **Prompt injection from supplier documents:** document text is passed to classification and extraction as data. Commit c1d93f6 isolates another party's text from the prompts. The licence gate holds a supplier whose licence could not be read rather than approving it (see the pending SQL `a_supplier_whose_licence_could_not_be_read_is_held_never_approved`).

**Scope note:** this was a targeted review of the API entry points and the paths that set verified flags. It was not a line-by-line audit of every action in every function.

## CWE-120 Buffer overflow: N/A
The stack is TypeScript on Deno and Node, which are memory-safe runtimes. The only WASM is the vendored imagescript PNG and JPEG decoders, which run inside the WASM sandbox with bounded linear memory. There are no native addons.
