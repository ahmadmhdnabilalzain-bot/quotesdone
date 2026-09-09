-- THE WIDGET IS THE SUPPORT SEAT, AND THERE IS NOBODY TO ESCALATE TO.
--
-- Two founder instructions, both open, both about the same seat.
--
--   (16) "The website chat widget is basically the customer support agent, they are not two
--        different things. When someone is on the home page, he didn't sign in as a customer or
--        supplier, then it's always the customer support agent. And once someone is registered,
--        then it's the other guy, the sales engineer who is responsible because he has all the
--        data."
--
--   (17) "Escalate to human, that is something that doesn't exist. We don't have escalation to
--        human. As I told you before, IT agent is the only one who reports to me directly."
--
-- WHAT WAS MEASURED BEFORE THIS FILE:
--
--   org_role.customer_support.responsibilities described a MAIL-PLUMBING OPERATOR -- "Own every
--   lifecycle message from queue to inbox: outbox depth, retries, dead letters and the digest, and
--   deliverability, sender reputation, bounces, suppressions..." -- and forbade it from "writing
--   message content". That row was last written on 7 September. The ruling that the widget IS this
--   seat is 8-9 September. So the seat's own definition forbade the job it actually does all day:
--   it answers strangers on the home page, in English and in Arabic, which is writing message
--   content. A seat whose charter contradicts its work cannot be audited against its charter.
--
--   handoff_targets was {communications_manager}. There is no communications_manager. There are
--   five roles and that is not one of them, so the seat's only recorded hand-off went to nobody.
--   The real hand-off is the founder's own line: a signed-in customer or supplier belongs to the
--   sales_engineer.
--
--   site_assistant set an `escalated` flag by running a REGEX over its OWN outgoing text --
--   /\/contact\/|management@quotesdone\.com|931 9355/ -- and wrote it to assistant_logs. 8 of 16
--   logged conversations came back true. Nothing read the column. Nothing was notified. It was not
--   measuring escalation; it was measuring whether the assistant happened to type a phone number,
--   which the prompt tells it to do on every question it cannot answer. And per (17) the thing it
--   claimed to measure does not exist in this company at all.
--
-- WHAT THIS FILE DOES:
--
--   1. Rewrites the seat's definition to describe the job it actually holds.
--   2. Puts the surface rule in ONE routine, fn_seat_for_surface, so "who owns this caller" is a
--      query and not a sentence repeated in three call sites.
--   3. Replaces the escalated fiction with the two outcomes that are real -- a recorded knowledge
--      gap that improves the corpus, and a report to the CEO -- and makes assistant_logs record
--      which seat answered, so the split the founder described can be MEASURED rather than assumed.
--
-- WHAT THIS FILE DELIBERATELY DOES NOT DO: it does not invent a support_knowledge_gap table.
-- sales_knowledge_gap already is the estate's gap register, keyed on the normalised question, and
-- the founder's own ruling of 8 Sep is that support and sales read ONE combined knowledge body. Two
-- registers for one corpus would mean the same unanswered question opens two tasks depending on
-- which door it came through. The seat that owns each gap is recorded on the org_tasks row, which
-- is where ownership already lives.

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 1. THE SEAT'S DEFINITION MATCHES ITS JOB.
--
-- The deliverability duties are KEPT, because function_owner still gives this seat send_outbox,
-- email_cron, wa_inbound, send_whatsapp, resend_inbound, inbound_email and email_triage -- it
-- genuinely does own the pipes. What is removed is the claim that the pipes are ALL it owns, and
-- the prohibition on writing the words that go through them.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
update public.org_role set
  responsibilities =
    'Answer anyone who is NOT signed in. This seat IS the website chat widget on quotesdone.com, '
    || 'and it is the same seat on WhatsApp and on inbound email: one agent, three doors. It '
    || 'answers in English and in Arabic, in the language the person wrote in, grounded in company '
    || 'knowledge -- the approved FAQ, the support pack and the operations corpus -- and never from '
    || 'invention. A figure it cannot cite it does not state. The moment a caller is signed in as a '
    || 'customer or a supplier they stop being this seat''s: they belong to the sales_engineer, who '
    || 'holds their data. It also owns the record of contact attempts to suppliers '
    || '(supplier_response_watch), which is the evidence every non-response refund rests on: an '
    || 'attempt that was never recorded is an attempt that cannot be proved. And it keeps the pipes '
    || 'those messages travel through -- outbox depth, retries, dead letters, deliverability, '
    || 'sender reputation, bounces, suppressions and opt-outs -- because a message that is never '
    || 'sent and a message that lands in spam are the same failure as a message that was never '
    || 'written.',
  owned_decisions = array[
    'what to answer an anonymous visitor, in English or Arabic, and which company knowledge grounds it',
    'when it does not have a sourced answer, and must record a knowledge gap instead of guessing',
    'when a signed-in caller is handed to the sales_engineer',
    'whether a supplier was actually contacted, and what the record of that attempt says',
    'outbox handling, retries and dead letters',
    'suppression and opt-out enforcement',
    'sender reputation actions'
  ],
  forbidden_decisions = array[
    'ESCALATING TO A HUMAN -- the founder ruled on 9 Sep 2026 that escalation to a human does not exist. There is no queue, no rota and no person waiting. When it cannot answer it records a knowledge gap; when a decision is needed it reports to the CEO.',
    'emailing the founder directly, under any circumstance -- only the it_engineer reports to him',
    'answering a signed-in customer or supplier about their own account -- that is the sales_engineer''s, who holds the data',
    'stating a fee, a date or a policy it cannot cite from company knowledge',
    'promising that a person will follow up, or that a message has been passed to someone',
    'sending to a suppressed or opted-out recipient'
  ],
  handoff_targets    = array['sales_engineer'],
  escalation_targets = array['ceo'],
  updated_at = now()
