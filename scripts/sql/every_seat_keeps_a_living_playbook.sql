-- EVERY SEAT KEEPS A LIVING PLAYBOOK: THE STEPS, DECISION RULES AND ESCALATION FOR EACH CASE KIND IT HANDLES.
-- apply-window: off-hours (release coordinator, 29 Sep 2026: applied outside a campaign hour; a lock wait is retried)
-- Seat: it_engineer (shared plumbing). Founder instruction 1013, item 9, 29 Sep 2026.
--
-- The founder: each seat keeps a living playbook covering each case kind it handles - the steps, decision
-- rules and escalation. Generate it from the seat's duties, handoff kinds and knowledge. Update it
-- automatically when a lesson is recorded (the learning loop). Store it in the database and export it as
-- docs/seats/<seat>_playbook.md so an auditor can read it.
--
-- MEASURED 29 Sep 2026 (production, read-only): 42 rows in public.seat_duty and 83 in
-- public.seat_handoff_kind across six seats (accountant, ceo, customer_support, it_engineer, marketing,
-- sales_engineer); lessons on public.seat_case_memory for it_engineer 426 cases, sales_engineer 6,
-- customer_support 5; public.reasoning_knowledge_candidate 0 rows. Each seat's verified pack lives in its
-- own table (every_verified_pack_has_a_home_and_every_seat_reads_its_own.sql), English rows keyed
-- '<seat>:<entry>' and Arabic '<seat>:<entry>@ar'. No playbook existed anywhere.
--
-- WHAT THIS BUILDS
--   public.seat_playbook             one row per seat: the playbook as jsonb, its Markdown, a version that
--                                    moves only when the content moves, and why it was last rebuilt.
--   public.fn_seat_playbook_build    generates one seat's playbook BY CODE from:
--        duties     - public.seat_duty (enabled) -> the standing steps the seat takes unasked
--        case kinds - public.seat_handoff_kind to_seat = seat -> per kind: steps (read the handoff note,
--                     the handler acts, reply window, who closes) and escalation (handler failure fails
--                     the row and opens an it_engineer finding in fn_seat_handoff; a missed window is
--                     picked up by fn_it_handoff_sla_items)
--        routes     - public.seat_handoff_kind from_seat = seat -> where the seat escalates / hands on
--        rules      - the 'Decision rule:' sentences of the seat's verified knowledge entries
--        lessons    - public.seat_case_memory lessons and approved reasoning_knowledge_candidate findings
--   public.fn_seat_playbook_build_all  every seat.
--   Triggers (the learning loop): a lesson written on seat_case_memory, a candidate approved or rejected,
--   or any change to seat_duty / seat_handoff_kind rebuilds the playbook(s) concerned. A rebuild that
--   fails never fails the write that caused it: it opens an it_engineer finding instead.
--   scripts/seats/export_playbooks.mjs writes docs/seats/<seat>_playbook.md from the table and, with
--   --check, fails when a committed file differs from the database.
--
-- WHAT IT DOES NOT DO. It does not match a knowledge entry to a case kind by words (the founder's
-- standing rule: by meaning, never by word matching) - decision rules are the seat's, listed once. It
-- shows the newest 25 lessons, not all 426 (the table keeps them all). It changes no duty and no kind.
--
-- Pending: scripts/sql/pending/every_seat_keeps_a_living_playbook.txt.
-- Proved by scripts/sql/every_handoff_note_and_seat_playbook_proved_on_zz_demo_probe.sql.

