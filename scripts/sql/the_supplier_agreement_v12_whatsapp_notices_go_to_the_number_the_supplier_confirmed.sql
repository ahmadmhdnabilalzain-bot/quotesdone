-- THE SUPPLIER AGREEMENT v12: A WHATSAPP NOTICE GOES TO THE NUMBER THE SUPPLIER CONFIRMED, AND EVERY FORMAL
-- NOTICE FOLLOWS THE VERSION THE SUPPLIER ACTUALLY ACCEPTED.
--
-- Agent: sales_engineer. Founder, 14 Sep 2026, answering "clause 21 of v11 sends WhatsApp notices to the registered
-- mobile: should they go to the WhatsApp number the supplier confirmed?": "whatsapp number supplier confirmed."
--
-- DEPENDS ON PR #657 (the_whatsapp_number_is_confirmed_and_only_a_confirmed_one_is_used.sql): leads.whatsapp_opt,
-- public.fn_verified_mobile and public.fn_whatsapp_destination. This file refuses to run without them and copies
-- none of them.
--
-- WHAT CHANGED IN THE TEXT (v11 -> v12, both languages; GENERATED from src/content/legal.json by the signed-body
-- rule that reproduces the v11 body byte-for-byte, sha 0510081a0fb6a4e061201c31fd4014fd9d22af6c1502a13c397a645401be9d36)
--   clause 21 (c) WhatsApp goes to the WhatsApp number the Supplier confirmed in the portal by a verification code
--             sent to that number, or, where it confirmed its registered mobile is its WhatsApp, to that mobile.
--             (d) SMS stays on the registered mobile. The details the Supplier keeps current now include the
--             confirmed WhatsApp number. Nothing else changes: no other clause cross-references clause 21's channel
--             (clause 22 is the language clause; clause 32 is consent to communications and names no number).
--   v11 stays word for word at /supplier-agreement/v11 (legal.json supplier-agreement-v11, plus only its
--   "Superseded" line, as v10 was kept).
--
-- WHAT WAS MEASURED BEFORE THIS FILE (repository, 14 Sep 2026):
--   * Every formal supplier notice reaches WhatsApp one of two ways: trg_wa_fanout's twin of the email row that
--     fn_customer_support_acts_on_handoff writes (type = the notice's msg_type), or fn_originator_checks_delivery's
--     one retry on WhatsApp or SMS. After #657, a03_notifications_whatsapp_goes_to_a_confirmed_number addresses
--     EVERY supplier WhatsApp row to fn_whatsapp_destination whatever version the supplier accepted - so a v11
--     supplier's demand would go to a number v11 never named, and a v10 supplier (email and portal only) would get
--     WhatsApp and SMS notices it never agreed to.
--   * fn_accountant_collections_tick held every demand below v11 and cited "v11" in its finding whatever the
--     supplier had accepted.
--
-- WHAT THIS CHANGES
--   1. The registry: legal_supplier_body, legal_documents and the terms pins move to v12 (as the v11 file did).
--   2. fn_supplier_notice_channel: the rule, pure: v12+ -> the confirmed WhatsApp number (fn_whatsapp_destination);
--      v11 -> the verified registered mobile (unless the supplier said it has no WhatsApp); older -> no WhatsApp
--      and no SMS. SMS: v11+ -> the verified registered mobile. fn_supplier_notice_route reads the supplier's row
--      and applies it, with the clause 21 wording of the version accepted (decision_policy).
--   3. a06_notifications_supplier_notice_follows_the_accepted_agreement: every formal supplier notice
--      (decision_policy supplier_formal_notice_types) on WhatsApp or SMS is addressed by that route AFTER #657's
--      a03, or recorded 'skipped' with the reason. A notice never goes to a channel the supplier has not agreed to.
--   4. z06_supplier_notice_whatsapp_twin_under_v11: a v11 supplier who has not answered the portal's WhatsApp
--      question gets no twin from trg_wa_fanout; v11 still names the registered mobile, so this adds the twin
--      (a06 addresses it). v11 already covers the notice: nothing is held because v12 is not yet accepted.
--   5. fn_accountant_collections_tick (body otherwise as the_accountant_chases_what_a_silent_supplier_owes.sql):
--      the demand gate still needs v11 or later (supplier_charge_demand_min_agreement_version = 11), and every
--      notice payload carries the clause 21 wording and WhatsApp basis of the version the supplier accepted
--      ({{notice_clause_en}}, {{notice_clause_ar}}, {{whatsapp_basis}} for the templates). It is redefined HERE,
--      not by re-applying its owning file, because that file's decision_policy upsert would reset
--      supplier_charge_recovery_basis.confirmed to false.
--
-- WHAT THIS DOES NOT CHANGE: #657's routines and trigger; non-notice WhatsApp (RFQ alerts and chat follow #657
-- alone); customer notices; any fee, rate or other clause. Existing suppliers re-accept through the same portal
-- card and supplier_api accept_terms that v11 used; until they do, notices follow the version they accepted.
--
--   apply order: #657's file, then this file:
--   node scripts/apply_sql.mjs scripts/sql/the_supplier_agreement_v12_whatsapp_notices_go_to_the_number_the_supplier_confirmed.sql --apply --ddl
--   then deploy supplier_api (it carries the v12 text and hash in _shared/supplier_agreement.ts).

begin;

-- ── 0. #657 MUST BE LIVE ──────────────────────────────────────────────────────────────────────────
do $need$
begin
  if to_regprocedure('public.fn_whatsapp_destination(text, uuid, bigint, text)') is null
     or to_regprocedure('public.fn_verified_mobile(text, uuid, bigint, text)') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'leads' and column_name = 'whatsapp_opt') then
    raise exception 'apply PR #657 (the_whatsapp_number_is_confirmed_and_only_a_confirmed_one_is_used.sql) first: fn_whatsapp_destination, fn_verified_mobile and leads.whatsapp_opt are required';
  end if;
end
$need$;

