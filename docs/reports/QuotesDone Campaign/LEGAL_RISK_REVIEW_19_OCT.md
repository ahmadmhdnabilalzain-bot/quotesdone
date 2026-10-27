# QuotesDone: legal risk review before launch (19 Oct 2026)

Seat: **ceo**. Ledger 1122 asks for nothing that could get the company sued. Scope: UAE, GCC and international law only; US law is excluded. Skill used: `legal:legal-risk-assessment`. Each risk is scored as severity (1-5) x likelihood (1-5): 16-25 is RED, 10-15 ORANGE, 5-9 YELLOW and 1-4 GREEN.

**What was read** (the committed text in `src/content/legal.json`, English and Arabic headers):
- Terms v10 (6 Oct)
- Supplier Agreement v15 (6 Oct)
- Privacy 1.6 (6 Oct)
- Refund 1.8 (24 Sep)
- Cookie 1.4
- Disclaimer 1.3
- `src/content/marketing.json`, including the blog, FAQ, about, services and how-we-verify pages
- `docs/legal/SUPPLIER_CAMPAIGN_LAWFUL_BASIS.md`
- `docs/legal/company_identity_sources.json`

This is a self-review. It is not legal advice from counsel. The founder has ruled out hiring a lawyer, so every residual risk below is accepted by the CEO seat.

---

## Summary

| # | Risk | Score | Level |
|---|---|---|---|
| 1 | Refunds are "decided by QuotesDone's CEO", but the CEO is an automated seat | 4x4=16 | RED |
| 2 | Promotional messages are opt-out in the Terms but opt-in in the Privacy Policy and Terms cl.10 | 4x4=16 | RED |
| 3 | The PDPL has no general "legitimate interests" basis, yet Privacy s3 and s9 rely on one | 4x3=12 | ORANGE |
| 4 | The licensed activity on DET Trader License 1633275 is not recorded anywhere | 5x2=10 | ORANGE |
| 5 | The two liability caps contradict each other (Disclaimer s5 vs Terms cl.9) | 3x3=9 | YELLOW |
| 6 | Quotes are "indicative only" (Disclaimer s3) but binding when revealed (Supplier cl.12) | 3x3=9 | YELLOW |
| 7 | Supplier fee increases can be accepted by continued use (cl.6), against cl.23 | 3x3=9 | YELLOW |
| 8 | Suppliers' names and logos are used as references unless they opt out (Supplier cl.32) | 3x3=9 | YELLOW |
| 9 | The e-commerce law (Federal Decree-Law 14/2023) is not cited or mapped anywhere | 3x3=9 | YELLOW |
| 10 | Refund 1.8 s2 still has card-fee wording ("Both amounts ... either", "They are") | 3x3=9 | YELLOW |
| 11 | Five-year conversation retention rests only on the tax regulation | 3x2=6 | YELLOW |
| 12 | Blog prices have no "indicative, not an offer" notice | 2x3=6 | YELLOW |
| 13 | Cross-border transfers (Singapore, US) rest on "contractual terms" with no transfer register | 3x2=6 | YELLOW |
| 14 | VAT threshold of AED 375k: one large reveal can cross it, since the 3% fee has no cap | 3x2=6 | YELLOW |
| 15 | Fixed compensation amounts (AED 5k, 10k, 20k, 25k) and the 24-month non-circumvention term | 3x2=6 | YELLOW |
| 16 | Government bodies (DEWA, Dubai Municipality, Civil Defence, SIRA) named with no non-affiliation line | 2x2=4 | GREEN |
| 17 | TDRA NOL NOL-26-100000665 expires 14 Sep 2027 | 4x1=4 | GREEN |
| 18 | E-signature: browse-wrap wording, and records called "conclusive evidence" | 2x2=4 | GREEN |
| 19 | Card-surcharge ban (Cabinet Res. 66/2023) | complies | GREEN |
| 20 | Intermediary status (Commercial Transactions Law Arts. 252 and 265) | sound | GREEN |
| 21 | Cookies: essential only, the notice matches the code | complies | GREEN |

---

## Findings

### 1. RED: an automated "CEO" decides refunds
**Where:**
- Terms v10, cl.5, para 3 ("Every refund is decided by QuotesDone's CEO")
- Refund 1.8, s3 and s6
- Supplier v15, cl.11 and cl.33 ("QuotesDone's CEO makes a final call to the Supplier")
- Privacy 1.6, s4, which admits that "assessing refund requests and disputes" is automated

