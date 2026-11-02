-- Auditor C (it_engineer), 28 Oct 2026: the sales engineer's verification decision table, run on production in ONE
-- aborted transaction (sent through scripts/lib/safe_replay.mjs replaySql; it always raises CHK<<…>>). Subjects: ZZ DEMO
-- leads at @example.invalid with fixture mobiles +9715000000NN and fixture storage rows, all created here, all rolled
-- back. It reads no real lead.
do $$
declare
  r record; v jsonb; out jsonb := '[]'::jsonb; ids bigint[] := array[]::bigint[]; v_id bigint; n int := 0;
  v_auto boolean := (select auto_approve_suppliers from public.pricing_config p where p.id = 1);
begin
  for r in select * from (values
    ('S1 complete, every licence field read, in date',               current_date + 300, 'ZZ DEMO AUDC One LLC',   'CN-1001', 'Dubai Department of Economy and Tourism', true,  true),
    ('S2 licence expired yesterday',                                  current_date - 1,   'ZZ DEMO AUDC Two LLC',   'CN-1002', 'Dubai Department of Economy and Tourism', true,  true),
    ('S3 expiry date not read',                                       null::date,         'ZZ DEMO AUDC Three LLC', 'CN-1003', 'Dubai Department of Economy and Tourism', true,  true),
    ('S4 licence name not read',                                      current_date + 300, null,                     'CN-1004', 'Dubai Department of Economy and Tourism', true,  true),
    ('S5 licence number not read',                                    current_date + 300, 'ZZ DEMO AUDC Five LLC',  null,      'Dubai Department of Economy and Tourism', true,  true),
    ('S6 company profile missing',                                    current_date + 300, 'ZZ DEMO AUDC Six LLC',   'CN-1006', 'Dubai Department of Economy and Tourism', false, true),
    ('S7 issuing authority is not a UAE authority',                   current_date + 300, 'ZZ DEMO AUDC Seven LLC', 'CN-1007', 'Ministry of Commerce, Kingdom of Saudi Arabia', true, true),
    ('S8 issuing authority never read',                               current_date + 300, 'ZZ DEMO AUDC Eight LLC', 'CN-1008', null,                                    true,  true)
  ) as t(label, expiry, legal_name, lic_no, authority, has_profile, has_terms) loop
    n := n + 1;
    insert into public.leads (company_name, email, claimed, claimed_by, owner_email_verified, owner_phone_verified, phone,
                              license_doc_path, company_profile_doc_path, signed_terms_path, license_expiry,
                              licence_legal_name, trade_license_no, license_authority, source, tags)
    values (coalesce(r.legal_name, 'ZZ DEMO AUDC Unread ' || n || ' LLC'), 'zz-demo-audc-verif-' || n || '@example.invalid', true,
            'zz-demo-audc-verif-' || n || '@example.invalid', true, true, '+9715000000' || lpad(n::text, 2, '0'),
            'zz-demo-audc/' || n || '/licence.pdf', 'zz-demo-audc/' || n || '/profile.pdf', 'zz-demo-audc/' || n || '/terms.pdf',
            r.expiry, r.legal_name, r.lic_no, r.authority, 'probe', array['qd_demo'])
    returning leads.id into v_id;
    ids := ids || v_id;
    insert into storage.objects (bucket_id, name) values ('supplier-docs', 'zz-demo-audc/' || n || '/licence.pdf');
    if r.has_profile then insert into storage.objects (bucket_id, name) values ('supplier-docs', 'zz-demo-audc/' || n || '/profile.pdf'); end if;
    v := public.fn_sales_engineer_verifies_supplier(v_id, 'save_profile');
    out := out || jsonb_build_array(jsonb_build_object('case', r.label, 'decision', v->>'decision', 'reason', v->>'reason',
      'review', (select a.status from public.agent_actions a where a.kind = 'supplier_verification' and a.target_id = v_id::text order by a.id desc limit 1),
      'recorded_reason', (select a.title from public.agent_actions a where a.kind = 'supplier_verification' and a.target_id = v_id::text order by a.id desc limit 1),
      'approval_notice', (select a.status || ': ' || coalesce(a.detail->>'not_sent', 'queued') from public.agent_actions a
                           where a.kind = 'supplier_approved_notice' and a.target_id = v_id::text order by a.id desc limit 1)));
  end loop;
  delete from public.agent_actions where target_table = 'leads' and target_id = any(select x::text from unnest(ids) x);
  delete from public.leads where leads.id = any(ids);
  raise exception 'CHK<<%>>', jsonb_build_object('auto_approve_suppliers', v_auto, 'cases', out,
    'left_leads', (select count(*) from public.leads where leads.id = any(ids)));
end $$;