-- ── 1. THE REGISTRY ───────────────────────────────────────────────────────────────────────────────
update public.pages set html = $qd_supplier_agreement$<style id="qdmf">html,body{overflow-x:hidden;max-width:100%}.body{overflow-wrap:anywhere;word-break:break-word}.body table{display:block;width:100%;overflow-x:auto;-webkit-overflow-scrolling:touch}.body img{max-width:100%;height:auto}</style><h1>Supplier Agreement</h1><div class="muted">For suppliers registering and quoting on QuotesDone. Version 12 · governed by the laws of the United Arab Emirates.</div><div class="card"><h2>1. Agreement &amp; acceptance</h2><p>This Supplier Agreement (the "Agreement") is a binding contract between QuotesDone Technologies (كوتس دن للتكنولوجيا), a Sole Establishment licensed by the Dubai Department of Economy and Tourism (DET) under Trader License No. 1633275, Dubai, United Arab Emirates, which operates the QuotesDone platform ("QuotesDone", "we", "us", "the Platform"), and the registering business ("you", "the Supplier"). By ticking the acceptance box during sign-up, or by using the Platform, you confirm that you have read, understood and agree to be bound by this Agreement. Ticking the box constitutes a valid electronic signature under UAE Federal Decree-Law No. 46 of 2021 on Electronic Transactions and Trust Services. If you are accepting on behalf of a company, you warrant that you are authorised to bind that company.</p>
<h2>2. Definitions</h2><ul><li><b>Customer</b> — a user who requests quotations through the Platform.</li><li><b>Quotation Value</b> — the total price the Supplier quotes for a job, exclusive of VAT.</li><li><b>Reveal</b> — the point at which a Customer pays to unlock and select a Supplier for a job; a job is "won" upon Reveal.</li><li><b>Subscription Fee</b> — the annual supplier subscription fee described in clause 6.</li><li><b>Working Days</b> — days other than Saturdays, Sundays and UAE public holidays.</li></ul>
<h2>3. Eligibility &amp; registration</h2><p>To register you must be a lawfully established business in the UAE holding a valid trade licence covering the services you offer, and the individual registering must be authorised to act for that business. You agree to provide accurate, current and complete company, licence, tax (TRN), bank and contact information and to keep it updated.</p>
<h2>4. Account &amp; security</h2><p>Access is secured by one-time-code verification. You are responsible for activity on your account and for keeping access credentials and the registered email secure. Notify us immediately of any unauthorised use.</p>
<h2>5. The service</h2><p>QuotesDone is an anonymous quotation marketplace and technology platform. Customers post jobs and receive anonymised quotations; the identities of Customer and Supplier are released only through the Platform after a Reveal. QuotesDone is an introducer and facilitator only; it is not the contractor, is not a party to the contract for the work, and does not supervise, perform or guarantee any work.</p>
<h2>6. Registration &amp; subscription fees</h2><p>Supplier registration is <b>free of charge for the first 1,000 businesses to register</b> on the Platform, permanently. From the <b>1,001st registration</b> a subscription fee of <b>AED 1,000 per year</b> applies, payable annually in advance. QuotesDone will give at least 30 days' notice and seek re-confirmation of acceptance before introducing or varying the fee, as set out in the Amendments section; continued use of the Platform after the effective date constitutes acceptance. The subscription fee, once paid, is non-refundable except as expressly stated at the time.</p>
<h2>7. No supplier commission</h2><p><b>QuotesDone charges the Supplier no commission on any job won through the Platform</b> — not on the Quotation Value, not on the amount finally invoiced, and not on repeat work with the same Customer. The Platform is funded by the subscription fee in clause 6 and by a fee payable by the Customer at Reveal. QuotesDone reserves the right to introduce a supplier commission in future only on at least 30 days' notice and re-confirmation of acceptance as set out in the Amendments section; no commission is or becomes payable under this version of the Agreement.</p>
<h2>8. Payment terms</h2><p>Where a Subscription Fee is payable under clause 6, it is payable annually in advance, by card or by bank transfer, on the renewal date of the Supplier's account. QuotesDone may issue an invoice or statement for amounts due; payment is not conditional on receipt of an invoice. All amounts are in AED unless stated. Separately, the Customer — not the Supplier — pays QuotesDone a reveal fee of <b>3% of the Quotation Value</b>, plus a card processing fee, at the moment of Reveal. Nothing is deducted from, or charged on, the amount the Customer pays the Supplier for the work.</p>
<h2>9. Late payment</h2><p>If a Subscription Fee is not received by its due date, QuotesDone may, after giving the Supplier notice and a further <b>7 Working Days</b> to pay, suspend the Supplier's account until payment is made. Unpaid Subscription Fees are debts due and payable and may be recovered through the competent UAE courts. Overdue amounts carry interest at the single rate set out in clause 31. QuotesDone holds no funds for the Supplier (it collects only its own fees), so no set-off against held sums applies.</p>
<h2>10. Anonymity &amp; non-circumvention</h2><p>The Platform's value depends on anonymity. The Supplier must not, during anonymised stages or in on-platform chat, share or solicit phone numbers, email addresses, links, WhatsApp or other messaging or social-media handles, or otherwise attempt to take dealings off the Platform or bypass the Reveal. Any such disclosure or circumvention entitles QuotesDone to suspend the Supplier's account and to a liquidated sum of <b>AED 10,000 per incident</b>, agreed as a genuine pre-estimate of the lost platform value and lost subscription revenue, which is the sole monetary remedy for that incident (QuotesDone will not separately claim general damages for the same act). For a first and evidently inadvertent technical breach, QuotesDone may at its discretion issue a written warning instead of applying the sum. The Supplier acknowledges that this sum is agreed compensation (liquidated damages) under the UAE Civil Transactions Law, which a competent court may adjust to the actual loss.</p>
<h2>11. Supplier obligations &amp; conduct</h2><p>The Supplier shall: honour every quotation it submits and any agreed timeline; respond to revealed Customers professionally and promptly; deal honestly and not engage in collusion, bid-rigging or price manipulation; and comply with all applicable UAE laws, including the Consumer Protection Law (Federal Law No. 15 of 2020) and health-and-safety requirements. QuotesDone, for its part, will operate the Platform in accordance with its own obligations as a digital marketplace under that law and its executive regulations.</p><p><b>Winning a job &amp; response time.</b> When a Customer reveals and selects the Supplier, the Supplier is notified that it has won the job and the Customer is given the Supplier&#39;s contact details (by SMS, WhatsApp and/or email) so the Customer can make contact. The Supplier must begin responding to the Customer within <b>5 working days</b> of the Reveal. If the Supplier has not responded within 3 working days of the Reveal, QuotesDone chases the Supplier, copying the Customer; if there is still no response by the 5th working day the case goes to QuotesDone&#39;s CEO for a final call, and if the Supplier does not respond to that call everything the Customer paid for the reveal is refunded and the Supplier pays the amounts in clause 33. Repeated non-responsiveness may lead to suspension. QuotesDone is notified of every such case.</p>
<h2>12. Quotations &amp; the supplier–customer contract</h2><p>A quotation is the price the Supplier wishes to receive for the work. A quotation is valid for <b>30 days</b> from submission unless the Supplier refreshes or withdraws it before Reveal, and the Supplier is bound by a quotation that is revealed within that validity period. The contract for the work itself is solely between the Supplier and the Customer, on terms they agree; QuotesDone is not a party to it and is not responsible for either party's performance, payment or conduct.</p>
<h2>13. Trade licence &amp; regulatory compliance</h2><p>The Supplier must maintain a valid UAE trade licence and any approvals required for its trade, and upload renewals before expiry. QuotesDone verifies every Supplier before it can be matched: the mandatory six (business name, mobile number, email address, trade licence, company profile and signed acceptance of this Agreement) must be complete, and the trade licence number, issuing authority and expiry date are checked, within three (3) Working Days of complete documents. QuotesDone does not verify the Supplier&#39;s workmanship, solvency or insurance (where an insurance policy is uploaded, only its expiry date is tracked). These checks are published at <a href="/how-we-verify/">How we verify suppliers</a>. QuotesDone may suspend, unverify or remove accounts that are unverified, expired, inaccurate or misrepresented.</p>
<h2>14. Ratings &amp; feedback</h2><p>The Supplier acknowledges that Customers and QuotesDone may rate and review performance, and that such ratings may be displayed. Ratings reflect user feedback and are not endorsements by QuotesDone.</p>
<h2>15. Intellectual property</h2><p>All intellectual property in the Platform belongs to QuotesDone. The Supplier grants QuotesDone a non-exclusive licence to display its business information, logo and quotation content for the purpose of operating the Platform.</p>
<h2>16. Confidentiality &amp; data protection</h2><p>The Supplier shall keep any Customer information received strictly confidential and use it only to fulfil the specific job. Each party shall comply with UAE Federal Decree-Law No. 45 of 2021 on the Protection of Personal Data (PDPL). QuotesDone processes the personal data of the Supplier and its representatives where necessary to perform this Agreement, and for these specified purposes: account management, identity and licence verification, subscription invoicing and collection, fraud and security monitoring, and service analytics. Processing necessary to operate this Agreement relies on contractual necessity rather than consent alone. Any separate purpose, such as marketing, will be based on separate consent. The Supplier and its representatives have the right to access, correct and request deletion of their personal data (PDPL Arts. 14–16) and may lodge a complaint with the UAE Data Office. Full details are set out in our <a href="/privacy/">Privacy Policy</a>, which is provided at the point of registration.</p>
<h2>17. Warranties &amp; disclaimers</h2><p>The Platform is provided on an "as is" and "as available" basis. QuotesDone does not warrant any volume of leads, quotations or jobs, uninterrupted availability, or that any Customer will proceed. To the extent permitted by law, all implied warranties are excluded.</p>
<h2>18. Limitation of liability &amp; indemnity</h2><p>To the maximum extent permitted by UAE law, QuotesDone, its owners, staff and affiliates shall not be liable for disputes between the Supplier and a Customer, loss of business or profit, or any indirect or consequential loss; and QuotesDone's total aggregate liability to the Supplier shall not exceed the fees the Supplier paid to QuotesDone in the 12 months before the claim. The Supplier shall indemnify QuotesDone against claims, losses and costs arising from the Supplier's work, breach of this Agreement, or breach of law. Nothing excludes liability that cannot lawfully be excluded.</p>
<h2>19. Suspension &amp; termination</h2><p>QuotesDone may suspend or terminate access for breach of this Agreement, non-payment, expired licensing, or conduct harmful to the Platform or its users. The Supplier may stop using the Platform at any time. Outstanding Subscription Fees and charges survive termination and remain payable.</p>
<h2>20. Force majeure</h2><p>Neither party is liable for failure or delay caused by events beyond its reasonable control.</p>
<h2>21. Notices</h2><p>Notices to the Supplier — including any invoice, reminder, notice of a charge or demand for payment — may be given by any one or more of the following, each of which the parties agree is a valid method of notice, including for the purposes of Article 81 of the Commercial Transactions Law (Federal Decree-Law No. 50 of 2022) and Article 9(1)(a) of the Civil Procedure Code (Federal Decree-Law No. 42 of 2022): (a) email to the Supplier&#39;s registered email address; (b) a message shown in the supplier portal; (c) a WhatsApp message to the WhatsApp number the Supplier confirmed in the supplier portal by entering a verification code sent to that number or, where the Supplier confirmed in the supplier portal that its registered mobile number is its WhatsApp number, to that registered mobile number; and (d) an SMS to the Supplier&#39;s registered mobile number. A notice is served when it is delivered to that address, number or portal account, as recorded by the email, WhatsApp or SMS service provider or by the Platform, and that record is evidence of service. The Supplier must keep its registered email address, registered mobile number and confirmed WhatsApp number current; a notice delivered to the details last registered or confirmed is validly served. Notices to QuotesDone should be sent to management@quotesdone.com.</p>
<h2>22. General</h2><p>QuotesDone may assign this Agreement; the Supplier may not assign without consent. If any provision is held unenforceable, the remainder stands. No failure to enforce is a waiver. This Agreement, with the Privacy Policy and any fee notices, is the entire agreement between the parties. This Agreement is made in Arabic and English. The Arabic text prevails for all purposes, including before any court or other authority in the United Arab Emirates, and the English text is provided for convenience only; in case of any difference between them, the Arabic text governs.</p>
<h2>23. Amendments</h2><p>QuotesDone may update this Agreement and its fees. For material changes — in particular any increase in fees — QuotesDone will give at least <b>30 days' notice</b> and will ask the Supplier to re-confirm acceptance; a Supplier who does not accept a material change may terminate without penalty within the notice period. Non-material changes take effect when published on this page.</p>
<h2>24. No-circumvention of the Platform</h2><p>The Supplier acknowledges that any customer, project or lead made known to it through the Platform results directly from QuotesDone's introduction and is QuotesDone's protected commercial interest. For 24 months from such introduction, the Supplier shall not, directly or indirectly, conclude, invoice or facilitate any transaction with that customer for the same or similar scope outside the Platform with the purpose or effect of avoiding QuotesDone's fee. Each breach entitles QuotesDone to liquidated compensation of AED 15,000 per incident, or three (3) times the fee that would otherwise have been payable, whichever is higher, in addition to recovery of the unpaid fee.</p>
<h2>25. Confidentiality &amp; platform data</h2><p>All leads, customer details, anonymised scopes, pricing data and materials accessed through the Platform are confidential and remain the property of QuotesDone. The Supplier shall not copy, store, resell or reuse such data outside a transaction conducted on the Platform, nor supply it to any third party or competing service. Each proven breach entitles QuotesDone to liquidated compensation of AED 20,000 per incident, plus injunctive relief.</p>
<h2>26. No replication or competing use</h2><p>The Supplier shall not reproduce, reverse-engineer, or use QuotesDone's software, matching logic, anonymisation outputs or document templates to develop or assist any competing platform.</p>
<h2>27. AI-generated content and platform outputs</h2><p>The Platform uses automated and AI-based tools to extract bills of quantities from drawings, standardise and anonymise quotations, generate cost estimates and comparisons, and power support and category assistants. These outputs are provided for convenience only, may contain errors or omissions, and do not constitute professional, engineering, legal or financial advice. The Supplier must independently verify any such output before relying on it, and QuotesDone is not liable for any loss arising from reliance on automated outputs.</p>
<h2>28. Anonymisation and standardised quotations</h2><p>QuotesDone anonymises quotations and related materials on a reasonable-efforts basis. The Supplier remains responsible for ensuring its quotations, drawings and uploads do not contain identifying, contact or branding information intended to circumvent anonymity, and QuotesDone is not liable if anonymisation is imperfect. Where QuotesDone produces a standardised or reformatted version of a quotation, that version is a convenience copy only; the Supplier's original submission governs in the event of any discrepancy.</p>
<h2>29. No guarantee of leads or outcomes</h2><p>QuotesDone provides access to the Platform but does not guarantee that the Supplier will receive any inquiries, quotation opportunities, reveals or won work, nor any particular volume, value or return. Registration and continued use are provided without any representation as to results.</p>
<h2>30. Electronic acceptance, records and audit</h2><p>The Supplier agrees that ticking the acceptance box, clicking to accept, or continuing to use the Platform constitutes a valid and binding electronic acceptance of this Agreement under the laws of the United Arab Emirates. QuotesDone's records — including its acceptance logs and the signed acceptance certificate it generates — are admissible and, absent manifest error, conclusive evidence of the terms accepted and the time of acceptance. To enforce the anti-circumvention provisions, QuotesDone may request reasonable evidence that a Customer introduced through the Platform was not dealt with off-Platform, and the Supplier shall cooperate in good faith.</p>
<h2>31. Payments, currency and future fees</h2><p>All amounts under this Agreement are stated and payable in UAE Dirhams (AED) unless otherwise agreed. Any amount overdue accrues simple interest at nine percent (9%) per annum, or the maximum permitted by UAE law if lower; this is the only interest rate under this Agreement. Registration and subscription fees are addressed in sections 6 and 7, and no supplier commission is charged; QuotesDone reserves the right to introduce or vary such fees in future in accordance with the Amendments section.</p>
<h2>32. Compliance, communications and feedback</h2><p>The Supplier warrants that it is not subject to sanctions and that its funds and activities are lawful, and it will comply with applicable anti-money-laundering and sanctions laws. The Supplier consents to receive service, transactional and (unless opted out) promotional communications by email, SMS and WhatsApp, and may unsubscribe from promotional messages at any time. Any feedback or suggestions the Supplier provides may be used by QuotesDone freely and without obligation. QuotesDone may identify the Supplier as a participant on the Platform and use its name or logo as a reference, unless the Supplier opts out by written notice.</p>
<h2>33. Response obligation and non-response charge</h2><p>Once a Customer reveals the Supplier&#39;s contact details, the Supplier must respond to that Customer within five (5) working days of the Reveal, by the on-platform message thread, telephone, email or other reasonable means. QuotesDone tracks every Reveal from payment: if the Supplier has not responded within three (3) working days, QuotesDone chases the Supplier, copying the Customer; if there is still no response by the fifth (5th) working day, QuotesDone&#39;s CEO makes a final call to the Supplier. If the Supplier does not respond to that call and QuotesDone consequently refunds the Customer, the Supplier shall pay QuotesDone: (a) a non-response charge equal to the exact amount refunded to the Customer, being the reveal fee (3% of the Quotation Value) plus the card processing fee charged on it; (b) an administrative fee of AED 250; and (c) simple interest on the unpaid total at the clause 31 rate of nine percent (9%) per annum (or the maximum permitted by UAE law if lower), from the due date until settled. These amounts reflect QuotesDone&#39;s cost of the refund caused by the Supplier&#39;s non-response; they are payable within seven (7) days of QuotesDone&#39;s notice (the due date) and may be recorded as a due on the Supplier&#39;s account. Once QuotesDone&#39;s notice is issued, the amounts in (a) and (b) together are a sum of money of a specified amount — the exact amount refunded to the Customer plus AED 250, as stated in that notice — which is certain and due on the due date; interest under (c) accrues on that sum at nine percent (9%) simple interest per annum from the due date until payment in full, and is never compounded. The administrative fee in (b) is compensation agreed in advance by the parties under Article 340(1) of the Civil Transactions Law (Federal Decree-Law No. 25 of 2025), which provides: "The contracting parties may pre-determine the amount of compensation by stipulating it in the contract or in a subsequent agreement, subject to the provisions of the law." The parties agree that AED 250 is a genuine pre-estimate of QuotesDone&#39;s cost of handling the refund. The Supplier is not matched to new Customers until the amount is settled. Repeated non-response may also lead to suspension or removal from the Platform.</p>
<h2>34. Governing law &amp; jurisdiction</h2><p>This Agreement is governed by the laws of the United Arab Emirates, and the parties submit to the exclusive jurisdiction of the competent courts of the Emirate of Dubai.</p>
<h2>35. Contact</h2><p>QuotesDone Technologies · Sole Establishment · DET Dubai Trader License No. 1633275 · Dubai, United Arab Emirates · management@quotesdone.com · +971 50 931 9355</p>
<div class="ar" dir="rtl" lang="ar"><style id="qdmf">html,body{overflow-x:hidden;max-width:100%}.body{overflow-wrap:anywhere;word-break:break-word}.body table{display:block;width:100%;overflow-x:auto;-webkit-overflow-scrolling:touch}.body img{max-width:100%;height:auto}</style><h1>اتفاقية المورّد</h1><div class="muted">للموردين الذين يسجّلون ويقدّمون عروض الأسعار على QuotesDone. الإصدار 12 · تخضع لقوانين دولة الإمارات العربية المتحدة.</div><div class="card"><h2>1. الاتفاقية والقبول</h2><p>اتفاقية المورّد هذه ("الاتفاقية") هي عقد مُلزِم بين QuotesDone Technologies (كوتس دن للتكنولوجيا)، وهي مؤسسة فردية مرخّصة من دائرة الاقتصاد والسياحة في دبي بموجب رخصة تاجر رقم 1633275، دبي، الإمارات العربية المتحدة، والتي تدير منصة QuotesDone ("QuotesDone"، "نحن"، "المنصة")، وبين النشاط التجاري المسجِّل ("أنت"، "المورّد"). بوضع علامة في مربع القبول أثناء التسجيل، أو باستخدام المنصة، فإنك تؤكد أنك قرأت هذه الاتفاقية وفهمتها وتوافق على الالتزام بها. يشكّل وضع العلامة في المربع توقيعًا إلكترونيًا صحيحًا بموجب المرسوم بقانون اتحادي رقم 46 لسنة 2021 بشأن المعاملات الإلكترونية وخدمات الثقة. وإذا كنت تقبل نيابةً عن شركة، فإنك تقرّ بأنك مفوّض بإلزام تلك الشركة.</p>
<h2>2. التعريفات</h2><ul><li><b>العميل</b> — المستخدم الذي يطلب عروض أسعار عبر المنصة.</li><li><b>قيمة عرض السعر</b> — إجمالي السعر الذي يقدّمه المورّد للعمل، غير شامل ضريبة القيمة المضافة.</li><li><b>الكشف</b> — اللحظة التي يدفع فيها العميل لكشف واختيار مورّد لعمل ما؛ ويُعدّ العمل "مكتسبًا" عند الكشف.</li><li><b>رسوم الاشتراك</b> — رسوم اشتراك المورّد السنوية الموضّحة في البند 6.</li><li><b>أيام العمل</b> — الأيام عدا السبت والأحد والعطلات الرسمية في دولة الإمارات.</li></ul>
<h2>3. الأهلية والتسجيل</h2><p>للتسجيل يجب أن تكون نشاطًا تجاريًا قائمًا بصفة قانونية في دولة الإمارات ويحمل رخصة تجارية سارية تغطي الخدمات التي تقدّمها، وأن يكون الشخص المسجِّل مفوّضًا بالتصرف نيابة عن ذلك النشاط. وتوافق على تقديم معلومات دقيقة وحديثة وكاملة عن الشركة والرخصة والرقم الضريبي (TRN) والبيانات البنكية وبيانات الاتصال، وعلى تحديثها باستمرار.</p>
<h2>4. الحساب والأمان</h2><p>يتم تأمين الوصول عبر التحقق برمز لمرة واحدة. وأنت مسؤول عن النشاط الذي يجري على حسابك وعن الحفاظ على سرية بيانات الدخول والبريد الإلكتروني المسجَّل. يُرجى إخطارنا فورًا بأي استخدام غير مصرّح به.</p>
<h2>5. الخدمة</h2><p>QuotesDone هي سوق إلكتروني لعروض الأسعار مجهولة الهوية ومنصة تقنية. ينشر العملاء أعمالهم ويتلقّون عروض أسعار مجهولة الهوية؛ ولا يتم الإفصاح عن هويتَي العميل والمورّد إلا من خلال المنصة بعد الكشف. تعمل QuotesDone كوسيط ومُيسِّر فقط؛ وهي ليست المقاول، وليست طرفًا في عقد تنفيذ العمل، ولا تشرف على أي عمل أو تنفّذه أو تضمنه.</p>
<h2>6. رسوم التسجيل والاشتراك</h2><p>تسجيل المورّدين <b>مجاني لأول 1,000 نشاط تجاري</b> يسجّل على المنصة، إعفاءً دائمًا. واعتبارًا من <b>التسجيل رقم 1,001</b> تُطبَّق رسوم اشتراك قدرها <b>1,000 درهم إماراتي سنويًا</b>، تُدفع سنويًا مقدمًا. وستمنح QuotesDone إشعارًا لا تقل مدته عن 30 يومًا وتطلب إعادة تأكيد القبول قبل استحداث الرسوم أو تعديلها، وفقًا لبند التعديلات؛ ويُعدّ استمرار استخدام المنصة بعد تاريخ السريان قبولًا بها. ورسوم الاشتراك، بمجرد سدادها، غير قابلة للاسترداد إلا وفق ما يُنص عليه صراحةً عند السداد.</p>
<h2>7. لا عمولة على المورّد</h2><p><b>لا تفرض QuotesDone على المورّد أي عمولة على أي عمل يكتسبه من خلال المنصة</b> — لا على قيمة عرض السعر، ولا على المبلغ المفوتر نهائيًا، ولا على الأعمال المتكررة مع العميل نفسه. ويتم تمويل المنصة من رسوم الاشتراك المنصوص عليها في البند 6 ومن رسوم يدفعها العميل عند الكشف. وتحتفظ QuotesDone بالحق في استحداث عمولة على المورّدين مستقبلًا فقط بإشعار لا تقل مدته عن 30 يومًا وإعادة تأكيد القبول وفقًا لبند التعديلات؛ ولا تُستحق أي عمولة ولا تصبح مستحقة بموجب هذه النسخة من الاتفاقية.</p>
<h2>8. شروط الدفع</h2><p>حيثما تكون رسوم الاشتراك مستحقة بموجب البند 6، فإنها تُدفع سنويًا مقدمًا، بالبطاقة أو بالتحويل البنكي، في تاريخ تجديد حساب المورّد. ويجوز لـ QuotesDone إصدار فاتورة أو كشف حساب بالمبالغ المستحقة؛ ولا يتوقف السداد على استلام الفاتورة. وجميع المبالغ بالدرهم الإماراتي ما لم يُذكر خلاف ذلك. وبصورة منفصلة، يدفع <b>العميل</b> — وليس المورّد — إلى QuotesDone رسوم كشف قدرها <b>3% من قيمة عرض السعر</b> مضافًا إليها رسوم معالجة البطاقة، لحظة الكشف. ولا يُخصم أي مبلغ من المبلغ الذي يدفعه العميل للمورّد مقابل العمل ولا يُفرض عليه أي رسم.</p>
<h2>9. التأخر في السداد</h2><p>إذا لم تُستلم رسوم الاشتراك في تاريخ استحقاقها، جاز لـ QuotesDone، بعد إخطار المورّد ومنحه <b>7 أيام عمل</b> إضافية للسداد، تعليق حساب المورّد إلى حين السداد. ورسوم الاشتراك غير المسددة تُعدّ ديونًا مستحقة وواجبة الأداء ويجوز تحصيلها عبر المحاكم المختصة في دولة الإمارات. وتُحتسب على المبالغ المتأخرة فائدة بالسعر الوحيد المحدد في البند 31. ولا تحتفظ QuotesDone بأي أموال لصالح المورّد (فهي لا تحصّل إلا رسومها الخاصة)، لذا لا تنطبق أي مقاصة مقابل مبالغ محتفظ بها.</p>
<h2>10. إخفاء الهوية وعدم التحايل</h2><p>تعتمد قيمة المنصة على إخفاء الهوية. ويجب على المورّد ألا يشارك أو يطلب، خلال المراحل مجهولة الهوية أو في المحادثات داخل المنصة، أرقام هواتف أو عناوين بريد إلكتروني أو روابط أو معرّفات واتساب أو غيرها من معرّفات المراسلة أو وسائل التواصل الاجتماعي، وألا يحاول بأي شكل نقل التعامل خارج المنصة أو تجاوز الكشف. ويترتب على أي إفصاح أو تحايل من هذا القبيل حق QuotesDone في تعليق حساب المورّد والمطالبة بمبلغ تعويض اتفاقي قدره <b>10,000 درهم إماراتي عن كل واقعة</b>، مُتفق عليه بوصفه تقديرًا حقيقيًا مسبقًا لقيمة المنصة المفقودة وإيرادات الاشتراك الضائعة، ويكون هو التعويض المالي الوحيد عن تلك الواقعة (ولن تطالب QuotesDone بتعويضات عامة منفصلة عن الفعل ذاته). وفي حالة المخالفة التقنية الأولى وغير المقصودة بشكل واضح، يجوز لـ QuotesDone وفق تقديرها توجيه إنذار كتابي بدلًا من تطبيق المبلغ. ويقرّ المورّد بأن هذا المبلغ تعويض اتفاقي (شرط جزائي) بموجب قانون المعاملات المدنية الإماراتي، ويجوز للمحكمة المختصة تعديله بما يعادل الضرر الفعلي.</p>
<h2>11. التزامات المورّد وسلوكه</h2><p>يلتزم المورّد بما يلي: احترام كل عرض سعر يقدّمه وأي جدول زمني متفق عليه؛ والرد على العملاء المكشوف عنهم بمهنية وسرعة؛ والتعامل بنزاهة وعدم الانخراط في التواطؤ أو التلاعب بالعطاءات أو الأسعار؛ والامتثال لجميع القوانين المعمول بها في دولة الإمارات، بما في ذلك قانون حماية المستهلك (القانون الاتحادي رقم 15 لسنة 2020) ومتطلبات الصحة والسلامة. وتلتزم QuotesDone من جانبها بتشغيل المنصة وفقًا لالتزاماتها كسوق رقمي بموجب ذلك القانون ولائحته التنفيذية.</p><p><b>اكتساب العمل ومدة الاستجابة.</b> عندما يكشف العميل عن المورّد ويختاره، يُخطَر المورّد بأنه اكتسب العمل وتُعطى للعميل بيانات اتصال المورّد (عبر الرسائل النصية و/أو واتساب و/أو البريد الإلكتروني) ليتمكّن العميل من التواصل. ويجب على المورّد أن يبدأ الرد على العميل خلال <b>5 أيام عمل</b> من الكشف. وإذا لم يستجب المورّد خلال 3 أيام عمل من الكشف، تتابعه QuotesDone مع إرسال نسخة إلى العميل؛ وإذا لم تصل أي استجابة بحلول يوم العمل الخامس تُحال الحالة إلى الرئيس التنفيذي لـ QuotesDone لإجراء اتصال أخير، وإذا لم يستجب المورّد لذلك الاتصال يُردّ إلى العميل كل ما دفعه مقابل الكشف ويدفع المورّد المبالغ الواردة في البند 33. وقد يؤدي تكرار عدم الاستجابة إلى التعليق. وتُخطَر QuotesDone بكل حالة من هذا النوع.</p>
<h2>12. عروض الأسعار والعقد بين المورّد والعميل</h2><p>عرض السعر هو المبلغ الذي يرغب المورّد في الحصول عليه مقابل العمل. ويكون عرض السعر ساريًا لمدة <b>30 يومًا</b> من تاريخ تقديمه ما لم يُحدّثه المورّد أو يسحبه قبل الكشف، ويكون المورّد ملزَمًا بعرض السعر الذي يُكشف عنه خلال مدة السريان تلك. أما عقد تنفيذ العمل ذاته فيكون حصريًا بين المورّد والعميل وبالشروط التي يتفقان عليها؛ وQuotesDone ليست طرفًا فيه وليست مسؤولة عن أداء أي من الطرفين أو سداده أو سلوكه.</p>
<h2>13. الرخصة التجارية والامتثال التنظيمي</h2><p>يجب على المورّد الاحتفاظ برخصة تجارية إماراتية سارية وبأي موافقات لازمة لنشاطه، ورفع التجديدات قبل انتهاء الصلاحية. وتتحقق QuotesDone من كل مورّد قبل مطابقته: يجب استكمال المتطلبات الستة الإلزامية (اسم النشاط التجاري، ورقم الهاتف المحمول، والبريد الإلكتروني، والرخصة التجارية، والملف التعريفي للشركة، والقبول الموقَّع لهذه الاتفاقية)، ويُتحقَّق من رقم الرخصة التجارية وجهة إصدارها وتاريخ انتهائها، خلال ثلاثة (3) أيام عمل من اكتمال المستندات. ولا تتحقق QuotesDone من جودة تنفيذ المورّد أو ملاءته المالية أو تأمينه (وإذا رُفعت وثيقة تأمين، يُتابَع تاريخ انتهائها فقط). وهذه الفحوص منشورة في صفحة <a href="/ar/how-we-verify/">كيف نتحقق من الموردين</a>. ويجوز لـ QuotesDone تعليق أو إلغاء توثيق أو إزالة الحسابات غير الموثّقة أو المنتهية أو غير الدقيقة أو المضلِّلة.</p>
<h2>14. التقييمات والملاحظات</h2><p>يقرّ المورّد بأنه يجوز للعملاء ولـ QuotesDone تقييم الأداء ومراجعته، وبأن تلك التقييمات قد تُعرض. وتعكس التقييمات ملاحظات المستخدمين ولا تُعدّ تزكية من QuotesDone.</p>
<h2>15. الملكية الفكرية</h2><p>جميع حقوق الملكية الفكرية في المنصة مملوكة لـ QuotesDone. ويمنح المورّد QuotesDone ترخيصًا غير حصري لعرض معلومات نشاطه التجاري وشعاره ومحتوى عروض أسعاره لغرض تشغيل المنصة.</p>
<h2>16. السرية وحماية البيانات</h2><p>يلتزم المورّد بالحفاظ على سرية أي معلومات عن العميل يتلقّاها واستخدامها فقط لتنفيذ العمل المحدد. ويلتزم كل طرف بالمرسوم بقانون اتحادي رقم 45 لسنة 2021 بشأن حماية البيانات الشخصية. وتعالج QuotesDone البيانات الشخصية للمورّد وممثليه عند الاقتضاء لتنفيذ هذه الاتفاقية، وللأغراض المحددة التالية: إدارة الحساب، والتحقق من الهوية والرخصة، وإصدار فواتير الاشتراك وتحصيلها، ومراقبة الاحتيال والأمن، وتحليلات الخدمة. وتستند المعالجة اللازمة لتنفيذ هذه الاتفاقية إلى الضرورة التعاقدية وليس إلى الموافقة وحدها. وأي غرض منفصل، كالتسويق، سيستند إلى موافقة منفصلة. وللمورّد وممثليه الحق في الوصول إلى بياناتهم الشخصية وتصحيحها وطلب حذفها (المواد 14–16 من قانون حماية البيانات الشخصية)، ويجوز لهم تقديم شكوى إلى مكتب البيانات في دولة الإمارات. وترد التفاصيل الكاملة في <a href="/ar/privacy/">سياسة الخصوصية</a>، والتي تُقدَّم عند التسجيل.</p>
<h2>17. الضمانات وإخلاء المسؤولية</h2><p>تُقدَّم المنصة "كما هي" و"حسب توافرها". ولا تضمن QuotesDone أي حجم من العملاء المحتملين أو عروض الأسعار أو الأعمال، ولا استمرارية التوافر دون انقطاع، ولا أن أي عميل سيمضي في التعامل. وإلى الحد الذي يسمح به القانون، تُستبعد جميع الضمانات الضمنية.</p>
<h2>18. تحديد المسؤولية والتعويض</h2><p>إلى أقصى حد يسمح به قانون دولة الإمارات، لا تتحمل QuotesDone ولا مالكوها ولا العاملون لديها ولا الشركات التابعة لها المسؤولية عن النزاعات بين المورّد والعميل، أو عن خسارة الأعمال أو الأرباح، أو عن أي خسارة غير مباشرة أو تبعية؛ ولا تتجاوز المسؤولية الإجمالية لـ QuotesDone تجاه المورّد قيمة الرسوم التي سددها المورّد لـ QuotesDone خلال الاثني عشر شهرًا السابقة للمطالبة. ويلتزم المورّد بتعويض QuotesDone عن المطالبات والخسائر والتكاليف الناشئة عن أعمال المورّد أو إخلاله بهذه الاتفاقية أو مخالفته للقانون. ولا يُستبعد أي التزام لا يجوز استبعاده قانونًا.</p>
<h2>19. التعليق والإنهاء</h2><p>يجوز لـ QuotesDone تعليق الوصول أو إنهاؤه بسبب الإخلال بهذه الاتفاقية، أو عدم السداد، أو انتهاء الترخيص، أو أي سلوك يضر بالمنصة أو بمستخدميها. ويجوز للمورّد التوقف عن استخدام المنصة في أي وقت. وتبقى رسوم الاشتراك والرسوم المستحقة قائمة وواجبة الأداء بعد الإنهاء.</p>
<h2>20. القوة القاهرة</h2><p>لا يُسأل أي من الطرفين عن الإخفاق أو التأخير الناجم عن أحداث خارجة عن سيطرته المعقولة.</p>
<h2>21. الإشعارات</h2><p>يجوز توجيه الإشعارات إلى المورّد — بما في ذلك أي فاتورة أو تذكير أو إشعار برسم أو إنذار بالوفاء — بوسيلة أو أكثر من الوسائل التالية، ويتفق الطرفان على أن كلًّا منها وسيلة صحيحة للإعلان، بما في ذلك لأغراض المادة (81) من قانون المعاملات التجارية (المرسوم بقانون اتحادي رقم 50 لسنة 2022) والبند (أ) من الفقرة (1) من المادة (9) من قانون الإجراءات المدنية (المرسوم بقانون اتحادي رقم 42 لسنة 2022): (أ) البريد الإلكتروني المسجَّل للمورّد؛ (ب) رسالة تُعرض في بوابة المورّد؛ (ج) رسالة واتساب إلى رقم الواتساب الذي أكّده المورّد في بوابة المورّد بإدخال رمز تحقق أُرسل إلى ذلك الرقم، أو إلى رقم الهاتف المحمول المسجَّل للمورّد إذا أكّد المورّد في بوابة المورّد أن رقم هاتفه المحمول المسجَّل هو رقم الواتساب الخاص به؛ (د) رسالة نصية قصيرة إلى رقم الهاتف المحمول المسجَّل للمورّد. ويُعدّ الإشعار قد أُعلن متى سُلِّم إلى ذلك العنوان أو الرقم أو حساب البوابة، وفق ما يسجّله مزوّد خدمة البريد الإلكتروني أو واتساب أو الرسائل النصية أو المنصة، ويكون ذلك السجلّ دليلًا على الإعلان. ويلتزم المورّد بتحديث عنوان بريده الإلكتروني ورقم هاتفه المحمول المسجَّلين ورقم الواتساب المؤكَّد؛ ويكون الإشعار المسلَّم إلى آخر بيانات مسجَّلة أو مؤكَّدة إعلانًا صحيحًا. وتُرسل الإشعارات إلى QuotesDone على العنوان management@quotesdone.com.</p>
<h2>22. أحكام عامة</h2><p>يجوز لـ QuotesDone التنازل عن هذه الاتفاقية؛ ولا يجوز للمورّد التنازل عنها دون موافقة. وإذا اعتُبر أي حكم غير قابل للتنفيذ، تظل بقية الأحكام سارية. ولا يُعدّ عدم إنفاذ أي حق تنازلًا عنه. وتشكّل هذه الاتفاقية، مع سياسة الخصوصية وأي إشعارات بالرسوم، كامل الاتفاق بين الطرفين. وقد حُرِّرت هذه الاتفاقية باللغتين العربية والإنجليزية، ويكون النص العربي هو المعتمد لجميع الأغراض، بما في ذلك أمام أي محكمة أو جهة أخرى في دولة الإمارات العربية المتحدة، والنص الإنجليزي مقدَّم للتيسير فقط؛ وعند أي اختلاف بينهما يسود النص العربي.</p>
<h2>23. التعديلات</h2><p>يجوز لـ QuotesDone تحديث هذه الاتفاقية ورسومها. وبالنسبة للتغييرات الجوهرية — وبخاصة أي زيادة في الرسوم — ستمنح QuotesDone إشعارًا لا تقل مدته عن <b>30 يومًا</b> وستطلب من المورّد إعادة تأكيد القبول؛ وللمورّد الذي لا يقبل تغييرًا جوهريًا أن ينهي الاتفاقية دون غرامة خلال مدة الإشعار. أما التغييرات غير الجوهرية فتسري عند نشرها على هذه الصفحة.</p>
<h2>24. عدم التحايل على المنصة</h2><p>يقرّ المورّد بأن أي عميل أو مشروع أو فرصة تُعرَّف إليه من خلال المنصة إنما تنتج مباشرةً عن تعريف QuotesDone وتمثّل مصلحة تجارية محمية لها. ولمدة 24 شهرًا من ذلك التعريف، لا يجوز للمورّد، بصورة مباشرة أو غير مباشرة، إبرام أو فوترة أو تيسير أي معاملة مع ذلك العميل لنطاق العمل ذاته أو مشابه له خارج المنصة بقصد أو بأثر تجنّب رسوم QuotesDone. ويترتب على كل مخالفة حق QuotesDone في تعويض اتفاقي قدره 15,000 درهم إماراتي عن كل واقعة، أو ثلاثة (3) أضعاف الرسوم التي كانت ستُستحق، أيهما أعلى، إضافةً إلى تحصيل الرسوم غير المسددة.</p>
<h2>25. السرية وبيانات المنصة</h2><p>جميع العملاء المحتملين وبيانات العملاء ونطاقات العمل مجهولة الهوية وبيانات التسعير والمواد التي يتم الاطلاع عليها من خلال المنصة تُعدّ سرية وتظل ملكًا لـ QuotesDone. ولا يجوز للمورّد نسخ تلك البيانات أو تخزينها أو إعادة بيعها أو إعادة استخدامها خارج معاملة تُجرى على المنصة، ولا تزويد أي طرف ثالث أو خدمة منافسة بها. ويترتب على كل مخالفة مثبتة حق QuotesDone في تعويض اتفاقي قدره 20,000 درهم إماراتي عن كل واقعة، إضافةً إلى الحق في طلب الأمر القضائي بوقف المخالفة.</p>
<h2>26. عدم الاستنساخ أو الاستخدام التنافسي</h2><p>لا يجوز للمورّد استنساخ برمجيات QuotesDone أو منطق المطابقة أو مخرجات إخفاء الهوية أو قوالب المستندات الخاصة بها، أو إجراء هندسة عكسية عليها، أو استخدامها لتطوير أي منصة منافسة أو المساعدة في تطويرها.</p>
<h2>27. المحتوى المولَّد بالذكاء الاصطناعي ومخرجات المنصة</h2><p>تستخدم المنصة أدوات آلية وقائمة على الذكاء الاصطناعي لاستخراج جداول الكميات من الرسومات، وتوحيد عروض الأسعار وإخفاء هويتها، وتوليد تقديرات التكلفة والمقارنات، وتشغيل مساعدي الدعم والفئات. وتُقدَّم هذه المخرجات لغرض التيسير فقط، وقد تحتوي على أخطاء أو إغفالات، ولا تشكّل استشارة مهنية أو هندسية أو قانونية أو مالية. ويجب على المورّد التحقق بشكل مستقل من أي مخرجات قبل الاعتماد عليها، وQuotesDone غير مسؤولة عن أي خسارة تنشأ عن الاعتماد على المخرجات الآلية.</p>
<h2>28. إخفاء الهوية وعروض الأسعار الموحّدة</h2><p>تقوم QuotesDone بإخفاء هوية عروض الأسعار والمواد المتصلة بها على أساس بذل الجهود المعقولة. ويظل المورّد مسؤولًا عن ضمان خلو عروض أسعاره ورسوماته وملفاته المرفوعة من أي معلومات تعريفية أو بيانات اتصال أو علامات تجارية يُقصد بها الالتفاف على إخفاء الهوية، وQuotesDone غير مسؤولة إذا كان إخفاء الهوية غير كامل. وحيثما تُنتج QuotesDone نسخة موحّدة أو مُعاد تنسيقها من عرض السعر، فإن تلك النسخة تكون للتيسير فقط؛ ويسود التقديم الأصلي للمورّد في حال وجود أي تعارض.</p>
<h2>29. عدم ضمان العملاء المحتملين أو النتائج</h2><p>توفّر QuotesDone الوصول إلى المنصة، لكنها لا تضمن أن يتلقّى المورّد أي طلبات أو فرص لتقديم عروض أسعار أو عمليات كشف أو أعمال مكتسبة، ولا أي حجم أو قيمة أو عائد معيّن. ويُقدَّم التسجيل والاستخدام المستمر دون أي إقرار بشأن النتائج.</p>
<h2>30. القبول الإلكتروني والسجلات والتدقيق</h2><p>يوافق المورّد على أن وضع علامة في مربع القبول، أو النقر للقبول، أو الاستمرار في استخدام المنصة، يشكّل قبولًا إلكترونيًا صحيحًا ومُلزِمًا لهذه الاتفاقية بموجب قوانين دولة الإمارات العربية المتحدة. وتُعدّ سجلات QuotesDone — بما فيها سجلات القبول وشهادة القبول الموقّعة التي تصدرها — مقبولة كدليل، وتكون، ما لم يثبت خطأ ظاهر، دليلًا قاطعًا على الشروط المقبولة ووقت القبول. ولإنفاذ أحكام عدم التحايل، يجوز لـ QuotesDone طلب دليل معقول على أن عميلًا عُرِّف من خلال المنصة لم يُتعامل معه خارجها، ويلتزم المورّد بالتعاون بحسن نية.</p>
<h2>31. المدفوعات والعملة والرسوم المستقبلية</h2><p>جميع المبالغ بموجب هذه الاتفاقية مقوّمة وواجبة الدفع بالدرهم الإماراتي (AED) ما لم يُتفق على خلاف ذلك. وتُحتسب على أي مبلغ متأخر فائدة بسيطة بنسبة تسعة بالمائة (9%) سنويًا، أو الحد الأقصى الذي يسمح به القانون الإماراتي إن كان أقل؛ وهذا هو سعر الفائدة الوحيد بموجب هذه الاتفاقية. وقد تناول البندان 6 و7 رسوم التسجيل والاشتراك، ولا تُفرض أي عمولة على المورّد؛ وتحتفظ QuotesDone بالحق في استحداث تلك الرسوم أو تعديلها مستقبلًا وفقًا لبند التعديلات.</p>
<h2>32. الامتثال والاتصالات والملاحظات</h2><p>يقرّ المورّد بأنه غير خاضع لعقوبات وبأن أمواله وأنشطته مشروعة، وبأنه سيلتزم بقوانين مكافحة غسل الأموال والعقوبات المعمول بها. ويوافق المورّد على تلقّي الاتصالات الخدمية والمعاملاتية و(ما لم ينسحب) الترويجية عبر البريد الإلكتروني والرسائل النصية وواتساب، ويجوز له إلغاء الاشتراك في الرسائل الترويجية في أي وقت. وأي ملاحظات أو اقتراحات يقدّمها المورّد يجوز لـ QuotesDone استخدامها بحرية ودون التزام. ويجوز لـ QuotesDone الإشارة إلى المورّد بوصفه مشاركًا على المنصة واستخدام اسمه أو شعاره كمرجع، ما لم ينسحب المورّد بإشعار كتابي.</p>
<h2>33. التزام الاستجابة ورسم عدم الاستجابة</h2><p>بمجرد أن يكشف العميل عن بيانات اتصال المورّد، يجب على المورّد الرد على ذلك العميل خلال خمسة (5) أيام عمل من الكشف، عبر سلسلة الرسائل داخل المنصة أو الهاتف أو البريد الإلكتروني أو أي وسيلة معقولة أخرى. وتتابع QuotesDone كل عملية كشف من لحظة الدفع: إذا لم يستجب المورّد خلال ثلاثة (3) أيام عمل، تتابعه QuotesDone مع إرسال نسخة إلى العميل؛ وإذا لم تصل أي استجابة بحلول يوم العمل الخامس (5)، يجري الرئيس التنفيذي لـ QuotesDone اتصالًا أخيرًا بالمورّد. وإذا لم يستجب المورّد لذلك الاتصال وردّت QuotesDone نتيجةً لذلك المبلغ إلى العميل، يدفع المورّد لـ QuotesDone: (أ) رسم عدم استجابة يعادل المبلغ الذي رُدّ إلى العميل بالضبط، أي رسوم الكشف (3% من قيمة عرض السعر) مضافًا إليها رسوم معالجة البطاقة المحصّلة عليها؛ و(ب) رسمًا إداريًا قدره 250 درهمًا إماراتيًا؛ و(ج) فائدة بسيطة على الإجمالي غير المسدَّد بسعر البند 31 البالغ تسعة بالمائة (9%) سنويًا (أو الحد الأقصى الذي يسمح به القانون الإماراتي إن كان أقل)، تُحتسب من تاريخ الاستحقاق حتى السداد. وتعكس هذه المبالغ تكلفة الاسترداد التي تكبدتها QuotesDone بسبب عدم استجابة المورّد؛ وهي واجبة السداد خلال سبعة (7) أيام من إشعار QuotesDone (تاريخ الاستحقاق)، ويجوز قيدها كمبلغ مستحق على حساب المورّد. ومتى صدر إشعار QuotesDone، يشكّل المبلغان الواردان في (أ) و(ب) معًا مبلغًا نقديًا معيّن المقدار — هو المبلغ الذي رُدّ إلى العميل بالضبط مضافًا إليه 250 درهمًا إماراتيًا، على النحو المبيّن في ذلك الإشعار — ثابتًا ومستحق الأداء في تاريخ الاستحقاق؛ وتُحتسب الفائدة الواردة في (ج) على ذلك المبلغ بواقع تسعة بالمائة (9%) سنويًا فائدةً بسيطة من تاريخ الاستحقاق حتى السداد التام، ولا تُركَّب في أي حال. ويُعدّ الرسم الإداري الوارد في (ب) تعويضًا اتفق عليه الطرفان مقدمًا وفقًا للبند (1) من المادة (340) من قانون المعاملات المدنية (المرسوم بقانون اتحادي رقم 25 لسنة 2025)، التي تنص على أنه: «يجوز للمتعاقدين أن يُحددا مقدمًا قيمة التعويض بالنص عليها في العقد أو في اتفاق لاحق، مع مراعاة أحكام القانون.» ويتفق الطرفان على أن مبلغ 250 درهمًا تقدير حقيقي مسبق لتكلفة QuotesDone في معالجة الاسترداد. ولا يُطابَق المورّد مع عملاء جدد حتى سداد المبلغ. وقد يؤدي تكرار عدم الاستجابة أيضًا إلى التعليق أو الإزالة من المنصة.</p>
<h2>34. القانون الواجب التطبيق والاختصاص القضائي</h2><p>تخضع هذه الاتفاقية لقوانين دولة الإمارات العربية المتحدة، ويخضع الطرفان للاختصاص الحصري للمحاكم المختصة في إمارة دبي.</p>
<h2>35. التواصل</h2><p>QuotesDone Technologies · مؤسسة فردية · رخصة تاجر من دائرة الاقتصاد والسياحة في دبي رقم 1633275 · دبي، الإمارات العربية المتحدة · management@quotesdone.com · +971 50 931 9355</p></div>$qd_supplier_agreement$
 where slug = 'legal_supplier_body';

