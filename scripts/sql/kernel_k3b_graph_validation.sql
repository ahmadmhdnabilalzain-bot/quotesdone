-- ============================================================================================
-- KERNEL K3b — THE 30-WORKFLOW GRAPH VALIDATOR
--
-- APPLY ORDER: after scripts/sql/kernel_k3_step_engine.sql. It calls fn_kernel_step_successor,
-- which K3 creates. That sharing is the point: the validator and the engine cannot disagree about
-- what a step's successor is, because there is only one function that decides.
--
-- WHAT IT PROVES, PER WORKFLOW, FROM THE FROZEN REGISTRY ALONE
--   one valid start                       exactly one step_no = 1, and its owner resolves
--   every reachable non-closure step
--     has a valid successor               classifier kind is same_owner or cross_owner
--   failure outcomes map to a state       failure_workflow_state is in phase_b_workflow_state
--   every path reaches closure            the walk from step 1 ends at a closure step
--   closure steps explicitly marked       next_step_if_pass = 'WORKFLOW_COMPLETE' AND
--                                         is_closure_step — both, agreeing
--   no missing owner                      every step's accountable_role_id resolves
--   no cycle                              the next_step_if_pass walk never revisits a step
--   no step falsely treated as terminal   see below
--
-- "FALSELY TREATED AS TERMINAL" — THE DEFINITION MATTERS
--   The old consumer inferred terminality from an EMPTY JOIN against phase_b_handoff. 96 of the
--   257 steps have no outgoing handoff row; 30 of those are the declared closure steps and 66 are
--   same-owner hops that legitimately owe no handoff. Reporting all 96 as defects would be wrong,
--   and reporting the number the classifier itself produces would be a tautology.
--
--   false_terminal_steps is therefore computed WITHOUT the classifier's verdict: a step with no
--   outgoing handoff row, which is not the declared closure step, and for which the engine has no
--   successor it can open. A step in that state stops the chain and reports success — the exact
--   defect. The 66 legitimate same-owner hops are counted separately and by name, so the number
--   is visible rather than buried.
--
-- TWO CLOSURE ANSWERS, DELIBERATELY
--   closure_path_topological  the walk reaches the closure step ignoring whether owners resolve
--   closure_path_executable   the walk reaches the closure step AND every hop on the way is one
--                             the engine will actually open
--   They differ for exactly one workflow and that difference is the finding, not a rounding error.
--   Collapsing them into one column would hide it.
-- ============================================================================================

create or replace function public.fn_kernel_workflow_graph_validate()
returns table(
  workflow_id                   text,
  workflow_name                 text,
  steps                         bigint,
  start_step_id                 text,
  start_ok                      boolean,
  reachable_steps               bigint,
  unreachable_steps             bigint,
  cycles                        bigint,
  nonterminal_without_successor bigint,
  successor_not_a_step          bigint,
  unresolved_successor_owners   bigint,
  registry_gap_no_handoff       bigint,
  false_terminal_steps          bigint,
  same_owner_hops_no_edge       bigint,
  owners_unresolved             bigint,
  closure_steps                 bigint,
  closure_path_topological      boolean,
  closure_path_executable       boolean,
  failure_states_valid          boolean,
  verdict                       text,
  detail                        text)
