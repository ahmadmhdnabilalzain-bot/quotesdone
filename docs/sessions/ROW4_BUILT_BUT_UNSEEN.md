# ROW #4 CUSTOMER PORTAL - 146 requirements enumerated, and the headline finding

## The customer portal's BACKEND is largely BUILT. The UI renders almost none of it.

16 capabilities measured as complete server-side and invisible to the customer.
Each line below is a measurement, not an impression - grep counts and production row counts.

- disc-match-reason-shown â€” inquiry_matches.match_reason is the ONLY place the system records why a supplier was contacted. customer_api WRITES it at line 181; at line 669 my_inquiries reads inquiry_matches back and keeps a COUNT only. The one component that renders match_reason and similarity is src/components/osx/OsxShell.tsx:1532 ('% match' bar + reason text) â€” that is /os, staff-only, robots index:false. Customer sees: NO.

- rfqcc-response-count â€” customer_api my_inquiries emits matched_suppliers per inquiry, with the source comment 'Without this the portal cannot tell "waiting for quotes" apart from "this reached nobody", and shows hope either way.' grep matched_suppliers in CustomerPortal.tsx = 0 hits. The empty state at line 326 still reads 'we matched you with suitable suppliers' regardless. The exact defect that field was added to fix is still live in the UI. Customer sees: NO.

- viz-annual-procurement-series â€” fn_customer_stats returns 9 keys; the portal renders 6 as KPI tiles. history_12m (a 12-point {month,inquiries} series, confirmed against production) is computed on EVERY customer_portal overview call and rendered nowhere. Customer sees: NO.

- viz-bar-chart-rendered â€” recharts is installed and src/components/ui/chart.tsx is written; grep for importers of ui/chart across src/ = 0. Zero charts exist in the entire customer product. Customer sees: NO.

- rel-customer-ui (spec Â§13 in full) â€” customer_api action=supplier_history is customer-authed, reveal-gated, and returns supplier profile + up to 20 past projects with category/emirate/month/value_band + projects_count. grep supplier_history in src/ = 0. Section 13 is built end to end and has no caller. Customer sees: NO.

- proj-ui-rendered / mod-projects (spec Â§5 in full) â€” project_api ships 7 customer-authed actions (list, detail, dashboard, create, update, link, unlink) over public.projects and the project_summary view (rfq_count, rfq_open, rfq_awarded, pipeline_value, budget_total). grep project_api in src/ = 0 references. Customer sees: NO.

- qc-comparison-export â€” customer_api action=compare_pdf and action=brief_pdf both exist; grep in src/ = 0 each. Only quote_pdf is wired. Customer sees: NO.

- mem-customer-visible (spec Â§17) â€” customer_preference + fn_customer_preference_learn + trg_learn_customer_preference are green at 9/9 in verify_customer_preference.mjs, and fn_ws_customer_360->'preferences' serves them. grep customer_preference across supabase/functions/ = 0 readers; the only consumer is os_api (staff). Customer sees: NO.

- rfqcc-stage-from-event-log â€” fn_entity_activity('inquiry',id) exists (5,823 chars, returns a JSON array, verified executable against production) and company_event holds 470 rows. Its only reader is os_api. CustomerPortal.tsx computes stepIdx in the browser from quotes.length and anyRevealed. Customer sees the trace: NO.

- twin-customer-visible (spec Â§2) â€” v_digital_twin, fn_twin, fn_ws_customer_360 and customer_score (rfqs_posted, rfqs_awarded, avg_budget_aed, preferred_categories, lifetime_value_aed, churn_risk) all exist. fn_twin, v_digital_twin and customer_score have ZERO edge-function readers; fn_ws_customer_360 has one, os_api. Customer sees: NO.

- viz-supplier-performance-graphs â€” supplier_score is populated for all 20,464 leads with response_rate, avg_response_hours, quotes_submitted, quotes_won, price_index, quality_rating, reliability (reliability non-null on 20,464/20,464). No customer-facing endpoint selects any of it. Customer sees: NO.

- appr-customer-ui (spec Â§12) â€” procurement_approval_policy(steps jsonb), procurement_approval_request(current_step, decisions) and v_approval_trace all exist. grep procurement_approval_request across supabase/functions/ = 0 readers. Customer sees: NO.

- neg-customer-ui (spec Â§15) â€” supplier_negotiation_policy(policy jsonb, approved_by, approved_at) exists; 0 edge-function readers. Customer sees: NO.

- mod-orders â€” po_orders(po_no, vendor_id, expected_date, status, approved_by) exists; 0 edge-function readers; fn_po_approve exists with no caller. Customer sees: NO.

- doc-customer-ui (spec Â§14) â€” documents (16 rows), document_inventory, document_kpis and fn_register_document exist and doc_extract is green 7/7. The only reader is fn_ws_documents, which is the staff workspace. Customer sees: NO.

- my_inquiries field-level waste â€” of 47 fields the payload serves, 18 are rendered nowhere: inquiry-level scope_type, brief_source, boq_confidence, outcome, matched_suppliers, drawing_file_url (a signed URL to the customer's OWN uploaded drawing), child_count; quote-level notes, validity, expires_at, expired, conditions, exclusions, source, has_original, rating_source, years_active, jobs_won. Quote expiry in particular is computed server-side and never warned about.

## What this means for the build order

This row is NOT 146 things to build from zero. A large fraction is already built and simply not
surfaced - those are the fastest real value in the whole project. The genuinely net-new builds
(3D project visualization, AI negotiation assistant, predictive intelligence, supply-chain map,
mobile app) are a smaller set and should be sequenced after the surfacing work.

Per docs/sessions/SPECS_ARE_UPGRADES.md: surfacing an existing capability is the FLOOR. Where the
spec asks for more than the backend provides, build the rest.
