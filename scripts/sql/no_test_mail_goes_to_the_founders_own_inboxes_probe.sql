-- PROBE for no_test_mail_goes_to_the_founders_own_inboxes.sql (it_engineer, 27 Oct 2026). Pure: no DDL. Run after the
-- file in the SAME request (scripts/checks/no_test_mail_goes_to_the_founders_own_inboxes.test.mjs does), inside one
-- transaction that ends in raise exception 'CHK<<verdict|evidence>>', so nothing commits.
--
-- It CANNOT reach a person: every row it writes is uncommitted (send_outbox cannot see it) and has status 'cancelled'.
-- It never writes app_secrets: the campaign switches are read as they are (held), never flipped, even inside this
-- transaction (review of #1696). The open-day branch of the gate (one finding, then the same unconditional return) is
-- proved from the code by the check, not by switching the campaign on here.
-- It asserts: the morning seed queues nothing at the hour it used to; the gate fails closed by name and, while the
-- campaign is held, files nothing; a seed to each of his mailboxes (and a +tag, a dotted Gmail, a capitalised address, a cc, an update) is
-- refused; a seed to a non-founder test address and a founder_brief to management@ still go in.
do $$ declare
  o jsonb := '{}'; v_fail text[] := '{}'; d date; t timestamptz; r jsonb; n_before bigint; n_after bigint;
  a text; v_ok boolean; v_id bigint;
  v_founder text[] := array['management@quotesdone.com', 'ahmadmhdnabilalzain@gmail.com', 'management@doratajewelries.com',
                            'djzaino@outlook.com', 'bookings@djzaino.com', 'fati.labib@icloud.com',
                            'ahmadmhdnabilalzain+warmup@gmail.com', 'Ahmad.Mhd.Nabil.Alzain@gmail.com', 'MANAGEMENT@QuotesDone.com',
                            'QuotesDone <management@quotesdone.com>'];
begin
  select x::date into d from generate_series(current_date + 1, current_date + 30, interval '1 day') x
   where extract(isodow from x) < 6
     and not exists (select 1 from company_calendar c where c.kind = 'public_holiday'
                      and x::date between c.starts_on and coalesce(c.ends_on, c.starts_on))
   order by x limit 1;
  t := fn_invite_placement_deadline(d);

  -- 1. the morning seed: nothing queued at 04:35 UTC on the next weekday
  select count(*) into n_before from notifications where type = 'supplier_invite_seed';
  r := fn_invite_placement_due(t - interval '85 minutes');
  select count(*) into n_after from notifications where type = 'supplier_invite_seed';
  o := o || jsonb_build_object('due', r ->> 'action', 'due_reason', r ->> 'reason', 'seeds_queued', n_after - n_before,
    'check_row', exists (select 1 from invite_placement_check where dubai_day = d));
  if r ->> 'action' <> 'idle' or n_after <> n_before then v_fail := v_fail || 'the morning seed still queues'; end if;
  if exists (select 1 from invite_placement_check where dubai_day = d) then v_fail := v_fail || 'a placement check row was written'; end if;

  -- 2. the gate fails closed by name, before and after the old cutoff, and files nothing while the campaign is held
  o := o || jsonb_build_object('gate_early', fn_invite_placement_gate(d, t - interval '1 hour'),
                               'gate_late', fn_invite_placement_gate(d, fn_invite_placement_cutoff(d) + interval '1 minute'));
  if o ->> 'gate_early' <> 'fail:seed_retired' or o ->> 'gate_late' <> 'fail:seed_retired' then
    v_fail := v_fail || 'the gate does not fail closed as seed_retired'; end if;
  o := o || jsonb_build_object('gate_finding', (select count(*) from it_engineer_finding
                                                 where issue_key = 'deliverability:inbox_placement' and closed_at is null
                                                   and evidence ->> 'dubai_day' = d::text and evidence ->> 'verdict' = 'seed_retired'));
  o := o || jsonb_build_object('held_because', fn_invite_placement_day_closed(fn_invite_placement_cutoff(d) + interval '1 minute'));
  if o ->> 'held_because' is not null and (o ->> 'gate_finding')::int <> 0 then
    v_fail := v_fail || 'the retired gate filed a finding while the campaign is held'; end if;

  -- 3. a seed to any of his mailboxes is refused, both kinds
  foreach a in array v_founder loop
    v_ok := false;
    begin
      insert into notifications (type, kind, to_email, to_role, subject, body, lang, status, requested_by)
      values ('supplier_invite_seed', 'invite_m365_seed', a, 'supplier', 'ZZ DEMO probe', 'ZZ DEMO probe', 'en', 'cancelled', 'it_engineer');
    exception when check_violation then
      v_ok := sqlerrm like 'no_test_mail_to_the_founder:%';
    end;
    if not v_ok then v_fail := v_fail || ('a seed to ' || a || ' was not refused'); end if;
  end loop;
  v_ok := false;
  begin
    insert into notifications (type, to_email, cc_emails, to_role, subject, body, lang, status, requested_by)
    values ('supplier_invite_seed', 'zz-seed@example.invalid', array['djzaino@outlook.com'], 'supplier', 'ZZ DEMO probe', 'ZZ DEMO probe', 'en', 'cancelled', 'it_engineer');
  exception when check_violation then v_ok := true;
  end;
  if not v_ok then v_fail := v_fail || 'a seed with the founder in cc was not refused'; end if;

  -- 4. a non-founder seed goes in (the GlockApps seeds' path), and cannot be re-addressed to him afterwards
  insert into notifications (type, kind, to_email, to_role, subject, body, lang, status, requested_by)
  values ('supplier_invite_seed', 'invite_m365_seed', 'zz-glockapps-seed@example.invalid', 'supplier', 'ZZ DEMO probe', 'ZZ DEMO probe', 'en', 'cancelled', 'it_engineer')
  returning id into v_id;
  o := o || jsonb_build_object('other_seed_kept', v_id is not null);
  v_ok := false;
  begin
    update notifications set to_email = 'management@doratajewelries.com' where id = v_id;
  exception when check_violation then v_ok := true;
  end;
  if not v_ok then v_fail := v_fail || 'a seed re-addressed to the founder was not refused'; end if;

  -- 5. business mail to him is untouched by this rule
  v_ok := true;
  begin
    insert into notifications (type, kind, to_email, to_role, subject, body, lang, status, requested_by)
    values ('founder_brief', 'founder_brief', 'management@quotesdone.com', 'founder', 'ZZ DEMO probe', 'ZZ DEMO probe', 'en', 'cancelled', 'ceo');
  exception when others then
    v_ok := sqlerrm not like 'no_test_mail_to_the_founder:%';
  end;
  if not v_ok then v_fail := v_fail || 'a founder_brief was refused as a test'; end if;

  -- 6. the ledger and the policy
  o := o || jsonb_build_object(
    'ledger', (select status from founder_instruction where instruction = 'stop doing tests on my email. thats extremely useless'
                and subject = 'no test email to the founder''s own inboxes' order by id desc limit 1),
    'policy_allows_seed', (select allowed_to_email from founder_mail_policy where kind = 'supplier_invite_seed'));
  if coalesce(o ->> 'ledger', '') <> 'standing' then v_fail := v_fail || 'the instruction is not standing in the ledger'; end if;
  if coalesce((o ->> 'policy_allows_seed')::boolean, false) then v_fail := v_fail || 'the founder-mail policy still allows the seed'; end if;

  raise exception 'CHK<<%|%>>',
    case when cardinality(v_fail) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_fail, '; ') end, o::text;
end $$;
