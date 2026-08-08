-- BUG FOUND BY THE 6.3 PROBE, and it would have shipped silently.
--
-- trg_leads_exception_invariant was created as `before insert or update OF approval_status, ...`.
-- Postgres decides whether such a trigger fires from THE COLUMNS NAMED IN THE UPDATE STATEMENT, not
-- from what the row ends up looking like. The 6.3 licence-gate trigger changes approval_status in
-- NEW during a statement that only names license_expiry — so the invariant never fired, and a
-- supplier who recovered by uploading a good licence was set back to 'approved' while KEEPING AN
-- OPEN EXCEPTION WINDOW. That is defect (b) of audit 6.5, reintroduced by the fix for 6.3.
--
-- The probe caught it because it asserted the window state after the recovery, not just the status.
-- Asserting the thing you changed would have passed.
--
-- The column list goes. The invariant now fires on every update of leads; the function returns on
-- the first branch for the overwhelming majority of rows, which is a cheap price for an invariant
-- that cannot be sidestepped by which columns a statement happens to name.
drop trigger if exists trg_leads_exception_invariant on public.leads;
create trigger trg_leads_exception_invariant
  before insert or update on public.leads
  for each row execute function public.fn_leads_exception_invariant();;
