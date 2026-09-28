-- PROBE: the CEO weekly review measures, opens tracked improvements with an owner, a due date and a closing check,
-- closes one whose check passes, escalates the rest the next week, and delivers one page through fn_notify_founder
-- (kind ceo_weekly_review) with the PDF attached. Pure probe -- NO DDL. Seat: ceo. 29 Sep 2026.
-- Pairs with the_ceo_weekly_review_acts_on_every_missed_target.sql; answers PROBE FAILED before that is applied.
--   node scripts/qsql.mjs scripts/sql/the_ceo_weekly_review_acts_on_every_missed_target_probe.sql
--
-- HOW IT STAYS HARMLESS: every write is inside an inner block that ends in a raised exception, so nothing commits.
-- It cannot reach the founder even if it did: app_secrets.admin_emails is pointed at zz.demo.founder@example.invalid
-- first; its weeks are January 2026 (no real review exists for them); its one risk is a ZZ DEMO row.
begin;

do $$
declare
  v_w1 jsonb; v_w2 jsonb; v_again jsonb; v_del jsonb; v_bad jsonb; v_blocks jsonb;
  v_risk bigint; v_imp_risk bigint; v_imp_status text; v_opened int; v_no_meta int; v_handoffs int;
  v_esc int; v_esc_tasks int; v_reopened int; v_kind text; v_natt int; v_to text; v_wa int;
  v_left int; v_mail_before text; v_mail_after text; v_id2 bigint;
