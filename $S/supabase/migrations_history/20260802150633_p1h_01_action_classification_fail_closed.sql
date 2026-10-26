-- PHASE 1 HARDENING 1 - CONTROL MODE FAILS CLOSED ON AN UNCLASSIFIED ACTION
--
-- The Phase 1 gate treated "not in the registry" as "read-only". That is the wrong default and the
-- founder was right to reject it: the registry then had to be remembered, and the one time it is
-- forgotten is exactly the time a new mutating action ships unguarded. Two live examples already
-- existed in the code before this migration:
--   * secretary_chat  - forwards message/decision/confirm_token to secretary_act, which ACTS.
--                       Unregistered, therefore treated as read-only, therefore ungated.
--   * record          - fn_os_record is STABLE, a pure read, but Phase 1 registered it as mutating.
--                       Opening any record in the console would have demanded a phone code.
-- Both are fixed here. Classification is now three-valued and mandatory.

alter table public.control_mode_action
  add column if not exists classification text;

update public.control_mode_action
   set classification = case when requires_control then 'mutating' else 'read_only' end
 where classification is null;

-- read_only    - allowed in Observe Mode. The action performs no persistent business write.
-- mutating     - requires an open Control Mode session.
-- mode_control - control_mode_status / _open / _close themselves. They cannot require Control Mode
--                without being unopenable, so they are handled before the gate. They are safe to
--                leave outside it because _open is the MFA challenge, and _status/_close only ever
--                touch the caller's own session. This class is pinned to exactly three names by the
--                constraint below, so it cannot become a loophole.
alter table public.control_mode_action
  drop constraint if exists control_mode_action_classification_chk;
alter table public.control_mode_action
  add constraint control_mode_action_classification_chk
  check (classification in ('read_only','mutating','mode_control'));

alter table public.control_mode_action
  drop constraint if exists control_mode_action_mode_control_pinned;
alter table public.control_mode_action
  add constraint control_mode_action_mode_control_pinned
  check (classification <> 'mode_control'
         or action in ('control_mode_status','control_mode_open','control_mode_close'));

alter table public.control_mode_action alter column classification set not null;

-- requires_control was a second, hand-maintained copy of the same fact. Make it derived so the two
-- cannot disagree - which they already did for `record`.
alter table public.control_mode_action drop column if exists requires_control;
alter table public.control_mode_action
  add column requires_control boolean
  generated always as (classification = 'mutating') stored;

insert into public.control_mode_action (action, classification, risk, description) values
  ('control_mode_status','mode_control','low' ,'Reports whether Control Mode is open. Reads the caller''s own session.'),
  ('control_mode_open'  ,'mode_control','high','Opens Control Mode. Is itself the MFA challenge, so it cannot require one.'),
  ('control_mode_close' ,'mode_control','low' ,'Closes the caller''s own Control Mode session early.'),
  ('inbox_send'        ,'mutating','high'  ,'Sends mail as the company.'),
  ('fraud_resolve'     ,'mutating','high'  ,'Resolves or dismisses a fraud case.'),
  ('refund_resolve'    ,'mutating','high'  ,'Approves or refuses a refund - moves money.'),
  ('prompt_approve'    ,'mutating','high'  ,'Approves an agent prompt draft into production.'),
  ('prompt_rollback'   ,'mutating','high'  ,'Rolls an agent prompt back to an earlier version.'),
  ('prompt_gate'       ,'mutating','high'  ,'Runs the prompt gate, which can promote a draft.'),
  ('comment_add'       ,'mutating','low'   ,'Writes a comment onto a record.'),
  ('review_decide'     ,'mutating','high'  ,'Decides a review item - approvals with downstream effects.'),
  ('blog_publish'      ,'mutating','high'  ,'Publishes or unpublishes public content.'),
  ('knowledge_dispatch','mutating','medium','Dispatches knowledge-gap work to agents.'),
  ('knowledge_refresh' ,'mutating','medium','Regenerates category knowledge - writes rows and spends OpenRouter credit.'),
  ('exam_run'          ,'mutating','low'   ,'Runs a knowledge exam - writes results and spends OpenRouter credit.'),
  ('exam_revert'       ,'mutating','medium','Reverts exam-derived knowledge.'),
  ('secretary_chat'    ,'mutating','high'  ,'Drives the secretary agent, which takes actions and accepts a confirm_token. Was UNREGISTERED before this migration and therefore ungated.'),
  ('ping'            ,'read_only','low'   ,'Liveness and identity echo.'),
  ('dashboard'       ,'read_only','low'   ,'fn_os_command - read.'),
  ('viz'             ,'read_only','low'   ,'fn_os_dashboard_viz - read.'),
  ('suppliers_board' ,'read_only','low'   ,'fn_suppliers_board - read.'),
  ('rfq_board'       ,'read_only','low'   ,'fn_rfq_board - read.'),
  ('customers_board' ,'read_only','low'   ,'fn_customers_board - read.'),
  ('agents_board'    ,'read_only','low'   ,'fn_agents_board - read (temp table, on commit drop).'),
  ('activity'        ,'read_only','low'   ,'fn_entity_activity - read.'),
  ('nav'             ,'read_only','low'   ,'fn_os_nav - read.'),
  ('inbox'           ,'read_only','low'   ,'fn_inbox_list - read.'),
  ('search'          ,'read_only','low'   ,'fn_os_search - read.'),
  ('record'          ,'read_only','low'   ,'fn_os_record is STABLE. Phase 1 wrongly marked this mutating; every record open would have demanded MFA.'),
  ('files'           ,'read_only','low'   ,'fn_entity_files - read.'),
  ('file'            ,'read_only','medium','Signs a 300s URL for a stored document. Reads, but hands out document access.'),
  ('prompt_view'     ,'read_only','low'   ,'Views a prompt version.'),
  ('marketing_studio','read_only','low'   ,'fn_marketing_studio - read.'),
  ('knowledge_gaps'  ,'read_only','low'   ,'fn_knowledge_gaps - read.'),
  ('exam_summary'    ,'read_only','low'   ,'fn_knowledge_exam_summary - read.'),
  ('knowledge_export','read_only','medium','Bulk markdown export of agent knowledge. No write, but it is the widest read on the surface.'),
  ('extract_doc'     ,'read_only','medium','OCR of caller-supplied bytes. Writes no record; spends a third-party call, so it stays off the preview-key allowlist.'),
  ('report_pdf'      ,'read_only','medium','Renders a report the caller can already read into a PDF object. No business state changes; stays off the preview-key allowlist.'),
  ('ws.suppliers'   ,'read_only','low','Workspace read.'),
  ('ws.supplier'    ,'read_only','low','Workspace read.'),
  ('ws.customer'    ,'read_only','low','Workspace read.'),
  ('ws.agent'       ,'read_only','low','Workspace read.'),
  ('ws.rfq'         ,'read_only','low','Workspace read.'),
  ('ws.exec'        ,'read_only','low','Workspace read.'),
  ('ws.marketplace' ,'read_only','low','Workspace read.'),
  ('ws.customers'   ,'read_only','low','Workspace read.'),
  ('ws.operations'  ,'read_only','low','Workspace read.'),
  ('ws.ai'          ,'read_only','low','Workspace read.'),
  ('ws.knowledge'   ,'read_only','low','Workspace read.'),
  ('ws.documents'   ,'read_only','low','Workspace read.'),
  ('ws.analytics'   ,'read_only','low','Workspace read.'),
  ('ws.company'     ,'read_only','low','Workspace read.'),
  ('ws.finance'     ,'read_only','low','Workspace read.'),
  ('ws.agents'      ,'read_only','low','Workspace read.'),
  ('ws.marketing'   ,'read_only','low','Workspace read.'),
  ('ws.ea'          ,'read_only','low','Workspace read.'),
  ('ws.reports'     ,'read_only','low','Workspace read.'),
  ('ws.strategy'    ,'read_only','low','Workspace read.'),
  ('ws.governance'  ,'read_only','low','Workspace read.'),
  ('ws.fraud'       ,'read_only','low','Workspace read.'),
  ('ws.refunds'     ,'read_only','low','Workspace read.')
