-- THE BACKBONE REACHES EVERY EAR (autonomy audit, degrading gap 13, part A).
--
-- MEASURED (company_event GROUP BY event_type LEFT JOIN event_subscription): of every emitted event
-- type, exactly ONE has zero active subscribers — task.assigned (233 emitted, 0 subs). It is the
-- Operations OS's own declared os_interface OUTPUT, and all 233 payloads carry subject_type='org_task'
-- with a subject that still exists, so a subscriber ATTACHES each delivery to the already-assigned task
-- (an ownership receipt) and creates no new work. Every other emitted type already has a live subscriber.
--
-- THIS FILE subscribes task.assigned to the Operations director. It is inserted active=false, matching
-- the disabled-cron discipline of the founder stand-down: the routing is wired and durable, and the
-- founder flips it active on resume (at which point the 233 backlog events attach to their tasks). No
-- new work, no LLM, no frozen touch.
--
--   node scripts/apply_sql.mjs scripts/sql/the_backbone_reaches_every_ear.sql --apply --ddl

begin;

insert into public.event_subscription (agent_key, event_type, reason, active)
values ('ops_director', 'task.assigned',
        'Operations OS owns execution; task.assigned is its declared os_interface OUTPUT. Closes the '
        || 'dangling output — the dispatcher attaches each delivery to the already-assigned org_task '
        || '(payload subject_type/subject_id), an ownership receipt, never new work. Inserted inactive '
        || 'under the founder stand-down; flip active on resume.',
        false)
on conflict (agent_key, event_type) do update
  set reason = excluded.reason;

commit;
