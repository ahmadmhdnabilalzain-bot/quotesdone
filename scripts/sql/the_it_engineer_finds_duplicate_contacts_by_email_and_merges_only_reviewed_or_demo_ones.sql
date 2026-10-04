-- CONTACT DEDUPLICATION ACROSS LEADS AND CUSTOMERS (it_engineer, 5 Oct 2026, backlog T4).
-- Assigned: it_engineer (owns it_engineer.data_quality; this is its contact_dedup duty).
--
-- Measured 5 Oct 2026 before writing: no routine or table grouped duplicate contacts.
-- accountant.fraud_watch writes duplicate-ACCOUNT fraud flags - a fraud signal, not a merge.
-- Unique indexes already stop the exact case inside one table (customers_email_lower_uidx on
-- lower(btrim(email)), uq_leads_email_lower on lower(email), leads_claimed_by_lower_uidx), so a
-- duplicate here is one of: a scraped lead whose email is the login (claimed_by) of another lead
-- (the supplier registered fresh instead of claiming), a whitespace variant that lower(email) alone
-- lets through, or the same mailbox as both a customer and a supplier. Live count that day: 0 groups.
--
-- RULES
--   * EMAIL IS THE IDENTITY: the key is lower(btrim(email)) over leads.email, leads.claimed_by and
--     customers.email. A phone may CONFIRM a group already joined by email (phone_confirms) but never
--     forms one - UAE numbers are shared (memory: a-phone-may-confirm-never-select).
--   * The daily duty REPORTS every group into contact_duplicate_group, MERGES only all-demo groups of
--     one kind, and hands every real group to sales_engineer (owns customers and suppliers) through
--     fn_it_duty_settle. The founder is never in the loop.
--   * A real merge is fn_contact_merge(group, reviewed_by_seat, reason): a live seat other than the
--     detector, a reason, an append-only audit row with before/after and every re-pointed FK.
--   * NOTHING IS DELETED. The loser keeps its row, marked merged_into/merged_at (a lead is also
--     matching_blocked). A customer and a supplier are different accounts and are never merged.
--   * FKs are enumerated from pg_constraint at merge time, so a table added later is re-pointed too.
--     A row the winner already has (a unique key would collide) stays on the loser and is recorded
--     as a conflict - the loser is not deleted, so nothing is lost.

alter table public.leads     add column if not exists merged_into bigint references public.leads(id);
alter table public.leads     add column if not exists merged_at timestamptz;
alter table public.customers add column if not exists merged_into uuid references public.customers(id);
alter table public.customers add column if not exists merged_at timestamptz;
comment on column public.leads.merged_into is 'Set by fn_contact_merge: this lead was a duplicate (same email identity) of that lead. Never deleted; read past it.';
comment on column public.customers.merged_into is 'Set by fn_contact_merge: this customer was a duplicate (same email identity) of that customer. Never deleted; read past it.';

create table if not exists public.contact_duplicate_group (
  id             uuid primary key default gen_random_uuid(),
  run_on         date not null default current_date,
  identity_key   text not null,                 -- lower(btrim(email)); the only thing that joins a group
  kinds          text[] not null,               -- {lead}, {customer} or {customer,lead}
  members        jsonb not null,                -- [{kind,id,via,is_demo}]
  member_count   int not null,
  phone_confirms boolean not null default false, -- a shared phone CONFIRMS; it never selected anyone
  all_demo       boolean not null,
  status         text not null default 'reported' check (status in ('reported', 'handed_to_seat', 'merged')),
  handed_to_seat text,
  merged_at      timestamptz,
  created_at     timestamptz not null default now(),
  unique (run_on, identity_key)
);
alter table public.contact_duplicate_group enable row level security;
drop policy if exists contact_duplicate_group_service_role_only on public.contact_duplicate_group;
create policy contact_duplicate_group_service_role_only on public.contact_duplicate_group as permissive for all to public using (false) with check (false);
revoke all on public.contact_duplicate_group from anon, authenticated;

