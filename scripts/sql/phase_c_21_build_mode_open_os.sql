-- BUILD MODE — the OS answers without a sign-in, until the founder says otherwise.
--
-- His instruction, 15 Aug 2026, third time of asking and unambiguous: "I'm the owner and this is
-- mine… whoever enters with my link, let him enter. I don't care… don't put any boundaries that
-- will limit you or force you to wait for me to give you access. No one knows about this company.
-- We wait till everything is done, everything is perfect. That time, I'll tell you activate the
-- credentials." And on the browser specifically: "that's not me accessing, it's you using my
-- browser. There's no access for me now. That's how it should be."
--
-- WHAT HE KEPT, in his own words, and this file honours all of it:
--   * Supabase itself stays locked — RLS is untouched by this file.
--   * GitHub stays private.
--   * Only the OS/website surface opens.
--
-- WHAT IS ACTUALLY BEHIND THAT DOOR, measured rather than assumed, because he deserves the real
-- number and not a warning:
--
--   customers ....... 0        transactions ..... 0
--   leads ....... 20,465       employees ....... 90
--
-- No consumer records and no payment data. The exposure is 20,465 scraped BUSINESS lead records —
-- company names and contacts, not private individuals. That is a real thing to hand out to anyone
-- with the URL, and it is a much smaller thing than it would be after launch. His call, and the
-- facts support it.
--
-- WHY THIS IS A SWITCH AND NOT A DELETION. Ripping the identity check out of os_api would make
-- "activate the credentials" a code change under time pressure on the day it matters most. This is
-- one row, like the Control Mode rollback he already has: fn_os_open_access() reads the newest
-- open/closed row, os_api consults it, and closing it is one INSERT.
--
-- THREE THINGS THIS KEEPS, deliberately, because none of them costs him anything:
--
--   * EVERY open-door request is written to os_audit_log under the identity
--     'build-mode (no authentication)'. If anyone does find the link, there is a record of exactly
--     what they touched. An open door with no camera is the only version of this that is careless.
--   * The build identity is NAMED, not disguised as him. A command issued through the open door is
--     attributed to build mode in founder_command_message.founder_identity, so the audit trail
--     never claims he said something he did not. That was worth removing a row for this morning
--     and it is worth preserving now.
--   * The x-os-key preview key stays read-only. It is a separate door and this file does not
--     widen it.
--
-- TO CLOSE IT — the "activate the credentials" moment:
--   insert into public.os_open_access_log (actor, state, reason)
--   values ('management@quotesdone.com', 'closed', 'launch: credentials active');
--   delete from public.phase_c_founder_identity where identity = 'build-mode@quotesdone.local';
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

create table if not exists public.os_open_access_log (
  id      bigint generated always as identity primary key,
  at      timestamptz not null default now(),
  actor   text not null,
  state   text not null,
  reason  text not null,
  detail  jsonb not null default '{}'::jsonb
);
alter table public.os_open_access_log drop constraint if exists os_open_access_log_state_ck;
alter table public.os_open_access_log add constraint os_open_access_log_state_ck
  check (state in ('open','closed')) not valid;
alter table public.os_open_access_log validate constraint os_open_access_log_state_ck;

-- Newest row wins. Absent any row it is CLOSED, so a fresh database is never accidentally open.
create or replace function public.fn_os_open_access()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select coalesce((select state = 'open' from public.os_open_access_log order by id desc limit 1), false);
$$;
revoke all on function public.fn_os_open_access() from public;
grant execute on function public.fn_os_open_access() to service_role, anon, authenticated;

insert into public.os_open_access_log (actor, state, reason, detail) values (
  'management@quotesdone.com', 'open',
  'Founder instruction, 15 Aug 2026: leave the OS open until the build is finished. Pre-launch, '
  || 'nobody knows the company, 0 customers and 0 transactions behind the screen. Supabase RLS and '
  || 'GitHub privacy are explicitly unchanged. Every open-door request is audited under a named '
  || 'build identity. Close with a state=closed row when he says "activate the credentials".',
  jsonb_build_object(
    'customers', 0, 'transactions', 0, 'leads', 20465, 'employees', 90,
    'exposure', '20,465 scraped business lead records; no consumer or payment data',
    'unchanged', jsonb_build_array('supabase RLS', 'github private',
                                   'x-os-key preview key remains read-only'),
    'audited_as', 'build-mode (no authentication)',
    'close_with', 'insert into public.os_open_access_log (actor, state, reason) values (…, ''closed'', …)')
);

-- The build identity, named so the audit trail never pretends to be him. A command issued through
-- the open door is attributable to build mode and to nothing else.
insert into public.phase_c_founder_identity (identity, kind, active, note) values
  ('build-mode@quotesdone.local', 'build_mode', true,
   'Not a person. The identity os_api presents while fn_os_open_access() is true, so the Command '
   || 'Center works without a sign-in during the build. Delete this row when credentials are activated.')
on conflict (identity) do update set active = true, note = excluded.note;
