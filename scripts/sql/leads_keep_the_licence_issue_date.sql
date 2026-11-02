-- THE LICENCE ISSUE DATE IS READ AND KEPT WHEN THE LICENCE PRINTS ONE. Seat: sales_engineer, 2 Nov 2026, ledger 1467
-- (the founder: dates are read and filled). The readers already return it (document_expiry.ts readLicenceFields,
-- license_extract issue_date); no column held it, so it was read and thrown away. Nothing requires it: a licence that
-- prints none leaves it null and blocks nothing. supplier_api process_docs and supplier_portal save_documents write it
-- in a write of their own, so a function deployed before this column exists costs only that one line.
alter table public.leads add column if not exists license_issue_date date;
comment on column public.leads.license_issue_date is 'Issue date printed on the trade licence, as read by code or the document model; null when the licence prints none or it was not read. Never required.';
