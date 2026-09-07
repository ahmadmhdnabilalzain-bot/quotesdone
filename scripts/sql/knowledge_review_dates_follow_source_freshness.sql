-- KNOWLEDGE REVIEW DATES FOLLOW SOURCE FRESHNESS (6 Sep 2026). Knowledge audit company_wide.md §5, action #9, and action #4's refresher.
--
-- MEASURED. agent_knowledge: 2,507 rows, every one with a review_due, none of them due (min
-- 2026-10-24) - trg_agent_knowledge_metadata stamped now()+90/180/365 by a topic regex at INSERT and
-- nothing ever recomputed it, so knowledge_decay_daily (cron 154) has decayed 0 rows in its life.
-- ops_knowledge: 5,164 of 9,132 rows have no review_after, so v3_knowledge_freshness_daily (272)
-- marks 0. The `_global company:self_knowledge` row the exam corpus reads was written 2026-08-16 by
-- cron 126, which the stand-down left inactive.
--
-- THE MECHANISM.
--   * trg_agent_knowledge_metadata fires on INSERT and on UPDATE OF content and computes review_due
--     from the row's CLASS unless the writer set one: company facts 30 days (a _global row of layer
--     'state', or whose topic names the live self-knowledge, FAQ, primer, pricing/fees or live state),
--     regulatory 180 days (regulation, licence, compliance, tax/VAT, law/decree/code, authority),
--     procedures and everything else 365. A refresh that changes content moves the date; a row
--     nobody refreshes comes due, decays 0.05 a month past due, and is quarantined under 0.35 with a
--     refresh task - the loop cron 154 was built to run.
--   * Every existing agent_knowledge row is re-dated by the same rule from its updated_at.
--   * ops_knowledge rows with no review_after get one from their class and effective_date:
--     regulatory 180, everything else 365 - EXCEPT the 44 qd-company:* rows, whose freshness is their
--     effective_date, rewritten every 15 minutes by cron 292; a fixed date there would mark a
--     15-minute-old row stale.
--   * Cron 126 (company_selfknowledge_refresh: the _global company:self_knowledge row <- fn_company_brief)
--     is wrapped and re-enabled under knowledge_director / data_intel, registered, and run once traced.
--
-- PROOF: the decay routine now finds due rows - aborted probe in the commit message; in-file the
-- count of due rows is asserted > 0.
--   node scripts/apply_sql.mjs scripts/sql/knowledge_review_dates_follow_source_freshness.sql --apply --ddl

begin;

-- ROUTINE REMOVED 7 September 2026. public.fn_knowledge_review_days was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


CREATE OR REPLACE FUNCTION public.trg_agent_knowledge_metadata()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare v_days int; begin
  v_days := public.fn_knowledge_review_days(NEW.agent_key, NEW.layer, NEW.topic);
  -- source_ref, confidence, owner_agent and supporting_evidence are deliberately NOT set here.
  -- They belong after trg_knowledge_provenance_stamp has had its chance to derive a real citation;
  -- setting them here is what stopped it running at all. See the header.
  if NEW.validation_status is null then NEW.validation_status := 'unvalidated'; end if;
  if TG_OP = 'INSERT' then
    if NEW.review_due  is null then NEW.review_due  := (now() + (v_days     || ' days')::interval)::date; end if;
    if NEW.valid_until is null then NEW.valid_until := (now() + (v_days * 2 || ' days')::interval)::date; end if;
  elsif NEW.content is distinct from OLD.content then
    -- a refresh that changed the content moves the review date, unless the writer set one itself
    if NEW.review_due is not distinct from OLD.review_due then
      NEW.review_due := (now() + (v_days || ' days')::interval)::date;
    end if;
    if NEW.validation_status = 'stale' and OLD.validation_status = 'stale' then NEW.validation_status := 'unvalidated'; end if;
  end if;
  return NEW;
end
$function$;

