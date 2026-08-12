-- OCR COVERAGE SAID 100% WHILE HALF THE EXTRACTIONS WERE EMPTY.
--
-- Chasing the four employee KPIs I had marked "needs a fixture or holdout set" turned up a
-- measurement that was already possible and an instrument reporting on the wrong subject.
--
-- MEASURED ON PRODUCTION 2026-08-12. All 8 rows in `documents` are status='done' and every one
-- carries an `extracted` jsonb. FOUR of the eight extracted to completely empty structure - empty
-- text and empty arrays on every field:
--
--   quote    produced      drawing  produced      licence  produced      drawing  produced
--   licence  EMPTY         profile  EMPTY         catalog  EMPTY         catalog  EMPTY
--
-- That is 50.00%. Meanwhile document_kpi_snapshots, written daily and 35 rows deep, reports
-- ocr_coverage_pct = 100 and doc_health = 96.3. Both are true to what they measure and neither
-- measures what its name implies: ocr_coverage_pct counts documents where extraction RAN, not
-- documents where it PRODUCED anything. A document that came back with an empty text field and
-- five empty arrays is counted as covered.
--
-- This is the recurring defect the founder has already named - a green number measuring something
-- other than what it says. It is recorded here rather than "fixed" by editing the snapshot: what
-- ocr_coverage_pct counts is a business definition, and changing it silently would move a number on
-- his dashboard without him choosing to. What IS fixed is that the employee responsible now has a
-- measure that reads the OUTPUT rather than the attempt.
--
-- ---------------------------------------------------------------------------------------------
-- KPI 101 doc_intel_manager — "Documents parsed to structured output", target 85%.
--
-- I MARKED THIS "NEEDS A FIXTURE" EARLIER TONIGHT AND THAT WAS THE WRONG REASON. Accuracy against
-- ground truth needs a fixture; this KPI's own NAME asks whether parsing produced structured output
-- at all, which is answerable from the 8 documents already on file. The metric text said "share of
-- uploads that produce requirements" and pointed at inquiry_requirement, which is empty because
-- there is no demand - so the metric text and the KPI name disagreed, and I took the metric text.
--
-- Measures 50.00% today against a target of 85. A thin denominator, and it grows with every upload.
update public.employee_kpi
   set measure_sql = $q$select round(100.0*count(*) filter (where coalesce(btrim(extracted->>'text'),'') <> '' or jsonb_array_length(coalesce(extracted->'specifications','[]'::jsonb)) > 0 or jsonb_array_length(coalesce(extracted->'quantities','[]'::jsonb)) > 0 or jsonb_array_length(coalesce(extracted->'brands','[]'::jsonb)) > 0 or jsonb_array_length(coalesce(extracted->'certifications','[]'::jsonb)) > 0)/nullif(count(*),0),2) from documents where status='done'$q$,
       no_measure_reason = null
 where id = 101;

-- ---------------------------------------------------------------------------------------------
-- KPI 102 drawing_analyst — "Drawings linked to RFQ items". The reason was wrong in KIND, and the
-- distinction matters because the two imply different next actions: a fixture is something to
-- BUILD, demand is something to WAIT for. There are 2 drawings on file and inquiry_requirement,
-- quote_requirements and inquiry_answer_document are all 0 rows - there is no RFQ line item in the
-- database to link a drawing TO. Nothing to build here.
update public.employee_kpi
   set no_measure_reason = 'NEEDS DEMAND THAT DOES NOT EXIST, not a fixture. Corrected 12 Aug 2026: '
       || '2 drawings are on file but inquiry_requirement, quote_requirements and '
       || 'inquiry_answer_document hold 0 rows, so there is no RFQ line item to link a drawing to. '
       || 'This starts answering with the first inquiry; it is a wait, not a build.'
 where id = 102;

-- 103 and 114 keep "needs a fixture or holdout set" and they are the real ones: their metric text
-- says "against the fixture set" and "against the holdout set" in so many words. Building those
-- sets IS the work, and it is a build, not a measure.
