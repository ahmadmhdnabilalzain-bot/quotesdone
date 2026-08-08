-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711192451   name: add_covering_indexes_for_unindexed_fks
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Covering indexes for unindexed foreign keys (ERP tables). Speeds up FK joins
-- and, importantly, makes parent-row deletes/updates non-sequential-scan.
create index if not exists ix_ap_bills_gl_journal_id on ap_bills (gl_journal_id);
create index if not exists ix_ap_bills_pay_journal_id on ap_bills (pay_journal_id);
create index if not exists ix_ap_bills_po_id on ap_bills (po_id);
create index if not exists ix_budget_lines_account_code on budget_lines (account_code);
create index if not exists ix_fa_assets_accum_account on fa_assets (accum_account);
create index if not exists ix_fa_assets_asset_account on fa_assets (asset_account);
create index if not exists ix_fa_assets_expense_account on fa_assets (expense_account);
create index if not exists ix_fa_depreciation_gl_journal_id on fa_depreciation (gl_journal_id);
create index if not exists ix_gl_accounts_parent_code on gl_accounts (parent_code);
create index if not exists ix_gl_expense_map_account_code on gl_expense_map (account_code);
create index if not exists ix_gl_journal_reverses on gl_journal (reverses);
create index if not exists ix_inv_items_cogs_account on inv_items (cogs_account);
create index if not exists ix_inv_items_inventory_account on inv_items (inventory_account);
create index if not exists ix_inv_stock_moves_gl_journal_id on inv_stock_moves (gl_journal_id);
create index if not exists ix_po_lines_account_code on po_lines (account_code);
create index if not exists ix_po_lines_item_id on po_lines (item_id);
create index if not exists ix_po_orders_vendor_id on po_orders (vendor_id);
create index if not exists ix_regulations_supersedes_id on regulations (supersedes_id);
