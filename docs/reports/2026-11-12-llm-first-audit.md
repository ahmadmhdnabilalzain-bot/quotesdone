# Where code decided what a document or a person meant, over or instead of the model

Read-only audit of 12 Nov 2026 by the it_engineer seat, after founder rulings 1663, 1664 and 1666 (the model reads and
understands; code does not interpret first and never overrides it). It was made by reading the code and its callers.
Nothing was run, so every "wrong input" below is traced through the code, not observed. Two of its examples were later
shown to be wrong by the engineers who reproduced the findings: "crack", "brackets" and "track" do not contain the
letters r-a-k and were never filed in Ras Al Khaimah (the real cases were "Mubarak" and "brake"), and "JLT, Dubai" was
not moved on main.

What became of each class A finding, as of the evening of 12 Nov 2026:

| Finding | Subject | Outcome |
|---|---|---|
| Licence | The expiry and every other licence field | PR #1978: the model's reading is the reading; code's is never stored or shown |
| A1, A7 | The emirate; the four sales-engineer questions (portal request chat) | PR #1979 |
| A6 | A filed answer moved by code | Taken out of #1979 after review proved it reopened the RFQ 164464 failure; redesigned on branch `sales_engineer-a-filed-answer-stands` (the model confirms each filing), not merged |
| A3, A4, A5 | Services typed in his own words; "supply only"; the licence's activities | PR #1980 |
| A9 | A catalogue's products | Taken out of #1980 after review (one capped model call cannot read a 20-page priced catalogue); kept on branch `sales_engineer-the-model-reads-a-catalogue`, not merged. Production held 0 catalogues |
| A2 | A quotation's total; whether an e-mail is a quotation | Not started |
| A8 | Opt-out from the invitation mailbox by a word list | Left as it is: it follows the compliance ruling of 28 Oct 2026 |

The audit's text follows unchanged, apart from this header.

---

Scope: supabase/functions, in the three surfaces in the brief. Method: grep and read only. Nothing was built, run or
deployed. "Verified" means I read the code and its callers. "Inferred" means I worked it out from the code and did not run it.
Paths are relative to supabase/functions/ unless they say otherwise.

## 0. The memory file, quoted exactly

`.claude/memory/code-extremely-well-built.md` (frontmatter `modified: 2026-09-14`):
- description: "Founder 14 Sep 2026 — code must be extremely well built; every helper PR gets an independent code+security review before merge; code first, LLM only where code can't"
- body quote: "the code need to be extremely well built" and "i am not saying no LLM at all. but if something can be coded then we do it" (14 Sep 2026).
- **How to apply** (verbatim, excerpt): "Anything a rule/SQL/code can do is coded; a model is used only for genuinely open-ended work (reading arbitrary drawings/documents, free-text conversation), always with a deterministic fallback. Exception he granted 14 Sep: 'in the case of the boq and drawing, i dont mind using LLM to confirm the result' — coded extraction is primary; one scoped vision call ... confirms it".
- Note: the body itself already puts "reading arbitrary drawings/documents, free-text conversation" on the model side. The "code first, LLM only where code can't" line in the description is the line that `_shared/document_expiry/licence_model.ts:18` quotes. Rulings 1663/1664 supersede the description line and the clause "always with a deterministic fallback" (a fallback that answers silently). The drawing exception, "coded extraction is primary", also needs restating.

## 1. The licence, one line only (another engineer is fixing it)

Confirmed: `_shared/document_expiry/licence_model.ts:18-43` `mergeLicenceReads` keeps every field code read and lets the model fill only the blanks.
**However, verified by grep, it has no non-test caller.** The LIVE paths apply the same rule through their own code:
- `supplier_api/lib/licence_store_first.ts:70-84` `modelReadingToRow`: the number, authority, emirate and name are taken from the model only when code left them blank. On expiry, the model's date is only recorded beside code's as `expiryDiffers` and never replaces it (`supplier_api/actions/documents.ts:215-247, 411`).
- `supplier_portal/actions/documents.ts:136-160, 186-190`: code's `readExpiry`, `readLicenceName` and `readLicenceFields` are written first. The model is called only if code missed the expiry or a field (`!licExpiryFromDoc || fieldsLeftUnread`), and then it fills only the blanks.
The fix has to cover these two files as well as `mergeLicenceReads`.

