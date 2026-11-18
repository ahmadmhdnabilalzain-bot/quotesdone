-- A BACKUP FOLDER WITH NO FILE, OR OF NO PARTY, IS A FINDING (sales_engineer, 18 Nov 2026; founder ruling ledger 1726).
-- "The Dropbox backup holds ONLY real, verified suppliers and customers ... no empty or useless folder ever ... EVERY folder he
-- appears in must contain his documents." Measured 17 Nov: Shine Carpets' first folder (Suppliers/Cleaning & facility services/
-- SHINE CARPETS WASHING L.L.C) was left holding only an empty "Earlier versions" folder when his files moved to Upholstery & soft
-- furnishing; the founder opened the empty one. The move now removes the folder it empties (dropbox_backup/move.ts
-- removeEmptiedSource). The nightly listing (dropbox_backup reconcile -> listingCheck) now also lists, under /QuotesDone Backup/
-- Suppliers and /Customers, every party folder with no file anywhere beneath it (summary.shells.empty) and every one no doc_backups
-- row files into (summary.shells.no_party: a demo, test or vanished party). This routine records them and raises ONE it_engineer
-- finding while any exists, closed when a listing finds none. Nothing is deleted: a person decides each folder.
--
-- The live body below is the one read on 18 Nov 2026 with pg_get_functiondef; only the shell lines are added.
-- Pending: scripts/sql/pending/a_backup_folder_with_no_file_or_no_party_is_a_finding.txt
-- Prevented by: supabase/functions/dropbox_backup/empty_source.test.ts (the listing), scripts/checks/an_interested_prospect_is_chased_three_times_until_he_registers_or_declines.test.mjs (its last test)

create or replace function public.fn_it_backup_listing_record(p_summary jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_bad integer := coalesce((p_summary->>'missing')::int, 0) + coalesce((p_summary->>'changed')::int, 0)
                       + coalesce((p_summary->>'unlisted_roots')::int, 0);
        v_shell integer := coalesce((p_summary->>'shell_folders')::int, 0);
        v_noparty integer := coalesce((p_summary->>'no_party_folders')::int, 0);
        v_status text;
begin
  v_status := case when v_bad + v_shell + v_noparty > 0 then 'warn' else 'ok' end;
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('it_engineer', v_status, jsonb_build_object('job', 'dropbox_listing_check') || coalesce(p_summary, '{}'::jsonb),
          left('IT engineer Dropbox listing check: ' || coalesce(p_summary->>'expected', '0') || ' backed-up files expected, '
               || coalesce(p_summary->>'listed', '0') || ' listed in Dropbox, ' || coalesce(p_summary->>'missing', '0') || ' missing ('
               || coalesce(p_summary->>'confirmed_missing', '0') || ' confirmed one by one), ' || coalesce(p_summary->>'changed', '0')
               || ' changed, ' || coalesce(p_summary->>'stray', '0') || ' in Dropbox with no record, '
               || coalesce(p_summary->>'unlisted_roots', '0') || ' folder(s) not listed in time, '
               || v_shell || ' empty party folder(s), ' || v_noparty || ' party folder(s) of no party.', 500),
          now(), now());
  -- ruling 1726: an empty folder, or one of no party, is raised (never deleted here); a listing that finds none closes it.
  -- A listing that did not reach Suppliers or Customers carries no 'shells' key and decides nothing.
  if p_summary ? 'shells' then
    if v_shell + v_noparty > 0 then
      perform public.fn_it_engineer_finding_upsert('dropbox:party_folder_empty_or_of_no_party',
        v_shell || ' empty and ' || v_noparty || ' ownerless supplier or customer folder(s) in the Dropbox backup',
        'Dropbox /QuotesDone Backup/Suppliers and /Customers (dropbox_backup listingCheck)', 'internal', v_shell + v_noparty,
        jsonb_build_object('empty', p_summary->'shells'->'empty', 'no_party', p_summary->'shells'->'no_party', 'owner_seat', 'sales_engineer',
                           'ask', 'Each folder is either filled with the party''s documents (a second trade folder gets them too) or removed by a person; nothing is deleted automatically.'),
        '{}'::text[], array['whether each listed folder belongs to a real verified party'], 'it_engineer');
    else
      perform public.fn_it_engineer_finding_close('dropbox:party_folder_empty_or_of_no_party', 'the nightly listing found no empty or ownerless party folder');
    end if;
  end if;
  return jsonb_build_object('status', v_status, 'shell_folders', v_shell, 'no_party_folders', v_noparty);
end $fn$;
revoke execute on function public.fn_it_backup_listing_record(jsonb) from public, anon, authenticated;
grant execute on function public.fn_it_backup_listing_record(jsonb) to service_role;