where role_id = 'customer_support';

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 2. THE SURFACE RULE, IN ONE PLACE.
--
-- Not SECURITY DEFINER on purpose: it reads one row of org_role and grants no access the caller did
-- not already have. A definer routine here would be privilege with nothing to spend it on.
--
-- It RAISES rather than returning null for an unknown surface or a retired seat. A null seat would
-- flow straight into assistant_logs.seat and read exactly like a seat that answered and was not
-- recorded -- the same column saying two different things is how the escalated flag got away with
-- being wrong for a month.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_seat_for_surface(p_signed_in boolean, p_surface text)
returns text
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_surface text := lower(btrim(coalesce(p_surface, '')));
  v_seat    text;
begin
  -- The doors a caller can arrive through. Adding one is a deliberate edit here, which is the
  -- point: a typo'd surface at a call site is a raise, not a silently different answer.
  if v_surface not in ('website_widget','whatsapp','inbound_email','customer_portal','supplier_portal') then
    raise exception 'fn_seat_for_surface: unknown surface %. Known surfaces are website_widget, whatsapp, inbound_email, customer_portal, supplier_portal.', coalesce(p_surface, '(null)');
  end if;

  -- THE FOUNDER'S RULE, AND NOTHING ELSE. Not signed in -> customer_support. Signed in as a
  -- customer or a supplier -> sales_engineer, "because he has all the data". The surface does NOT
  -- move the decision: an anonymous visitor reading /portal is still a stranger on the website and
  -- is still Support's. The surface is carried so it can be recorded beside the answer.
  v_seat := case when coalesce(p_signed_in, false) then 'sales_engineer' else 'customer_support' end;

  perform 1 from public.org_role where role_id = v_seat and status = 'active';
  if not found then
    raise exception 'fn_seat_for_surface: seat % is not an active role. The rule cannot route a caller to a seat that does not exist.', v_seat;
  end if;

  return v_seat;
end
$function$;

comment on function public.fn_seat_for_surface(boolean, text) is
  'Founder ruling 9 Sep 2026: not signed in -> customer_support (the website widget IS that seat); signed in as customer or supplier -> sales_engineer. The rule lives here so it is one fact, not three copies.';

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 3. THE WIDGET'S LOG RECORDS WHO ANSWERED AND WHAT HAPPENED.
--
-- escalated is DROPPED, not left in place unused. It held 8 true values out of 16 and every one of
-- them meant "the reply contained a phone number". Keeping a column whose name asserts something
-- the company does not do is how the next reader gets misled.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
alter table public.assistant_logs
  add column if not exists seat        text,
  add column if not exists answered    boolean,
  add column if not exists gap_task_id bigint;

alter table public.assistant_logs drop column if exists escalated;

comment on column public.assistant_logs.seat is
  'Which seat answered this turn, from fn_seat_for_surface. customer_support for an anonymous visitor, sales_engineer for a signed-in customer or supplier. Makes the founder''s split measurable.';
comment on column public.assistant_logs.answered is
  'True when the turn produced a grounded answer. False when it fell through to the contact-details fallback -- which is a refusal, not an answer, and is what gap_task_id then points at.';
