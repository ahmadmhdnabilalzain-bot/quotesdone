# QuotesDone e2e run 2026-11-10T14-26-24

Site https://quotesdone.com · project htdblwldjkcgjvmqkbeh · run tag `c47515e7` · 1909s · journeys f

**139 passed · 0 failed · 0 held by the model hold · 0 skipped**

| # | journey | step | result | detail | ms |
|---|---|---|---|---|---|
| 1 | fixtures | fixtures of runs that are over are removed before this run starts | PASS | none left behind |  |
| 2 | fixtures | demo customer complete (name, 18+ DOB, email+mobile verified, current terms signed) | PASS | is_demo=true dob=1990-01-15 email_verified=true phone_verified=true terms=v11/v11 signed=false |  |
| 3 | fixtures | demo supplier A has the mandatory six | PASS | is_demo=true approval=approved missing=[] licence=uploaded profile=uploaded agreement=v17/v17 signed=true |  |
| 4 | fixtures | demo supplier B has the mandatory six | PASS | is_demo=true approval=approved missing=[] licence=uploaded profile=uploaded agreement=v17/v17 signed=true |  |
| 5 | fixtures | demo supplier C has the mandatory six | PASS | is_demo=true approval=approved missing=[] licence=uploaded profile=uploaded agreement=v17/v17 signed=true |  |
| 6 | f crawl | customer en-desktop: the portal is in this language | PASS | dir/lang = ltr/en |  |
| 7 | f crawl | customer en-desktop: every destination is on screen | PASS | 10 destination(s): Overview / My requests / Documents / Orders / Messages / Projects / Project room / What you may need next / Buying profile / Account |  |
| 8 | f crawl | customer en-desktop: Overview | PASS | 260 ms | 260 |
| 9 | f crawl | customer en-desktop: Overview - in-view buttons | PASS | 3 button(s) pressed without a crash |  |
| 10 | f crawl | customer en-desktop: My requests | PASS | 343 ms | 343 |
| 11 | f crawl | customer en-desktop: My requests - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 12 | f crawl | customer en-desktop: Documents | PASS | 157 ms | 157 |
| 13 | f crawl | customer en-desktop: Documents - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 14 | f crawl | customer en-desktop: Orders | PASS | 171 ms | 171 |
| 15 | f crawl | customer en-desktop: Orders - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 16 | f crawl | customer en-desktop: Messages | PASS | 105 ms | 105 |
| 17 | f crawl | customer en-desktop: Messages - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 18 | f crawl | customer en-desktop: Projects | PASS | 194 ms | 194 |
| 19 | f crawl | customer en-desktop: Projects - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 20 | f crawl | customer en-desktop: Project room | PASS | 74 ms | 74 |
| 21 | f crawl | customer en-desktop: Project room - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 22 | f crawl | customer en-desktop: What you may need next | PASS | 199 ms | 199 |
| 23 | f crawl | customer en-desktop: What you may need next - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 24 | f crawl | customer en-desktop: Buying profile | PASS | 201 ms | 201 |
| 25 | f crawl | customer en-desktop: Buying profile - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 26 | f crawl | customer en-desktop: Account | PASS | 178 ms | 178 |
| 27 | f crawl | customer en-desktop: Account - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 28 | f crawl | customer en-desktop: no console errors | PASS | clean |  |
| 29 | f crawl | customer ar-desktop: the portal is in this language | PASS | dir/lang = rtl/ar |  |
| 30 | f crawl | customer ar-desktop: every destination is on screen | PASS | 10 destination(s): نظرة عامة / طلباتي / المستندات / أوامر الشراء / الرسائل / المشاريع / غرفة المشروع / ما قد تحتاجه لاحقًا / ملف المشتريات / الحساب |  |
| 31 | f crawl | customer ar-desktop: نظرة عامة | PASS | 283 ms | 283 |
| 32 | f crawl | customer ar-desktop: نظرة عامة - in-view buttons | PASS | 3 button(s) pressed without a crash |  |
| 33 | f crawl | customer ar-desktop: طلباتي | PASS | 190 ms | 190 |
| 34 | f crawl | customer ar-desktop: طلباتي - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 35 | f crawl | customer ar-desktop: المستندات | PASS | 128 ms | 128 |
| 36 | f crawl | customer ar-desktop: المستندات - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 37 | f crawl | customer ar-desktop: أوامر الشراء | PASS | 125 ms | 125 |
| 38 | f crawl | customer ar-desktop: أوامر الشراء - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 39 | f crawl | customer ar-desktop: الرسائل | PASS | 319 ms | 319 |
| 40 | f crawl | customer ar-desktop: الرسائل - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 41 | f crawl | customer ar-desktop: المشاريع | PASS | 222 ms | 222 |
| 42 | f crawl | customer ar-desktop: المشاريع - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 43 | f crawl | customer ar-desktop: غرفة المشروع | PASS | 186 ms | 186 |
| 44 | f crawl | customer ar-desktop: غرفة المشروع - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 45 | f crawl | customer ar-desktop: ما قد تحتاجه لاحقًا | PASS | 145 ms | 145 |
| 46 | f crawl | customer ar-desktop: ما قد تحتاجه لاحقًا - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 47 | f crawl | customer ar-desktop: ملف المشتريات | PASS | 303 ms | 303 |
| 48 | f crawl | customer ar-desktop: ملف المشتريات - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 49 | f crawl | customer ar-desktop: الحساب | PASS | 74 ms | 74 |
| 50 | f crawl | customer ar-desktop: الحساب - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 51 | f crawl | customer ar-desktop: no console errors | PASS | clean |  |
| 52 | f crawl | customer en-mobile: the portal is in this language | PASS | dir/lang = ltr/en |  |
| 53 | f crawl | customer en-mobile: every destination is on screen | PASS | 10 destination(s): Overview / My requests / Documents / Messages / Orders / Projects / Project room / What you may need next / Buying profile / Account / العربية / Light mode / Sign out |  |
| 54 | f crawl | customer en-mobile: Overview | PASS | 81 ms | 81 |
| 55 | f crawl | customer en-mobile: Overview - in-view buttons | PASS | 3 button(s) pressed without a crash |  |
| 56 | f crawl | customer en-mobile: My requests | PASS | 164 ms | 164 |
| 57 | f crawl | customer en-mobile: My requests - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 58 | f crawl | customer en-mobile: Documents | PASS | 76 ms | 76 |
| 59 | f crawl | customer en-mobile: Documents - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 60 | f crawl | customer en-mobile: Orders | PASS | 432 ms | 432 |
| 61 | f crawl | customer en-mobile: Orders - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 62 | f crawl | customer en-mobile: Messages | PASS | 101 ms | 101 |
| 63 | f crawl | customer en-mobile: Messages - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 64 | f crawl | customer en-mobile: Projects | PASS | 438 ms | 438 |
| 65 | f crawl | customer en-mobile: Projects - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 66 | f crawl | customer en-mobile: Project room | PASS | 390 ms | 390 |
| 67 | f crawl | customer en-mobile: Project room - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 68 | f crawl | customer en-mobile: What you may need next | PASS | 461 ms | 461 |
| 69 | f crawl | customer en-mobile: What you may need next - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 70 | f crawl | customer en-mobile: Buying profile | PASS | 444 ms | 444 |
| 71 | f crawl | customer en-mobile: Buying profile - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 72 | f crawl | customer en-mobile: Account | PASS | 161 ms | 161 |
| 73 | f crawl | customer en-mobile: Account - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 74 | f crawl | customer en-mobile: no console errors | PASS | clean |  |
| 75 | f crawl | customer ar-mobile: the portal is in this language | PASS | dir/lang = rtl/ar |  |
| 76 | f crawl | customer ar-mobile: every destination is on screen | PASS | 10 destination(s): نظرة عامة / طلباتي / المستندات / الرسائل / أوامر الشراء / المشاريع / غرفة المشروع / ما قد تحتاجه لاحقًا / ملف المشتريات / الحساب / English / الوضع الفاتح / تسجيل الخروج |  |
| 77 | f crawl | customer ar-mobile: نظرة عامة | PASS | 61 ms | 61 |
| 78 | f crawl | customer ar-mobile: نظرة عامة - in-view buttons | PASS | 3 button(s) pressed without a crash |  |
| 79 | f crawl | customer ar-mobile: طلباتي | PASS | 119 ms | 119 |
| 80 | f crawl | customer ar-mobile: طلباتي - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 81 | f crawl | customer ar-mobile: المستندات | PASS | 91 ms | 91 |
| 82 | f crawl | customer ar-mobile: المستندات - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 83 | f crawl | customer ar-mobile: أوامر الشراء | PASS | 428 ms | 428 |
| 84 | f crawl | customer ar-mobile: أوامر الشراء - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 85 | f crawl | customer ar-mobile: الرسائل | PASS | 87 ms | 87 |
| 86 | f crawl | customer ar-mobile: الرسائل - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 87 | f crawl | customer ar-mobile: المشاريع | PASS | 440 ms | 440 |
| 88 | f crawl | customer ar-mobile: المشاريع - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 89 | f crawl | customer ar-mobile: غرفة المشروع | PASS | 431 ms | 431 |
| 90 | f crawl | customer ar-mobile: غرفة المشروع - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 91 | f crawl | customer ar-mobile: ما قد تحتاجه لاحقًا | PASS | 205 ms | 205 |
| 92 | f crawl | customer ar-mobile: ما قد تحتاجه لاحقًا - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 93 | f crawl | customer ar-mobile: ملف المشتريات | PASS | 497 ms | 497 |
| 94 | f crawl | customer ar-mobile: ملف المشتريات - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 95 | f crawl | customer ar-mobile: الحساب | PASS | 75 ms | 75 |
| 96 | f crawl | customer ar-mobile: الحساب - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 97 | f crawl | customer ar-mobile: no console errors | PASS | clean |  |
| 98 | f crawl | supplier en-desktop: the portal is in this language | PASS | dir/lang = ltr/en |  |
| 99 | f crawl | supplier en-desktop: every destination is on screen | PASS | 9 destination(s): Profile / Billing / Settings / Services / Inquiries received / Quotations submitted / Messages / Documents / Insights |  |
| 100 | f crawl | supplier en-desktop: Services | PASS | 223 ms | 223 |
| 101 | f crawl | supplier en-desktop: Services - in-view buttons | PASS | 9 button(s) pressed without a crash |  |
| 102 | f crawl | supplier en-desktop: Inquiries received | PASS | 2063 ms | 2063 |
| 103 | f crawl | supplier en-desktop: Quotations submitted | PASS | 2041 ms | 2041 |
| 104 | f crawl | supplier en-desktop: Messages | PASS | 2043 ms | 2043 |
| 105 | f crawl | supplier en-desktop: Messages - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 106 | f crawl | supplier en-desktop: Documents | PASS | 2039 ms | 2039 |
| 107 | f crawl | supplier en-desktop: Documents - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 108 | f crawl | supplier en-desktop: Insights | PASS | 4033 ms | 4033 |
| 109 | f crawl | supplier en-desktop: Insights - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 110 | f crawl | supplier en-desktop: Profile | PASS | 2072 ms | 2072 |
| 111 | f crawl | supplier en-desktop: Profile - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 112 | f crawl | supplier en-desktop: Billing | PASS | 2024 ms | 2024 |
| 113 | f crawl | supplier en-desktop: Billing - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 114 | f crawl | supplier en-desktop: Settings | PASS | 2049 ms | 2049 |
| 115 | f crawl | supplier en-desktop: Settings - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 116 | f crawl | supplier en-desktop: no console errors | PASS | clean |  |
| 117 | f crawl | supplier en-mobile: the portal is in this language | PASS | dir/lang = ltr/en |  |
| 118 | f crawl | supplier en-mobile: every destination is on screen | PASS | 9 destination(s): Profile / Billing / Settings / Services / Inquiries received / Quotations submitted / Messages / Documents / Insights |  |
| 119 | f crawl | supplier en-mobile: Services | PASS | 51 ms | 51 |
| 120 | f crawl | supplier en-mobile: Services - in-view buttons | PASS | 14 button(s) pressed without a crash |  |
| 121 | f crawl | supplier en-mobile: Inquiries received | PASS | 711 ms | 711 |
| 122 | f crawl | supplier en-mobile: Inquiries received - in-view buttons | PASS | 5 button(s) pressed without a crash |  |
| 123 | f crawl | supplier en-mobile: Quotations submitted | PASS | 1148 ms | 1148 |
| 124 | f crawl | supplier en-mobile: Quotations submitted - in-view buttons | PASS | 5 button(s) pressed without a crash |  |
| 125 | f crawl | supplier en-mobile: Messages | PASS | 607 ms | 607 |
| 126 | f crawl | supplier en-mobile: Messages - in-view buttons | PASS | 5 button(s) pressed without a crash |  |
| 127 | f crawl | supplier en-mobile: Documents | PASS | 816 ms | 816 |
| 128 | f crawl | supplier en-mobile: Documents - in-view buttons | PASS | 9 button(s) pressed without a crash |  |
| 129 | f crawl | supplier en-mobile: Insights | PASS | 1914 ms | 1914 |
| 130 | f crawl | supplier en-mobile: Insights - in-view buttons | PASS | 2 button(s) pressed without a crash |  |
| 131 | f crawl | supplier en-mobile: Profile | PASS | 2059 ms | 2059 |
| 132 | f crawl | supplier en-mobile: Profile - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 133 | f crawl | supplier en-mobile: Billing | PASS | 2043 ms | 2043 |
| 134 | f crawl | supplier en-mobile: Billing - in-view buttons | PASS | 1 button(s) pressed without a crash |  |
| 135 | f crawl | supplier en-mobile: Settings | PASS | 2032 ms | 2032 |
| 136 | f crawl | supplier en-mobile: Settings - in-view buttons | PASS | 3 button(s) pressed without a crash |  |
| 137 | f crawl | supplier en-mobile: no console errors | PASS | clean |  |
| 138 | safety | nothing the run caused was dispatched | PASS | email/suppressed: 4, whatsapp/suppressed: 4 |  |
| 139 | cleanup | zero leftovers | PASS | removed: notifications 8, comparison_candidate_v2 (table no longer exists) 0, agent_actions 9, documents 6, company_event (lead) 3, supplier_capability_confirmation 3, supplier_availability (fk supplier_id -> leads) 1, supplier_capabilities (fk supplier_id -> leads) 3, leads 3, customer_organization |  |

