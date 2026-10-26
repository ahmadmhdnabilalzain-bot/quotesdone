select now() at time zone 'utc' now_utc,
 (select jsonb_agg(jsonb_build_object('id',id,'surface',surface,'status',status,'created',created_at)) from reasoning_held_question where subject::text like '%"161"%' or subject::text like '%: 161%' or subject->>'email_id' = '161') held,
 (select max(started_at) from agent_runs where agent ilike '%accountant%') last_accountant_run;
