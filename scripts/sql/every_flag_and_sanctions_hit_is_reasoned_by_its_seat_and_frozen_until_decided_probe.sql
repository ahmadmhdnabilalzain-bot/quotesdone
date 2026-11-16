-- PROBE (never applied): every fraud flag and every sanctions hit is reasoned by its seat, and the party is frozen until
-- it is decided. Seats: ceo, accountant. Agent: FLAGS_DECIDED, 16 Nov 2026.
-- Runs inside ONE block that always raises, so nothing it writes survives (the change's file is run first in the same
-- transaction while it is pending). THE DATA IS ZZ DEMO ONLY: every party is made here, named 'ZZ DEMO', at the reserved
-- @example.invalid domain, and every notification it writes is to such an address (captured, never handed to a provider).
-- The base rows are written with session_replication_role = replica (no trigger runs for them); the behaviour under test
-- runs with triggers on. The sanctions list entry is made here too (run_tag 'zz_probe'), so no real entry is involved.
--
-- What it proves (each is a CONTROL first where a pass could be vacuous):
--   S1 the rehearsal screen finds the ZZ DEMO supplier AND the ZZ DEMO customer on the probe's own list entry;
--   S2 an open hit freezes the supplier (matching_blocked 'compliance_review', fn_is_matchable false);
--   S3 the CEO's answer is applied: false_positive lifts the freeze; confirmed bans the supplier and tells the customer who
--      holds its quote (no reason given, the supplier not named); confirmed bans a customer; a non-option raises;
--   F1 a new flag gets a close_by and a review at insert; the backlog is filed by the tick; an overdue flag is reported;
--   F2 customer_matches_supplier: the facts carry the IP equality and the supplier's trades; the customer's quotes in that
--      trade are held and in another trade are not; benign releases them; equal terms IP raises the flag in the tick;
--   V1 the fifth request in an hour carries plausibility.velocity and raises request_velocity;
--   B1 a supplier's second new-job notice in an hour waits, and the third is folded into it.
do $probe$
declare
  f text[] := '{}'; o jsonb := '{}'::jsonb; v jsonb; x record;
  v_run bigint; v_l1 bigint; v_l2 bigint; v_l3 bigint; v_l4 bigint; v_l5 bigint;
  v_c1 uuid := gen_random_uuid(); v_c2 uuid := gen_random_uuid(); v_c3 uuid := gen_random_uuid(); v_c4 uuid := gen_random_uuid(); v_c5 uuid := gen_random_uuid();
  v_i2 uuid := gen_random_uuid(); v_i3a uuid := gen_random_uuid(); v_i3b uuid := gen_random_uuid();
  v_q2 uuid := gen_random_uuid(); v_h bigint; v_ids bigint[]; v_n int; v_nid1 bigint; v_nid2 bigint; v_nid3 bigint;
  v_trade text := 'zzprobe_trade_' || substr(md5(random()::text), 1, 6);
