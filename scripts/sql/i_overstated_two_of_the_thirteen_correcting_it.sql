-- CORRECTING TWO SCENARIO ROWS I WROTE AN HOUR AGO. I STATED MORE THAN I HAD MEASURED.
--
-- pdf_corrupted and zip_instead_of_pdf were written as "NO RECOVERY PATH EXISTS ... the file is
-- accepted and then fails downstream where the error means nothing to the customer." I had checked
-- that no MIME validation existed and inferred the failure mode from that. Then I read the intake
-- path properly.
--
-- What actually happens, measured in customer_api action='analyze_drawing': a ZIP or an unreadable
-- PDF produces no renderable pages, and the function returns {ok:true, boq:null,
-- note:'no_readable_pages'} — a graceful degrade, not a crash. My text was wrong about the
-- mechanism. It was right that the customer is left with nothing to act on: one generic note
-- covered a corrupt file, a password-protected file and a compressed archive alike.
--
-- Both rows now describe the real behaviour AND the fix that shipped with this correction:
-- analyze_drawing distinguishes archive_not_supported from no_readable_pages and returns advice
-- the customer can follow. Recorded rather than quietly rewritten, because the founder's standing
-- rule is that a narrow check never licenses a broad claim, and I broke it.

update public.scenario_library set expected_behaviour =
 'RECOVERY EXISTS AS OF 11 AUG 2026, AND IT IS AN INSTRUCTION RATHER THAN A RETRY. Measured first: an unreadable PDF was never a crash — customer_api action=analyze_drawing finds no renderable pages and returns {ok:true, boq:null, note:''no_readable_pages''}. The defect was that the note was generic, so a corrupt file, a password-protected file and a compressed archive were indistinguishable to the customer. analyze_drawing now returns note plus advice: "We could not read any pages from this file. It may be corrupted, password-protected, or saved in a format we cannot open. Please re-export it as a PDF or upload clear images of each page." The original file is still stored, so nothing is lost and support can inspect it. STILL MISSING: no MIME or integrity validation at upload, so the file is accepted before we discover it is unusable.'
 where scenario_key = 'pdf_corrupted';

update public.scenario_library set expected_behaviour =
 'RECOVERY EXISTS AS OF 11 AUG 2026. This is the likeliest of the sixteen to actually happen — sending a zipped drawing set is normal practice in UAE construction. Measured first: the ZIP was never rejected and never crashed; it produced no renderable pages and fell through to the same generic ''no_readable_pages'' note as every other unreadable file. analyze_drawing now detects archives by extension and MIME (zip, rar, 7z, tar, tgz, gz) and returns note=''archive_not_supported'' with advice: "This is a compressed archive, so we cannot read the drawings inside it. Please extract it and upload the PDF or image files themselves — you can attach up to 10 pages." NOT BUILT, AND A DELIBERATE CHOICE: server-side extraction. Expanding untrusted archives inside an edge function invites zip-bomb and path-traversal handling that a clear instruction avoids entirely.'
 where scenario_key = 'zip_instead_of_pdf';
