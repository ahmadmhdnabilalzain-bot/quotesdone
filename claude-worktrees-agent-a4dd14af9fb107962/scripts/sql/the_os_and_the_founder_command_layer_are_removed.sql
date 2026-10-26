-- THE OS IS REMOVED, AND THE FOUNDER-COMMAND LAYER GOES WITH IT.
--
-- Founder, 8 September 2026: "anything related to OS can be removed. its totally irrelevant to my new
-- structure", and "i dont want a single routine or workflow or decision prior 7 september. literally
-- nothing."
--
-- WHAT WENT IN THE SAME CHANGE AS THIS FILE
--   Twelve edge functions, deleted from the repository and from production (65 deployed now, and
--   gen_supabase_config reports 0 deployed-but-not-in-repo and 0 in-repo-but-not-deployed):
--     os_api os_ops os_settings os_automation os_catalog os_health os_incidents
--     report_body report_pdf agent_learnings_report make_pdf make_xlsx
--   The console itself: src/components/osx/OsxShell.tsx, src/lib/osClient.ts, and the /os and
--   /console routes. Eight redirects in next.config.mjs that pointed /os2, /os3, /crm and /admin at
--   /os, because a redirect to a deleted route is worse than no redirect — it looks deliberate. And
--   the /os and /console entries in the middleware matcher, which otherwise cost a middleware run on
--   every request to a 404.
--
--   NOT deleted, and each verified before the knife: src/components/ui/* (6-18 non-OS importers
--   each), src/components/NodeField.tsx (rendered by the public layout on every page), and the .osx
--   CSS class (used by CustomerPortal, SupplierPortal and two ui primitives).
--
-- WHY THE FOUNDER-COMMAND LAYER FALLS NOW. os_api was the SOLE caller of fn_founder_command_submit,
-- _clarify, _control, _inbox, _status and _thread, and the only writer of public.founder_command.
-- With it gone the layer has no entry point at all. It is replaced, not merely deleted: ceo_agent
-- and ceo_command went live first, deliberately, so that the founder never had a moment without a
-- command channel. All 27 founder_command rows are in terminal states (cancelled or refused).
--
-- AND IT IS THE PRECONDITION FOR THE PHASE DROP. the_phase_programme_and_its_kernel_are_removed.sql
-- opens with a do $precondition$ block that REFUSES to run while fn_founder_command_submit,
-- _classify, _inbox or fn_red_view_alert still exist, because those four are what reach into the
-- machinery it drops. This file is what makes that one applicable.
--
-- ORDER MATTERS AND IS NOT COSMETIC: children before parents. founder_command carries 11 inbound
-- foreign keys and founder_command_message and _session carry one each, so the parent cannot go
-- first. No CASCADE anywhere — an unexpected dependency must fail the apply rather than quietly take
-- a neighbour with it.
--
--   node scripts/apply_sql.mjs scripts/sql/the_os_and_the_founder_command_layer_are_removed.sql --apply --ddl

begin;

-- ── THE REGISTRIES STOP CLAIMING WHAT IS GONE ──────────────────────────────────────────────────
-- A registry that lists twelve absent functions is how a future reader concludes they exist. Both of
-- these are read by live checks, so a stale row is a red gate tomorrow, not a tidy-up.
delete from public.function_owner
 where function_slug in ('os_api','os_ops','os_settings','os_automation','os_catalog','os_health',
                         'os_incidents','report_body','report_pdf','agent_learnings_report',
                         'make_pdf','make_xlsx');

delete from public.phase_c_component
 where component_id in ('edge:os_api','edge:os_ops','edge:os_settings','edge:os_automation',
                        'edge:os_catalog','edge:os_health','edge:os_incidents','edge:report_body',
                        'edge:report_pdf','edge:agent_learnings_report','edge:make_pdf',
                        'edge:make_xlsx');

-- ── THE TRIGGERS FIRST ─────────────────────────────────────────────────────────────────────────
-- The first version of this file went straight to the routines and Postgres refused it: "cannot drop
-- function fn_founder_command_state_guard() because other objects depend on it — trigger
-- z20_founder_command_state_guard on table founder_command". That refusal is the database doing its
-- job, and the answer is to name the trigger, not to reach for CASCADE. CASCADE would have taken
-- whatever else happened to depend on these without saying what.
-- These five names come from pg_trigger, not from memory. The second attempt failed too, on
-- a00_founder_command_clarification_answer_is_sealed, because I had guessed the name and guessed it
-- wrong. Asking the catalogue took one query and would have saved both failures.
drop trigger if exists z20_founder_command_state_guard on public.founder_command;
drop trigger if exists z00_kernel_truncate_guard       on public.founder_command;
drop trigger if exists a00_founder_command_clarification_answer_is_sealed on public.founder_command_clarification;
drop trigger if exists z00_kernel_truncate_guard       on public.founder_command_clarification;
drop trigger if exists z10_founder_command_message_immutable on public.founder_command_message;
drop trigger if exists z00_kernel_truncate_guard       on public.founder_command_message;

-- ── THE FOUNDER-COMMAND ROUTINES ───────────────────────────────────────────────────────────────
-- Dropped before the tables they read, so nothing is left resolving a missing relation. plpgsql
-- binds late: a surviving routine over a dropped table applies cleanly and throws on first use.
--
-- EVERY SIGNATURE BELOW COMES FROM pg_get_function_identity_arguments, not from reading the calls.
-- The first version guessed them and five routines survived the drop -- fn_founder_command_submit
-- takes (text, text, text, jsonb) and not (text, text, text), _inbox takes p_limit, _status takes
-- p_ref, _admit takes five arguments. `drop function if exists` on a wrong signature does not error;
-- it matches nothing and reports success, which is exactly how five of these would have been left
-- standing over dropped tables. The closing assertion is what caught it.
--
drop function if exists public.fn_founder_command_authenticate(p_channel text, p_sender_ref text);
drop function if exists public.fn_founder_command_clarification_answer_is_sealed();
drop function if exists public.fn_founder_command_clarify(p_command_id bigint, p_answer text, p_actor text);
drop function if exists public.fn_founder_command_classify(p_text text);
drop function if exists public.fn_founder_command_control(p_command_id bigint, p_op text, p_target text, p_value text, p_actor text);
drop function if exists public.fn_founder_command_duplicate_result(p_command_id bigint, p_key text);
drop function if exists public.fn_founder_command_inbox(p_limit integer);
drop function if exists public.fn_founder_command_message_immutable();
drop function if exists public.fn_founder_command_rollup(p_command_id bigint);
drop function if exists public.fn_founder_command_state_guard();
drop function if exists public.fn_founder_command_status(p_ref text);
drop function if exists public.fn_founder_command_admit(p_message_id bigint, p_channel text, p_sender_ref text, p_scope text, p_seq bigint);
drop function if exists public.fn_founder_command_submit(p_founder_identity text, p_text text, p_idempotency_key text, p_ctx jsonb);
drop function if exists public.fn_founder_command_thread(p_command_id bigint);
drop function if exists public.fn_founder_command_trace_guard();

-- ── THE TABLES, CHILDREN FIRST ─────────────────────────────────────────────────────────────────
drop table if exists public.founder_command_overlay_invocation;
drop table if exists public.founder_command_progress_note;
drop table if exists public.founder_command_task_link;
drop table if exists public.founder_command_workflow_link;
drop table if exists public.founder_command_status_history;
drop table if exists public.founder_command_completion;
drop table if exists public.founder_command_plan_item;
drop table if exists public.founder_command_plan;
drop table if exists public.founder_command_interpretation;
drop table if exists public.founder_command_clarification;
-- founder_command IS THE CHILD of message and session, not their parent — it carries
-- founder_command_message_id_fkey and a session reference. Dropping message first was refused, and
-- correctly: "constraint founder_command_message_id_fkey on table founder_command depends on it".
-- The eleven inbound foreign keys made it look like the root of this cluster; it is the root of most
-- of it and a leaf of the rest, which is why this order comes from pg_constraint rather than from a
-- mental model of what looks like a parent.
drop table if exists public.founder_command;
drop table if exists public.founder_command_message;
drop table if exists public.founder_command_session;

-- ── ASSERT IT, rather than trusting the statements above ───────────────────────────────────────
do $check$
declare n_t int; n_f int; n_owner int;
begin
  select count(*) into n_t from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'founder\_command%';
  select count(*) into n_f from pg_proc
   where pronamespace = 'public'::regnamespace and proname like 'fn\_founder\_command\_%';
  select count(*) into n_owner from public.function_owner where function_slug like 'os\_%';
  if n_t > 0 or n_f > 0 or n_owner > 0 then
    raise exception 'INCOMPLETE: % founder_command table(s), % routine(s), % os_ owner row(s) remain',
      n_t, n_f, n_owner;
  end if;

  -- The CEO's replacement must be standing. Deleting the old channel without the new one live is the
  -- one outcome this whole sequence was ordered to avoid.
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relname = 'ceo_command')
     or not exists (select 1 from pg_proc
                     where pronamespace = 'public'::regnamespace and proname = 'fn_ceo_command_submit')
     or not exists (select 1 from public.function_owner where function_slug = 'ceo_agent') then
    raise exception 'REFUSED: the CEO command channel is not in place. Do not remove his old one.';
  end if;
end
$check$;

commit;
