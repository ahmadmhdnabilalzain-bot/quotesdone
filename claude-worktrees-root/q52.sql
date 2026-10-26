select step, last_started_at from resilience_step where step in ('itChangeWatch','changeWatch','it_change_watch') or step ilike '%change%';