language sql stable security definer set search_path to 'public','pg_temp' as $fn$
with recursive k as (
  -- the classifier, once per step. Everything below reads THIS, never phase_b_handoff directly,
  -- except has_out_edge, which exists precisely to measure the old consumer's mistake.
  select s.workflow_id, s.step_id, s.step_no, s.is_closure_step, s.next_step_if_pass,
         s.accountable_role_id, s.failure_workflow_state,
         c.kind, c.next_step_id, c.next_owner_role_id, c.handoff_id, c.this_owner_role_id,
         exists (select 1 from public.phase_b_handoff h where h.from_step_id = s.step_id) as has_out_edge
  from public.phase_b_workflow_step s
  cross join lateral public.fn_kernel_step_successor(s.step_id) c
),
walk as (
  -- topological reachability from the declared start along next_step_if_pass
  select k.workflow_id, k.step_id, k.next_step_id, k.kind, 1 as depth,
         array[k.step_id] as path, false as cyc
  from k where k.step_no = 1
  union all
  select n.workflow_id, n.step_id, n.next_step_id, n.kind, w.depth + 1,
         w.path || n.step_id, n.step_id = any (w.path)
  from walk w join k n on n.step_id = w.next_step_id
  where not w.cyc and w.depth < 400
),
ewalk as (
  -- executable reachability: the same walk, stopped the moment the engine would refuse to open
  select k.workflow_id, k.step_id, k.next_step_id, k.kind, 1 as depth, array[k.step_id] as path
  from k where k.step_no = 1
  union all
  select n.workflow_id, n.step_id, n.next_step_id, n.kind, e.depth + 1, e.path || n.step_id
  from ewalk e join k n on n.step_id = e.next_step_id
  where e.kind in ('same_owner','cross_owner')
    and not (n.step_id = any (e.path)) and e.depth < 400
),
per as (
  select w.workflow_id as wf, w.workflow_name as wname,
         count(*)                                                        as n_steps,
         min(k.step_id) filter (where k.step_no = 1)                     as start_step,
         count(*) filter (where k.step_no = 1)                           as n_starts,
         count(*) filter (where k.this_owner_role_id is null)            as n_owner_unresolved,
         count(*) filter (where k.is_closure_step)                       as n_closure,
         count(*) filter (where k.kind = 'successor_not_a_step')         as n_not_a_step,
         count(*) filter (where k.kind = 'successor_owner_unresolved')   as n_succ_owner_bad,
         count(*) filter (where k.kind = 'registry_gap_no_handoff')      as n_gap,
         count(*) filter (where k.kind = 'closure_flag_disagrees')       as n_flag_bad,
         -- legitimate, named, and not a defect
         count(*) filter (where not k.has_out_edge and k.kind = 'same_owner') as n_same_owner_noedge,
         -- FALSE TERMINAL, computed without the classifier's verdict driving it:
         -- no outgoing handoff row, not the declared closure step, and no openable successor.
         count(*) filter (where not k.has_out_edge
                            and not k.is_closure_step
                            and k.next_step_if_pass <> 'WORKFLOW_COMPLETE'
                            and k.kind not in ('same_owner','cross_owner'))  as n_false_terminal,
         count(*) filter (where not exists (select 1 from public.phase_b_workflow_state x
                                             where x.state = k.failure_workflow_state)) as n_fail_state_bad
  from public.phase_b_workflow w
  join k on k.workflow_id = w.workflow_id
  group by w.workflow_id, w.workflow_name
),
reach as (
  select p.wf,
         (select count(distinct x.step_id) from walk x where x.workflow_id = p.wf)   as n_reach,
         (select count(*) from walk x where x.workflow_id = p.wf and x.cyc)          as n_cyc,
         (select count(*) from k where k.workflow_id = p.wf
            and not exists (select 1 from walk x where x.step_id = k.step_id))       as n_unreach,
         -- reachable steps the engine cannot progress from at all
         (select count(*) from walk x
           where x.workflow_id = p.wf
             and x.kind not in ('closure','same_owner','cross_owner'))               as n_no_successor,
         exists (select 1 from walk x where x.workflow_id = p.wf and x.kind = 'closure') as topo_ok,
         exists (select 1 from ewalk x where x.workflow_id = p.wf and x.kind = 'closure') as exec_ok
  from per p
),
rows_out as (
  select p.wf, p.wname, p.n_steps, p.start_step,
         (p.n_starts = 1 and p.start_step is not null
          and exists (select 1 from k where k.step_id = p.start_step
                       and k.this_owner_role_id is not null))                        as start_ok,
         r.n_reach, r.n_unreach, r.n_cyc, r.n_no_successor,
         p.n_not_a_step, p.n_succ_owner_bad, p.n_gap, p.n_false_terminal,
         p.n_same_owner_noedge, p.n_owner_unresolved, p.n_closure,
         r.topo_ok, r.exec_ok, (p.n_fail_state_bad = 0) as fail_ok, p.n_flag_bad
  from per p join reach r on r.wf = p.wf
)
select o.wf, o.wname, o.n_steps, o.start_step, o.start_ok,
       o.n_reach, o.n_unreach, o.n_cyc, o.n_no_successor,
       o.n_not_a_step, o.n_succ_owner_bad, o.n_gap, o.n_false_terminal,
       o.n_same_owner_noedge, o.n_owner_unresolved, o.n_closure,
       o.topo_ok, o.exec_ok, o.fail_ok,
       case when o.start_ok and o.n_unreach = 0 and o.n_cyc = 0 and o.n_no_successor = 0
                 and o.n_false_terminal = 0 and o.n_succ_owner_bad = 0 and o.n_gap = 0
                 and o.n_owner_unresolved = 0 and o.n_closure > 0 and o.topo_ok and o.exec_ok
                 and o.fail_ok and o.n_flag_bad = 0
            then 'OK' else 'REGISTRY_DEFECT' end,
       coalesce(nullif(concat_ws('; ',
         case when not o.start_ok           then 'no single valid start' end,
         case when o.n_unreach > 0          then o.n_unreach || ' unreachable step(s)' end,
         case when o.n_cyc > 0              then o.n_cyc || ' cycle(s)' end,
         case when o.n_no_successor > 0     then o.n_no_successor
              || ' reachable step(s) the engine cannot progress from' end,
         case when o.n_not_a_step > 0       then o.n_not_a_step || ' successor(s) not a step' end,
         case when o.n_succ_owner_bad > 0   then o.n_succ_owner_bad
              || ' successor owner(s) that do not resolve to an active canonical role' end,
         case when o.n_gap > 0              then o.n_gap
              || ' owner change(s) with no declared handoff' end,
         case when o.n_false_terminal > 0   then o.n_false_terminal
              || ' step(s) with no handoff edge, not closure, and no openable successor' end,
         case when o.n_owner_unresolved > 0 then o.n_owner_unresolved || ' step owner(s) unresolved' end,
         case when o.n_flag_bad > 0         then o.n_flag_bad || ' closure flag disagreement(s)' end,
         case when not o.topo_ok            then 'no topological path to a closure step' end,
         case when o.topo_ok and not o.exec_ok then 'closure is topologically reachable but NOT '
              || 'executable: the walk stops at a step the engine refuses to open' end,
         case when not o.fail_ok            then 'failure_workflow_state not in the state registry' end
       ), ''), 'clean')