on conflict (action) do update
  set classification = excluded.classification,
      risk           = excluded.risk,
      description    = excluded.description;

create or replace function public.fn_control_mode_require(p_actor_email text, p_action text)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_class text; v_s record;
begin
  select classification into v_class from public.control_mode_action where action = p_action;

  -- FAIL CLOSED. An action nobody classified is an action nobody thought about, and the cost of
  -- being wrong is asymmetric: refusing a read is an inconvenience, allowing an unreviewed mutation
  -- is the incident. The refusal is audited so the missing classification is discoverable.
  if v_class is null then
    insert into public.control_mode_audit (actor_email, event, action, allowed, reason)
    values (p_actor_email, 'action_unclassified', p_action, false, 'action is not in control_mode_action');
    return jsonb_build_object(
      'allowed', false, 'mode', 'observe', 'error', 'action_classification_required',
      'message', 'This action has not been classified as read-only or mutating, so it is refused. '
              || 'Classify it in control_mode_action (and in os_api ACTION_CLASS) before using it.');
  end if;

  if v_class = 'read_only' then
    return jsonb_build_object('allowed', true, 'mode', 'observe', 'reason', 'action is registered read-only');
  end if;

  if v_class = 'mode_control' then
    return jsonb_build_object('allowed', true, 'mode', 'observe', 'reason', 'Control Mode plumbing; handled before the gate');
  end if;

  select * into v_s from public.control_mode_session
   where actor_email = p_actor_email and closed_at is null and expires_at > now()
   order by opened_at desc limit 1;

  if not found then
    insert into public.control_mode_audit (actor_email, event, action, allowed, reason)
    values (p_actor_email, 'action_denied', p_action, false, 'no active Control Mode session');
    return jsonb_build_object('allowed', false, 'mode', 'observe', 'error', 'control_mode_required',
      'message', 'This changes something, so it needs Control Mode. Open it with a code sent to your phone, and say why.');
  end if;

  update public.control_mode_session set actions_used = actions_used + 1 where id = v_s.id;
  insert into public.control_mode_audit (actor_email, event, action, session_id, allowed, reason)
  values (p_actor_email, 'action_allowed', p_action, v_s.id, true, v_s.reason);

  return jsonb_build_object('allowed', true, 'mode', 'control', 'session_id', v_s.id, 'reason', v_s.reason,
                            'seconds_remaining', greatest(0, extract(epoch from (v_s.expires_at - now()))::int));
end $fn$;

revoke all on function public.fn_control_mode_require(text, text) from public, anon, authenticated;

create or replace view public.v_os_action_classification as
select classification, count(*) as actions,
       string_agg(action, ', ' order by action) as action_list
from public.control_mode_action group by classification;

comment on table public.control_mode_action is
  'Every os_api action, explicitly classified. An action absent from this table is refused by fn_control_mode_require with action_classification_required - absence is never permission.';
