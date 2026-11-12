-- MY_DATA_PDF IS OWNED BY CUSTOMER SUPPORT (12 Nov 2026; seat: customer_support, built by it_engineer).
--
-- The edge function my_data_pdf (founder ledgers 1669 and 1671: "Download my data should be a pdf with our template")
-- draws a signed-in person's own data copy on the document template. Customer support owns a person's privacy requests
-- (pdpl_request_me and the erase flow beside it), so it owns the door that answers one. Without this row
-- every_deployed_function_has_an_owner goes red the moment the function deploys (review of #1986, item 5).
-- ORDER: apply this, then deploy my_data_pdf at once (an owned function that is not deployed is the same check's
-- "stale row" finding, so the two are one step).
-- Prevented by: scripts/checks/every_deployed_function_has_an_owner.mjs

insert into public.function_owner (function_slug, owner, note)
values ('my_data_pdf', 'customer_support',
        'Download my data (PR #1986): the signed-in person''s own export from pdpl_request_me, drawn by pdf_native/render.ts on the '
        'letterhead and returned as a PDF; nothing stored. Seat of the privacy self-service controls on both portals.')
on conflict (function_slug) do update set owner = excluded.owner, note = excluded.note;

select case when (select owner from public.function_owner where function_slug = 'my_data_pdf') = 'customer_support'
            then 'PROBE OK: my_data_pdf is owned by customer_support'
            else 'PROBE FAILED: my_data_pdf has no owner row' end as verdict;