## Console errors

none

## Screenshots

- customer en-desktop: Overview: f_customer_en-desktop_1_Overview.png
- customer en-desktop: My requests: f_customer_en-desktop_2_My_requests.png
- customer en-desktop: Documents: f_customer_en-desktop_3_Documents.png
- customer en-desktop: Orders: f_customer_en-desktop_4_Orders.png
- customer en-desktop: Messages: f_customer_en-desktop_5_Messages.png
- customer en-desktop: Projects: f_customer_en-desktop_6_Projects.png
- customer en-desktop: Project room: f_customer_en-desktop_7_Project_room.png
- customer en-desktop: What you may need next: f_customer_en-desktop_8_What_you_may_need_next.png
- customer en-desktop: Buying profile: f_customer_en-desktop_9_Buying_profile.png
- customer en-desktop: Account: f_customer_en-desktop_10_Account.png
- customer ar-desktop: نظرة عامة: f_customer_ar-desktop_1__.png
- customer ar-desktop: طلباتي: f_customer_ar-desktop_2__.png
- customer ar-desktop: المستندات: f_customer_ar-desktop_3__.png
- customer ar-desktop: أوامر الشراء: f_customer_ar-desktop_4__.png
- customer ar-desktop: الرسائل: f_customer_ar-desktop_5__.png
- customer ar-desktop: المشاريع: f_customer_ar-desktop_6__.png
- customer ar-desktop: غرفة المشروع: f_customer_ar-desktop_7__.png
- customer ar-desktop: ما قد تحتاجه لاحقًا: f_customer_ar-desktop_8__.png
- customer ar-desktop: ملف المشتريات: f_customer_ar-desktop_9__.png
- customer ar-desktop: الحساب: f_customer_ar-desktop_10__.png
- customer en-mobile: Overview: f_customer_en-mobile_1_Overview.png
- customer en-mobile: My requests: f_customer_en-mobile_2_My_requests.png
- customer en-mobile: Documents: f_customer_en-mobile_3_Documents.png
- customer en-mobile: Orders: f_customer_en-mobile_4_Orders.png
- customer en-mobile: Messages: f_customer_en-mobile_5_Messages.png
- customer en-mobile: Projects: f_customer_en-mobile_6_Projects.png
- customer en-mobile: Project room: f_customer_en-mobile_7_Project_room.png
- customer en-mobile: What you may need next: f_customer_en-mobile_8_What_you_may_need_next.png
- customer en-mobile: Buying profile: f_customer_en-mobile_9_Buying_profile.png
- customer en-mobile: Account: f_customer_en-mobile_10_Account.png
- customer ar-mobile: نظرة عامة: f_customer_ar-mobile_1__.png
- customer ar-mobile: طلباتي: f_customer_ar-mobile_2__.png
- customer ar-mobile: المستندات: f_customer_ar-mobile_3__.png
- customer ar-mobile: أوامر الشراء: f_customer_ar-mobile_4__.png
- customer ar-mobile: الرسائل: f_customer_ar-mobile_5__.png
- customer ar-mobile: المشاريع: f_customer_ar-mobile_6__.png
- customer ar-mobile: غرفة المشروع: f_customer_ar-mobile_7__.png
- customer ar-mobile: ما قد تحتاجه لاحقًا: f_customer_ar-mobile_8__.png
- customer ar-mobile: ملف المشتريات: f_customer_ar-mobile_9__.png
- customer ar-mobile: الحساب: f_customer_ar-mobile_10__.png
- supplier en-desktop: Services: f_supplier_en-desktop_1_Services.png
- supplier en-desktop: Inquiries received: f_supplier_en-desktop_2_Inquiries_received.png
- supplier en-desktop: Quotations submitted: f_supplier_en-desktop_3_Quotations_submitted.png
- supplier en-desktop: Messages: f_supplier_en-desktop_4_Messages.png
- supplier en-desktop: Documents: f_supplier_en-desktop_5_Documents.png
- supplier en-desktop: Insights: f_supplier_en-desktop_6_Insights.png
- supplier en-desktop: Profile: f_supplier_en-desktop_7_Profile.png
- supplier en-desktop: Billing: f_supplier_en-desktop_8_Billing.png
- supplier en-desktop: Settings: f_supplier_en-desktop_9_Settings.png
- supplier en-mobile: Services: f_supplier_en-mobile_1_Services.png
- supplier en-mobile: Inquiries received: f_supplier_en-mobile_2_Inquiries_received.png
- supplier en-mobile: Quotations submitted: f_supplier_en-mobile_3_Quotations_submitted.png
- supplier en-mobile: Messages: f_supplier_en-mobile_4_Messages.png
- supplier en-mobile: Documents: f_supplier_en-mobile_5_Documents.png
- supplier en-mobile: Insights: f_supplier_en-mobile_6_Insights.png
- supplier en-mobile: Profile: f_supplier_en-mobile_7_Profile.png
- supplier en-mobile: Billing: f_supplier_en-mobile_8_Billing.png
- supplier en-mobile: Settings: f_supplier_en-mobile_9_Settings.png