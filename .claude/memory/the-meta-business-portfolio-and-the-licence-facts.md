---
name: the-meta-business-portfolio-and-the-licence-facts
description: "Meta Business portfolio IDs, what the DET licence actually prints, and why the ad account is invisible to any Meta token"
metadata: 
  node_type: memory
  type: reference
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-14T19:15:10.871Z
---

**Portfolio:** "Quotes Done", business_id `2335064440232533`. A second portfolio "DJ ZAINO" exists
and is unrelated. Both were created from Meta's unclaimed pool ("UnclaimedBusinessUser FromPool",
24 Jun 2026), which is why the portfolio arrived almost empty.

**Verification submitted 7 Sep 2026, IN REVIEW** (~2 business days). It had previously been
**Rejected**, most likely because the portfolio carried no phone, no address and the legal name
"QuotesDone" — Meta could not match it to a real business. Filling those cleared it to Unverified
and the resubmission was accepted without a document upload.

**14 Sep 2026: rejected again, and resubmitted by the founder** (his words: "i resubmitted for
verification approval cuz we got rejected last time"). Until it is approved: the WhatsApp
"Authentication" template category (needed for WhatsApp OTP) and a business-owned system-user token
(needed for automatic ad-spend tracking) stay blocked. Check the verification status before
planning either.

**DET E-Trader licence 1633275 — read from the PDF, not inferred:**

| | |
|---|---|
| Trade name | quotesdone technologies |
| Type | Portal License (E-Trader) |
| Issue / expiry | 25 Jun 2026 → 24 Jun 2027 |
| Email | management@quotesdone.com |
| Mobile | 971 56 791 8605 |
| Activities | Computer Systems · Communication Equipment · Software Design |
| Owner nationality | Syria |
| Stores | facebook.com/quotesdone · instagram.com/official.quotesdone · linkedin.com/company/quotesdone · quotesdone.com |

**Meta's "Legal name of business" wants the TRADE NAME, not the founder's personal name.** I got
this wrong once by inferring from context; the licence settles it. Ahmad Mhd Nabil Alzain is the
licence holder, and the business name is QuotesDone Technologies.

**Two phone numbers, both his, and they are not interchangeable:**
- **+971 56 791 8605** — on the trade licence. Use this for anything Meta or DET cross-checks.
- **+971 50 931 9355** — the approved PUBLIC contact given to customers ([[founder-landline-and-mobile]]).

**A Portal licence has no street address** — its "address" is those four store URLs. Jabal Ali
First / Shaista Azizi 702 / Dubai is his accommodation, which is normal and correct for a
home-based E-Trader. If a reviewer ever pushes on address, the Ejari is the proof document.

**THE AD ACCOUNT IS NOT IN THE BUSINESS.** Ad account `10151242677262668` ("Ahmad Zain") is
personal — the API returns `business_id: ""`, and both portfolios show "No ad accounts added". A
system-user token issued by Quotes Done would authenticate perfectly and then see zero ad accounts.
That reads like a permissions bug and is an ownership one. Adding it to the business is
irreversible and touches billing, so it needs the founder's explicit go-ahead.

The licence PDF is a scrambled-font substitution cipher, not extractable text; the decoder that
reads it is in the session scratchpad pattern — inflate the streams, then map the glyphs from words
whose plaintext is certain ("quotesdone", "license").

Related: [[trade-licence-and-vat-status-are-closed]], [[ad-spend-autopilot-built]],
[[support-and-ceo-v1-2-build-complete]].
