-- EVERY HANDOFF NOTE STATES ITS CONTEXT, DECISION, OPEN ASKS AND DEADLINE, AND THE RECEIVER CITES IT.
-- apply-window: off-hours (the trigger and the constraint take a brief lock on public.agent_actions)
-- Seat: ceo. Founder ledger row 1013: "seat handover notes: when work passes between seats, a structured
-- note (context, decision, open asks, deadline) is written and read by the receiver."
--
-- MEASURED 19 Oct 2026 02:28 UTC (production, read-only): #1072 IS applied - fn_handoff_summary,
-- trg_handoff_carries_its_note and fn_seat_handoff_notes exist, trigger a01_handoff_carries_its_note is on
-- public.agent_actions, and the CHECK agent_actions_handoff_carries_its_note is in place (NOT VALID, as
-- written). 17,287 handoff rows; 7,245 carry detail.summary; 3,061 were written in the last 7 days
-- (2,160 done, 901 pending).
--
-- WHAT WAS MISSING
--   1. The note held known / tried / needed / evidence, but not the four fields the ledger names. There
--      was no DEADLINE at all: needed.reply_within is an interval text ('24:00:00' or 'no deadline set'),
--      never a time, and 10 of the 35 conversations between customer_support, sales_engineer and
--      accountant have no reply window. There was no DECISION: nothing said what the sender decided.
--   2. Nothing recorded that the receiver READ the note. fn_seat_handoff_act ran the handler and stored
--      its answer as the row's evidence; the answer named no note. A receiver that ignored the note and
--      one that used it left identical rows.
--
-- WHAT THIS CHANGES (extends #1072, does not duplicate it: same routine, same trigger, same table)
--   1. public.fn_handoff_summary keeps known / tried / needed / evidence and adds, BY CODE:
--        context   - one sentence: the case, the conversation, who sent it to whom, its facts, and how much
--                    already happened on the case (counts of earlier actions and remembered decisions)
--        decision  - what the sender decided, first found of: the sender's payload 'decision'; the
--                    sender's newest seat_case_memory decision on this case; the registered conversation's
--                    meaning, stated as the sender's decision to hand it over
--        open_asks - a JSON array of what the receiver must do: the ask, plus any payload 'asks' (array)
--                    or 'question' the sender wrote
--        deadline  - a timestamptz, first found of: the payload's 'deadline' / 'due_at'; now() + the
--                    conversation's reply_within; the case row's own due column (due_at, deadline,
--                    due_date, response_due_at, expires_at); else now() + 24 hours, the company's default
--                    handoff window, with deadline_source saying which one was used
--      A note that cannot state context, decision, at least one open ask and a deadline is REFUSED.
--   2. Trigger a01_handoff_carries_its_note now also fires on a row whose note lacks any of the four, so an
--      older row gains them the first time it is touched (a 17k-row UPDATE is a lock nobody needs).
--   3. CHECK agent_actions_handoff_note_states_four_fields (NOT VALID, same reasoning as #1072) refuses a
--      handoff row whose note lacks any of the four, even with triggers off.
--   4. THE RECEIVER CITES THE NOTE. fn_seat_handoff_act (the dispatcher every registered handler is reached
--      through) and fn_seat_handoff_complete (every way a handoff closes) put evidence.cites_note =
--      {handoff_id, read_by, deadline, open_asks, on_time} on the receiver's answer. A model path cites it
--      through the recall trace (case_recall.ts already records the handoff ids it showed the model, and
--      now shows the four fields and tells the model to cite "handoff #N").
--   5. public.fn_handoff_citation_gaps(p_since) MEASURES it: handoffs closed since p_since whose note is
--      complete but whose answer cites no note. Read by scripts/checks/every_handoff_note_is_cited_by_its_receiver.test.mjs
--      against this file, and on production after apply.
--
-- WHAT IT DOES NOT DO. It does not change any handler, any reply window, any title or the inbox line. It
-- does not rewrite the 17,287 earlier rows. It does not change who closes a handoff.
--
-- Bodies of fn_seat_handoff_act and fn_seat_handoff_complete are production's (read 19 Oct 2026 from the
-- schema mirror; canonical files the_it_engineer_closes_every_loop_it_opens.sql and
-- payments_are_the_accountant_and_the_seats_close_every_refund_together.sql) with ONLY the citation added.
--
-- Pending: scripts/sql/pending/every_handoff_note_states_context_decision_open_asks_and_deadline_and_its_receiver_cites_it.txt
-- Proved by: scripts/sql/every_handoff_note_states_context_decision_open_asks_and_deadline_probe.sql

-- 13 Nov 2026 (it_engineer; coordinator's review 3, items 2 and 4): 1.5 s, the same as every file of that release; the
-- apply FAILS rather than queue behind a long query on agent_actions. The trigger is replaced in place (CREATE OR REPLACE
-- TRIGGER) and the CHECK is added NOT VALID (no scan). Canonical for every routine it defines, checked 13 Nov 2026 against
-- production (md5 of each body, read only) and by applying it whole on a local copy: fn_handoff_redact, fn_handoff_summary,
-- trg_handoff_carries_its_note, fn_handoff_note_citation and fn_seat_handoff_complete are this file's; the copy of
-- fn_handoff_citation_gaps that lived here was superseded by a_handoff_closes_only_when_its_receiver_cites_the_note_or_says_why_not.sql
-- (MANIFEST line 2149) and is removed, so re-applying this file no longer reverts it.
set local lock_timeout = '1500ms';

-- Redacts e-mail addresses and phone numbers: international (+ or 00 then 7+ digits, spaces/dashes allowed) and
-- UAE local (a word starting 0[1-9] with exactly 9-10 digits, single space/dash between: 05x xxx xxxx, 04 xxx xxxx).
-- Measured not to touch ids (no leading 0), ISO dates/times (separators are ':' or 'T', at most 2 digits per run),
-- dd-mm-yyyy dates (8 digits), or AED amounts (a '.' ends the run) - see the probe's control string.
-- Applied to the WHOLE note, so case-memory lessons copied under tried.case_memory are redacted too.
--
-- 13 Nov 2026 (it_engineer; coordinator's review 3, item 4). It ran the patterns over the note's JSON TEXT, so a NUMBER
-- was text to it: 135.000000000000000000 (a numeric total with its scale) became 135.[phone] and the cast back to jsonb
-- raised 22P02, refusing the hand-over (reproduced on production with a SELECT the same day). Now it walks the value:
-- object KEYS and string VALUES are redacted, at any depth, in objects and arrays; numbers, booleans and null are
-- returned as they are. And neither phone pattern starts on a digit that follows a digit or a dot ((?<![0-9.])), so the
-- decimals of an amount written as text ('135.000000000') are never a phone number either.
-- A number Stripe or a seat stores as a JSON NUMBER is not a contact detail here; fn_handoff_summary drops contact KEYS
-- (mail, phone, mobile, whatsapp ...) before this runs.
create or replace function public.fn_handoff_redact_text(p text)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select regexp_replace(regexp_replace(
           regexp_replace(p, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}', '[email]', 'g'),
           '(?<![0-9.])([+]|\m00)[0-9][0-9 -]{5,}[0-9]', '[phone]', 'g'),
           '(?<![0-9.])\m0[1-9]([ -]?[0-9]){7,8}\M', '[phone]', 'g');
$fn$;

revoke execute on function public.fn_handoff_redact_text(text) from public, anon, authenticated;

create or replace function public.fn_handoff_redact(p jsonb)
returns jsonb
language plpgsql
immutable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v jsonb;
begin
  case jsonb_typeof(p)
    when 'object' then
      select coalesce(jsonb_object_agg(public.fn_handoff_redact_text(e.key), public.fn_handoff_redact(e.value)), '{}'::jsonb)
        into v from jsonb_each(p) e;
    when 'array' then
      select coalesce(jsonb_agg(public.fn_handoff_redact(e.value) order by e.n), '[]'::jsonb)
        into v from jsonb_array_elements(p) with ordinality e(value, n);
    when 'string' then
      v := to_jsonb(public.fn_handoff_redact_text(p #>> '{}'));
    else
      v := p;   -- number, boolean, null: never text to the patterns
  end case;
  return v;
end $fn$;

revoke execute on function public.fn_handoff_redact(jsonb) from public, anon, authenticated;

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
  v_context  text;
  v_decision text;
  v_asks     jsonb;
  v_deadline timestamptz;
  v_dsource  text;
  v_row      jsonb;
  v_col      text;
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
     -- 1013 review: no contact detail is a fact; a key naming one is dropped (its value is redacted below too)
     and e.key !~* '(mail|phone|mobile|whatsapp|msisdn|tel|contact|address|wa_?id|number$)'
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

  -- 1013: CONTEXT. One sentence a colleague reads first.
  v_context := format('%s handed %s on %s#%s to %s.%s Earlier on this case: %s action(s), %s remembered decision(s).',
    coalesce(v_from, 'a seat'), v_type, v_table, v_id, p_agent,
    case when v_facts = '{}'::jsonb then '' else ' Facts: ' || left(v_facts::text, 400) || '.' end,
    jsonb_array_length(v_tried), jsonb_array_length(v_cases));

  -- 1013: DECISION. What the sender decided.
  v_decision := coalesce(
    nullif(btrim(d->>'decision'), ''),
    (select left(m.decision, 300) from public.seat_case_memory m
      where m.source_table = v_table and m.source_id = v_id and m.seat = v_from
        and nullif(btrim(m.decision), '') is not null order by m.id desc limit 1),
    case when v_from is not null
         then v_from || ' decided this needs ' || p_agent || ': ' || (v_needed->>'ask') end);

  -- 1013: OPEN ASKS. What the receiver must do, as a list.
  select coalesce(jsonb_agg(distinct q), '[]'::jsonb) into v_asks
    from (select v_needed->>'ask' as q
          union all select jsonb_array_elements_text(case when jsonb_typeof(d->'asks') = 'array' then d->'asks' else '[]'::jsonb end)
          union all select d->>'question') s
   where nullif(btrim(q), '') is not null;

  -- 1013: DEADLINE. The sender's own date, the conversation's window, the case's due date, else 24 h.
  begin
    v_deadline := nullif(coalesce(d->>'deadline', d->>'due_at'), '')::timestamptz;
    if v_deadline is not null then v_dsource := 'set by ' || coalesce(v_from, 'the sender'); end if;
  exception when others then v_deadline := null;
  end;
  if v_deadline is null and k.reply_within is not null then
    v_deadline := now() + k.reply_within; v_dsource := 'reply window of ' || v_type || ' (' || k.reply_within::text || ')';
  end if;
  if v_deadline is null and v_table ~ '^[a-z_][a-z0-9_]*$'
     and exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = v_table and c.column_name = 'id') then
    begin
      execute format('select to_jsonb(t) from public.%I t where t.id::text = $1 limit 1', v_table) into v_row using v_id;
      foreach v_col in array array['due_at','deadline','due_date','response_due_at','expires_at'] loop
        if v_row ? v_col and nullif(v_row->>v_col, '') is not null then
          v_deadline := (v_row->>v_col)::timestamptz; v_dsource := 'case due date ' || v_table || '.' || v_col; exit;
        end if;
      end loop;
    exception when others then v_deadline := null;
    end;
  end if;
  if v_deadline is null then
    v_deadline := now() + interval '24 hours'; v_dsource := 'default handoff window (24 hours)';
  end if;

  if nullif(btrim(v_context), '') is null or nullif(btrim(v_decision), '') is null
     or jsonb_array_length(v_asks) = 0 or v_deadline is null then
    raise exception 'handoff % on %#% cannot state its context, decision, open asks and deadline - refused', v_type, v_table, v_id;
  end if;

  -- 1013 review: the note is read by other seats and by a model; no e-mail address or phone number lands
  -- in it, whichever field carried it (a fact, the question, the decision, the title).
  return public.fn_handoff_redact(jsonb_build_object(
    'context', v_context,
    'decision', v_decision,
    'open_asks', v_asks,
    'deadline', v_deadline,
    'deadline_source', v_dsource,
    'known', jsonb_build_object('case', v_table || '#' || v_id, 'conversation', v_type,
                                'from', v_from, 'to', p_agent, 'means', k.meaning, 'facts', v_facts),
    'tried', jsonb_build_object('actions', v_tried, 'case_memory', v_cases),
    'needed', v_needed,
    'evidence', coalesce(v_links, '[]'::jsonb),
    'built_by', 'fn_handoff_summary'));
end $fn$;

-- CREATE OR REPLACE keeps the ACL #1072 revoked; repeated so the file stands alone.
revoke execute on function public.fn_handoff_summary(jsonb, text, text, text, text, text, bigint) from public, anon, authenticated;

-- 1013 review: INSERT builds the note and refuses one that cannot be stated. An UPDATE of an older row
-- (17,287 exist; most have no four-field note) must NEVER fail because of the note: the builder is tried,
-- and if it refuses, the row gets a plain note from its own columns, marked legacy, so both CHECKs hold.
create or replace function public.trg_handoff_carries_its_note()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_note jsonb;
begin
  if tg_op = 'INSERT' then
    v_note := public.fn_handoff_summary(new.detail, new.agent, new.target_table, new.target_id,
                                        new.title, new.recommendation, new.id);
  else
    begin
      v_note := public.fn_handoff_summary(new.detail, new.agent, new.target_table, new.target_id,
                                          new.title, new.recommendation, new.id);
    exception when others then
      v_note := coalesce(new.detail->'summary', '{}'::jsonb) || public.fn_handoff_redact(jsonb_build_object(
        'context', coalesce(new.title, 'handoff ' || new.id) || ' (note rebuilt from the row; the case could not be read)',
        'decision', coalesce(new.detail->>'from', 'the sender') || ' handed this to ' || new.agent,
        'open_asks', jsonb_build_array(coalesce(nullif(btrim(new.recommendation), ''), new.title, 'handoff ' || new.id)),
        'deadline', coalesce(new.created_at, now()) + interval '24 hours',
        'deadline_source', 'legacy row: created_at + 24 hours',
        'legacy', true,
        'known', coalesce(new.detail->'summary'->'known', '{}'::jsonb),
        'tried', coalesce(new.detail->'summary'->'tried', '{}'::jsonb),
        'needed', coalesce(new.detail->'summary'->'needed', '{}'::jsonb),
        'evidence', coalesce(new.detail->'summary'->'evidence', '[]'::jsonb)));
    end;
  end if;
  new.detail := coalesce(new.detail, '{}'::jsonb) || jsonb_build_object('summary', v_note);
  return new;
end $fn$;

revoke execute on function public.trg_handoff_carries_its_note() from public, anon, authenticated;

create or replace trigger a01_handoff_carries_its_note
  before insert or update on public.agent_actions
  for each row
  when (new.kind = 'handoff'
        and not (coalesce(new.detail->'summary', '{}'::jsonb) ?& array['known','tried','needed','evidence',
                                                                       'context','decision','open_asks','deadline']))
  execute function public.trg_handoff_carries_its_note();

-- trg_handoff_carries_its_note rebuilt the note only when there was none; now it also replaces an
-- incomplete one (the || on 'summary' overwrites the key).
alter table public.agent_actions drop constraint if exists agent_actions_handoff_note_states_four_fields;
alter table public.agent_actions add constraint agent_actions_handoff_note_states_four_fields
  check (kind <> 'handoff'
         or coalesce(detail->'summary', '{}'::jsonb) ?& array['context','decision','open_asks','deadline'])
  not valid;

-- The citation the receiver's answer carries.
create or replace function public.fn_handoff_note_citation(p_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object('handoff_id', a.id, 'read_by', a.agent, 'read_at', now(),
                            'deadline', a.detail->'summary'->'deadline',
                            'open_asks', a.detail->'summary'->'open_asks',
                            'on_time', now() <= (a.detail->'summary'->>'deadline')::timestamptz)
    from public.agent_actions a
   where a.id = p_id and a.kind = 'handoff';
$fn$;

revoke execute on function public.fn_handoff_note_citation(bigint) from public, anon, authenticated;

-- fn_seat_handoff_act cites the note too (1013); its body lives in its one owner,
-- the_it_engineer_closes_every_loop_it_opens.sql (handoff_kinds_are_data.test.mjs), and was applied from here on 19 Oct 2026.

create or replace function public.fn_seat_handoff_complete(p_id bigint, p_evidence jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare a public.agent_actions; v_ev jsonb := coalesce(p_evidence, '{}'::jsonb);
begin
  -- 1013: every way a handoff closes, the answer cites the note.
  if jsonb_typeof(v_ev) = 'object' and not v_ev ? 'cites_note' then
    v_ev := v_ev || jsonb_build_object('cites_note', public.fn_handoff_note_citation(p_id));
  end if;
  update public.agent_actions
     set status = 'done', decided_at = now(), decided_by = agent,
         evidence = v_ev,
         detail = detail - 'awaiting'
   where id = p_id and kind = 'handoff' and status <> 'done'
  returning * into a;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no open handoff ' || p_id); end if;
  perform public.fn_seat_handoff_event(p_id, 'done');

  if a.detail->>'type' = 'refund.remediate' and (a.detail->>'refund_id') is not null then
    perform public.fn_ceo_refund_loop_advance((a.detail->>'refund_id')::bigint);
  elsif a.detail->>'type' = 'incident.fix' and (a.detail->>'incident_id') is not null then
    perform public.fn_ceo_incident_advance((a.detail->>'incident_id')::bigint);
  end if;
  return jsonb_build_object('ok', true, 'handoff_id', p_id, 'type', a.detail->>'type');
end $function$;

revoke execute on function public.fn_seat_handoff_complete(bigint, jsonb) from public, anon, authenticated;

-- THE MEASUREMENT, public.fn_handoff_citation_gaps(p_since): handoffs closed since p_since whose note has the four fields
-- and whose answer cites no note. Its canonical definition is
-- scripts/sql/a_handoff_closes_only_when_its_receiver_cites_the_note_or_says_why_not.sql (MANIFEST line 2149, which
-- superseded the one this file held; removed here 13 Nov 2026 so a re-apply cannot revert it).
