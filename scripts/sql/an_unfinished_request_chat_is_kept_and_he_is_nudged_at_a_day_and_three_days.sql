-- AN UNFINISHED REQUEST CHAT IS KEPT, AND HE IS NUDGED AT A DAY AND AT THREE DAYS.
-- Seat: sales_engineer. Agent: CUSTOMER_W2 (wave 2 of the real-company hole hunt, 16 Nov 2026; scratchpad holes/CUSTOMER.md item 7).
--
-- MEASURED on origin/main 27969740b and production (SELECT, 16 Nov 2026: inquiry_intake holds 1 'ready' and 3 'expired'): a
-- request chat he left half-answered, or complete and never sent, was never mentioned to him again; at 30 days
-- fn_sales_engineer_expires_abandoned_intakes marks it expired with no message. A salesperson calls: "you are two answers from
-- getting quotes".
--
-- WHAT THIS CHANGES
--   1. inquiry_intake gains nudged_24h_at and nudged_72h_at.
--   2. fn_sales_engineer_nudges_unfinished_requests (the hourly duty sales_engineer.unfinished_requests): a draft in needs_info
--      or ready that he has not touched for 24 hours gets one nudge, and at 72 hours one more, in his registered language, on
--      his sign-in e-mail (the account's own address; fn_wa_fanout makes the WhatsApp twin when he confirmed a WhatsApp number,
--      the channel he consented to). It says what is left: "N questions left" from the draft's own missing list, or "complete:
--      one tap sends it". A nudge is sent once per pause: if he comes back and leaves again, the clock starts again. Nothing
--      older than 7 days is nudged (the first run after the apply does not write to old drafts). A fixture is nudged only by a
--      probe that asked for fixtures (qd.duty_fixtures), a real draft only by the real duty; a demo address never.
--   The resume itself is inquiry_intake (./resume.ts): his newest open draft is found by his signed-in address on any return.
-- Every new routine: SECURITY DEFINER, search_path pinned, EXECUTE revoked from public, anon and authenticated.
-- Probe: an_unfinished_request_chat_is_kept_and_he_is_nudged_at_a_day_and_three_days_probe.sql (local Postgres 16).
-- Deploy order: apply this file, then deploy inquiry_intake (independent: either order is safe).

alter table public.inquiry_intake add column if not exists nudged_24h_at timestamptz, add column if not exists nudged_72h_at timestamptz;
comment on column public.inquiry_intake.nudged_24h_at is
  'When the customer was last nudged a day after he left this request chat unfinished (fn_sales_engineer_nudges_unfinished_requests). Sales engineer, 16 Nov 2026.';

