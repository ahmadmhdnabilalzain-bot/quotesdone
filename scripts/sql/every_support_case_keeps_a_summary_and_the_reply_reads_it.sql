-- every_support_case_keeps_a_summary_and_the_reply_reads_it.sql
-- Assigned: customer_support (the case is support's record), built by it_engineer. Founder rulings of 11 Nov 2026:
--   1635: "Every conversation is a case with a case number. After each exchange the agent records a summary of the case.
--          When the same customer or supplier writes again, the agent decides whether it is the same matter (then it works
--          from that case's summary instead of rereading the whole chat) or a different matter (then it opens a new case).
--          ... The case summaries are backed up in the customer's or supplier's Dropbox folder with their profile."
--   1634: keep everything in history (nothing here deletes; every summary version is kept).
--   1631: every agent reads the history before it replies, economically.
--
-- WHAT EXISTS (measured 11 Nov 2026, so nothing is built twice): public.support_case (28 rows, 26 in 30 days) already has a
-- case number (case_ref), the person (customer_profile_id -> support_customer_profile, one row per person across email,
-- phone, customer id and lead id), opened / last activity, state (open, waiting_customer, waiting_service, blocked, closed),
-- the owning seat, channel(s) and inquiry_ref. fn_support_touch, fired by the z50 triggers on wa_messages, inbound_messages
-- and assistant_logs, attaches every message to the person's newest open case and opens one after 7 idle days.
-- WHAT IS MISSING, and what this adds:
--   1. the summary: support_case.summary (jsonb: asked, said_or_did, promised [{what, by}], open), summary_text (what a reply
--      is given), title (one line), summary_version, summary_updated_at, linked_refs (inquiries, quotes, transactions);
--      status_plain states the founder's vocabulary over the existing states (waiting_on_us / waiting_on_them / closed);
--   2. support_case_summary_version: every summary ever written, append-only (ruling 1634);
--   3. fn_support_case_summary_write: the one writer, refusing a stale version (two replies at once cannot overwrite);
--   4. fn_support_open_cases: what the same-matter decision is given (number, title, summary), one person, every channel;
--   5. fn_support_case_route: "continue case X" makes X the case fn_support_touch attaches to; "new case" opens one;
--   6. the case_summary model class (cheap model, high effort: the next reply relies on what it records as promised);
--   7. the Dropbox seam: fn_support_case_summary_backup_enqueue queues a doc_backups row (gen_kind case_summary) beside the
--      person's existing Customer/Company Details file, only while app_secrets.case_summary_backup_enabled = 'true'
--      (unset today: pdf_native has no case_summary renderer yet, and a row it cannot render would read as a failed backup).
-- WHAT IT DOES NOT CHANGE: fn_support_touch and its triggers; how a case closes; no row is deleted or rewritten.
-- Code: supabase/functions/_shared/support_case_memory.ts (decision, summary step, the reply's cached case block).
-- prevented by: supabase/functions/_shared/support_case_memory.test.ts, scripts/checks/every_case_keeps_a_summary.test.mjs

alter table public.support_case add column if not exists title text;
alter table public.support_case add column if not exists summary jsonb;
alter table public.support_case add column if not exists summary_text text;
alter table public.support_case add column if not exists summary_version integer not null default 0;
alter table public.support_case add column if not exists summary_updated_at timestamptz;
alter table public.support_case add column if not exists linked_refs jsonb not null default '{}'::jsonb;
alter table public.support_case add column if not exists status_plain text generated always as (
  case when state = 'closed' then 'closed' when state = 'waiting_customer' then 'waiting_on_them' else 'waiting_on_us' end) stored;
alter table public.support_case drop constraint if exists support_case_summary_shape_ck;
alter table public.support_case add constraint support_case_summary_shape_ck check (
  summary is null or (jsonb_typeof(summary) = 'object' and summary ? 'asked' and summary ? 'said_or_did'
                      and jsonb_typeof(summary -> 'promised') = 'array' and jsonb_typeof(summary -> 'open') = 'array'));

create table if not exists public.support_case_summary_version (
  id bigserial primary key,
  case_id bigint not null references public.support_case (case_id),
  version integer not null,
  summary jsonb not null,
  summary_text text not null,
  title text,
  written_by text not null,
  model text,
  created_at timestamptz not null default now(),
  unique (case_id, version)
);
alter table public.support_case_summary_version enable row level security;
drop policy if exists support_case_summary_version_service_role_only on public.support_case_summary_version;
create policy support_case_summary_version_service_role_only on public.support_case_summary_version
  as permissive for all to public using (false) with check (false);
revoke all on public.support_case_summary_version from anon, authenticated;

create or replace function public.fn_support_case_summary_version_is_append_only()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $fn$
begin
  raise exception 'support_case_summary_version is append-only (ruling 1634): write a new version instead';
end $fn$;
revoke execute on function public.fn_support_case_summary_version_is_append_only() from public, anon, authenticated;
drop trigger if exists a00_support_case_summary_version_append_only on public.support_case_summary_version;
create trigger a00_support_case_summary_version_append_only before update or delete on public.support_case_summary_version
  for each row execute function public.fn_support_case_summary_version_is_append_only();

-- 7. the Dropbox seam (off until pdf_native renders gen_kind case_summary)
create or replace function public.fn_support_case_summary_backup_enqueue(p_case_id bigint)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.support_case; v_folder text;
begin
  if coalesce((select value from public.app_secrets where key = 'case_summary_backup_enabled'), '') <> 'true' then return false; end if;
  select * into c from public.support_case where case_id = p_case_id;
  if c.case_id is null or c.summary is null or c.party_kind not in ('customer', 'supplier') then return false; end if;
  -- the person's folder is where their details file already lives (Customers/<name (id)>/, Suppliers/<trade>/<name>/)
  select regexp_replace(b.dropbox_path, '/[^/]+$', '') into v_folder from public.doc_backups b
   where b.source = 'generated' and b.gen_kind in ('customer_details', 'supplier_details') and b.entity_id = c.party_id
     and b.dropbox_path not like '%/_archive/%'
   order by b.created_at desc limit 1;
  if v_folder is null then return false; end if;
  -- the same row shape the generated details files use (bucket 'backups', path 'generated/...'); one row per summary version
  insert into public.doc_backups (entity, entity_id, doc_type, source, gen_kind, gen_ref, bucket, path, file_name, dropbox_path, status, dedupe_key)
  values (c.party_kind, c.party_id, 'Case Summary', 'generated', 'case_summary', c.case_ref, 'backups',
          'generated/case_summary_' || c.case_ref || '_v' || c.summary_version,
          c.case_ref || '.pdf', v_folder || '/Cases/' || c.case_ref || '.pdf', 'pending',
          'case_summary:' || c.case_ref || ':' || c.summary_version)
  on conflict (bucket, path) do nothing;
  return true;
end $fn$;
revoke execute on function public.fn_support_case_summary_backup_enqueue(bigint) from public, anon, authenticated;

-- 3. the one writer
create or replace function public.fn_support_case_summary_write(
  p_case_ref text, p_expected_version integer, p_summary jsonb, p_summary_text text, p_title text,
  p_written_by text, p_model text default null, p_linked_refs jsonb default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.support_case; v_next int;
begin
  select * into c from public.support_case where case_ref = p_case_ref for update;
  if c.case_id is null then return jsonb_build_object('ok', false, 'reason', 'no such case'); end if;
  if c.summary_version <> coalesce(p_expected_version, -1) then
    return jsonb_build_object('ok', false, 'reason', 'stale', 'version', c.summary_version);
  end if;
  if p_summary is null or jsonb_typeof(p_summary) <> 'object' or not (p_summary ? 'asked' and p_summary ? 'said_or_did')
     or jsonb_typeof(p_summary -> 'promised') <> 'array' or jsonb_typeof(p_summary -> 'open') <> 'array'
     or length(coalesce(p_summary_text, '')) not between 1 and 4000 then
    return jsonb_build_object('ok', false, 'reason', 'bad shape');
  end if;
  v_next := c.summary_version + 1;
  update public.support_case
     set summary = p_summary, summary_text = p_summary_text, title = coalesce(nullif(left(btrim(p_title), 160), ''), title),
         summary_version = v_next, summary_updated_at = now(),
         linked_refs = case when p_linked_refs is null then linked_refs else linked_refs || p_linked_refs end
   where case_id = c.case_id;
  insert into public.support_case_summary_version (case_id, version, summary, summary_text, title, written_by, model)
  values (c.case_id, v_next, p_summary, p_summary_text, left(btrim(p_title), 160), coalesce(p_written_by, 'customer_support'), p_model);
  perform public.fn_support_case_summary_backup_enqueue(c.case_id);
  return jsonb_build_object('ok', true, 'case_ref', c.case_ref, 'version', v_next);
end $fn$;
revoke execute on function public.fn_support_case_summary_write(text, integer, jsonb, text, text, text, text, jsonb) from public, anon, authenticated;

-- 4. what the same-matter decision is given: the person's open cases on every channel, newest first, at most five
create or replace function public.fn_support_open_cases(p_party_kind text, p_party_id text, p_email text, p_phone text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_prof bigint;
begin
  v_prof := public.fn_support_profile_resolve(case when p_party_kind in ('customer', 'supplier') then p_party_kind else 'unknown' end,
                                              p_party_id, p_email, p_phone);
  if v_prof is null then return jsonb_build_object('profile', null, 'cases', '[]'::jsonb); end if;
  return jsonb_build_object('profile', v_prof, 'cases', coalesce((
    select jsonb_agg(jsonb_build_object('case_ref', x.case_ref, 'title', coalesce(x.title, left(x.subject, 160)),
                                        'summary_text', x.summary_text, 'summary_version', x.summary_version,
                                        'status', x.status_plain, 'channels', x.channels, 'last_activity_at', x.last_activity_at)
                     order by x.last_activity_at desc)
      from (select * from public.support_case where customer_profile_id = v_prof and state <> 'closed'
             order by last_activity_at desc limit 5) x), '[]'::jsonb));
end $fn$;
revoke execute on function public.fn_support_open_cases(text, text, text, text) from public, anon, authenticated;

-- 5. the decision, recorded: continue a case of THIS person, or open a new one
create or replace function public.fn_support_case_route(p_profile bigint, p_choice text, p_case_ref text, p_channel text, p_text text, p_lang text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.support_case; p public.support_customer_profile; v_ref text; attempt int := 0;
begin
  select * into p from public.support_customer_profile where id = p_profile;
  if p.id is null then return jsonb_build_object('ok', false, 'reason', 'no such person'); end if;
  if p_choice = 'continue' then
    select * into c from public.support_case where case_ref = p_case_ref and customer_profile_id = p_profile and state <> 'closed';
    if c.case_id is null then return jsonb_build_object('ok', false, 'reason', 'not an open case of this person'); end if;
    -- the newest open case is the one fn_support_touch attaches the message to
    -- clock_timestamp, not now(): inside one transaction now() ties with the case opened a moment before (probe, 11 Nov)
    update public.support_case set last_activity_at = clock_timestamp() where case_id = c.case_id;
    return jsonb_build_object('ok', true, 'case_ref', c.case_ref, 'opened', false);
  elsif p_choice = 'new' then
    loop
      attempt := attempt + 1;
      begin
        v_ref := public.fn_support_case_new_ref();
        insert into public.support_case (case_ref, party_kind, party_id, subject, state, identity_verified, verified_how,
                                         owner_role_id, customer_profile_id, channel, lang)
        values (v_ref, coalesce(p.party_kind, 'unknown'), coalesce(p.customer_id::text, p.lead_id::text, p.email, p.phone_tail),
                initcap(coalesce(p_channel, 'internal')) || ': ' || left(coalesce(nullif(btrim(p_text), ''), '(no text)'), 4000),
                'open', coalesce(p.party_kind, 'unknown') <> 'unknown',
                case when coalesce(p.party_kind, 'unknown') <> 'unknown' then 'matched on the ' || coalesce(p_channel, 'internal') || ' identity' end,
                'customer_support', p_profile,
                case when p_channel in ('whatsapp', 'email', 'widget', 'portal', 'phone', 'internal', 'social') then p_channel end,
                case when p_lang in ('en', 'ar') then p_lang end);
        exit;
      exception when unique_violation then
        if attempt >= 5 then raise; end if;
      end;
    end loop;
    return jsonb_build_object('ok', true, 'case_ref', v_ref, 'opened', true);
  end if;
  return jsonb_build_object('ok', false, 'reason', 'choice is continue or new');
end $fn$;
revoke execute on function public.fn_support_case_route(bigint, text, text, text, text, text) from public, anon, authenticated;

-- 6. the summary's model class: the cheap model, high effort (supabase/functions/_shared/effort_policy.ts)
insert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, rationale, active, cache_ttl_min, effort)
values ('case_summary', 'medium', 'openai/gpt-6-luna-pro', 'qwen/qwen3.8-flash', 900,
        'Ruling 1635: the case summary after each exchange. Cheap model; high effort because the next reply relies on what it records as promised.',
        true, 0, 'high')
on conflict (task_class) do nothing;

-- verdict: the shape is in place, the writers are closed to callers, and nothing was rewritten
select case
  when (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'support_case'
         and column_name in ('title', 'summary', 'summary_text', 'summary_version', 'summary_updated_at', 'linked_refs', 'status_plain')) <> 7
    then 'PROBE FAILED: a support_case column is missing'
  when has_function_privilege('anon', 'public.fn_support_case_summary_write(text, integer, jsonb, text, text, text, text, jsonb)', 'execute')
    or has_function_privilege('anon', 'public.fn_support_open_cases(text, text, text, text)', 'execute')
    or has_function_privilege('anon', 'public.fn_support_case_route(bigint, text, text, text, text, text)', 'execute')
    then 'PROBE FAILED: anon can execute a case routine'
  when not exists (select 1 from public.model_policy where task_class = 'case_summary')
    then 'PROBE FAILED: no case_summary policy row'
  else 'PROBE OK' end as verdict;
