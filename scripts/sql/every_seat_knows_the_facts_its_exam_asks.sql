-- EVERY SEAT KNOWS THE FACTS ITS EXAM ASKS (ceo, 19 Nov 2026). Founder ledgers 889, 893, 894, 899, 1209 (every seat's knowledge
-- at a professional standard) and 1084 (the exam tests the real answer with the model on; a mistake leads to a real fix).
-- Assigned: ceo. Agent: exam-knowledge.
--
-- MEASURED (production SELECT, 19 Nov 2026). seat_exam_run 1 (week 15 Nov, run_tag exam:2026-11-15) asked 18 items, 3 a seat,
-- and passed 1 (accountant-exam-09). All 17 misses read graded_by 'code': the exact-phrase check, never the judge.
--   * THE JUDGE NEVER RAN. llm_attempt and ai_cost_log, fn knowledge_exam, 16 Nov 22:00Z-17 Nov 01:10Z: 18 calls from agent
--     it_engineer task routine_employee_reasoning (the wordings, ~1.9k prompt tokens each) and 0 from agent it_engineer task
--     knowledge_validation (the judge). supabase/functions/it_engineer/index.ts:448 calls the judge as task knowledge_validation
--     with no counterpart_model; model_policy.knowledge_validation.reviews_class is non-empty, so ai_gateway/handle.ts:156-161
--     answers 400 review_needs_counterpart before any model is chosen; parseJudge(null) is null and seat_exam.ts:133-134 keeps
--     the code verdict. Every paraphrase was therefore marked a miss.
--   * THE KNOWLEDGE IS THERE. Each of the 24 expected facts of the 18 items (the 19 missing among them) is, verbatim after
--     normalising case and punctuation, in the seat's own live store row its item names (accountant_knowledge, ceo_knowledge,
--     support_knowledge, it_engineer_knowledge, marketing_knowledge, sales_knowledge), runtime_index_eligible and embedded; and by gte-small distance to the item's q_vec
--     that row (or its @ar twin) ranks 1st-3rd in the seat's store for all 18 items. 0 knowledge rows are missing.
--   * CLASSIFICATION of the 19 missing facts:
--       grader too literal 13: accountant-03 "nothing is added for paying by card" (answer: "Paying by card adds nothing");
--         accountant-08 "everything the customer paid" ("the full reveal fee paid back, with no deduction") and "absorbs Stripe"
--         ("QuotesDone bears Stripe's processing cost"); customer_support-09 "no escalation to a human" ("there is no handoff to
--         a human"); customer_support-11 "not a request" ("does not qualify as a human-handoff request"); it_engineer-09
--         "otp_burst_per_prefix_hour 5" ("Five OTP requests ... within one hour"); it_engineer-10 "otp_block_hours 24" ("24 hours");
--         it_engineer-100 "full-length commit SHA" ("its full commit SHA"); marketing-10 "same competitor set" ("a fixed, named
--         competitor set ... the same competitors"); marketing-11 "Department of Economy and Tourism" ("DET"); sales_engineer-09
--         "effective 1 December 2021" ("came into force on 1 December 2021"); sales_engineer-10 "allowed for in the rate, not added
--         to the quantity" ("do not add ... to the measured quantity; allow for it in the rate"); sales_engineer-100 "stage
--         conversion" ("conversion between stages").
--       prompt gap 5: ceo-09 "counter-positioning" and ceo-10 "comparable, compliant quotations" (the rewording dropped the term of
--         art: "strategic powers" became "strategic capabilities", "really hiring QuotesDone to do" became "what service ... to
--         provide"; seat_exam.ts:62-65 REWORD_SYSTEM does not tell the model to keep named frameworks and terms); ceo-08 "Federal
--         Decree-Law No. 32 of 2021", marketing-09 "within an hour", marketing-10 "excess share of voice" (retrieved at rank 1-2,
--         left out by the synthesis: think/prompts.ts:52 asks the answer to cite sources, not to carry the named law, study or
--         figure that decides it).
--       knowledge gap 1: customer_support-10 "founder is then emailed". The pack row says it (founder_instruction 17, 721, 763,
--         status done: no escalation to a human, except a person who asks for one on WhatsApp or social media, when the founder is
--         emailed and carries on), but the seat's settled card knowledge/brief/seats/customer_support.md:59-60, which "overrides
--         any SOURCE", keeps "there is no escalation to a human" and drops the exception (scripts/kb/compile_brief.mjs:157-174
--         round-robin to CARD_BUDGET). The answer cited [brief] and said the person is not transferred. The fix is the card, in
--         code; no database row would outrank it, so none is added here.
--       retrieval gap 0.
--   * A false miss is not harmless here: fn_seat_exam_record opened 15 fixes and wrote 17 lessons for run 1 (agent_knowledge
--     source_ref seat_exam_fix:*), and next Sunday every open fix is re-asked first; with the judge still refused, each re-ask
--     is a code miss again and the tick would raise "fix_did_not_hold" for the 11 items the seat had answered correctly.
--
-- THE CHANGE (no knowledge row is added: every fact the exam asked is already in the store the seat reads).
--   1. seat_exam_run.unjudged: an answer the exact-phrase check missed and the judge gave no verdict on (graded_by 'code',
--      status 'answered', not pass) is counted as unjudged, not missed. It still fails (pass stays false; nothing is loosened),
--      but it opens no fix and writes no lesson, because no one has judged that the seat did not know.
--   2. fn_seat_exam_record: the rule above. 3. fn_it_engineer_seat_exam_tick: a run with most answers unjudged raises the IT
--      engineer's finding duty:seat_exam:judge:<week>; "fix did not hold" counts only a judged miss; the wording alarm leaves
--      unjudged answers out of its "could not word or answer" count.
--   4. The existing runs' missed/unjudged counters are recounted from their own seat_exam_asked rows (run 1: missed 17 -> 0,
--      unjudged 0 -> 17), so this week's finding names the judge outage. No ask, fix or lesson row is changed.
-- NEEDS CODE (not in this file): pass counterpart_model to the judge (seat_exam.ts:44,132 and it_engineer/index.ts:436-448);
--   keep terms of art in REWORD_SYSTEM (seat_exam.ts:62-65); keep a rule's exception with the rule in the card
--   (compile_brief.mjs:157-174) and recompile the brief.
-- APPLY: node scripts/apply_sql.mjs scripts/sql/every_seat_knows_the_facts_its_exam_asks.sql --apply --ddl, then append the file to
--   the END of scripts/sql/MANIFEST.txt and delete scripts/sql/pending/every_seat_knows_the_facts_its_exam_asks.txt. Before the
--   next run opens (Sunday 22 Nov 2026 08:00 Dubai). Independent of the code fix, which can deploy before or after.
-- ROLLBACK: re-apply fn_seat_exam_record and fn_it_engineer_seat_exam_tick from scripts/sql/the_company_runs_its_own_weekly_seat_exam.sql
--   (live md5 of fn_seat_exam_record before this file: e3a0b48080a42f003c24ee4d33ff8035, identical to that file), then
--   update seat_exam_run set missed = missed + unjudged; alter table seat_exam_run drop column unjudged.
-- prevented by: the verdict row at the end of this file (production: a SELECT only; it writes nothing and reaches no person).
set local lock_timeout = '3s';

