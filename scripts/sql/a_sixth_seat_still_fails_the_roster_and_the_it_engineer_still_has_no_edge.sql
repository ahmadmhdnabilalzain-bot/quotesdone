-- POSITIVE CONTROL + FOUR NEGATIVE CASES, ALL INSIDE A TRANSACTION THAT ENDS IN A RAISE.
--
-- THE QUESTION THIS ANSWERS. The roster in scripts/checks/support_acceptance_group_org_and_channels.mjs
-- was widened from four names to five on 9 Sep 2026 to admit the IT engineer. A roster that has been
-- widened once looks exactly like a roster that has been loosened, and the only way to tell them
-- apart is to try to get a SIXTH seat past it. This file tries, four different ways, and it also
-- tries to edge the IT engineer under the CEO -- the silent reorganisation that every_edge_reports_to
-- _the_ceo would NOT catch on its own, because an edge to the ceo is exactly what it is looking for.
--
-- IT COMMITS NOTHING. Every case runs inside its own PL/pgSQL subtransaction and is rolled back by
-- raising inside it, and the whole block ends in `raise exception` so the transaction dies with the
-- numbers in the message. No row survives, and the numbers still come out.
--
-- THE POSITIVE CONTROL IS TAKEN FIRST AND IS NOT OPTIONAL: if the roster instruments do not read
-- their PASSING values before anything is inserted, then a "fail" afterwards proves nothing -- it
-- could be a broken query rather than a caught seat. Zero cannot tell a dead guard from an idle
-- system, and neither can a fail.
--
--   node scripts/qsql.mjs scripts/sql/a_sixth_seat_still_fails_the_roster_and_the_it_engineer_still_has_no_edge.sql
--
-- READ-ONLY BY CONSTRUCTION. This file is never applied with apply_sql; it is a probe, run through
-- the read path, and it aborts itself.

do $probe$
declare
  -- the four instruments the acceptance check reads
  v_names text; v_off int; v_bad int; v_it boolean;
  -- control
  c_names text; c_off int; c_bad int; c_it boolean;
  -- case A: a sixth seat inserted ACTIVE and never edged
  a_names text; a_off int; a_bad int;
  -- case B: a sixth seat inserted RETIRED and never edged -- the one a roster of active names misses
  b_names text; b_off int; b_bad int;
  -- case C: a sixth seat inserted ACTIVE and edged to the ceo
  c2_names text; c2_off int; c2_bad int;
  -- case D: the IT ENGINEER edged under the ceo -- a well-formed edge, and still a reorganisation
  d_bad int; d_it boolean; d_names text; d_off int;
