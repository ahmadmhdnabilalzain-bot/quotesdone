-- PROBE: A CONFIRMED SANCTIONS HIT LEAVES A PARTY UNREACHABLE, AND THE RECORD SURVIVES.
--
-- PURE PROBE. It contains no DDL, so `raise exception` at the end is correct and required: the
-- whole transaction rolls back and the ZZ DEMO party, its screening run, its entry, its hit and its
-- sanctions_ban row all disappear. Nothing it creates can be deleted afterwards by design
-- (public.sanctions_ban is append-only and a sanctioned lead cannot be deleted), so the aborted
-- transaction is not a convenience here -- it is the only way to run this against production
-- without leaving a permanent record of a company that does not exist.
--
-- INCAPABLE OF REACHING A REAL PERSON, not merely careful: the company name begins 'ZZ DEMO', the
-- addresses are @example.invalid (RFC 2606, undeliverable by definition) and the licence number is
-- a literal that cannot be issued. The first thing the probe does is assert that no live row
-- already holds those values, so it can never adopt somebody else's record.
--
-- The verdict is RAISED, not noticed: the Supabase management API discards `raise notice`, so a
-- probe that reports with a notice reports to nobody.
--
--   node scripts/qsql.mjs scripts/sql/probe_a_sanctioned_party_is_unreachable.sql
--   -> ERROR  CHK<<sanctioned party unreachable: ... >>   on success
--   -> ERROR  PROBE FAILED: ...                           on failure
do $probe$
declare
  v_name   text := 'ZZ DEMO Sanctioned Contracting LLC';
  v_name2  text := 'zz demo sanctioned contracting l.l.c.';   -- same identity, different spelling
  v_lic    text := 'ZZDEMO-SANCT-0001';
  v_lic2   text := 'zzdemo sanct 0001';                       -- same licence, different spelling
  v_mail   text := 'zz.demo.sanctioned@example.invalid';
  v_mail2  text := 'zz.demo.sanctioned.again@example.invalid';
  v_phone  text := '+971500000096';                           -- the fixture range; no handset answers it
  v_lead bigint; v_run bigint; v_entry bigint; v_hit bigint; v_dec jsonb; v_tok uuid;
  v_lead2 bigint; n int; b boolean;
  f text[] := '{}';   -- failures
  p text[] := '{}';   -- what was proved, with its number