begin
  set local statement_timeout = '60s';
  select value into v_mail_before from public.app_secrets where key = 'admin_emails';
  begin
    update public.app_secrets set value = 'zz.demo.founder@example.invalid' where key = 'admin_emails';
    insert into public.risk_register (dept_key, risk, probability, impact, owner_agent, status, review_due, mitigation)
    values ('exec', 'ZZ DEMO probe risk with no review date', 'low', 'low', 'marketing', 'open', null, null) returning id into v_risk;

    -- WEEK 1: every missed target gets one improvement: owner, due date, closing check
    v_w1 := public.fn_ceo_weekly_review(date '2026-01-05');
    select count(*), count(*) filter (where due_on is null or close_check is null or seat is null),
           count(*) filter (where seat <> 'ceo' and handoff_id is not null)
      into v_opened, v_no_meta, v_handoffs
      from public.ceo_improvement where source_kind = 'weekly_review' and id in (select unnest(opened) from public.ceo_weekly_review where week = date '2026-01-05');
    select id into v_imp_risk from public.ceo_improvement
     where source_kind = 'weekly_review' and seat = 'marketing' and evidence->>'target' = 'risks' and status in ('open', 'assigned');

    -- the marketing seat fixes its risk before week 2
    update public.risk_register set mitigation = 'ZZ DEMO mitigation', review_due = current_date + 30 where id = v_risk;

    -- WEEK 2: the fixed one closes; every other one is past due (week 1's due date is 12 Jan 2026) and escalates
    v_w2 := public.fn_ceo_weekly_review(date '2026-01-12');
    select status into v_imp_status from public.ceo_improvement where id = v_imp_risk;
    select count(*), count(*) filter (where jsonb_array_length(coalesce(evidence->'escalation_tasks', '[]'::jsonb)) = 1)
      into v_esc, v_esc_tasks
      from public.ceo_improvement where source_kind = 'weekly_review' and escalations = 1 and due_on = (now() at time zone 'Asia/Dubai')::date + 7;
    select count(*) into v_reopened from public.ceo_improvement n
     where n.id in (select unnest(opened) from public.ceo_weekly_review where week = date '2026-01-12')
       and exists (select 1 from public.ceo_improvement e
                    where e.id in (select unnest(escalated) from public.ceo_weekly_review where week = date '2026-01-12')
                      and e.seat = n.seat and e.evidence->>'target' = n.evidence->>'target');
    v_again := public.fn_ceo_weekly_review(date '2026-01-12');
    select id, pdf_blocks into v_id2, v_blocks from public.ceo_weekly_review where week = date '2026-01-12';

    -- DELIVERY: a failed render is retained; a rendered page goes through fn_notify_founder with the PDF attached
    v_bad := public.fn_ceo_weekly_review_attach_pdf(v_id2, null, null, null, null, 'ZZ DEMO render failure');
    v_del := public.fn_ceo_weekly_review_attach_pdf(v_id2, 'agent-docs', 'zzdemo/ceo_weekly_review_probe.pdf', null, 1234, null);
    select n.kind, jsonb_array_length(n.attachments), n.to_email into v_kind, v_natt, v_to
      from public.notifications n where n.id = (v_del->>'notification_id')::bigint;
    select count(*) into v_wa from public.notifications where kind = 'ceo_weekly_review' and channel = 'whatsapp' and created_at = now();
    raise exception 'qd_probe_rollback';
  exception when raise_exception then
    if sqlerrm <> 'qd_probe_rollback' then raise; end if;
  end;

  select count(*) into v_left from public.ceo_weekly_review where week in (date '2026-01-05', date '2026-01-12');
  v_left := v_left + (select count(*) from public.risk_register where risk like 'ZZ DEMO probe risk%')
                   + (select count(*) from public.ceo_improvement where source_kind = 'weekly_review' and source_ref like '%:2026-01-%');
  select value into v_mail_after from public.app_secrets where key = 'admin_emails';

  if not coalesce((v_w1->>'ok')::boolean, false) or (v_w1->>'missed')::int < 1 then raise exception 'week 1 did not run or missed nothing: %', v_w1; end if;
  if v_opened <> (v_w1->>'missed')::int then raise exception 'week 1 missed % targets but opened % improvements', v_w1->>'missed', v_opened; end if;
  if v_no_meta <> 0 then raise exception '% improvement(s) opened without an owner, a due date or a closing check', v_no_meta; end if;
  if v_handoffs < 1 then raise exception 'no improvement was handed to its seat'; end if;
  if v_imp_risk is null then raise exception 'the ZZ DEMO risk owned by marketing opened no improvement for marketing'; end if;
  if v_imp_status is distinct from 'done' then raise exception 'the fixed risk''s improvement did not close (status %)', v_imp_status; end if;
  if (v_w2->>'closed')::int < 1 then raise exception 'week 2 closed nothing: %', v_w2; end if;
  if (v_w2->>'escalated')::int < 1 or v_esc <> (v_w2->>'escalated')::int or v_esc_tasks <> v_esc then
    raise exception 'escalation: week 2 says %, improvements escalated once and moved a week: %, with a task: %', v_w2->>'escalated', v_esc, v_esc_tasks;
  end if;
  if v_reopened <> 0 then raise exception 'week 2 opened % duplicate improvement(s) for targets already escalated', v_reopened; end if;
  if not coalesce((v_again->>'already')::boolean, false) then raise exception 'a second run of the same week was not a no-op: %', v_again; end if;
  if v_blocks->0->>'text' is distinct from 'CEO weekly review' or v_blocks::text not like '%ESCALATED x1%' then
    raise exception 'the page does not open with the review title or does not show the escalation: %', left(v_blocks::text, 300);
  end if;
  if coalesce((v_bad->>'ok')::boolean, true) or not coalesce((v_bad->>'retained')::boolean, false) then raise exception 'a failed render was not retained: %', v_bad; end if;
  if not coalesce((v_del->>'ok')::boolean, false) then raise exception 'delivery failed: %', v_del; end if;
  if v_kind is distinct from 'ceo_weekly_review' or v_natt is distinct from 1 then raise exception 'the email is kind % with % attachment(s)', v_kind, v_natt; end if;
  if v_to is distinct from 'zz.demo.founder@example.invalid' then raise exception 'the probe email went to %', v_to; end if;
  if v_wa <> 0 then raise exception 'a WhatsApp copy was queued for an info-level review'; end if;
  if v_left <> 0 or v_mail_after is distinct from v_mail_before then raise exception 'the rollback left % row(s), or admin_emails changed', v_left; end if;

  perform set_config('qd.probe_verdict',
    format('PROBE OK week1 missed=%s opened=%s (owner, due, check on all; %s handed off); week2 closed=%s escalated=%s (each with a CEO task, due +7) duplicates=0; rerun=no-op; page shows ESCALATED; failed render retained; delivered kind=%s attachments=%s to the ZZ address, no WhatsApp; left_behind=0',
           v_w1->>'missed', v_opened, v_handoffs, v_w2->>'closed', v_w2->>'escalated', v_kind, v_natt), true);
exception when others then
  perform set_config('qd.probe_verdict', 'PROBE FAILED ' || sqlerrm, true);
end $$;

select coalesce(current_setting('qd.probe_verdict', true), 'PROBE FAILED (the block set no verdict)') as verdict;

commit;
