-- THE FOUNDER HAS A TRACKED LINK FOR EACH SUPPLIER HE KNOWS.
--
-- Assigned: marketing (the links and the reading), sales_engineer (the sign-up they lead to).
-- Agent: marketing founder-network kit, 19 Nov 2026. Founder ledger 1709: he will message and call his own network of UAE
-- suppliers himself, from his own number (his estimate: 20 to 100 people), and the company supports him with a kit, tracking and
-- a smooth sign-up. Ledger 1184: the referral channel reads "ready" while nothing has been sent through it.
--
-- MEASURED BEFORE WRITING (19 Nov 2026, light SELECTs on production): supplier_referral_code 0 rows, supplier_referral 0 rows;
-- marketing_first_touch holds 1 row (utm_source invite, medium email); 3 real suppliers are approved, 3 have submitted a licence;
-- inquiries 0 rows ever, so no buyer has sent a request yet and nothing below says one has. ceo_supplier_channel.supplier_referral
-- reads 'ready' ("0 approved suppliers hold a referral link"). outreach_channel_policy.founder_direct_uae is 'open' (cap 20 a day).
--
-- WHY NOT THE SUPPLIER REFERRAL CODE. supplier_referral_code is keyed on an APPROVED supplier's lead (fn_supplier_referral_link
-- refuses anyone else), and its trigger credits that supplier. The founder is not a supplier, and what he needs to know is WHICH
-- of his contacts registered, so his links are his own: one code per contact, carried as the link's own tags
-- (utm_source=founder, utm_medium=personal, utm_campaign=founder-network, utm_content=<code>). The first-touch path already in place
-- (src/components/FirstTouch.tsx on every page -> supplier_api create_company / claim -> fn_marketing_first_touch_record) keeps any
-- tag of the shape ^[A-Za-z0-9._-]{1,100}$, so the registration brings the code with it and no new door is opened.
--
-- WHAT IS HERE
--   1. founder_network_link: one stable code per contact the founder names (a label he chooses, e.g. "Khalid - Gulf Steel").
--   2. fn_founder_network_links(text[]): mints (or returns the existing) code for each name and answers the English and Arabic
--      links. A session runs it when he sends a list of names; nothing here sends anything to anyone.
--   3. v_founder_network_signups: each link, and the company that registered through it (licence submitted, approval). A
--      registration with a founder tag whose code was never minted (he typed his own) is listed too, with no contact.
--   4. ERASE AND RETENTION (review of PR #2084): the label is a third party's name, and fn_pdpl_export_data / fn_pdpl_carry_out
--      find a person only by e-mail or phone, so they can never reach it. fn_founder_network_forget(code) deletes one row the
--      moment the founder says a person said no or asked to be removed. The duty marketing.founder_network_retention (daily,
--      fn_marketing_founder_network_retention) deletes a link nobody registered through 90 days after it was made, and replaces
--      the name on a registered link with 'lead <id>' after the same 90 days: by then the company speaks for itself.
--      BACKUPS: both act on the live table only. founder_network_link is in the daily export, so a copy already taken (the
--      bucket and Dropbox) keeps the name until fn_backup_prune_decide removes that copy: a daily copy after 30 days, a monthly
--      copy after 12 months. A forgotten name is gone from the live system at once and from backups as they age out, up to 12
--      months. The backup system is not changed here.
--
-- LIMIT, stated so nobody reads more into the view than it holds: first touch wins (src/lib/firstTouch.ts). A contact who had
-- already opened another tagged QuotesDone link in the same browser keeps that older touch; a contact in a private window keeps
-- none. Such a registration is still a registration; it is just not attributed here, and the founder will recognise the name.
--
-- prevented by: the_founder_has_a_tracked_link_for_each_supplier_he_knows_probe.sql (LOCAL Postgres 16, ZZ DEMO only).
-- Apply: node scripts/apply_sql.mjs scripts/sql/the_founder_has_a_tracked_link_for_each_supplier_he_knows.sql --apply --ddl
-- Rollback: delete from public.seat_duty where duty = 'marketing.founder_network_retention';
--           drop view public.v_founder_network_signups; drop function public.fn_founder_network_links(text[]);
--           drop function public.fn_founder_network_forget(text); drop function public.fn_marketing_founder_network_retention(integer);
--           drop table public.founder_network_link;  (no other object reads them)

set local lock_timeout = '3s';

-- ── 1. the links ───────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.founder_network_link (
  code        text primary key check (code ~ '^f[0-9a-f]{9}$'),
  contact     text not null check (length(btrim(contact)) between 1 and 120),
  contact_key text generated always as (lower(btrim(contact))) stored unique,
  is_demo     boolean generated always as (contact ilike 'ZZ DEMO%') stored,
  created_at  timestamptz not null default now()
);
comment on table public.founder_network_link is
  'One tracked sign-up link per supplier the founder contacts personally (ledger 1709). The code rides as utm_content with utm_source=founder; v_founder_network_signups reads who registered. Seat: marketing.';
alter table public.founder_network_link enable row level security;
drop policy if exists founder_network_link_service_role_only on public.founder_network_link;
create policy founder_network_link_service_role_only on public.founder_network_link
  as permissive for all to public using (false) with check (false);
revoke all on public.founder_network_link from anon, authenticated;
-- in the daily export with its subject (every_table_is_exported_or_explicitly_excluded.test.mjs): the founder's labels are the only
-- record of which person each code was given to
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('founder_network_link', true, 'marketing', 'Each tracked sign-up link the founder gave a supplier he knows personally (ledger 1709), and the name he gave it.', 'marketing')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- ── 2. minting them ────────────────────────────────────────────────────────────────────────────────────────────────────
-- SECURITY INVOKER (review of PR #2084): only service_role calls it, and service_role holds the table already.
create or replace function public.fn_founder_network_links(p_contacts text[])
 returns jsonb
 language plpgsql
 security invoker
 set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_name text; v_code text; v_try int; v_out jsonb := '[]'::jsonb;
  v_tags constant text := '?utm_source=founder&utm_medium=personal&utm_campaign=founder-network&utm_content=';
begin
  if p_contacts is null or cardinality(p_contacts) = 0 then
    return jsonb_build_object('ok', false, 'code', 'no_names', 'links', '[]'::jsonb);
  end if;
  if cardinality(p_contacts) > 200 then
    return jsonb_build_object('ok', false, 'code', 'too_many', 'why', 'At most 200 names in one call.');
  end if;
  foreach v_name in array p_contacts loop
    v_name := nullif(left(btrim(coalesce(v_name, '')), 120), '');
    continue when v_name is null;
    select code into v_code from public.founder_network_link where contact_key = lower(v_name);
    v_try := 0;
    while v_code is null and v_try < 5 loop
      v_try := v_try + 1;
      insert into public.founder_network_link (code, contact)
      values ('f' || substr(md5(gen_random_uuid()::text), 1, 9), v_name)
      on conflict do nothing
      returning code into v_code;
      if v_code is null then select code into v_code from public.founder_network_link where contact_key = lower(v_name); end if;
    end loop;
    if v_code is null then
      v_out := v_out || jsonb_build_object('contact', v_name, 'ok', false, 'code', 'unavailable');
    else
      v_out := v_out || jsonb_build_object('contact', v_name, 'ok', true, 'link_code', v_code,
        'en', 'https://quotesdone.com/en/supplier' || v_tags || v_code,
        'ar', 'https://quotesdone.com/ar/supplier' || v_tags || v_code);
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'links', v_out,
    'how', 'One link per person. Send each person his own link, in the language he reads; when his company registers through it, '
        || 'v_founder_network_signups shows it against his name.');
end $fn$;
revoke execute on function public.fn_founder_network_links(text[]) from public, anon, authenticated;
grant execute on function public.fn_founder_network_links(text[]) to service_role;

-- ── 3. who signed up through them ──────────────────────────────────────────────────────────────────────────────────────
create or replace view public.v_founder_network_signups with (security_invoker = true) as
  select f.contact, f.code as link_code, f.created_at as link_made_at, f.is_demo,
         t.lead_id, x.company_name, t.recorded_at as registered_at,
         x.registration_submitted_at as licence_submitted_at, x.approval_status, x.approved_at
    from public.founder_network_link f
    left join public.marketing_first_touch t on t.utm_source = 'founder' and t.utm_content = f.code
    left join public.leads x on x.id = t.lead_id
  union all
  select null, t.utm_content, null, coalesce(x.is_demo, false),
         t.lead_id, x.company_name, t.recorded_at,
         x.registration_submitted_at, x.approval_status, x.approved_at
    from public.marketing_first_touch t
    left join public.leads x on x.id = t.lead_id
   where t.utm_source = 'founder'
     and not exists (select 1 from public.founder_network_link f where f.code = t.utm_content);
comment on view public.v_founder_network_signups is
  'Each founder-network link and the company that registered through it; a founder-tagged registration with an unminted code has no contact. Read: select * from v_founder_network_signups where not is_demo order by registered_at desc nulls last, contact. Seat: marketing.';
revoke all on public.v_founder_network_signups from anon, authenticated;
grant select on public.v_founder_network_signups to service_role;

-- ── 4. erase and retention ─────────────────────────────────────────────────────────────────────────────────────────────
-- The person said no, or asked to be removed: his name and code go at once. A registration already made through the code is the
-- company's own record (marketing_first_touch, leads) and is not touched; the view then lists it with no contact.
create or replace function public.fn_founder_network_forget(p_code text)
 returns jsonb
 language plpgsql
 security invoker
 set search_path to 'public', 'pg_temp'
as $fn$
declare n int;
begin
  delete from public.founder_network_link where code = btrim(coalesce(p_code, ''));
  get diagnostics n = row_count;
  return jsonb_build_object('ok', n = 1, 'deleted', n,
    'code', case when n = 1 then 'forgotten' else 'no_such_code' end);
end $fn$;
revoke execute on function public.fn_founder_network_forget(text) from public, anon, authenticated;
grant execute on function public.fn_founder_network_forget(text) to service_role;

-- 90 days: a link nobody registered through is deleted; a registered one keeps its code and loses the name.
create or replace function public.fn_marketing_founder_network_retention(p_days integer default 90)
 returns jsonb
 language plpgsql
 security invoker
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_cut timestamptz := now() - make_interval(days => greatest(coalesce(p_days, 90), 1)); v_del int; v_anon int;
begin
  delete from public.founder_network_link f
   where f.created_at < v_cut
     and not exists (select 1 from public.marketing_first_touch t where t.utm_source = 'founder' and t.utm_content = f.code);
  get diagnostics v_del = row_count;
  -- a ZZ DEMO label stays marked demo, so is_demo keeps it out of every real count
  update public.founder_network_link f set contact = case when f.is_demo then 'ZZ DEMO lead ' else 'lead ' end || t.lead_id
    from public.marketing_first_touch t
   where t.utm_source = 'founder' and t.utm_content = f.code
     and f.created_at < v_cut and f.contact !~ '^(ZZ DEMO )?lead [0-9]+$';
  get diagnostics v_anon = row_count;
  return jsonb_build_object('ok', true, 'days', greatest(coalesce(p_days, 90), 1), 'deleted_unregistered', v_del, 'names_removed', v_anon,
    'left', (select count(*) from public.founder_network_link));
end $fn$;
revoke execute on function public.fn_marketing_founder_network_retention(integer) from public, anon, authenticated;
grant execute on function public.fn_marketing_founder_network_retention(integer) to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('marketing.founder_network_retention', 'marketing', interval '1 day', 'fn_marketing_founder_network_retention',
   'Deletes a founder-network link nobody registered through 90 days after it was made, and removes the name from a registered one after the same 90 days.',
   'scripts/sql/the_founder_has_a_tracked_link_for_each_supplier_he_knows.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