begin
  -- 0. THE FIXTURE CANNOT COLLIDE WITH A REAL ROW
  select count(*) into n from public.leads
   where company_name in (v_name, v_name2) or lower(email) in (v_mail, v_mail2)
      or public.fn_sanctions_identity_key(trade_license_no) = public.fn_sanctions_identity_key(v_lic);
  if n <> 0 then
    raise exception 'PROBE REFUSED: % live lead(s) already carry the fixture identity. The probe will not adopt a row it did not create.', n;
  end if;

  -- 1. THE PARTY, THE LIST AND THE HIT
  insert into public.screening_run (source, source_url, fetched_at, sha256, entries, status, run_tag)
  values ('un_consolidated', 'probe://sanctioned-party-unreachable', now(), 'probe', 1, 'ok', 'zz-demo-sanctions-probe')
  returning id into v_run;

  insert into public.screening_entry (run_id, source, entry_type, reference, name)
  values (v_run, 'un_consolidated', 'entity', 'ZZ-DEMO-PROBE-1', v_name)
  returning id into v_entry;

  -- lifecycle_stage only: approval_status 'approved' is refused by the mandatory-six gate for a
  -- supplier with no licence documents.
  insert into public.leads (company_name, email, claimed_by, claimed, trade_license_no, lifecycle_stage, claim_token, invite_status,
                            phone, owner_phone_verified, whatsapp_opt)
  values (v_name, v_mail, v_mail, true, v_lic, 'registered', gen_random_uuid(), null,
          v_phone, true, 'same')
  returning id, claim_token into v_lead, v_tok;

  insert into public.supplier_screening_hit
    (run_id, lead_id, field, supplier_value, entry_id, entry_name, entry_source, entry_reference,
     entry_type, match_kind, score, status)
  values (v_run, v_lead, 'company_name', v_name, v_entry, v_name, 'un_consolidated', 'ZZ-DEMO-PROBE-1',
          'entity', 'exact', 1.0, 'open')
  returning id into v_hit;

  -- 2. THE CEO CONFIRMS IT
  v_dec := public.fn_supplier_screening_decide(v_hit, 'confirmed', 'ceo');
  if not coalesce((v_dec ->> 'ok')::boolean, false) then
    raise exception 'PROBE FAILED: the decision did not run: %', v_dec;
  end if;

  -- 3. THE REGISTER EXISTS AND IS WHAT EVERY SURFACE READS
  select count(*) into n from public.sanctions_ban where lead_id = v_lead;
  if n <> 1 then f := f || format('sanctions_ban rows for the party = %s, expected 1', n); end if;
  p := p || format('sanctions_ban rows = %s', n);
  if not public.fn_is_sanctioned_lead(v_lead) then f := f || 'fn_is_sanctioned_lead said false'::text; end if;

  -- 4. MATCHING
  select public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status,
                                l.permanently_closed, l.chat_strikes)
    into b from public.leads l where l.id = v_lead;
  if coalesce(b, true) then f := f || 'fn_is_matchable still returns true'::text; end if;
  p := p || format('fn_is_matchable = %s', coalesce(b::text, 'null'));

  -- 5. INVITATIONS -- the enqueuer's own candidate predicate, evaluated against the party
  select count(*) into n from public.leads l
   where l.id = v_lead
     and l.email is not null and l.email <> '' and l.invite_status is null
     and coalesce(l.source,'') <> 'self_registered' and coalesce(l.claimed,false) = false
     and coalesce(l.banned,false) = false;
  if n <> 0 then f := f || format('the invite candidate predicate still selects the party (%s row)', n); end if;
  p := p || format('invite candidates = %s', n);

  -- 6. MESSAGING -- every outbound path writes public.notifications. By lead_id and by address.
  begin
    insert into public.notifications (type, to_email, to_role, lead_id, channel, subject, body, status)
    values ('supplier_invite', v_mail, 'supplier', v_lead, 'email', 'probe', 'probe', 'queued');
    f := f || 'a notification addressed by lead_id was ACCEPTED'::text;
  exception when others then
    if sqlerrm not like 'SANCTIONED_PARTY_BLOCKED%' then f := f || format('notification-by-lead_id refused for the wrong reason: %s', sqlerrm); end if;
  end;
  begin
    insert into public.notifications (type, to_email, to_role, channel, subject, body, status)
    values ('supplier_notice', v_mail, 'supplier', 'email', 'probe', 'probe', 'queued');
    f := f || 'a notification addressed by e-mail alone was ACCEPTED'::text;
  exception when others then
    if sqlerrm not like 'SANCTIONED_PARTY_BLOCKED%' then f := f || format('notification-by-email refused for the wrong reason: %s', sqlerrm); end if;
  end;
  p := p || 'notifications refused by lead_id and by address'::text;

  -- 7. SIGN-IN AND THE FRONT DOORS -- the claim link is dead and no account owns the row. The
  --    e-mail guard the edge functions read is present.
  select count(*) into n from public.leads where id = v_lead and claim_token <> v_tok and coalesce(claimed, false) = false;
  if n <> 1 then f := f || 'the claim token was not rotated, or the claimed flag survived the ban'::text; end if;
  select count(*) into n from public.sanctions_ban where lead_id = v_lead and account_email = v_mail;
  if n <> 1 then f := f || 'sanctions_ban carries no account e-mail, so the sign-in guard has nothing to match on'::text; end if;
  p := p || 'claim link revoked, account e-mail recorded'::text;

  -- 7b. THE WHATSAPP CHANNEL -- the one identity with no session to refuse. The handset must name
  --     NOBODY: fn_whatsapp_owner is the root fn_wa_lead_id, fn_conversation_party and
  --     fn_identify_contact all resolve through, and fn_supplier_apply_change (which changes a
  --     quoted price by text message) is scoped by it.
  select count(*) into n from public.fn_whatsapp_owner(v_phone) o where o.lead_id = v_lead;
  if n <> 0 then f := f || 'the handset still names the sanctioned party through fn_whatsapp_owner'::text; end if;
  select count(*) into n from public.fn_wa_lead_id(v_phone) z where z is not null;
  if n <> 0 then f := f || 'fn_wa_lead_id still resolves the sanctioned party'::text; end if;
  p := p || 'the handset names nobody'::text;

  -- 8. RE-REGISTRATION -- name, licence and e-mail, each in a spelling the raw column would not match
  begin
    insert into public.leads (company_name, email, lifecycle_stage) values (v_name2, v_mail2, 'registered') returning id into v_lead2;
    f := f || 'a re-registration under the same NAME was accepted'::text;
  exception when others then
    if sqlerrm not like 'SANCTIONED_PARTY_BLOCKED%' then f := f || format('name re-registration refused for the wrong reason: %s', sqlerrm); end if;
  end;
  begin
    insert into public.leads (company_name, email, trade_license_no, lifecycle_stage)
    values ('ZZ DEMO Unrelated Name Co', v_mail2, v_lic2, 'registered') returning id into v_lead2;
    f := f || 'a re-registration under the same TRADE LICENCE was accepted'::text;
  exception when others then
    if sqlerrm not like 'SANCTIONED_PARTY_BLOCKED%' then f := f || format('licence re-registration refused for the wrong reason: %s', sqlerrm); end if;
  end;
  begin
    insert into public.leads (company_name, claimed_by, lifecycle_stage)
    values ('ZZ DEMO Another Name Co', v_mail, 'registered') returning id into v_lead2;
    f := f || 'a re-registration on the same ACCOUNT E-MAIL was accepted'::text;
  exception when others then
    if sqlerrm not like 'SANCTIONED_PARTY_BLOCKED%' then f := f || format('account-email re-registration refused for the wrong reason: %s', sqlerrm); end if;
  end;
  -- and an UNRELATED registration still works, or the guard is a wall rather than a filter
  begin
    insert into public.leads (company_name, email, trade_license_no, lifecycle_stage)
    values ('ZZ DEMO Perfectly Ordinary Joinery', 'zz.demo.ordinary@example.invalid', 'ZZDEMO-CLEAN-0002', 'registered')
    returning id into v_lead2;
  exception when others then
    f := f || format('an UNRELATED registration was refused: %s', sqlerrm);
  end;
  p := p || 'name / licence / account e-mail all refused, an unrelated registration still admitted'::text;

  -- 9. THE RECORD SURVIVES
  begin
    delete from public.leads where id = v_lead;
    f := f || 'the sanctioned lead was DELETED, which would have cascaded its screening hits away'::text;
  exception when others then
    if sqlerrm not like 'SANCTIONS_RECORD_IS_SEALED%' then f := f || format('lead delete refused for the wrong reason: %s', sqlerrm); end if;
  end;
  begin
    delete from public.supplier_screening_hit where id = v_hit;
    f := f || 'the screening hit was DELETED'::text;
  exception when others then
    if sqlerrm not like 'SANCTIONS_RECORD_IS_SEALED%' then f := f || format('hit delete refused for the wrong reason: %s', sqlerrm); end if;
  end;
  begin
    delete from public.sanctions_ban where lead_id = v_lead;
    f := f || 'the sanctions_ban row was DELETED'::text;
  exception when others then
    if sqlerrm not like 'SANCTIONS_RECORD_IS_SEALED%' then f := f || format('sanctions_ban delete refused for the wrong reason: %s', sqlerrm); end if;
  end;
  begin
    update public.leads set banned = false, matching_blocked = false where id = v_lead;
    f := f || 'the party was UN-BANNED'::text;
  exception when others then
    if sqlerrm not like 'SANCTIONS_BAN_IS_PERMANENT%' then f := f || format('un-ban refused for the wrong reason: %s', sqlerrm); end if;
  end;
  begin
    delete from public.screening_entry where id = v_entry;
    f := f || 'the cited screening_entry was DELETED'::text;
  exception when others then
    if sqlerrm not like 'SANCTIONS_RECORD_IS_SEALED%' then f := f || format('cited-entry delete refused for the wrong reason: %s', sqlerrm); end if;
  end;
  -- the record is still there after all five attempts
  select count(*) into n from public.supplier_screening_hit where id = v_hit and status = 'confirmed';
  if n <> 1 then f := f || 'the confirmed hit did not survive'::text; end if;
  p := p || 'lead / hit / register / entry all survived deletion, ban survived un-ban'::text;

  -- 10. THE CEO CAN STILL READ IT (this probe runs as service_role, the seat's own access)
  select count(*) into n from public.sanctions_ban b
    join public.supplier_screening_hit h on h.id = b.hit_id
    join public.leads l on l.id = b.lead_id
   where b.lead_id = v_lead and b.decided_by = 'ceo' and h.entry_source = 'un_consolidated';
  if n <> 1 then f := f || 'the audit trail does not join up (register -> hit -> lead)'::text; end if;
  p := p || 'audit trail joins register -> hit -> lead, decided_by = ceo'::text;

  if array_length(f, 1) is not null then
    raise exception 'PROBE FAILED: %', array_to_string(f, ' | ');
  end if;
  raise exception 'CHK<<sanctioned party unreachable: %>>', array_to_string(p, '; ');
end $probe$;