**Risk:** A reader takes "CEO" to mean a human officer. If the decision is made by the automated CEO seat, the wording is misleading:
- It breaches Consumer Protection Law 15/2020 (accurate information) and the duty of good faith in the Civil Transactions Law.
- It breaches PDPL Art. 18, the right to object to automated decisions. The "reconsidered by a person" route in Privacy s4 only works if a human actually reads management@quotesdone.com.
- This is also ledger 1152.

**Fix:**
- **Terms v11 cl.5 and Refund 1.9 s3/s6:** say "decided by QuotesDone under its published rules, using automated tools; you may ask for any refund decision to be reviewed by a member of QuotesDone's management, who will reply within 10 working days".
- **Supplier v16 cl.11 and cl.33:** replace "CEO makes a final call" with "QuotesDone makes a final contact attempt by phone, WhatsApp or email".
- **Operations:** route every "review by a person" request to the founder's own inbox. No agent may close one.

### 2. RED: promotional messages, opt-in or opt-out
**Where:**
- Terms v10 cl.17 says "(unless you opt out) promotional communications, by email, SMS and WhatsApp".
- Supplier v15 cl.32 says the same.
- Terms cl.10 and Privacy s9 say "only with your consent".

**Risk:**
- The documents contradict each other.
- The PDPL requires consent that is clear and specific (Art. 6).
- Cabinet Resolutions 56 and 57 of 2024 (marketing calls and messages) need prior consent and come with fines.
- Meta's WhatsApp Business Policy requires opt-in, so the number can be banned.
- A contradiction in a standard-form contract is read against the drafter.

**Fix:** In Terms v11 cl.17 and Supplier v16 cl.32, replace the opt-out phrase with: "and, only if you tick the separate box to agree, promotional communications. You may withdraw that consent at any time." Add an unticked consent box at sign-up, stored with a timestamp. Until that ships, treat no customer or supplier as opted in.

### 3. ORANGE: the PDPL has no "legitimate interests" basis
**Where:**
- Privacy 1.6 s3, bullet 3 (vetting, fraud, improving services)
- Privacy s3, closing line
- Privacy s9, business invitations
- The campaign lawful-basis file

**Risk:**
- PDPL Art. 4 lists exceptions to consent: contract, legal obligation, vital interest, data the person has made public, legal claims and others. There is no general "legitimate interests" basis.
- A cold invitation sent to a named person's mailbox (for example ahmed@company.ae) is processing of personal data.

**Fix:** In Privacy 1.7, replace "legitimate interests" with the Art. 4 grounds that apply:
- fraud and security: legal obligation, and defending legal claims;
- vetting: performance of the supplier contract at the request of the person;
- business invitations: "data that the business has itself made publicly available" (Art. 4).

For the campaign, keep sending only to role addresses (info@, sales@, enquiries@), as `SUPPLIER_CAMPAIGN_LAWFUL_BASIS.md` already prefers, and exclude any address that is a person's name.

### 4. ORANGE: the licensed activity is not recorded
**Where:** `company_identity_sources.json` records the licence number and its dates, but not the activities. No page states which activities the licence covers.

**Risk:**
- A DET Dubai Trader licence covers a limited list of activities. The business runs a marketplace, charges a 3% fee as an intermediary and plans an AED 1,000 supplier subscription.
- If none of these is a licensed activity, DET can fine the company or suspend the licence.
- The Terms' claim to be "licensed" for this business would then be untrue.

**Fix (manual, by the founder):** read the "Activities" field on the licence PDF, `Dropbox/QuotesDone Backup/Assets/639183403868888392.pdf`. Record it as `licence_activities` in `company_identity_sources.json`.
- If no activity covers an online portal or marketplace, ask DET to add one before the first paid reveal.
- Check the same way that the licensed trade name matches "QuotesDone Technologies", the name used in every document.

### 5. YELLOW: the two liability caps contradict each other
- Disclaimer 1.3 s5 limits liability to "fees ... for the relevant transaction".
- Terms v10 cl.9 sets the cap at the greater of 12 months' fees or AED 1,000.

