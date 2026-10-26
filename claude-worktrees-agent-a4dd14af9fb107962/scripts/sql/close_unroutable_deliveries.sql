-- CLOSE THE DELIVERIES THAT CAN NEVER COME BACK — the backfill half of the fn_event_dispatch fix
-- of 6 Aug 2026.
--
-- An event_delivery with unroutable_reason set and task_id NULL is TERMINAL: the subscription names
-- an employee who does not exist, so no org_task was created, none ever will be, and no result can
-- ever be returned. Until today those rows sat with result/closed_at NULL forever, which files them
-- as "the loop is still open" when in fact the loop finished — badly, and the reason it finished is
-- already stored on the row. contract-consolidation scores the share of deliveries that came back
-- with a result AND a closed_at, so every broken subscription permanently subtracted from a ratio
-- that no amount of correct work could ever restore.
--
-- NOTHING IS INVENTED AND NOTHING IS BACK-DATED. `result` is derived from the unroutable_reason the
-- dispatcher itself wrote at delivery time; `closed_at` is now(), the moment this recognition was
-- made, NOT delivered_at. Guarded by `result is null` so re-running it is a no-op, and by
-- `task_id is null and unroutable_reason is not null` so it can only ever touch a delivery that
-- reached nobody — a delivery with a task is real work and is closed by fn_event_consolidate when
-- that work finishes, never here.
--
-- Measured before: 11 such rows on production, 0 on staging.
update public.event_delivery
   set result = left('unroutable: ' || unroutable_reason
                  || ' — nothing further will happen to this delivery', 1000),
       closed_at = now()
 where task_id is null
   and unroutable_reason is not null
   and result is null;
