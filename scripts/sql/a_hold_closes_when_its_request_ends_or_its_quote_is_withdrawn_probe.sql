-- PROBE: A HOLD CLOSES WHEN ITS REQUEST ENDS OR ITS QUOTE IS WITHDRAWN. Seat: sales_engineer (hold desk), delivered by
-- customer_support. 10 Nov 2026. Pure probe: no DDL, never applied; run after (or concatenated after)
-- a_hold_closes_when_its_request_ends_or_its_quote_is_withdrawn.sql. It always raises, so every row is rolled back.
-- Every party is a ZZ DEMO fixture on @example.invalid.
-- PROBE OK only if
--   1. withdrawing a held quote closes its spec hold as quote_withdrawn and supersedes its quality hold;
--   2. a request ending (expired) closes the spec and quality holds of its quotes as request_ended / superseded;
--   3. neither is counted as an ignored hold (no supplier_collaboration_event), and a live request's hold stays open.
do $probe$
declare
  fails text := ''; c uuid := gen_random_uuid(); s1 bigint; ia uuid := gen_random_uuid(); ib uuid := gen_random_uuid(); il uuid := gen_random_uuid();
  qa uuid := gen_random_uuid(); qb uuid := gen_random_uuid(); ql uuid := gen_random_uuid(); n int;
begin
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO Hold Customer', 'zz-demo-holdend@example.invalid', '+971500000146', true, true, 'demo://terms', 'en', now() - interval '30 days');
  insert into public.leads (company_name, email) values ('ZZ DEMO Hold Supplier', 'zz-demo-holdend-s1@example.invalid') returning id into s1;
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at, scope_type)
  values (ia, c, 'joinery', 'Dubai', 'ZZ DEMO hold probe A', 'sent', 'en', now() - interval '25 days', 'single'),
         (ib, c, 'joinery', 'Dubai', 'ZZ DEMO hold probe B', 'sent', 'en', now() - interval '5 days', 'single'),
         (il, c, 'joinery', 'Dubai', 'ZZ DEMO hold probe live', 'sent', 'en', now() - interval '5 days', 'single');
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at)
  values (qa, ia, s1, 9000, 'draft', now() - interval '20 days'), (qb, ib, s1, 9000, 'draft', now() - interval '2 days'),
         (ql, il, s1, 9000, 'draft', now() - interval '2 days');
  insert into public.quote_spec_hold (quote_id, inquiry_id, supplier_id, state, original_snapshot)
  select q, i, s1, 'open', '{}'::jsonb from (values (qa, ia), (qb, ib), (ql, il)) v(q, i);
  insert into public.quote_quality_hold (quote_id, inquiry_id, supplier_id, fixture, release_due, accepted_md5)
  select q, i, s1, true, now() + interval '1 day', 'zz' from (values (qa, ia), (qb, ib), (ql, il)) v(q, i);

  update public.quotes set status = 'withdrawn' where id = qb;
  if (select state from public.quote_spec_hold where quote_id = qb) <> 'quote_withdrawn' then fails := fails || ' 1:spec'; end if;
  if (select superseded_at from public.quote_quality_hold where quote_id = qb) is null then fails := fails || ' 1:quality'; end if;

  update public.inquiries set status = 'expired' where id = ia;
  if (select state from public.quote_spec_hold where quote_id = qa) <> 'request_ended' then fails := fails || ' 2:spec'; end if;
  if (select superseded_at from public.quote_quality_hold where quote_id = qa) is null then fails := fails || ' 2:quality'; end if;

  select count(*) into n from public.supplier_collaboration_event where lead_id = s1;
  if n <> 0 then fails := fails || ' 3:incident(' || n || ')'; end if;
  if (select state from public.quote_spec_hold where quote_id = ql) <> 'open'
     or (select superseded_at from public.quote_quality_hold where quote_id = ql) is not null then fails := fails || ' 3:live_closed'; end if;

  if fails <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: withdrawn -> quote_withdrawn + superseded; expired -> request_ended + superseded; 0 incidents; the live hold stays open>>';
end $probe$;