-- ── 1. The count ────────────────────────────────────────────────────────────────────────────────────────────────────
alter table public.seat_exam_run add column if not exists unjudged int not null default 0;
comment on column public.seat_exam_run.unjudged is 'Answers the exact-phrase check missed and the model judge gave no verdict on (graded_by code): failed, but no fix and no lesson. scripts/sql/every_seat_knows_the_facts_its_exam_asks.sql.';

-- ── 2. One ask recorded: only a judged miss opens a fix ─────────────────────────────────────────────────────────────
create or replace function public.fn_seat_exam_record(p_run_id bigint, p_item_id text, p_seat text, p_wording text, p_answer text,
  p_model text, p_status text, p_pass boolean, p_graded_by text, p_missing text[])
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.seat_exam_run; f public.seat_exam_fix; v_asked bigint; v_fix bigint; v_lesson boolean := false;
        -- only an ANSWER that misses is a knowledge miss: a held or failed think() (model hold, deadline) opens no fix
        v_unjudged boolean := not coalesce(p_pass, false) and p_status = 'answered' and p_graded_by = 'code';
        -- and only a JUDGED miss: a code miss the judge never graded (seat_exam.ts keeps graded_by 'code' when the judge
        -- gave no verdict) is unjudged, recorded as such, and opens no fix and writes no lesson
        v_miss boolean := not coalesce(p_pass, false) and p_status = 'answered' and not v_unjudged;
