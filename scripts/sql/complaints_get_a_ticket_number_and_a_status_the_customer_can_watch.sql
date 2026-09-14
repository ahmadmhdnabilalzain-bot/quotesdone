-- COMPLAINTS GET A TICKET NUMBER AND A STATUS THE CUSTOMER CAN WATCH
--
-- Agent: customer_support. Complaints are handled by customer_support; the CEO decides refunds.
--
-- The website audit of 14 Sep 2026: "Complaints: expose a ticket number and status page for every
-- complaint (acknowledged / in review / final response) with the 2-day and 10-day timers visible,
-- plus the DET Consumer / Dubai Consumer App and 800 1222 escalation links printed on the final
-- response." The Complaints Policy promises an acknowledgement within 2 working days and a
-- substantive (final) response within 10 working days. Before this file a complaint was a
-- contact_messages row like any other: no number the customer could quote, no clock anyone could
-- see, and nothing that could show the policy was kept.
--
-- WHAT THIS BUILDS
--   1. public.complaint_tickets - one row per complaint, written by contact_submit (kind=complaint)
--      right after its contact_messages insert. Ticket numbers are QD-C- plus 6 characters from a
--      32-symbol alphabet with no 0/O/1/I, drawn from gen_random_uuid() bytes, so they cannot be
--      walked in sequence.
--   2. fn_complaint_open    - opens the ticket and stamps both due dates.
--   3. fn_complaint_lookup  - the public status read behind the complaint_status edge function.
--                             Ticket AND email must both match; a wrong email returns exactly what a
--                             missing ticket returns (null), so the endpoint never confirms that a
--                             ticket exists.
--   4. fn_complaint_set_status - customer_support moves a ticket forward only:
--                             acknowledged -> in_review -> final_response. A final response needs text.
--
-- WHAT IT REUSES (nothing second is invented)
--   * Working days: public.fn_add_working_days / fn_working_days_between, which read
--     fn_is_working_day = Monday-Friday and not in public.public_holidays, in Asia/Dubai time.
--     Measured 14 Sep 2026: public_holidays holds 16 rows, the last on 2027-12-03 - the table must be
--     extended before 2028 or the timers will count UAE holidays as working days.
--   * Rate limiting: public.rl_check(text,int,int) over rl_hits, called from the edge function the
--     same way login_otp, kyc, role_guard and site_assistant call it.
--
-- THE ACKNOWLEDGEMENT. Opening the ticket returns the ticket number and both due dates to the
-- customer on screen, which IS the acknowledgement the policy asks for, so a ticket opens in status
-- 'acknowledged' with acknowledged_at = now(). acknowledge_due is still stored so the 2-day promise
-- is visible and checkable against acknowledged_at.
--
-- Security: the table is RLS on, one explicit service-role-only policy, all privileges revoked from
-- public/anon/authenticated. Every routine is SECURITY DEFINER with search_path pinned and EXECUTE
-- revoked from public/anon/authenticated for its one signature (CREATE grants EXECUTE to PUBLIC, so
-- the revokes follow the creates), then granted to service_role only.
--
-- The probe at the end writes one @example.invalid row, proves the contract, deletes the row, asserts
-- it is gone and ends in raise notice - never raise exception, which would roll back the DDL above.
--
--   node scripts/apply_sql.mjs scripts/sql/complaints_get_a_ticket_number_and_a_status_the_customer_can_watch.sql --apply --ddl

begin;

