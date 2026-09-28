-- accountant: a demo supplier is never an owner_unknown finding (28 Sep 2026).
--
-- MEASURED. Handoff 98486 (issue acct:ubo:owner_unknown, incident 471) named ONE supplier: lead 133960
-- "ZZ DEMO holds probe 0b04d2d2", a probe fixture since deleted. fn_accountant_ubo_watch_tick excluded
-- demo rows by a private literal (the 'ZZ DEMO' prefix followed by an em dash) and an @example.invalid
-- email. The probe name has no em dash, so it was counted as a real registered supplier with no owner.
--
-- FIX. Reuse the estate's one demo rule, the generated column leads.is_demo (fn_is_demo_email, fn_is_demo_phone,
-- the qd_demo tag, company_name ILIKE 'ZZ DEMO%', 'QD Demo ', demo sources) instead of a private copy of it.
-- Fixture mode (qd.duty_fixtures = on) reads the same column, so it sees exactly the rows real mode skips.
-- Only the tmp_ubo filter changes; the rest of the body is the one in
-- sanctions_and_ubo_checks_have_one_owner_the_accountant.sql.
--
-- CREATE OR REPLACE keeps the ACL; the revoke below is idempotent and restates it.
-- prevented by: scripts/checks/the_ubo_watch_uses_the_leads_demo_column.test.mjs

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
       and coalesce(l.is_demo, false) = v_fx;

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

-- PROBE (verdict row). The tick writes accountant_ubo_seen and findings, so it is not run here.
select case when to_regprocedure('public.fn_accountant_ubo_watch_tick()') is null then 'PROBE FAILED: routine missing'
            when pg_get_functiondef('public.fn_accountant_ubo_watch_tick()'::regprocedure) not like '%l.is_demo%'
              then 'PROBE FAILED: the watch does not read leads.is_demo'
            else 'PROBE OK' end as verdict;
