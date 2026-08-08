-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260626204232   name: tighten_grants_and_add_fk_indexes
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #2 defense-in-depth: the public roles never write directly (all writes go via service-role functions)
revoke insert, update, delete, truncate on all tables in schema public from anon, authenticated;

-- #10 covering indexes for hot foreign keys
create index if not exists idx_inquiries_customer_id        on public.inquiries(customer_id);
create index if not exists idx_inquiries_hired_supplier_id  on public.inquiries(hired_supplier_id);
create index if not exists idx_inquiry_matches_supplier_id  on public.inquiry_matches(supplier_id);
create index if not exists idx_quotes_supplier_id           on public.quotes(supplier_id);
create index if not exists idx_transactions_customer_id     on public.transactions(customer_id);
create index if not exists idx_transactions_inquiry_id      on public.transactions(inquiry_id);
create index if not exists idx_transactions_quote_id        on public.transactions(quote_id);
create index if not exists idx_transactions_supplier_id     on public.transactions(supplier_id);
create index if not exists idx_messages_customer_id         on public.messages(customer_id);
create index if not exists idx_messages_supplier_id         on public.messages(supplier_id);
create index if not exists idx_reviews_customer_id          on public.reviews(customer_id);
create index if not exists idx_reviews_inquiry_id           on public.reviews(inquiry_id);
create index if not exists idx_reviews_supplier_id          on public.reviews(supplier_id);
create index if not exists idx_questions_customer_id        on public.questions(customer_id);
create index if not exists idx_doc_reviews_lead_id          on public.doc_reviews(lead_id);
create index if not exists idx_inbound_messages_lead_id     on public.inbound_messages(lead_id);
