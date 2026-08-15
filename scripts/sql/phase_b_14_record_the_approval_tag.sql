-- Phase B — record the approval tag by name on the baseline row.
--
-- Phase A recorded final_commit = d5107300 while its tag phase-a-founder-approved-2026-08-15
-- was later placed on the merge commit 00f1f47. Both are correct — the first is the tree the
-- digests were taken from, the second is the commit that carries it on main — but nothing said
-- so, and a future reader comparing them finds a discrepancy with no explanation.
--
-- So Phase B records BOTH, and says which is which:
--   final_commit  the commit whose tree the registry digests were computed from
--   git_tag       the annotated tag placed on the merge that carries the architecture AND its
--                 freeze. Resolve it with `git rev-list -n 1 <tag>`; it is deliberately not
--                 hard-coded here, because the SHA cannot be known until the commit that
--                 contains this file has itself been merged.

set lock_timeout = '8s';
set statement_timeout = '600s';

update public.org_phase_baseline
   set counts = counts || jsonb_build_object(
         'git_tag', 'phase-b-founder-approved-2026-08-15',
         'git_tag_note', 'The tag is placed on the merge commit that carries both the approved '
           || 'architecture and its freeze. final_commit names the commit whose tree the registry '
           || 'digests were computed from; the two differ by the bookkeeping commits that record '
           || 'the approval, which is expected and is stated here rather than left to be found.')
 where phase = 'B';

do $$
begin
  if not exists (select 1 from public.org_phase_baseline
                  where phase = 'B' and counts ? 'git_tag') then
    raise exception 'phase_b: the approval tag was not recorded on the baseline row';
  end if;
  raise notice 'phase_b: approval tag recorded as %',
    (select counts->>'git_tag' from public.org_phase_baseline where phase = 'B');
end $$;
