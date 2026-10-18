-- A PERSON SEES THEIR OWN OPEN PRIVACY REQUESTS ON ANY DEVICE (sales_engineer, 7 Oct 2026, #1273).
-- Assigned: sales_engineer. The account page's "Your data" section reads this on load, so a scheduled erase
-- shows its date, what is kept and its Cancel button on every device, not only the browser that confirmed it.
-- Own requests only: no identity argument; the address is fn_pdpl_my_verified_email() (JWT email AND that
-- account's email_verified), exactly as pdpl_request_me / pdpl_confirm_me / pdpl_cancel_me (#1237).
-- Returns only open requests (received, cooling_off, held), never a code hash or the export itself.
create or replace function public.pdpl_status_me()
returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with me as (select public.fn_pdpl_my_verified_email() as em)
  select case when (select em from me) is null
    then jsonb_build_object('ok', false, 'code', 'email_not_verified')
    else jsonb_build_object('ok', true, 'requests', coalesce((
      select jsonb_agg(jsonb_build_object(
               'request_id', q.id, 'kind', q.kind, 'status', q.status, 'created_at', q.created_at,
               'confirm_after', q.confirm_after,
               'deferred', coalesce(q.outcome -> 'deferred', '[]'::jsonb),
               'held', q.outcome -> 'held') order by q.created_at desc)
        from public.pdpl_requests q, me
       where q.email = me.em and q.status in ('received', 'cooling_off', 'held')), '[]'::jsonb))
  end;
$fn$;
revoke execute on function public.pdpl_status_me() from public, anon;
grant execute on function public.pdpl_status_me() to authenticated;