create table if not exists public.seat_playbook (
  seat           text primary key
                 check (seat = any (array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing'])),
  version        integer not null default 1,
  playbook       jsonb not null,
  markdown       text not null,
  content_md5    text not null,
  rebuilt_reason text not null,
  rebuilt_at     timestamptz not null default now()
);
alter table public.seat_playbook enable row level security;
drop policy if exists seat_playbook_service_role_only on public.seat_playbook;
create policy seat_playbook_service_role_only on public.seat_playbook
  as permissive for all to public using (false) with check (false);
revoke all on public.seat_playbook from anon, authenticated;

create or replace function public.fn_seat_playbook_build(p_seat text, p_reason text default 'rebuilt on request')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_table   text := case p_seat when 'sales_engineer' then 'sales_knowledge' when 'customer_support' then 'support_knowledge'
                            when 'accountant' then 'accountant_knowledge' when 'it_engineer' then 'it_engineer_knowledge'
                            when 'ceo' then 'ceo_knowledge' when 'marketing' then 'marketing_knowledge' end;
  v_duties  jsonb; v_kinds jsonb; v_routes jsonb; v_rules jsonb := '[]'::jsonb; v_lessons jsonb;
  v_pb      jsonb; v_md text; v_md5 text; v_old public.seat_playbook; v_version int;
begin
  if v_table is null then raise exception 'no seat %', p_seat; end if;

  select coalesce(jsonb_agg(jsonb_build_object('duty', duty, 'every', every::text, 'what', what, 'routine', routine)
                            order by duty), '[]'::jsonb)
    into v_duties from public.seat_duty where owner_seat = p_seat and enabled;

  select coalesce(jsonb_agg(jsonb_build_object(
           'kind', type, 'from', from_seat, 'means', meaning,
           'steps', jsonb_build_array(
              'Read the handoff note first (known / tried / needed / evidence) - it leads my recall.',
              'Act through ' || handler || '.',
              'Reply ' || coalesce('within ' || reply_within::text, 'without a set deadline') || '.',
              case when originator_closes then from_seat || ' re-verifies my answer and closes the handoff.'
                   else 'I close the handoff with evidence when done.' end),
           'escalation', jsonb_build_array(
              'If ' || handler || ' fails, the handoff is marked failed and an it_engineer finding is opened (fn_seat_handoff).',
              case when reply_within is not null then 'Past ' || reply_within::text || ' the it_engineer SLA monitor (fn_it_handoff_sla_items) picks it up.'
                   else 'No reply window: the originator re-verifies (fn_originators_reverify_handoffs).' end))
         order by type, from_seat), '[]'::jsonb)
    into v_kinds from public.seat_handoff_kind where to_seat = p_seat;

  select coalesce(jsonb_agg(jsonb_build_object('to', to_seat, 'kind', type, 'means', meaning) order by to_seat, type), '[]'::jsonb)
    into v_routes from public.seat_handoff_kind where from_seat = p_seat;

  -- The decision rules the seat's verified knowledge states, one per entry that states one.
  if to_regclass('public.' || v_table) is not null then
    execute format($q$
      select coalesce(jsonb_agg(jsonb_build_object('entry', record_id, 'topic', title, 'rule', rule) order by record_id), '[]'::jsonb)
        from (select k.record_id, k.title,
                     btrim((regexp_match(coalesce(to_jsonb(k)->>'content', to_jsonb(k)->>'body', ''),
                                         -- [^\n], not '.': in a Postgres regex '.' matches a newline, and
                                         -- the first dry run swallowed each entry to its end.
                                         'Decision rules?:\s*([^\n]+)'))[1]) as rule
                from public.%I k
               where k.record_id like $1 || ':%%' and k.record_id not like '%%@ar') r
       where rule is not null$q$, v_table)
      into v_rules using p_seat;
  end if;

  select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) into v_lessons from (
    select x from (
      select jsonb_build_object('lesson', l, 'case_id', m.id, 'case_kind', m.case_kind, 'at', m.updated_at) x
        from public.seat_case_memory m, unnest(m.lessons) l
       where m.seat = p_seat and btrim(l) <> ''
      union all
      select jsonb_build_object('lesson', c.finding, 'candidate_id', c.id, 'case_kind', 'approved finding', 'at', coalesce(c.reviewed_at, c.created_at))
        from public.reasoning_knowledge_candidate c
       where c.seat = p_seat and c.status = 'approved'
    ) u order by x->>'at' desc limit 25) z;

  v_pb := jsonb_build_object('seat', p_seat, 'duties', v_duties, 'case_kinds', v_kinds, 'hands_on_to', v_routes,
                             'decision_rules', coalesce(v_rules, '[]'::jsonb), 'lessons', v_lessons);
  v_md5 := md5(v_pb::text);

  select * into v_old from public.seat_playbook where seat = p_seat;
  if found and v_old.content_md5 = v_md5 then
    return jsonb_build_object('seat', p_seat, 'version', v_old.version, 'changed', false);
  end if;
  v_version := coalesce(v_old.version, 0) + 1;

  -- The Markdown an auditor reads. No clock in it: the file changes only when the playbook does.
  v_md := '# ' || initcap(replace(p_seat, '_', ' ')) || ' playbook' || E'\n\n'
    || '> Generated by `public.fn_seat_playbook_build` from the database (seat_duty, seat_handoff_kind, the seat''s verified knowledge, and its lessons). '
    || 'Do not edit by hand - it is rebuilt every time a lesson is recorded. Version ' || v_version || '.' || E'\n\n'
    || '## Standing duties (what I do without being asked)' || E'\n\n'
    || coalesce((select string_agg('- **' || (d->>'duty') || '** (every ' || (d->>'every') || '): ' || (d->>'what') || ' - `' || (d->>'routine') || '`', E'\n' order by ord)
                   from jsonb_array_elements(v_duties) with ordinality t(d, ord)), '- none') || E'\n\n'
    || '## Case kinds I handle' || E'\n\n'
    || coalesce((select string_agg('### ' || (c->>'kind') || ' (from ' || (c->>'from') || ')' || E'\n\n'
                                   || (c->>'means') || E'\n\n' || 'Steps:' || E'\n'
                                   || (select string_agg((n) || '. ' || s, E'\n' order by n) from jsonb_array_elements_text(c->'steps') with ordinality s2(s, n))
                                   || E'\n\n' || 'Escalation:' || E'\n'
                                   || (select string_agg('- ' || s, E'\n') from jsonb_array_elements_text(c->'escalation') s),
                                   E'\n\n' order by ord)
                   from jsonb_array_elements(v_kinds) with ordinality t(c, ord)), 'No case kind is handed to this seat.') || E'\n\n'
    || '## Where I hand work on' || E'\n\n'
    || coalesce((select string_agg('- to **' || (r->>'to') || '** as `' || (r->>'kind') || '`: ' || (r->>'means'), E'\n' order by ord)
                   from jsonb_array_elements(v_routes) with ordinality t(r, ord)), '- nowhere') || E'\n\n'
    || '## Decision rules from my verified knowledge' || E'\n\n'
    || coalesce((select string_agg('- **' || (r->>'topic') || '** (`' || (r->>'entry') || '`): ' || (r->>'rule'), E'\n' order by ord)
                   from jsonb_array_elements(coalesce(v_rules, '[]'::jsonb)) with ordinality t(r, ord)), '- none stated yet') || E'\n\n'
    || '## Lessons learned (newest 25, from the learning loop)' || E'\n\n'
    || coalesce((select string_agg('- ' || replace(l->>'lesson', E'\n', ' ')
                                   || coalesce(' (case #' || (l->>'case_id') || ')', ' (finding #' || (l->>'candidate_id') || ')'), E'\n' order by ord)
                   from jsonb_array_elements(v_lessons) with ordinality t(l, ord)), '- none recorded yet') || E'\n';

  insert into public.seat_playbook (seat, version, playbook, markdown, content_md5, rebuilt_reason, rebuilt_at)
  values (p_seat, v_version, v_pb, v_md, v_md5, left(coalesce(p_reason, 'rebuilt'), 300), now())
  on conflict (seat) do update set version = excluded.version, playbook = excluded.playbook, markdown = excluded.markdown,
                                   content_md5 = excluded.content_md5, rebuilt_reason = excluded.rebuilt_reason,
                                   rebuilt_at = excluded.rebuilt_at;
  return jsonb_build_object('seat', p_seat, 'version', v_version, 'changed', true);
end $fn$;

revoke execute on function public.fn_seat_playbook_build(text, text) from public, anon, authenticated;

create or replace function public.fn_seat_playbook_build_all(p_reason text default 'rebuilt on request')
returns jsonb
language sql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_agg(public.fn_seat_playbook_build(s, p_reason) order by s)
    from unnest(array['accountant','ceo','customer_support','it_engineer','marketing','sales_engineer']) s;
$fn$;

revoke execute on function public.fn_seat_playbook_build_all(text) from public, anon, authenticated;

-- THE LEARNING LOOP. A rebuild failure must never undo the lesson that caused it.
create or replace function public.trg_seat_playbook_learns()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  begin
    if tg_table_name = 'seat_case_memory' then
      perform public.fn_seat_playbook_build(new.seat, 'lesson recorded on case #' || new.id);
    elsif tg_table_name = 'reasoning_knowledge_candidate' then
      perform public.fn_seat_playbook_build(new.seat, 'finding #' || new.id || ' ' || new.status);
    else
      perform public.fn_seat_playbook_build_all(tg_table_name || ' changed');
    end if;
  exception when others then
    begin
      perform public.fn_it_engineer_finding_upsert(
        'monitor:seat_playbook_rebuild_failed:' || tg_table_name,
        'A seat playbook could not be rebuilt after a change to ' || tg_table_name,
        'public.trg_seat_playbook_learns', 'agent_facing', 1,
        jsonb_build_object('error', left(sqlerrm, 500), 'owner_seat', 'it_engineer',
                           'fix', 'run select public.fn_seat_playbook_build_all() and read the error'),
        '{}'::text[], array['why fn_seat_playbook_build failed'], 'trg_seat_playbook_learns');
    exception when others then null;  -- the lesson stands; the next rebuild retries
    end;
  end;
  return null;
end $fn$;

revoke execute on function public.trg_seat_playbook_learns() from public, anon, authenticated;

drop trigger if exists z70_seat_playbook_learns on public.seat_case_memory;
create trigger z70_seat_playbook_learns
  after insert or update of lessons on public.seat_case_memory
  for each row
  when (cardinality(new.lessons) > 0)
  execute function public.trg_seat_playbook_learns();

drop trigger if exists z70_seat_playbook_learns on public.reasoning_knowledge_candidate;
create trigger z70_seat_playbook_learns
  after insert or update of status on public.reasoning_knowledge_candidate
  for each row
  when (new.status in ('approved','rejected'))
  execute function public.trg_seat_playbook_learns();

drop trigger if exists z70_seat_playbook_follows_duties on public.seat_duty;
create trigger z70_seat_playbook_follows_duties
  -- NOT on last_started_at / last_ok_at / failures: every duty tick writes those, and a playbook does
  -- not change because a duty ran.
  after insert or delete or update of duty, owner_seat, every, routine, what, enabled on public.seat_duty
  for each statement execute function public.trg_seat_playbook_learns();

drop trigger if exists z70_seat_playbook_follows_kinds on public.seat_handoff_kind;
create trigger z70_seat_playbook_follows_kinds
  after insert or update or delete on public.seat_handoff_kind
  for each statement execute function public.trg_seat_playbook_learns();

select public.fn_seat_playbook_build_all('first build, founder instruction 1013 item 9');
