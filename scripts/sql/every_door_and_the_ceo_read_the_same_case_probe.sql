-- every_door_and_the_ceo_read_the_same_case_probe.sql (sales_engineer builder (every door reads the same case), 16 Nov 2026)
-- A pure probe: run AFTER the file, in the SAME transaction, which this probe always aborts (raise 'CHK<<...>>'), so nothing it
-- does survives. Every subject is created here and is ZZ DEMO with an @example.invalid address and a number no person holds;
-- the fault is filed under the duty fixtures switch (a fixture report, never a live one), and no message reaches anyone (the
-- report has no address, so "fixed" is recorded as not told). Run 16 Nov 2026 twice on a local Postgres 16 from the schema
-- mirror (scripts/db/local_pg16.mjs, with support_and_the_it_engineer_hand_a_fault_both_ways.sql applied first, as it is on
-- production): PROBE OK both times. Each rule below was broken once in a scratch copy and is named in its failure.
do $probe$
declare
  v_email constant text := 'zz-samecase-probe@example.invalid';
  v_phone constant text := '+971 50 000 0111';
  v_cust uuid; v_other uuid; v_inq uuid; v_prof bigint; v_ref text; v_tx uuid;
  f jsonb; l jsonb; tl jsonb; ev jsonb; pr jsonb; chk jsonb; item jsonb; w jsonb;
  v_real_cases int; v_real_cases_after int; v_real_reports int; v_real_reports_after int;