create or replace function public.fn_sales_engineer_nudges_unfinished_requests(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  x record; v_stage text; v_left int; v_ar boolean; v_what text; v_what_ar text; v_d jsonb; n24 int := 0; n72 int := 0; v_ids uuid[] := '{}';
begin
  for x in
    select it.id, it.status, it.category, it.missing, coalesce(it.updated_at, it.created_at) as touched, it.nudged_24h_at, it.nudged_72h_at,
           coalesce(c.email, it.email) as email, c.locale, coalesce(c.is_demo, false) or public.fn_is_demo_email(coalesce(c.email, it.email)) as demo
      from public.inquiry_intake it
      left join public.customers c on c.id = it.customer_id
     where it.status in ('needs_info', 'ready')
       and coalesce(it.updated_at, it.created_at) <= p_at - interval '24 hours'
       and coalesce(it.updated_at, it.created_at) > p_at - interval '7 days'
       and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(it.turns) = 'array' then it.turns else '[]'::jsonb end) t
                    where t ->> 'role' = 'user' and btrim(coalesce(t ->> 'text', '')) <> '')
       and coalesce(c.email, it.email, '') like '%@%'
     order by coalesce(it.updated_at, it.created_at) limit 200
  loop
    continue when x.demo is distinct from v_fx;
    -- once per pause: a nudge already sent since he last wrote is not sent again
    if x.touched <= p_at - interval '72 hours' then
      continue when x.nudged_72h_at is not null and x.nudged_72h_at >= x.touched;
      v_stage := '72h';
    else
      continue when x.nudged_24h_at is not null and x.nudged_24h_at >= x.touched;
      v_stage := '24h';
    end if;
    v_ar := x.locale = 'ar';
    v_left := case when x.status = 'ready' then 0 when jsonb_typeof(x.missing) = 'array' then jsonb_array_length(x.missing) else null end;
    v_what := coalesce(nullif(btrim(replace(coalesce(x.category, ''), '_', ' ')), ''), 'your');
    v_what_ar := coalesce(nullif(btrim(replace(coalesce(x.category, ''), '_', ' ')), ''), '');
    v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'intake_nudge', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', x.email, 'to_role', 'customer',
      'lang', case when v_ar then 'ar' else 'en' end,
      'subject', case
        when v_ar and x.status = 'ready' then 'طلبك مكتمل وجاهز للإرسال'
        when v_ar then 'طلبك بانتظار ' || case when v_left between 1 and 10 then v_left || ' من الإجابات' else 'بضع إجابات' end
        when x.status = 'ready' then 'Your request is complete: one tap sends it'
        else 'Your request is ' || case when v_left between 1 and 10 then v_left || ' answer' || case when v_left = 1 then '' else 's' end else 'a few answers' end || ' from going to suppliers' end,
      'body', case
        when v_ar and x.status = 'ready' then 'أهلًا،' || chr(10) || chr(10) || 'طلبك ' || case when v_what_ar <> '' then '(' || v_what_ar || ') ' else '' end
             || 'مكتمل وجاهز للإرسال إلى المورّدين، ولم يبقَ إلا أن تضغط «إرسال». افتح طلباتك على https://quotesdone.com/ar/me لتراجعه وترسله، وستجده حيث تركته.'
             || chr(10) || chr(10) || 'QuotesDone'
        when v_ar then 'أهلًا،' || chr(10) || chr(10) || 'طلبك ' || case when v_what_ar <> '' then '(' || v_what_ar || ') ' else '' end || 'محفوظ حيث تركته، '
             || case when v_left between 1 and 10 then 'وبقي ' || v_left || ' من الأسئلة' else 'وبقيت أسئلة قليلة' end
             || ' قبل أن نرسله إلى المورّدين المناسبين. افتح طلباتك على https://quotesdone.com/ar/me لتكمل من حيث توقفت.'
             || chr(10) || chr(10) || 'QuotesDone'
        when x.status = 'ready' then 'Hello,' || chr(10) || chr(10) || 'Your ' || v_what || ' request is complete and ready to go to suppliers: one tap on Send does it. '
             || 'Open your requests at https://quotesdone.com/me to check it and send it; it is exactly where you left it.' || chr(10) || chr(10) || 'QuotesDone'
        else 'Hello,' || chr(10) || chr(10) || 'Your ' || v_what || ' request is saved where you left it, '
             || case when v_left between 1 and 10 then v_left || ' question' || case when v_left = 1 then '' else 's' end else 'a few questions' end
             || ' from going to the right suppliers. Open your requests at https://quotesdone.com/me to carry on from where you stopped.' || chr(10) || chr(10) || 'QuotesDone' end,
      'dedupe_key', 'intake_nudge:' || x.id || ':' || v_stage || ':' || to_char(x.touched, 'YYYYMMDDHH24MISS'))));
    if v_stage = '72h' then
      update public.inquiry_intake set nudged_72h_at = p_at where id = x.id;
      n72 := n72 + 1;
    else
      update public.inquiry_intake set nudged_24h_at = p_at where id = x.id;
      n24 := n24 + 1;
    end if;
    v_ids := v_ids || x.id;
  end loop;
  return jsonb_build_object('nudged_24h', n24, 'nudged_72h', n72, 'fixtures', v_fx, 'ids', to_jsonb(v_ids));
end $fn$;
revoke execute on function public.fn_sales_engineer_nudges_unfinished_requests(timestamptz) from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.unfinished_requests', 'sales_engineer', interval '1 hour', 'fn_sales_engineer_nudges_unfinished_requests',
   'A request chat (inquiry_intake) left unfinished or unsent: one nudge at 24 hours and one at 72 hours, in the customer''s language, on his e-mail (and his confirmed WhatsApp), saying what is left.',
   'scripts/sql/an_unfinished_request_chat_is_kept_and_he_is_nudged_at_a_day_and_three_days.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

select case
  when not exists (select 1 from public.seat_duty where duty = 'sales_engineer.unfinished_requests') then 'PROBE FAILED: the duty is not registered'
  when has_function_privilege('anon', 'public.fn_sales_engineer_nudges_unfinished_requests(timestamptz)', 'execute') then 'PROBE FAILED: anon can run it'
  else 'PROBE OK' end as verdict;
