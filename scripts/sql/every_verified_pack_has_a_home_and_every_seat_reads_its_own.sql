-- EVERY VERIFIED PACK HAS A HOME, AND EVERY SEAT READS ITS OWN AT DECISION TIME. Seat: it_engineer, 23 Sep 2026.
--
-- The verified knowledge packs (knowledge/packs/<trade>.json, knowledge/seats/<seat>.json: every entry
-- sourced, EN + AR, confidence and as-of) are loaded by scripts/kb/load_verified_packs.mjs. This file
-- gives each of them a home the seat's reasoning actually reads (public.fn_reason_retrieve, #884).
--
-- MEASURED 23 Sep 2026 against production (read-only), before this file:
--   * fn_reason_retrieve read sales_knowledge ONLY for sales_engineer. customer_support answers the
--     same buyers about the same trades (the homepage widget and WhatsApp are Support) and could not
--     reach a single trade entry.
--   * support_knowledge (408 rows) and ceo_knowledge (508 rows) had NO vector column, so neither the
--     customer_support nor the ceo seat read its own table at all. The #884 header says so.
--   * there was no marketing knowledge table; the marketing seat reasoned from agent_knowledge only
--     (51 rows).
--   * accountant_knowledge and it_engineer_knowledge refuse any epistemic_status outside a fixed list,
--     and support_knowledge refuses any pack_version but '1.2.0'. A sourced pack entry fits none of
--     them honestly, so each list gains exactly one value / one clause rather than borrowing a wrong one.
--
-- WHERE EACH PACK LIVES
--   trade pack  -> sales_knowledge, tags 'trade:<code>' (the #881 check's convention), record_type
--                  'verified_pack_entry'; read by sales_engineer and, from this file on, customer_support
--   seat pack   -> that seat's own table: sales_engineer sales_knowledge, customer_support support_knowledge,
--                  accountant accountant_knowledge, it_engineer it_engineer_knowledge, ceo ceo_knowledge,
--                  marketing marketing_knowledge (new here)
--   Each entry is two rows: '<entry id>' (English) and '<entry id>@ar' (Arabic), each with its own
--   gte-small vector, so a question in either language is matched by meaning in that language. pack_id
--   'verified:trade:<code>' / 'verified:seat:<seat>' is what a reload replaces and retires by.
--
-- WHAT IT DOES NOT DO. It does not embed the 408 support and 508 ceo rows written before it (they stay
-- NULL and are skipped by the `embedding_gte is not null` filter until embedded); it does not touch any
-- row; it adds no lexical path. customer_support reads only the trade-pack rows of sales_knowledge, not
-- the sales engineer's own playbooks.
--
-- Pending: scripts/sql/pending/every_verified_pack_has_a_home_and_every_seat_reads_its_own.txt. Proved in one
-- aborted transaction by scripts/checks/every_seat_reads_its_verified_pack.test.mjs.

-- ── 1. the marketing seat's own table (the same shape as accountant_ / it_engineer_knowledge) ───────
create table if not exists public.marketing_knowledge (
  record_id              text primary key,
  record_type            text not null,
  domain                 text,
  title                  text not null,
  content                text not null,
  structured_data        jsonb not null default '{}'::jsonb,
  source_ids             text[] not null default '{}'::text[],
  epistemic_status       text not null,
  jurisdiction           text,
  pack_id                text not null,
  pack_version           text not null,
  body_sha256            text not null,
  runtime_index_eligible boolean not null default true,
  authority_effect       text not null default 'none' check (authority_effect = 'none'),
  tags                   text[] not null default '{}'::text[],
  updated_at             timestamptz,
  ingested_at            timestamptz not null default now(),
  embedding_gte          vector(384)
);
alter table public.marketing_knowledge enable row level security;
drop policy if exists marketing_knowledge_service_role_only on public.marketing_knowledge;
create policy marketing_knowledge_service_role_only on public.marketing_knowledge
  as permissive for all to public using (false) with check (false);
revoke all on public.marketing_knowledge from anon, authenticated;
comment on table public.marketing_knowledge is
  'The marketing seat''s own knowledge, read by fn_reason_retrieve for p_seat = marketing. Loaded from knowledge/seats/marketing.json by scripts/kb/load_verified_packs.mjs.';

-- ── 2. a vector on the two seat tables that had none ─────────────────────────────────────────────
alter table public.support_knowledge add column if not exists embedding_gte vector(384);
alter table public.ceo_knowledge     add column if not exists embedding_gte vector(384);
create index if not exists support_knowledge_emb_hnsw   on public.support_knowledge   using hnsw (embedding_gte vector_cosine_ops);
create index if not exists ceo_knowledge_emb_hnsw       on public.ceo_knowledge       using hnsw (embedding_gte vector_cosine_ops);
create index if not exists marketing_knowledge_emb_hnsw on public.marketing_knowledge using hnsw (embedding_gte vector_cosine_ops);
create index if not exists sales_knowledge_pack_idx     on public.sales_knowledge (pack_id);

-- ── 3. the one honest value each vocabulary lacked ───────────────────────────────────────────────
alter table public.accountant_knowledge drop constraint if exists accountant_knowledge_epistemic_ck;
alter table public.accountant_knowledge add constraint accountant_knowledge_epistemic_ck check (epistemic_status = any (array[
  'method_general_accounting', 'marketplace_policy_derived', 'framework_shape_verify_current_text', 'obligation_shape_no_figures',
  'resolve_from_authority', 'company_record_generated', 'company_governance_ruling', 'authority_protocol', 'verified_pack_sourced']));
alter table public.it_engineer_knowledge drop constraint if exists it_engineer_knowledge_epistemic_ck;
alter table public.it_engineer_knowledge add constraint it_engineer_knowledge_epistemic_ck check (epistemic_status = any (array[
  'method_engineering', 'diagnostic_lens', 'estate_architecture_measured', 'failure_signature', 'security_posture_no_version_claim',
  'resolve_from_live_system', 'company_governance_ruling', 'company_record_generated', 'verified_pack_sourced']));
-- The 1.2.0 pin stays for the authored support pack; a verified pack carries its own content hash as version.
alter table public.support_knowledge drop constraint if exists support_knowledge_version_ck;
alter table public.support_knowledge add constraint support_knowledge_version_ck
  check (pack_version = '1.2.0' or pack_id like 'verified:%');

-- ── 4. retrieval by meaning: every seat reads its own table ─────────────────────────────────────
-- Unchanged from #884 except: sales_knowledge's trade-pack rows are read by customer_support too, and
-- support_knowledge, ceo_knowledge and marketing_knowledge are read by their seats. Each source is still
-- ordered by distance on its own index, and the union ranked by the same distance.
create or replace function public.fn_reason_retrieve(p_seat text, p_embedding vector(384), p_k integer default 6)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
set "hnsw.iterative_scan" to 'relaxed_order'
set "hnsw.ef_search" to '100'
as $fn$
declare
  k   integer := greatest(1, least(coalesce(p_k, 6), 12));
  out jsonb := '[]'::jsonb;
begin
  if p_embedding is null then return out; end if;

  with hits as (
    (select 'kb_chunks' src, c.id::text id, c.title, left(c.content, 1200) excerpt, c.citation,
            1 - (c.embedding_gte <=> p_embedding) sim, 'reviewed' trust
       from public.kb_chunks c where c.embedding_gte is not null
      order by c.embedding_gte <=> p_embedding limit k)
    union all
    (select 'ops_knowledge', o.record_id, o.title, left(o.content, 1200), o.source_path,
            1 - (o.embedding_gte <=> p_embedding), 'reviewed'
       from public.ops_knowledge o
      where o.embedding_gte is not null and o.runtime_eligible and o.supersession_state = 'current'
        and o.scope_type in ('company', 'external_source', 'category')
      order by o.embedding_gte <=> p_embedding limit k)
    union all
    (select 'agent_knowledge', a.id::text, a.topic, left(a.content, 1200), a.source_ref,
            1 - (a.embedding_gte <=> p_embedding), 'reviewed'
       from public.agent_knowledge a
      where a.embedding_gte is not null and a.agent_key in (p_seat, '_global')
      order by a.embedding_gte <=> p_embedding limit k)
    union all
    (select 'company_faq', f.id::text, f.question, left(f.answer, 1200), 'FAQ ' || f.id,
            1 - (f.embedding_gte <=> p_embedding), 'reviewed'
       from public.company_faq f where f.embedding_gte is not null and f.status = 'approved'
      order by f.embedding_gte <=> p_embedding limit k)
    union all
    (select 'sales_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.sales_knowledge s
      where s.embedding_gte is not null and s.runtime_index_eligible
        and (p_seat = 'sales_engineer' or (p_seat = 'customer_support' and s.pack_id like 'verified:trade:%'))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'accountant_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.accountant_knowledge s
      where p_seat = 'accountant' and s.embedding_gte is not null and s.runtime_index_eligible
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'it_engineer_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.it_engineer_knowledge s
      where p_seat = 'it_engineer' and s.embedding_gte is not null and s.runtime_index_eligible
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'support_knowledge', s.record_id, s.title, left(s.body, 1200), coalesce(s.source_path, s.pack_id),
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.support_knowledge s
      where p_seat = 'customer_support' and s.embedding_gte is not null and coalesce(s.runtime_index_eligible, true)
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'ceo_knowledge', s.record_id, s.title, left(s.body, 1200), coalesce(s.source_path, s.pack_fingerprint),
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.ceo_knowledge s
      where p_seat = 'ceo' and s.embedding_gte is not null and s.runtime_index_eligible
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'marketing_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.marketing_knowledge s
      where p_seat = 'marketing' and s.embedding_gte is not null and s.runtime_index_eligible
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'research', r.id::text, left(r.question, 200), r.finding, r.sources->0->>'url',
            1 - (r.embedding_gte <=> p_embedding), case when r.status = 'approved' then 'reviewed' else 'pending_review' end
       from public.reasoning_knowledge_candidate r
      where r.embedding_gte is not null and r.status <> 'rejected'
      order by r.embedding_gte <=> p_embedding limit k)
  )
  select coalesce(jsonb_agg(jsonb_build_object('source', src, 'id', id, 'title', title, 'excerpt', excerpt,
           'citation', citation, 'similarity', round(sim::numeric, 4), 'trust', trust) order by sim desc), '[]'::jsonb)
    into out
    from (select * from hits order by sim desc limit k * 2) t;
  return out;
end $fn$;
revoke execute on function public.fn_reason_retrieve(text, vector, integer) from public, anon, authenticated;
grant execute on function public.fn_reason_retrieve(text, vector, integer) to service_role;

-- ── 5. the daily table export carries the new table ──────────────────────────────────────────────
-- Copied verbatim from the canonical, applied definition
-- (the_marketing_seat_watches_its_videos_studies_the_market_and_argues_its_month_with_the_ceo.sql) with
-- marketing_knowledge added (scripts/checks/every_marketing_table_is_in_the_daily_export.test.mjs).
create or replace function public.fn_table_export_list()
returns table(table_name text, subject text, change_log text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select v.t, v.s,
         (select 'table_export_change' from public.table_export_change_tracked x where x.table_name = v.t)
  from (values
    ('customers','customer'), ('customer_preference','customer'), ('customer_calls','customer'), ('projects','customer'),
    ('leads','supplier'), ('lead_category','supplier'), ('lead_subcategory','supplier'), ('supplier_capabilities','supplier'),
    ('supplier_catalog','supplier'), ('supplier_product','supplier'), ('supplier_product_variant','supplier'),
    ('supplier_capability_confirmation','supplier'), ('supplier_collaboration','supplier'), ('supplier_collaboration_event','supplier'),
    ('supplier_negotiation_policy','supplier'), ('supplier_screening_hit','supplier'), ('supplier_lead_intake','supplier'),
    ('doc_reviews','supplier'), ('licence_renewal_ask','supplier'), ('outreach','supplier'), ('company_registration','company'),
    ('inquiries','inquiry'), ('inquiry_intake','inquiry'), ('inquiry_matches','inquiry'), ('inquiry_requirement','inquiry'),
    ('inquiry_cancellations','inquiry'), ('inquiry_supplier_brief','inquiry'), ('inquiry_state_audit','inquiry'),
    ('inquiry_gate','inquiry'), ('inquiry_answer','inquiry'), ('inquiry_answer_document','inquiry'), ('inquiry_answer_scope','inquiry'),
    ('inquiry_workstream','inquiry'), ('inquiry_workstream_group','inquiry'), ('inquiry_workstream_requirement','inquiry'),
    ('inquiry_trade_candidate','inquiry'), ('inquiry_trade_clarification','inquiry'), ('inquiry_scope_disposition','inquiry'),
    ('rfq_archives','inquiry'), ('rfq_clarification','inquiry'),
    ('quotes','quote'), ('quote_items','quote'), ('quote_reviews','quote'), ('quote_review_messages','quote'),
    ('quote_requirements','quote'), ('quote_committed_items','quote'), ('quote_comparisons','quote'), ('quote_spec_hold','quote'),
    ('spec_alternative_offer','quote'), ('po_orders','quote'), ('po_vendors','quote'), ('questions','quote'), ('reviews','quote'),
    ('category_specs','quote rules'), ('category_quote_specs','quote rules'),
    ('transactions','payment'), ('reveal_invoices','payment'), ('supplier_dues','payment'), ('refunds','payment'),
    ('refund_case','payment'), ('refund_incident','payment'), ('refund_ceo_review','payment'), ('refund_ceo_check','payment'),
    ('refund_ladder_evidence','payment'), ('refund_status_transition','payment'), ('stripe_events','payment'),
    ('stripe_payout','payment'), ('stripe_dispute','payment'), ('charge_audit','payment'), ('pricing_config','payment'),
    ('gl_journal','accounting'), ('gl_journal_lines','accounting'), ('gl_expense_map','accounting'), ('expenses','accounting'),
    ('expense_entries','accounting'), ('bank_statement_intake','accounting'), ('bank_statement_line','accounting'),
    ('accountant_month_close','accounting'), ('accountant_issued_document','accounting'),
    ('messages','conversation'), ('chat_threads','conversation'), ('conversation_archive','conversation'),
    ('inbound_messages','conversation'), ('contact_messages','conversation'), ('complaint_tickets','conversation'),
    ('support_case','conversation'), ('support_notification','conversation'), ('support_document_intake','conversation'),
    ('wa_messages','conversation'), ('wa_conversation','conversation'), ('wa_turn','conversation'),
    ('wa_document_intake','conversation'), ('notifications','conversation'), ('agent_chats','conversation'),
    ('legal_reviews','legal'), ('pdpl_requests','legal'), ('pdpl_erase_files','legal'), ('email_suppressions','legal'),
    ('founder_instruction','decision'), ('company_policy_decision','decision'),
    ('kb_chunks','knowledge'), ('dept_library','knowledge'), ('ops_knowledge','knowledge'), ('agent_knowledge','knowledge'),
    ('sales_knowledge','knowledge'), ('ceo_knowledge','knowledge'), ('support_knowledge','knowledge'),
    ('accountant_knowledge','knowledge'), ('it_engineer_knowledge','knowledge'), ('employee_knowledge','knowledge'),
    ('marketing_post','marketing'), ('marketing_connection_check','marketing'), ('marketing_insight_day','marketing'),
    ('marketing_ad_spend_day','marketing'), ('marketing_duty_run','marketing'), ('marketing_report','marketing'),
    ('marketing_article','marketing'), ('marketing_prospect','marketing'), ('marketing_outreach_message','marketing'),
    ('marketing_platform_spec','marketing'), ('marketing_platform_spec_source','marketing'),
    ('marketing_campaign','marketing'), ('marketing_post_variant','marketing'),
    ('marketing_post_platform','marketing'), ('marketing_post_metric','marketing'), ('marketing_first_touch','marketing'),
    ('marketing_goal','marketing'), ('marketing_scorecard_report','marketing'),
    ('marketing_asset_feature','marketing'), ('marketing_asset_perception','marketing'), ('marketing_asset_review','marketing'),
    ('marketing_insight_note','marketing'), ('marketing_month_plan','marketing'), ('marketing_plan_review_turn','marketing'),
    ('marketing_model_run','marketing'), ('market_intel','marketing'), ('competitor','marketing'), ('marketing_knowledge','knowledge'),
    ('table_export_change','backup')
  ) v(t, s)
  -- The sibling PRs' tables may not exist yet when this applies; backup/index.ts fails the whole day on a
  -- missing table, so ONLY those nine are skipped until their own file creates them. Every other table in the
  -- list still fails loudly if it disappears.
  where v.t not in ('marketing_platform_spec','marketing_platform_spec_source','marketing_campaign','marketing_post_variant',
                    'marketing_post_platform','marketing_post_metric','marketing_first_touch','marketing_goal','marketing_scorecard_report')
     or to_regclass('public.' || v.t) is not null
$fn$;
revoke execute on function public.fn_table_export_list() from public, anon, authenticated;
grant execute on function public.fn_table_export_list() to service_role;