**Fix:** Disclaimer 1.4 s5 should say "as set out in clause 9 of the Terms of Service" and nothing else.

### 6. YELLOW: indicative or binding
- Disclaimer s3 says "Quotations ... are indicative only ... may differ".
- Supplier v15 cl.12 says the Supplier "is bound by a quotation that is revealed".
- The reveal fee is 3% of the quote, so if the quote is "indicative", the customer has paid a fee on a soft number.

**Fix:** Disclaimer 1.4 should say: "A Supplier is bound by its revealed quotation for its scope and validity (Supplier Agreement cl.12). The final contract may change only if the scope changes by agreement between you and the Supplier."

### 7. YELLOW: supplier fees and continued use
Supplier v15 cl.6 says "continued use ... after the effective date constitutes acceptance" of a new or changed fee. Cl.23 requires re-confirmation and a right to terminate.

**Fix:** In Supplier v16 cl.6, delete the continued-use sentence. A fee applies only after the supplier has expressly re-accepted it.

### 8. YELLOW: supplier logos used without consent
Supplier v15 cl.32 lets QuotesDone use a supplier's name or logo as a reference unless the supplier opts out.

**Risk:**
- Unauthorised trademark use (Federal Law 36/2021 on Trademarks).
- An implied endorsement in marketing (Consumer Protection Law).
- The founder's own rule is never to name suppliers publicly.

**Fix:** In Supplier v16 cl.32, make it opt-in: "only with the Supplier's prior written consent".

### 9. YELLOW: the e-commerce law is not cited
Federal Decree-Law 14/2023 on trading by modern technological means is cited nowhere in `legal.json`. It sets duties for digital platforms: disclose identity, terms, price, complaint handling and data protection. Most of these are already met in substance.

**Fix:** Add it to the governing-law list in Terms v11 and Supplier v16. Add one line to Terms cl.18 tying the complaints procedure to it.

### 10. YELLOW: leftover card-fee wording in the Refund Policy
Refund 1.8 s2 says "Both amounts and the total are shown ... no VAT is charged on either". The next paragraph says "They are separate". The Arabic text says the same ("المبلغان ... أيٍّ منهما"). These are left over from the card fee that has been removed. A price notice that does not make sense breaches the clear-price duty (Cabinet Res. 66/2023).

**Fix:** In Refund 1.9, replace them with:
- **English:** "The Reveal Fee is the total you pay and is shown before you pay. QuotesDone is not registered for VAT, and no VAT is charged on it." and "It is separate from ...".
- **Arabic:** "رسوم الكشف هي المبلغ الإجمالي الذي تدفعه وتُعرض عليك قبل الدفع. وQuotesDone غير مسجلة لضريبة القيمة المضافة، ولا تُفرض الضريبة عليها." and "وهي منفصلة عن ...".

### 11. YELLOW: five-year conversation retention
Privacy s7 rests the five-year retention of conversations only on Cabinet Decision 74/2023 Art. 3. That rule covers records relevant to tax. A chat about a job that was never revealed has no tax relevance, and PDPL Art. 5 requires that data is not kept longer than needed.

**Fix:** In Privacy 1.7 s7, add a second ground: "the five-year period within which commercial claims about the service may be brought (Commercial Transactions Law)". Keep the founder's five-year period. Data without tax relevance is now justified on the claims ground.

### 12. YELLOW: blog prices
More than 50 AED price ranges appear in blog posts (for example "AED 40–120 per square metre"), with no notice that they are indicative. A reader who relies on them could claim the prices were misleading.

**Fix:** Add a footer to every blog post in EN and AR: "Prices are indicative market ranges at the date of writing, not an offer or a quotation. Ask for quotes on QuotesDone for your exact scope." Blog copy is not a signed document, so a normal PR is enough.

### 13. YELLOW: cross-border transfers
All data is hosted in Singapore (Supabase), and other providers process it in the US. Privacy s6 cites PDPL Arts. 22 and 23. No register of each provider's data processing agreement (DPA) or transfer clauses exists.

**Fix:** Create a single file, `docs/legal/TRANSFER_REGISTER.md`. For each provider, list the DPA link, its date and its transfer mechanism (Supabase, Vercel, OpenRouter and its model providers, Resend, Microsoft, Meta, Twilio, Stripe, Dropbox, Serper). Confirm that OpenRouter routes with "no training on data" turned on.