comment on column public.assistant_logs.gap_task_id is
  'org_tasks row opened by fn_support_knowledge_gap when the seat could not source an answer. There is no escalation to a human; this is what happens instead.';

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 4. WHAT HAPPENS WHEN SUPPORT CANNOT ANSWER.
--
-- Copied from fn_sales_assist's fallback, which the founder already accepted: the question is kept
-- word for word, counted, and OWNED by a task. Same register, same idempotency on the normalised
-- question, same priority-follows-demand rule. The difference is the seat on the task.
--
-- The visitor sentence returned here is the honest one. It does not say a person will follow up,
-- because no mechanism does that. It gives the published direct line -- which is real, answered,
-- and printed on /contact/ -- and says plainly that the question has been recorded.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_support_knowledge_gap(p_question text, p_refusal text, p_surface text default 'website_widget')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_norm text;
  v_gap  public.sales_knowledge_gap%rowtype;
  v_task bigint;
  v_asks int;
begin
  if coalesce(btrim(p_question), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'empty_question');
  end if;

  v_norm := left(lower(regexp_replace(btrim(p_question), '\s+', ' ', 'g')), 400);
  select * into v_gap from public.sales_knowledge_gap where question_norm = v_norm;

  if not found then
    insert into public.org_tasks (title, detail, status, tier, action_class, assigned_agent,
                                  priority, requires_evidence, needs_founder)
    values (
      left('Answer an unanswered support question: ' || btrim(p_question), 160),
      'Someone who was NOT signed in asked this on the ' || coalesce(nullif(btrim(p_surface), ''), 'website_widget')
        || ' and Customer Support could not source an answer from company knowledge.' || E'\n\n'
        || 'QUESTION: ' || btrim(p_question) || E'\n'
        || 'REFUSAL: ' || coalesce(nullif(btrim(p_refusal), ''), 'no_grounded_answer') || E'\n\n'
        || 'THERE IS NO ESCALATION TO A HUMAN -- founder ruling, 9 Sep 2026. This task IS what '
        || 'happens instead, and it is the only thing that happens.' || E'\n\n'
        || 'DONE MEANS: the answer exists in a corpus fn_support_corpus_search reads (company_faq, '
        || 'support_knowledge, ops_knowledge) and this question returns it. Then set '
        || 'sales_knowledge_gap.status to knowledge_added.',
      'assigned', 'advisory', 'knowledge_gap', 'customer_support', 3, true, false)
    returning id into v_task;

    insert into public.sales_knowledge_gap (question_norm, question, refusal, nearest_corpus, task_id)
    values (v_norm, left(btrim(p_question), 2000),
            coalesce(nullif(btrim(p_refusal), ''), 'no_grounded_answer'),
            'support_corpus', v_task);
    v_asks := 1;
  else
    v_task := v_gap.task_id;
    v_asks := v_gap.asks + 1;
    update public.sales_knowledge_gap
       set asks = asks + 1, last_asked_at = now(),
           refusal = coalesce(nullif(btrim(p_refusal), ''), refusal)
     where id = v_gap.id;
    -- Asked repeatedly is the definition of urgent, exactly as on the sales side.
    update public.org_tasks
       set priority = least(9, greatest(priority, 3 + v_gap.asks)), updated_at = now()
     where id = v_task and status not in ('done', 'cancelled');
  end if;

  return jsonb_build_object(
    'ok', true, 'task_id', v_task, 'asks', v_asks,
    'reply_en', 'I do not have a sourced answer to that yet, and I will not guess at it. I have '
      || 'recorded your question exactly as you asked it so it gets answered properly. If you need '
      || 'it now, call or WhatsApp +971 50 931 9355 (Sun-Thu, 9am-6pm GST) or email '
      || 'management@quotesdone.com.',
    'reply_ar', 'ليس لدي إجابة موثقة على ذلك حتى الآن، ولن أخمّن. لقد سجّلت سؤالك كما كتبته '
      || 'تماماً ليتم الرد عليه بشكل صحيح. وإذا كنت بحاجة إليه الآن، يمكنك الاتصال أو المراسلة عبر '
      || 'واتساب:' || E'\n' || '+971 50 931 9355' || E'\n' || 'أو البريد الإلكتروني:' || E'\n'
      || 'management@quotesdone.com');
end
$function$;

revoke execute on function public.fn_support_knowledge_gap(text, text, text) from public;

comment on function public.fn_support_knowledge_gap(text, text, text) is
  'What Customer Support does instead of escalating to a human: keeps the question, counts it, and opens an org_tasks row owned by customer_support. Shares sales_knowledge_gap because support and sales read one combined corpus.';

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 5. PROBES. Each one cleans up after itself, so a later assertion failing rolls back the whole
--    file rather than leaving fixture rows behind.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
do $probe$
declare
  v_anon   text;
  v_signed text;
  v_bad    boolean := false;
  v_gap    jsonb;
  v_task   bigint;
  v_again  jsonb;
  v_prio   smallint;
  v_row    public.org_role%rowtype;
