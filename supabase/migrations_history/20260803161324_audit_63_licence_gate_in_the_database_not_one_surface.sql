-- AUDIT 6.3 — corrected-document recovery.
--
-- THE DEFECT. Only supplier_api's save_profile re-runs the licence gate and closes the exception.
-- The Documents tab does not: SupplierPortal.tsx calls supplier_portal save_documents, kind='license'
-- is a first-class document there, and that path ends in a plain UPDATE — no gate re-run, no
-- approval_status write, no exception close. And the reminder text the sweep sends points at exactly
-- that surface: "Upload a clear copy of your current trade licence in your supplier portal and your
-- account activates automatically." A supplier who does as they are told stays action_required and is
-- auto-rejected on day 14 WITH A VALID LICENCE ON FILE.
--
-- WHY NOT JUST COPY THE GATE INTO supplier_portal. Because the gate living in one surface's
-- TypeScript is the entire reason this happened. Copy it and there are two implementations to drift,
-- and a third upload surface reintroduces the bug. The gate belongs where the data is.
--
-- SO: the gate is a database function, and a trigger re-runs it whenever the licence columns change,
-- whatever wrote them. supplier_portal needs no change at all — its plain UPDATE now re-runs the
-- gate by construction. So does any future surface, and so does a manual fix by an operator.
--
-- SECOND DEFECT, same item: fn_supplier_exception_close is `where exception_closed_at is null`, so a
-- supplier auto-rejected and then recovered keeps exception_outcome='expired_auto_rejected' forever
-- — permanently miscounting recoveries as rejections in the very metric the report calls "the number
-- to watch". Recovery is now recorded as its own outcome.

create or replace function public.fn_supplier_licence_gate(
  p_license_doc_path text, p_trade_license_no text, p_license_expiry date)
returns jsonb
language sql immutable
as $$
  -- Mirrors what license_extract writes and, deliberately, what it refuses to write: expiry is left
  -- NULL when the document printed none, because license_extract never guesses. Treating NULL as a
  -- failure would reject perfectly good licences for the crime of an unusual layout, so NULL passes
  -- and the missing-document and missing-number cases carry the weight.
  select case
    when coalesce(p_license_doc_path, '') = '' then
      jsonb_build_object('ok', false, 'reason', 'No trade licence document on file.')
    when coalesce(p_trade_license_no, '') = '' then
      jsonb_build_object('ok', false, 'reason', 'A trade licence is on file but no licence number could be read from it. Please upload a clearer copy.')
    when p_license_expiry is not null and p_license_expiry < current_date then
      jsonb_build_object('ok', false, 'reason', 'The trade licence on file expired on ' || to_char(p_license_expiry, 'DD Mon YYYY') || '.')
    else jsonb_build_object('ok', true, 'reason', null)
  end;
$$;

create or replace function public.fn_leads_licence_gate_rerun()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare g jsonb;
begin
  -- Only when the licence evidence itself moved. A name change must not re-adjudicate approval.
  if tg_op = 'UPDATE'
     and new.license_doc_path  is not distinct from old.license_doc_path
     and new.trade_license_no  is not distinct from old.trade_license_no
     and new.license_expiry    is not distinct from old.license_expiry then
    return new;
  end if;

  g := public.fn_supplier_licence_gate(new.license_doc_path, new.trade_license_no, new.license_expiry);

  if (g ->> 'ok')::boolean then
    -- RECOVERY. This is the whole point of 6.3: a supplier who uploads a good licence anywhere gets
    -- their account back without anyone pressing anything.
    if coalesce(new.approval_status,'') = 'action_required' then
      new.approval_status     := 'approved';
      new.licence_gate_reason := null;
    elsif coalesce(new.approval_status,'') = 'rejected'
          and coalesce(new.exception_outcome,'') = 'expired_auto_rejected' then
      -- Auto-rejected on day 14, then fixed it. Previously impossible to record: the close is
      -- `where exception_closed_at is null` and the window was already closed, so the outcome stayed
      -- 'expired_auto_rejected' forever and every recovery was counted as a rejection.
      new.approval_status     := 'approved';
      new.licence_gate_reason := null;
      new.exception_outcome   := 'recovered_after_auto_reject';
    end if;
  else
    if coalesce(new.approval_status,'') in ('approved','verified') then
      new.approval_status     := 'action_required';
      new.licence_gate_reason := g ->> 'reason';
    elsif coalesce(new.approval_status,'') = 'action_required' then
      new.licence_gate_reason := g ->> 'reason';   -- keep the reason current as the evidence changes
    end if;
  end if;
  return new;
end $fn$;
revoke all on function public.fn_leads_licence_gate_rerun() from public, anon, authenticated;

-- NAME MATTERS. Postgres fires same-timing triggers in NAME order, and this one must run BEFORE
-- trg_leads_exception_invariant so the invariant sees the status this sets and opens or closes the
-- exception window to match. 'trg_leads_a_...' sorts before 'trg_leads_exception_...'.
drop trigger if exists trg_leads_a_licence_gate on public.leads;
create trigger trg_leads_a_licence_gate
  before insert or update of license_doc_path, trade_license_no, license_expiry
  on public.leads
  for each row execute function public.fn_leads_licence_gate_rerun();

create or replace view public.v_supplier_exception_outcomes as
select coalesce(exception_outcome, '(open or never opened)') as outcome, count(*) as suppliers
  from public.leads
 where exception_opened_at is not null
 group by 1 order by 2 desc;
comment on view public.v_supplier_exception_outcomes is
  'Exception outcomes including recovered_after_auto_reject, which could not previously exist: the '
  'close is `where exception_closed_at is null`, so a recovered supplier kept expired_auto_rejected '
  'forever and every recovery was counted as a rejection.';;
