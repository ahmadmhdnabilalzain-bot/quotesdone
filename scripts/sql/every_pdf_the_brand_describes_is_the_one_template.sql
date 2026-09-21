-- EVERY PDF THE BRAND DESCRIBES IS THE ONE TEMPLATE (22 Sep 2026, seat: sales_engineer).
--
-- MEASURED 22 Sep 2026 on production (read-only):
--   * public.company_brand 'type.pdf' says reports use "Helvetica / Helvetica-Bold (pdf-lib standard)", and
--     'imagery.documents' says every PDF has a "Helvetica body" and the footer "Confidential — QuotesDone".
--   * Both describe report_pdf, which is not deployed: the project's edge-function list holds pdf_native
--     and no other function with "pdf" or "report" in its name, and action_execution has 0 rows keyed
--     report_pdf:*. Every PDF the company issues is drawn by pdf_native (Sora + Arabic faces, the
--     doc_template.ts letterhead and footer).
--   * These rows are rendered into every agent head (qd-company:brand), so the agents were taught a
--     template that does not exist.
--
-- WHAT THIS CHANGES. The two rows' value and note, to the one template (audit of every document we issue,
-- finding 6). The owning file, the_company_knows_its_own_brand.sql, carries the same values, so a re-apply
-- of it cannot bring the old text back.
--
-- WHAT IT DOES NOT CHANGE. No other brand row; no routine; the colour rows (navy #0C2330 is already the
-- table's value — pdf_native was the one off the table, fixed in render.ts). The dormant z_report_pdf_enqueue
-- triggers are NOT touched here (a separate subject: an enqueue with no consumer).
--
-- Probe: every_pdf_the_brand_describes_is_the_one_template_probe.sql (pure probe, verdict row).

update public.company_brand set
  value = 'Sora (Latin) + the brand Arabic faces (brand bucket qd_sora_*.ttf, qd_ar_*.ttf), embedded and subset, for EVERY PDF: pdf_native is the one template',
  note = 'There is no report_pdf renderer (not deployed, measured 22 Sep 2026). A character no embedded face can draw is counted, and a signed or stamped document carrying one is refused.',
  updated_at = now()
 where key = 'type.pdf';

update public.company_brand set
  value = 'Every PDF is drawn by pdf_native (supabase/functions/pdf_native/render.ts) with the doc_template.ts letterhead: navy #0C2330 cover band or letterhead band with the OnDark lockup sized by height, teal section markers, gold rules and totals, Sora and the brand Arabic faces, and on every page the legal line (DET Trader License No. 1633275 · TDRA NOL-26-100000665), contact line, document-control line and page x of y, all in the document''s language. No third-party PDF (Stripe''s included) is issued as ours. Email: white card on #F6F7F9, navy "Quotes" + teal "Done" wordmark, teal-deep links.',
  note = 'Checked by scripts/checks/every_pdf_we_issue_is_on_our_template.mjs.',
  updated_at = now()
 where key = 'imagery.documents';