begin
  -- 5a. the rule
  v_anon   := public.fn_seat_for_surface(false, 'website_widget');
  v_signed := public.fn_seat_for_surface(true,  'website_widget');
  if v_anon <> 'customer_support' then
    raise exception 'PROBE FAILED: an anonymous visitor routed to %, expected customer_support', v_anon;
  end if;
  if v_signed <> 'sales_engineer' then
    raise exception 'PROBE FAILED: a signed-in caller routed to %, expected sales_engineer', v_signed;
  end if;
  if public.fn_seat_for_surface(false, 'whatsapp') <> 'customer_support'
     or public.fn_seat_for_surface(true, 'supplier_portal') <> 'sales_engineer' then
    raise exception 'PROBE FAILED: the rule is not surface-independent';
  end if;
  begin
    perform public.fn_seat_for_surface(false, 'carrier pigeon');
  exception when others then v_bad := true;
  end;
  if not v_bad then
    raise exception 'PROBE FAILED: an unknown surface was accepted instead of raising';
  end if;

  -- 5b. the seat's row
  select * into v_row from public.org_role where role_id = 'customer_support';
  if v_row.responsibilities ilike '%queue to inbox%' then
    raise exception 'PROBE FAILED: the seat still describes itself as a mail-plumbing operator';
  end if;
  if 'writing message content' = any (v_row.forbidden_decisions) then
    raise exception 'PROBE FAILED: the seat is still forbidden from writing message content';
  end if;
  if not (v_row.escalation_targets = array['ceo']) then
    raise exception 'PROBE FAILED: escalation_targets is %, expected {ceo}', v_row.escalation_targets;
  end if;
  if not (v_row.handoff_targets = array['sales_engineer']) then
    raise exception 'PROBE FAILED: handoff_targets is %, expected {sales_engineer}', v_row.handoff_targets;
  end if;

  -- 5c. the escalated fiction is gone from the log
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'assistant_logs' and column_name = 'escalated') then
    raise exception 'PROBE FAILED: assistant_logs.escalated still exists';
  end if;

  -- 5d. the knowledge-gap path, written and then removed. The question is deliberately absurd so it
  --     cannot collide with a real one already in the register.
  v_gap := public.fn_support_knowledge_gap(
    'zz probe do you deliver quotations to the sea floor of the arabian gulf',
    'probe_only', 'website_widget');
  if (v_gap->>'ok')::boolean is not true then
    raise exception 'PROBE FAILED: the gap path refused: %', v_gap;
  end if;
  v_task := (v_gap->>'task_id')::bigint;
  if v_task is null then
    raise exception 'PROBE FAILED: no task was opened';
  end if;
  if not exists (select 1 from public.org_tasks
                  where id = v_task and assigned_agent = 'customer_support'
                    and action_class = 'knowledge_gap' and status = 'assigned') then
    raise exception 'PROBE FAILED: task % is not an assigned customer_support knowledge_gap', v_task;
  end if;
  if v_gap->>'reply_en' ilike '%someone will%' or v_gap->>'reply_en' ilike '%get back to you%' then
    raise exception 'PROBE FAILED: the visitor reply promises a human follow-up';
  end if;

  -- asked twice: one task, higher priority
  v_again := public.fn_support_knowledge_gap(
    'ZZ PROBE  do you deliver quotations to the sea floor of the ARABIAN GULF ',
    'probe_only', 'whatsapp');
  if (v_again->>'task_id')::bigint <> v_task then
    raise exception 'PROBE FAILED: the same question opened a second task (% then %)', v_task, v_again->>'task_id';
  end if;
  if (v_again->>'asks')::int <> 2 then
    raise exception 'PROBE FAILED: asks is %, expected 2', v_again->>'asks';
  end if;
  select priority into v_prio from public.org_tasks where id = v_task;
  if v_prio <> 4 then
    raise exception 'PROBE FAILED: priority did not follow demand (got %, expected 4)', v_prio;
  end if;

  -- clean up: the register and the task must be exactly as they were before this probe ran
  delete from public.sales_knowledge_gap where task_id = v_task;
  delete from public.org_tasks where id = v_task;
  if exists (select 1 from public.org_tasks where id = v_task) then
    raise exception 'PROBE FAILED: the probe task could not be removed';
  end if;

  raise notice 'PROBES PASSED: anonymous -> %, signed in -> %; unknown surface raises; the seat describes its real job; assistant_logs.escalated is gone; the gap path opened task % owned by customer_support, counted a second ask, and was cleaned up.',
    v_anon, v_signed, v_task;
end
$probe$;