begin
  select * into r from public.seat_exam_run where id = p_run_id for update;
  if not found then raise exception 'fn_seat_exam_record: no seat_exam_run %', p_run_id; end if;
  if not exists (select 1 from jsonb_array_elements(r.planned) e where e->>'item_id' = p_item_id and e->>'seat' = p_seat) then
    raise exception 'fn_seat_exam_record: % (%) is not planned in run %', p_item_id, p_seat, p_run_id;
  end if;
  if exists (select 1 from public.seat_exam_asked where run_tag = r.run_tag and item_id = p_item_id) then
    raise exception 'fn_seat_exam_record: % was already asked in run %', p_item_id, p_run_id;
  end if;
  select * into f from public.seat_exam_fix where item_id = p_item_id and status = 'open' order by id limit 1;
  insert into public.seat_exam_asked (run_tag, seat, item_id, wording, answer, model, status, pass, graded_by, missing, fix_id)
  values (r.run_tag, p_seat, p_item_id, coalesce(p_wording, ''), coalesce(p_answer, ''), p_model, p_status, coalesce(p_pass, false),
          p_graded_by, coalesce(p_missing, '{}'::text[]), f.id)
  returning id into v_asked;
  v_fix := f.id;
  if v_miss and f.id is null then
    insert into public.seat_exam_fix (seat, item_id, opened_run) values (p_seat, p_item_id, r.run_tag) returning id into v_fix;
    v_lesson := true;
  elsif f.id is not null and f.fix_ref is null and p_status = 'answered' and not v_unjudged then
    -- the fix was never made: make it now, at a pass too (seat_exam_fix may close only with a fix_ref, so an unmade
    -- fix that is then passed would otherwise stay open and be re-asked first every week for ever)
    v_lesson := true;
  elsif coalesce(p_pass, false) and f.fix_ref is not null then
    update public.seat_exam_fix set status = 'closed', closed_at = now(), closed_by_asked_id = v_asked where id = f.id;
  end if;
  update public.seat_exam_run set asked = asked + 1, passed = passed + (case when coalesce(p_pass, false) then 1 else 0 end),
         missed = missed + (case when v_miss then 1 else 0 end), no_wording = no_wording + (case when p_status = 'no_wording' then 1 else 0 end),
         unjudged = unjudged + (case when v_unjudged then 1 else 0 end)
   where id = r.id;
  return jsonb_build_object('asked_id', v_asked, 'fix_id', v_fix, 'lesson_needed', v_lesson, 'unjudged', v_unjudged);
end $fn$;
revoke execute on function public.fn_seat_exam_record(bigint, text, text, text, text, text, text, boolean, text, text[]) from public, anon, authenticated;

-- ── 3. The duty's alarm knows an unjudged answer from a miss ────────────────────────────────────────────────────────
create or replace function public.fn_it_engineer_seat_exam_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare pol jsonb := coalesce((select value from public.decision_policy where key = 'seat_exam_weekly'), '{}'::jsonb);
        v_dow int := coalesce((pol->>'dow')::int, 0); v_hour int := coalesce((pol->>'hour_dubai')::int, 8);
        v_deadline interval := make_interval(hours => coalesce((pol->>'deadline_hours')::int, 30));
        v_max_failed int := coalesce((pol->>'max_failed_posts')::int, 3);
        v_now_dxb timestamp := now() at time zone 'Asia/Dubai';
        v_week date; v_due timestamptz; r public.seat_exam_run; v_plan jsonb; v_ref text; v_key text; v_cred text; v_req bigint;
        v_items jsonb := '[]'::jsonb; v_action text := 'idle'; v_remaining int; x record;
