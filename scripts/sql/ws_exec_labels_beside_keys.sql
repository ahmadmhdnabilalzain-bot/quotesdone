-- ---------------------------------------------------------------------------------------------
-- fn_ws_exec CARRIES THE LABEL BESIDE THE KEY.
--
-- The bell and the escalations page were handed `notifications.type` and `agent_actions.kind` and
-- nothing else, so each invented its own cosmetic transform and both still printed the developer's
-- vocabulary at the founder: "Resilience Alert", "Ops Alert", "Legal Flag".
--
-- The key stays - it is what the front end routes on. The label rides beside it, resolved once by
-- public.fn_ui_label(), so every reader gets the same words and none of them has to guess.
-- fn_ui_label never returns null, so *_label is always safe to render directly.
--
-- This file also brings fn_ws_exec under scripts/sql for the first time: it was live-only, which
-- is why sql_files_match_live could report 0 drift while this function had no file to drift from.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ws_exec()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'command', fn_os_command(),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'priority',priority,'due',due_date,'entity',entity)) from (select * from crm_tasks order by (coalesce(status,'')='done'), created_at desc limit 8) t),'[]'::jsonb),
    'approvals', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'title',title,'kind',kind,'kind_label',fn_ui_label('action_kind',kind),'risk',risk,'status',status,'created_at',created_at)) from (select * from agent_actions where status='pending' order by created_at desc limit 6) a),'[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object('actor',actor,'kind',kind,'kind_label',fn_ui_label('action_kind',kind),'decision',decision,'confidence',confidence,'route_to',route_to,'created_at',created_at)) from (select * from decision_log order by created_at desc limit 10) d),'[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(jsonb_build_object('type',type,'type_label',fn_ui_label('notification_type',type),'subject',subject,'status',status,'created_at',created_at)) from (select * from notifications order by created_at desc limit 6) n),'[]'::jsonb)
  );
$function$;

-- ---------------------------------------------------------------------------------------------
-- fn_founder_queue: the same, on the list he actually reads first.
--
-- Its rows render as "Core legal documents missing / legal · legal flag" on the OS home screen.
-- `kind` stays for routing; `kind_label` is what the founder should be reading.
-- Only the two jsonb_build_object calls changed.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_founder_queue(p_limit integer DEFAULT 12)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'waiting_on_you_total',
      (select count(*) from public.agent_actions a
         join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
        where a.status in ('pending','needs_review')),
    'oldest_days',
      (select round(extract(epoch from now() - min(a.created_at)) / 86400)::int
         from public.agent_actions a
         join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
        where a.status in ('pending','needs_review')),
    'waiting_on_you', coalesce((
      select jsonb_agg(x order by x->>'raised')
        from (select jsonb_build_object(
                       'id', a.id, 'kind', a.kind,
                       'kind_label', public.fn_ui_label('action_kind', a.kind),
                       'from', a.agent,
                       'title', left(coalesce(a.title, a.recommendation, ''), 160),
                       'raised', a.created_at,
                       'age_days', round(extract(epoch from now() - a.created_at) / 86400)::int) as x
                from public.agent_actions a
                join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
               where a.status in ('pending','needs_review')
               order by a.created_at
               limit greatest(coalesce(p_limit, 12), 1)) z), '[]'::jsonb),
    -- The machine's own work in flight, kept separate so the two are never added together again.
    'machine_is_working_on', (select count(*) from public.agent_actions a
                                join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
                               where a.status = 'pending'),
    -- A kind nobody has classified. Fail-closed and NAMED: the sweep will not queue it and the
    -- worker will not settle it, so if this list is not empty, work is sitting still and this is
    -- the only place that says so.
    'unrouted_kinds', coalesce((
      select jsonb_agg(jsonb_build_object('kind', k,
                                          'kind_label', public.fn_ui_label('action_kind', k),
                                          'pending', n, 'oldest_days', d))
        from (select a.kind k, count(*) n,
                     round(extract(epoch from now() - min(a.created_at)) / 86400)::int d
                from public.agent_actions a
               where a.status = 'pending'
                 and not exists (select 1 from public.agent_action_kind_policy p where p.kind = a.kind)
               group by a.kind order by 2 desc) y), '[]'::jsonb));
$function$;
