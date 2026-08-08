-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708111711   name: erp_ws_supplier_360
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_ws_supplier_360(p_id bigint)
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare l public.leads%rowtype; j jsonb; docs jsonb := '[]'::jsonb;
begin
  select * into l from public.leads where id=p_id;
  if l.id is null then return jsonb_build_object('error','supplier not found'); end if;

  -- documents from path fields
  if l.license_doc_path is not null then docs:=docs||jsonb_build_object('type','Trade licence','name',coalesce(l.license_doc_name,'licence'),'path',l.license_doc_path); end if;
  if l.iban_doc_path is not null then docs:=docs||jsonb_build_object('type','Bank/IBAN','name',coalesce(l.iban_doc_name,'iban'),'path',l.iban_doc_path); end if;
  if l.egr_doc_path is not null then docs:=docs||jsonb_build_object('type','Establishment card','name',coalesce(l.egr_doc_name,'egr'),'path',l.egr_doc_path); end if;
  if l.insurance_doc_path is not null then docs:=docs||jsonb_build_object('type','Insurance','name','insurance','path',l.insurance_doc_path); end if;
  if l.vat_doc_path is not null then docs:=docs||jsonb_build_object('type','VAT certificate','name','vat','path',l.vat_doc_path); end if;
  if l.company_profile_doc_path is not null then docs:=docs||jsonb_build_object('type','Company profile','name','profile','path',l.company_profile_doc_path); end if;
  if l.signed_terms_path is not null then docs:=docs||jsonb_build_object('type','Signed terms','name','terms','path',l.signed_terms_path); end if;
  if l.catalog_doc_paths is not null then
    docs := docs || coalesce((select jsonb_agg(jsonb_build_object('type','Catalogue','name','catalogue','path',x))
                              from unnest(l.catalog_doc_paths) x),'[]'::jsonb);
  end if;

  j := jsonb_build_object(
    'profile', jsonb_build_object(
      'id', l.id, 'company_name', l.company_name, 'sector', l.sector, 'sub_type', l.sub_type,
      'emirate', l.emirate, 'city', l.city, 'phone', coalesce(l.phone_e164,l.phone), 'email', l.email,
      'website', l.website, 'contact_name', l.contact_name, 'founded_year', l.founded_year,
      'company_size', l.company_size, 'employee_count', l.employee_count, 'business_role', l.business_role,
      'lifecycle_stage', l.lifecycle_stage, 'claimed', l.claimed
    ),
    'status', jsonb_build_object(
      'approval_status', l.approval_status, 'verified', l.verified, 'verification_status', l.verification_status,
      'registration_status', l.registration_status, 'matching_blocked', l.matching_blocked,
      'matching_block_reason', l.matching_block_reason, 'banned', l.banned, 'banned_reason', l.banned_reason,
      'chat_strikes', l.chat_strikes
    ),
    'ai', jsonb_build_object(
      'capability_summary', l.capability_summary, 'capability_score', l.capability_score,
      'review_notes', l.ai_review_notes, 'review_flags', l.ai_review_flags, 'reviewed_at', l.ai_reviewed_at,
      'twin', coalesce((select to_jsonb(tw) from public.supplier_twin tw where tw.supplier_id=p_id),'{}'::jsonb)
    ),
    'compliance', jsonb_build_object(
      'trade_license_no', l.trade_license_no, 'license_authority', l.license_authority,
      'license_expiry', l.license_expiry, 'trn', l.trn, 'vat_number', l.vat_number,
      'insurance_expiry', l.insurance_expiry, 'iso_certifications', l.iso_certifications,
      'certifications', l.certifications, 'accepted_terms_at', l.accepted_terms_at,
      'registration_expires_at', l.registration_expires_at,
      'license_expiring', (l.license_expiry is not null and l.license_expiry < current_date + 30),
      'insurance_expiring', (l.insurance_expiry is not null and l.insurance_expiry < current_date + 30)
    ),
    'capabilities', jsonb_build_object(
      'brands_carried', l.brands_carried, 'machinery', l.machinery, 'engineers_count', l.engineers_count,
      'team_size', l.team_size, 'warehouse_area', l.warehouse_area, 'service_emirates', l.service_emirates,
      'manufacturer_authorizations', l.manufacturer_authorizations, 'client_references', l.client_references,
      'products', l.products, 'services', l.services,
      'detail', coalesce((select to_jsonb(c) from public.supplier_capabilities c where c.supplier_id=p_id),'{}'::jsonb)
    ),
    'performance', coalesce((select jsonb_build_object(
        'matched',pf.matched,'quoted',pf.quoted,'won',pf.won,'quote_rate',pf.quote_rate,
        'win_rate',pf.win_rate,'perf_score',pf.perf_score,'rating',pf.rating,'review_count',pf.review_count)
        from public.supplier_perf pf where pf.supplier_id=p_id),'{}'::jsonb)
      || jsonb_build_object('rv_reveals',l.rv_reveals,'rv_responded',l.rv_responded,'rv_response_rate',l.rv_response_rate,
                            'app_rating',l.app_rating,'app_reviews',l.app_reviews),
    'reputation', coalesce((select to_jsonb(rp) - 'supplier_id' - 'company_name' from public.supplier_reputation rp where rp.supplier_id=p_id),'{}'::jsonb),
    'financials', (
      select jsonb_build_object(
        'deals_count', count(*) filter (where t.id is not null),
        'deal_value_total', coalesce(sum(t.quote_amount),0),
        'reveal_fees_generated', coalesce(sum(t.reveal_fee) filter (where t.fee_status='paid'),0)
      ) from public.transactions t where t.supplier_id=p_id
    ) || (
      select jsonb_build_object(
        'commission_total', coalesce(sum(amount_due),0),
        'commission_paid', coalesce(sum(amount_due) filter (where status in ('paid','settled')),0),
        'commission_owed', coalesce(sum(amount_due) filter (where status not in ('paid','settled')),0)
      ) from public.supplier_dues where supplier_id=p_id
    ),
    'documents', docs,
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'amount',q.quote_amount,'status',q.status,'created_at',q.created_at) order by q.created_at desc)
                        from (select * from public.quotes where supplier_id=p_id order by created_at desc limit 10) q),'[]'::jsonb),
    'reviews', coalesce((select jsonb_agg(jsonb_build_object('rating',r.rating,'comment',r.comment,'created_at',r.created_at) order by r.created_at desc)
                        from (select * from public.reviews where supplier_id=p_id order by created_at desc limit 8) r),'[]'::jsonb),
    'timeline', (select jsonb_agg(e order by e->>'at' desc) from (
        select jsonb_build_object('at',l.created_at,'event','Added to directory') e where l.created_at is not null
        union all select jsonb_build_object('at',l.registration_submitted_at,'event','Registration submitted') where l.registration_submitted_at is not null
        union all select jsonb_build_object('at',l.approved_at,'event','Approved'||coalesce(' by '||l.approval_decided_by,'')) where l.approved_at is not null
        union all select jsonb_build_object('at',l.accepted_terms_at,'event','Accepted terms') where l.accepted_terms_at is not null
      ) tl)
  );
  return j;
end $$;

revoke execute on function public.fn_ws_supplier_360(bigint) from anon, authenticated, public;