begin
  -- ── 0. POSITIVE CONTROL ────────────────────────────────────────────────────────────────────
  select string_agg(role_id, ',' order by role_id) into c_names from public.org_role where status='active';
  select count(*) into c_off from public.org_role
   where role_id not in ('accountant','ceo','customer_support','it_engineer','sales_engineer');
  select (select count(*) from public.org_reporting_edge
           where parent_role_id <> 'ceo'
              or child_role_id not in ('accountant','customer_support','sales_engineer'))
       + (select count(*) - count(distinct child_role_id) from public.org_reporting_edge)
    into c_bad;
  select (count(*) = 0) into c_it from public.org_reporting_edge where child_role_id='it_engineer';
  c_it := c_it and ('founder' = any(coalesce((select escalation_targets from public.org_role where role_id='it_engineer'), array[]::text[])));

  if c_names is distinct from 'accountant,ceo,customer_support,it_engineer,sales_engineer'
     or c_off <> 0 or c_bad <> 0 or c_it is distinct from true then
    raise exception 'POSITIVE CONTROL FAILED -- the roster does not read its passing values before anything was inserted, so nothing below would prove anything. names=% off=% bad=% it_founder=%',
      c_names, c_off, c_bad, c_it;
  end if;

  -- ── A. A SIXTH SEAT, ACTIVE, NEVER EDGED ───────────────────────────────────────────────────
  -- A PL/pgSQL BEGIN...EXCEPTION block IS a subtransaction: raising inside it rolls the block's
  -- writes back while the variables it assigned survive. `rollback to savepoint` is not valid inside
  -- PL/pgSQL, so this is how one case is undone without ending the transaction.
  begin
  insert into public.org_role (role_id, display_name, runtime_mode, authority_level,
                               responsibilities, activation_conditions, status)
  values ('zz_demo_seat','ZZ DEMO Seat','on_demand_specialist','advisory',
          'ZZ DEMO -- a seat the founder never authorised.','ZZ DEMO probe.','active');
  select string_agg(role_id, ',' order by role_id) into a_names from public.org_role where status='active';
  select count(*) into a_off from public.org_role
   where role_id not in ('accountant','ceo','customer_support','it_engineer','sales_engineer');
  select (select count(*) from public.org_reporting_edge
           where parent_role_id <> 'ceo'
              or child_role_id not in ('accountant','customer_support','sales_engineer'))
       + (select count(*) - count(distinct child_role_id) from public.org_reporting_edge)
    into a_bad;
    raise exception 'ZZ_DEMO_ROLLBACK';
  exception when others then
    if sqlerrm <> 'ZZ_DEMO_ROLLBACK' then raise; end if;
  end;

  -- ── B. A SIXTH SEAT, RETIRED, NEVER EDGED ──────────────────────────────────────────────────
  -- The one a roster of ACTIVE names cannot see. It must be caught by the off-roster count alone.
  -- A PL/pgSQL BEGIN...EXCEPTION block IS a subtransaction: raising inside it rolls the block's
  -- writes back while the variables it assigned survive. `rollback to savepoint` is not valid inside
  -- PL/pgSQL, so this is how one case is undone without ending the transaction.
  begin
  insert into public.org_role (role_id, display_name, runtime_mode, authority_level,
                               responsibilities, activation_conditions, status)
  values ('zz_demo_seat','ZZ DEMO Seat','on_demand_specialist','advisory',
          'ZZ DEMO -- parked out of sight.','ZZ DEMO probe.','retired');
  select string_agg(role_id, ',' order by role_id) into b_names from public.org_role where status='active';
  select count(*) into b_off from public.org_role
   where role_id not in ('accountant','ceo','customer_support','it_engineer','sales_engineer');
  select (select count(*) from public.org_reporting_edge
           where parent_role_id <> 'ceo'
              or child_role_id not in ('accountant','customer_support','sales_engineer'))
       + (select count(*) - count(distinct child_role_id) from public.org_reporting_edge)
    into b_bad;
    raise exception 'ZZ_DEMO_ROLLBACK';
  exception when others then
    if sqlerrm <> 'ZZ_DEMO_ROLLBACK' then raise; end if;
  end;

  -- ── C. A SIXTH SEAT, ACTIVE, EDGED TO THE CEO ──────────────────────────────────────────────
  -- A PL/pgSQL BEGIN...EXCEPTION block IS a subtransaction: raising inside it rolls the block's
  -- writes back while the variables it assigned survive. `rollback to savepoint` is not valid inside
  -- PL/pgSQL, so this is how one case is undone without ending the transaction.
  begin
  insert into public.org_role (role_id, display_name, runtime_mode, authority_level,
                               responsibilities, activation_conditions, status)
  values ('zz_demo_seat','ZZ DEMO Seat','on_demand_specialist','advisory',
          'ZZ DEMO -- edged in as if authorised.','ZZ DEMO probe.','active');
  insert into public.org_reporting_edge (child_role_id, parent_role_id, established_by, reason)
  values ('zz_demo_seat','ceo','probe','ZZ DEMO');
  select string_agg(role_id, ',' order by role_id) into c2_names from public.org_role where status='active';
  select count(*) into c2_off from public.org_role
   where role_id not in ('accountant','ceo','customer_support','it_engineer','sales_engineer');
  select (select count(*) from public.org_reporting_edge
           where parent_role_id <> 'ceo'
              or child_role_id not in ('accountant','customer_support','sales_engineer'))
       + (select count(*) - count(distinct child_role_id) from public.org_reporting_edge)
    into c2_bad;
    raise exception 'ZZ_DEMO_ROLLBACK';
  exception when others then
    if sqlerrm <> 'ZZ_DEMO_ROLLBACK' then raise; end if;
  end;

  -- ── D. THE IT ENGINEER, QUIETLY EDGED UNDER THE CEO ────────────────────────────────────────
  -- A perfectly well-formed edge: parent IS the ceo, no duplicate child. every_edge_reports_to_the
  -- _ceo counts children NOT on its authorised list, so this DOES move it -- and if that list were
  -- ever widened to admit it_engineer "for tidiness", only the named exception scenario would be
  -- left standing. Both are measured here so the difference is on the record.
  -- A PL/pgSQL BEGIN...EXCEPTION block IS a subtransaction: raising inside it rolls the block's
  -- writes back while the variables it assigned survive. `rollback to savepoint` is not valid inside
  -- PL/pgSQL, so this is how one case is undone without ending the transaction.
  begin
  insert into public.org_reporting_edge (child_role_id, parent_role_id, established_by, reason)
  values ('it_engineer','ceo','probe','ZZ DEMO -- a silent reorganisation');
  select (select count(*) from public.org_reporting_edge
           where parent_role_id <> 'ceo'
              or child_role_id not in ('accountant','customer_support','sales_engineer'))
       + (select count(*) - count(distinct child_role_id) from public.org_reporting_edge)
    into d_bad;
  select (count(*) = 0) into d_it from public.org_reporting_edge where child_role_id='it_engineer';
  d_it := d_it and ('founder' = any(coalesce((select escalation_targets from public.org_role where role_id='it_engineer'), array[]::text[])));
  select string_agg(role_id, ',' order by role_id) into d_names from public.org_role where status='active';
  select count(*) into d_off from public.org_role
   where role_id not in ('accountant','ceo','customer_support','it_engineer','sales_engineer');
    raise exception 'ZZ_DEMO_ROLLBACK';
  exception when others then
    if sqlerrm <> 'ZZ_DEMO_ROLLBACK' then raise; end if;
  end;

  raise exception E'PROBE<<\ncontrol  names=%  off_roster=%  bad_edges=%  it_reports_to_founder=%\nA active  names=%  off_roster=%  bad_edges=%\nB retired names=%  off_roster=%  bad_edges=%\nC edged   names=%  off_roster=%  bad_edges=%\nD it_edged names=% off_roster=%  bad_edges=%  it_reports_to_founder=%\n>>',
    c_names, c_off, c_bad, c_it,
    a_names, a_off, a_bad,
    b_names, b_off, b_bad,
    c2_names, c2_off, c2_bad,
    d_names, d_off, d_bad, d_it;
end
$probe$;