### 14. YELLOW: the VAT threshold
The 3% fee has no cap. One reveal on a quote of AED 12.5M is an AED 375k fee, so a single reveal can cross the mandatory registration threshold. Registration is due within 30 days of crossing it, and the threshold counts the last 12 months or the next 30 days. The Terms already promise notice before any VAT is charged.

**Fix:** The accountant seat should alert when 12-month fees pass AED 300k, and when any single pending reveal would push the total over AED 375k.

### 15. YELLOW: fixed compensation amounts
The amounts are AED 5,000 (Terms cl.6), AED 10,000 (Supplier cl.10), AED 20,000 (Terms cl.21 and cl.23, Supplier cl.24 and cl.36) and AED 25,000 (Supplier cl.25). Supplier cl.24 also bars dealing off-platform for 24 months. All are drafted as genuine pre-estimates, apply to businesses only, and leave the court's power to adjust in place, so they are lawful.

**Risk:** the risk is in enforcement. A court will cut them to the actual loss.

**Fix:** None to the text. Before claiming any of these amounts, keep evidence of the actual loss.

### 16. GREEN: government bodies named
The services and FAQ pages name DEWA, Dubai Municipality, Civil Defence, SIRA and MoIAT/ESMA.

**Fix:** Add one line to the services page: "QuotesDone is independent and is not affiliated with or endorsed by any authority named here."

### 17. GREEN: the TDRA NOL
NOL-26-100000665 covers quotesdone.ae and is valid until 14 Sep 2027. The trade licence expires 24 Jun 2027, first.

**Fix:** The it_engineer seat should set renewal reminders for 24 May 2027 (licence) and 14 Aug 2027 (NOL). The registrant name on the .ae domain must match the licence.

### 18. GREEN: e-signature
Terms cl.16 and Supplier cl.1 and cl.30 treat "continuing to use the Platform" as acceptance. Under Federal Decree-Law 46/2021, a click on the acceptance box, together with the archived acceptance certificate, is the strong evidence; continued use is weak. Calling the records "conclusive" does not bind a court.

**Fix:** In Terms v11 and Supplier v16, drop "or continuing to use", and change "conclusive" to "evidence".

### 19-21. Already compliant
- **No card surcharge:** Terms cl.4 and Supplier cl.8 comply with Cabinet Res. 66/2023.
- **Intermediary status:** Terms cl.8, with carve-outs for fraud, harmful acts, injury and consumer rights, is sound.
- **Cookies:** the cookie banner and policy say "essential only", and that matches the code (`CookieConsent.tsx`).
- **Consumer carve-outs:** Terms cl.11 and cl.22 are drafted correctly.

**Citations to check:** some article numbers cannot be verified from the repository: Civil Transactions Law Federal Decree-Law 25/2025 Arts. 257, 334(2) and 236; Commercial Transactions Law Arts. 252, 258 and 265; PDPL Arts. 14-16 in Supplier cl.16. Read them against the official text at uaelegislation.gov.ae before the v11 and v16 texts are published.

---

## New versions needed (signed versions are never edited)

| Document | From | To | Findings |
|---|---|---|---|
| Customer Terms | v10 | **v11** | 1, 2, 9, 18 |
| Supplier Agreement | v15 | **v16** | 1, 2, 7, 8, 9, 18 |
| Privacy Policy | 1.6 | **1.7** | 3, 11 |
| Refund Policy | 1.8 | **1.9** | 1, 10 |
| Disclaimer | 1.3 | **1.4** | 5, 6 |
| Blog and services copy | n/a | a normal PR | 12, 16 |

Each new version follows the pattern of #1234 and #1250:
- English and Arabic text in `legal.json` (the Arabic prevails);
- a pending SQL file in `scripts/sql/pending/` that adds the registry row and its body hash, applied at merge;
- the change notice on the page;
- the `company_facts` version;
- `the_refund_ladder_texts_agree` kept green;
- Terms v11 and Supplier v16 need re-acceptance. The 30-day notice in Terms cl.13 and Supplier cl.23 applies, and consumers must accept expressly.

**Status:** these PRs have **not** been opened in this session. Each needs Arabic legal drafting of equal standing plus registry SQL. They go to the release operator as the work list above, signed `ceo:`. Finding 4 needs the founder to read the licence PDF.