update public.legal_documents
   set version = 'v12', effective_date = date '2026-09-14',
       content_sha256 = encode(sha256(convert_to(body_html, 'UTF8')), 'hex'), updated_at = now()
 where slug = 'supplier-agreement';

update public.app_secrets set value = (select encode(sha256(convert_to(html, 'UTF8')), 'hex') from public.pages where slug = 'legal_supplier_body'), updated_at = now()
 where key = 'terms_sha256_supplier';
update public.app_secrets set value = (select version from public.legal_documents where slug = 'supplier-agreement'), updated_at = now()
 where key in ('terms_version', 'supplier_terms_version', 'terms_sha256_supplier_version');
update public.app_secrets s
   set value = 'Supplier Agreement — Version ' || ltrim(d.version, 'vV'), updated_at = now()
  from public.legal_documents d
 where s.key = 'supplier_terms_label' and d.slug = 'supplier-agreement';

-- ── 2. WHICH NOTICES ARE FORMAL, AND WHAT EACH VERSION'S CLAUSE 21 SAYS ───────────────────────────
insert into public.decision_policy (key, value, description) values
  ('supplier_formal_notice_types',
   '["nonresponse_charge", "nonresponse_charge_correction", "nonresponse_charge_reminder", "nonresponse_final_demand", "charge_dispute_answer", "subscription_due", "subscription_renewal_reminder", "subscription_dunning", "subscription_payment_failed", "supplier_no_response_chase", "refund_final_notice", "reveal_no_response_notice"]'::jsonb,
   'notifications.type values that are formal notices to a supplier under Supplier Agreement clause 21 (an invoice, reminder, notice of a charge or demand for payment, and the refund-ladder notices). On WhatsApp and SMS they go only where the version the supplier accepted says (fn_supplier_notice_route, a06 on notifications).'),
  ('supplier_agreement_notice_clause',
   $j${"10": {"en": "Clause 21 (v10): Notices to the Supplier may be sent to the registered email or shown in the supplier portal; notices to QuotesDone should be sent to management@quotesdone.com.", "ar": "البند 21 (الإصدار v10): يجوز إرسال الإشعارات إلى المورّد على البريد الإلكتروني المسجَّل أو عرضها في بوابة المورّد؛ وتُرسل الإشعارات إلى QuotesDone على العنوان management@quotesdone.com."},
       "11": {"en": "Clause 21 (v11): (c) a WhatsApp message to the Supplier's registered mobile number; and (d) an SMS to the Supplier's registered mobile number.", "ar": "البند 21 (الإصدار v11): (ج) رسالة واتساب إلى رقم الهاتف المحمول المسجَّل للمورّد؛ (د) رسالة نصية قصيرة إلى رقم الهاتف المحمول المسجَّل للمورّد."},
       "12": {"en": "Clause 21 (v12): (c) a WhatsApp message to the WhatsApp number the Supplier confirmed in the supplier portal by entering a verification code sent to that number or, where the Supplier confirmed in the supplier portal that its registered mobile number is its WhatsApp number, to that registered mobile number; and (d) an SMS to the Supplier's registered mobile number.", "ar": "البند 21 (الإصدار v12): (ج) رسالة واتساب إلى رقم الواتساب الذي أكّده المورّد في بوابة المورّد بإدخال رمز تحقق أُرسل إلى ذلك الرقم، أو إلى رقم الهاتف المحمول المسجَّل للمورّد إذا أكّد المورّد في بوابة المورّد أن رقم هاتفه المحمول المسجَّل هو رقم الواتساب الخاص به؛ (د) رسالة نصية قصيرة إلى رقم الهاتف المحمول المسجَّل للمورّد."}}$j$::jsonb,
   'The clause 21 notice channels of each Supplier Agreement version, verbatim from src/content/legal.json. A notice cites the wording of the version the supplier accepted (key "12" covers v12 and later).')
