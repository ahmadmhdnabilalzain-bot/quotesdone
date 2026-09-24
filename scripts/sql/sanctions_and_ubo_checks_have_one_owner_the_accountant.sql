-- SANCTIONS AND UBO CHECKS HAVE ONE OWNER: THE ACCOUNTANT.
--
-- Assigned: accountant. Ledger 983 (24 Sep 2026): Accountant gap 5 ("the first screen at onboarding is owned
-- by sales_engineer, the re-screen by the accountant; the ownership should be one seat") and founder_
-- instruction 898 ("ongoing sanctions/UBO checks" -- the audit found no UBO routine at all).
--
-- WHAT WAS MEASURED (24 Sep 2026, production, read-only):
--   * function_owner('sanctions_screen') = sales_engineer. seat_duty accountant.sanctions_rescreen (daily) and
--     the finding for a stale list are the accountant's. Two seats owned one control.
--   * There is no UBO register. The person the estate holds as a supplier's owner is leads.signatory_name,
--     which fn_supplier_sanctions_screen already screens (field 'owner'). Nothing checks that a registered
--     supplier HAS one, and nothing notices when it changes.
--
-- WHAT THIS CHANGES
--   1. function_owner('sanctions_screen') -> accountant. The accountant is "in the picture for anything to do
--      with money" (seat map, 24 Sep 2026) and a sanctioned counterparty is money risk. What a hit does is
--      unchanged: the CEO decides, the sales engineer holds the supplier's outreach (that hold is supplier work,
--      so it stays on the sales engineer).
--   2. accountant.ubo_watch (daily, fn_accountant_ubo_watch_tick):
--        - every registered or approved supplier with NO owner name is a finding handed to the sales engineer
--          (collecting it is supplier-facing work), because a supplier with no owner cannot be screened;
--        - a CHANGED owner name is recorded in accountant_ubo_seen (normalised with the screen's own
--          fn_screening_normalise, equality only) and returned, and the next daily re-screen screens it.
--      A fixture run (set local qd.duty_fixtures = 'on') selects ONLY 'ZZ DEMO — ' suppliers.
--
-- NOT DONE HERE: a UBO capture field on the registration form (the sales engineer's portal). Until one exists
-- the signatory is the owner of record, and this says so in every finding.
--
-- prevented by: scripts/checks/accountant_duties_are_wired.test.mjs

update public.function_owner
   set owner = 'accountant', recorded_at = now(),
       note = 'Downloads the UN consolidated list and the UAE local terrorist list weekly and hands the run ids to '
           || 'fn_supplier_sanctions_screen. Owned by the accountant with the daily re-screen and the UBO watch '
           || '(ledger 983, 24 Sep 2026: one seat owns sanctions). A hit is decided by the CEO; the sales engineer holds the supplier.'
 where function_slug = 'sanctions_screen';

create table if not exists public.accountant_ubo_seen (
  lead_id bigint primary key,
  owner_name text not null,
  owner_norm text not null,
  first_seen_at timestamptz not null default now(),
  changed_at timestamptz,
  previous_owner_name text
);
comment on table public.accountant_ubo_seen is
  'The owner (leads.signatory_name) the accountant last saw for each registered supplier, so a change of owner is noticed. Written by fn_accountant_ubo_watch_tick.';
alter table public.accountant_ubo_seen enable row level security;
drop policy if exists accountant_ubo_seen_service_role_only on public.accountant_ubo_seen;
create policy accountant_ubo_seen_service_role_only on public.accountant_ubo_seen
  as permissive for all to public using (false) with check (false);
revoke all on public.accountant_ubo_seen from anon, authenticated;

create or replace function public.fn_accountant_ubo_watch_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_none jsonb; v_none_n int; v_changed jsonb := '[]'::jsonb; v_new int := 0; r record; v_items jsonb := '[]'::jsonb;
begin
  create temp table tmp_ubo on commit drop as
    select l.id, l.company_name, nullif(btrim(coalesce(l.signatory_name, '')), '') as owner_name
      from public.leads l
     where (l.lifecycle_stage = 'registered' or l.approval_status = 'approved')
       and not coalesce(l.banned, false)
       and case when v_fx then l.company_name like 'ZZ DEMO — %'
                else coalesce(l.company_name, '') not like 'ZZ DEMO — %' and coalesce(l.email, '') not ilike '%@example.invalid' end;

  select coalesce(jsonb_agg(jsonb_build_object('lead_id', id, 'company', company_name) order by id), '[]'::jsonb), count(*)
    into v_none, v_none_n from tmp_ubo where owner_name is null;
  if v_none_n > 0 then
    v_items := v_items || jsonb_build_object('item', 'owner_unknown' || case when v_fx then '_demo' else '' end,
      'owner_seat', 'sales_engineer', 'subject', 'leads.signatory_name', 'demo', v_fx,
      'title', v_none_n || ' registered supplier(s) name no owner, so their owner cannot be sanctions-screened',
      'affected', v_none_n,
      'evidence', jsonb_build_object('suppliers', v_none,
        'act', 'ask each supplier for the name of its owner or authorised signatory as the trade licence shows it and record it in leads.signatory_name',
        'basis', 'there is no UBO register yet: the signatory is the owner of record and the one the sanctions screen reads'));
  end if;

  for r in select t.id, t.owner_name, public.fn_screening_normalise(t.owner_name) as norm, s.owner_norm as seen_norm, s.owner_name as seen_name
             from tmp_ubo t left join public.accountant_ubo_seen s on s.lead_id = t.id
            where t.owner_name is not null loop
    if r.seen_norm is null then
      insert into public.accountant_ubo_seen (lead_id, owner_name, owner_norm) values (r.id, r.owner_name, r.norm);
      v_new := v_new + 1;
    elsif r.seen_norm is distinct from r.norm then
      update public.accountant_ubo_seen
         set previous_owner_name = owner_name, owner_name = r.owner_name, owner_norm = r.norm, changed_at = now()
       where lead_id = r.id;
      v_changed := v_changed || jsonb_build_object('lead_id', r.id, 'from', r.seen_name, 'to', r.owner_name);
    end if;
  end loop;
  drop table if exists tmp_ubo;

  return jsonb_build_object('suppliers_without_owner', v_none_n, 'owners_first_seen', v_new, 'owners_changed', v_changed,
    'rescreened_by', 'accountant.sanctions_rescreen (daily) screens every current owner name',
    'findings', public.fn_accountant_duty_settle('ubo' || case when v_fx then '_demo' else '' end, v_items));
end $fn$;
revoke execute on function public.fn_accountant_ubo_watch_tick() from public, anon, authenticated;
grant execute on function public.fn_accountant_ubo_watch_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('accountant.ubo_watch', 'accountant', interval '1 day', 'fn_accountant_ubo_watch_tick',
   'every registered supplier names an owner the sanctions screen can read; a missing owner goes to the sales engineer, a changed owner is recorded and re-screened',
   'scripts/sql/sanctions_and_ubo_checks_have_one_owner_the_accountant.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- PROBE (verdict row). The tick writes accountant_ubo_seen and findings, so it is not run here.
select case when (select owner from public.function_owner where function_slug = 'sanctions_screen') is distinct from 'accountant'
              then 'PROBE FAILED: sanctions_screen is not owned by the accountant'
            when to_regprocedure('public.fn_accountant_ubo_watch_tick()') is null then 'PROBE FAILED: routine missing'
            else 'PROBE OK' end as verdict;