begin
  perform set_config('qd.duty_fixtures', 'on', true);             -- the hand-over files fixtures only, in this transaction
  select count(*) into v_real_cases from public.support_case where linked_refs ? 'faults';
  select count(*) into v_real_reports from public.support_fault_report where not fixture;

  -- a ZZ DEMO customer with one request and one support case, known to support by the reserved address and a demo number
  -- his number is VERIFIED and his WhatsApp is that number: a phone may confirm an identity, never select one
  -- (a_phone_tail_never_joins_two_people.sql, applied before this file; release wave C)
  insert into public.customers (full_name, email, phone, phone_verified, whatsapp_opt)
  values ('ZZ DEMO samecase probe', v_email, v_phone, true, 'same') returning id into v_cust;
  insert into public.customers (full_name, email) values ('ZZ DEMO samecase other', 'zz-samecase-other@example.invalid') returning id into v_other;
  insert into public.inquiries (customer_id, summary, status) values (v_cust, 'ZZ DEMO samecase probe: 6 windows', 'sent') returning id into v_inq;
  v_prof := public.fn_support_profile_resolve('customer', v_cust::text, v_email, null);
  v_ref := public.fn_support_case_route(v_prof, 'new', null, 'widget', 'ZZ DEMO samecase probe', 'en') ->> 'case_ref';
  if v_ref is null then raise exception 'CHK<<PROBE FAILED: no case was opened>>'; end if;

  -- 1. ITEM 8: a fault he reports on WhatsApp (no identity on the report) is written onto his case by his number
  f := public.fn_support_hands_it_a_fault('whatsapp', 'whatsapp:zzdemo0samecase', 'en', 'customer',
         jsonb_build_array(jsonb_build_object('role', 'person', 'text', 'ZZ DEMO the upload button does nothing')), null);
  if not coalesce((f ->> 'filed')::boolean, false) then raise exception 'CHK<<PROBE FAILED: the fixture fault was not filed: %>>', f; end if;
  l := public.fn_support_case_links_a_fault('customer', null, null, v_phone, f ->> 'issue_key', 'whatsapp');
  if not coalesce((l ->> 'linked')::boolean, false) or l ->> 'case_ref' <> v_ref then
    raise exception 'CHK<<PROBE FAILED: the fault was not linked to his case by his number: %>>', l; end if;
  -- the same nine digits under another country's code name nobody: nothing is linked to his case (release wave C)
  l := public.fn_support_case_links_a_fault('customer', null, null, '+999 50 000 0111', f ->> 'issue_key', 'whatsapp');
  if coalesce((l ->> 'linked')::boolean, true) then
    raise exception 'CHK<<PROBE FAILED: another country''s number with his last nine digits reached his case: %>>', l; end if;
  if jsonb_array_length(public.fn_person_open_promises('customer', null, null, '+999 50 000 0111', 10)) <> 0 then
    raise exception 'CHK<<PROBE FAILED: another country''s number with his last nine digits reads his promises>>'; end if;
  l := public.fn_support_case_links_a_fault('customer', v_cust::text, v_email, null, f ->> 'issue_key', 'whatsapp');
  if not coalesce((l ->> 'already')::boolean, false) then raise exception 'CHK<<PROBE FAILED: a second link wrote it twice: %>>', l; end if;
  if (select jsonb_array_length(linked_refs -> 'faults') from public.support_case where case_ref = v_ref) <> 1 then
    raise exception 'CHK<<PROBE FAILED: linked_refs.faults is not one entry>>'; end if;
  -- a key no report carries, or a key of the wrong shape, plants nothing
  l := public.fn_support_case_links_a_fault('customer', v_cust::text, null, null, 'support:fault:0000000000000000', 'widget');
  if coalesce((l ->> 'linked')::boolean, true) then raise exception 'CHK<<PROBE FAILED: an unfiled fault key was linked>>'; end if;
  l := public.fn_support_case_links_a_fault('customer', v_cust::text, null, null, 'anything', 'widget');
  if coalesce((l ->> 'linked')::boolean, true) then raise exception 'CHK<<PROBE FAILED: a free-text key was linked>>'; end if;
  l := public.fn_support_case_links_a_fault('customer', null, null, null, f ->> 'issue_key', 'widget');
  if coalesce((l ->> 'linked')::boolean, true) then raise exception 'CHK<<PROBE FAILED: a fault was linked with no identity>>'; end if;

  -- 2. every door's timeline sees it, open, by his e-mail (the widget, the CEO) and by his number (WhatsApp)
  tl := public.fn_contact_timeline(v_email, 60);
  select x into ev from jsonb_array_elements(tl -> 'events') x where x ->> 'kind' = 'it_fault';
  if ev is null or ev ->> 'summary' !~ '^open: reported on whatsapp' or ev ->> 'ref' <> f ->> 'issue_key' then
    raise exception 'CHK<<PROBE FAILED: the e-mail timeline does not show the open fault: %>>', coalesce(ev, tl); end if;
  if ev::text ~* 'upload button' then raise exception 'CHK<<PROBE FAILED: the timeline carries his words>>'; end if;
  tl := public.fn_contact_timeline('whatsapp:' || v_phone, 60);
  if not exists (select 1 from jsonb_array_elements(tl -> 'events') x where x ->> 'kind' = 'it_fault') then
    raise exception 'CHK<<PROBE FAILED: the WhatsApp timeline does not show the fault>>'; end if;
  if exists (select 1 from jsonb_array_elements(public.fn_contact_timeline('zz-samecase-other@example.invalid', 60) -> 'events') x where x ->> 'kind' = 'it_fault') then
    raise exception 'CHK<<PROBE FAILED: another person sees his fault>>'; end if;

  -- 3. fixed: the timeline says so, and that he holds no address to be told at
  w := public.fn_support_fault_fixed(f ->> 'issue_key', null, 'ZZ DEMO the upload works again');
  select x into ev from jsonb_array_elements(public.fn_contact_timeline(v_email, 60) -> 'events') x where x ->> 'kind' = 'it_fault';
  if ev ->> 'summary' !~ '^fixed: ZZ DEMO the upload works again \(not told' then
    raise exception 'CHK<<PROBE FAILED: the timeline does not show the fix: % (%)>>', ev, w; end if;

  -- 4. ITEM 1 and 9: the promise his case records is his open promise, by his id, by his e-mail, never another person's
  w := public.fn_support_case_summary_write(v_ref, 0, jsonb_build_object('asked', 'ZZ DEMO 6 windows', 'said_or_did', 'took the sizes', 'open', '[]'::jsonb,
         'promised', jsonb_build_array(jsonb_build_object('what', 'send the quotes', 'by', 'in 24 hours', 'kind', 'quotes',
           'due_at', to_char((now() + interval '24 hours') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')))),
         'ASKED: ZZ DEMO 6 windows', 'ZZ DEMO windows', 'sales_engineer');
  if not coalesce((w ->> 'ok')::boolean, false) then raise exception 'CHK<<PROBE FAILED: the summary was not written: %>>', w; end if;
  pr := public.fn_person_open_promises('customer', v_cust::text, null, null, 10);
  if jsonb_array_length(pr) <> 1 or pr -> 0 ->> 'what' <> 'send the quotes' or pr -> 0 ->> 'case_ref' <> v_ref or pr -> 0 ->> 'owner_seat' <> 'sales_engineer' then
    raise exception 'CHK<<PROBE FAILED: his open promise is not read by his id: %>>', pr; end if;
  if jsonb_array_length(public.fn_person_open_promises('customer', null, v_email, null, 10)) <> 1 then
    raise exception 'CHK<<PROBE FAILED: his open promise is not read by his e-mail>>'; end if;
  if jsonb_array_length(public.fn_person_open_promises('customer', null, null, v_phone, 10)) <> 1 then
    raise exception 'CHK<<PROBE FAILED: his open promise is not read by his verified WhatsApp number>>'; end if;
  if jsonb_array_length(public.fn_person_open_promises('customer', null, null, '+999 50 000 0111', 10)) <> 0 then
    raise exception 'CHK<<PROBE FAILED: another country''s number with his last nine digits reads his promise>>'; end if;
  if jsonb_array_length(public.fn_person_open_promises('customer', v_other::text, null, null, 10)) <> 0 then
    raise exception 'CHK<<PROBE FAILED: another person reads his promise>>'; end if;
  if (select count(*) from public.support_customer_profile where customer_id = v_other) <> 0 then
    raise exception 'CHK<<PROBE FAILED: reading promises created a profile>>'; end if;

  -- 5. ITEM 9: the CEO's refund checklist records his timeline and his open promise, and still decides only on the terms' items
  insert into public.transactions (customer_id, inquiry_id) values (v_cust, v_inq) returning id into v_tx;
  chk := public.fn_ceo_refund_checklist(v_tx, 'approve', false);
  select x into item from jsonb_array_elements(chk -> 'items') x where x ->> 'item' = 'what_he_was_told_and_promised_on_every_channel';
  if item is null or not coalesce((item ->> 'passed')::boolean, false) or item ->> 'kind' <> 'information' then
    raise exception 'CHK<<PROBE FAILED: the checklist has no passing information item 1b: %>>', chk; end if;
  if jsonb_array_length(item -> 'evidence' -> 'open_promises') <> 1
     or not exists (select 1 from jsonb_array_elements(item -> 'evidence' -> 'timeline_since_reveal') x where x ->> 'kind' = 'it_fault')
     or not exists (select 1 from jsonb_array_elements(item -> 'evidence' -> 'timeline_since_reveal') x where x ->> 'kind' = 'support_case') then
    raise exception 'CHK<<PROBE FAILED: item 1b does not carry his timeline and promise: %>>', item; end if;
  if exists (select 1 from jsonb_array_elements(chk -> 'failed') x where x ->> 'item' = 'what_he_was_told_and_promised_on_every_channel') then
    raise exception 'CHK<<PROBE FAILED: item 1b can fail a refund>>'; end if;

  -- 6. nothing real moved
  select count(*) into v_real_cases_after from public.support_case where linked_refs ? 'faults' and case_ref <> v_ref;
  select count(*) into v_real_reports_after from public.support_fault_report where not fixture;
  if v_real_cases_after <> v_real_cases or v_real_reports_after <> v_real_reports then
    raise exception 'CHK<<PROBE FAILED: real rows moved (cases % -> %, reports % -> %)>>', v_real_cases, v_real_cases_after, v_real_reports, v_real_reports_after; end if;

  raise exception 'CHK<<PROBE OK %>>', jsonb_build_object('case', v_ref, 'fault', f ->> 'issue_key', 'items', jsonb_array_length(chk -> 'items'));
end $probe$;
