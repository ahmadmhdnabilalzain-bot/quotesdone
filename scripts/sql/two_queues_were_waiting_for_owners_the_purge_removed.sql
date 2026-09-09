-- TWO QUEUES WERE WAITING FOR OWNERS THE PURGE REMOVED.
--
-- The IT engineer's first two alerts, sent unaided on 9 September 2026, were both real and both the
-- same shape. Measured before touching anything:
--
--   exec_reports  318 rows at status 'new', 6 Jul - 15 Aug 2026, addressed to officers `strategy`,
--                 `competitive`, `data_science`, `product_ux`, `operations`, `procurement_quality`
--                 and others. Of the six distinct officers named in that table, ZERO still exist
--                 in org_role. I had said "exactly one" from an agent's summary and never checked
--                 it: org_role holds accountant, ceo, customer_support, it_engineer and
--                 sales_engineer, and not one of the six is among them. These are executive reports
--                 written by the programme the founder deleted on 7 September, queued for readers
--                 who no longer exist.
--
--   doc_backups   26 rows at status 'error', 11 Jul - 15 Jul 2026, attempts exhausted. They are
--                 Dropbox backup jobs whose SUBJECT was deleted underneath them.
--
-- Neither is a LIVE fault. Nothing is broken because of them; nothing is waiting on them. They are
-- residue of the September purge, and their only effect is that the detector keeps raising them,
-- which is how a real alert gets ignored.
--
-- TWO MISTAKES I MADE WRITING THIS FILE, BOTH CAUGHT BY GUARDS RATHER THAN BY ME.
--
--   1. I read ONE doc_backups row and wrote the file as though all 26 were `supplier_missing`.
--      Only 8 are. There are three error strings across two subjects.
--   2. I then keyed the widened guard on the ERROR TEXT and invented the tables it should check --
--      `public.suppliers` and `public.quote_comparisons`. Neither is the subject. `suppliers` does
--      not exist at all; the apply failed with 42P01. doc_backups carries an `entity` column that
--      says what entity_id points at, and it is the only thing that should decide the lookup:
--
--        entity 'supplier' (11 rows) -> public.leads      (bigint id; entity_ids 30296..40467)
--        entity 'inquiry'  (15 rows) -> public.inquiries  (uuid id)
--
--      An error string describes how a job failed. It is not a statement about which table owns the
--      row, and reading it as one is how I nearly checked the emptiness of the wrong table and
--      called that proof.
--
-- WHAT THE POSITIVE CONTROLS CAN AND CANNOT SHOW. Stated plainly, because they differ per class:
--
--   supplier / leads      STRONG. leads holds 22,264 rows and the id range 1..122460 spans every
--                         entity_id here, so the lookup CAN return true. It returns 0 -- these
--                         particular suppliers were purged out of a table that is otherwise full.
--   supplier / storage    STRONG. bucket `supplier-docs` holds 24 objects, so the lookup can return
--                         true. These 3 paths are genuinely absent from a bucket with content.
--   inquiry / inquiries   WEAK, AND SAID SO. public.inquiries has ZERO rows. "not exists" is
--                         trivially true for every possible entity_id, so this check cannot tell an
--                         orphan from a live row -- there are no live rows to tell it from. An empty
--                         parent means every child reference IS orphaned, which is why closing them
--                         is still correct; it is not evidence that the check discriminates.
--
-- WHY CLOSE RATHER THAN DELETE. The rows are the evidence that the purge left work behind. Deleting
-- them erases the only record it happened. exec_reports go to 'obsolete', doc_backups to
-- 'abandoned'. The queue detector reads pending/error states, so both leave its window and stop
-- alerting, while an auditor can still see what was orphaned.
--
-- THE DETECTOR IS NOT WEAKENED. Its thresholds are untouched. If either queue fills again with
-- genuinely pending work it fires exactly as before -- this closes the findings by removing the
-- FAULT, never by softening the instrument that found it.

do $do$
declare
  v_exec_before int; v_exec_after int; v_orphan int; v_live_officers int;
  v_back_before int; v_back_after int; v_orphaned int;
  v_leads int; v_bucket_objs int; v_inquiries int;