from rows_out o

union all

-- ---- the summary row. Its numbers are SUMS of the per-workflow numbers, so it cannot drift. ----
select 'SUMMARY', 'all workflows', sum(o.n_steps), null, bool_and(o.start_ok),
       sum(o.n_reach), sum(o.n_unreach), sum(o.n_cyc), sum(o.n_no_successor),
       sum(o.n_not_a_step), sum(o.n_succ_owner_bad), sum(o.n_gap), sum(o.n_false_terminal),
       sum(o.n_same_owner_noedge), sum(o.n_owner_unresolved), sum(o.n_closure),
       bool_and(o.topo_ok), bool_and(o.exec_ok), bool_and(o.fail_ok),
       case when bool_and(o.start_ok) and sum(o.n_unreach) = 0 and sum(o.n_cyc) = 0
                 and sum(o.n_no_successor) = 0 and sum(o.n_false_terminal) = 0
                 and sum(o.n_succ_owner_bad) = 0 and sum(o.n_gap) = 0
                 and sum(o.n_owner_unresolved) = 0 and bool_and(o.topo_ok) and bool_and(o.exec_ok)
                 and bool_and(o.fail_ok) and sum(o.n_flag_bad) = 0
            then 'OK' else 'REGISTRY_DEFECT' end,
       format('workflows with no EXECUTABLE closure path %s of %s; with no topological closure '
           || 'path %s of %s; reachable steps the engine cannot progress from %s; false terminal '
           || 'steps %s; unresolved successor owners %s; registry gaps with no handoff %s; '
           || 'successors that are not a step %s; cycles %s; step owners unresolved %s; '
           || 'legitimate same-owner hops with no handoff edge %s (not a defect)',
         count(*) filter (where not o.exec_ok), count(*),
         count(*) filter (where not o.topo_ok), count(*),
         sum(o.n_no_successor), sum(o.n_false_terminal), sum(o.n_succ_owner_bad),
         sum(o.n_gap), sum(o.n_not_a_step), sum(o.n_cyc), sum(o.n_owner_unresolved),
         sum(o.n_same_owner_noedge))
from rows_out o
order by 1;
$fn$;

revoke all on function public.fn_kernel_workflow_graph_validate() from public;
grant execute on function public.fn_kernel_workflow_graph_validate() to service_role;
