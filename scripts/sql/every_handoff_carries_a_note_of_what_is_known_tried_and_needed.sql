-- EVERY HANDOFF CARRIES A NOTE OF WHAT IS KNOWN, WHAT WAS TRIED, WHAT IS NEEDED AND THE EVIDENCE.
-- Seat: it_engineer (shared plumbing). Founder instruction 1013, item 6, 29 Sep 2026.
--
-- The founder: every seat_handoff carries a structured summary - what is known, what has been tried,
-- what is needed, and the evidence links. Built from the case's existing rows by code; a handoff without
-- one is refused. The receiving seat's recall shows it first.
--
-- MEASURED 29 Sep 2026 (production, read-only): 9,563 handoff rows in public.agent_actions
-- (kind = 'handoff'), 83 conversations in public.seat_handoff_kind. Three code paths write a handoff:
--   * public.fn_seat_handoff                          (the registered conversation, every seat)
--   * public.fn_accountant_files_reveal_invoice       (a direct insert, no subject_table/subject_id keys)
--   * public.fn_customer_support_adopts_untracked_send (a direct insert, already 'done')
-- None carried a summary. A receiving seat read a title of <= 200 characters and a payload of loose keys.
--
-- WHAT THIS CHANGES
--   1. public.fn_handoff_summary builds the note BY CODE from rows that already exist for the case:
--        known    - the case (table + id), the conversation, who sent it to whom, what it means, and the
--                   scalar facts the sender put in the payload
--        tried    - every earlier public.agent_actions row on the same case (handoffs and other actions,
--                   newest 10) and every public.seat_case_memory row for it (decision, outcome, lessons)
--        needed   - the conversation's meaning, handler and reply window from public.seat_handoff_kind;
--                   for a path with no registered kind, the row's own recommendation or title
--        evidence - a link per row used above: public.<table>?id=eq.<id>
--   2. Trigger a01_handoff_carries_its_note (BEFORE INSERT OR UPDATE, after a00_ resolves the addressee)
--      puts the note in detail->'summary' on EVERY path - the three above and any written later - so no
--      caller has to remember. It REFUSES a handoff that names no case, or one whose need cannot be
--      stated: a note with nothing needed is not a handoff.
--   3. Constraint agent_actions_handoff_carries_its_note (NOT VALID: the 9,563 earlier rows are history
--      and are filled the first time they are touched) refuses any handoff row without all four parts,
--      even one written with triggers off (session_replication_role = replica does not skip a CHECK).
--   4. public.fn_seat_handoff_notes(seat, subject_table, subject_id) is what the receiving seat's recall
--      reads FIRST (supabase/functions/_shared/case_recall.ts puts the notes above past cases).
--
-- WHAT IT DOES NOT DO. It does not rewrite the 9,563 earlier rows in one statement (a 9.5k-row UPDATE on
-- the table every seat writes to is a lock nobody needs; a row gains its note when it is next touched).
-- Measured before writing the refusal: of the 9,563 earlier rows, 0 name no case and 0 state nothing
-- needed, so touching an old row can never be refused by it. 49 are open.
-- It does not change any handler, any title, or the inbox line (fn_agent_handoff_inbox keeps its measured
-- 215-character budget).
--
-- Pending: scripts/sql/pending/every_handoff_carries_a_note_of_what_is_known_tried_and_needed.txt.
-- Proved by scripts/sql/every_handoff_note_and_seat_playbook_proved_on_zz_demo_probe.sql.

-- The trigger and the constraint take a brief exclusive lock on the table every seat writes to. The
-- first dry proof on 29 Sep met a live writer and deadlocked; wait at most 5 s, then fail and re-run.
set local lock_timeout = '5s';