create table if not exists public.contact_merge_audit (
  id               bigserial primary key,
  group_id         uuid not null references public.contact_duplicate_group(id),
  kind             text not null check (kind in ('lead', 'customer')),
  winner_id        text not null,
  loser_id         text not null,
  reviewed_by_seat text not null,
  reason           text not null,
  before_row       jsonb not null,
  after_row        jsonb not null,
  repointed        jsonb not null,               -- [{table,column,rows}|{table,column,conflict}]
  at               timestamptz not null default now()
);
alter table public.contact_merge_audit enable row level security;
drop policy if exists contact_merge_audit_service_role_only on public.contact_merge_audit;
create policy contact_merge_audit_service_role_only on public.contact_merge_audit as permissive for all to public using (false) with check (false);
revoke all on public.contact_merge_audit from anon, authenticated;

create or replace function public.fn_contact_merge_audit_is_append_only()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $fn$
begin
  raise exception 'contact_merge_audit is append-only: a merge record is never changed or removed';
end $fn$;
revoke execute on function public.fn_contact_merge_audit_is_append_only() from public, anon, authenticated;
drop trigger if exists contact_merge_audit_append_only on public.contact_merge_audit;
create trigger contact_merge_audit_append_only before update or delete on public.contact_merge_audit
  for each row execute function public.fn_contact_merge_audit_is_append_only();
drop trigger if exists contact_merge_audit_no_truncate on public.contact_merge_audit;
create trigger contact_merge_audit_no_truncate before truncate on public.contact_merge_audit
  for each statement execute function public.fn_contact_merge_audit_is_append_only();

-- The live members of one identity, recomputed (a report can be stale by the time a seat reviews it).
create or replace function public.fn_contact_identity_members(p_key text)
returns table (kind text, id text, via text, is_demo boolean, phone_key text, rank_key text)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with m as (
    select 'lead'::text kind, l.id::text id, v.via,
           -- every operand coalesced: a NULL here would make bool_and skip a real row and auto-merge it
           (coalesce(l.is_demo, false) or coalesce(l.company_name ilike 'ZZ DEMO%', false)
             or coalesce(l.company_name ilike 'QD Demo%', false) or coalesce(l.email ilike '%@example.invalid', false)
             or coalesce(l.claimed_by ilike '%@example.invalid', false)) is_demo,
           right(regexp_replace(coalesce(l.phone_e164, l.phone, ''), '\D', '', 'g'), 9) phone_key,
           -- winner: the claimed (registered) lead, then the verified one, then the oldest
           (case when coalesce(l.claimed, false) then '0' else '1' end) || (case when coalesce(l.verified, false) then '0' else '1' end)
             || lpad(l.id::text, 20, '0') rank_key
      from public.leads l
      cross join lateral (values ('email', l.email), ('claimed_by', l.claimed_by)) v(via, addr)
     where lower(btrim(v.addr)) = p_key and l.merged_into is null
    union all
    select 'customer', c.id::text, 'email',
           (coalesce(c.is_demo, false) or coalesce(c.full_name ilike 'ZZ DEMO%', false)
             or coalesce(c.email ilike '%@example.invalid', false)),
           right(regexp_replace(coalesce(c.phone, c.whatsapp_phone, ''), '\D', '', 'g'), 9),
           to_char(c.created_at, 'YYYYMMDDHH24MISSUS') || c.id::text
      from public.customers c
     where lower(btrim(c.email)) = p_key and c.merged_into is null
  )
  select distinct on (kind, id) kind, id, via, is_demo, phone_key, rank_key from m order by kind, id, via;
$fn$;
revoke execute on function public.fn_contact_identity_members(text) from public, anon, authenticated;