on conflict (key) do update set value = excluded.value, description = excluded.description;

update public.decision_policy
   set description = 'The final demand needs a supplier who accepted v11 or later: from v11, clause 21 makes WhatsApp and SMS formal notice and clause 22 makes the Arabic text govern. A v11 supplier is NOT held for v12: v11 already covers the notice, which then goes to the registered mobile. The demand cites the clause 21 wording of the version accepted (decision_policy supplier_agreement_notice_clause).'
 where key = 'supplier_charge_demand_min_agreement_version';

-- ── 3. THE RULE ───────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_agreement_version_no(p_version text)
returns int language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select nullif(regexp_replace(coalesce(p_version, ''), '[^0-9]', '', 'g'), '')::int
$fn$;
revoke execute on function public.fn_supplier_agreement_version_no(text) from public, anon, authenticated;

-- Pure, so the probe below proves it without touching a row. p_confirmed is fn_whatsapp_destination's answer.
create or replace function public.fn_supplier_notice_channel(p_version_no int, p_channel text, p_whatsapp_opt text,
  p_verified_mobile text, p_confirmed_whatsapp text)
returns jsonb language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case
    when p_channel = 'whatsapp' and coalesce(p_version_no, 0) >= 12 then
      jsonb_build_object('to', p_confirmed_whatsapp, 'basis', 'confirmed_whatsapp',
        'reason', case when p_confirmed_whatsapp is null then 'no WhatsApp number confirmed in the portal' end)
    when p_channel = 'whatsapp' and p_version_no = 11 then
      case when p_whatsapp_opt = 'none'
           then jsonb_build_object('to', null, 'basis', 'registered_mobile', 'reason', 'the supplier said it does not use WhatsApp')
           else jsonb_build_object('to', p_verified_mobile, 'basis', 'registered_mobile',
                  'reason', case when p_verified_mobile is null then 'no verified registered mobile' end) end
    when p_channel = 'sms' and coalesce(p_version_no, 0) >= 11 then
      jsonb_build_object('to', p_verified_mobile, 'basis', 'registered_mobile',
        'reason', case when p_verified_mobile is null then 'no verified registered mobile' end)
    else jsonb_build_object('to', null, 'basis', 'not_agreed',
           'reason', 'the Supplier Agreement version accepted (' || coalesce('v' || p_version_no, 'none') || ') does not make ' || coalesce(p_channel, '?') || ' a notice channel')
  end
