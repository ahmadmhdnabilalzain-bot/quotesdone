-- TWO LIVE INVITE TASKS WERE ONE QUEUE POSITION FROM FIRING.
--
-- org_tasks 1360 "Start invites: kitchen-and-bathroom-suppliers" and 1361 "Start invites:
-- real-estate-agencies" are action_class='invite', tier='autonomous', status='assigned', wired to
-- fn_org_exec_invite with risk_tier='high', advisory_safe=false, reversible=false.
--
-- cos_execute builds its executor map filtered ONLY on `active`, so if its FIFO pick ever reached
-- these rows it would run that executor. Today it cannot: they hold the two highest ids behind 385
-- older tasks. That is queue position, not a guard, and queue position changes every hour.
--
-- The founder's standing decision, 12 Aug 2026: "LAST — supplier invites. DO NOT ENABLE YET",
-- because the bounce rate is at or above the platform's own 0.08 brake and a burned sending domain
-- takes real customer mail with it. That decision is already made; leaving two rows that can act
-- against it and writing it up for him to read later is not honouring it.
--
-- 'proposed' IS THE MECHANISM THAT ALREADY EXISTS. cos_execute's own header: "GATED tasks are
-- status='proposed' and are NEVER touched here — they wait for the founder." No new flag, no new
-- guard, no weakened check — the permission model was built for exactly this case and these two rows
-- were simply in the wrong lane. One UPDATE back to 'assigned' releases them the day invites are
-- enabled.
update public.org_tasks
   set status = 'proposed', updated_at = now(),
       detail = coalesce(detail,'') ||
         E'\n\n[12 Aug 2026] Moved assigned -> proposed. Wired to fn_org_exec_invite: risk_tier=high, '
         'advisory_safe=false, reversible=false. Supplier invitations are not enabled until one real '
         'registration completes end to end and bounce is under the platform brake. cos_execute never '
         'touches status=proposed. Reverse with a single UPDATE back to assigned.'
 where action_class = 'invite'
   and status in ('assigned','in_progress');