-- ---------------------------------------------------------------------------------------------
-- THE TICKETS
-- ---------------------------------------------------------------------------------------------
create table if not exists public.complaint_tickets (
  id                  bigint generated always as identity primary key,
  ticket_no           text        not null unique check (ticket_no ~ '^QD-C-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}$'),
  email               text        not null check (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  name                text,
  message             text        not null,
  contact_message_id  bigint      references public.contact_messages(id) on delete set null,
  status              text        not null default 'acknowledged'
                        check (status in ('acknowledged','in_review','final_response')),
  created_at          timestamptz not null default now(),
  acknowledge_due     timestamptz not null,   -- 2 working days after created_at
  respond_due         timestamptz not null,   -- 10 working days after created_at
  acknowledged_at     timestamptz,
  in_review_at        timestamptz,
  final_response_at   timestamptz,
  final_response      text,
  handled_by          text        not null default 'customer_support'
                        check (handled_by in ('customer_support','ceo')),
  check (status <> 'final_response' or (final_response_at is not null and coalesce(btrim(final_response),'') <> ''))
);

create index if not exists complaint_tickets_open_idx
  on public.complaint_tickets (respond_due) where status <> 'final_response';

alter table public.complaint_tickets enable row level security;
drop policy if exists complaint_tickets_service_role_only on public.complaint_tickets;
create policy complaint_tickets_service_role_only on public.complaint_tickets
  as permissive for all to public using (false) with check (false);
revoke all on public.complaint_tickets from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- OPEN
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_complaint_open(
  p_email text, p_name text, p_message text, p_contact_message_id bigint default null)
returns jsonb language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';   -- 32 symbols, no 0/O/1/I
  v_email text := lower(btrim(coalesce(p_email,'')));
  v_no    text;
  v_bytes bytea;
  v_row   public.complaint_tickets;
  i int;
  attempt int := 0;
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'fn_complaint_open: invalid email'; end if;
  if coalesce(btrim(p_message),'') = '' then raise exception 'fn_complaint_open: empty message'; end if;
  loop
    attempt := attempt + 1;
    v_bytes := decode(replace(gen_random_uuid()::text,'-',''),'hex');
    v_no := 'QD-C-';
    for i in 0..5 loop v_no := v_no || substr(alphabet, (get_byte(v_bytes, i) % 32) + 1, 1); end loop;
    begin
      insert into public.complaint_tickets
        (ticket_no, email, name, message, contact_message_id, status,
         acknowledge_due, respond_due, acknowledged_at)
      values
        (v_no, v_email, nullif(btrim(coalesce(p_name,'')),''), left(p_message, 4000), p_contact_message_id,
         'acknowledged', public.fn_add_working_days(now(), 2), public.fn_add_working_days(now(), 10), now())
      returning * into v_row;
      exit;
    exception when unique_violation then
      if attempt >= 5 then raise; end if;
    end;
  end loop;
  return jsonb_build_object(
    'ticket', v_row.ticket_no, 'status', v_row.status, 'created_at', v_row.created_at,
    'acknowledge_due', v_row.acknowledge_due, 'respond_due', v_row.respond_due);
end $fn$;

revoke execute on function public.fn_complaint_open(text, text, text, bigint) from public, anon, authenticated;
grant  execute on function public.fn_complaint_open(text, text, text, bigint) to service_role;

-- ---------------------------------------------------------------------------------------------
-- LOOKUP (public-safe; null for a wrong email exactly as for a missing ticket)
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_complaint_lookup(p_ticket_no text, p_email text)
returns jsonb language plpgsql stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_row public.complaint_tickets;
begin
  select * into v_row from public.complaint_tickets
   where ticket_no = upper(btrim(coalesce(p_ticket_no,'')))
     and email = lower(btrim(coalesce(p_email,'')));
  if not found then return null; end if;
  return jsonb_build_object(
    'ticket', v_row.ticket_no,
    'status', v_row.status,
    'created_at', v_row.created_at,
    'acknowledge_due', v_row.acknowledge_due,
    'respond_due', v_row.respond_due,
    'acknowledged_at', v_row.acknowledged_at,
    'in_review_at', v_row.in_review_at,
    'final_response_at', v_row.final_response_at,
    'final_response', v_row.final_response,
    -- working days still left before each promise falls due (0 once today is the due day or later)
    'acknowledge_days_left', public.fn_working_days_between(now(), v_row.acknowledge_due),
    'respond_days_left', public.fn_working_days_between(now(), v_row.respond_due));
end $fn$;

revoke execute on function public.fn_complaint_lookup(text, text) from public, anon, authenticated;
grant  execute on function public.fn_complaint_lookup(text, text) to service_role;

-- ---------------------------------------------------------------------------------------------
-- SET STATUS (customer_support; forward only)
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_complaint_set_status(
  p_ticket_no text, p_status text, p_final_response text default null)
returns jsonb language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_row public.complaint_tickets;
  rank_old int; rank_new int;
begin
  select * into v_row from public.complaint_tickets
   where ticket_no = upper(btrim(coalesce(p_ticket_no,''))) for update;
  if not found then raise exception 'fn_complaint_set_status: no ticket %', p_ticket_no; end if;
  rank_old := array_position(array['acknowledged','in_review','final_response'], v_row.status);
  rank_new := array_position(array['acknowledged','in_review','final_response'], p_status);
  if rank_new is null then raise exception 'fn_complaint_set_status: unknown status %', p_status; end if;
  if rank_new <= rank_old then
    raise exception 'fn_complaint_set_status: % is already %; status only moves forward', v_row.ticket_no, v_row.status;
  end if;
  if p_status = 'final_response' and coalesce(btrim(p_final_response),'') = '' then
    raise exception 'fn_complaint_set_status: a final response needs its text';
  end if;
  update public.complaint_tickets set
    status            = p_status,
    in_review_at      = case when p_status = 'in_review' then now() else in_review_at end,
    final_response_at = case when p_status = 'final_response' then now() else final_response_at end,
    final_response    = case when p_status = 'final_response' then btrim(p_final_response) else final_response end
  where id = v_row.id
  returning * into v_row;
  return jsonb_build_object('ticket', v_row.ticket_no, 'status', v_row.status,
    'in_review_at', v_row.in_review_at, 'final_response_at', v_row.final_response_at);
end $fn$;

revoke execute on function public.fn_complaint_set_status(text, text, text) from public, anon, authenticated;
grant  execute on function public.fn_complaint_set_status(text, text, text) to service_role;

-- ---------------------------------------------------------------------------------------------
-- PROBE: one @example.invalid ticket, proved and removed. Cleans up and ends in a notice.
-- ---------------------------------------------------------------------------------------------
do $probe$
declare
  t jsonb; l jsonb; no text; backward_refused boolean := false; before_n int; after_n int;
begin
  select count(*) into before_n from public.complaint_tickets;
  t  := public.fn_complaint_open('ZZ.Probe@Example.invalid', 'ZZ DEMO probe', 'probe', null);
  no := t->>'ticket';
  if no !~ '^QD-C-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}$' then raise exception 'probe: bad ticket %', no; end if;
  if (t->>'respond_due')::timestamptz <= (t->>'acknowledge_due')::timestamptz then raise exception 'probe: respond_due not after acknowledge_due'; end if;
  if public.fn_complaint_lookup(no, 'someone.else@example.invalid') is not null then raise exception 'probe: wrong email revealed a ticket'; end if;
  if public.fn_complaint_lookup('QD-C-ZZZZZZ', 'zz.probe@example.invalid') is not null and no <> 'QD-C-ZZZZZZ' then raise exception 'probe: missing ticket found'; end if;
  l := public.fn_complaint_lookup(lower(no), 'zz.probe@example.invalid');
  if l->>'status' <> 'acknowledged' then raise exception 'probe: lookup failed %', l; end if;
  perform public.fn_complaint_set_status(no, 'in_review');
  begin
    perform public.fn_complaint_set_status(no, 'acknowledged');
  exception when others then backward_refused := true;
  end;
  if not backward_refused then raise exception 'probe: status moved backward'; end if;
  perform public.fn_complaint_set_status(no, 'final_response', 'probe final response');
  if public.fn_complaint_lookup(no, 'zz.probe@example.invalid')->>'final_response' <> 'probe final response' then raise exception 'probe: final response not returned'; end if;
  delete from public.complaint_tickets where ticket_no = no;
  select count(*) into after_n from public.complaint_tickets;
  if after_n <> before_n then raise exception 'probe: left % rows behind', after_n - before_n; end if;
  raise notice 'complaint ticket probe ok: open, lookup (right/wrong email), forward-only status, final response; probe row removed';
end $probe$;

commit;