$fn$;
revoke execute on function public.fn_supplier_notice_channel(int, text, text, text, text) from public, anon, authenticated;

create or replace function public.fn_supplier_notice_route(p_lead bigint, p_email text default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint; v_accepted text; v_opt text; v_no int; v_mobile text; v_key text; v_clause jsonb;
begin
  select l.id, l.accepted_terms_version, l.whatsapp_opt into v_id, v_accepted, v_opt from public.leads l
   where l.id = p_lead or (p_lead is null and p_email is not null and lower(l.claimed_by) = lower(btrim(p_email)))
   order by l.id limit 1;
  v_no := public.fn_supplier_agreement_version_no(v_accepted);
  v_mobile := case when v_id is not null then public.fn_verified_mobile('supplier', null, v_id, null) end;
  v_key := case when coalesce(v_no, 0) >= 12 then '12' when v_no = 11 then '11' else '10' end;
  select value -> v_key into v_clause from public.decision_policy where key = 'supplier_agreement_notice_clause';
  return jsonb_build_object('supplier_id', v_id, 'agreement_version', v_accepted, 'version_no', v_no,
    'whatsapp', public.fn_supplier_notice_channel(v_no, 'whatsapp', v_opt, v_mobile,
                  case when coalesce(v_no, 0) >= 12 and v_id is not null then public.fn_whatsapp_destination('supplier', null, v_id, null) end),
    'sms', public.fn_supplier_notice_channel(v_no, 'sms', v_opt, v_mobile, null),
    'clause_en', v_clause->>'en', 'clause_ar', v_clause->>'ar');
end $fn$;
revoke execute on function public.fn_supplier_notice_route(bigint, text) from public, anon, authenticated;

-- ── 4. EVERY FORMAL NOTICE ON WHATSAPP OR SMS FOLLOWS THE VERSION ACCEPTED ────────────────────────
-- Named a06 so it fires after #657's a03 (BEFORE triggers run in name order) and has the last word.
create or replace function public.fn_notifications_supplier_notice_follows_the_accepted_agreement()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_route jsonb; v_to text;
begin
  if coalesce(new.to_role, '') <> 'supplier' or coalesce(new.channel, '') not in ('whatsapp', 'sms')
     or coalesce(new.status, 'queued') not in ('queued', 'skipped')
     or not exists (select 1 from public.decision_policy p, jsonb_array_elements_text(p.value) t
                     where p.key = 'supplier_formal_notice_types' and t = new.type) then
    return new;
  end if;
  v_route := public.fn_supplier_notice_route(new.lead_id, new.to_email) -> new.channel;
  v_to := v_route->>'to';
  if v_to is not null then
    new.to_phone := v_to; new.status := 'queued'; new.last_error := null;
  else
    new.status := 'skipped';
    new.last_error := 'not sent on ' || new.channel || ': ' || coalesce(v_route->>'reason', 'no agreed number')
                      || '; email and the portal carry this notice (Supplier Agreement clause 21)';
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_notifications_supplier_notice_follows_the_accepted_agreement() from public, anon, authenticated;
drop trigger if exists a06_notifications_supplier_notice_follows_the_accepted_agreement on public.notifications;
create trigger a06_notifications_supplier_notice_follows_the_accepted_agreement before insert on public.notifications
  for each row execute function public.fn_notifications_supplier_notice_follows_the_accepted_agreement();

-- ── 5. THE v11 TWIN trg_wa_fanout DOES NOT MAKE ───────────────────────────────────────────────────
create or replace function public.fn_supplier_notice_whatsapp_twin_under_v11()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint; v_accepted text; v_opt text;
begin
  if coalesce(new.channel, 'email') <> 'email' or coalesce(new.to_role, '') <> 'supplier' or new.to_email is null
     or not exists (select 1 from public.decision_policy p, jsonb_array_elements_text(p.value) t
                     where p.key = 'supplier_formal_notice_types' and t = new.type) then
    return null;
  end if;
  select l.id, l.accepted_terms_version, l.whatsapp_opt into v_id, v_accepted, v_opt from public.leads l
   where l.id = new.lead_id or (new.lead_id is null and lower(l.claimed_by) = lower(new.to_email)) order by l.id limit 1;
  -- Answered (same/other/none): trg_wa_fanout already made or recorded the twin. Only unanswered v11 is missing.
  if v_id is null or v_opt is not null or public.fn_supplier_agreement_version_no(v_accepted) is distinct from 11
     or public.fn_verified_mobile('supplier', null, v_id, null) is null then
    return null;
  end if;
  insert into public.notifications (type, to_email, to_role, lead_id, inquiry_id, quote_id, subject, body, channel, status)
  values (new.type, new.to_email, new.to_role, v_id, new.inquiry_id, new.quote_id, new.subject, new.body, 'whatsapp', 'queued');
  return null;
end $fn$;
revoke execute on function public.fn_supplier_notice_whatsapp_twin_under_v11() from public, anon, authenticated;
drop trigger if exists z06_supplier_notice_whatsapp_twin_under_v11 on public.notifications;
create trigger z06_supplier_notice_whatsapp_twin_under_v11 after insert on public.notifications
  for each row execute function public.fn_supplier_notice_whatsapp_twin_under_v11();

-- ── 6. THE COLLECTIONS DUTY CITES THE VERSION ACCEPTED ────────────────────────────────────────────
-- Owning file: the_accountant_chases_what_a_silent_supplier_owes.sql. Redefined here (see the header) with three
-- changes: the route in every payload, the version read through it, and the held finding citing what was accepted.
create or replace function public.fn_accountant_collections_tick(p_as_of date default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_basis boolean := coalesce((select (value->>'confirmed')::boolean from public.decision_policy where key = 'supplier_charge_recovery_basis'), false);
  v_offs int[] := public.fn_policy_int_array('supplier_charge_reminder_after_due_days');
  v_fd int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_final_demand_after_due_days');
  v_notice int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_final_demand_notice_days');
  v_esc int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_escalate_ceo_after_due_days');
  v_min_notice int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_legal_minimum_notice_days');
  v_lim_years int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_limitation_years');
  v_lim_warn int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_limitation_warn_days');
  v_min_ver int := (select (value #>> '{}')::int from public.decision_policy where key = 'supplier_charge_demand_min_agreement_version');
  v_ver int; v_limit_on date; v_route jsonb;
  d record; v jsonb; v_days int; v_i int; v_items jsonb := '[]'::jsonb; v_payload jsonb; v_disputed boolean;
  n_rem int := 0; n_fd int := 0; n_file int := 0; v_accrued int;
begin
  if array_length(v_offs, 1) is null or v_fd is null or v_notice is null or v_esc is null then
    raise exception 'fn_accountant_collections_tick: the supplier_charge_* timeline is missing from decision_policy';
  end if;
  if v_min_notice is null or v_lim_years is null or v_lim_warn is null or v_min_ver is null then
    raise exception 'fn_accountant_collections_tick: the legal minimum, limitation or agreement-version row is missing from decision_policy';
  end if;
  -- CPL 42/2022 Art 144(1): a demand giving fewer than five days is not a notice for payment.
  if v_notice < v_min_notice then
    raise exception 'supplier_charge_final_demand_notice_days is % but CPL Art 144(1) requires at least %; nothing is sent', v_notice, v_min_notice;
  end if;
  v_accrued := public.fn_supplier_dues_accrue_interest(v_as_of);

  for d in select s.*, l.company_name, coalesce(l.is_demo, false) demo, l.accepted_terms_version agreement_version
             from public.supplier_dues s join public.leads l on l.id = s.supplier_id
            where s.paid_at is null and coalesce(s.status, '') not in ('paid', 'settled', 'waived', 'cancelled')
              and coalesce(s.legal_stage, '') not like 'outcome:%'
            order by s.id loop
    v_days := v_as_of - d.due_date;
    v := public.fn_accountant_nonresponse_charge(d.transaction_id, v_as_of);
    v_payload := coalesce(v, '{}'::jsonb) || jsonb_build_object('agreement_version', coalesce(d.agreement_version, ''), 'due_id', d.id, 'supplier_id', d.supplier_id,
      'transaction_id', d.transaction_id, 'quote_id', d.quote_id, 'days_overdue', greatest(v_days, 0),
      'interest_pct', round(coalesce((v->>'interest_apr')::numeric, 0) * 100, 2), 'due_date', d.due_date,
      'total_aed', coalesce(d.total_claim, d.amount_due));
    -- 14 SEP 2026 (Supplier Agreement v12): every notice carries the clause 21 wording and the WhatsApp basis of
    -- the version THIS supplier accepted, for the templates ({{notice_clause_en}}, {{notice_clause_ar}},
    -- {{whatsapp_basis}}). The number itself is chosen at the outbox by a06 (fn_supplier_notice_route), never here.
    v_route := public.fn_supplier_notice_route(d.supplier_id, null);
    v_payload := v_payload || jsonb_build_object('notice_clause_en', coalesce(v_route->>'clause_en', ''),
      'notice_clause_ar', coalesce(v_route->>'clause_ar', ''), 'whatsapp_basis', coalesce(v_route->'whatsapp'->>'basis', ''));
    v_disputed := exists (select 1 from public.agent_actions a
                           where a.kind = 'handoff' and a.detail->>'type' = 'charge.dispute_answer'
                             and (a.detail->>'due_id')::bigint = d.id and (a.detail->>'figures_match')::boolean is false);

    if v_disputed then
      v_items := v_items || jsonb_build_object('item', 'disputed:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', coalesce(d.company_name, 'A supplier') || ' disputed charge #' || d.id || ' and the recomputation did not confirm it; notices are held until the CEO decides',
        'blast', 'agent_facing', 'affected', 1, 'demo', d.demo, 'evidence', v_payload);
    elsif not v_basis then
      if v_days >= v_offs[1] then
        v_items := v_items || jsonb_build_object('item', 'held_basis:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
          'title', 'Charge #' || d.id || ' (' || coalesce(d.company_name, 'supplier') || ', AED ' || coalesce(d.total_claim, d.amount_due)
                   || ') is ' || v_days || ' day(s) past due and no reminder can go: the UAE recovery timeline and wording are not yet configured',
          'blast', 'agent_facing', 'affected', 1, 'demo', d.demo,
          'evidence', v_payload || jsonb_build_object('needs', 'decision_policy supplier_charge_recovery_basis confirmed = true, from docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md'));
      end if;
    else
      -- The next reminder, once its day is reached.
      v_i := coalesce(d.reminders, 0) + 1;
      if v_i <= array_length(v_offs, 1) and v_days >= v_offs[v_i] and d.legal_stage is null then
        perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.charge_reminder', 'supplier_dues',
          d.id || ':reminder:' || v_i, v_payload || jsonb_build_object('notice', 'charge_reminder', 'reminder_no', v_i));
        update public.supplier_dues set reminders = v_i, last_reminder_at = now() where id = d.id;
        n_rem := n_rem + 1;
      end if;
      -- THE DEMAND NEEDS v11 OR LATER (clause 21 makes WhatsApp and SMS notice, clause 22 makes Arabic govern).
      -- A v11 supplier is not held for v12: v11 covers the notice, which goes to the registered mobile. A
      -- supplier below v11 is held for the CEO until it accepts the current version. Unreadable is older.
      v_ver := (v_route->>'version_no')::int;
      if v_days >= v_fd and d.legal_stage is null and coalesce(v_ver, 0) < v_min_ver then
        v_items := v_items || jsonb_build_object('item', 'demand_held_version:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
          'title', 'The final demand on charge #' || d.id || ' (' || coalesce(d.company_name, 'supplier') || ') is held: the supplier accepted '
                   || coalesce(d.agreement_version, 'no version') || ' (' || coalesce(v_route->>'clause_en', 'no clause 21 on record')
                   || '), and a demand needs Supplier Agreement v' || v_min_ver || ' or later (WhatsApp/SMS notice, Arabic governing text)',
          'blast', 'agent_facing', 'affected', 1, 'demo', d.demo,
          'evidence', v_payload || jsonb_build_object('accepted_version', d.agreement_version, 'required_version', 'v' || v_min_ver,
            'remedy', 'the supplier accepts the current version on the next portal sign-in; the demand goes on the next run after that'));
      -- The formal final demand.
      elsif v_days >= v_fd and d.legal_stage is null then
        perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.final_demand', 'supplier_dues',
          d.id || ':final_demand', v_payload || jsonb_build_object('notice', 'final_demand',
            'pay_by', (now() at time zone 'Asia/Dubai')::date + v_notice));
        update public.supplier_dues set legal_stage = 'final_demand_sent', legal_escalated_at = now() where id = d.id;
        n_fd := n_fd + 1;
      elsif d.legal_stage = 'final_demand_sent' and now() >= d.legal_escalated_at + make_interval(days => v_notice) then
        update public.supplier_dues set legal_stage = 'filing_pack_due' where id = d.id;
        d.legal_stage := 'filing_pack_due';
        n_file := n_file + 1;
      end if;
    end if;

    if d.legal_stage in ('filing_pack_due', 'filing_pack_sent') then
      v_items := v_items || jsonb_build_object('item', 'filing:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', 'The final demand on charge #' || d.id || ' (' || coalesce(d.company_name, 'supplier') || ', AED '
                 || coalesce(d.total_claim, d.amount_due) || ') has expired unpaid: the filing pack is '
                 || case d.legal_stage when 'filing_pack_due' then 'due to the founder' else 'with the founder' end
                 || ', and this stays open until he records the outcome',
        'blast', 'agent_facing', 'affected', 1, 'demo', d.demo,
        'evidence', v_payload || jsonb_build_object('legal_stage', d.legal_stage, 'case_file_path', d.case_file_path,
                                                   'record_outcome', 'select public.fn_accountant_record_filing_outcome(' || d.id || ', ''filed'', ''<reference>'')'));
    end if;
    -- CTL Art 92: five years from the due date. An unfiled charge nearing that date is the CEO's.
    v_limit_on := (d.due_date + make_interval(years => v_lim_years))::date;
    if v_as_of >= v_limit_on - v_lim_warn and coalesce(d.legal_stage, '') not like 'outcome:filed%' then
      v_items := v_items || jsonb_build_object('item', 'limitation:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', 'Charge #' || d.id || ' (' || coalesce(d.company_name, 'supplier') || ') is time-barred on ' || v_limit_on
                 || ' (CTL Art 92, five years from the due date) and has not been filed',
        'blast', 'agent_facing', 'affected', 1, 'demo', d.demo, 'evidence', v_payload || jsonb_build_object('limitation_on', v_limit_on));
    end if;
    if v_days >= v_esc then
      v_items := v_items || jsonb_build_object('item', 'overdue:' || d.id, 'owner_seat', 'ceo', 'subject', 'supplier_dues',
        'title', coalesce(d.company_name, 'A supplier') || ' owes AED ' || coalesce(d.total_claim, d.amount_due) || ' on charge #' || d.id
                 || ', ' || v_days || ' days past due, after ' || coalesce(d.reminders, 0) || ' reminder(s)',
        'blast', 'agent_facing', 'affected', 1, 'demo', d.demo, 'evidence', v_payload);
    end if;
  end loop;

  return jsonb_build_object('as_of', v_as_of, 'basis_confirmed', v_basis, 'interest_updated', v_accrued,
    'reminders', n_rem, 'final_demands', n_fd, 'filing_packs_due', n_file, 'aging', public.fn_accountant_dues_aging(v_as_of),
    'findings', public.fn_accountant_duty_settle('collections', v_items));
end $fn$;
revoke execute on function public.fn_accountant_collections_tick(date) from public, anon, authenticated;

-- ── 7. PROOF ──────────────────────────────────────────────────────────────────────────────────────
-- This file defines routines, so the probe writes nothing and ends in a notice. The rule is pure; the route of
-- a supplier id that cannot exist must name no number at all.
do $check$
declare n int; v text; r jsonb;
begin
  select count(*) into n from public.legal_documents d
   where d.slug = 'supplier-agreement' and d.version = 'v12' and d.effective_date = date '2026-09-14'
     and d.content_sha256 = '94151f940a4567944ff04f362e8c8c3ae6ad87d96cbb7ef280f505420c8648a4' and encode(sha256(convert_to(d.body_html, 'UTF8')), 'hex') = '94151f940a4567944ff04f362e8c8c3ae6ad87d96cbb7ef280f505420c8648a4';
  if n <> 1 then raise exception 'legal_documents.supplier-agreement is not v12 / 2026-09-14 / 94151f940a4567944ff04f362e8c8c3ae6ad87d96cbb7ef280f505420c8648a4'; end if;
  if exists (
    select 1 from (
      select (select value from public.app_secrets where key = 'terms_version') dv,
             (select value from public.app_secrets where key = 'terms_sha256_supplier_version') pv,
             (select value from public.app_secrets where key = 'terms_sha256_supplier') psha,
             (select encode(sha256(convert_to(value, 'UTF8')), 'hex') from public.app_secrets where key = 'supplier_terms_html') lsha,
             (select encode(sha256(convert_to(html, 'UTF8')), 'hex') from public.pages where slug = 'legal_supplier_body') pubsha) s
     where dv is null or pv is null or psha is null or lsha is null or pubsha is null
        or psha <> lsha or dv <> pv or pubsha <> lsha or psha <> '94151f940a4567944ff04f362e8c8c3ae6ad87d96cbb7ef280f505420c8648a4')
  then raise exception 'supplier terms pins are not intact'; end if;
  if (select value from public.app_secrets where key = 'supplier_terms_version') <> 'v12' then raise exception 'supplier_terms_version did not follow'; end if;
  select value into v from public.app_secrets where key = 'supplier_terms_label';
  if v not like '%Version 12' then raise exception 'supplier_terms_label is %', v; end if;
  select html into v from public.pages where slug = 'legal_supplier_body';
  if v !~ 'the WhatsApp number the Supplier confirmed in the supplier portal' then raise exception 'clause 21 does not name the confirmed WhatsApp number'; end if;
  if v !~ 'رقم الواتساب الذي أكّده المورّد' then raise exception 'the Arabic clause 21 does not name the confirmed WhatsApp number'; end if;
  if v !~ 'Trader License No\. 1633275' or v !~ 'رخصة تاجر رقم 1633275' then raise exception 'the identity is not the Trader License'; end if;

  -- the rule, every row of it
  if public.fn_supplier_notice_channel(12, 'whatsapp', 'other', '+971500000001', '+971500000002')->>'to' is distinct from '+971500000002' then raise exception 'v12 WhatsApp is not the confirmed number'; end if;
  if public.fn_supplier_notice_channel(12, 'whatsapp', null, '+971500000001', null)->>'to' is not null then raise exception 'v12 WhatsApp went somewhere with no confirmed number'; end if;
  if public.fn_supplier_notice_channel(11, 'whatsapp', 'other', '+971500000001', '+971500000002')->>'to' is distinct from '+971500000001' then raise exception 'v11 WhatsApp is not the registered mobile'; end if;
  if public.fn_supplier_notice_channel(11, 'whatsapp', 'none', '+971500000001', null)->>'to' is not null then raise exception 'v11 WhatsApp ignored "I do not use WhatsApp"'; end if;
  if public.fn_supplier_notice_channel(10, 'whatsapp', 'same', '+971500000001', '+971500000001')->>'to' is not null then raise exception 'v10 got a WhatsApp notice'; end if;
  if public.fn_supplier_notice_channel(null, 'whatsapp', 'same', '+971500000001', '+971500000001')->>'to' is not null then raise exception 'a supplier with no accepted version got a WhatsApp notice'; end if;
  if public.fn_supplier_notice_channel(12, 'sms', 'other', '+971500000001', '+971500000002')->>'to' is distinct from '+971500000001' then raise exception 'v12 SMS is not the registered mobile'; end if;
  if public.fn_supplier_notice_channel(11, 'sms', null, '+971500000001', null)->>'to' is distinct from '+971500000001' then raise exception 'v11 SMS is not the registered mobile'; end if;
  if public.fn_supplier_notice_channel(10, 'sms', null, '+971500000001', null)->>'to' is not null then raise exception 'v10 got an SMS notice'; end if;
  r := public.fn_supplier_notice_route(-1, 'zz-demo-no-such-supplier@example.invalid');
  if r->'whatsapp'->>'to' is not null or r->'sms'->>'to' is not null or r->>'clause_en' !~ '\(v10\)' then raise exception 'an unknown supplier routed somewhere: %', r; end if;
  if to_regprocedure('public.fn_accountant_collections_tick(date)') is null then raise exception 'collections tick missing'; end if;
  raise notice 'supplier-agreement v12 registered (94151f940a4567944ff04f362e8c8c3ae6ad87d96cbb7ef280f505420c8648a4); formal supplier notices follow the version accepted';
end
$check$;

commit;
