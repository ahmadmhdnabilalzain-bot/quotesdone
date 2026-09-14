-- CUSTOMERS ARE NOT TOLD WE KEEP COPIES, OR WHICH VENDORS WE USE
--
-- The founder, 14 Sep 2026 (public.founder_instruction 196 and 197, verbatim):
--   "why do we have to mention to customers that we are saving a copy. remove that"
--   "the part where it says supabase and dropbox. definitely remove that"
--
-- MEASURED. The website widget (site_assistant) answers from company_faq rows with public = true and
-- status = 'approved', and from fn_support_corpus_search(p_public => true), whose only public rows are
-- those same FAQ rows (v_support_corpus lets only src = 'faq' be public). A scan of those public rows
-- for the two vendor names and for backup / archive / "signed copy" wording found seven:
--   119 How are backups performed?          -- whole answer is "we back it up / archive it"
--   128 How are documents archived?         -- whole answer is "we archive your documents"
--   154 How does Dropbox integration work?  -- whole answer is the vendor
--   157 Which APIs are available?           -- lists every vendor
--   160 Customer onboarding policy          -- "(a signed copy is stored)"
--   161 Document policy                     -- "Originals are backed up to <vendor> ..."
--   163 Data retention policy               -- "backups are kept in <vendor>"
-- The knowledge index kb_chunks carries a copy of each of these under source_kind 'company_faq'
-- (ids 174360, 174361, 174363, 174463, 174511, 174640), which the portal agents retrieve from.
-- support_public_override has no row for any of the seven, so f.public alone decides.
--
-- WHAT THIS CHANGES.
--   * 119, 128, 154 stop being public. They are not deleted: the rows are still true, and the seats'
--     internal answers keep them. Their kb_chunks copies move to kb_chunk_quarantine with a reason.
--   * 157, 160, 161, 163 are rewritten in place, the sentence removed and the rest kept, and the same
--     sentence is removed from their kb_chunks copies. Stripe stays in 157 because the checkout shows it.
--   * The same edits were made to the published FAQ page, src/content/marketing.json, EN and AR.
--
-- WHAT THIS DOES NOT CHANGE.
--   * Internal FAQ rows (public = false) that name the vendors: they are the seats' own knowledge.
--   * The Privacy Policy and Terms: versioned legal documents with acceptance records. Any sentence
--     there is listed for the founder, not edited here.
--   * Embeddings of the rewritten rows are left as they are; the edits only remove a sentence, so the
--     vectors still describe the answer.
--
-- No routine is defined in this file, so the probe at the end uses raise notice, never an exception.

-- Rewrites: each must change exactly one row, or the file fails and nothing is applied.
do $$
declare n int;
begin
  update public.company_faq set answer = replace(answer,
    'QuotesDone runs on its own secure backend and connects to trusted third-party services behind the scenes: Stripe (payments), Dropbox (document backup), Twilio (SMS and voice OTP), WhatsApp (notifications), an email service (transactional mail), a large-language-model gateway (the Smart Engine), and Meta Ads (marketing).',
    'QuotesDone runs on its own secure backend. Payments are processed by Stripe; everything else runs behind the scenes.'),
    source_note = coalesce(source_note,'') || ' | 14 Sep 2026: vendor list removed (founder_instruction 197)', updated_at = now()
   where id = 157 and answer like 'QuotesDone runs on its own secure backend and connects%';
  get diagnostics n = row_count; if n <> 1 then raise exception 'faq 157: % rows', n; end if;

  update public.company_faq set answer = replace(answer, ' (a signed copy is stored)', ''),
    source_note = coalesce(source_note,'') || ' | 14 Sep 2026: copy-kept wording removed (founder_instruction 196)', updated_at = now()
   where id = 160 and answer like '%(a signed copy is stored)%';
  get diagnostics n = row_count; if n <> 1 then raise exception 'faq 160: % rows', n; end if;

  update public.company_faq set answer = replace(answer, ' Originals are backed up to Dropbox in an organized tree.', ''),
    source_note = coalesce(source_note,'') || ' | 14 Sep 2026: backup sentence removed (founder_instruction 196, 197)', updated_at = now()
   where id = 161 and answer like '%Originals are backed up to Dropbox in an organized tree.%';
  get diagnostics n = row_count; if n <> 1 then raise exception 'faq 161: % rows', n; end if;

  update public.company_faq set answer = replace(answer, 'dispute obligations; backups are kept in Dropbox.', 'dispute obligations.'),
    source_note = coalesce(source_note,'') || ' | 14 Sep 2026: backup clause removed (founder_instruction 196, 197)', updated_at = now()
   where id = 163 and answer like '%backups are kept in Dropbox.%';
  get diagnostics n = row_count; if n <> 1 then raise exception 'faq 163: % rows', n; end if;

  update public.company_faq set public = false,
    source_note = coalesce(source_note,'') || ' | 14 Sep 2026: withdrawn from customers (founder_instruction 196, 197); kept for the seats', updated_at = now()
   where id in (119, 128, 154) and public;
  get diagnostics n = row_count; if n <> 3 then raise exception 'withdraw 119/128/154: % rows', n; end if;

  -- The index copies of the rewritten answers.
  update public.kb_chunks set content = replace(content, ' (a signed copy is stored)', '') where id = 174360;
  update public.kb_chunks set content = replace(content, ' Originals are backed up to Dropbox in an organized tree.', '') where id = 174361;
  update public.kb_chunks set content = replace(content, 'dispute obligations; backups are kept in Dropbox.', 'dispute obligations.') where id = 174363;

  -- The index copies of the withdrawn questions leave the index; the quarantine keeps the text.
  insert into public.kb_chunk_quarantine (id, source_kind, source_id, category, title, content, citation,
                                          effective_date, created_at, category_norm, reason, quarantined_at)
  select id, source_kind, source_id, category, title, content, citation, effective_date, created_at, category_norm,
         'withdrawn from customer answers 14 Sep 2026 (founder_instruction 196, 197)', now()
    from public.kb_chunks where id in (174463, 174511, 174640)
  on conflict do nothing;
  delete from public.kb_chunks where id in (174463, 174511, 174640);
end $$;

-- PROBE: nothing a customer can be answered from names either vendor or says a copy is kept.
do $$
declare n_public int; n_chunks int;
begin
  select count(*) into n_public from public.v_support_corpus
   where is_public and (coalesce(title,'') || ' ' || content) ~* '(dropbox|supabase|backed up|backups? (are|is) kept|signed copy is stored)';
  select count(*) into n_chunks from public.kb_chunks
   where source_kind = 'company_faq' and id in (174360, 174361, 174363, 174463, 174511, 174640)
     and content ~* '(dropbox|backed up|signed copy is stored)';
  if n_public <> 0 or n_chunks <> 0 then
    raise exception 'CHK<<public=% chunks=%>>', n_public, n_chunks;
  end if;
  raise notice 'CHK<<public=0 chunks=0>>';
end $$;