create or replace function public.fn_handoff_summary(
  p_detail jsonb, p_agent text, p_target_table text, p_target_id text,
  p_title text default null, p_recommendation text default null, p_self_id bigint default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  d        jsonb := coalesce(p_detail, '{}'::jsonb);
  v_table  text  := nullif(btrim(coalesce(d->>'subject_table', p_target_table, '')), '');
  v_id     text  := nullif(btrim(coalesce(d->>'subject_id', p_target_id, '')), '');
  v_type   text  := coalesce(d->>'type', d->>'subject', 'handoff');
  v_from   text  := d->>'from';
  k        public.seat_handoff_kind;
  v_facts  jsonb;
  v_tried  jsonb;
  v_cases  jsonb;
  v_needed jsonb;
  v_links  jsonb;
begin
  if v_id is null then
    raise exception 'a handoff must name its case (subject_id or target_id) - refused, no note can be built';
  end if;
  v_table := coalesce(v_table, 'unknown');

  select * into k from public.seat_handoff_kind
   where type = v_type and from_seat = v_from and to_seat = p_agent;

  -- The sender's scalar facts, minus the keys that are the envelope itself.
  select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) into v_facts
    from jsonb_each(d) e
   where e.key not in ('type','from','from_name','to','subject_table','subject_id','summary','error',
                       'awaiting','replied_at','subject')
     and jsonb_typeof(e.value) in ('string','number','boolean');

  -- What was already done on this case: earlier actions (any seat, any kind), newest first.
  select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) into v_tried
    from (select jsonb_build_object('action_id', a.id, 'seat', a.agent, 'kind', a.kind, 'status', a.status,
                                    'what', left(coalesce(a.title, a.kind), 200), 'at', a.created_at) x
            from public.agent_actions a
           where a.id is distinct from p_self_id
             and ((a.target_table = v_table and a.target_id = v_id)
               or (a.kind = 'handoff' and a.detail->>'subject_id' = v_id
                   and coalesce(a.detail->>'subject_table', a.target_table) = v_table))
           order by a.created_at desc limit 10) t;

  -- What the seats remember deciding on this case.
  select coalesce(jsonb_agg(jsonb_build_object('case_id', m.id, 'seat', m.seat, 'decision', left(m.decision, 300),
                                               'outcome', left(m.outcome, 300), 'finalised', m.finalised,
                                               'lessons', to_jsonb(m.lessons)) order by m.id desc), '[]'::jsonb)
    into v_cases
    from public.seat_case_memory m
   where m.source_table = v_table and m.source_id = v_id;

  v_needed := case
    when k.type is not null then jsonb_build_object(
      'ask', k.meaning, 'handler', k.handler,
      'reply_within', coalesce(k.reply_within::text, 'no deadline set'),
      'closes', case when k.originator_closes then v_from || ' re-verifies and closes' else p_agent || ' closes' end)
    else jsonb_build_object('ask', nullif(btrim(coalesce(p_recommendation, p_title, '')), ''),
                            'handler', null, 'reply_within', 'no registered conversation',
                            'closes', p_agent || ' closes')
  end;
  if nullif(btrim(coalesce(v_needed->>'ask', '')), '') is null then
    raise exception 'handoff % on %#% states nothing needed - refused', v_type, v_table, v_id;
  end if;

  select jsonb_agg(l) into v_links from (
    select 'public.' || v_table || '?id=eq.' || v_id as l
    union all select 'public.agent_actions?id=eq.' || (t->>'action_id') from jsonb_array_elements(v_tried) t
    union all select 'public.seat_case_memory?id=eq.' || (c->>'case_id') from jsonb_array_elements(v_cases) c
  ) z;

  return jsonb_build_object(
    'known', jsonb_build_object('case', v_table || '#' || v_id, 'conversation', v_type,
                                'from', v_from, 'to', p_agent, 'means', k.meaning, 'facts', v_facts),
    'tried', jsonb_build_object('actions', v_tried, 'case_memory', v_cases),
    'needed', v_needed,
    'evidence', coalesce(v_links, '[]'::jsonb),
    'built_by', 'fn_handoff_summary');
end $fn$;

revoke execute on function public.fn_handoff_summary(jsonb, text, text, text, text, text, bigint) from public, anon, authenticated;

create or replace function public.trg_handoff_carries_its_note()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  new.detail := coalesce(new.detail, '{}'::jsonb) || jsonb_build_object('summary',
    public.fn_handoff_summary(new.detail, new.agent, new.target_table, new.target_id,
                              new.title, new.recommendation, new.id));
  return new;
end $fn$;

revoke execute on function public.trg_handoff_carries_its_note() from public, anon, authenticated;

drop trigger if exists a01_handoff_carries_its_note on public.agent_actions;
create trigger a01_handoff_carries_its_note
  before insert or update on public.agent_actions
  for each row
  when (new.kind = 'handoff' and not (coalesce(new.detail, '{}'::jsonb) ? 'summary'))
  execute function public.trg_handoff_carries_its_note();

alter table public.agent_actions drop constraint if exists agent_actions_handoff_carries_its_note;
alter table public.agent_actions add constraint agent_actions_handoff_carries_its_note
  check (kind <> 'handoff'
         or coalesce(detail->'summary', '{}'::jsonb) ?& array['known','tried','needed','evidence'])
  not valid;

-- What the receiving seat's recall reads first: its open handoffs on this case (or, with no case, its
-- three newest open handoffs), each with the note.
create or replace function public.fn_seat_handoff_notes(p_seat text, p_subject_table text default null,
                                                       p_subject_id text default null)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('handoff_id', a.id, 'from', a.detail->>'from',
                                               'conversation', coalesce(a.detail->>'type', a.detail->>'subject'),
                                               'opened_at', a.created_at, 'status', a.status,
                                               'summary', a.detail->'summary') order by a.created_at desc), '[]'::jsonb)
    from (select * from public.agent_actions a
           where a.kind = 'handoff' and a.agent = p_seat
             and (a.status in ('pending','needs_review') or (a.detail ? 'awaiting' and a.status <> 'failed' and a.decided_at is null))
             and a.detail ? 'summary'
             and (p_subject_id is null
                  or (coalesce(a.detail->>'subject_id', a.target_id) = p_subject_id
                      and (p_subject_table is null or coalesce(a.detail->>'subject_table', a.target_table) = p_subject_table)))
           order by a.created_at desc limit 3) a;
$fn$;

revoke execute on function public.fn_seat_handoff_notes(text, text, text) from public, anon, authenticated;
grant execute on function public.fn_seat_handoff_notes(text, text, text) to service_role;
