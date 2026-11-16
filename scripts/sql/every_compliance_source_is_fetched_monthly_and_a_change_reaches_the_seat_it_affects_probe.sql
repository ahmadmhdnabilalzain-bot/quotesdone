-- every_compliance_source_is_fetched_monthly_and_a_change_reaches_the_seat_it_affects_probe.sql (it_engineer, OPS_LOOPS, 16 Nov 2026)
-- A pure probe, run AFTER the file in the SAME transaction on a LOCAL Postgres 16 (scripts/db/local_pg16.mjs); it always
-- aborts (raise 'CHK<<...>>'), so nothing it writes survives. Its source is ZZ DEMO at example.invalid; the readings and the
-- model's answers are stubs; nothing is fetched and nothing is sent. Run twice on 16 Nov 2026: PROBE OK.
do $probe$
declare v_src bigint; d jsonb; r jsonb; v_q bigint; v_q2 bigint; v_res jsonb; v_act bigint; v_checked timestamptz;
begin
  update public.compliance_sources set active = false where active;        -- the local cluster holds none; only the probe's source counts
  insert into public.compliance_sources (authority, topic, url, active, last_checked_at, last_signature, last_summary)
  values ('ZZ DEMO Authority', 'ZZ DEMO fire code', 'https://www.example.invalid/code', true, now() - interval '98 days', 'old-watcher-sig',
          'ZZ DEMO: the 2018 fire code applies.') returning id into v_src;

  -- 1. it is due, and the allowlist is the registered hosts only
  d := public.fn_compliance_sources_due(6);
  if not (d->'sources') @> jsonb_build_array(jsonb_build_object('id', v_src)) then raise exception 'CHK<<PROBE FAILED: a 98-day-old source is not due: %>>', d; end if;
  if d->'allowed_hosts' <> '["www.example.invalid"]'::jsonb then raise exception 'CHK<<PROBE FAILED: the allowlist is not the registered hosts: %>>', d->'allowed_hosts'; end if;

  -- 2. a failed fetch is not a check, and it is not retried the same day
  r := public.fn_compliance_sources_record(jsonb_build_object('id', v_src, 'ok', false, 'error', 'http_404: the target answered 404'));
  if (select last_checked_at from public.compliance_sources where id = v_src) > now() - interval '90 days' then
    raise exception 'CHK<<PROBE FAILED: a failed fetch stamped the source checked>>'; end if;
  if (public.fn_compliance_sources_due(6)->'sources') @> jsonb_build_array(jsonb_build_object('id', v_src)) then
    raise exception 'CHK<<PROBE FAILED: a source that failed today is asked again today>>'; end if;
  -- three days running is the it_engineer's finding
  update public.compliance_sources set fetch_failures = 3 where id = v_src;
  r := public.fn_compliance_watch_settle('{}'::jsonb);
  if (r->>'failing_3_days')::int <> 1 then raise exception 'CHK<<PROBE FAILED: three failed days raised nothing: %>>', r; end if;
  if not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:compliance_watch') then
    raise exception 'CHK<<PROBE FAILED: the run was not recorded, so the step would be due for ever>>'; end if;

  -- 3a. a 200 whose text is a challenge page: asked, read as not the source, NOT checked
  r := public.fn_compliance_sources_record(jsonb_build_object('id', v_src, 'ok', true, 'signature', 'v2:cccccccccccccccc3333',
         'excerpt', 'ZZ DEMO Request unsuccessful. Incapsula incident ID: 000.', 'final_url', 'https://www.example.invalid/code'));
  v_res := public.fn_reason_held_resolve((r->>'held_id')::bigint, jsonb_build_object('status', 'answered', 'model', 'stub',
             'answer', 'A firewall challenge page, not the code.', 'decision', jsonb_build_object('choice', 'not_the_page')));
  if (select last_checked_at from public.compliance_sources where id = v_src) > now() - interval '90 days'
     or (select last_signature from public.compliance_sources where id = v_src) like 'v2:%' then
    raise exception 'CHK<<PROBE FAILED: a challenge page counted as a check>>'; end if;
  update public.compliance_sources set last_fetch_at = null where id = v_src;
  -- 3. the first read since the old watcher: asked of the CEO seat's model, with the old summary and the new text; checked
  --    only once the model has read it as the source
  r := public.fn_compliance_sources_record(jsonb_build_object('id', v_src, 'ok', true, 'signature', 'v2:aaaaaaaaaaaaaaaa1111',
         'excerpt', 'ZZ DEMO: the 2026 fire code applies from 1 January; sprinkler rules changed.', 'final_url', 'https://www.example.invalid/code'));
  select last_checked_at, change_held_id into v_checked, v_q from public.compliance_sources where id = v_src;
  if v_checked > now() - interval '90 days' or (r->>'outcome') is distinct from 'asked' or v_q is null then
    raise exception 'CHK<<PROBE FAILED: a changed page was not asked, or was checked before it was read: %>>', r; end if;
  if (select surface from public.reasoning_held_question where id = v_q) is distinct from 'ceo.compliance_change'
     or (select request->'context'->'case'->>'what_we_last_recorded' from public.reasoning_held_question where id = v_q) not like 'ZZ DEMO: the 2018%'
     or (select request->'context'->'case'->>'page_text_today' from public.reasoning_held_question where id = v_q) not like '%sprinkler%' then
    raise exception 'CHK<<PROBE FAILED: the question lacks the old summary or the new text>>'; end if;

  -- 5. the model names a department: nothing applied; it names the sales_engineer: the change is routed there
  v_res := public.fn_reason_apply_ceo__compliance_change(v_q, jsonb_build_object('answer', 'x', 'decision', jsonb_build_object('choice', 'Legal')));
  if v_res is not null then raise exception 'CHK<<PROBE FAILED: a seat that does not exist was routed to>>'; end if;
  v_res := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'model', 'stub',
             'answer', 'ZZ DEMO: the 2026 code changes sprinkler rules for fit-out contractors; their quotes must name the new standard.',
             'decision', jsonb_build_object('choice', 'sales_engineer')));
  v_act := nullif(v_res->'effect'->>'action_id', '')::bigint;
  if v_act is null or (select agent || '/' || kind || '/' || status from public.agent_actions where id = v_act) is distinct from 'sales_engineer/compliance_update/pending' then
    raise exception 'CHK<<PROBE FAILED: the change did not reach the seat it affects: %>>', v_res; end if;
  if (select last_changed_at from public.compliance_sources where id = v_src) < now() - interval '1 minute'
     or (select last_summary from public.compliance_sources where id = v_src) not like 'ZZ DEMO: the 2026 code%' then
    raise exception 'CHK<<PROBE FAILED: the change was not recorded on the source>>'; end if;
  if (select last_checked_at from public.compliance_sources where id = v_src) < now() - interval '1 minute' then
    raise exception 'CHK<<PROBE FAILED: a page the model read was not stamped checked>>'; end if;
  if (select fetch_failures from public.compliance_sources where id = v_src) <> 0 then raise exception 'CHK<<PROBE FAILED: a good read kept the failure count>>'; end if;
  -- 4. the same page again: checked, not asked again
  update public.compliance_sources set last_checked_at = now() - interval '40 days', last_fetch_at = null where id = v_src;
  r := public.fn_compliance_sources_record(jsonb_build_object('id', v_src, 'ok', true, 'signature', 'v2:aaaaaaaaaaaaaaaa1111', 'excerpt', 'same'));
  if (r->>'outcome') is distinct from 'unchanged' or (select last_checked_at from public.compliance_sources where id = v_src) < now() - interval '1 minute' then
    raise exception 'CHK<<PROBE FAILED: an unchanged page was not stamped checked: %>>', r; end if;

  -- 6. a later change the model reads as immaterial records its reading and routes nothing
  r := public.fn_compliance_sources_record(jsonb_build_object('id', v_src, 'ok', true, 'signature', 'v2:bbbbbbbbbbbbbbbb2222', 'excerpt', 'ZZ DEMO: a new footer.'));
  v_q2 := (r->>'held_id')::bigint;
  v_res := public.fn_reason_held_resolve(v_q2, jsonb_build_object('status', 'answered', 'model', 'stub',
             'answer', 'Only the page footer changed.', 'decision', jsonb_build_object('choice', 'none')));
  if (select last_review->>'material_change' from public.compliance_sources where id = v_src) is distinct from 'false'
     or (select count(*) from public.agent_actions where kind = 'compliance_update' and target_id = v_src::text) <> 1 then
    raise exception 'CHK<<PROBE FAILED: an immaterial change was routed or not recorded>>'; end if;

  raise exception 'CHK<<PROBE OK>>';
end $probe$;
