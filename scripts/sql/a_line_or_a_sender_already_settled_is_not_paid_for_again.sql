-- A LINE OR A SENDER ALREADY SETTLED IS NOT PAID FOR AGAIN.
--
-- Assigned: it_engineer. 24 Sep 2026, before the OpenRouter top-up of 25 Sep: routine work is code, the model only
-- for real judgement. Founder rule 890 (no word matching to infer meaning) holds: every lookup here is EXACT
-- (a sha-256 key, a whole email address), never a word or a domain.
--
-- MEASURED (inventory 24 Sep 2026): quote.line_specs is the largest paid surface (178 rows / 24 h, ~AED 15/day);
-- accountant.document_kind + receipt_vendor pay 2-4 think() calls per receipt, email_triage one per mail, the
-- competitor watch one per page (~AED 0.2/day together). What this file adds:
--   1. public.line_spec_reading: sha-256 of a quote line's text + the checklist codes it was asked -> what was
--      settled for it. _shared/line_specs/reasoned_specs.ts reasonLineSpecs reuses it, so a re-sent unchanged line
--      is not reasoned twice (it also settles by SHAPE, in TypeScript, the specs whose label names a unit).
--   2. public.expense_sender_reading: the exact address that issued an expense document -> the kind and vendor the
--      reasoning last gave, and how many times running it gave that same answer. _shared/reasoned_books.ts reuses a
--      kind / vendor only at >= 2 identical answers running (a different answer resets the count to 1).
-- Not here, already in force: the competitor watch hashes each page (fn_competitor_scan_ingest, md5 of the
-- normalised text, the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql) and reasons only a changed
-- page; email_triage's exact-sender spam route reads public.inbound_messages directly.
--
-- New tables: RLS on, deny-all policy, nothing for anon/authenticated. New functions: SECURITY DEFINER, pinned
-- search_path, EXECUTE revoked from public/anon/authenticated by exact signature, granted to service_role.

create table if not exists public.line_spec_reading (
  reading_key text primary key check (reading_key ~ '^[0-9a-f]{64}$'),
  found jsonb not null default '{}'::jsonb check (jsonb_typeof(found) = 'object'),
  created_at timestamptz not null default now()
);
alter table public.line_spec_reading enable row level security;
drop policy if exists line_spec_reading_service_role_only on public.line_spec_reading;
create policy line_spec_reading_service_role_only on public.line_spec_reading as permissive for all to public using (false) with check (false);
revoke all on public.line_spec_reading from anon, authenticated;

create table if not exists public.expense_sender_reading (
  sender text primary key check (sender = lower(sender) and sender ~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$'),
  kind text,
  kind_times integer not null default 0,
  vendor text,
  vendor_times integer not null default 0,
  last_email_id text,
  updated_at timestamptz not null default now()
);
alter table public.expense_sender_reading enable row level security;
drop policy if exists expense_sender_reading_service_role_only on public.expense_sender_reading;
create policy expense_sender_reading_service_role_only on public.expense_sender_reading as permissive for all to public using (false) with check (false);
revoke all on public.expense_sender_reading from anon, authenticated;

-- { reading_key: found } for the keys held.
create or replace function public.fn_line_spec_reading_get(p_keys text[])
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select coalesce(jsonb_object_agg(reading_key, found), '{}'::jsonb) from public.line_spec_reading where reading_key = any (p_keys);
$$;
revoke execute on function public.fn_line_spec_reading_get(text[]) from public, anon, authenticated;
grant execute on function public.fn_line_spec_reading_get(text[]) to service_role;

-- p_rows: [{ key, found }]. A key already held keeps its first reading (that same text was already settled).
create or replace function public.fn_line_spec_reading_put(p_rows jsonb)
returns integer language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare n integer;
begin
  insert into public.line_spec_reading (reading_key, found)
  select r->>'key', coalesce(r->'found', '{}'::jsonb) from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
   where r->>'key' ~ '^[0-9a-f]{64}$' and jsonb_typeof(coalesce(r->'found', '{}'::jsonb)) = 'object'
  on conflict (reading_key) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.fn_line_spec_reading_put(jsonb) from public, anon, authenticated;
grant execute on function public.fn_line_spec_reading_put(jsonb) to service_role;

create or replace function public.fn_expense_sender_reading(p_sender text)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select to_jsonb(r) - 'sender' from public.expense_sender_reading r where r.sender = lower(btrim(p_sender));
$$;
revoke execute on function public.fn_expense_sender_reading(text) from public, anon, authenticated;
grant execute on function public.fn_expense_sender_reading(text) to service_role;

-- The same answer again counts up; a different answer starts again at 1. A null leaves that half untouched.
create or replace function public.fn_expense_sender_learn(p_sender text, p_kind text, p_vendor text, p_email_id text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare v_sender text := lower(btrim(p_sender)); r public.expense_sender_reading;
begin
  if v_sender is null or v_sender !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' then
    return jsonb_build_object('learned', false, 'why', 'not an address');
  end if;
  insert into public.expense_sender_reading as e (sender, kind, kind_times, vendor, vendor_times, last_email_id)
  values (v_sender, p_kind, case when p_kind is null then 0 else 1 end, p_vendor, case when p_vendor is null then 0 else 1 end, p_email_id)
  on conflict (sender) do update set
    kind = coalesce(excluded.kind, e.kind),
    kind_times = case when excluded.kind is null then e.kind_times when excluded.kind = e.kind then e.kind_times + 1 else 1 end,
    vendor = coalesce(excluded.vendor, e.vendor),
    vendor_times = case when excluded.vendor is null then e.vendor_times when excluded.vendor = e.vendor then e.vendor_times + 1 else 1 end,
    last_email_id = coalesce(excluded.last_email_id, e.last_email_id),
    updated_at = now()
  returning * into r;
  return jsonb_build_object('learned', true, 'kind', r.kind, 'kind_times', r.kind_times, 'vendor', r.vendor, 'vendor_times', r.vendor_times);
end $$;
revoke execute on function public.fn_expense_sender_learn(text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_expense_sender_learn(text, text, text, text) to service_role;

-- PROBE. Its rows are rolled back by its own raise inside the block's subtransaction; the DDL above is outside it
-- and stays. A same answer counts up, a different one resets, a line key round-trips. ZZ DEMO / example.invalid only.
do $$
declare o jsonb; k text := repeat('a', 64);
begin
  perform public.fn_expense_sender_learn('ZZ-demo@example.invalid', 'receipt_monthly', 'ZZ DEMO', 'zz-1');
  o := public.fn_expense_sender_learn('zz-demo@example.invalid', 'receipt_monthly', null, 'zz-2');
  if (o->>'kind_times')::int <> 2 or (o->>'vendor_times')::int <> 1 then raise exception 'CHK<<same answer did not count up: %>>', o; end if;
  o := public.fn_expense_sender_learn('zz-demo@example.invalid', 'receipt_annual', null, 'zz-3');
  if (o->>'kind_times')::int <> 1 then raise exception 'CHK<<different answer did not reset: %>>', o; end if;
  perform public.fn_line_spec_reading_put(jsonb_build_array(jsonb_build_object('key', k, 'found', '{"spec_x":"6 tonne"}'::jsonb)));
  if public.fn_line_spec_reading_get(array[k])->k->>'spec_x' is distinct from '6 tonne' then raise exception 'CHK<<line reading did not round-trip>>'; end if;
  raise exception 'PROBE_ROLLBACK';
exception when others then
  if sqlerrm <> 'PROBE_ROLLBACK' then raise; end if;
end $$;
select 'PROBE OK' as verdict;