begin
  if not pg_try_advisory_xact_lock(hashtext('qd.seat_exam_tick')) then
    return jsonb_build_object('busy', true);
  end if;
  -- 1. the answer of the last post
  update public.seat_exam_run s
     set http_status = coalesce(h.status_code, 0),
         http_error = case when h.status_code = 200 then null else left(coalesce(h.error_msg, h.content::text, 'no answer'), 500) end,
         failed_posts = case when h.status_code = 200 then 0 else s.failed_posts + 1 end
    from net._http_response h
   where h.id = s.request_id and s.http_status is null;
  -- a post with no answer after 10 minutes is a failed post
  update public.seat_exam_run set http_status = 0, http_error = 'no answer within 10 minutes', failed_posts = failed_posts + 1
   where status = 'open' and request_id is not null and http_status is null and posted_at < now() - interval '10 minutes';

  -- 2. this week's run: the exam day's date, due at its hour (Dubai)
  v_week := (v_now_dxb::date - ((extract(dow from v_now_dxb)::int - v_dow + 7) % 7));
  v_due := (v_week + make_interval(hours => v_hour)) at time zone 'Asia/Dubai';
  if now() >= v_due and not exists (select 1 from public.seat_exam_run where week = v_week) then
    -- a run of an earlier week still open is closed: a week's exam belongs to its week
    update public.seat_exam_run set status = 'failed', finished_at = now(), note = 'not finished within its week'
     where status = 'open' and week < v_week;
    v_plan := public.fn_seat_exam_plan(coalesce((pol->>'per_seat')::int, 3));
    insert into public.seat_exam_run (week, run_tag, planned, cap_aed, status, finished_at, note)
    values (v_week, 'exam:' || to_char(v_week, 'YYYY-MM-DD'), v_plan, coalesce((pol->>'week_aed_cap')::numeric, 10),
            case when jsonb_array_length(v_plan) = 0 then 'done' else 'open' end,
            case when jsonb_array_length(v_plan) = 0 then now() end,
            case when jsonb_array_length(v_plan) = 0 then 'no exam item is loaded' end);
    v_action := 'opened';
  end if;

  -- 3. the open run: finished, capped, failed, waiting on its post, or posted again
  select * into r from public.seat_exam_run where status = 'open' order by week desc limit 1;
  if found then
    v_remaining := jsonb_array_length(r.planned)
                   - (select count(*) from public.seat_exam_asked a where a.run_tag = r.run_tag
                        and exists (select 1 from jsonb_array_elements(r.planned) e where e->>'item_id' = a.item_id));
    update public.seat_exam_run set spent_aed = public.fn_seat_exam_spent(r.created_at) where id = r.id returning * into r;
    if v_remaining <= 0 then
      update public.seat_exam_run set status = 'done', finished_at = now() where id = r.id;   v_action := 'done';
    elsif r.spent_aed >= r.cap_aed then
      update public.seat_exam_run set status = 'capped', finished_at = now(),
             note = format('stopped at AED %s of its AED %s cap with %s item(s) unasked', r.spent_aed, r.cap_aed, v_remaining)
       where id = r.id;   v_action := 'capped';
    elsif r.failed_posts >= v_max_failed then
      update public.seat_exam_run set status = 'failed', finished_at = now(),
             note = format('%s posts running answered other than 200: %s', r.failed_posts, coalesce(r.http_error, '?'))
       where id = r.id;   v_action := 'failed';
    elsif r.request_id is not null and r.http_status is null then
      v_action := 'waiting';
    else
      select value into v_ref from public.app_secrets where key = 'project_ref';
      v_key := public.fn_gateway_client_key();
      select value into v_cred from public.app_secrets where key = 'cred_fn_it_engineer';
      if coalesce(v_ref, '') = '' or coalesce(v_key, '') = '' or coalesce(v_cred, '') = '' then
        -- a duty that cannot post has failed: fn_seat_duty_health shows it red
        raise exception 'fn_it_engineer_seat_exam_tick: project_ref, the gateway key or cred_fn_it_engineer is missing from app_secrets';
      end if;
      v_req := net.http_post(url := 'https://' || v_ref || '.supabase.co/functions/v1/it_engineer',
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key, 'apikey', v_key),
        body := jsonb_build_object('__secret', v_cred, 'action', 'seat_exam', 'run_id', r.id),
        timeout_milliseconds := 150000);
      update public.seat_exam_run set request_id = v_req, http_status = null, http_error = null, posted_at = now(), posts = posts + 1
       where id = r.id;
      v_action := 'posted';
    end if;
  end if;

  -- 4. the alarm
  for x in select * from public.seat_exam_run where week >= v_week - 7 order by week loop
    if x.status in ('capped', 'failed') then
      v_items := v_items || jsonb_build_object('item', 'run:' || x.week, 'owner_seat', 'it_engineer', 'subject', 'seat_exam',
        'title', 'The weekly seat exam of ' || to_char(x.week, 'DD Mon') || ' ended ' || x.status || ': ' || coalesce(x.note, '?'),
        'evidence', jsonb_build_object('run_id', x.id, 'asked', x.asked, 'planned', jsonb_array_length(x.planned), 'spent_aed', x.spent_aed,
                                       'cap_aed', x.cap_aed, 'http_error', x.http_error));
    elsif x.status = 'open' and x.created_at < now() - v_deadline then
      v_items := v_items || jsonb_build_object('item', 'late:' || x.week, 'owner_seat', 'it_engineer', 'subject', 'seat_exam',
        'title', 'The weekly seat exam of ' || to_char(x.week, 'DD Mon') || ' is not finished ' || extract(hour from v_deadline) || ' hours after it opened ('
                 || x.asked || ' of ' || jsonb_array_length(x.planned) || ' asked)',
        'evidence', jsonb_build_object('run_id', x.id, 'posts', x.posts, 'failed_posts', x.failed_posts, 'http_error', x.http_error));
    elsif x.status = 'done' and x.unjudged * 2 > greatest(x.asked, 1) then
      v_items := v_items || jsonb_build_object('item', 'judge:' || x.week, 'owner_seat', 'it_engineer', 'subject', 'seat_exam',
        'title', 'The weekly seat exam of ' || to_char(x.week, 'DD Mon') || ': the judge gave no verdict on ' || x.unjudged || ' of ' || x.asked
                 || ' answers (the exact-phrase check missed them); they are recorded as unjudged, not as misses',
        'evidence', jsonb_build_object('run_id', x.id, 'look_at', 'llm_attempt fn knowledge_exam agent it_engineer task knowledge_validation'));
    elsif x.status = 'done' and (x.asked - x.passed - x.missed - x.unjudged) * 2 > greatest(x.asked, 1) then
      v_items := v_items || jsonb_build_object('item', 'wording:' || x.week, 'owner_seat', 'it_engineer', 'subject', 'seat_exam',
        'title', 'The weekly seat exam of ' || to_char(x.week, 'DD Mon') || ' could not word or get an answer to ' || (x.asked - x.passed - x.missed - x.unjudged) || ' of ' || x.asked || ' questions',
        'evidence', jsonb_build_object('run_id', x.id, 'look_at', 'ai_cost_log fn knowledge_exam task routine_employee_reasoning'));
    end if;
  end loop;
  -- a fix that did not hold: the lesson is in the seat's knowledge and a later ask of the item still missed
  for x in select f.id, f.seat, f.item_id, f.fix_ref, k.created_at made_at
             from public.seat_exam_fix f
             join public.agent_knowledge k on 'agent_knowledge:' || k.id = f.fix_ref
            where f.status = 'open'
              and exists (select 1 from public.seat_exam_asked a where a.item_id = f.item_id and a.asked_at > k.created_at
                            and not a.pass and a.status = 'answered' and a.graded_by <> 'code') loop
    v_items := v_items || jsonb_build_object('item', 'fix_did_not_hold:' || x.item_id, 'owner_seat', 'it_engineer', 'subject', 'seat_exam',
      'title', 'The ' || x.seat || ' seat missed exam item ' || x.item_id || ' again after its lesson was written: the knowledge is there and '
               || 'the seat does not use it (retrieval or the prompt, an engineer session)',
      'evidence', jsonb_build_object('fix_id', x.id, 'fix_ref', x.fix_ref, 'lesson_written_at', x.made_at));
  end loop;
  return jsonb_build_object('action', v_action, 'week', v_week, 'run', (select to_jsonb(s) - 'planned' from public.seat_exam_run s where s.week = v_week),
                            'settle', public.fn_it_duty_settle('seat_exam', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_seat_exam_tick() from public, anon, authenticated;

-- ── 4. The runs already recorded, recounted from their own asks (no ask, fix or lesson row changes) ────────────────
update public.seat_exam_run r
   set missed   = c.missed,
       unjudged = c.unjudged,
       note     = concat_ws(' | ', nullif(r.note, ''), '19 Nov 2026: missed ' || r.missed || ' recounted as ' || c.missed || ' judged and '
                  || c.unjudged || ' unjudged from seat_exam_asked (every_seat_knows_the_facts_its_exam_asks.sql)')
  from (select a.run_tag,
               count(*) filter (where a.status = 'answered' and not a.pass and a.graded_by <> 'code')::int missed,
               count(*) filter (where a.status = 'answered' and not a.pass and a.graded_by = 'code')::int unjudged
          from public.seat_exam_asked a group by a.run_tag) c
 where c.run_tag = r.run_tag and (r.missed, r.unjudged) is distinct from (c.missed, c.unjudged);

-- ── PROBE: a verdict row, never a raise (this file holds DDL) ───────────────────────────────────────────────────────
with item as (select i.seat, i.item_id, unnest(i.expected_facts) fact, i.expected_entry_ids ids
                from public.seat_exam_item i
               where i.item_id in (select a.item_id from public.seat_exam_asked a where a.run_tag = 'exam:2026-11-15')),
live as (
  select 'accountant' seat, record_id, content txt from public.accountant_knowledge where runtime_index_eligible and embedding_gte is not null
  union all select 'ceo', record_id, body from public.ceo_knowledge where runtime_index_eligible and embedding_gte is not null
  union all select 'customer_support', record_id, body from public.support_knowledge where runtime_index_eligible and embedding_gte is not null
  union all select 'it_engineer', record_id, content from public.it_engineer_knowledge where runtime_index_eligible and embedding_gte is not null
  union all select 'marketing', record_id, content from public.marketing_knowledge where runtime_index_eligible and embedding_gte is not null
  union all select 'sales_engineer', record_id, content from public.sales_knowledge where runtime_index_eligible and embedding_gte is not null),
facts as (
  select i.item_id, i.fact,
         exists (select 1 from live l where l.seat = i.seat and l.record_id = any (i.ids)
                    and lower(regexp_replace(l.txt, '[\W_]+', '', 'g')) like '%' || lower(regexp_replace(i.fact, '[\W_]+', '', 'g')) || '%') known
    from item i),
chk as (
  select (select count(*) from facts) n_facts,
         (select string_agg(item_id || ' "' || fact || '"', '; ') from facts where not known) unknown,
         (select count(*) from public.seat_exam_asked where run_tag = 'exam:2026-11-15') asks,
         (select unjudged from public.seat_exam_run where run_tag = 'exam:2026-11-15') run1_unjudged,
         (select missed from public.seat_exam_run where run_tag = 'exam:2026-11-15') run1_missed,
         exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'seat_exam_run' and column_name = 'unjudged') col,
         (select prosrc from pg_proc where oid = 'public.fn_seat_exam_record(bigint,text,text,text,text,text,text,boolean,text,text[])'::regprocedure) rec_src,
         (select prosrc from pg_proc where oid = 'public.fn_it_engineer_seat_exam_tick()'::regprocedure) tick_src,
         (select coalesce(bool_or(has_function_privilege(r, 'public.fn_seat_exam_record(bigint,text,text,text,text,text,text,boolean,text,text[])', 'execute')
                              or has_function_privilege(r, 'public.fn_it_engineer_seat_exam_tick()', 'execute')), false)
            from unnest(array['anon', 'authenticated']) r) open_to_clients)
select case
  when not col then 'PROBE FAILED: seat_exam_run.unjudged is missing'
  when asks <> 18 then 'PROBE FAILED: run exam:2026-11-15 holds ' || asks || ' asks, measured 18 (this file must not change them)'
  when n_facts <> 24 then 'PROBE FAILED: the 18 items of run 1 carry ' || n_facts || ' expected facts, measured 24'
  when unknown is not null then 'PROBE FAILED: an expected fact is not in the seat''s live store row it names: ' || unknown
  when position('p_graded_by = ''code''' in rec_src) = 0 or position('unjudged = unjudged +' in rec_src) = 0
    then 'PROBE FAILED: fn_seat_exam_record does not set an unjudged answer apart'
  when position('''judge:'' || x.week' in tick_src) = 0 or position('a.graded_by <> ''code''' in tick_src) = 0
    then 'PROBE FAILED: fn_it_engineer_seat_exam_tick does not raise the judge finding or still counts an unjudged re-ask'
  when run1_unjudged <> 17 or run1_missed <> 0 then 'PROBE FAILED: run 1 recount reads missed ' || run1_missed || ', unjudged ' || run1_unjudged || ' (measured 0 and 17)'
  when open_to_clients then 'PROBE FAILED: anon or authenticated can execute a routine of this file'
  else 'PROBE OK: 24 of 24 expected facts of run 1 are in the seats'' live stores; run 1 reads 0 judged misses and 17 unjudged'
end as verdict
from chk;
