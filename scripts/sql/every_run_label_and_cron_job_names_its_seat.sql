-- EVERY RUN LABEL AND CRON JOB NAMES ITS SEAT (30 Sep 2026; seat: it_engineer).
--
-- Senior-hire audit, ownership: "no job or task exists without an agent" (founder, 7 Sep 2026). Two things
-- ran with no seat behind them.
--
-- WHAT WAS MEASURED (30 Sep 2026, production, read-only):
--   * 81 distinct agent_runs labels in the last 7 days. A label is owned when it (or, for 'fn:<slug>', its slug)
--     is a function_owner.function_slug, or a seat_duty duty or routine. Exactly five were not:
--       backup_kick 500 runs, brief 7, company_snapshot 6, supplier_invites 7, supplier_sanctions_screen 13
--     (every one of them status ok: they work, nobody owns them).
--   * cron.job ceo-strategy-memo-monthly (0 2 2 * *, select public.fn_ceo_strategy_memo()) is scheduled
--     directly by the_ceo_writes_a_one_page_strategy_memo_every_month.sql. It is not a seat_duty, so no seat's
--     clock, failure count or finding sees it. Moving it onto the seat clock changes when and how it runs, which
--     is behaviour, not a defect; this change records its owner and leaves the schedule alone.
--
-- WHAT THIS ADDS
--   public.writer_seat (kind, name, owner_seat -> org_role): the owner of a writer that no seat_duty or
--   function_owner row already names. Owners, per the founder's seat map of 24 Sep 2026:
--     backup_kick                 it_engineer   (the platform's backups: IT monitors everything)
--     brief, company_snapshot     ceo           (the company's own picture for the chief executive)
--     supplier_invites            marketing     (the supplier registration campaign, Oct-Dec 2026)
--     supplier_sanctions_screen   accountant    (sanctions rescreening sits with money and compliance)
--     cron ceo-strategy-memo-monthly  ceo
--   fn_writers_without_a_seat(p_days) returns every agent_runs label of the last p_days days and every cron job
--   that resolves to no seat. It is the one definition of "owned", read by the check below.
--
-- Prevented by: scripts/checks/every_run_label_and_cron_job_names_its_seat.test.mjs (production: the function
-- returns no rows; static: revoke, search_path, RLS and policy).
--   node scripts/apply_sql.mjs scripts/sql/every_run_label_and_cron_job_names_its_seat.sql --apply --ddl

create table if not exists public.writer_seat (
  kind        text not null check (kind in ('agent_runs_label', 'cron_job')),
  name        text not null,
  owner_seat  text not null references public.org_role (role_id),
  note        text not null,
  owner_file  text not null,
  recorded_at timestamptz not null default now(),
  primary key (kind, name)
);
alter table public.writer_seat enable row level security;
drop policy if exists writer_seat_service_role_only on public.writer_seat;
create policy writer_seat_service_role_only on public.writer_seat
  as permissive for all to public using (false) with check (false);
revoke all on public.writer_seat from anon, authenticated;
comment on table public.writer_seat is
  'The seat that owns an agent_runs label or a cron job that no seat_duty or function_owner row names (30 Sep 2026). fn_writers_without_a_seat() lists what is still unowned.';

insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('agent_runs_label', 'backup_kick', 'it_engineer', 'Kicks the platform backup. IT monitors the platform.', 'scripts/sql/every_run_label_and_cron_job_names_its_seat.sql'),
  ('agent_runs_label', 'brief', 'ceo', 'The company brief read by the chief executive.', 'scripts/sql/every_run_label_and_cron_job_names_its_seat.sql'),
  ('agent_runs_label', 'company_snapshot', 'ceo', 'The company snapshot and pulse for the chief executive.', 'scripts/sql/every_run_label_and_cron_job_names_its_seat.sql'),
  ('agent_runs_label', 'supplier_invites', 'marketing', 'The supplier registration invitations (campaign Oct-Dec 2026).', 'scripts/sql/every_run_label_and_cron_job_names_its_seat.sql'),
  ('agent_runs_label', 'supplier_sanctions_screen', 'accountant', 'Sanctions rescreening of registered suppliers.', 'scripts/sql/every_run_label_and_cron_job_names_its_seat.sql'),
  ('cron_job', 'ceo-strategy-memo-monthly', 'ceo', 'fn_ceo_strategy_memo on the 2nd of each month; scheduled outside the seat clock.', 'scripts/sql/every_run_label_and_cron_job_names_its_seat.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

create or replace function public.fn_writers_without_a_seat(p_days integer default 7)
returns table (kind text, name text, runs bigint)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select 'agent_runs_label', l.agent, count(*)
    from public.agent_runs l
   where l.started_at > now() - make_interval(days => greatest(coalesce(p_days, 7), 1))
     and not exists (select 1 from public.function_owner f where f.function_slug = regexp_replace(l.agent, '^fn:', ''))
     and not exists (select 1 from public.seat_duty d where l.agent in (d.duty, d.routine))
     and not exists (select 1 from public.writer_seat o join public.org_role r on r.role_id = o.owner_seat and r.status = 'active'
                      where o.kind = 'agent_runs_label' and o.name = l.agent)
   group by l.agent
  union all
  select 'cron_job', j.jobname, null::bigint
    from cron.job j
   where not exists (select 1 from public.writer_seat o join public.org_role r on r.role_id = o.owner_seat and r.status = 'active'
                      where o.kind = 'cron_job' and o.name = j.jobname)
$fn$;
revoke execute on function public.fn_writers_without_a_seat(integer) from public, anon, authenticated;
grant execute on function public.fn_writers_without_a_seat(integer) to service_role;

-- THE REGISTER IS IN THE DAILY EXPORT. Body = scripts/sql/the_seat_playbooks_are_in_the_daily_export.sql (MANIFEST
-- canonical, 162 rows) + ONE row, writer_seat. If another definer lands first, rebase = take the newest body and
-- re-add that single marked line. CREATE OR REPLACE keeps the ACL; the revoke is repeated as the source does.
create or replace function public.fn_table_export_list()
returns table(table_name text, subject text, change_log text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select v.t, v.s,
         (select 'table_export_change' from public.table_export_change_tracked x where x.table_name = v.t)
  from (values
    ('seat_playbook','knowledge'),
    ('writer_seat','company'),   -- 30 Sep 2026: every_run_label_and_cron_job_names_its_seat.sql
    ('customer_followup','customer'),
    ('it_game_day_run','company'), ('it_duty_schedule','company'),
    ('ceo_decision_round','decision'),
    ('founder_mail_policy','decision'), ('marketing_article_round','marketing'), ('marketing_blog_topic','marketing'),
    ('fraud_flags','risk'), ('free_email_domain','risk'), ('money_move_hold','risk'), ('seat_handoff_kind','decision'), ('supplier_availability','supplier'),
    ('quote_quality_hold','quote'),
    ('stalled_inquiry_rescue','inquiry'),
    ('customers','customer'), ('customer_preference','customer'), ('customer_calls','customer'), ('projects','customer'),
    ('leads','supplier'), ('lead_category','supplier'), ('lead_subcategory','supplier'), ('supplier_capabilities','supplier'),
    ('supplier_catalog','supplier'), ('supplier_product','supplier'), ('supplier_product_variant','supplier'),
    ('supplier_capability_confirmation','supplier'), ('supplier_collaboration','supplier'), ('supplier_collaboration_event','supplier'),
    ('supplier_negotiation_policy','supplier'), ('supplier_screening_hit','supplier'), ('supplier_lead_intake','supplier'),
    ('doc_reviews','supplier'), ('licence_renewal_ask','supplier'), ('outreach','supplier'), ('company_registration','company'),
    ('inquiries','inquiry'), ('inquiry_intake','inquiry'), ('inquiry_matches','inquiry'), ('inquiry_requirement','inquiry'),
    ('inquiry_cancellations','inquiry'), ('inquiry_supplier_brief','inquiry'), ('inquiry_state_audit','inquiry'),
    ('inquiry_gate','inquiry'), ('inquiry_answer','inquiry'), ('inquiry_answer_document','inquiry'), ('inquiry_answer_scope','inquiry'),
    ('inquiry_workstream','inquiry'), ('inquiry_workstream_group','inquiry'), ('inquiry_workstream_requirement','inquiry'),
    ('inquiry_trade_candidate','inquiry'), ('inquiry_trade_clarification','inquiry'), ('inquiry_scope_disposition','inquiry'),
    ('rfq_archives','inquiry'), ('rfq_clarification','inquiry'),
    ('quotes','quote'), ('quote_items','quote'), ('quote_reviews','quote'), ('quote_review_messages','quote'),
    ('quote_requirements','quote'), ('quote_committed_items','quote'), ('quote_comparisons','quote'), ('quote_spec_hold','quote'),
    ('spec_alternative_offer','quote'), ('po_orders','quote'), ('po_vendors','quote'), ('questions','quote'), ('reviews','quote'),
    ('category_specs','quote rules'), ('category_quote_specs','quote rules'),
    ('transactions','payment'), ('reveal_invoices','payment'), ('supplier_dues','payment'), ('refunds','payment'),
    ('refund_case','payment'), ('refund_incident','payment'), ('refund_ceo_review','payment'), ('refund_ceo_check','payment'),
    ('refund_ladder_evidence','payment'), ('refund_status_transition','payment'), ('stripe_events','payment'),
    ('stripe_payout','payment'), ('stripe_dispute','payment'), ('charge_audit','payment'), ('pricing_config','payment'),
    ('gl_journal','accounting'), ('gl_journal_lines','accounting'), ('gl_expense_map','accounting'), ('expenses','accounting'),
    ('expense_entries','accounting'), ('bank_statement_intake','accounting'), ('bank_statement_line','accounting'),
    ('accountant_month_close','accounting'), ('accountant_issued_document','accounting'),
    ('messages','conversation'), ('chat_threads','conversation'), ('conversation_archive','conversation'),
    ('inbound_messages','conversation'), ('contact_messages','conversation'), ('complaint_tickets','conversation'),
    ('support_case','conversation'), ('support_notification','conversation'), ('support_document_intake','conversation'),
    ('wa_messages','conversation'), ('wa_conversation','conversation'), ('wa_turn','conversation'),
    ('wa_document_intake','conversation'), ('notifications','conversation'), ('agent_chats','conversation'),
    ('legal_reviews','legal'), ('pdpl_requests','legal'), ('pdpl_erase_files','legal'), ('email_suppressions','legal'),
    ('founder_instruction','decision'), ('company_policy_decision','decision'),
    ('kb_chunks','knowledge'), ('dept_library','knowledge'), ('ops_knowledge','knowledge'), ('agent_knowledge','knowledge'),
    ('sales_knowledge','knowledge'), ('ceo_knowledge','knowledge'), ('support_knowledge','knowledge'),
    ('accountant_knowledge','knowledge'), ('it_engineer_knowledge','knowledge'), ('employee_knowledge','knowledge'),
    ('marketing_post','marketing'), ('marketing_connection_check','marketing'), ('marketing_insight_day','marketing'),
    ('marketing_ad_spend_day','marketing'), ('marketing_duty_run','marketing'), ('marketing_report','marketing'),
    ('marketing_article','marketing'), ('marketing_prospect','marketing'), ('marketing_outreach_message','marketing'),
    ('marketing_platform_spec','marketing'), ('marketing_platform_spec_source','marketing'),
    ('marketing_campaign','marketing'), ('marketing_founder_request','marketing'), ('marketing_video_idea','marketing'), ('supplier_campaign_daily_list','supplier'), ('marketing_post_variant','marketing'),
    ('marketing_post_platform','marketing'), ('marketing_post_channel_result','marketing'), ('marketing_calendar_resend_decision','marketing'), ('marketing_post_metric','marketing'), ('marketing_first_touch','marketing'),
    ('marketing_goal','marketing'), ('marketing_scorecard_report','marketing'),
    ('marketing_asset_feature','marketing'), ('marketing_asset_perception','marketing'), ('marketing_asset_review','marketing'),
    ('marketing_insight_note','marketing'), ('marketing_month_plan','marketing'), ('marketing_plan_review_turn','marketing'),
    ('marketing_model_run','marketing'), ('marketing_trend_source','marketing'), ('marketing_trend','marketing'),
    ('marketing_geo_question','marketing'), ('marketing_geo_check','marketing'), ('marketing_review','marketing'), ('market_intel','marketing'), ('competitor','marketing'), ('marketing_knowledge','knowledge'),
    ('marketing_recruitment_source','marketing'), ('marketing_gap_recruitment_plan','marketing'), ('marketing_plan_doc','marketing'),
    ('table_export_change','backup'),
    -- 1056: the model routing the founder rules on, and what every seat runs on
    ('model_policy','model_routing'), ('model_policy_by_identity','model_routing'), ('model_registry','model_routing'),
    ('fn_task_class','model_routing'), ('review_pool','model_routing'), ('paid_route_exception','model_routing'),
    ('it_model_consumer','model_routing')
  ) v(t, s)
  -- The sibling PRs' tables may not exist yet when this applies; backup/index.ts fails the whole day on a
  -- missing table, so ONLY those nine are skipped until their own file creates them. Every other table in the
  -- list still fails loudly if it disappears.
  where v.t not in ('marketing_platform_spec','marketing_platform_spec_source','marketing_campaign','marketing_post_variant',
                    'marketing_post_platform','marketing_post_metric','marketing_first_touch','marketing_goal','marketing_scorecard_report')
     or to_regclass('public.' || v.t) is not null
$fn$;
revoke execute on function public.fn_table_export_list() from public, anon, authenticated;

select case when exists (select 1 from public.fn_writers_without_a_seat(7) w where w.kind = 'agent_runs_label')
            then 'PROBE FAILED: ' || (select string_agg(w.name, ', ') from public.fn_writers_without_a_seat(7) w where w.kind = 'agent_runs_label') || ' has no seat'
            else 'PROBE OK: every run label of the last 7 days names its seat' end as verdict;
