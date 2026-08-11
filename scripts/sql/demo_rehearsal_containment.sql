-- =================================================================================================
-- OUTBOUND CONTAINMENT FOR THE DRESS REHEARSAL. BUILT BEFORE THE FIRST SEED ROW, NOT AFTER.
--
-- THE RISK, COUNTED:
--   leads with a real, unbanned email address                       19,903
--   SQL routines that INSERT INTO notifications                     45
--   of those, ones that fan out over matched leads                  enqueue_supplier_invites,
--                                                                   fn_notify_matched_supplier,
--                                                                   fn_notify_supplier,
--                                                                   run_no_quote_nudges
--
-- A rehearsal that triggers supplier matching can email twenty thousand real companies. All 45
-- producers write to ONE table, so one BEFORE INSERT trigger on that table is the whole choke point.
-- That is why this is a trigger and not 45 edits.
--
-- WHY IT HOLDS EVERYTHING, NOT JUST DEMO-DERIVED ROWS. The brief's rule was "any notification
-- arising from a demo entity whose recipient is not .invalid is held". Tracing "arising from" means
-- walking lead_id / inquiry_id / quote_id back to a demo row on every insert, and any path that does
-- not carry one of those ids escapes the trace. While the switch is on, EVERY recipient that is not
-- @example.invalid is held. That is a guarantee instead of a claim, and the cost is that the
-- founder's own mail is held for the duration and released afterwards with the function that already
-- exists for it. With 0 customers and 0 real claimed suppliers, he is the only real recipient there
-- is.
--
-- ZZZ_, NOT A00_. Postgres fires BEFORE triggers in NAME order, and trg_notifications_digest is
-- already a BEFORE INSERT trigger that rewrites NEW.status. A guard that runs first would have its
-- verdict overwritten. This one runs last on purpose, and it is the only trigger here that gets the
-- final word on status.
--
-- WHAT THIS DOES NOT COVER, STATED. Four edge functions call api.resend.com directly rather than
-- through notifications: kyc, login_otp, contact_submit, qa_suite. The trigger cannot see them.
-- They are contained by the second rule instead — every demo entity carries an @example.invalid
-- address (RFC 2606, guaranteed undeliverable), so a direct sender handed a demo recipient cannot
-- reach a real company. login_otp, contact_submit and qa_suite are not on any rehearsal path;
-- kyc is, and it emails the address on the lead it is processing, which for a demo lead is
-- .invalid. That is the boundary of this containment and it is written down rather than implied.
-- =================================================================================================

insert into public.decision_policy (key, value, description)
values ('demo_rehearsal_active', 'false'::jsonb,
        'While true, every notifications insert whose recipient is not @example.invalid is HELD '
        'rather than queued. Set true before seeding a ZZ DEMO rehearsal, false after teardown, '
        'then run fn_notifications_release_held() to let the real backlog go.')
on conflict (key) do update set description = excluded.description;

create or replace function public.zzz_fn_notifications_demo_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_on boolean;
begin
  select coalesce((d.value #>> '{}')::boolean, false) into v_on
    from public.decision_policy d where d.key = 'demo_rehearsal_active';
  if not coalesce(v_on, false) then return NEW; end if;

  -- RFC 2606 reserves .invalid as permanently undeliverable. Anything else, including NULL, is
  -- treated as possibly real and held. Failing closed is the whole point of this trigger.
  if coalesce(NEW.to_email, '') ~* '@example\.invalid$' then return NEW; end if;

  NEW.status := 'held';
  NEW.last_error := 'HELD by zzz_notifications_demo_guard: decision_policy.demo_rehearsal_active is '
                 || 'true and the recipient is not @example.invalid. Release with '
                 || 'fn_notifications_release_held() once the rehearsal is torn down.';
  return NEW;
exception when others then
  -- A guard that throws would block the insert entirely, which is a different outage. Hold and
  -- carry on: held is the safe verdict, and the reason travels with the row.
  NEW.status := 'held';
  NEW.last_error := 'HELD by zzz_notifications_demo_guard (guard itself errored: ' || sqlerrm || ')';
  return NEW;
end $function$;

-- CREATE grants EXECUTE to PUBLIC. CREATE OR REPLACE preserves the existing ACL, so this revoke is
-- a no-op on re-run and correct on first run.
revoke execute on function public.zzz_fn_notifications_demo_guard() from public;

drop trigger if exists zzz_notifications_demo_guard on public.notifications;
create trigger zzz_notifications_demo_guard
  before insert on public.notifications
  for each row execute function public.zzz_fn_notifications_demo_guard();

-- =================================================================================================
-- THE MARKER SCAN. One predicate, every text column in public, used for BOTH the before-picture and
-- the teardown proof. The convention is the one already in the data since 7 Aug 2026 —
-- 'ZZ DEMO — …' in a name and '@example.invalid' in an email — not a new registry table.
--
-- Dynamic over information_schema rather than a hand-written list of tables, because a hand-written
-- list is exactly how a teardown proof misses the table the rehearsal added.
-- =================================================================================================

create or replace function public.fn_demo_marker_scan()
returns table (rel text, col text, rows bigint)
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; n bigint;
begin
  for r in
    select c.table_name t, c.column_name k
      from information_schema.columns c
      join information_schema.tables tb
        on tb.table_schema = c.table_schema and tb.table_name = c.table_name
     where c.table_schema = 'public'
       and tb.table_type = 'BASE TABLE'
       and c.data_type in ('text','character varying','character')
     order by 1, 2
  loop
    begin
      execute format(
        'select count(*) from public.%I where %I ~* %L', r.t, r.k,
        'ZZ DEMO|example\.invalid|qd-demo') into n;
    exception when others then
      n := -1;   -- an unreadable column is reported, never silently counted as zero
    end;
    if n <> 0 then rel := r.t; col := r.k; rows := n; return next; end if;
  end loop;
end $function$;

revoke execute on function public.fn_demo_marker_scan() from public;

comment on function public.fn_demo_marker_scan() is
  'Every text column of every base table in public, matched against ZZ DEMO | example.invalid | '
  'qd-demo. Returns only non-zero counts; -1 means the column could not be read and is NOT a zero. '
  'BOUNDARY: this finds rows carrying one of those three markers in a TEXT column. A demo row '
  'created under another convention, or marked only in a numeric or jsonb column, does not appear. '
  'It is evidence about this convention, not proof that nothing else in the database is synthetic.';