-- THE REVIEWED MERGE. A named live seat and a reason; never the detector on a real group; never a delete.
create or replace function public.fn_contact_merge(p_group uuid, p_reviewed_by_seat text, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare g public.contact_duplicate_group; v_kind text; v_tbl regclass; v_winner text; v_loser text;
        fk record; n int; v_rep jsonb; v_before jsonb; v_after jsonb; v_done jsonb := '[]'::jsonb; v_live_demo boolean;
begin
  if length(btrim(coalesce(p_reason, ''))) < 10 then
    raise exception 'fn_contact_merge: a reason of at least 10 characters is required';
  end if;
  if not exists (select 1 from public.org_role where role_id = p_reviewed_by_seat and status = 'active') then
    raise exception 'fn_contact_merge: % is not a live seat; a merge needs a named live reviewer', p_reviewed_by_seat;
  end if;
  select * into g from public.contact_duplicate_group where id = p_group for update;
  if not found then raise exception 'fn_contact_merge: no duplicate group %', p_group; end if;
  if g.status = 'merged' then raise exception 'fn_contact_merge: group % is already merged', p_group; end if;
  -- kinds and demo-ness are judged on the LIVE members, never on the stored report (it can be stale)
  select count(distinct m.kind), min(m.kind), coalesce(bool_and(m.is_demo), false)
    into n, v_kind, v_live_demo from public.fn_contact_identity_members(g.identity_key) m;
  if cardinality(g.kinds) <> 1 or n > 1 then
    raise exception 'fn_contact_merge: group % spans a customer and a supplier - different accounts, never merged', p_group;
  end if;
  if not v_live_demo and p_reviewed_by_seat = 'it_engineer' then
    raise exception 'fn_contact_merge: a real group is reviewed by its owning seat, not by the detector';
  end if;
  v_kind := coalesce(v_kind, g.kinds[1]);
  v_tbl := case v_kind when 'lead' then 'public.leads'::regclass else 'public.customers'::regclass end;

  select m.id into v_winner from public.fn_contact_identity_members(g.identity_key) m
   where m.kind = v_kind order by m.rank_key limit 1;
  if (select count(*) from public.fn_contact_identity_members(g.identity_key) m where m.kind = v_kind) < 2 then
    raise exception 'fn_contact_merge: group % no longer has two live % rows for its email', p_group, v_kind;
  end if;

  for v_loser in select m.id from public.fn_contact_identity_members(g.identity_key) m
                  where m.kind = v_kind and m.id <> v_winner order by m.rank_key loop
    execute format('select to_jsonb(t) from %s t where t.id::text = $1', v_tbl) into v_before using v_loser;
    v_rep := '[]'::jsonb;
    -- EVERY single-column FK that points at this table's id, read from the catalogue now.
    for fk in select c.conrelid::regclass tbl, a.attname col
                from pg_constraint c
                join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
                join pg_attribute r on r.attrelid = c.confrelid and r.attnum = c.confkey[1]
               where c.contype = 'f' and c.confrelid = v_tbl and cardinality(c.conkey) = 1 and r.attname = 'id'
               order by 1, 2 loop
      begin
        execute format('update %s set %I = %L where %I = %L', fk.tbl, fk.col, v_winner, fk.col, v_loser);
        get diagnostics n = row_count;
        if n > 0 then v_rep := v_rep || jsonb_build_object('table', fk.tbl::text, 'column', fk.col, 'rows', n); end if;
      exception when unique_violation or exclusion_violation then
        -- the winner already holds the equivalent row; the loser keeps its own (it is never deleted)
        v_rep := v_rep || jsonb_build_object('table', fk.tbl::text, 'column', fk.col, 'conflict', sqlerrm);
      end;
    end loop;

    if v_kind = 'lead' then
      update public.leads set merged_into = v_winner::bigint, merged_at = now(), matching_blocked = true,
             matching_block_reason = 'merged into lead #' || v_winner
       where id = v_loser::bigint;
    else
      update public.customers set merged_into = v_winner::uuid, merged_at = now() where id = v_loser::uuid;
    end if;
    execute format('select to_jsonb(t) from %s t where t.id::text = $1', v_tbl) into v_after using v_loser;

    insert into public.contact_merge_audit (group_id, kind, winner_id, loser_id, reviewed_by_seat, reason, before_row, after_row, repointed)
    values (g.id, v_kind, v_winner, v_loser, p_reviewed_by_seat, btrim(p_reason), v_before, v_after, v_rep);
    v_done := v_done || jsonb_build_object('loser', v_loser, 'repointed', v_rep);
  end loop;

  update public.contact_duplicate_group set status = 'merged', merged_at = now() where id = g.id;
  return jsonb_build_object('group', g.id, 'kind', v_kind, 'winner', v_winner, 'merged', v_done, 'reviewed_by', p_reviewed_by_seat);
end $fn$;
revoke execute on function public.fn_contact_merge(uuid, text, text) from public, anon, authenticated;

-- THE DAILY DUTY: report every group, merge demo ones, hand real ones to sales_engineer.
create or replace function public.fn_it_engineer_contact_dedup()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare g record; v_items jsonb := '[]'::jsonb; n_groups int := 0; n_demo int := 0; n_handed int := 0;
        v_merged boolean; v_err text;
begin
  for g in
    with ids as (
      select lower(btrim(l.email)) k from public.leads l where l.merged_into is null and btrim(coalesce(l.email, '')) <> ''
      union all select lower(btrim(l.claimed_by)) from public.leads l where l.merged_into is null and btrim(coalesce(l.claimed_by, '')) <> ''
      union all select lower(btrim(c.email)) from public.customers c where c.merged_into is null and btrim(coalesce(c.email, '')) <> ''
    ), keys as (select k from ids group by k having count(*) > 1)
    select k.k, array_agg(distinct m.kind order by m.kind) kinds,
           jsonb_agg(jsonb_build_object('kind', m.kind, 'id', m.id, 'via', m.via, 'is_demo', m.is_demo) order by m.kind, m.id) members,
           count(*)::int n, coalesce(bool_and(m.is_demo), false) all_demo,
           -- confirmation only: two members of an EMAIL group share a phone
           (count(m.phone_key) filter (where length(m.phone_key) >= 7)
             > count(distinct m.phone_key) filter (where length(m.phone_key) >= 7)) phone_confirms
      from keys k cross join lateral public.fn_contact_identity_members(k.k) m
     group by k.k having count(*) > 1
  loop
    n_groups := n_groups + 1;
    insert into public.contact_duplicate_group as d (identity_key, kinds, members, member_count, phone_confirms, all_demo)
    values (g.k, g.kinds, g.members, g.n, g.phone_confirms, g.all_demo)
    on conflict (run_on, identity_key) do update
      set kinds = excluded.kinds, members = excluded.members, member_count = excluded.member_count,
          phone_confirms = excluded.phone_confirms, all_demo = excluded.all_demo
      where d.status <> 'merged';

    v_merged := false; v_err := null;
    if g.all_demo and cardinality(g.kinds) = 1 then
      -- one failing group must not lose every other group's report: it falls through to the hand-off
      begin
        perform public.fn_contact_merge(d.id, 'it_engineer', 'demo fixture auto-merge by it_engineer.contact_dedup')
           from public.contact_duplicate_group d where d.run_on = current_date and d.identity_key = g.k and d.status <> 'merged';
        v_merged := true; n_demo := n_demo + 1;
      exception when others then v_err := sqlerrm;
      end;
    end if;
    if not v_merged then
      update public.contact_duplicate_group set status = 'handed_to_seat', handed_to_seat = 'sales_engineer'
       where run_on = current_date and identity_key = g.k and status = 'reported';
      n_handed := n_handed + 1;
      v_items := v_items || jsonb_build_object(
        'item', 'contact_duplicate:' || md5(g.k), 'owner_seat', 'sales_engineer', 'subject', 'contact_duplicate',
        'affected', g.n, 'blast', 'internal',
        'title', g.n || ' accounts share one email identity (' || array_to_string(g.kinds, ' + ') || ')'
                 || case when g.phone_confirms then ', phone confirms' else '' end
                 || ' - review and merge with fn_contact_merge, or leave',
        'evidence', jsonb_build_object('identity_md5', md5(g.k), 'members', g.members, 'kinds', g.kinds,
                                       'cross_kind', cardinality(g.kinds) > 1, 'auto_merge_error', v_err));
    end if;
  end loop;

  return jsonb_build_object('groups', n_groups, 'demo_merged', n_demo, 'handed_to_sales_engineer', n_handed,
                            'settled', public.fn_it_duty_settle('contact_dedup', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_contact_dedup() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, enabled)
values ('it_engineer.contact_dedup', 'it_engineer', '1 day', 'fn_it_engineer_contact_dedup',
        'Group leads and customers that share one email identity (phone only confirms); merge demo groups, hand real ones to sales_engineer for a reviewed fn_contact_merge. Nothing is deleted.',
        'scripts/sql/the_it_engineer_finds_duplicate_contacts_by_email_and_merges_only_reviewed_or_demo_ones.sql', true)
on conflict (duty) do update set routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file, every = excluded.every;