drop trigger if exists a00_agent_knowledge_metadata on public.agent_knowledge;
create trigger a00_agent_knowledge_metadata
  before insert or update of content on public.agent_knowledge
  for each row execute function public.trg_agent_knowledge_metadata();

-- re-date every existing row from its own updated_at by the class rule
update public.agent_knowledge k
   set review_due = (coalesce(k.updated_at, k.created_at, now())::date + public.fn_knowledge_review_days(k.agent_key, k.layer, k.topic))
 where k.review_due is distinct from (coalesce(k.updated_at, k.created_at, now())::date + public.fn_knowledge_review_days(k.agent_key, k.layer, k.topic));

-- ops_knowledge: a review_after for every row that had none, by class; the live company rows excepted
update public.ops_knowledge o
   set review_after = coalesce(o.effective_date, current_date)
                    + case when o.scope_type = 'external_source'
                             or o.jurisdiction is not null
                             or coalesce(o.source_type, '') ~* 'regulat|law|statut|standard'
                             or coalesce(o.layer, '') ~* 'regulat|complian'
                             or coalesce(o.title, '') ~* 'regulat|licen[cs]|complian|\mtax\M|\mvat\M|\mlaw\M|decree'
                           then 180 else 365 end
 where o.review_after is null
   and o.record_id not like 'qd-company:%';

-- cron 126: the _global self-knowledge row refreshes again, traced
do $cron$
declare v jsonb;
begin
  if not exists (select 1 from cron.job where jobid = 126 and jobname = 'company_selfknowledge_refresh') then
    raise exception 'cron job 126 is not company_selfknowledge_refresh on this project';
  end if;
  v := public.fn_kernel_wrap_and_enable_cron(126, 'knowledge_director', 'data_intel', 'routine_operational_decision');
  if coalesce((v->>'ok')::boolean, false) is not true then raise exception 'wrap of 126 refused: %', v; end if;
  insert into public.cron_registry (jobname, human_name, category, purpose) values
    ('company_selfknowledge_refresh', 'Company self-knowledge row refresh', 'knowledge',
     'Every 3 hours (:13): rewrites the _global company:self_knowledge agent_knowledge row from fn_company_brief(4000) so the exam corpus and every reader of _global sees the current organisation. The run-time head reads the live qd-company:* rows directly.')
  on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
    (126, 'company_selfknowledge_refresh',
     'UPDATEs one public.agent_knowledge row (agent_key _global, topic company:self_knowledge) with fn_company_brief(4000). Reads org tables; writes nothing a scenario writes.',
     'agent_knowledge is not a scenario relation; the row is fixed and carries no ZZ DEMO marker.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
end $cron$;

do $proof$
declare n_due int; n_ops_null int; t bigint; v_res text; v_upd timestamptz;
begin
  select count(*) into n_due from public.agent_knowledge where review_due < current_date and coalesce(validation_status,'') <> 'quarantined';
  if n_due = 0 then raise exception 'no agent_knowledge row is due after re-dating; the decay loop still has nothing to act on'; end if;
  select count(*) into n_ops_null from public.ops_knowledge where review_after is null and record_id not like 'qd-company:%';
  if n_ops_null <> 0 then raise exception '% ops_knowledge rows still have no review_after', n_ops_null; end if;
  t := public.fn_kernel_cron_exec(126);
  select result into v_res from public.phase_c_system_execution where trace_id = t;
  if v_res is distinct from 'succeeded' then raise exception 'traced run of cron 126 ended %', v_res; end if;
  select updated_at into v_upd from public.agent_knowledge where agent_key = '_global' and topic = 'company:self_knowledge';
  if v_upd < now() - interval '5 minutes' then raise exception 'company:self_knowledge was not refreshed by the traced run (updated_at %)', v_upd; end if;
  raise notice 'review dates: % agent_knowledge rows due today; company:self_knowledge refreshed at %', n_due, v_upd;
end $proof$;

commit;
