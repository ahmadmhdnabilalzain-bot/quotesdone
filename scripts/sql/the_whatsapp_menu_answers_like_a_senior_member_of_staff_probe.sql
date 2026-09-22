-- PROBE: THE WHATSAPP MENU ANSWERS LIKE A SENIOR MEMBER OF STAFF — the database half of instruction 763.
--
-- Assigned: customer_support. 22 Sep 2026. Pure probe: no DDL, nothing survives it. Run AFTER
-- the_whatsapp_menu_answers_like_a_senior_member_of_staff.sql, as ONE query through the Management API;
-- never applied. Every write happens inside a block that always raises, so all of it is rolled back —
-- including the pg_net request the follow-up queues (pg_net sends only committed rows) and the founder
-- alerts (notifications rows). Subjects are the reserved ZZ DEMO fixture numbers +971500000041/42, which
-- no account owns.
--
-- VERDICT: PROBE OK only if
--   1. fn_wa_menu_context gives the fixture no name and no requests (never an address, never a guess);
--   2. a first problem report opens a case AND a pending support.case_open handoff with the 24-hour
--      clock; a second report from the same number is ADDED to that case (same reference, two reports);
--   3. fn_support_case_close closes it, completes the handoff and returns the reporter's number;
--   4. fn_wa_human_request holds the conversation (fn_wa_human_hold true) with a pending handoff;
--   5. aged past 23 hours inside an open WhatsApp window, fn_wa_human_request_tick queues the follow-up,
--      releases the hold and marks the handoff followed up; fn_wa_human_request_close then closes it;
--   6. fn_faq_answer refuses a nearest neighbour the asker's words do not corroborate (FAQ 22's own
--      vector asked as "can i trust the suppliers on your site": cosine 1.0, one shared concept of three)
--      and accepts a corroborated one (FAQ 500's vector asked as "is it free for suppliers").
create temp table zz_probe_verdict (verdict text, detail text) on commit drop;
do $probe$
declare
  ctx jsonb; r1 jsonb; r2 jsonb; cl jsonb; hr jsonb; tk jsonb; hc jsonb; neg jsonb; pos jsonb;
  h_case public.agent_actions; h_case_after public.agent_actions; h_hum public.agent_actions; h_hum_after public.agent_actions;
  held_before boolean; held_after boolean; v_err text; v22 vector; v500 vector;
begin
  begin
    ctx := public.fn_wa_menu_context('whatsapp:+971500000041');
    r1 := public.fn_wa_problem_report('whatsapp:+971500000041', 'ZZ DEMO probe: the quote page did not load', 'en');
    r2 := public.fn_wa_problem_report('whatsapp:+971500000041', 'ZZ DEMO probe: still not loading', 'en');
    select * into h_case from public.agent_actions where kind = 'handoff' and target_id = 'support.case_open:' || (r1 ->> 'case_id');
    cl := public.fn_support_case_close(r1 ->> 'case_ref', 'ZZ DEMO probe fixed', 'probe');
    select * into h_case_after from public.agent_actions where id = h_case.id;

    hr := public.fn_wa_human_request('whatsapp:+971500000042', true, 'ZZ DEMO probe asks for a person', 'ZZ DEMO probe detail');
    held_before := public.fn_wa_human_hold('whatsapp:+971500000042');
    update public.agent_actions set created_at = now() - interval '24 hours' where id = (hr ->> 'handoff_id')::bigint;
    update public.wa_conversation set window_expires_at = now() + interval '1 hour' where phone_e164 = '971500000042';
    tk := public.fn_wa_human_request_tick();
    held_after := public.fn_wa_human_hold('whatsapp:+971500000042');
    select * into h_hum from public.agent_actions where id = (hr ->> 'handoff_id')::bigint;
    hc := public.fn_wa_human_request_close('+971500000042', 'probe', 'ZZ DEMO probe');
    select * into h_hum_after from public.agent_actions where id = (hr ->> 'handoff_id')::bigint;

    select embedding_gte into v22 from public.company_faq where id = 22;
    select embedding_gte into v500 from public.company_faq where id = 500;
    neg := public.fn_faq_answer('can i trust the suppliers on your site', 0.15, v22, 0.84);
    pos := public.fn_faq_answer('is it free for suppliers', 0.15, v500, 0.84);
    raise exception 'ZZPROBE rollback';
  exception when others then
    v_err := sqlerrm;
  end;
  insert into zz_probe_verdict
  select case when v_err = 'ZZPROBE rollback'
                   and ctx ->> 'name' is null and jsonb_array_length(ctx -> 'requests') = 0
                   and (r1 ->> 'appended')::boolean = false and h_case.status = 'pending'
                   and h_case.detail ->> 'type' = 'support.case_open' and (h_case.detail ->> 'sla_hours')::numeric > 0
                   and r2 ->> 'case_ref' = r1 ->> 'case_ref' and (r2 ->> 'appended')::boolean
                   and (cl ->> 'ok')::boolean and cl ->> 'phone_digits' = '971500000041' and h_case_after.status = 'done'
                   and jsonb_array_length(h_case_after.detail -> 'reports') = 2
                   and held_before and not held_after and (tk ->> 'followups_queued')::int >= 1
                   and h_hum.detail ? 'followed_up_at' and (h_hum.detail ->> 'followup_request_id') is not null
                   and (hc ->> 'closed')::int = 1 and h_hum_after.status = 'done'
                   and v22 is not null and v500 is not null
                   and not (coalesce(neg ->> 'source', '') = 'faq_semantic' and neg ->> 'question' ilike 'Can I invite my own supplier%')
                   and pos ->> 'source' = 'faq_semantic' and pos ->> 'question' = 'Is there a subscription fee for suppliers?'
              then 'PROBE OK' else 'PROBE FAILED' end,
         format('ctx=%s; r1=%s; r2=%s; case handoff=%s/%s -> %s reports=%s; close=%s; human=%s held %s->%s tick=%s followed=%s close=%s -> %s; '
                || 'faq negative=%s; faq positive=%s; block ended with: %s',
                ctx, r1, r2, h_case.id, h_case.status, h_case_after.status, jsonb_array_length(h_case_after.detail -> 'reports'),
                cl, hr, held_before, held_after, tk, h_hum.detail ->> 'followed_up_at', hc, h_hum_after.status,
                neg - 'answer', pos - 'answer', v_err);
end $probe$;
select * from zz_probe_verdict;