## 2. Counts

| Surface | A | B | C (listed in section 6) |
|---|---|---|---|
| 1 Licence and supplier documents (licence itself excluded) | 0 | 3 | 7 |
| 2 Company profile, services, catalogue | 4 | 5 | 5 |
| 3 Sales agent, chats, intake, email, quotes | 5 | 12 | 12 |

## 3. Class A, ranked by harm

### A1. The emirate is a substring search, and "rak" matches any word that contains it (customer, every request chat)
- `inquiry_intake/classify.ts:18` `detectEmirate`: `t.includes(e.toLowerCase())`, then `if (t.includes('rak')) return 'Ras Al Khaimah'`. Its input is every user turn of the request chat (`handle.ts:150, 225`).
- Where the answer is used: `handle.ts:626, 663` (`withUniversal(... universalAnswers({ emirate }))` fills the request's LOCATION spec), `:859` (code's emirate is passed before the model's `out.brief.emirate` to the blocking gate), `:958` (it becomes `brief.emirate` when the model gave none), `:1029` (it is the supplier count shown to the customer).
- Model status: PRE-EMPTED, and on :859 and :1029 it OVERRIDES the model's emirate.
- Wrong inputs: "wall **crack** repair in my villa", "TV **brack**ets", "**track** lighting for the shop", "name: Mubarak" with no emirate stated. Each is read as Ras Al Khaimah. Inferred from the code path: the location question is then never asked, and the request is counted and placed in RAK. With two emirates the first one listed wins ("moving the office from Abu Dhabi to Dubai" gives Dubai).
- What the person sees: a request filed in the wrong emirate, the wrong supplier count, and the matched suppliers in the wrong emirate. HIGH: it loses or misroutes requests.
- (public_site/index.ts:66-79 has its own detectEmirate using `\brak\b`, which does not have this bug.)

### A2. Quotation reading: code finds the total and the lines, and decides the file is a quotation (supplier to customer)
- `quote_extract/index.ts:67-94`: "CODE FIRST ... the model is asked only when code found no total". A priced code reading is returned with `extracted_by_model: 'deterministic'`. If code finds a total but is unsure (`total_ambiguous`), the file is held for the supplier, "never handed to a model".
- `resend_inbound/quote_by_email.ts:88-95, 173-177` `isQuotation`: a mail is a quotation when the code reader priced it. That includes an e-mail BODY with one priced line when the supplier has one open request (`only_open`). It then goes to `supplier_api/email_quote.ts` (extract, then submit). Per that file's header, the review rules decide whether it is SENT TO THE CUSTOMER.
- Model status: SKIPPED whenever code prices the file.
- Wrong inputs (inferred): a quotation with options ("Option A total 12,000 / Option B total 9,500"), or one that prints "Advance 50%: 5,250" under the total. An e-mail from a supplier with one open request saying "our minimum call-out charge is AED 150, we will visit Sunday", which is read as a priced quotation and submitted. An invoice for another job attached to a reply.
- What the person sees: a wrong total or a non-quote submitted on the supplier's behalf, which the customer may receive. HIGH: a wrong figure can reach a customer. On the portal, the supplier reviews the proposal before submitting, which limits the harm there.

### A3. The supplier's services from his own words: code matching, and the model only when code finds nothing (supplier registration)
- `_shared/supplier_services.ts:416-470` `servicesRewrite`: exact names and aliases (`service_rewrite.ts` rewriteServices), then gte-small embedding "meaning" (`service_meaning.proposeByMeaning`), then implications. `readWithModel` runs only "CODE READ NOTHING" (`:466-468`). Live callers: `supplier_api/actions/capabilities.ts:84` (`services_rewrite`, the Services tab's "Add a service we missed" box in `src/components/portal/supplier/ServicesTab.tsx`) and `:95`, where the answer to "Something else" on a question card is mapped by this same rewrite.
- Model status: SKIPPED whenever one phrase matched exactly or by vector.
- Wrong inputs: "Supply & fix of gypsum partitions and some painting touch-ups" matches "painting" exactly. "Supply & fix" is not understood, and the embedding proposes from the remaining clauses. "We do everything except plumbing": one exact part ("plumbing") would name plumbing if the split leaves it whole (inferred). Gulf Arabic: "نسوي صيانة مكيفات وتنظيف دكت" is read only by alias and vector.
- What the person sees: the wrong service cards proposed. The exact ones are listed as his, and the meaning ones stay off until he adds them. MEDIUM: it mis-profiles a supplier, and matching reads the confirmed keys.

### A4. "Supply only" is decided by word lists (supplier registration)
- `_shared/catalogue_read.ts:100-130` `supplyOnlyOf`: true when there is any trading word ("trading", "dealer", "تجارة", "للتجارة") and none of the install words. Applied in `supplier_services.ts:427-429` (it changes the rewrite, and every implication comes back struck out) and stored for catalogues (`supplier_doc_trades.ts:141, 326`).
- Model status: PRE-EMPTED. The supplier can override it with a toggle.
- Wrong inputs: "Al Noor General Trading LLC – we clean water tanks and do pest control" ("clean" and "pest control" are not install words). "شركة النور للتجارة – نقوم بتنظيف الواجهات" ("cleaning facades").
- What the person sees: "supply only" proposed, installation services refused, and implications struck out. MEDIUM-LOW: it is visible and he can override it.

### A5. Licence activities read by a label parser are the only licence text the model sees (supplier registration)
- `_shared/supplier_doc_trades.ts:194-197` `preparedText('licence')`: the model gets only `'Activities: ' + licenceFieldsFromText(text).activities`. `:326` stores the same list. `_shared/supplier_profile_reading.ts:408-412` builds the supplier-facing card "Your trade licence lists {first 3 code-read activities}. Your profile is about X. Which is your business today?". `:266-268` is the model's per-service licence verdict, which goes to the ticket `licenceScopeCheck` (`:388-405`).
- Model status: PRE-EMPTED. The model judges "covered / not covered" against what code parsed, and never sees the licence itself.
- Wrong inputs (`document_expiry/licence_fields.ts:142-181`): activities printed on the same line as the label are split at commas, so "Activities: Air-Conditioning, Ventilation & Air Filtration Systems Installation" becomes two activities. Activities in a table with an "Activity Code | Activity Name" header, or printed at the bottom of the page, are mis-read or missed. An Arabic-only licence's activities are read only under 'الأنشطة' or 'النشاط'.
- What the person sees: a wrong "not on your licence" card and a sales-engineer ticket. If the parser read nothing, the check is silently 'unclear'. MEDIUM: it mis-profiles and creates friction, but it is never a rejection.

### A6. A spec value the model filed is moved by code if it "looks like" a date, money, warranty or emirate (customer request chat)
- `inquiry_intake/interview.ts:318-346` `statementKind`/`answersAnotherKind` (with `parseWhen` :107, `parseBudget` :144 and `parseEmirate`) is applied to the model's own filing in `slots.ts:263-273` `reconcileSlots.put`. The value is moved to the "universal" field, or dropped, and the spec stays open. `parseAnswer` (:349-352) applies the same test to the customer's typed answer.
- Model status: OVERRIDDEN.
- Wrong inputs: field "Which area / community?" (`kindOf` reads "area" as a measure) answered "JLT, Dubai", which is treated as an emirate statement and moved to location. "AMC contract period?" (no "duration" or "date" in the key) answered "12 months" is read as a timeline, moved to required_by, and AMC period stays open. "Hire period" answered "2 weeks" goes the same way.
- What the person sees: the same question asked again, and possibly a wrong required_by. It breaks the "never repeat" ruling (1631). MEDIUM.

### A7. The four sales-engineer questions (installation, warranty, materials, needed-by) are parsed only by code (customer request chat)
- `_shared/intake_requirements.ts:247-260` `parseRequirementAnswer`. `:346-370` `statedAnswers` reads the whole conversation. `:405-425` `requirementsStep` runs at status 'ready' (`inquiry_intake/handle.ts:885-905`). The model's `requirementsFromModel` fills only first. After that, the customer's reply to the question just asked is read by code alone, and if code can't parse it the reply is "I couldn't match that to one of the answers. Tap an option below".
- Model status: SKIPPED for the reply to the question just asked.
- Wrong inputs: "Supply and fix please" (no "install" or "supply only" in it) gets "couldn't match". "Yes but only the outdoor units, our own guy does the indoor" is read as plain yes. In `statedAnswers`, "no installation needed in the kitchen, but the majlis needs full installation" is read as supply_only because the supply-only test comes first. "Usual manufacturer warranty is fine" gets "couldn't match".
- What the person sees: a refusal to understand, or a wrong installation answer that suppliers then quote on. MEDIUM.

### A8. Opt-out from the invitation mailbox is decided by a word list, and the rest of the mail is lost (invited suppliers)
- `_shared/unsubscribe_mailbox.ts:22-34` (PHRASE on the subject or first line), `:40-90` (`lineSaysStop`: on supplier@, any of the first three lines whose words are all opt-out phrases or fillers; the list includes "no", "no thanks", "not interested", "لا", "غير مهتم"). It is applied in `resend_inbound/steps/bounce_unsubscribe.ts:35`, which suppresses the sender and returns. `_shared/customer_mail.ts:109` then refuses to answer.
- Model status: SKIPPED. This was a deliberate coordinator ruling of 28 Oct ("a stop must be honoured whether or not any model is reachable").
- Wrong input: a reply to the invitation that reads "Hi,\nNot interested in the paid plan.\nWe'd like to register for free – how?" Line 2 is a stop, so the sender is suppressed and the question is never answered.
- What the person sees: silence, and no more invitations. LOW-MEDIUM: only cold outreach stops, but a supplier lead is lost. I recommend the model reads it, with code as the floor only when no model answers.

### A9. Catalogue products: a priced line is a product, and one priced line skips the model (supplier registration)
- `supplier_catalog_ingest/index.ts:281-288` "CODE FIRST ... a line that prints a price is a product". `rows_from_text.ts:16-31`. The model runs only `if (!products.length)`. Rows go to `supplier_product` with status 'extracted' (`index.ts:342`).
- Model status: SKIPPED if even ONE line prints a price.
- Wrong inputs: a 40-page product catalogue with a single "Delivery charge AED 150" or "Minimum order AED 500" line gives one product, "Delivery charge", and the rest of the catalogue is never read.
- What the person sees: a near-empty or wrong product list for the supplier. MEDIUM-LOW (inferred: I did not trace who reads `supplier_product`).

## 4. Registering supplier vs customer side

- Supplier REGISTERING from Monday can hit: A3 (services box and "Something else"), A4 (supply only), A5 (licence activities card and ticket), A9 (catalogue upload), A8 (if he replies to an invitation e-mail). He also hits the licence bug being fixed (section 1: supplier_api process_docs and the supplier_portal documents tab). On WhatsApp: B3-1 (a thank-you gets no reply), B3-2 (loop guard) and B1-3 (caption keywords on pending documents). The WhatsApp licence path is MODEL-led and correct (`wa_inbound/media.ts:62-75` isConfidentLicence).
- Customer side: A1 (emirate), A6 (misfiled specs), A7 (four SE questions), A2 (a wrong quote total reaching them).

## 5. Class B (pre-filter or fallback; cheap or corrected)

Surface 1
- B1-1 `_shared/read_every_attachment.ts:73-74`: a text layer with 12 or more letters counts as "read by code" and the vision model is skipped. A scanned licence or profile whose PDF carries only a short text footer (a scanner or portal watermark) is "read" as that footer (inferred). Callers then judge the text, and a licence path still asks license_extract.
- B1-2 `supplier_portal/actions/documents.ts:136, 166-176`: for insurance, ISO and manufacturer certificates, code's `readExpiry` date is returned, and the model ('cert' mode) is asked only when code read none. Same pairing risk as the licence, but returned `needs_confirm` unless the typed date matches, so the supplier confirms it.
- B1-3 `wa_inbound/media.ts:62-63, 152-156`: a caption without licence words goes to `fn_wa_attach_document`, which files the document by caption keywords (SQL, not read). The file is PENDING for a person and never applied, so it costs little.

Surface 2
- B2-1 `_shared/supplier_doc_trades.ts:139-142` + `catalogue_read.ts`: catalogue lines sorted by code. Spec rows and contact/LLC lines are dropped before the model sees them, so "AMC available: Yes" (a bare-Yes cell) or "XYZ Contracting LLC – Fit-out division" never reach the model (inferred from the header rules).
- B2-2 `supplier_doc_trades.ts:150-154` `withoutCredentialLines`: ISO lines are dropped unless they say certification, audit, consultancy or training services. A certification-consultancy profile that writes "ISO 9001:2015 implementation for SMEs" is kept, while "ISO 45001:2018 – we help you get certified" is dropped (no listed phrase).
- B2-3 `_shared/supplier_profile_reading.ts:247-270` `codeKeysOf`: a phrase that IS a catalogue name or alias is mapped by code before the model maps it. Exact whole-phrase match within the model's chosen trade, so it rarely goes wrong.
- B2-4 `_shared/supplier_service_questions.ts:180-245`: the model's chip suggestions are rebound to catalogue keys by stemmed word overlap. The supplier taps the chip and sees the catalogue label.
- B2-5 `supplier_doc_trades.ts:174-190` `offerText`: brings "we offer / our services" lines first. Ordering only, because the whole document follows.

Surface 3
- B3-1 `wa_inbound/burst.ts:131-135, 152-160` `thanksOnly`: a closed, anchored thanks-only list gets no model and no reply, but only when our last reply asked nothing. Wrong case: sarcastic "great, thanks" after "the supplier cancelled", which leaves a complaint unanswered.
- B3-2 `_shared/auto_reply_loop.ts:23-35`: messages are judged "machine-sounding" by phrase. A person who writes "ساعات العمل؟" ("working hours?") or "I'm travelling, can they come Sunday?" counts as a machine. A stop needs 3 of our replies with no human message in between, so this is rare.
- B3-3 `_shared/conversation_trade.ts:32-92` (used by `company_brief.ts:22`): the customer's words pick the ONE trade pack the chat model is given. "AC duct cleaning" gives the cleaning pack (cleaning is listed before hvac). "My bathroom tiles are leaking" gives tiling. "smart quote for AC" gives smart-home. The model still reads the message, but gets the wrong verified knowledge.
- B3-4 `wa_inbound/menu_flow.ts:130-142` + `faq.ts`, `fn_faq_answer`: text rank plus gte-small at 0.84 picks the FAQ the model is told is "approved knowledge for this question". The model writes the reply. `welcomeFirstContact` and `reofferMenu` have no callers (dead), and `answerFromFaq` is called only from founder.ts.
- B3-5 `marketing_social_inbox/reply.ts:57-66`: the model picks the meaning, and the reply is a library row, an FAQ answer or a corpus passage sent VERBATIM (clipped at 700 characters). That conflicts with ruling 1195-1197 as WhatsApp applies it.
- B3-6 `public_site/index.ts:86-95`: the model may only choose among `fn_kb_route_decide` candidates, which come from alias substring matching (per the handle.ts:220 comment; I did not read the SQL). No candidate means the visitor is asked to describe the job.
- B3-7 `_shared/inquiry_state.ts:94-110` `saysDontKnow`: "Not sure, maybe 2 ton for the bedroom" marks the asked key unknown. A value the model filed still wins in reconcileSlots.
- B3-8 `wa_inbound/reprice_outage.ts:54-60`: when the model is down, a supplier message with any number gets a code-written "if it asks to change your price (to AED 3)..." notice and the turn ends, so a non-price question is lost until replay (outage only).
- B3-9 `_shared/support_case_memory.ts:131-134` + header: before the reply, the case is the named case or the newest open one (code). The model's same-matter decision comes after the reply.
- B3-10 `quote_compare/index.ts:351, 452, 482`: if the model fails, the customer gets a deterministic ranking marked `degraded: true`. It is an honest label, but a silent answer.
- B3-11 `inquiry_intake/slots.ts:182-204` + `handle.ts:613-616` `readHeldAnswer`/DEFERRAL: code reads the answer to a held spec. The model's filing overrides it (reconcileSlots puts the model value after the previous one).
- B3-12 Language by script: `wa_inbound/menu.ts:21-25`, `general_turn.ts:126`, `media_in.ts:114-117` (the last also picks audience 'customer' when Arabic, else 'visitor'), and `fn_wa_route` `v_latin`. An Arabizi customer ("abi a/c service") gets English.

## 6. Class C (legitimate code; stays)

- Licence and documents: file-size ceiling (`licence_model.ts:8-12`); `isConfidentLicence` checks the MODEL's reading before applying it (`wa_inbound/media.ts:65-71`); sanitize/scan/mime gates; the licence-number clash set-aside (`duplicate_company.ts`); the PDF text-layer extraction in doc_extract and inbound_email ("code first" there means transcription, not meaning); the late-write guard `writerForFile`; resend_inbound supplier docs are classified by the model (`steps/supplier_docs.ts:117-146`).
- Profile and services: `checkReading` (each quote must stand in a non-licence document, and a key must be ours); `applyMapping` (the key is a catalogue key of a trade that was shown); HEADING_ONLY rejecting a heading as proof; `partner_match.ts` ordering and hiding; `licenceScopeCheck` is never a rejection.
- Chats and intake: `directive_gate.ts` `amountInOwnWords` (the model's amount must stand in the supplier's words); `fn_supplier_apply_change` scoped by phone; `model_says.ts` and `status_lane.ts` DECLINES check the MODEL's output; `menuChoice` (list IDs, a digit only right after the menu); `fn_wa_route` routes on the reasoned intent; `namedCase` (a case ref the person typed); `requestNumbersIn`/`chooseRequest`/`verifiedSender` (known facts, ask on two candidates); the mailbox hard rules (bounce, no-reply, own addresses) and email_triage's unread-classification hold; think's `figuresGrounded` (internal audiences only); the widget `quoteAnswer` metres arithmetic (the model picks the quote and field); `login_otp` code routing; `drawing_boq` printed-tag counts merged with the model reading (an exception the founder granted, and outside these surfaces).

## 7. What I could not determine

- SQL I did not read: `fn_kb_route_decide`, `fn_faq_answer`, `fn_wa_attach_document`, `fn_wa_menu_context`. I describe them from code comments.
- Whether an e-mailed quotation with a code-read total is actually sent to the customer without supplier review. email_quote.ts says the review rules decide; I did not trace `submit.ts` and the hold evaluator.
- How many live checklist keys fall into A6 (it depends on `category_specs`/`trade_spec_checklist` data in the database).
- Who reads `supplier_product` (A9 harm).
- Nothing was executed, so every "wrong input" is traced through the code by reading, not run.
