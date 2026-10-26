-- THE LINE I NEARLY SHIPPED WAS THE SAME LIE, ONE CATEGORY OVER
--
-- The previous file split the brief's "Approvals waiting: 38" into what is his and what is the
-- machine's, and wrote:
--
--     - The machine is working on: 51 item(s) it settles itself; no action needed
--
-- Then I checked the claim instead of the arithmetic. The arithmetic is right — 78 rows in the five
-- open statuses, 27 of them his, 51 not. The CLAIM is wrong for 39 of the 51.
--
-- fn_agent_action_work_sweep selects `status = 'pending'` and nothing else. On production right now
-- the open rows are:
--
--     pending      auto      12     <- genuinely in flight, settled within the hour
--     pending      founder   26     <- his
--     needs_review auto      39     <- NOTHING SELECTS THESE
--     needs_review founder    1     <- his
--
-- The 39 are 31 handoffs (oldest 3 days), 7 strategy_rec, 1 report_task. fn_action_queue_sweep runs
-- hourly and succeeds, but all it does is supersede duplicates and auto-resolve stale incidents —
-- it has decided nothing since 10:35, thirteen hours ago. So "it settles itself; no action needed"
-- would have been a fresh instance of exactly the defect the previous file exists to fix, printed
-- in his inbox every morning with more authority than the number it replaced.
--
-- I am NOT making the worker pick them up. Something put those rows in a status literally named
-- needs_review, and draining a queue on the grounds that nobody is draining it is the mass-settling
-- the standing rules forbid. Who sets that status and what it is supposed to mean is a question for
-- a session that can answer it. Until then the brief SAYS SO, which is the whole point: a number
-- that cannot explain itself should be visible, not absorbed into a neighbouring one.
do $$
declare v_def text; v_new text; v_oid oid; a0 text; b0 text; a1 text; b1 text; a2 text; b2 text;
  function_cnt int;
begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_founder_brief' and p.pronargs = 0;
  if v_oid is null then raise exception 'fn_founder_brief() not found'; end if;
  v_def := pg_get_functiondef(v_oid);

  a0 := $q$  v_owner text; v_run bigint; v_fq jsonb; v_fq_n int := 0; v_fq_age int; v_fq_list text;$q$;
  b0 := $q$  v_owner text; v_run bigint; v_fq jsonb; v_fq_n int := 0; v_fq_age int; v_fq_list text;
  v_auto_q int := 0; v_stalled int := 0;$q$;

  a1 := $q$    v_fq_age := (v_fq->>'oldest_days')::int;$q$;
  b1 := $q$    v_fq_age := (v_fq->>'oldest_days')::int;
    -- The two halves of "not his", counted separately because only one of them is moving.
    select count(*) into v_auto_q from public.agent_actions a
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
     where a.status = 'pending';
    select count(*) into v_stalled from public.agent_actions a
     where a.status in ('held_for_review','proposed','open','needs_review')
       and not exists (select 1 from public.agent_action_kind_policy q
                        where q.kind = a.kind and q.policy = 'founder');$q$;

  a2 := $q$    '- The machine is working on: '||greatest(v_pend - v_fq_n, 0)||' item(s) it settles itself; no action needed'||E'\n'||$q$;
  b2 := $q$    '- The machine is working on: '||v_auto_q||' item(s) it will settle itself within the hour'||E'\n'||
    case when v_stalled > 0 then
      '- NOT MOVING: '||v_stalled||' item(s) sit in needs_review / proposed / open. The worker only '||
      'selects status=pending, so nothing is draining these. They are not yours to decide and they '||
      'are not being done either.'||E'\n'
    else '' end||$q$;

  if (length(v_def) - length(replace(v_def, a0, ''))) / nullif(length(a0),0) <> 1 then
    raise exception 'anchor 0 (locals) not found exactly once — has the previous patch been applied?'; end if;
  if (length(v_def) - length(replace(v_def, a1, ''))) / nullif(length(a1),0) <> 1 then
    raise exception 'anchor 1 (oldest_days) not found exactly once'; end if;
  if (length(v_def) - length(replace(v_def, a2, ''))) / nullif(length(a2),0) <> 1 then
    raise exception 'anchor 2 (machine-is-working-on line) not found exactly once'; end if;

  v_new := replace(replace(replace(v_def, a0, b0), a1, b1), a2, b2);
  if v_new = v_def then raise exception 'the three replacements changed nothing'; end if;
  execute v_new;
end $$;
