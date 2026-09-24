-- THE ACCOUNTANT RE-SCREENS EVERY BENEFICIAL OWNER, NOT ONLY THE NAMES ON THE SUPPLIER'S OWN RECORD.
-- Seat: accountant (the CEO decides a hit, as for every sanctions hit). 24 Sep 2026, founder_instruction 898
-- ("ongoing UBO checks" among the 15 additional duties) and ledger 983 (every gap in the seat audit fixed).
-- Needs the_accountant_watches_for_fee_circumvention_and_rescreens_sanctions.sql (fn_accountant_sanctions_rescreen).
--
-- WHAT WAS MEASURED (24 Sep 2026, repository and schema mirror):
--   * accountant.sanctions_rescreen screens, daily, the names fn_supplier_sanctions_screen reads off public.leads:
--     company_name, name_corrected_from, signatory_name, contact_name and the e-mail domain. That file says it
--     plainly: "There is no UBO register." A supplier owned by a listed person who is not its signatory or its
--     contact was therefore never screened. The seat audit (GAPS.md, row 898) lists this as the one duty of the
--     fifteen with no routine.
--
-- WHAT THIS ADDS
--   1. public.supplier_beneficial_owner: one row per owner of a supplier (lead), with where the name came from
--      (the trade licence, the supplier's own declaration, or a registry) and when it was last verified. Written
--      only through fn_supplier_beneficial_owner_record (service_role), once per supplier and owner name.
--   2. accountant.ubo_rescreen (daily, fn_accountant_ubo_rescreen): every owner of a registered or approved
--      supplier is screened against the LATEST ok list per source with the SAME rule fn_supplier_sanctions_screen
--      uses for a person's name (normalised equality of at least 6 characters, or one name's tokens wholly inside
--      the other's with at least two tokens on each side). A match is a supplier_screening_hit on field
--      'beneficial_owner'. The routine then runs fn_accountant_sanctions_rescreen, whose screen turns every open
--      hit of those runs into the existing path: ONE decision task on the ceo and ONE outreach hold on the
--      sales_engineer. Nobody is removed automatically; fn_supplier_screening_decide is the CEO's.
--      It also reports, in its result, how many suppliers in scope have no owner on record and how many owner
--      records have not been verified for a year. That is a measurement, not an alarm: until capture exists every
--      registered supplier has none, and a daily finding saying so would be the noise ledger 642 removed.
--   A fixture run (set local qd.duty_fixtures = 'on') selects ONLY ZZ DEMO suppliers.
--
-- WHAT THIS DOES NOT DO: it does not capture owners at registration or read them off a licence (that is the
-- sales_engineer's onboarding and document reading); it does not fetch the lists; it bans nobody.

create table if not exists public.supplier_beneficial_owner (
  id           bigint generated always as identity primary key,
  lead_id      bigint not null references public.leads(id),
  full_name    text not null check (btrim(full_name) <> ''),
  nationality  text,
  share_pct    numeric check (share_pct is null or (share_pct > 0 and share_pct <= 100)),
  source       text not null check (source in ('trade_licence', 'supplier_declared', 'registry')),
  declared_at  timestamptz not null default now(),
  verified_at  timestamptz
);
create unique index if not exists supplier_beneficial_owner_once
  on public.supplier_beneficial_owner (lead_id, lower(btrim(full_name)));
comment on table public.supplier_beneficial_owner is
  'The beneficial owners of a supplier (lead). Screened daily by accountant.ubo_rescreen against the latest sanctions lists; a match follows the existing supplier_screening_hit path (CEO decides, sales_engineer holds outreach).';
alter table public.supplier_beneficial_owner enable row level security;
drop policy if exists supplier_beneficial_owner_service_role_only on public.supplier_beneficial_owner;
create policy supplier_beneficial_owner_service_role_only on public.supplier_beneficial_owner as permissive for all to public using (false) with check (false);
revoke all on public.supplier_beneficial_owner from anon, authenticated;

create or replace function public.fn_supplier_beneficial_owner_record(
  p_lead_id bigint, p_full_name text, p_source text, p_nationality text default null, p_share_pct numeric default null)
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint;
begin
  insert into public.supplier_beneficial_owner as o (lead_id, full_name, source, nationality, share_pct, verified_at)
  values (p_lead_id, btrim(p_full_name), p_source, nullif(btrim(p_nationality), ''), p_share_pct, now())
  on conflict (lead_id, lower(btrim(full_name))) do update
     set source = excluded.source, nationality = coalesce(excluded.nationality, o.nationality),
         share_pct = coalesce(excluded.share_pct, o.share_pct), verified_at = now()
  returning o.id into v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_supplier_beneficial_owner_record(bigint, text, text, text, numeric) from public, anon, authenticated;
grant execute on function public.fn_supplier_beneficial_owner_record(bigint, text, text, text, numeric) to service_role;

create or replace function public.fn_accountant_ubo_rescreen()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_runs bigint[]; v_owners int; v_new int := 0; v_missing int; v_stale int; v_screen jsonb; h record;
begin
  select array_agg(id order by id) into v_runs
    from (select distinct on (source) id from public.screening_run where status = 'ok'
           order by source, fetched_at desc, id desc) x;
  if v_runs is null then raise exception 'no sanctions list has ever been fetched successfully (screening_run has no ok row)'; end if;

  -- the suppliers in scope are exactly the ones fn_supplier_sanctions_screen screens (same demo split)
  create temp table if not exists tmp_ubo_scope (lead_id bigint primary key) on commit drop;
  truncate tmp_ubo_scope;
  insert into tmp_ubo_scope
  select l.id from public.leads l
   where (l.lifecycle_stage = 'registered' or l.approval_status = 'approved')
     and case when v_fx then l.company_name like 'ZZ DEMO — %'
              else coalesce(l.company_name, '') not like 'ZZ DEMO — %' and coalesce(l.email, '') not ilike '%@example.invalid' end;

  select count(*) into v_owners from public.supplier_beneficial_owner o join tmp_ubo_scope s on s.lead_id = o.lead_id;

  for h in
    select o.lead_id, o.full_name, e.id as entry_id, e.run_id, e.name, e.source, coalesce(e.reference, '') as reference, e.entry_type,
           case when x.norm = e.name_norm then 'exact' else 'token_overlap' end as kind,
           case when x.norm = e.name_norm then 1.0
                else round(least(cardinality(x.toks), cardinality(e.tokens))::numeric / greatest(cardinality(x.toks), cardinality(e.tokens), 1), 2) end as score
      from public.supplier_beneficial_owner o
      join tmp_ubo_scope s on s.lead_id = o.lead_id
      cross join lateral (select public.fn_screening_normalise(o.full_name) as norm, public.fn_screening_tokens(o.full_name) as toks) x
      join public.screening_entry e
        on e.run_id = any(v_runs)
       and ((x.norm = e.name_norm and length(x.norm) >= 6)
         or (cardinality(x.toks) >= 2 and cardinality(e.tokens) >= 2 and (x.toks <@ e.tokens or e.tokens <@ x.toks)))
  loop
    insert into public.supplier_screening_hit (run_id, lead_id, field, supplier_value, entry_id, entry_name, entry_source, entry_reference, entry_type, match_kind, score)
    values (h.run_id, h.lead_id, 'beneficial_owner', h.full_name, h.entry_id, h.name, h.source, h.reference, h.entry_type, h.kind, h.score)
    on conflict (lead_id, entry_source, entry_reference, field) do nothing;
    if found then v_new := v_new + 1; end if;
  end loop;

  -- the existing screen files the CEO decision and the sales_engineer hold for every open hit of these runs
  v_screen := public.fn_accountant_sanctions_rescreen();

  select count(*) filter (where not exists (select 1 from public.supplier_beneficial_owner o where o.lead_id = s.lead_id)),
         count(*) filter (where exists (select 1 from public.supplier_beneficial_owner o where o.lead_id = s.lead_id
                                          and coalesce(o.verified_at, o.declared_at) < now() - interval '365 days'))
    into v_missing, v_stale from tmp_ubo_scope s;

  return jsonb_build_object('owners_screened', v_owners, 'owner_hits_new', v_new,
    'suppliers_without_owner_on_record', v_missing, 'suppliers_with_owner_unverified_a_year', v_stale,
    'screen', v_screen - 'sources' - 'runs' - 'oldest_list');
end $fn$;
revoke execute on function public.fn_accountant_ubo_rescreen() from public, anon, authenticated;
grant execute on function public.fn_accountant_ubo_rescreen() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('accountant.ubo_rescreen', 'accountant', interval '1 day', 'fn_accountant_ubo_rescreen',
   'every beneficial owner of a registered or approved supplier re-screened against the latest sanctions lists; a match goes to the CEO',
   'scripts/sql/the_accountant_rescreens_every_beneficial_owner.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