begin
  ---------------------------------------------------------------------------------------------
  -- POSITIVE CONTROL FIRST: the rows must be there. Closing an empty queue proves nothing.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_exec_before from public.exec_reports where status = 'new';
  select count(*) into v_back_before from public.doc_backups  where status = 'error';
  if v_exec_before = 0 and v_back_before = 0 then
    raise notice 'both queues are already clear - nothing to do';
    return;
  end if;

  -- Of the officers these reports are addressed to, how many still exist, and how many do not?
  select count(distinct e.officer) into v_orphan
    from public.exec_reports e
   where e.status = 'new'
     and not exists (select 1 from public.org_role r where r.role_id = e.officer);
  select count(distinct e.officer) into v_live_officers
    from public.exec_reports e
   where e.status = 'new'
     and exists (select 1 from public.org_role r where r.role_id = e.officer);

  if v_exec_before > 0 and v_orphan = 0 then
    raise exception 'every officer in exec_reports still exists - these are NOT orphaned and must not be closed';
  end if;

  -- The two lookups that CAN return true must be able to. If leads were empty or the bucket bare,
  -- "the subject is gone" would be a statement about the instrument, not about these rows.
  select count(*) into v_leads       from public.leads;
  select count(*) into v_bucket_objs from storage.objects where bucket_id = 'supplier-docs';
  select count(*) into v_inquiries   from public.inquiries;
  if v_leads = 0 or v_bucket_objs = 0 then
    raise exception 'POSITIVE CONTROL FAILED: leads has % row(s) and supplier-docs has % object(s); a lookup that cannot return true proves nothing about these rows',
      v_leads, v_bucket_objs;
  end if;

  ---------------------------------------------------------------------------------------------
  -- Each row checked against the table its OWN `entity` column names.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_orphaned
    from public.doc_backups d
   where d.status = 'error'
     and (
       -- the lead (supplier) it was backing up is gone
       (d.entity = 'supplier' and d.entity_id ~ '^[0-9]+$'
          and not exists (select 1 from public.leads l where l.id = d.entity_id::bigint))
       -- ...or the file it was told to download is gone from a bucket that still holds others
       or (d.entity = 'supplier' and d.bucket is not null
          and not exists (select 1 from storage.objects o
                           where o.bucket_id = d.bucket and o.name = d.path))
       -- the inquiry it was backing up is gone (see WEAK above: inquiries is empty)
       or (d.entity = 'inquiry'
          and not exists (select 1 from public.inquiries i where i.id::text = d.entity_id))
     );

  if v_back_before > 0 and v_orphaned <> v_back_before then
    raise exception '% of % doc_backups error row(s) still have a live subject; they are a real fault to FIX, not residue to close',
      v_back_before - v_orphaned, v_back_before;
  end if;

  ---------------------------------------------------------------------------------------------
  -- Close only what is genuinely orphaned. A report addressed to an officer who still exists is
  -- LEFT ALONE, even in the same sweep -- the whole justification is that the reader is gone.
  ---------------------------------------------------------------------------------------------
  update public.exec_reports
     set status = 'obsolete'
   where status = 'new'
     and not exists (select 1 from public.org_role r where r.role_id = exec_reports.officer);

  update public.doc_backups d
     set status = 'abandoned'
   where d.status = 'error'
     and (
       (d.entity = 'supplier' and d.entity_id ~ '^[0-9]+$'
          and not exists (select 1 from public.leads l where l.id = d.entity_id::bigint))
       or (d.entity = 'supplier' and d.bucket is not null
          and not exists (select 1 from storage.objects o
                           where o.bucket_id = d.bucket and o.name = d.path))
       or (d.entity = 'inquiry'
          and not exists (select 1 from public.inquiries i where i.id::text = d.entity_id))
     );

  select count(*) into v_exec_after from public.exec_reports where status = 'new';
  select count(*) into v_back_after from public.doc_backups  where status = 'error';

  -- Reports for an officer who still exists must have survived.
  if v_live_officers > 0 and v_exec_after = 0 then
    raise exception 'reports addressed to % surviving officer(s) were closed too - that is live work', v_live_officers;
  end if;
  if v_back_after <> 0 then
    raise exception '% doc_backups error row(s) remain', v_back_after;
  end if;

  raise notice 'exec_reports new % -> % (% orphaned officer(s), % surviving). doc_backups error % -> 0. Controls: leads %, supplier-docs objects %, inquiries % (empty - that class is closed because its parent holds nothing, not because the check discriminated).',
    v_exec_before, v_exec_after, v_orphan, v_live_officers, v_back_before,
    v_leads, v_bucket_objs, v_inquiries;
end
$do$;