begin
  -- ── fixtures (no trigger) ──
  set local session_replication_role = replica;
  insert into public.screening_run (source, entries, status, run_tag, note) values ('un_consolidated', 1, 'ok', 'zz_probe', 'ZZ DEMO probe list') returning id into v_run;
  insert into public.screening_entry (run_id, source, entry_type, reference, name, name_norm, tokens)
  values (v_run, 'un_consolidated', 'entity', 'ZZPROBE.01', 'Zzprobe Listed Holdings',
          public.fn_screening_normalise('Zzprobe Listed Holdings'), public.fn_screening_tokens('Zzprobe Listed Holdings'));
  insert into public.leads (company_name, email, lifecycle_stage, approval_status, verified, banned, matching_blocked, claimed, claimed_by)
  values ('ZZ DEMO — Zzprobe Listed Holdings Contracting', 'zzprobe-l1@example.invalid', 'registered', 'approved', true, false, false, true, 'zzprobe-l1@example.invalid')
  returning id into v_l1;
  insert into public.leads (company_name, email, lifecycle_stage, approval_status, verified, banned, matching_blocked, claimed, claimed_by)
  values ('ZZ DEMO — Zzprobe Listed Holdings Supplies', 'zzprobe-l2@example.invalid', 'registered', 'approved', true, false, false, true, 'zzprobe-l2@example.invalid')
  returning id into v_l2;
  insert into public.leads (company_name, email, lifecycle_stage, approval_status, verified, claimed, claimed_by, accepted_terms_ip)
  values ('ZZ DEMO — Probe Rival Pricing', 'zzprobe-l3@example.invalid', 'registered', 'approved', true, true, 'zzprobe-l3@example.invalid', '198.51.100.23')
  returning id into v_l3;
  insert into public.supplier_capabilities (supplier_id, trades, confirmed_at) values (v_l3, array[v_trade], now());
  insert into public.leads (company_name, email, lifecycle_stage, approval_status, verified, claimed, claimed_by, accepted_terms_ip)
  values ('ZZ DEMO — Probe Same Office', 'zzprobe-l4@example.invalid', 'registered', 'approved', true, true, 'zzprobe-l4@example.invalid', '198.51.100.77')
  returning id into v_l4;
  insert into public.leads (company_name, email, lifecycle_stage, approval_status, verified, claimed, claimed_by)
  values ('ZZ DEMO — Probe Busy Inbox', 'zzprobe-l5@example.invalid', 'registered', 'approved', true, true, 'zzprobe-l5@example.invalid')
  returning id into v_l5;
  insert into public.customers (id, full_name, email, tos_accepted_at) values
    (v_c1, 'ZZ DEMO Zzprobe Listed Holdings', 'zzprobe-c1@example.invalid', now()),
    (v_c2, 'ZZ DEMO Probe Buyer Two', 'zzprobe-c2@example.invalid', now()),
    (v_c3, 'ZZ DEMO Probe Buyer Three', 'zzprobe-c3@example.invalid', now()),
    (v_c4, 'ZZ DEMO Probe Buyer Four', 'zzprobe-c4@example.invalid', now()),
    (v_c5, 'ZZ DEMO Probe Buyer Five', 'zzprobe-c5@example.invalid', now());
  update public.customers set tos_ip = '198.51.100.23' where id = v_c3;
  update public.customers set tos_ip = '198.51.100.77' where id = v_c4;
  insert into public.inquiries (id, customer_id, category, summary, status) values
    (v_i2, v_c2, v_trade, 'ZZ DEMO probe request two', 'quoted'),
    (v_i3a, v_c3, v_trade, 'ZZ DEMO probe request three a', 'quoted'),
    (v_i3b, v_c3, 'zzprobe_other_trade', 'ZZ DEMO probe request three b', 'quoted');
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status) values (v_q2, v_i2, v_l2, 1000, 'submitted');
  set local session_replication_role = origin;

  -- ── S1 the screen ──
  perform set_config('qd.duty_fixtures', 'on', true);
  drop table if exists tmp_screen_sup;
  v := public.fn_supplier_sanctions_screen(array[v_run], 'zz_probe');
  o := o || jsonb_build_object('screen', v);
  if not exists (select 1 from public.supplier_screening_hit where lead_id = v_l1 and status = 'open') then f := f || 'S1: the ZZ DEMO supplier was not hit'::text; end if;
  if not exists (select 1 from public.supplier_screening_hit where lead_id = v_l2 and status = 'open') then f := f || 'S1: the second ZZ DEMO supplier was not hit'::text; end if;
  if not exists (select 1 from public.customer_screening_hit where customer_id = v_c1 and status = 'open') then f := f || 'S1: the ZZ DEMO customer was not screened'::text; end if;
  if exists (select 1 from public.customer_screening_hit where customer_id = v_c2) then f := f || 'S1: a customer with an unrelated name was hit'::text; end if;

  -- ── S2 the freeze ──
  select * into x from public.leads where id = v_l1;
  if not (x.matching_blocked and x.matching_block_reason = 'compliance_review') then f := f || ('S2: an open hit did not freeze matching: ' || coalesce(x.matching_block_reason, 'null'))::text; end if;
  if public.fn_is_matchable(x.verified, x.banned, x.matching_blocked, x.approval_status, x.permanently_closed, x.chat_strikes) then f := f || 'S2: a frozen supplier is still matchable'::text; end if;

  -- the tick runs (its questions on fixtures are not filed: nothing is paid for); its decide-by is in the facts
  v := public.fn_ceo_sanctions_review_tick();
  o := o || jsonb_build_object('ceo_tick', v);
  v := public.fn_ceo_sanctions_party_facts('supplier', v_l1, null);
  if (v->>'decide_by') is null or jsonb_array_length(v->'open_hits') < 1 or (v->'record'->>'company_name') is null then f := f || 'S3: the CEO''s facts lack the hits, the record or the decide-by'::text; end if;

  -- ── S3 the CEO's answer, applied ──
  select array_agg(id order by id) into v_ids from public.supplier_screening_hit where lead_id = v_l1 and status = 'open';
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values ('ceo', 'ceo.sanctions_hit', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('party', 'supplier', 'lead_id', v_l1, 'hit_ids', to_jsonb(v_ids)), 'probe', 'zzprobe:' || v_l1) returning id into v_h;
  v := public.fn_reason_held_resolve(v_h, jsonb_build_object('status', 'answered', 'decision', jsonb_build_object('choice', 'false_positive'), 'answer', 'ZZ DEMO a different company', 'model', 'probe'));
  if v->>'status' <> 'applied' then f := f || ('S3: false_positive not applied: ' || v::text)::text; end if;
  select * into x from public.leads where id = v_l1;
  if x.matching_blocked or exists (select 1 from public.supplier_screening_hit where lead_id = v_l1 and status = 'open') then f := f || 'S3: a false positive did not lift the freeze'::text; end if;

  select array_agg(id order by id) into v_ids from public.supplier_screening_hit where lead_id = v_l2 and status = 'open';
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values ('ceo', 'ceo.sanctions_hit', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('party', 'supplier', 'lead_id', v_l2, 'hit_ids', to_jsonb(v_ids)), 'probe', 'zzprobe:' || v_l2) returning id into v_h;
  v := public.fn_reason_held_resolve(v_h, jsonb_build_object('status', 'answered', 'decision', jsonb_build_object('choice', 'confirmed'), 'answer', 'ZZ DEMO the listed party', 'model', 'probe'));
  if not exists (select 1 from public.sanctions_ban where lead_id = v_l2) then f := f || ('S3: confirmed did not ban the supplier: ' || v::text)::text; end if;
  select count(*) into v_n from public.notifications n
   where n.type = 'supplier_no_longer_available' and n.to_email = 'zzprobe-c2@example.invalid' and n.inquiry_id = v_i2;
  if v_n <> 1 then f := f || ('S3: the customer holding the banned supplier''s quote was told ' || v_n || ' times, not once')::text; end if;
  if exists (select 1 from public.notifications n where n.type = 'supplier_no_longer_available' and n.inquiry_id = v_i2
               and (n.body ilike '%sanction%' or n.body ilike '%Zzprobe%')) then f := f || 'S3: the notice states a reason or names the unrevealed supplier'::text; end if;

  select array_agg(id order by id) into v_ids from public.customer_screening_hit where customer_id = v_c1 and status = 'open';
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values ('ceo', 'ceo.sanctions_hit', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('party', 'customer', 'customer_id', v_c1, 'hit_ids', to_jsonb(v_ids)), 'probe', 'zzprobe:' || v_c1) returning id into v_h;
  v := public.fn_reason_held_resolve(v_h, jsonb_build_object('status', 'answered', 'decision', jsonb_build_object('choice', 'confirmed'), 'answer', 'ZZ DEMO', 'model', 'probe'));
  if not exists (select 1 from public.customers where id = v_c1 and banned) or exists (select 1 from public.customer_screening_hit where customer_id = v_c1 and status = 'open') then
    f := f || ('S3: a confirmed customer hit did not ban the customer: ' || v::text)::text;
  end if;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values ('ceo', 'ceo.sanctions_hit', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb, '{"party":"supplier","hit_ids":[]}'::jsonb, 'probe', 'zzprobe:bad') returning id into v_h;
  begin
    v := public.fn_reason_held_resolve(v_h, '{"status":"answered","decision":{"choice":"probably"}}'::jsonb);
    f := f || 'S3: an answer that is not an option was applied'::text;
  exception when others then
    if sqlerrm not like 'CHOICE_NOT_AN_OPTION%' then f := f || ('S3: a non-option failed for the wrong reason: ' || sqlerrm)::text; end if;
  end;
  if not exists (select 1 from public.org_task_kind_handler where action_class = 'compliance_check' and owner_seat = 'ceo') then f := f || 'S3: compliance_check has no handler'::text; end if;

  -- ── F1 every flag is reasoned, with a close-by date ──
  insert into public.fraud_flags (kind, subject_type, subject_id, severity, detail) values ('free_email_company', 'lead', v_l5::text, 'low', '{}'::jsonb);
  select detail into v from public.fraud_flags where kind = 'free_email_company' and subject_type = 'lead' and subject_id = v_l5::text;
  if (v->>'close_by') is null or not (v ? 'review') then f := f || ('F1: a new flag got no close_by or review: ' || v::text)::text; end if;
  if (v->>'close_by')::timestamptz < now() + interval '9 days' then f := f || 'F1: a low flag''s close_by is not 10 days'::text; end if;
  set local session_replication_role = replica;   -- a flag written past the trigger: the backlog
  insert into public.fraud_flags (kind, subject_type, subject_id, severity, detail, created_at) values
    ('refund_pattern', 'customer', v_c5::text, 'medium', '{}'::jsonb, now() - interval '13 days'),
    ('disposable_email', 'customer', v_c4::text, 'high', jsonb_build_object('close_by', now() - interval '1 day', 'review', jsonb_build_object('filed_at', now() - interval '3 days')), now() - interval '3 days');
  set local session_replication_role = origin;
  v := public.fn_accountant_flag_review_tick();
  o := o || jsonb_build_object('flag_tick', v);
  if not exists (select 1 from public.fraud_flags where kind = 'refund_pattern' and subject_id = v_c5::text and detail ? 'review' and detail ? 'close_by') then f := f || 'F1: the backlog flag was not filed by the tick'::text; end if;
  -- a flag 13 days old gets its 5 days from filing, and is not reported overdue in the hour it is first filed
  if exists (select 1 from public.fraud_flags where kind = 'refund_pattern' and subject_id = v_c5::text and ((detail->>'close_by')::timestamptz < now() + interval '4 days' or detail ? 'overdue_reported_at')) then f := f || 'F1: a backlog flag was reported overdue as soon as it was filed'::text; end if;
  if not exists (select 1 from public.fraud_flags where kind = 'disposable_email' and subject_id = v_c4::text and detail ? 'overdue_reported_at') then f := f || 'F1: an overdue flag was not reported to the CEO'::text; end if;

  -- ── F2 a supplier posing as a customer ──
  -- control: the equal IP was raised by the tick for the fourth buyer and the fourth supplier (terms_ip)
  if not exists (select 1 from public.fraud_flags where kind = 'customer_matches_supplier' and subject_id = v_c4::text
                   and detail->'lead_ids' @> to_jsonb(v_l4) and detail->'on' ? 'terms_ip' and detail ? 'review') then f := f || 'F2: equal terms IP did not raise customer_matches_supplier'::text; end if;
  -- the tick also raised it for the third buyer and the rival; its facts and the hold
  v := public.fn_accountant_flag_facts('customer_matches_supplier', 'customer', v_c3::text);
  o := o || jsonb_build_object('cms_facts_keys', (select jsonb_agg(k) from jsonb_object_keys(coalesce(v->'suppliers_it_matches'->0, '{}'::jsonb)) k));
  if not coalesce((v->'suppliers_it_matches'->0->>'same_terms_ip')::boolean, false) then f := f || ('F2: the facts do not carry the IP equality: ' || left(v::text, 400))::text; end if;
  if not coalesce(v->'suppliers_it_matches'->0->'trades' ? v_trade, false) then f := f || 'F2: the facts do not carry the supplier''s trades'::text; end if;
  if coalesce((v->'suppliers_it_matches'->0->>'customer_requests_in_these_trades')::int, 0) <> 1 then f := f || 'F2: the customer''s requests in the trade are not counted'::text; end if;
  -- an equal IP alone (a shared office, a carrier's NAT) holds nothing before the verdict
  v := public.fn_customer_quotes_being_checked(v_c3);
  if coalesce(jsonb_array_length(v->'inquiry_ids'), 0) <> 0 then f := f || ('F2: an equal IP alone held a customer''s quotes before any verdict: ' || v::text)::text; end if;
  if exists (select 1 from public.fraud_flags where kind = 'customer_matches_supplier' and subject_id = v_c3::text and severity = 'high') then f := f || 'F2: an equal IP alone raised a HIGH flag (the money screen holds reveals on it)'::text; end if;
  update public.fraud_flags set status = 'escalated' where kind = 'customer_matches_supplier' and subject_id = v_c3::text;   -- a genuine verdict
  v := public.fn_customer_quotes_being_checked(v_c3);
  if not coalesce(v->'inquiry_ids' ? v_i3a::text, false) then f := f || ('F2: the request in the supplier''s trade is not held: ' || v::text)::text; end if;
  if coalesce(v->'inquiry_ids' ? v_i3b::text, false) then f := f || 'F2: a request in another trade is held'::text; end if;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values ('accountant', 'accountant.fraud_flag', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('kind', 'customer_matches_supplier', 'subject_type', 'customer', 'subject_id', v_c3::text), 'probe', 'zzprobe:cms') returning id into v_h;
  v := public.fn_reason_held_resolve(v_h, '{"status":"answered","decision":{"choice":"benign"},"answer":"ZZ DEMO a shared office network","model":"probe"}'::jsonb);
  if not exists (select 1 from public.fraud_flags where kind = 'customer_matches_supplier' and subject_id = v_c3::text and status = 'dismissed')
     or jsonb_array_length(public.fn_customer_quotes_being_checked(v_c3)->'inquiry_ids') <> 0 then f := f || ('F2: benign did not release the held quotes: ' || v::text)::text; end if;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values ('accountant', 'accountant.fraud_flag', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('kind', 'customer_matches_supplier', 'subject_type', 'customer', 'subject_id', v_c4::text), 'probe', 'zzprobe:cms4') returning id into v_h;
  v := public.fn_reason_held_resolve(v_h, '{"status":"answered","decision":{"choice":"genuine"},"answer":"ZZ DEMO","model":"probe"}'::jsonb);
  if not exists (select 1 from public.fraud_flags where kind = 'customer_matches_supplier' and subject_id = v_c4::text and status = 'escalated') then f := f || 'F2: genuine did not escalate the flag'::text; end if;

  -- ── V1 velocity ──
  for v_n in 1..5 loop
    insert into public.inquiries (customer_id, category, summary, status) values (v_c5, 'zzprobe_velocity', 'ZZ DEMO probe burst request number ' || v_n || ' ' || md5(v_n::text), 'open');
  end loop;
  select plausibility into v from public.inquiries where customer_id = v_c5 order by created_at desc, summary desc limit 1;
  if coalesce((v->'velocity'->>'requests_last_hour')::int, 0) <> 5 then f := f || ('V1: the fifth request does not carry its velocity: ' || coalesce(v::text, 'null'))::text; end if;
  if not exists (select 1 from public.fraud_flags where kind = 'request_velocity' and subject_id = v_c5::text and severity = 'medium' and detail ? 'review') then f := f || 'V1: five requests in an hour raised no reasoned request_velocity flag'::text; end if;

  -- ── B1 one new-job notice per supplier per hour ──
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, channel)
  values ('new_inquiry', 'zzprobe-l5@example.invalid', 'supplier', v_l5, 'New job request on QuotesDone', 'ZZ DEMO job one', 'queued', 'email') returning id into v_nid1;
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, channel)
  values ('new_inquiry', 'zzprobe-l5@example.invalid', 'supplier', v_l5, 'New job request on QuotesDone', 'ZZ DEMO job two', 'queued', 'email') returning id into v_nid2;
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, channel)
  values ('new_inquiry', 'zzprobe-l5@example.invalid', 'supplier', v_l5, 'New job request on QuotesDone', 'ZZ DEMO job three', 'queued', 'email') returning id into v_nid3;
  select * into x from public.notifications where id = v_nid1;
  if x.not_before is not null and x.not_before > now() then f := f || 'B1: the first notice of the hour was delayed'::text; end if;
  select * into x from public.notifications where id = v_nid2;
  if x.not_before is null or x.not_before < now() + interval '59 minutes' or coalesce(x.dedupe_key, '') not like 'new_job_batch:%' then f := f || ('B1: the second notice did not wait for the hour: ' || coalesce(x.not_before::text, 'null'))::text; end if;
  if x.body not like '%ZZ DEMO job three%' or x.subject not like '%(2)%' then f := f || ('B1: the third job was not folded into the batch: ' || coalesce(x.subject, ''))::text; end if;
  select * into x from public.notifications where id = v_nid3;
  if x.status <> 'merged' then f := f || ('B1: the folded notice is ' || coalesce(x.status, 'null') || ', not merged')::text; end if;
  -- B2 a SECOND supplier's batch row in the same hour lands too (notifications_dedupe_key_uidx is unique over every row)
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, channel)
  values ('new_inquiry', 'zzprobe-l4@example.invalid', 'supplier', v_l4, 'New job request on QuotesDone', 'ZZ DEMO other one', 'queued', 'email');
  begin
    insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, channel)
    values ('new_inquiry', 'zzprobe-l4@example.invalid', 'supplier', v_l4, 'New job request on QuotesDone', 'ZZ DEMO other two', 'queued', 'email') returning id into v_nid3;
    if not exists (select 1 from public.notifications where id = v_nid3 and not_before > now() + interval '59 minutes') then f := f || 'B2: the second supplier''s second notice did not wait'::text; end if;
  exception when unique_violation then f := f || 'B2: the second supplier''s batch row was refused (unique dedupe_key): the notice is lost'::text;
  end;

  raise exception 'CHK<<%>>', (jsonb_build_object('ok', cardinality(f) = 0, 'failures', to_jsonb(f)) || o)::text;
end $probe$;
