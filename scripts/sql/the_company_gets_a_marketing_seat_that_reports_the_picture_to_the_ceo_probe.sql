-- PROBE: THE MARKETING SEAT'S CONVERSATIONS WORK END TO END, AND NOTHING IN THEM CAN REACH A PERSON.
--
-- Assigned: ceo (the seat's creation). 22 Sep 2026. Pure probe: no DDL, nothing survives it. Run AFTER
-- the_company_gets_a_marketing_seat_that_reports_the_picture_to_the_ceo.sql, as ONE query through the
-- Management API; it is never applied.
--
-- WHAT IT RUNS, inside a block that always raises so every write is rolled back (app.qd_stub_founder_notify
-- is set on, so even the founder path stops at a stub before fn_notify_founder):
--   A  real-shaped spend (meta, USD 10, reference probe:meta:...) -> adspend.recorded -> the accountant's row
--      (AED 36.73) -> adspend.booked verified -> fn_marketing_closes_ad_spend_loops closes adspend.recorded;
--   B  the same reference at USD 12 -> the row is revised (revisions 2), not duplicated;
--   C  test money (ZZ DEMO reference) -> no row, and the loop still closes;
--   D  the daily report for 2 Jan 2099 08:00 Dubai -> marketing_report row -> marketing.report -> the CEO reads
--      it (read_by_ceo_at set) and the handoff is done, nothing approved;
--   E  a ZZ DEMO social conversation is refused before anything is queued; a real-shaped one opens a
--      delivery.request to customer_support for the founder, stubbed, and no notification row is written;
--   F  fn_marketing_assist answers with the company block;
--   G  (after the CEO-plan file is re-applied) the demand stage binds on marketing, and a ceo.directive to marketing is
--      answered by fn_seat_takes_ceo_directive with the seat's duty and waits for the CEO to re-measure.
-- VERDICT: PROBE OK only if every step above holds and no marketing handoff ended 'failed'.
create temp table zz_probe_verdict (verdict text, detail text) on commit drop;
do $probe$
declare
  v_ref text := 'probe:meta:act_0:' || md5(random()::text);
  hA bigint; hB bigint; hC bigint; r public.ad_spend_reported; v_rows_c int; v_a_status text; v_c_status text;
  v_booked_ok boolean; v_rep jsonb; v_m public.marketing_report; v_rep_status text;
  v_demo jsonb; v_demo_rows int; v_real jsonb; v_real_status text; v_notes int; v_before bigint;
  v_assist jsonb; v_failed int; v_err text; v_close jsonb; v_dec jsonb; hD bigint; v_dir public.agent_actions;
begin
  begin
    perform set_config('app.qd_stub_founder_notify', 'on', true);
    select coalesce(max(id), 0) into v_before from public.notifications;

    hA := public.fn_marketing_records_ad_spend('meta', current_date, 'USD', 10, v_ref);
    -- addressed to 'marketing', not re-addressed to 'brief' by a00_agent_action_resolve_addressee (org_agents knows the seat)
    select exists (select 1 from public.agent_actions b where b.kind = 'handoff' and b.detail->>'type' = 'adspend.booked' and b.agent = 'marketing'
                    and (b.detail->>'recorded_handoff')::bigint = hA and b.status = 'done'
                    and (b.evidence->>'verified')::boolean) into v_booked_ok;
    v_close := public.fn_marketing_closes_ad_spend_loops();
    select status into v_a_status from public.agent_actions where id = hA;

    hB := public.fn_marketing_records_ad_spend('meta', current_date, 'USD', 12, v_ref);
    perform public.fn_marketing_closes_ad_spend_loops();
    select * into r from public.ad_spend_reported where source_ref = v_ref;

    hC := public.fn_marketing_records_ad_spend('meta', current_date, 'AED', 5, 'ZZ DEMO probe spend ' || v_ref, null, true);
    perform public.fn_marketing_closes_ad_spend_loops();
    select count(*) into v_rows_c from public.ad_spend_reported where source_ref like 'ZZ DEMO probe spend%';
    select status into v_c_status from public.agent_actions where id = hC;

    v_rep := public.fn_marketing_report_tick(timestamp '2099-01-02 08:00' at time zone 'Asia/Dubai');
    select * into v_m from public.marketing_report where report_date = date '2099-01-02';
    select status into v_rep_status from public.agent_actions where id = (v_rep->>'handoff_id')::bigint;

    v_demo := public.fn_marketing_asks_the_founder_to_take_over('instagram', 'zzdemo-thread', 'ZZ DEMO person', 'can I speak to someone');
    select count(*) into v_demo_rows from public.agent_actions where target_id like 'delivery.request:instagram:zzdemo-thread%';
    v_real := public.fn_marketing_asks_the_founder_to_take_over('instagram', 'probe-' || md5(random()::text), '@probe', 'can I speak to a person please');
    select status into v_real_status from public.agent_actions where id = (v_real->>'handoff_id')::bigint;
    select count(*) into v_notes from public.notifications where id > v_before;

    v_assist := public.fn_marketing_assist('how do we measure the contribution of organic SEO to reveals');

    -- G. the CEO's plan: the demand stage names marketing, and a ceo.directive reaches it and is answered
    v_dec := public.fn_ceo_plan_decide(jsonb_build_object('local_date', '2099-01-25', 'day_of_month', 15, 'days_in_month', 31,
               'gates', jsonb_build_object('invite_enabled', true, 'supplier_outreach_golive', true, 'invite_daily_cap', 100),
               'month_to_date', jsonb_build_object('invitations_delivered', 5000, 'registrations_submitted', 500, 'registrations_verified', 500,
                                                   'inquiries_posted', 0, 'quote_coverage_pct', null, 'reveals_paid', 0, 'fee_aed', 0),
               'last_7_days', jsonb_build_object('inquiries_posted', 0),
               'state', jsonb_build_object('bounce_pct_7d', 1, 'stranded_submissions', 0)),
             jsonb_build_object('invites', 2200, 'registered', 90, 'verified', 65, 'inquiries', 70, 'reveals', 30, 'fee_aed', 45000), null);
    hD := public.fn_seat_handoff('ceo', 'marketing', 'ceo.directive', 'ceo_plan', 'zzprobe:' || v_ref,
            jsonb_build_object('stage', 'demand', 'measure_key', 'inquiries_posted', 'direction', 'min', 'target', 1,
                               'due_at', now() + interval '7 days', 'demo', true));
    select * into v_dir from public.agent_actions where id = hD;

    select count(*) into v_failed from public.agent_actions
     where kind = 'handoff' and status = 'failed' and created_at = now()
       and (agent = 'marketing' or detail->>'from' = 'marketing');
    raise exception 'ZZPROBE rollback';
  exception when others then
    v_err := sqlerrm;
  end;
  insert into zz_probe_verdict
  select case when v_err = 'ZZPROBE rollback'
                   and v_booked_ok and v_a_status = 'done'
                   and r.amount = 12 and r.revisions = 2 and r.amount_aed = round(12 * coalesce((select num_value from public.gl_settings where key = 'usd_to_aed'), 3.6725), 2)
                   and v_rows_c = 0 and v_c_status = 'done'
                   and coalesce((v_rep->>'reported')::boolean, false) and v_m.read_by_ceo_at is not null and v_rep_status = 'done'
                   and (v_demo->>'asked')::boolean is false and v_demo_rows = 0
                   and v_real_status = 'done' and v_notes = 0
                   and coalesce((v_assist->>'ok')::boolean, false) and v_assist->'company'->>'block' is not null
                   and v_failed = 0
                   and v_dec->>'stage' = 'demand' and v_dec->'directive'->>'seat' = 'marketing' and v_dec->>'lever' = 'seat'
                   and v_dir.agent = 'marketing' and v_dir.status = 'pending' and v_dir.detail ? 'replied_at' and v_dir.evidence->>'duty' like '%marketing%'
              then 'PROBE OK' else 'PROBE FAILED' end,
         format('A booked_verified=%s recorded_status=%s close=%s | B amount=%s revisions=%s aed=%s | C demo_rows=%s status=%s | '
                || 'D report=%s read_at=%s handoff=%s | E demo=%s demo_rows=%s real=%s real_status=%s notifications=%s | '
                || 'F assist_ok=%s answered=%s | failed=%s | G stage=%s seat=%s lever=%s directive_agent=%s status=%s duty=%s | block ended with: %s',
                v_booked_ok, v_a_status, v_close, r.amount, r.revisions, r.amount_aed, v_rows_c, v_c_status,
                v_rep, v_m.read_by_ceo_at, v_rep_status, v_demo, v_demo_rows, v_real, v_real_status, v_notes,
                v_assist->>'ok', v_assist->>'answered', v_failed, v_dec->>'stage', v_dec->'directive'->>'seat', v_dec->>'lever', v_dir.agent, v_dir.status, left(v_dir.evidence->>'duty', 60), v_err);
end $probe$;
select * from zz_probe_verdict;
