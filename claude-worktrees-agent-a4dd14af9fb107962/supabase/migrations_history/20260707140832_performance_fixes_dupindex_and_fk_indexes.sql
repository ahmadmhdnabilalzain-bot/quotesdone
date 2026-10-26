-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260707140832   name: performance_fixes_dupindex_and_fk_indexes
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Drop duplicate indexes (each identical to the one kept).
drop index if exists public.idx_ak_key;          -- dup of idx_agent_knowledge_key
drop index if exists public.idx_inq_customer;    -- dup of idx_inquiries_customer_id
drop index if exists public.inq_status_idx;      -- dup of idx_inq_status
drop index if exists public.idx_im_supplier;     -- dup of idx_inquiry_matches_supplier_id
drop index if exists public.idx_q_supplier;      -- dup of idx_quotes_supplier_id
drop index if exists public.idx_txn_customer;    -- dup of idx_transactions_customer_id
drop index if exists public.idx_txn_inquiry;     -- dup of idx_transactions_inquiry_id
drop index if exists public.idx_txn_quote;       -- dup of idx_transactions_quote_id
drop index if exists public.idx_txn_supplier;    -- dup of idx_transactions_supplier_id

-- Add covering indexes for the two unindexed foreign keys.
create index if not exists idx_mdm_cities_emirate_code on public.mdm_cities (emirate_code);
create index if not exists idx_user_roles_role          on public.user_roles (role);
