-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260626204501   name: cleanup_test_data_and_vestigial_table
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

do $$
declare
  test_cust uuid := 'f24d3ddd-0223-404a-a3e1-02861ae86dc4';
  test_leads bigint[];
  test_inq uuid[];
begin
  select array_agg(id) into test_leads from leads where email ilike '%@quotesdone.test' or company_name like '%(TEST)%';
  select array_agg(id) into test_inq from inquiries where customer_id = test_cust;
  test_leads := coalesce(test_leads, '{}');
  test_inq := coalesce(test_inq, '{}');

  delete from transactions where customer_id = test_cust or supplier_id = any(test_leads) or inquiry_id = any(test_inq);
  delete from reviews      where customer_id = test_cust or supplier_id = any(test_leads) or inquiry_id = any(test_inq);
  delete from messages     where customer_id = test_cust or supplier_id = any(test_leads);
  delete from questions    where customer_id = test_cust;
  delete from inquiry_matches where supplier_id = any(test_leads) or inquiry_id = any(test_inq);
  delete from quotes       where supplier_id = any(test_leads) or inquiry_id = any(test_inq);
  delete from notifications where lead_id = any(test_leads) or inquiry_id = any(test_inq) or to_email ilike '%@quotesdone.test';
  begin delete from doc_reviews where lead_id = any(test_leads); exception when others then null; end;
  begin delete from outreach where lead_id = any(test_leads); exception when others then null; end;
  begin delete from supplier_dues where supplier_id = any(test_leads); exception when others then null; end;
  begin delete from inbound_messages where lead_id = any(test_leads); exception when others then null; end;

  delete from inquiries where customer_id = test_cust;
  delete from customers where id = test_cust;
  delete from leads where id = any(test_leads);
end $$;

-- drop the vestigial empty duplicate suppression table (sender + unsubscribe both use email_suppressions)
drop table if exists public.email_suppression;
