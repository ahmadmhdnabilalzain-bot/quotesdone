-- QuotesDone — FULL SCHEMA EXPORT (generated from live DB, project htdblwldjkcgjvmqkbeh)
-- Excludes: secret VALUES (key names listed below), and table ROW DATA (PII).
-- Order is best-effort; this is a faithful reference mirror, not a guaranteed one-click restore.

-- ===== EXTENSIONS =====
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;

-- ===== SEQUENCES =====
CREATE SEQUENCE IF NOT EXISTS public.agent_actions_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.agent_command_log_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.agent_evals_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.agent_knowledge_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.agent_memory_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.agent_runs_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.ai_constitution_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.board_reports_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.brand_assets_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.business_rules_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.canon_eval_questions_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.canon_eval_runs_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.category_quote_specs_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.compliance_sources_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.decision_log_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.dept_library_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.doc_backups_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.doc_versions_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.documents_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.dr_restore_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.error_events_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.expense_entries_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.expenses_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.experiment_events_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.finance_reports_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.finance_snapshots_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.hlm_digest_log_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.kb_revisions_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.llm_calls_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.marketing_library_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.mdm_brands_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.mdm_cities_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.mdm_manufacturers_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.mdm_standards_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.pdpl_erase_files_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.policy_rules_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.prompt_versions_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.quote_comparisons_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.quote_items_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.review_queue_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.rfq_archives_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.simulations_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.supply_health_snapshots_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.wa_messages_id_seq;

-- ===== TABLES (214) =====\nCREATE TABLE IF NOT EXISTS public.admin_mfa_sessions (
  session_id text NOT NULL,
  email text,
  verified_at timestamp with time zone DEFAULT now(),
  expires_at timestamp with time zone NOT NULL,
  ip text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.agent_action_log (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  agent_key text,
  action text,
  args jsonb,
  result jsonb,
  ok boolean,
  actor text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.agent_actions (
  id bigint DEFAULT nextval('agent_actions_id_seq'::regclass) NOT NULL,
  agent text NOT NULL,
  kind text NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  risk text DEFAULT 'low'::text NOT NULL,
  title text,
  recommendation text,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL,
  target_table text,
  target_id text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  decided_at timestamp with time zone,
  decided_by text,
  confidence numeric,
  evidence jsonb,
  escalated boolean DEFAULT false NOT NULL,
  escalation_reason text
);

CREATE TABLE IF NOT EXISTS public.agent_chats (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  agent_key text NOT NULL,
  role text NOT NULL,
  content text NOT NULL,
  created_by text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.agent_command_log (
  id bigint DEFAULT nextval('agent_command_log_id_seq'::regclass) NOT NULL,
  agent text,
  actor text,
  command text,
  did jsonb,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.agent_evals (
  id bigint DEFAULT nextval('agent_evals_id_seq'::regclass) NOT NULL,
  snapshot_at timestamp with time zone DEFAULT now(),
  window_days integer DEFAULT 30,
  kpis jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.agent_expectations (
  agent text NOT NULL,
  max_silence_hours numeric NOT NULL,
  on_demand boolean DEFAULT false NOT NULL,
  median_gap_hours numeric,
  runs_observed integer,
  note text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.agent_governance (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  version integer NOT NULL,
  universal_rules jsonb NOT NULL,
  response_structure jsonb NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.agent_knowledge (
  id bigint DEFAULT nextval('agent_knowledge_id_seq'::regclass) NOT NULL,
  agent_key text NOT NULL,
  topic text,
  content text NOT NULL,
  priority integer DEFAULT 5,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  layer text DEFAULT 'profession'::text
);

CREATE TABLE IF NOT EXISTS public.agent_memory (
  id bigint DEFAULT nextval('agent_memory_id_seq'::regclass) NOT NULL,
  agent_key text NOT NULL,
  kind text DEFAULT 'learning'::text,
  content text NOT NULL,
  source text,
  importance integer DEFAULT 5,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.agent_pending_actions (
  token uuid DEFAULT gen_random_uuid() NOT NULL,
  created_by text,
  created_at timestamp with time zone DEFAULT now(),
  status text DEFAULT 'pending'::text,
  summary text,
  actions jsonb
);

CREATE TABLE IF NOT EXISTS public.agent_runs (
  id bigint DEFAULT nextval('agent_runs_id_seq'::regclass) NOT NULL,
  agent text NOT NULL,
  started_at timestamp with time zone DEFAULT now() NOT NULL,
  finished_at timestamp with time zone,
  status text DEFAULT 'ok'::text,
  counts jsonb DEFAULT '{}'::jsonb,
  note text
);

CREATE TABLE IF NOT EXISTS public.ai_constitution (
  id bigint DEFAULT nextval('ai_constitution_id_seq'::regclass) NOT NULL,
  version integer NOT NULL,
  body text NOT NULL,
  principles jsonb DEFAULT '[]'::jsonb NOT NULL,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ai_qa_log (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  email text,
  kind text,
  model text,
  input jsonb,
  output jsonb,
  flags jsonb
);

CREATE TABLE IF NOT EXISTS public.ai_quality_snapshots (
  at timestamp with time zone DEFAULT now() NOT NULL,
  agent text,
  override_pct numeric,
  actions_30d integer,
  id bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ai_trainer_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ai_usage (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  email text,
  kind text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ap_bills (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  bill_no text,
  vendor_id bigint NOT NULL,
  po_id bigint,
  bill_date date DEFAULT CURRENT_DATE NOT NULL,
  due_date date,
  currency text DEFAULT 'AED'::text NOT NULL,
  subtotal numeric(18,2) DEFAULT 0 NOT NULL,
  vat_amount numeric(18,2) DEFAULT 0 NOT NULL,
  total numeric(18,2) DEFAULT 0 NOT NULL,
  amount_paid numeric(18,2) DEFAULT 0 NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  gl_journal_id bigint,
  pay_journal_id bigint,
  created_by text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.app_blocked_domains (
  domain text NOT NULL,
  reason text DEFAULT 'disposable'::text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.app_secrets (
  key text NOT NULL,
  value text NOT NULL,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.assistant_logs (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  message text,
  reply text,
  matched_ids bigint[],
  escalated boolean DEFAULT false,
  user_agent text,
  created_at timestamp with time zone DEFAULT now(),
  audience text,
  path text
);

CREATE TABLE IF NOT EXISTS public.blog_posts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  slug text NOT NULL,
  title text NOT NULL,
  excerpt text,
  meta_desc text,
  body_html text NOT NULL,
  author text DEFAULT 'QuotesDone'::text,
  category text,
  published boolean DEFAULT true,
  published_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  sort integer DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.board_reports (
  id bigint DEFAULT nextval('board_reports_id_seq'::regclass) NOT NULL,
  week_start date,
  title text,
  body text,
  kpis jsonb,
  created_at timestamp with time zone DEFAULT now(),
  report_type text DEFAULT 'weekly'::text
);

CREATE TABLE IF NOT EXISTS public.brand_assets (
  id bigint DEFAULT nextval('brand_assets_id_seq'::regclass) NOT NULL,
  kind text NOT NULL,
  platform text,
  filename text NOT NULL,
  url text NOT NULL,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.budget_lines (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  budget_id bigint NOT NULL,
  account_code text NOT NULL,
  period_month date NOT NULL,
  amount numeric(18,2) DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.budgets (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text NOT NULL,
  fiscal_year integer NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  created_by text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.business_rules (
  id bigint DEFAULT nextval('business_rules_id_seq'::regclass) NOT NULL,
  name text,
  category text,
  priority integer DEFAULT 100,
  when_json jsonb NOT NULL,
  then_json jsonb NOT NULL,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.canary_records (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  kind text NOT NULL,
  label text NOT NULL,
  fingerprint text NOT NULL,
  planted_table text,
  planted_id text,
  honeytoken_email text,
  notes text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.canon_eval_questions (
  id bigint DEFAULT nextval('canon_eval_questions_id_seq'::regclass) NOT NULL,
  category text,
  question text NOT NULL,
  reference text,
  active boolean DEFAULT true,
  layer text DEFAULT 'company'::text,
  agent_key text
);

CREATE TABLE IF NOT EXISTS public.canon_eval_runs (
  id bigint DEFAULT nextval('canon_eval_runs_id_seq'::regclass) NOT NULL,
  run_at timestamp with time zone DEFAULT now(),
  agent text,
  asked integer,
  passed integer,
  score_pct numeric,
  gaps jsonb
);

CREATE TABLE IF NOT EXISTS public.category_agents (
  slug text NOT NULL,
  name text NOT NULL,
  emoji text DEFAULT '🛠️'::text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  persona text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  requires_regulation boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.category_quote_specs (
  id bigint DEFAULT nextval('category_quote_specs_id_seq'::regclass) NOT NULL,
  spec_group text NOT NULL,
  aspect text NOT NULL,
  label text NOT NULL,
  match_regex text NOT NULL,
  mandatory boolean DEFAULT true NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.category_specs (
  category text NOT NULL,
  label text,
  fields jsonb NOT NULL,
  updated_at timestamp with time zone DEFAULT now(),
  supplier_requirements jsonb,
  compliance_checklist jsonb,
  reqs_updated_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.chat_threads (
  inquiry_id text NOT NULL,
  supplier_id bigint NOT NULL,
  customer_id uuid,
  status text DEFAULT 'requested'::text NOT NULL,
  reason text,
  requested_by text,
  category text,
  strikes integer DEFAULT 0 NOT NULL,
  opened_at timestamp with time zone,
  closed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.chat_violations (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  inquiry_id text,
  supplier_id bigint,
  sender_role text,
  sender_email text,
  matched text,
  body text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.collections_config (
  id integer DEFAULT 1 NOT NULL,
  interest_pa numeric DEFAULT 0.09 NOT NULL,
  admin_fee numeric DEFAULT 250 NOT NULL,
  escalate_working_days integer DEFAULT 30 NOT NULL,
  reminder_max integer DEFAULT 3 NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_faq (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  section text DEFAULT 'General'::text NOT NULL,
  sort integer DEFAULT 0 NOT NULL,
  question text NOT NULL,
  answer text,
  audience text DEFAULT 'all'::text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  source_note text,
  tags text[] DEFAULT '{}'::text[],
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  approved_at timestamp with time zone,
  approved_by text,
  public boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_vision (
  id integer DEFAULT 1 NOT NULL,
  vision text NOT NULL,
  mission text NOT NULL,
  principles text,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.compliance_sources (
  id bigint DEFAULT nextval('compliance_sources_id_seq'::regclass) NOT NULL,
  authority text NOT NULL,
  topic text NOT NULL,
  url text NOT NULL,
  last_signature text,
  last_summary text,
  last_checked_at timestamp with time zone,
  last_changed_at timestamp with time zone,
  active boolean DEFAULT true NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  doc_path text,
  doc_bytes bigint,
  doc_content_type text,
  doc_downloaded_at timestamp with time zone,
  fetch_mode text DEFAULT 'direct'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.contact_messages (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text,
  email text,
  phone text,
  message text,
  source text DEFAULT 'contact_page'::text,
  status text DEFAULT 'new'::text,
  user_agent text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.content_drafts (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  channel text DEFAULT 'social'::text NOT NULL,
  category text,
  title text,
  body text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  source text DEFAULT 'marketing_agent'::text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  staged_at timestamp with time zone,
  image_url text,
  review_status text DEFAULT 'pending'::text,
  founder_comment text,
  reviewed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.content_drafts_backup_20260724 (
  id bigint,
  channel text,
  category text,
  title text,
  body text,
  status text,
  source text,
  created_at timestamp with time zone,
  staged_at timestamp with time zone,
  image_url text,
  review_status text,
  founder_comment text,
  reviewed_at timestamp with time zone,
  _pk bigint GENERATED ALWAYS AS IDENTITY NOT NULL
);

CREATE TABLE IF NOT EXISTS public.crm_activities (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  entity text NOT NULL,
  entity_id text NOT NULL,
  type text NOT NULL,
  subject text,
  body text,
  actor text,
  due_at timestamp with time zone,
  done boolean DEFAULT false NOT NULL,
  done_at timestamp with time zone,
  meta jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.crm_lost_reasons (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  label text NOT NULL,
  sort_order integer DEFAULT 0 NOT NULL,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.crm_notes (
  id bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
  entity text NOT NULL,
  entity_id text NOT NULL,
  body text NOT NULL,
  author text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.crm_stages (
  key text NOT NULL,
  label text NOT NULL,
  sort_order integer DEFAULT 0 NOT NULL,
  probability integer DEFAULT 0 NOT NULL,
  is_won boolean DEFAULT false NOT NULL,
  is_lost boolean DEFAULT false NOT NULL,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.crm_tasks (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  title text NOT NULL,
  detail text,
  status text DEFAULT 'open'::text NOT NULL,
  priority text DEFAULT 'normal'::text,
  source text DEFAULT 'admin'::text,
  entity text,
  entity_id text,
  due_date date,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  done_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.cron_job_seen (
  jobid bigint NOT NULL,
  jobname text NOT NULL,
  schedule text,
  first_seen timestamp with time zone DEFAULT now() NOT NULL,
  last_seen timestamp with time zone DEFAULT now() NOT NULL,
  last_success timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.customer_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.customer_phone_otps (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  customer_id uuid,
  phone text NOT NULL,
  code_hash text NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  attempts integer DEFAULT 0,
  consumed boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.customers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  full_name text,
  phone text,
  email text,
  created_at timestamp with time zone DEFAULT now(),
  phone_verified boolean DEFAULT false,
  banned boolean DEFAULT false,
  banned_reason text,
  chat_strikes integer DEFAULT 0,
  date_of_birth date,
  email_verified boolean DEFAULT false NOT NULL,
  tos_accepted_at timestamp with time zone,
  tos_version text,
  wa_optin boolean DEFAULT false,
  signed_terms_url text,
  signed_terms_path text,
  signed_terms_at timestamp with time zone,
  tos_ip text,
  locale text DEFAULT 'en'::text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.data_owner_registry (
  table_name text NOT NULL,
  owner text DEFAULT 'Founder'::text NOT NULL,
  steward_agent text,
  classification text,
  notes text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.decision_log (
  id bigint DEFAULT nextval('decision_log_id_seq'::regclass) NOT NULL,
  actor text,
  kind text NOT NULL,
  ctx jsonb,
  decision text,
  confidence numeric,
  reasons jsonb,
  sources jsonb,
  route_to text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.decision_policy (
  key text NOT NULL,
  value jsonb NOT NULL,
  description text,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.deploy_state (
  id integer NOT NULL,
  dirty boolean DEFAULT false,
  last_deploy timestamp with time zone,
  last_status text
);

CREATE TABLE IF NOT EXISTS public.dept_library (
  id bigint DEFAULT nextval('dept_library_id_seq'::regclass) NOT NULL,
  department text NOT NULL,
  category text,
  domain text,
  title text NOT NULL,
  content text NOT NULL,
  tags text,
  source_file text,
  tsv tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((((COALESCE(title, ''::text) || ' '::text) || COALESCE(tags, ''::text)) || ' '::text) || COALESCE(content, ''::text)))) STORED,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.doc_backups (
  id bigint DEFAULT nextval('doc_backups_id_seq'::regclass) NOT NULL,
  entity text NOT NULL,
  entity_id text NOT NULL,
  doc_type text,
  bucket text,
  path text,
  file_name text,
  dropbox_path text,
  bytes bigint,
  status text DEFAULT 'pending'::text NOT NULL,
  error text,
  attempts integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  backed_up_at timestamp with time zone,
  source text DEFAULT 'storage'::text NOT NULL,
  gen_kind text,
  gen_ref text,
  dedupe_key text
);

CREATE TABLE IF NOT EXISTS public.doc_reviews (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  lead_id bigint,
  from_email text,
  subject text,
  file_name text,
  file_path text,
  mime text,
  ai_relevant boolean,
  ai_category text,
  ai_summary text,
  ai_suggested_field text,
  ai_confidence text,
  status text DEFAULT 'pending'::text NOT NULL,
  decided_by text,
  decided_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  auto_applied boolean DEFAULT false,
  extracted jsonb
);

CREATE TABLE IF NOT EXISTS public.doc_versions (
  id bigint DEFAULT nextval('doc_versions_id_seq'::regclass) NOT NULL,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  version integer NOT NULL,
  snapshot jsonb NOT NULL,
  checksum text,
  changed_fields text[] DEFAULT '{}'::text[],
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.document_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.documents (
  id bigint DEFAULT nextval('documents_id_seq'::regclass) NOT NULL,
  bucket text NOT NULL,
  path text NOT NULL,
  file_name text,
  kind text NOT NULL,
  ref_table text,
  ref_id text,
  mime text,
  status text DEFAULT 'pending'::text NOT NULL,
  extracted jsonb,
  indexed boolean DEFAULT false,
  error text,
  attempts integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  processed_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.dr_restore (
  id bigint DEFAULT nextval('dr_restore_id_seq'::regclass) NOT NULL,
  drill_at timestamp with time zone DEFAULT now(),
  kind text,
  "row" jsonb
);

CREATE TABLE IF NOT EXISTS public.dropbox_files (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  dropbox_id text,
  path text NOT NULL,
  name text,
  is_folder boolean DEFAULT false,
  size bigint DEFAULT 0,
  content_hash text,
  server_modified timestamp with time zone,
  synced_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ea_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  kind text DEFAULT 'meeting'::text NOT NULL,
  title text NOT NULL,
  starts_at timestamp with time zone,
  ends_at timestamp with time zone,
  all_day boolean DEFAULT false,
  location text,
  attendees text[],
  notes text,
  source text DEFAULT 'manual'::text,
  external_id text,
  status text DEFAULT 'scheduled'::text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ea_meetings (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  title text,
  meeting_at timestamp with time zone DEFAULT now(),
  attendees text[],
  summary text,
  decisions jsonb DEFAULT '[]'::jsonb,
  action_items jsonb DEFAULT '[]'::jsonb,
  source text DEFAULT 'manual'::text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ea_reminders (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  title text NOT NULL,
  remind_at timestamp with time zone NOT NULL,
  notes text,
  done boolean DEFAULT false,
  done_at timestamp with time zone,
  notified_at timestamp with time zone,
  source text DEFAULT 'manual'::text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ea_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  agenda jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.email_suppressions (
  email text NOT NULL,
  reason text DEFAULT 'unsubscribe'::text,
  source text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.email_verifications (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  email text NOT NULL,
  token text,
  purpose text DEFAULT 'signup'::text NOT NULL,
  user_kind text DEFAULT 'customer'::text NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  used_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  token_hash text
);

CREATE TABLE IF NOT EXISTS public.error_events (
  id bigint DEFAULT nextval('error_events_id_seq'::regclass) NOT NULL,
  source text NOT NULL,
  kind text,
  severity text DEFAULT 'error'::text,
  detail jsonb,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.escalations_archive_20260724 (
  src text,
  "row" jsonb,
  _pk bigint GENERATED ALWAYS AS IDENTITY NOT NULL
);

CREATE TABLE IF NOT EXISTS public.exec_reports (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  officer text NOT NULL,
  period text,
  summary text,
  findings jsonb DEFAULT '[]'::jsonb,
  recommendations jsonb DEFAULT '[]'::jsonb,
  metrics jsonb DEFAULT '{}'::jsonb,
  status text DEFAULT 'new'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.expense_entries (
  id bigint DEFAULT nextval('expense_entries_id_seq'::regclass) NOT NULL,
  vendor text NOT NULL,
  category text,
  amount numeric NOT NULL,
  currency text DEFAULT 'USD'::text NOT NULL,
  charged_on date DEFAULT CURRENT_DATE NOT NULL,
  note text,
  source text DEFAULT 'manual'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  doc_path text,
  doc_name text,
  doc_content_type text
);

CREATE TABLE IF NOT EXISTS public.expenses (
  id bigint DEFAULT nextval('expenses_id_seq'::regclass) NOT NULL,
  vendor text NOT NULL,
  category text NOT NULL,
  description text,
  amount numeric NOT NULL,
  currency text DEFAULT 'USD'::text NOT NULL,
  cadence text DEFAULT 'monthly'::text NOT NULL,
  expense_date date,
  active boolean DEFAULT true NOT NULL,
  source text DEFAULT 'seed'::text NOT NULL,
  confidence text DEFAULT 'estimate'::text NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  next_due date,
  last_reminded_at timestamp with time zone,
  reminder_days integer DEFAULT 3 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.experiment_assignments (
  experiment text NOT NULL,
  subject text NOT NULL,
  variant text,
  assigned_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.experiment_events (
  id bigint DEFAULT nextval('experiment_events_id_seq'::regclass) NOT NULL,
  experiment text,
  subject text,
  variant text,
  event text,
  value numeric,
  ts timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.experiments (
  key text NOT NULL,
  status text DEFAULT 'running'::text,
  metric text,
  variants jsonb NOT NULL,
  started_at timestamp with time zone DEFAULT now(),
  stopped_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.fa_assets (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  asset_no text,
  name text NOT NULL,
  category text,
  acquire_date date DEFAULT CURRENT_DATE NOT NULL,
  in_service_date date DEFAULT CURRENT_DATE NOT NULL,
  cost numeric(18,2) NOT NULL,
  salvage_value numeric(18,2) DEFAULT 0 NOT NULL,
  useful_life_months integer NOT NULL,
  method text DEFAULT 'straight_line'::text NOT NULL,
  asset_account text DEFAULT '1600'::text NOT NULL,
  accum_account text DEFAULT '1650'::text NOT NULL,
  expense_account text DEFAULT '6400'::text NOT NULL,
  accumulated_depreciation numeric(18,2) DEFAULT 0 NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  disposed_date date,
  created_by text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.fa_depreciation (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  asset_id bigint NOT NULL,
  period date NOT NULL,
  amount numeric(18,2) NOT NULL,
  gl_journal_id bigint,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.feature_flags (
  key text NOT NULL,
  enabled boolean DEFAULT false,
  rollout_pct integer DEFAULT 100,
  audience jsonb DEFAULT '{}'::jsonb,
  description text,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.finance_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  forecast jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.finance_reports (
  id bigint DEFAULT nextval('finance_reports_id_seq'::regclass) NOT NULL,
  period_start date,
  period_end date,
  kind text DEFAULT 'weekly'::text,
  summary text,
  kpis jsonb,
  html_path text,
  xlsx_path text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  pdf_path text
);

CREATE TABLE IF NOT EXISTS public.finance_snapshots (
  id bigint DEFAULT nextval('finance_snapshots_id_seq'::regclass) NOT NULL,
  period_start date,
  period_end date,
  revenue_aed numeric DEFAULT 0,
  fees_collected_aed numeric DEFAULT 0,
  fees_pending_aed numeric DEFAULT 0,
  refunds_aed numeric DEFAULT 0,
  supplier_sub_aed numeric DEFAULT 0,
  expenses_aed numeric DEFAULT 0,
  net_aed numeric DEFAULT 0,
  kpis jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.founder_alerts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  level text DEFAULT 'info'::text,
  event text NOT NULL,
  detail text,
  channel text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.fraud_flags (
  kind text NOT NULL,
  subject_type text NOT NULL,
  subject_id text NOT NULL,
  severity text DEFAULT 'medium'::text NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb,
  status text DEFAULT 'open'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.gl_accounts (
  code text NOT NULL,
  name text NOT NULL,
  type text NOT NULL,
  subtype text,
  normal_balance character(1) NOT NULL,
  parent_code text,
  is_active boolean DEFAULT true NOT NULL,
  description text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.gl_expense_map (
  category text NOT NULL,
  account_code text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.gl_journal (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  entry_no text,
  entry_date date DEFAULT ((now() AT TIME ZONE 'utc'::text))::date NOT NULL,
  memo text,
  source text DEFAULT 'manual'::text NOT NULL,
  source_ref text,
  currency text DEFAULT 'AED'::text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  reverses bigint,
  created_by text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  posted_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.gl_journal_lines (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  journal_id bigint NOT NULL,
  line_no integer,
  account_code text NOT NULL,
  debit numeric(18,2) DEFAULT 0 NOT NULL,
  credit numeric(18,2) DEFAULT 0 NOT NULL,
  memo text
);

CREATE TABLE IF NOT EXISTS public.gl_settings (
  key text NOT NULL,
  num_value numeric,
  txt_value text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.graph_edges (
  src_kind text NOT NULL,
  src_ref text NOT NULL,
  rel text NOT NULL,
  dst_kind text NOT NULL,
  dst_ref text NOT NULL,
  props jsonb DEFAULT '{}'::jsonb,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.graph_nodes (
  kind text NOT NULL,
  ref_id text NOT NULL,
  label text,
  props jsonb DEFAULT '{}'::jsonb,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.health_checks (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  check_kind text NOT NULL,
  target text,
  ok boolean,
  status_code integer,
  latency_ms integer,
  detail text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.health_state (
  id integer NOT NULL,
  last_run timestamp with time zone,
  last_status text,
  last_alert_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.hlm_digest_log (
  id bigint DEFAULT nextval('hlm_digest_log_id_seq'::regclass) NOT NULL,
  ts timestamp with time zone DEFAULT now(),
  coin text,
  dir integer,
  lean real,
  long_n integer,
  short_n integer
);

CREATE TABLE IF NOT EXISTS public.hlm_state (
  key text NOT NULL,
  val jsonb
);

CREATE TABLE IF NOT EXISTS public.hlm_watchlist (
  addr text NOT NULL,
  name text,
  score real
);

CREATE TABLE IF NOT EXISTS public.inbound_messages (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  lead_id bigint,
  from_email text,
  to_email text,
  subject text,
  body text,
  attachments_count integer DEFAULT 0,
  matched_existing boolean DEFAULT false,
  created_new_lead boolean DEFAULT false,
  ai_ok boolean DEFAULT false,
  ai_notes text,
  raw jsonb,
  created_at timestamp with time zone DEFAULT now(),
  needs_review boolean DEFAULT false,
  ai_category text,
  ai_draft_reply text,
  ai_summary text,
  triaged_at timestamp with time zone,
  replied_at timestamp with time zone,
  replied_by text
);

CREATE TABLE IF NOT EXISTS public.inquiries (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  customer_id uuid,
  category text,
  emirate text,
  role_needed text,
  raw_input text,
  spec jsonb,
  summary text,
  keywords text[],
  status text DEFAULT 'open'::text,
  created_at timestamp with time zone DEFAULT now(),
  drawing_file_path text,
  drawing_file_name text,
  boq jsonb,
  boq_confidence text,
  budget text,
  scope_type text,
  trades text[],
  brief_source text,
  hired_supplier_id bigint,
  completed_at timestamp with time zone,
  outcome text,
  no_quote_notified boolean DEFAULT false,
  drawing_redacted_paths text[],
  routing jsonb,
  pipeline_stage text,
  deal_owner text,
  stage_changed_at timestamp with time zone,
  expected_value numeric,
  lost_reason text,
  project_id uuid,
  completeness jsonb,
  rfq_ready boolean DEFAULT false,
  urgency text,
  parent_inquiry_id uuid,
  provenance jsonb,
  plausibility jsonb
);

CREATE TABLE IF NOT EXISTS public.inquiry_cancellations (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  inquiry_id uuid NOT NULL,
  customer_id uuid,
  reason text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.inquiry_intake (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  customer_id uuid,
  email text,
  category text,
  status text DEFAULT 'needs_info'::text NOT NULL,
  raw_input text,
  turns jsonb DEFAULT '[]'::jsonb NOT NULL,
  brief jsonb,
  readiness integer DEFAULT 0 NOT NULL,
  missing jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.inquiry_matches (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  inquiry_id uuid,
  supplier_id bigint,
  similarity numeric,
  sent_at timestamp with time zone DEFAULT now(),
  match_reason text
);

CREATE TABLE IF NOT EXISTS public.inquiry_requirement (
  inquiry_id uuid NOT NULL,
  trades_required text[] DEFAULT '{}'::text[] NOT NULL,
  role_required text,
  emirate text,
  authority_required text[] DEFAULT '{}'::text[] NOT NULL,
  products_norm text[] DEFAULT '{}'::text[] NOT NULL,
  brands_specified text[] DEFAULT '{}'::text[] NOT NULL,
  project_type text,
  value_band numeric,
  scope_type text,
  confidence jsonb DEFAULT '{}'::jsonb NOT NULL,
  missing_fields text[] DEFAULT '{}'::text[] NOT NULL,
  parsed_at timestamp with time zone DEFAULT now() NOT NULL,
  parser_version text
);

CREATE TABLE IF NOT EXISTS public.inv_items (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  sku text,
  name text NOT NULL,
  uom text DEFAULT 'unit'::text NOT NULL,
  category text,
  inventory_account text DEFAULT '1500'::text NOT NULL,
  cogs_account text DEFAULT '5000'::text NOT NULL,
  reorder_point numeric(18,4) DEFAULT 0 NOT NULL,
  is_active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inv_stock_moves (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  item_id bigint NOT NULL,
  move_date date DEFAULT CURRENT_DATE NOT NULL,
  move_type text NOT NULL,
  qty_delta numeric(18,4) NOT NULL,
  cost_delta numeric(18,2) NOT NULL,
  unit_cost numeric(18,4),
  ref_type text,
  ref_id text,
  gl_journal_id bigint,
  memo text,
  created_by text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.invite_schedule (
  day date NOT NULL,
  planned integer DEFAULT 0 NOT NULL,
  sent integer DEFAULT 0 NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.kb_category_aliases (
  category text NOT NULL,
  maps_to text NOT NULL,
  rationale text
);

CREATE TABLE IF NOT EXISTS public.kb_chunks (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  source_kind text NOT NULL,
  source_id text,
  category text,
  title text,
  content text NOT NULL,
  citation text,
  effective_date date,
  fts tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((COALESCE(title, ''::text) || ' '::text) || COALESCE(content, ''::text)))) STORED,
  created_at timestamp with time zone DEFAULT now(),
  embedding_gte vector(384),
  category_norm text GENERATED ALWAYS AS (NULLIF(regexp_replace(lower(COALESCE(category, ''::text)), '^cat:'::text, ''::text), ''::text)) STORED
);

CREATE TABLE IF NOT EXISTS public.kb_revisions (
  id bigint DEFAULT nextval('kb_revisions_id_seq'::regclass) NOT NULL,
  entry_kind text NOT NULL,
  entry_ref text NOT NULL,
  version integer NOT NULL,
  content text,
  status text DEFAULT 'published'::text NOT NULL,
  author text,
  reviewer text,
  review_notes text,
  ai_validation jsonb,
  created_at timestamp with time zone DEFAULT now(),
  decided_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.kb_usage_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  query text,
  category text,
  agent text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.knowledge_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.leads (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  sector text,
  sub_type text,
  company_name text NOT NULL,
  phone text,
  phone_e164 text,
  website text,
  maps_website text,
  domain text,
  street text,
  city text,
  emirate text,
  rating numeric,
  reviews integer,
  rating_maps numeric,
  reviews_maps integer,
  categories text,
  maps_url text,
  place_id text,
  email text,
  email_domain text,
  email_verified text,
  instagram text,
  whatsapp text,
  facebook text,
  website_status text,
  permanently_closed boolean DEFAULT false,
  enrich_source text,
  source text,
  scraped_at date,
  contacted boolean DEFAULT false,
  signed boolean DEFAULT false,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  description text,
  founded_year integer,
  company_type text,
  company_size text,
  business_role text,
  products text,
  services text,
  certifications text,
  scale text,
  capability_summary text,
  embedding vector(256),
  embedding_gte vector(384),
  claimed boolean DEFAULT false,
  contact_name text,
  service_emirates text[],
  bank_name text,
  bank_iban text,
  bank_account_name text,
  trade_license_no text,
  verified boolean DEFAULT false,
  portal_updated_at timestamp with time zone,
  trn text,
  license_authority text,
  license_expiry date,
  license_doc_name text,
  iban_doc_name text,
  signatory_name text,
  emirates_id text,
  accepted_terms_at timestamp with time zone,
  accepted_terms_version text,
  claimed_by text,
  license_doc_path text,
  iban_doc_path text,
  email_shared boolean DEFAULT false,
  linkedin text,
  employee_count integer,
  business_hours text,
  catalogue_pdfs text,
  registration_status text,
  registration_paid_at timestamp with time zone,
  registration_expires_at timestamp with time zone,
  registration_fee_due numeric,
  egr_doc_path text,
  egr_doc_name text,
  egr_number text,
  approval_status text,
  ai_review_notes text,
  ai_review_flags jsonb,
  ai_reviewed_at timestamp with time zone,
  registration_submitted_at timestamp with time zone,
  app_rating numeric,
  app_reviews integer DEFAULT 0,
  invite_status text,
  invited_at timestamp with time zone,
  lifecycle_stage text,
  banned boolean DEFAULT false,
  banned_reason text,
  chat_strikes integer DEFAULT 0,
  verification_status text DEFAULT 'unverified'::text,
  owner_dob date,
  owner_email_verified boolean DEFAULT false NOT NULL,
  license_city text,
  doc_extracted_at timestamp with time zone,
  name_corrected_from text,
  catalog_doc_paths text[],
  company_profile_doc_path text,
  approved_at timestamp with time zone,
  approval_decided_by text,
  rejection_reason text,
  tags text[],
  wa_optin boolean DEFAULT false,
  signed_terms_url text,
  signed_terms_path text,
  signed_terms_at timestamp with time zone,
  accepted_terms_ip text,
  matching_blocked boolean DEFAULT false NOT NULL,
  matching_block_reason text,
  rv_reveals integer DEFAULT 0 NOT NULL,
  rv_responded integer DEFAULT 0 NOT NULL,
  rv_response_rate numeric,
  rv_nonresponse_refunds integer DEFAULT 0 NOT NULL,
  vat_number text,
  vat_doc_path text,
  insurance_doc_path text,
  insurance_expiry date,
  manufacturer_authorizations jsonb,
  machinery jsonb,
  team_size integer,
  engineers_count integer,
  warehouse_area text,
  brands_carried jsonb,
  client_references jsonb,
  iso_certifications jsonb,
  capability_score integer,
  iso_expiry date,
  iso_doc_path text,
  manufacturer_auth_expiry date,
  manufacturer_auth_doc_path text,
  capability_enriched_at timestamp with time zone,
  locale text DEFAULT 'en'::text NOT NULL,
  owner_phone_verified boolean DEFAULT false,
  founding_rank integer,
  subscription_exempt boolean DEFAULT false NOT NULL,
  subscription_paid_until date,
  claim_token uuid DEFAULT gen_random_uuid() NOT NULL,
  invite_trades text[]
);

CREATE TABLE IF NOT EXISTS public.legal_checklist (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  requirement text NOT NULL,
  category text NOT NULL,
  applies_to text,
  priority integer DEFAULT 2 NOT NULL,
  match_slug text,
  present boolean DEFAULT false NOT NULL,
  notes text
);

CREATE TABLE IF NOT EXISTS public.legal_documents (
  slug text NOT NULL,
  title text NOT NULL,
  category text DEFAULT 'public'::text NOT NULL,
  version text DEFAULT '1.0'::text,
  effective_date date DEFAULT CURRENT_DATE,
  summary text,
  body_html text,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.legal_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.legal_reviews (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  doc_kind text,
  title text,
  source text,
  summary text,
  risk_flags jsonb DEFAULT '[]'::jsonb,
  risk_level text,
  needs_licensed_review boolean DEFAULT true,
  reviewed_at timestamp with time zone DEFAULT now() NOT NULL,
  reviewed_by text DEFAULT 'legal_ai'::text
);

CREATE TABLE IF NOT EXISTS public.llm_calls (
  id bigint DEFAULT nextval('llm_calls_id_seq'::regclass) NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  fn text NOT NULL,
  purpose text,
  model_wanted text,
  model_used text,
  fell_back boolean GENERATED ALWAYS AS ((model_used IS DISTINCT FROM model_wanted)) STORED,
  ok boolean DEFAULT true NOT NULL,
  attempts integer DEFAULT 1 NOT NULL,
  cached boolean,
  prompt_tokens integer,
  output_tokens integer,
  cached_tokens integer,
  latency_ms integer,
  err text
);

CREATE TABLE IF NOT EXISTS public.llm_policy (
  model text NOT NULL,
  role text NOT NULL,
  approved boolean DEFAULT true NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.market_intel (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  kind text NOT NULL,
  title text NOT NULL,
  detail text,
  source text,
  impact text DEFAULT 'medium'::text,
  status text DEFAULT 'open'::text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.marketing_library (
  id bigint DEFAULT nextval('marketing_library_id_seq'::regclass) NOT NULL,
  category text NOT NULL,
  domain text,
  title text NOT NULL,
  content text NOT NULL,
  tags text,
  source_file text,
  tsv tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((((COALESCE(title, ''::text) || ' '::text) || COALESCE(tags, ''::text)) || ' '::text) || COALESCE(content, ''::text)))) STORED,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.marketing_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  plan jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.match_eval_runs (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  ran_at timestamp with time zone DEFAULT now(),
  precision_pct numeric,
  recall_pct numeric,
  cases_total integer,
  detail jsonb
);

CREATE TABLE IF NOT EXISTS public.materials (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  category text NOT NULL,
  item text NOT NULL,
  properties jsonb DEFAULT '{}'::jsonb,
  standards text[] DEFAULT '{}'::text[],
  price_band text,
  alternatives jsonb DEFAULT '[]'::jsonb,
  pros text[] DEFAULT '{}'::text[],
  cons text[] DEFAULT '{}'::text[],
  source text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.mdm_brands (
  id bigint DEFAULT nextval('mdm_brands_id_seq'::regclass) NOT NULL,
  name text NOT NULL,
  category text,
  manufacturer text,
  aliases text[] DEFAULT '{}'::text[],
  active boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.mdm_cities (
  id bigint DEFAULT nextval('mdm_cities_id_seq'::regclass) NOT NULL,
  name text NOT NULL,
  emirate_code text,
  aliases text[] DEFAULT '{}'::text[],
  active boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.mdm_currencies (
  code text NOT NULL,
  name text NOT NULL,
  symbol text,
  is_base boolean DEFAULT false,
  active boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.mdm_emirates (
  code text NOT NULL,
  name text NOT NULL,
  name_ar text,
  aliases text[] DEFAULT '{}'::text[],
  active boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.mdm_manufacturers (
  id bigint DEFAULT nextval('mdm_manufacturers_id_seq'::regclass) NOT NULL,
  name text NOT NULL,
  country text,
  aliases text[] DEFAULT '{}'::text[],
  active boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.mdm_standards (
  id bigint DEFAULT nextval('mdm_standards_id_seq'::regclass) NOT NULL,
  code text NOT NULL,
  title text,
  authority text,
  domain text,
  aliases text[] DEFAULT '{}'::text[],
  active boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.mdm_units (
  code text NOT NULL,
  name text NOT NULL,
  dimension text,
  aliases text[] DEFAULT '{}'::text[],
  active boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.memory_promotions (
  memory_id bigint NOT NULL,
  kb_chunk_id bigint,
  category text,
  promoted_at timestamp with time zone DEFAULT now() NOT NULL,
  promoted_by text
);

CREATE TABLE IF NOT EXISTS public.messages (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  inquiry_id uuid,
  supplier_id bigint,
  customer_id uuid,
  sender text NOT NULL,
  body text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  read_by_customer boolean DEFAULT false,
  read_by_supplier boolean DEFAULT false,
  flagged boolean DEFAULT false,
  blocked boolean DEFAULT false,
  redacted_body text
);

CREATE TABLE IF NOT EXISTS public.meta_insights (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  campaign_id text NOT NULL,
  campaign_name text,
  effective_status text,
  objective text,
  time_window text DEFAULT 'last_30d'::text NOT NULL,
  spend numeric(14,2) DEFAULT 0,
  impressions bigint DEFAULT 0,
  clicks bigint DEFAULT 0,
  reach bigint DEFAULT 0,
  ctr numeric(8,3),
  cpc numeric(10,3),
  results bigint DEFAULT 0,
  currency text DEFAULT 'AED'::text,
  synced_at timestamp with time zone DEFAULT now() NOT NULL,
  synced_via text DEFAULT 'meta_sync'::text
);

CREATE TABLE IF NOT EXISTS public.notifications (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  type text NOT NULL,
  to_email text,
  to_role text,
  lead_id bigint,
  inquiry_id uuid,
  quote_id uuid,
  subject text,
  body text,
  status text DEFAULT 'pending'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  sent_at timestamp with time zone,
  channel text DEFAULT 'email'::text,
  to_phone text,
  attempts integer DEFAULT 0 NOT NULL,
  last_error text,
  html text,
  cc_emails text[] DEFAULT '{}'::text[] NOT NULL
);

CREATE TABLE IF NOT EXISTS public.ops_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_action_executor (
  action_class text NOT NULL,
  kind text NOT NULL,
  target text NOT NULL,
  params jsonb DEFAULT '{}'::jsonb NOT NULL,
  active boolean DEFAULT true NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  advisory_safe boolean DEFAULT false NOT NULL,
  department text
);

CREATE TABLE IF NOT EXISTS public.org_agents (
  agent_key text NOT NULL,
  department text NOT NULL,
  role text NOT NULL,
  kind text DEFAULT 'brain'::text NOT NULL,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.org_authority (
  dept_key text NOT NULL,
  action_class text NOT NULL,
  max_tier text NOT NULL,
  threshold_aed numeric,
  note text
);

CREATE TABLE IF NOT EXISTS public.org_departments (
  dept_key text NOT NULL,
  name text NOT NULL,
  charter text NOT NULL,
  north_star text,
  health_fn text,
  lead_agent text,
  active boolean DEFAULT true NOT NULL,
  sort integer DEFAULT 100 NOT NULL,
  brain_agent text
);

CREATE TABLE IF NOT EXISTS public.org_memory (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  scope text DEFAULT 'global'::text NOT NULL,
  kind text DEFAULT 'note'::text NOT NULL,
  content text NOT NULL,
  source text,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_objectives (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  objective text NOT NULL,
  raw_input text,
  created_by text DEFAULT 'founder'::text,
  status text DEFAULT 'open'::text NOT NULL,
  priority text DEFAULT 'normal'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  closed_at timestamp with time zone,
  outcome text
);

CREATE TABLE IF NOT EXISTS public.org_onboarding (
  agent_key text NOT NULL,
  department text,
  status text DEFAULT 'onboarding'::text NOT NULL,
  l1_score numeric,
  l1_at timestamp with time zone,
  l2_score numeric,
  l2_at timestamp with time zone,
  l3_score numeric,
  l3_at timestamp with time zone,
  l4_score numeric,
  l4_at timestamp with time zone,
  pass_threshold numeric DEFAULT 85 NOT NULL,
  probation_reviews_done integer DEFAULT 0 NOT NULL,
  probation_reviews_required integer DEFAULT 3 NOT NULL,
  certified_at timestamp with time zone,
  recert_due date,
  note text,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.org_reset_backup_20260724 (
  src text,
  "row" jsonb,
  _pk bigint GENERATED ALWAYS AS IDENTITY NOT NULL
);

CREATE TABLE IF NOT EXISTS public.org_tasks (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  objective_id bigint,
  dept_key text,
  title text NOT NULL,
  detail text,
  status text DEFAULT 'proposed'::text NOT NULL,
  tier text,
  needs_founder boolean DEFAULT false NOT NULL,
  result jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  decided_by text,
  action_class text,
  attempts integer DEFAULT 0 NOT NULL,
  last_run_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.os_audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  actor text,
  action text NOT NULL,
  entity text,
  entity_id text,
  detail jsonb,
  ok boolean,
  err text
);

CREATE TABLE IF NOT EXISTS public.outreach (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  lead_id bigint,
  source text DEFAULT 'database'::text NOT NULL,
  email text,
  company text,
  contact_name text,
  contact_title text,
  category text,
  emirate text,
  channel text DEFAULT 'email'::text NOT NULL,
  status text DEFAULT 'queued'::text NOT NULL,
  subject text,
  body text,
  batch_date date DEFAULT CURRENT_DATE,
  sent_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.pages (
  slug text NOT NULL,
  html text NOT NULL,
  updated_at timestamp with time zone DEFAULT now(),
  html_gz text,
  _osb bytea
);

CREATE TABLE IF NOT EXISTS public.pdpl_erase_files (
  id bigint DEFAULT nextval('pdpl_erase_files_id_seq'::regclass) NOT NULL,
  request_id uuid NOT NULL,
  subject_email text NOT NULL,
  bucket text,
  storage_path text,
  dropbox_path text,
  origin text,
  status text DEFAULT 'pending'::text NOT NULL,
  error text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  erased_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.pdpl_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  kind text NOT NULL,
  email text NOT NULL,
  role text,
  details text,
  status text DEFAULT 'received'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  handled_at timestamp with time zone,
  handled_by text
);

CREATE TABLE IF NOT EXISTS public.phone_verifications (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  email text,
  phone text NOT NULL,
  code text NOT NULL,
  user_kind text DEFAULT 'customer'::text NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  used_at timestamp with time zone,
  attempts integer DEFAULT 0 NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.po_lines (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  po_id bigint NOT NULL,
  line_no integer NOT NULL,
  description text NOT NULL,
  account_code text NOT NULL,
  item_id bigint,
  qty numeric(18,4) NOT NULL,
  unit_price numeric(18,4) DEFAULT 0 NOT NULL,
  qty_received numeric(18,4) DEFAULT 0 NOT NULL,
  qty_billed numeric(18,4) DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS public.po_orders (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  po_no text,
  vendor_id bigint NOT NULL,
  order_date date DEFAULT CURRENT_DATE NOT NULL,
  expected_date date,
  currency text DEFAULT 'AED'::text NOT NULL,
  status text DEFAULT 'draft'::text NOT NULL,
  memo text,
  subtotal numeric(18,2) DEFAULT 0 NOT NULL,
  created_by text,
  approved_by text,
  approved_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.po_vendors (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text NOT NULL,
  email text,
  phone text,
  trn text,
  currency text DEFAULT 'AED'::text NOT NULL,
  is_active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.policy_rules (
  id bigint DEFAULT nextval('policy_rules_id_seq'::regclass) NOT NULL,
  name text NOT NULL,
  severity text DEFAULT 'high'::text NOT NULL,
  forbid_regex text NOT NULL,
  scope text DEFAULT 'all'::text NOT NULL,
  note text,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.pricing_config (
  id integer DEFAULT 1 NOT NULL,
  promo_reveal_rate numeric DEFAULT 0.02 NOT NULL,
  promo_reveal_cap numeric DEFAULT 250 NOT NULL,
  standard_reveal_rate numeric DEFAULT 0.02 NOT NULL,
  standard_reveal_cap numeric DEFAULT 250 NOT NULL,
  promo_until timestamp with time zone,
  supplier_free_count integer DEFAULT 1000 NOT NULL,
  supplier_reg_fee numeric DEFAULT 100 NOT NULL,
  supplier_reg_period text DEFAULT 'yearly'::text NOT NULL,
  refund_window_working_days integer DEFAULT 3 NOT NULL,
  updated_at timestamp with time zone DEFAULT now(),
  auto_approve_suppliers boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.projects (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  customer_id uuid,
  name text NOT NULL,
  description text,
  status text DEFAULT 'active'::text NOT NULL,
  target_open_date date,
  budget_total numeric,
  meta jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.prompt_benchmarks (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  prompt_key text NOT NULL,
  name text NOT NULL,
  input text NOT NULL,
  rubric text NOT NULL,
  weight numeric DEFAULT 1 NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.prompt_eval_runs (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  prompt_key text NOT NULL,
  version integer,
  score numeric,
  cases_total integer,
  detail jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.prompt_versions (
  id bigint DEFAULT nextval('prompt_versions_id_seq'::regclass) NOT NULL,
  prompt_key text,
  version integer NOT NULL,
  content text NOT NULL,
  status text DEFAULT 'active'::text,
  rollout_pct integer DEFAULT 100,
  eval_score numeric,
  approved_by text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.prompts (
  key text NOT NULL,
  owner text,
  description text,
  active_version integer DEFAULT 1,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.public_holidays (
  holiday_date date NOT NULL,
  name text NOT NULL,
  confirmed boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.qa_results (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  run_at timestamp with time zone DEFAULT now(),
  passed boolean,
  total integer,
  failed integer,
  results jsonb
);

CREATE TABLE IF NOT EXISTS public.qd_compare_cache (
  inquiry_id text NOT NULL,
  quotes_hash text NOT NULL,
  lang text DEFAULT 'en'::text NOT NULL,
  analysis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.qd_deploy_src (
  path text NOT NULL,
  data text
);

CREATE TABLE IF NOT EXISTS public.qd_i18n (
  source text NOT NULL,
  slug text NOT NULL,
  title text,
  html text,
  status text DEFAULT 'done'::text,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.qd_i18n_chunks (
  source text NOT NULL,
  slug text NOT NULL,
  idx integer NOT NULL,
  ar text
);

CREATE TABLE IF NOT EXISTS public.qualification_playbooks (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  category text NOT NULL,
  version integer DEFAULT 1 NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  questions jsonb DEFAULT '[]'::jsonb NOT NULL,
  effective_date date DEFAULT CURRENT_DATE,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.questions (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  inquiry_id uuid,
  supplier_id bigint,
  customer_id uuid,
  question text NOT NULL,
  answer text,
  asked_at timestamp with time zone DEFAULT now(),
  answered_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.quote_committed_items (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  review_id uuid NOT NULL,
  seq integer DEFAULT 0,
  description text,
  brand text,
  model text,
  spec text,
  qty text,
  unit_price numeric,
  line_amount numeric,
  warranty text,
  source text DEFAULT 'own'::text,
  sub_quote_path text,
  sub_cost numeric,
  markup_pct numeric,
  customer_description text,
  hide_brand boolean DEFAULT false,
  confirmed boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.quote_comparisons (
  id bigint DEFAULT nextval('quote_comparisons_id_seq'::regclass) NOT NULL,
  inquiry_id uuid NOT NULL,
  customer_id uuid,
  lang text DEFAULT 'en'::text,
  quote_count integer,
  signature text,
  analysis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.quote_items (
  id bigint DEFAULT nextval('quote_items_id_seq'::regclass) NOT NULL,
  quote_id text NOT NULL,
  line_no integer,
  description text,
  brand text,
  model text,
  specification text,
  qty numeric,
  unit text,
  unit_price numeric,
  labour numeric,
  install numeric,
  commissioning numeric,
  amount numeric,
  country_of_origin text,
  datasheet_path text,
  notes text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.quote_pdf_cache (
  quote_id uuid NOT NULL,
  lang text NOT NULL,
  customer_id uuid,
  bucket text NOT NULL,
  path text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.quote_requirements (
  category text NOT NULL,
  required_sections jsonb DEFAULT '[]'::jsonb NOT NULL,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.quote_review_messages (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  review_id uuid NOT NULL,
  role text NOT NULL,
  body text,
  attachments jsonb DEFAULT '[]'::jsonb,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.quote_reviews (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  inquiry_id uuid NOT NULL,
  supplier_id bigint NOT NULL,
  status text DEFAULT 'open'::text NOT NULL,
  original_file_path text,
  original_file_name text,
  extracted jsonb,
  currency text DEFAULT 'AED'::text,
  total_amount numeric,
  completed_at timestamp with time zone,
  committed_hash text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.quotes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  inquiry_id uuid,
  supplier_id bigint,
  quote_amount numeric NOT NULL,
  notes text,
  margin_rate numeric GENERATED ALWAYS AS (margin_rate(quote_amount)) STORED,
  app_fee numeric GENERATED ALWAYS AS (round((quote_amount * margin_rate(quote_amount)), 2)) STORED,
  customer_price numeric GENERATED ALWAYS AS (round((quote_amount * ((1)::numeric + margin_rate(quote_amount))), 2)) STORED,
  status text DEFAULT 'submitted'::text,
  created_at timestamp with time zone DEFAULT now(),
  lead_time text,
  validity text,
  payment_terms text,
  warranty text,
  scope text,
  conditions text,
  exclusions text,
  anonymized boolean DEFAULT false,
  original_file_path text,
  original_file_name text,
  source text DEFAULT 'form'::text NOT NULL,
  masked_terms jsonb,
  extracted jsonb,
  expires_at timestamp with time zone,
  review_id uuid,
  review_status text,
  committed_at timestamp with time zone,
  committed_hash text,
  committed_items jsonb,
  quality jsonb,
  structured jsonb,
  submittable boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.reg_catalog (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  jurisdiction text NOT NULL,
  authority text NOT NULL,
  code_name text NOT NULL,
  domain text NOT NULL,
  categories text[],
  priority integer DEFAULT 2 NOT NULL,
  copyright text DEFAULT 'free'::text NOT NULL,
  source_url text,
  compliance_source_id bigint,
  status text DEFAULT 'needs_source'::text NOT NULL,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.regulations (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  authority text NOT NULL,
  jurisdiction text,
  categories text[] DEFAULT '{}'::text[],
  title text NOT NULL,
  doc_ref text,
  summary text,
  key_requirements jsonb DEFAULT '[]'::jsonb,
  source_url text,
  effective_date date,
  version integer DEFAULT 1 NOT NULL,
  status text DEFAULT 'active'::text NOT NULL,
  body text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  approved_at timestamp with time zone,
  approved_by text,
  supersedes_id bigint
);

CREATE TABLE IF NOT EXISTS public.report_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.retention_policy (
  bucket text NOT NULL,
  retention_days integer,
  class text NOT NULL,
  notes text
);

CREATE TABLE IF NOT EXISTS public.reveal_invoices (
  transaction_id uuid NOT NULL,
  invoice_no text,
  bucket text,
  path text,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.review_queue (
  id bigint DEFAULT nextval('review_queue_id_seq'::regclass) NOT NULL,
  kind text NOT NULL,
  dept_key text,
  title text NOT NULL,
  summary text,
  payload jsonb,
  status text DEFAULT 'pending'::text NOT NULL,
  founder_comment text,
  created_at timestamp with time zone DEFAULT now(),
  decided_at timestamp with time zone,
  decided_by text
);

CREATE TABLE IF NOT EXISTS public.reviews (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  supplier_id bigint,
  customer_id uuid,
  inquiry_id uuid,
  transaction_id uuid,
  rating integer NOT NULL,
  comment text,
  created_at timestamp with time zone DEFAULT now(),
  r_communication smallint,
  r_quality smallint,
  r_punctuality smallint,
  r_documentation smallint,
  r_after_sales smallint,
  r_compliance smallint
);

CREATE TABLE IF NOT EXISTS public.rfq_archives (
  id bigint DEFAULT nextval('rfq_archives_id_seq'::regclass) NOT NULL,
  rfq_id text NOT NULL,
  customer_id text,
  supplier_ids text[] DEFAULT '{}'::text[],
  category text,
  status text,
  dates jsonb,
  bucket text DEFAULT 'backups'::text,
  archive_path text,
  checksum text,
  archive_version integer DEFAULT 1,
  ai_summary jsonb,
  size_bytes integer,
  created_at timestamp with time zone DEFAULT now(),
  restored_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.rl_hits (
  k text NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  _pk bigint GENERATED ALWAYS AS IDENTITY NOT NULL
);

CREATE TABLE IF NOT EXISTS public.role_permissions (
  role text NOT NULL,
  action text NOT NULL,
  constraint_json jsonb DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS public.roles (
  name text NOT NULL,
  description text
);

CREATE TABLE IF NOT EXISTS public.scrape_runs (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  run_id text,
  dataset_id text,
  actor text,
  sector text,
  emirate text,
  label text,
  status text DEFAULT 'RUNNING'::text,
  requested integer,
  fetched integer DEFAULT 0,
  inserted integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  collected_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.security_audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  db_user text DEFAULT CURRENT_USER NOT NULL,
  action text NOT NULL,
  table_name text NOT NULL,
  row_pk text,
  old_data jsonb,
  new_data jsonb
);

CREATE TABLE IF NOT EXISTS public.security_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  kind text NOT NULL,
  severity text DEFAULT 'low'::text NOT NULL,
  source text,
  subject text,
  detail jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.security_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.security_selfaudit_snapshots (
  at timestamp with time zone DEFAULT now() NOT NULL,
  rls_disabled_tables integer,
  rls_no_policy integer,
  secdef_views integer,
  secdef_fns_anon integer,
  id bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
  anon_tables integer,
  anon_views integer,
  anon_defaults integer
);

CREATE TABLE IF NOT EXISTS public.seo_categories (
  slug text NOT NULL,
  name text NOT NULL,
  search_term text,
  intro text,
  includes jsonb,
  faqs jsonb,
  sort integer DEFAULT 100,
  generated boolean DEFAULT false,
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.simulations (
  id bigint DEFAULT nextval('simulations_id_seq'::regclass) NOT NULL,
  scenario jsonb,
  result jsonb,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.site_publish_state (
  id integer DEFAULT 1 NOT NULL,
  dirty boolean DEFAULT false NOT NULL,
  last_change_at timestamp with time zone,
  last_deploy_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.social_posts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  source text DEFAULT 'manual'::text,
  content jsonb,
  image_url text,
  channels text[] DEFAULT '{}'::text[],
  schedule_at timestamp with time zone,
  mode text DEFAULT 'draft'::text,
  status text DEFAULT 'pending'::text,
  postiz_ids jsonb,
  error text
);

CREATE TABLE IF NOT EXISTS public.strategy_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.strategy_risks (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  category text NOT NULL,
  title text NOT NULL,
  likelihood integer DEFAULT 3 NOT NULL,
  impact integer DEFAULT 3 NOT NULL,
  score integer GENERATED ALWAYS AS ((likelihood * impact)) STORED,
  mitigation text,
  source text DEFAULT 'internal_scan'::text,
  status text DEFAULT 'open'::text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.stripe_events (
  event_id text NOT NULL,
  type text,
  payment_status text,
  first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
  delivery_count integer DEFAULT 1 NOT NULL,
  note text
);

CREATE TABLE IF NOT EXISTS public.supplier_capabilities (
  supplier_id bigint NOT NULL,
  services text[] DEFAULT '{}'::text[],
  brands text[] DEFAULT '{}'::text[],
  authorized_distributor jsonb DEFAULT '[]'::jsonb,
  certifications text[] DEFAULT '{}'::text[],
  team_size integer,
  engineers integer,
  technicians integer,
  equipment text[] DEFAULT '{}'::text[],
  coverage_emirates text[] DEFAULT '{}'::text[],
  insurance jsonb DEFAULT '{}'::jsonb,
  warranty_policy text,
  emergency_support boolean,
  response_time_hours numeric,
  languages text[] DEFAULT '{}'::text[],
  fleet integer,
  warehouse text,
  min_project_value numeric,
  max_project_value numeric,
  annual_capacity text,
  years_in_business integer,
  updated_at timestamp with time zone DEFAULT now(),
  trades text[] DEFAULT '{}'::text[] NOT NULL,
  roles text[] DEFAULT '{}'::text[] NOT NULL,
  products_norm text[] DEFAULT '{}'::text[] NOT NULL,
  project_types text[] DEFAULT '{}'::text[] NOT NULL,
  exclusions text[] DEFAULT '{}'::text[] NOT NULL,
  authority_approvals jsonb DEFAULT '{}'::jsonb NOT NULL,
  source_docs jsonb DEFAULT '{}'::jsonb NOT NULL,
  confidence jsonb DEFAULT '{}'::jsonb NOT NULL,
  completeness numeric,
  extracted_at timestamp with time zone,
  extractor_version text,
  review_status text DEFAULT 'pending'::text NOT NULL,
  missing_fields text[] DEFAULT '{}'::text[] NOT NULL,
  confirmed_at timestamp with time zone,
  confirmed_version integer,
  excluded_trades text[] DEFAULT '{}'::text[] NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_capability_confirmation (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  supplier_id bigint NOT NULL,
  version integer DEFAULT 1 NOT NULL,
  proposed jsonb DEFAULT '{}'::jsonb NOT NULL,
  confirmed jsonb DEFAULT '{}'::jsonb NOT NULL,
  supplier_added jsonb DEFAULT '{}'::jsonb NOT NULL,
  exclusions text[] DEFAULT '{}'::text[] NOT NULL,
  source_docs jsonb DEFAULT '{}'::jsonb NOT NULL,
  confirmed_at timestamp with time zone,
  confirmed_via text,
  agent_version text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supplier_dues (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  transaction_id uuid,
  supplier_id bigint,
  quote_id uuid,
  quote_amount numeric,
  commission_pct numeric DEFAULT 2,
  amount_due numeric,
  currency text DEFAULT 'AED'::text,
  reveal_date date,
  due_date date,
  due_date_30 date,
  status text DEFAULT 'pending'::text,
  reminders integer DEFAULT 0,
  last_reminder_at timestamp with time zone,
  overdue_emailed_at timestamp with time zone,
  fine_pct numeric DEFAULT 0,
  fine_amount numeric DEFAULT 0,
  paid_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  interest_amount numeric,
  admin_fee numeric,
  total_claim numeric,
  legal_stage text,
  legal_escalated_at timestamp with time zone,
  demand_letter_path text,
  case_file_path text,
  evidence_terms_path text,
  payment_ref text,
  stripe_session_id text
);

CREATE TABLE IF NOT EXISTS public.supplier_kpi_snapshots (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  snapshot_date date DEFAULT CURRENT_DATE NOT NULL,
  kpis jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.supply_health_snapshots (
  id bigint DEFAULT nextval('supply_health_snapshots_id_seq'::regclass) NOT NULL,
  period_end date,
  metrics jsonb,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.taxonomy_authority (
  code text NOT NULL,
  label text NOT NULL,
  emirates text[] DEFAULT '{}'::text[] NOT NULL,
  reg_catalog_ids integer[] DEFAULT '{}'::integer[] NOT NULL,
  notes text
);

CREATE TABLE IF NOT EXISTS public.taxonomy_role (
  code text NOT NULL,
  label text NOT NULL,
  aliases text[] DEFAULT '{}'::text[] NOT NULL,
  supplies boolean DEFAULT false NOT NULL,
  executes boolean DEFAULT false NOT NULL,
  whole_scope boolean DEFAULT false NOT NULL,
  sort integer DEFAULT 100 NOT NULL,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.taxonomy_trade (
  code text NOT NULL,
  label text NOT NULL,
  aliases text[] DEFAULT '{}'::text[] NOT NULL,
  authority_required text[] DEFAULT '{}'::text[] NOT NULL,
  sort integer DEFAULT 100 NOT NULL,
  active boolean DEFAULT true NOT NULL
);

CREATE TABLE IF NOT EXISTS public.templates (
  name text NOT NULL,
  content text,
  description text,
  updated_at timestamp with time zone DEFAULT now(),
  updated_by text
);

CREATE TABLE IF NOT EXISTS public.transactions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  quote_id uuid,
  inquiry_id uuid,
  supplier_id bigint,
  customer_id uuid,
  quote_amount numeric,
  app_fee numeric,
  customer_price numeric,
  fee_status text DEFAULT 'pending'::text,
  revealed_at timestamp with time zone DEFAULT now(),
  reveal_fee numeric,
  paid_by text DEFAULT 'customer'::text,
  payment_ref text,
  refund_deadline timestamp with time zone,
  refund_status text,
  refund_reason text,
  refund_requested_at timestamp with time zone,
  refund_resolved_at timestamp with time zone,
  refund_note text,
  supplier_ack_at timestamp with time zone,
  nudged_24_at timestamp with time zone,
  nudged_48_at timestamp with time zone,
  ack_token uuid DEFAULT gen_random_uuid(),
  customer_notified_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.undo_log (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  table_name text,
  row_id text,
  op text,
  before jsonb,
  actor text,
  reverted boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_roles (
  email text NOT NULL,
  role text NOT NULL,
  added_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.vt_results (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  sha256 text,
  bucket text,
  path text,
  status text,
  malicious_count integer DEFAULT 0,
  checked_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.wa_messages (
  id bigint DEFAULT nextval('wa_messages_id_seq'::regclass) NOT NULL,
  wa_from text,
  wa_to text,
  profile_name text,
  inbound text,
  reply text,
  lang text,
  escalated boolean DEFAULT false,
  sent boolean DEFAULT false,
  meta jsonb,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.yello_staging (
  company_id text NOT NULL,
  slug text,
  name text,
  city text,
  src_category text,
  profile_url text,
  website text,
  phone text,
  mobile text,
  whatsapp text,
  categories text[],
  manager text,
  established text,
  address text,
  email text,
  email_source text,
  sector text,
  stage text DEFAULT 'listed'::text NOT NULL,
  note text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

-- ===== CONSTRAINTS =====
ALTER TABLE public.admin_mfa_sessions ADD CONSTRAINT admin_mfa_sessions_pkey PRIMARY KEY (session_id);
ALTER TABLE public.agent_action_log ADD CONSTRAINT agent_action_log_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_actions ADD CONSTRAINT agent_actions_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_chats ADD CONSTRAINT agent_chats_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_command_log ADD CONSTRAINT agent_command_log_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_evals ADD CONSTRAINT agent_evals_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_expectations ADD CONSTRAINT agent_expectations_pkey PRIMARY KEY (agent);
ALTER TABLE public.agent_governance ADD CONSTRAINT agent_governance_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_knowledge ADD CONSTRAINT agent_knowledge_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_memory ADD CONSTRAINT agent_memory_pkey PRIMARY KEY (id);
ALTER TABLE public.agent_pending_actions ADD CONSTRAINT agent_pending_actions_pkey PRIMARY KEY (token);
ALTER TABLE public.agent_runs ADD CONSTRAINT agent_runs_pkey PRIMARY KEY (id);
ALTER TABLE public.ai_constitution ADD CONSTRAINT ai_constitution_pkey PRIMARY KEY (id);
ALTER TABLE public.ai_qa_log ADD CONSTRAINT ai_qa_log_pkey PRIMARY KEY (id);
ALTER TABLE public.ai_quality_snapshots ADD CONSTRAINT ai_quality_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.ai_trainer_snapshots ADD CONSTRAINT ai_trainer_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.ai_usage ADD CONSTRAINT ai_usage_pkey PRIMARY KEY (id);
ALTER TABLE public.ap_bills ADD CONSTRAINT ap_bills_pkey PRIMARY KEY (id);
ALTER TABLE public.app_blocked_domains ADD CONSTRAINT app_blocked_domains_pkey PRIMARY KEY (domain);
ALTER TABLE public.app_secrets ADD CONSTRAINT app_secrets_pkey PRIMARY KEY (key);
ALTER TABLE public.assistant_logs ADD CONSTRAINT assistant_logs_pkey PRIMARY KEY (id);
ALTER TABLE public.blog_posts ADD CONSTRAINT blog_posts_pkey PRIMARY KEY (id);
ALTER TABLE public.board_reports ADD CONSTRAINT board_reports_pkey PRIMARY KEY (id);
ALTER TABLE public.brand_assets ADD CONSTRAINT brand_assets_pkey PRIMARY KEY (id);
ALTER TABLE public.budget_lines ADD CONSTRAINT budget_lines_pkey PRIMARY KEY (id);
ALTER TABLE public.budgets ADD CONSTRAINT budgets_pkey PRIMARY KEY (id);
ALTER TABLE public.business_rules ADD CONSTRAINT business_rules_pkey PRIMARY KEY (id);
ALTER TABLE public.canary_records ADD CONSTRAINT canary_records_pkey PRIMARY KEY (id);
ALTER TABLE public.canon_eval_questions ADD CONSTRAINT canon_eval_questions_pkey PRIMARY KEY (id);
ALTER TABLE public.canon_eval_runs ADD CONSTRAINT canon_eval_runs_pkey PRIMARY KEY (id);
ALTER TABLE public.category_agents ADD CONSTRAINT category_agents_pkey PRIMARY KEY (slug);
ALTER TABLE public.category_quote_specs ADD CONSTRAINT category_quote_specs_pkey PRIMARY KEY (id);
ALTER TABLE public.category_specs ADD CONSTRAINT category_specs_pkey PRIMARY KEY (category);
ALTER TABLE public.chat_threads ADD CONSTRAINT chat_threads_pkey PRIMARY KEY (inquiry_id, supplier_id);
ALTER TABLE public.chat_violations ADD CONSTRAINT chat_violations_pkey PRIMARY KEY (id);
ALTER TABLE public.collections_config ADD CONSTRAINT collections_config_pkey PRIMARY KEY (id);
ALTER TABLE public.company_faq ADD CONSTRAINT company_faq_pkey PRIMARY KEY (id);
ALTER TABLE public.company_vision ADD CONSTRAINT company_vision_pkey PRIMARY KEY (id);
ALTER TABLE public.compliance_sources ADD CONSTRAINT compliance_sources_pkey PRIMARY KEY (id);
ALTER TABLE public.contact_messages ADD CONSTRAINT contact_messages_pkey PRIMARY KEY (id);
ALTER TABLE public.content_drafts ADD CONSTRAINT content_drafts_pkey PRIMARY KEY (id);
ALTER TABLE public.content_drafts_backup_20260724 ADD CONSTRAINT content_drafts_backup_20260724_pkey PRIMARY KEY (_pk);
ALTER TABLE public.crm_activities ADD CONSTRAINT crm_activities_pkey PRIMARY KEY (id);
ALTER TABLE public.crm_lost_reasons ADD CONSTRAINT crm_lost_reasons_pkey PRIMARY KEY (id);
ALTER TABLE public.crm_notes ADD CONSTRAINT crm_notes_pkey PRIMARY KEY (id);
ALTER TABLE public.crm_stages ADD CONSTRAINT crm_stages_pkey PRIMARY KEY (key);
ALTER TABLE public.crm_tasks ADD CONSTRAINT crm_tasks_pkey PRIMARY KEY (id);
ALTER TABLE public.cron_job_seen ADD CONSTRAINT cron_job_seen_pkey PRIMARY KEY (jobid);
ALTER TABLE public.customer_kpi_snapshots ADD CONSTRAINT customer_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.customer_phone_otps ADD CONSTRAINT customer_phone_otps_pkey PRIMARY KEY (id);
ALTER TABLE public.customers ADD CONSTRAINT customers_pkey PRIMARY KEY (id);
ALTER TABLE public.data_owner_registry ADD CONSTRAINT data_owner_registry_pkey PRIMARY KEY (table_name);
ALTER TABLE public.decision_log ADD CONSTRAINT decision_log_pkey PRIMARY KEY (id);
ALTER TABLE public.decision_policy ADD CONSTRAINT decision_policy_pkey PRIMARY KEY (key);
ALTER TABLE public.deploy_state ADD CONSTRAINT deploy_state_pkey PRIMARY KEY (id);
ALTER TABLE public.dept_library ADD CONSTRAINT dept_library_pkey PRIMARY KEY (id);
ALTER TABLE public.doc_backups ADD CONSTRAINT doc_backups_pkey PRIMARY KEY (id);
ALTER TABLE public.doc_reviews ADD CONSTRAINT doc_reviews_pkey PRIMARY KEY (id);
ALTER TABLE public.doc_versions ADD CONSTRAINT doc_versions_pkey PRIMARY KEY (id);
ALTER TABLE public.document_kpi_snapshots ADD CONSTRAINT document_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.documents ADD CONSTRAINT documents_pkey PRIMARY KEY (id);
ALTER TABLE public.dr_restore ADD CONSTRAINT dr_restore_pkey PRIMARY KEY (id);
ALTER TABLE public.dropbox_files ADD CONSTRAINT dropbox_files_pkey PRIMARY KEY (id);
ALTER TABLE public.ea_events ADD CONSTRAINT ea_events_pkey PRIMARY KEY (id);
ALTER TABLE public.ea_meetings ADD CONSTRAINT ea_meetings_pkey PRIMARY KEY (id);
ALTER TABLE public.ea_reminders ADD CONSTRAINT ea_reminders_pkey PRIMARY KEY (id);
ALTER TABLE public.ea_snapshots ADD CONSTRAINT ea_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.email_suppressions ADD CONSTRAINT email_suppressions_pkey PRIMARY KEY (email);
ALTER TABLE public.email_verifications ADD CONSTRAINT email_verifications_pkey PRIMARY KEY (id);
ALTER TABLE public.error_events ADD CONSTRAINT error_events_pkey PRIMARY KEY (id);
ALTER TABLE public.escalations_archive_20260724 ADD CONSTRAINT escalations_archive_20260724_pkey PRIMARY KEY (_pk);
ALTER TABLE public.exec_reports ADD CONSTRAINT exec_reports_pkey PRIMARY KEY (id);
ALTER TABLE public.expense_entries ADD CONSTRAINT expense_entries_pkey PRIMARY KEY (id);
ALTER TABLE public.expenses ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);
ALTER TABLE public.experiment_assignments ADD CONSTRAINT experiment_assignments_pkey PRIMARY KEY (experiment, subject);
ALTER TABLE public.experiment_events ADD CONSTRAINT experiment_events_pkey PRIMARY KEY (id);
ALTER TABLE public.experiments ADD CONSTRAINT experiments_pkey PRIMARY KEY (key);
ALTER TABLE public.fa_assets ADD CONSTRAINT fa_assets_pkey PRIMARY KEY (id);
ALTER TABLE public.fa_depreciation ADD CONSTRAINT fa_depreciation_pkey PRIMARY KEY (id);
ALTER TABLE public.feature_flags ADD CONSTRAINT feature_flags_pkey PRIMARY KEY (key);
ALTER TABLE public.finance_kpi_snapshots ADD CONSTRAINT finance_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.finance_reports ADD CONSTRAINT finance_reports_pkey PRIMARY KEY (id);
ALTER TABLE public.finance_snapshots ADD CONSTRAINT finance_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.founder_alerts ADD CONSTRAINT founder_alerts_pkey PRIMARY KEY (id);
ALTER TABLE public.fraud_flags ADD CONSTRAINT fraud_flags_pkey PRIMARY KEY (kind, subject_type, subject_id);
ALTER TABLE public.gl_accounts ADD CONSTRAINT gl_accounts_pkey PRIMARY KEY (code);
ALTER TABLE public.gl_expense_map ADD CONSTRAINT gl_expense_map_pkey PRIMARY KEY (category);
ALTER TABLE public.gl_journal ADD CONSTRAINT gl_journal_pkey PRIMARY KEY (id);
ALTER TABLE public.gl_journal_lines ADD CONSTRAINT gl_journal_lines_pkey PRIMARY KEY (id);
ALTER TABLE public.gl_settings ADD CONSTRAINT gl_settings_pkey PRIMARY KEY (key);
ALTER TABLE public.graph_edges ADD CONSTRAINT graph_edges_pkey PRIMARY KEY (src_kind, src_ref, rel, dst_kind, dst_ref);
ALTER TABLE public.graph_nodes ADD CONSTRAINT graph_nodes_pkey PRIMARY KEY (kind, ref_id);
ALTER TABLE public.health_checks ADD CONSTRAINT health_checks_pkey PRIMARY KEY (id);
ALTER TABLE public.health_state ADD CONSTRAINT health_state_pkey PRIMARY KEY (id);
ALTER TABLE public.hlm_digest_log ADD CONSTRAINT hlm_digest_log_pkey PRIMARY KEY (id);
ALTER TABLE public.hlm_state ADD CONSTRAINT hlm_state_pkey PRIMARY KEY (key);
ALTER TABLE public.hlm_watchlist ADD CONSTRAINT hlm_watchlist_pkey PRIMARY KEY (addr);
ALTER TABLE public.inbound_messages ADD CONSTRAINT inbound_messages_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiries ADD CONSTRAINT inquiries_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_cancellations ADD CONSTRAINT inquiry_cancellations_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_intake ADD CONSTRAINT inquiry_intake_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_matches ADD CONSTRAINT inquiry_matches_pkey PRIMARY KEY (id);
ALTER TABLE public.inquiry_requirement ADD CONSTRAINT inquiry_requirement_pkey PRIMARY KEY (inquiry_id);
ALTER TABLE public.inv_items ADD CONSTRAINT inv_items_pkey PRIMARY KEY (id);
ALTER TABLE public.inv_stock_moves ADD CONSTRAINT inv_stock_moves_pkey PRIMARY KEY (id);
ALTER TABLE public.invite_schedule ADD CONSTRAINT invite_schedule_pkey PRIMARY KEY (day);
ALTER TABLE public.kb_category_aliases ADD CONSTRAINT kb_category_aliases_pkey PRIMARY KEY (category, maps_to);
ALTER TABLE public.kb_chunks ADD CONSTRAINT kb_chunks_pkey PRIMARY KEY (id);
ALTER TABLE public.kb_revisions ADD CONSTRAINT kb_revisions_pkey PRIMARY KEY (id);
ALTER TABLE public.kb_usage_log ADD CONSTRAINT kb_usage_log_pkey PRIMARY KEY (id);
ALTER TABLE public.knowledge_kpi_snapshots ADD CONSTRAINT knowledge_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.leads ADD CONSTRAINT leads_pkey PRIMARY KEY (id);
ALTER TABLE public.legal_checklist ADD CONSTRAINT legal_checklist_pkey PRIMARY KEY (id);
ALTER TABLE public.legal_documents ADD CONSTRAINT legal_documents_pkey PRIMARY KEY (slug);
ALTER TABLE public.legal_kpi_snapshots ADD CONSTRAINT legal_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.legal_reviews ADD CONSTRAINT legal_reviews_pkey PRIMARY KEY (id);
ALTER TABLE public.llm_calls ADD CONSTRAINT llm_calls_pkey PRIMARY KEY (id);
ALTER TABLE public.llm_policy ADD CONSTRAINT llm_policy_pkey PRIMARY KEY (model);
ALTER TABLE public.market_intel ADD CONSTRAINT market_intel_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_library ADD CONSTRAINT marketing_library_pkey PRIMARY KEY (id);
ALTER TABLE public.marketing_snapshots ADD CONSTRAINT marketing_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.match_eval_runs ADD CONSTRAINT match_eval_runs_pkey PRIMARY KEY (id);
ALTER TABLE public.materials ADD CONSTRAINT materials_pkey PRIMARY KEY (id);
ALTER TABLE public.mdm_brands ADD CONSTRAINT mdm_brands_pkey PRIMARY KEY (id);
ALTER TABLE public.mdm_cities ADD CONSTRAINT mdm_cities_pkey PRIMARY KEY (id);
ALTER TABLE public.mdm_currencies ADD CONSTRAINT mdm_currencies_pkey PRIMARY KEY (code);
ALTER TABLE public.mdm_emirates ADD CONSTRAINT mdm_emirates_pkey PRIMARY KEY (code);
ALTER TABLE public.mdm_manufacturers ADD CONSTRAINT mdm_manufacturers_pkey PRIMARY KEY (id);
ALTER TABLE public.mdm_standards ADD CONSTRAINT mdm_standards_pkey PRIMARY KEY (id);
ALTER TABLE public.mdm_units ADD CONSTRAINT mdm_units_pkey PRIMARY KEY (code);
ALTER TABLE public.memory_promotions ADD CONSTRAINT memory_promotions_pkey PRIMARY KEY (memory_id);
ALTER TABLE public.messages ADD CONSTRAINT messages_pkey PRIMARY KEY (id);
ALTER TABLE public.meta_insights ADD CONSTRAINT meta_insights_pkey PRIMARY KEY (id);
ALTER TABLE public.notifications ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);
ALTER TABLE public.ops_kpi_snapshots ADD CONSTRAINT ops_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.org_action_executor ADD CONSTRAINT org_action_executor_pkey PRIMARY KEY (action_class);
ALTER TABLE public.org_agents ADD CONSTRAINT org_agents_pkey PRIMARY KEY (agent_key);
ALTER TABLE public.org_authority ADD CONSTRAINT org_authority_pkey PRIMARY KEY (dept_key, action_class);
ALTER TABLE public.org_departments ADD CONSTRAINT org_departments_pkey PRIMARY KEY (dept_key);
ALTER TABLE public.org_memory ADD CONSTRAINT org_memory_pkey PRIMARY KEY (id);
ALTER TABLE public.org_objectives ADD CONSTRAINT org_objectives_pkey PRIMARY KEY (id);
ALTER TABLE public.org_onboarding ADD CONSTRAINT org_onboarding_pkey PRIMARY KEY (agent_key);
ALTER TABLE public.org_reset_backup_20260724 ADD CONSTRAINT org_reset_backup_20260724_pkey PRIMARY KEY (_pk);
ALTER TABLE public.org_tasks ADD CONSTRAINT org_tasks_pkey PRIMARY KEY (id);
ALTER TABLE public.os_audit_log ADD CONSTRAINT os_audit_log_pkey PRIMARY KEY (id);
ALTER TABLE public.outreach ADD CONSTRAINT outreach_pkey PRIMARY KEY (id);
ALTER TABLE public.pages ADD CONSTRAINT pages_pkey PRIMARY KEY (slug);
ALTER TABLE public.pdpl_erase_files ADD CONSTRAINT pdpl_erase_files_pkey PRIMARY KEY (id);
ALTER TABLE public.pdpl_requests ADD CONSTRAINT pdpl_requests_pkey PRIMARY KEY (id);
ALTER TABLE public.phone_verifications ADD CONSTRAINT phone_verifications_pkey PRIMARY KEY (id);
ALTER TABLE public.po_lines ADD CONSTRAINT po_lines_pkey PRIMARY KEY (id);
ALTER TABLE public.po_orders ADD CONSTRAINT po_orders_pkey PRIMARY KEY (id);
ALTER TABLE public.po_vendors ADD CONSTRAINT po_vendors_pkey PRIMARY KEY (id);
ALTER TABLE public.policy_rules ADD CONSTRAINT policy_rules_pkey PRIMARY KEY (id);
ALTER TABLE public.pricing_config ADD CONSTRAINT pricing_config_pkey PRIMARY KEY (id);
ALTER TABLE public.projects ADD CONSTRAINT projects_pkey PRIMARY KEY (id);
ALTER TABLE public.prompt_benchmarks ADD CONSTRAINT prompt_benchmarks_pkey PRIMARY KEY (id);
ALTER TABLE public.prompt_eval_runs ADD CONSTRAINT prompt_eval_runs_pkey PRIMARY KEY (id);
ALTER TABLE public.prompt_versions ADD CONSTRAINT prompt_versions_pkey PRIMARY KEY (id);
ALTER TABLE public.prompts ADD CONSTRAINT prompts_pkey PRIMARY KEY (key);
ALTER TABLE public.public_holidays ADD CONSTRAINT public_holidays_pkey PRIMARY KEY (holiday_date);
ALTER TABLE public.qa_results ADD CONSTRAINT qa_results_pkey PRIMARY KEY (id);
ALTER TABLE public.qd_compare_cache ADD CONSTRAINT qd_compare_cache_pkey PRIMARY KEY (inquiry_id, quotes_hash, lang);
ALTER TABLE public.qd_deploy_src ADD CONSTRAINT qd_deploy_src_pkey PRIMARY KEY (path);
ALTER TABLE public.qd_i18n ADD CONSTRAINT qd_i18n_pkey PRIMARY KEY (source, slug);
ALTER TABLE public.qd_i18n_chunks ADD CONSTRAINT qd_i18n_chunks_pkey PRIMARY KEY (source, slug, idx);
ALTER TABLE public.qualification_playbooks ADD CONSTRAINT qualification_playbooks_pkey PRIMARY KEY (id);
ALTER TABLE public.questions ADD CONSTRAINT questions_pkey PRIMARY KEY (id);
ALTER TABLE public.quote_committed_items ADD CONSTRAINT quote_committed_items_pkey PRIMARY KEY (id);
ALTER TABLE public.quote_comparisons ADD CONSTRAINT quote_comparisons_pkey PRIMARY KEY (id);
ALTER TABLE public.quote_items ADD CONSTRAINT quote_items_pkey PRIMARY KEY (id);
ALTER TABLE public.quote_pdf_cache ADD CONSTRAINT quote_pdf_cache_pkey PRIMARY KEY (quote_id, lang);
ALTER TABLE public.quote_requirements ADD CONSTRAINT quote_requirements_pkey PRIMARY KEY (category);
ALTER TABLE public.quote_review_messages ADD CONSTRAINT quote_review_messages_pkey PRIMARY KEY (id);
ALTER TABLE public.quote_reviews ADD CONSTRAINT quote_reviews_pkey PRIMARY KEY (id);
ALTER TABLE public.quotes ADD CONSTRAINT quotes_pkey PRIMARY KEY (id);
ALTER TABLE public.reg_catalog ADD CONSTRAINT reg_catalog_pkey PRIMARY KEY (id);
ALTER TABLE public.regulations ADD CONSTRAINT regulations_pkey PRIMARY KEY (id);
ALTER TABLE public.report_kpi_snapshots ADD CONSTRAINT report_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.retention_policy ADD CONSTRAINT retention_policy_pkey PRIMARY KEY (bucket);
ALTER TABLE public.reveal_invoices ADD CONSTRAINT reveal_invoices_pkey PRIMARY KEY (transaction_id);
ALTER TABLE public.review_queue ADD CONSTRAINT review_queue_pkey PRIMARY KEY (id);
ALTER TABLE public.reviews ADD CONSTRAINT reviews_pkey PRIMARY KEY (id);
ALTER TABLE public.rfq_archives ADD CONSTRAINT rfq_archives_pkey PRIMARY KEY (id);
ALTER TABLE public.rl_hits ADD CONSTRAINT rl_hits_pkey PRIMARY KEY (_pk);
ALTER TABLE public.role_permissions ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role, action);
ALTER TABLE public.roles ADD CONSTRAINT roles_pkey PRIMARY KEY (name);
ALTER TABLE public.scrape_runs ADD CONSTRAINT scrape_runs_pkey PRIMARY KEY (id);
ALTER TABLE public.security_audit_log ADD CONSTRAINT security_audit_log_pkey PRIMARY KEY (id);
ALTER TABLE public.security_events ADD CONSTRAINT security_events_pkey PRIMARY KEY (id);
ALTER TABLE public.security_kpi_snapshots ADD CONSTRAINT security_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.security_selfaudit_snapshots ADD CONSTRAINT security_selfaudit_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.seo_categories ADD CONSTRAINT seo_categories_pkey PRIMARY KEY (slug);
ALTER TABLE public.simulations ADD CONSTRAINT simulations_pkey PRIMARY KEY (id);
ALTER TABLE public.site_publish_state ADD CONSTRAINT site_publish_state_pkey PRIMARY KEY (id);
ALTER TABLE public.social_posts ADD CONSTRAINT social_posts_pkey PRIMARY KEY (id);
ALTER TABLE public.strategy_kpi_snapshots ADD CONSTRAINT strategy_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.strategy_risks ADD CONSTRAINT strategy_risks_pkey PRIMARY KEY (id);
ALTER TABLE public.stripe_events ADD CONSTRAINT stripe_events_pkey PRIMARY KEY (event_id);
ALTER TABLE public.supplier_capabilities ADD CONSTRAINT supplier_capabilities_pkey PRIMARY KEY (supplier_id);
ALTER TABLE public.supplier_capability_confirmation ADD CONSTRAINT supplier_capability_confirmation_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_dues ADD CONSTRAINT supplier_dues_pkey PRIMARY KEY (id);
ALTER TABLE public.supplier_kpi_snapshots ADD CONSTRAINT supplier_kpi_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.supply_health_snapshots ADD CONSTRAINT supply_health_snapshots_pkey PRIMARY KEY (id);
ALTER TABLE public.taxonomy_authority ADD CONSTRAINT taxonomy_authority_pkey PRIMARY KEY (code);
ALTER TABLE public.taxonomy_role ADD CONSTRAINT taxonomy_role_pkey PRIMARY KEY (code);
ALTER TABLE public.taxonomy_trade ADD CONSTRAINT taxonomy_trade_pkey PRIMARY KEY (code);
ALTER TABLE public.templates ADD CONSTRAINT templates_pkey PRIMARY KEY (name);
ALTER TABLE public.transactions ADD CONSTRAINT transactions_pkey PRIMARY KEY (id);
ALTER TABLE public.undo_log ADD CONSTRAINT undo_log_pkey PRIMARY KEY (id);
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_pkey PRIMARY KEY (email, role);
ALTER TABLE public.vt_results ADD CONSTRAINT vt_results_pkey PRIMARY KEY (id);
ALTER TABLE public.wa_messages ADD CONSTRAINT wa_messages_pkey PRIMARY KEY (id);
ALTER TABLE public.yello_staging ADD CONSTRAINT yello_staging_pkey PRIMARY KEY (company_id);
ALTER TABLE public.blog_posts ADD CONSTRAINT blog_posts_slug_key UNIQUE (slug);
ALTER TABLE public.brand_assets ADD CONSTRAINT brand_assets_url_key UNIQUE (url);
ALTER TABLE public.budget_lines ADD CONSTRAINT budget_lines_budget_id_account_code_period_month_key UNIQUE (budget_id, account_code, period_month);
ALTER TABLE public.budgets ADD CONSTRAINT budgets_name_fiscal_year_key UNIQUE (name, fiscal_year);
ALTER TABLE public.canary_records ADD CONSTRAINT canary_records_fingerprint_key UNIQUE (fingerprint);
ALTER TABLE public.category_quote_specs ADD CONSTRAINT category_quote_specs_spec_group_aspect_key UNIQUE (spec_group, aspect);
ALTER TABLE public.crm_lost_reasons ADD CONSTRAINT crm_lost_reasons_label_key UNIQUE (label);
ALTER TABLE public.doc_backups ADD CONSTRAINT doc_backups_bucket_path_key UNIQUE (bucket, path);
ALTER TABLE public.doc_versions ADD CONSTRAINT doc_versions_entity_type_entity_id_version_key UNIQUE (entity_type, entity_id, version);
ALTER TABLE public.documents ADD CONSTRAINT documents_bucket_path_key UNIQUE (bucket, path);
ALTER TABLE public.dropbox_files ADD CONSTRAINT dropbox_files_dropbox_id_key UNIQUE (dropbox_id);
ALTER TABLE public.email_verifications ADD CONSTRAINT email_verifications_token_key UNIQUE (token);
ALTER TABLE public.fa_assets ADD CONSTRAINT fa_assets_asset_no_key UNIQUE (asset_no);
ALTER TABLE public.fa_depreciation ADD CONSTRAINT fa_depreciation_asset_id_period_key UNIQUE (asset_id, period);
ALTER TABLE public.gl_journal ADD CONSTRAINT gl_journal_entry_no_key UNIQUE (entry_no);
ALTER TABLE public.inquiry_matches ADD CONSTRAINT inquiry_matches_inquiry_id_supplier_id_key UNIQUE (inquiry_id, supplier_id);
ALTER TABLE public.inv_items ADD CONSTRAINT inv_items_sku_key UNIQUE (sku);
ALTER TABLE public.kb_revisions ADD CONSTRAINT kb_revisions_entry_kind_entry_ref_version_key UNIQUE (entry_kind, entry_ref, version);
ALTER TABLE public.leads ADD CONSTRAINT leads_place_id_key UNIQUE (place_id);
ALTER TABLE public.legal_checklist ADD CONSTRAINT legal_checklist_requirement_key UNIQUE (requirement);
ALTER TABLE public.mdm_brands ADD CONSTRAINT mdm_brands_name_key UNIQUE (name);
ALTER TABLE public.mdm_cities ADD CONSTRAINT mdm_cities_name_emirate_code_key UNIQUE (name, emirate_code);
ALTER TABLE public.mdm_manufacturers ADD CONSTRAINT mdm_manufacturers_name_key UNIQUE (name);
ALTER TABLE public.mdm_standards ADD CONSTRAINT mdm_standards_code_key UNIQUE (code);
ALTER TABLE public.meta_insights ADD CONSTRAINT meta_insights_campaign_id_time_window_key UNIQUE (campaign_id, time_window);
ALTER TABLE public.po_lines ADD CONSTRAINT po_lines_po_id_line_no_key UNIQUE (po_id, line_no);
ALTER TABLE public.po_orders ADD CONSTRAINT po_orders_po_no_key UNIQUE (po_no);
ALTER TABLE public.prompt_benchmarks ADD CONSTRAINT prompt_benchmarks_prompt_key_name_key UNIQUE (prompt_key, name);
ALTER TABLE public.prompt_versions ADD CONSTRAINT prompt_versions_prompt_key_version_key UNIQUE (prompt_key, version);
ALTER TABLE public.qualification_playbooks ADD CONSTRAINT qualification_playbooks_category_version_key UNIQUE (category, version);
ALTER TABLE public.quote_reviews ADD CONSTRAINT quote_reviews_inquiry_id_supplier_id_key UNIQUE (inquiry_id, supplier_id);
ALTER TABLE public.quotes ADD CONSTRAINT quotes_inquiry_id_supplier_id_key UNIQUE (inquiry_id, supplier_id);
ALTER TABLE public.reg_catalog ADD CONSTRAINT reg_catalog_authority_code_name_key UNIQUE (authority, code_name);
ALTER TABLE public.reviews ADD CONSTRAINT reviews_transaction_id_key UNIQUE (transaction_id);
ALTER TABLE public.rfq_archives ADD CONSTRAINT rfq_archives_rfq_id_key UNIQUE (rfq_id);
ALTER TABLE public.strategy_risks ADD CONSTRAINT strategy_risks_category_title_key UNIQUE (category, title);
ALTER TABLE public.supplier_dues ADD CONSTRAINT supplier_dues_transaction_id_key UNIQUE (transaction_id);
ALTER TABLE public.vt_results ADD CONSTRAINT vt_results_path_key UNIQUE (path);
ALTER TABLE public.agent_chats ADD CONSTRAINT agent_chats_role_check CHECK ((role = ANY (ARRAY['user'::text, 'assistant'::text])));
ALTER TABLE public.agent_knowledge ADD CONSTRAINT agent_knowledge_layer_check CHECK ((layer = ANY (ARRAY['company'::text, 'profession'::text, 'state'::text, 'experience'::text])));
ALTER TABLE public.ap_bills ADD CONSTRAINT ap_bills_status_check CHECK ((status = ANY (ARRAY['open'::text, 'partial'::text, 'paid'::text, 'void'::text])));
ALTER TABLE public.budgets ADD CONSTRAINT budgets_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'closed'::text])));
ALTER TABLE public.canon_eval_questions ADD CONSTRAINT canon_eval_questions_layer_check CHECK ((layer = ANY (ARRAY['company'::text, 'profession'::text, 'state'::text, 'experience'::text])));
ALTER TABLE public.company_vision ADD CONSTRAINT company_vision_singleton CHECK ((id = 1));
ALTER TABLE public.crm_stages ADD CONSTRAINT crm_stages_probability_check CHECK (((probability >= 0) AND (probability <= 100)));
ALTER TABLE public.customers ADD CONSTRAINT customers_locale_chk CHECK ((locale = ANY (ARRAY['en'::text, 'ar'::text]))) NOT VALID;
ALTER TABLE public.fa_assets ADD CONSTRAINT fa_assets_status_check CHECK ((status = ANY (ARRAY['active'::text, 'fully_depreciated'::text, 'disposed'::text])));
ALTER TABLE public.fa_assets ADD CONSTRAINT fa_assets_cost_check CHECK ((cost >= (0)::numeric));
ALTER TABLE public.fa_assets ADD CONSTRAINT fa_assets_useful_life_months_check CHECK ((useful_life_months > 0));
ALTER TABLE public.fa_assets ADD CONSTRAINT fa_assets_method_check CHECK ((method = 'straight_line'::text));
ALTER TABLE public.gl_accounts ADD CONSTRAINT gl_accounts_normal_balance_check CHECK ((normal_balance = ANY (ARRAY['D'::bpchar, 'C'::bpchar])));
ALTER TABLE public.gl_accounts ADD CONSTRAINT gl_accounts_type_check CHECK ((type = ANY (ARRAY['asset'::text, 'liability'::text, 'equity'::text, 'revenue'::text, 'expense'::text])));
ALTER TABLE public.gl_journal ADD CONSTRAINT gl_journal_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'posted'::text, 'void'::text])));
ALTER TABLE public.gl_journal_lines ADD CONSTRAINT gl_journal_lines_debit_check CHECK ((debit >= (0)::numeric));
ALTER TABLE public.gl_journal_lines ADD CONSTRAINT gl_journal_lines_credit_check CHECK ((credit >= (0)::numeric));
ALTER TABLE public.gl_journal_lines ADD CONSTRAINT gl_line_one_side CHECK (((debit = (0)::numeric) <> (credit = (0)::numeric)));
ALTER TABLE public.inv_stock_moves ADD CONSTRAINT inv_stock_moves_move_type_check CHECK ((move_type = ANY (ARRAY['in'::text, 'out'::text, 'adjust'::text])));
ALTER TABLE public.leads ADD CONSTRAINT leads_locale_chk CHECK ((locale = ANY (ARRAY['en'::text, 'ar'::text]))) NOT VALID;
ALTER TABLE public.market_intel ADD CONSTRAINT market_intel_impact_check CHECK ((impact = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text])));
ALTER TABLE public.market_intel ADD CONSTRAINT market_intel_status_check CHECK ((status = ANY (ARRAY['open'::text, 'reviewed'::text, 'actioned'::text, 'dismissed'::text])));
ALTER TABLE public.market_intel ADD CONSTRAINT market_intel_kind_check CHECK ((kind = ANY (ARRAY['competitor'::text, 'trend'::text, 'expansion'::text, 'regulatory'::text, 'other'::text])));
ALTER TABLE public.messages ADD CONSTRAINT messages_sender_check CHECK ((sender = ANY (ARRAY['customer'::text, 'supplier'::text])));
ALTER TABLE public.org_action_executor ADD CONSTRAINT org_action_executor_kind_check CHECK ((kind = ANY (ARRAY['rpc'::text, 'edge'::text])));
ALTER TABLE public.org_authority ADD CONSTRAINT org_authority_max_tier_check CHECK ((max_tier = ANY (ARRAY['advisory'::text, 'gated'::text, 'supervised'::text, 'autonomous'::text])));
ALTER TABLE public.org_objectives ADD CONSTRAINT org_objectives_status_check CHECK ((status = ANY (ARRAY['open'::text, 'in_progress'::text, 'blocked'::text, 'done'::text, 'cancelled'::text])));
ALTER TABLE public.org_onboarding ADD CONSTRAINT org_onboarding_status_check CHECK ((status = ANY (ARRAY['onboarding'::text, 'probation'::text, 'certified'::text, 'recert_due'::text])));
ALTER TABLE public.org_tasks ADD CONSTRAINT org_tasks_tier_check CHECK ((tier = ANY (ARRAY['advisory'::text, 'gated'::text, 'supervised'::text, 'autonomous'::text])));
ALTER TABLE public.org_tasks ADD CONSTRAINT org_tasks_status_check CHECK ((status = ANY (ARRAY['proposed'::text, 'assigned'::text, 'in_progress'::text, 'blocked'::text, 'done'::text, 'failed'::text, 'escalated'::text])));
ALTER TABLE public.pdpl_requests ADD CONSTRAINT pdpl_requests_kind_check CHECK ((kind = ANY (ARRAY['export'::text, 'delete'::text])));
ALTER TABLE public.po_lines ADD CONSTRAINT po_lines_qty_check CHECK ((qty > (0)::numeric));
ALTER TABLE public.po_orders ADD CONSTRAINT po_orders_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'partial'::text, 'received'::text, 'billed'::text, 'closed'::text, 'cancelled'::text])));
ALTER TABLE public.pricing_config ADD CONSTRAINT pricing_config_singleton CHECK ((id = 1));
ALTER TABLE public.quotes ADD CONSTRAINT quotes_quote_amount_check CHECK ((quote_amount > (0)::numeric));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_r_communication_check CHECK (((r_communication >= 1) AND (r_communication <= 5)));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_r_quality_check CHECK (((r_quality >= 1) AND (r_quality <= 5)));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_rating_check CHECK (((rating >= 1) AND (rating <= 5)));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_r_compliance_check CHECK (((r_compliance >= 1) AND (r_compliance <= 5)));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_r_punctuality_check CHECK (((r_punctuality >= 1) AND (r_punctuality <= 5)));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_r_after_sales_check CHECK (((r_after_sales >= 1) AND (r_after_sales <= 5)));
ALTER TABLE public.reviews ADD CONSTRAINT reviews_r_documentation_check CHECK (((r_documentation >= 1) AND (r_documentation <= 5)));
ALTER TABLE public.strategy_risks ADD CONSTRAINT strategy_risks_likelihood_check CHECK (((likelihood >= 1) AND (likelihood <= 5)));
ALTER TABLE public.strategy_risks ADD CONSTRAINT strategy_risks_status_check CHECK ((status = ANY (ARRAY['open'::text, 'mitigating'::text, 'accepted'::text, 'closed'::text])));
ALTER TABLE public.strategy_risks ADD CONSTRAINT strategy_risks_impact_check CHECK (((impact >= 1) AND (impact <= 5)));
ALTER TABLE public.ap_bills ADD CONSTRAINT ap_bills_gl_journal_id_fkey FOREIGN KEY (gl_journal_id) REFERENCES gl_journal(id);
ALTER TABLE public.ap_bills ADD CONSTRAINT ap_bills_pay_journal_id_fkey FOREIGN KEY (pay_journal_id) REFERENCES gl_journal(id);
ALTER TABLE public.ap_bills ADD CONSTRAINT ap_bills_po_id_fkey FOREIGN KEY (po_id) REFERENCES po_orders(id);
ALTER TABLE public.ap_bills ADD CONSTRAINT ap_bills_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES po_vendors(id);
ALTER TABLE public.budget_lines ADD CONSTRAINT budget_lines_budget_id_fkey FOREIGN KEY (budget_id) REFERENCES budgets(id) ON DELETE CASCADE;
ALTER TABLE public.budget_lines ADD CONSTRAINT budget_lines_account_code_fkey FOREIGN KEY (account_code) REFERENCES gl_accounts(code);
ALTER TABLE public.customer_phone_otps ADD CONSTRAINT customer_phone_otps_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE;
ALTER TABLE public.doc_reviews ADD CONSTRAINT doc_reviews_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id);
ALTER TABLE public.experiment_assignments ADD CONSTRAINT experiment_assignments_experiment_fkey FOREIGN KEY (experiment) REFERENCES experiments(key);
ALTER TABLE public.fa_assets ADD CONSTRAINT fa_assets_asset_account_fkey FOREIGN KEY (asset_account) REFERENCES gl_accounts(code);
ALTER TABLE public.fa_assets ADD CONSTRAINT fa_assets_expense_account_fkey FOREIGN KEY (expense_account) REFERENCES gl_accounts(code);
ALTER TABLE public.fa_assets ADD CONSTRAINT fa_assets_accum_account_fkey FOREIGN KEY (accum_account) REFERENCES gl_accounts(code);
ALTER TABLE public.fa_depreciation ADD CONSTRAINT fa_depreciation_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES fa_assets(id) ON DELETE CASCADE;
ALTER TABLE public.fa_depreciation ADD CONSTRAINT fa_depreciation_gl_journal_id_fkey FOREIGN KEY (gl_journal_id) REFERENCES gl_journal(id);
ALTER TABLE public.gl_accounts ADD CONSTRAINT gl_accounts_parent_code_fkey FOREIGN KEY (parent_code) REFERENCES gl_accounts(code);
ALTER TABLE public.gl_expense_map ADD CONSTRAINT gl_expense_map_account_code_fkey FOREIGN KEY (account_code) REFERENCES gl_accounts(code);
ALTER TABLE public.gl_journal ADD CONSTRAINT gl_journal_reverses_fkey FOREIGN KEY (reverses) REFERENCES gl_journal(id);
ALTER TABLE public.gl_journal_lines ADD CONSTRAINT gl_journal_lines_account_code_fkey FOREIGN KEY (account_code) REFERENCES gl_accounts(code);
ALTER TABLE public.gl_journal_lines ADD CONSTRAINT gl_journal_lines_journal_id_fkey FOREIGN KEY (journal_id) REFERENCES gl_journal(id) ON DELETE CASCADE;
ALTER TABLE public.inbound_messages ADD CONSTRAINT inbound_messages_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES leads(id);
ALTER TABLE public.inquiries ADD CONSTRAINT inquiries_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL;
ALTER TABLE public.inquiries ADD CONSTRAINT inquiries_parent_inquiry_id_fkey FOREIGN KEY (parent_inquiry_id) REFERENCES inquiries(id);
ALTER TABLE public.inquiries ADD CONSTRAINT inquiries_hired_supplier_id_fkey FOREIGN KEY (hired_supplier_id) REFERENCES leads(id);
ALTER TABLE public.inquiries ADD CONSTRAINT inquiries_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE public.inquiry_matches ADD CONSTRAINT inquiry_matches_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id);
ALTER TABLE public.inquiry_matches ADD CONSTRAINT inquiry_matches_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.inquiry_requirement ADD CONSTRAINT inquiry_requirement_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.inv_items ADD CONSTRAINT inv_items_inventory_account_fkey FOREIGN KEY (inventory_account) REFERENCES gl_accounts(code);
ALTER TABLE public.inv_items ADD CONSTRAINT inv_items_cogs_account_fkey FOREIGN KEY (cogs_account) REFERENCES gl_accounts(code);
ALTER TABLE public.inv_stock_moves ADD CONSTRAINT inv_stock_moves_gl_journal_id_fkey FOREIGN KEY (gl_journal_id) REFERENCES gl_journal(id);
ALTER TABLE public.inv_stock_moves ADD CONSTRAINT inv_stock_moves_item_id_fkey FOREIGN KEY (item_id) REFERENCES inv_items(id);
ALTER TABLE public.mdm_cities ADD CONSTRAINT mdm_cities_emirate_code_fkey FOREIGN KEY (emirate_code) REFERENCES mdm_emirates(code);
ALTER TABLE public.messages ADD CONSTRAINT messages_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE public.messages ADD CONSTRAINT messages_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.messages ADD CONSTRAINT messages_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.org_agents ADD CONSTRAINT org_agents_department_fkey FOREIGN KEY (department) REFERENCES org_departments(dept_key);
ALTER TABLE public.org_authority ADD CONSTRAINT org_authority_dept_key_fkey FOREIGN KEY (dept_key) REFERENCES org_departments(dept_key) ON DELETE CASCADE;
ALTER TABLE public.org_tasks ADD CONSTRAINT org_tasks_dept_key_fkey FOREIGN KEY (dept_key) REFERENCES org_departments(dept_key);
ALTER TABLE public.org_tasks ADD CONSTRAINT org_tasks_objective_id_fkey FOREIGN KEY (objective_id) REFERENCES org_objectives(id) ON DELETE CASCADE;
ALTER TABLE public.pdpl_erase_files ADD CONSTRAINT pdpl_erase_files_request_id_fkey FOREIGN KEY (request_id) REFERENCES pdpl_requests(id) ON DELETE CASCADE;
ALTER TABLE public.po_lines ADD CONSTRAINT po_lines_account_code_fkey FOREIGN KEY (account_code) REFERENCES gl_accounts(code);
ALTER TABLE public.po_lines ADD CONSTRAINT po_lines_po_id_fkey FOREIGN KEY (po_id) REFERENCES po_orders(id) ON DELETE CASCADE;
ALTER TABLE public.po_lines ADD CONSTRAINT po_lines_item_id_fkey FOREIGN KEY (item_id) REFERENCES inv_items(id);
ALTER TABLE public.po_orders ADD CONSTRAINT po_orders_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES po_vendors(id);
ALTER TABLE public.projects ADD CONSTRAINT projects_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE;
ALTER TABLE public.prompt_versions ADD CONSTRAINT prompt_versions_prompt_key_fkey FOREIGN KEY (prompt_key) REFERENCES prompts(key);
ALTER TABLE public.questions ADD CONSTRAINT questions_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
ALTER TABLE public.questions ADD CONSTRAINT questions_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.questions ADD CONSTRAINT questions_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.quote_committed_items ADD CONSTRAINT quote_committed_items_review_id_fkey FOREIGN KEY (review_id) REFERENCES quote_reviews(id) ON DELETE CASCADE;
ALTER TABLE public.quote_review_messages ADD CONSTRAINT quote_review_messages_review_id_fkey FOREIGN KEY (review_id) REFERENCES quote_reviews(id) ON DELETE CASCADE;
ALTER TABLE public.quotes ADD CONSTRAINT quotes_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id);
ALTER TABLE public.quotes ADD CONSTRAINT quotes_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id) ON DELETE CASCADE;
ALTER TABLE public.regulations ADD CONSTRAINT regulations_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES regulations(id);
ALTER TABLE public.reveal_invoices ADD CONSTRAINT reveal_invoices_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE;
ALTER TABLE public.reviews ADD CONSTRAINT reviews_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id);
ALTER TABLE public.reviews ADD CONSTRAINT reviews_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE public.reviews ADD CONSTRAINT reviews_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id);
ALTER TABLE public.reviews ADD CONSTRAINT reviews_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES transactions(id);
ALTER TABLE public.role_permissions ADD CONSTRAINT role_permissions_role_fkey FOREIGN KEY (role) REFERENCES roles(name);
ALTER TABLE public.supplier_capabilities ADD CONSTRAINT supplier_capabilities_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id) ON DELETE CASCADE;
ALTER TABLE public.transactions ADD CONSTRAINT transactions_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE public.transactions ADD CONSTRAINT transactions_quote_id_fkey FOREIGN KEY (quote_id) REFERENCES quotes(id);
ALTER TABLE public.transactions ADD CONSTRAINT transactions_inquiry_id_fkey FOREIGN KEY (inquiry_id) REFERENCES inquiries(id);
ALTER TABLE public.transactions ADD CONSTRAINT transactions_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES leads(id);
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_role_fkey FOREIGN KEY (role) REFERENCES roles(name);

-- ===== INDEXES =====
CREATE INDEX agent_action_log_created_idx ON public.agent_action_log USING btree (created_at DESC);
CREATE UNIQUE INDEX agent_actions_dedupe ON public.agent_actions USING btree (agent, kind, target_id) WHERE (status = 'pending'::text);
CREATE INDEX agent_actions_status_idx ON public.agent_actions USING btree (status, created_at DESC);
CREATE INDEX agent_chats_agent_idx ON public.agent_chats USING btree (agent_key, id);
CREATE UNIQUE INDEX ai_trainer_snap_day ON public.ai_trainer_snapshots USING btree (snapshot_date);
CREATE INDEX ai_usage_email_time_idx ON public.ai_usage USING btree (email, created_at);
CREATE INDEX content_drafts_status_idx ON public.content_drafts USING btree (status, id DESC);
CREATE INDEX cpo_cust_idx ON public.customer_phone_otps USING btree (customer_id, created_at DESC);
CREATE UNIQUE INDEX customer_kpi_snap_day ON public.customer_kpi_snapshots USING btree (snapshot_date);
CREATE INDEX doc_reviews_status_idx ON public.doc_reviews USING btree (status, created_at DESC);
CREATE UNIQUE INDEX document_kpi_snap_day ON public.document_kpi_snapshots USING btree (snapshot_date);
CREATE INDEX dropbox_files_path ON public.dropbox_files USING btree (path);
CREATE INDEX ea_events_start ON public.ea_events USING btree (starts_at);
CREATE INDEX ea_reminders_at ON public.ea_reminders USING btree (remind_at) WHERE (NOT done);
CREATE UNIQUE INDEX ea_snap_day ON public.ea_snapshots USING btree (snapshot_date);
CREATE INDEX email_verifications_lookup_idx ON public.email_verifications USING btree (email, purpose, used_at, created_at DESC);
CREATE INDEX exec_reports_officer ON public.exec_reports USING btree (officer, created_at DESC);
CREATE INDEX expenses_next_due_idx ON public.expenses USING btree (next_due) WHERE active;
CREATE UNIQUE INDEX finance_kpi_snap_day ON public.finance_kpi_snapshots USING btree (snapshot_date);
CREATE INDEX graph_edges_dst ON public.graph_edges USING btree (dst_kind, dst_ref, rel);
CREATE INDEX graph_edges_rel ON public.graph_edges USING btree (rel);
CREATE INDEX idx_agent_knowledge_key ON public.agent_knowledge USING btree (agent_key);
CREATE INDEX idx_agent_memory_key ON public.agent_memory USING btree (agent_key, created_at DESC);
CREATE INDEX idx_ap_bills_status ON public.ap_bills USING btree (status);
CREATE INDEX idx_ap_bills_vendor ON public.ap_bills USING btree (vendor_id);
CREATE INDEX idx_budget_lines_budget ON public.budget_lines USING btree (budget_id);
CREATE INDEX idx_crm_activities_entity ON public.crm_activities USING btree (entity, entity_id, created_at DESC);
CREATE INDEX idx_crm_activities_tasks ON public.crm_activities USING btree (type, done, due_at) WHERE (type = 'task'::text);
CREATE INDEX idx_crm_notes_entity ON public.crm_notes USING btree (entity, entity_id, created_at DESC);
CREATE INDEX idx_crm_tasks_status ON public.crm_tasks USING btree (status, created_at DESC);
CREATE INDEX idx_declog ON public.decision_log USING btree (kind, created_at DESC);
CREATE INDEX idx_dept_library_dept ON public.dept_library USING btree (department);
CREATE INDEX idx_dept_library_tsv ON public.dept_library USING gin (tsv);
CREATE INDEX idx_doc_reviews_lead_id ON public.doc_reviews USING btree (lead_id);
CREATE INDEX idx_documents_status ON public.documents USING btree (status) WHERE (status = 'pending'::text);
CREATE INDEX idx_docver_entity ON public.doc_versions USING btree (entity_type, entity_id, version DESC);
CREATE INDEX idx_email_verif_email ON public.email_verifications USING btree (email);
CREATE INDEX idx_email_verif_token ON public.email_verifications USING btree (token);
CREATE INDEX idx_error_events_created ON public.error_events USING btree (created_at DESC);
CREATE INDEX idx_gl_journal_date ON public.gl_journal USING btree (entry_date);
CREATE INDEX idx_gl_journal_source ON public.gl_journal USING btree (source, source_ref);
CREATE INDEX idx_gl_journal_status ON public.gl_journal USING btree (status);
CREATE INDEX idx_gl_lines_account ON public.gl_journal_lines USING btree (account_code);
CREATE INDEX idx_gl_lines_journal ON public.gl_journal_lines USING btree (journal_id);
CREATE INDEX idx_im_inquiry ON public.inquiry_matches USING btree (inquiry_id);
CREATE INDEX idx_inbound_messages_lead_id ON public.inbound_messages USING btree (lead_id);
CREATE INDEX idx_inq_category ON public.inquiries USING btree (category);
CREATE INDEX idx_inq_status ON public.inquiries USING btree (status);
CREATE INDEX idx_inqreq_trades ON public.inquiry_requirement USING gin (trades_required);
CREATE INDEX idx_inquiries_customer_id ON public.inquiries USING btree (customer_id);
CREATE INDEX idx_inquiries_hired_supplier_id ON public.inquiries USING btree (hired_supplier_id);
CREATE INDEX idx_inquiry_matches_supplier_id ON public.inquiry_matches USING btree (supplier_id);
CREATE INDEX idx_inv_moves_item ON public.inv_stock_moves USING btree (item_id);
CREATE INDEX idx_kbrev ON public.kb_revisions USING btree (entry_kind, entry_ref, version DESC);
CREATE INDEX idx_leads_approval ON public.leads USING btree (approval_status);
CREATE INDEX idx_leads_claimedby ON public.leads USING btree (lower(claimed_by));
CREATE INDEX idx_leads_embedding_gte ON public.leads USING hnsw (embedding_gte vector_cosine_ops);
CREATE INDEX idx_leads_invite_trades ON public.leads USING gin (invite_trades);
CREATE INDEX idx_marketing_library_category ON public.marketing_library USING btree (category);
CREATE INDEX idx_marketing_library_tsv ON public.marketing_library USING gin (tsv);
CREATE INDEX idx_mdm_cities_emirate_code ON public.mdm_cities USING btree (emirate_code);
CREATE INDEX idx_messages_customer_id ON public.messages USING btree (customer_id);
CREATE INDEX idx_messages_supplier_id ON public.messages USING btree (supplier_id);
CREATE INDEX idx_msg_inquiry ON public.messages USING btree (inquiry_id);
CREATE INDEX idx_notif_inquiry ON public.notifications USING btree (inquiry_id);
CREATE INDEX idx_notif_lead ON public.notifications USING btree (lead_id);
CREATE INDEX idx_notif_type ON public.notifications USING btree (type);
CREATE INDEX idx_org_agents_department ON public.org_agents USING btree (department);
CREATE INDEX idx_os_audit_action ON public.os_audit_log USING btree (action);
CREATE INDEX idx_os_audit_actor ON public.os_audit_log USING btree (actor);
CREATE INDEX idx_os_audit_at ON public.os_audit_log USING btree (at DESC);
CREATE INDEX idx_pdpl_erase_files_req ON public.pdpl_erase_files USING btree (request_id, status);
CREATE INDEX idx_phone_verif_phone ON public.phone_verifications USING btree (phone);
CREATE INDEX idx_po_lines_po ON public.po_lines USING btree (po_id);
CREATE INDEX idx_q_inquiry ON public.quotes USING btree (inquiry_id);
CREATE INDEX idx_q_status ON public.quotes USING btree (status);
CREATE INDEX idx_qcitems_review ON public.quote_committed_items USING btree (review_id, seq);
CREATE INDEX idx_qreviews_sup ON public.quote_reviews USING btree (supplier_id);
CREATE INDEX idx_qrmsg_review ON public.quote_review_messages USING btree (review_id, created_at);
CREATE INDEX idx_questions_customer_id ON public.questions USING btree (customer_id);
CREATE INDEX idx_quote_items_quote ON public.quote_items USING btree (quote_id);
CREATE INDEX idx_quote_pdf_cache_cust_time ON public.quote_pdf_cache USING btree (customer_id, created_at);
CREATE INDEX idx_quotes_supplier_id ON public.quotes USING btree (supplier_id);
CREATE INDEX idx_reviews_customer_id ON public.reviews USING btree (customer_id);
CREATE INDEX idx_reviews_inquiry_id ON public.reviews USING btree (inquiry_id);
CREATE INDEX idx_reviews_supplier_id ON public.reviews USING btree (supplier_id);
CREATE INDEX idx_rfq_arch_cat ON public.rfq_archives USING btree (category);
CREATE INDEX idx_rfq_arch_customer ON public.rfq_archives USING btree (customer_id);
CREATE INDEX idx_supcap_emirates ON public.supplier_capabilities USING gin (coverage_emirates);
CREATE INDEX idx_supcap_excluded ON public.supplier_capabilities USING gin (excluded_trades);
CREATE INDEX idx_supcap_exclusions ON public.supplier_capabilities USING gin (exclusions);
CREATE INDEX idx_supcap_products ON public.supplier_capabilities USING gin (products_norm);
CREATE INDEX idx_supcap_roles ON public.supplier_capabilities USING gin (roles);
CREATE INDEX idx_supcap_trades ON public.supplier_capabilities USING gin (trades);
CREATE INDEX idx_supcapconf_supplier ON public.supplier_capability_confirmation USING btree (supplier_id, version DESC);
CREATE INDEX idx_taxonomy_role_aliases ON public.taxonomy_role USING gin (aliases);
CREATE INDEX idx_taxonomy_trade_aliases ON public.taxonomy_trade USING gin (aliases);
CREATE INDEX idx_transactions_customer_id ON public.transactions USING btree (customer_id);
CREATE INDEX idx_transactions_inquiry_id ON public.transactions USING btree (inquiry_id);
CREATE INDEX idx_transactions_quote_id ON public.transactions USING btree (quote_id);
CREATE INDEX idx_transactions_supplier_id ON public.transactions USING btree (supplier_id);
CREATE INDEX idx_user_roles_role ON public.user_roles USING btree (role);
CREATE INDEX inquiries_project ON public.inquiries USING btree (project_id);
CREATE INDEX inquiry_intake_customer_idx ON public.inquiry_intake USING btree (customer_id);
CREATE INDEX inquiry_intake_email_idx ON public.inquiry_intake USING btree (email);
CREATE INDEX inquiry_intake_status_idx ON public.inquiry_intake USING btree (status);
CREATE INDEX ix_ap_bills_gl_journal_id ON public.ap_bills USING btree (gl_journal_id);
CREATE INDEX ix_ap_bills_pay_journal_id ON public.ap_bills USING btree (pay_journal_id);
CREATE INDEX ix_ap_bills_po_id ON public.ap_bills USING btree (po_id);
CREATE INDEX ix_budget_lines_account_code ON public.budget_lines USING btree (account_code);
CREATE INDEX ix_doc_backups_status ON public.doc_backups USING btree (status) WHERE (status = ANY (ARRAY['pending'::text, 'error'::text]));
CREATE INDEX ix_fa_assets_accum_account ON public.fa_assets USING btree (accum_account);
CREATE INDEX ix_fa_assets_asset_account ON public.fa_assets USING btree (asset_account);
CREATE INDEX ix_fa_assets_expense_account ON public.fa_assets USING btree (expense_account);
CREATE INDEX ix_fa_depreciation_gl_journal_id ON public.fa_depreciation USING btree (gl_journal_id);
CREATE INDEX ix_gl_accounts_parent_code ON public.gl_accounts USING btree (parent_code);
CREATE INDEX ix_gl_expense_map_account_code ON public.gl_expense_map USING btree (account_code);
CREATE INDEX ix_gl_journal_reverses ON public.gl_journal USING btree (reverses);
CREATE INDEX ix_inqcancel_cust ON public.inquiry_cancellations USING btree (customer_id, created_at DESC);
CREATE INDEX ix_inquiries_parent_inquiry ON public.inquiries USING btree (parent_inquiry_id);
CREATE INDEX ix_inv_items_cogs_account ON public.inv_items USING btree (cogs_account);
CREATE INDEX ix_inv_items_inventory_account ON public.inv_items USING btree (inventory_account);
CREATE INDEX ix_inv_stock_moves_gl_journal_id ON public.inv_stock_moves USING btree (gl_journal_id);
CREATE INDEX ix_org_memory_scope ON public.org_memory USING btree (scope) WHERE active;
CREATE INDEX ix_org_tasks_dept_status ON public.org_tasks USING btree (dept_key, status);
CREATE INDEX ix_org_tasks_objective ON public.org_tasks USING btree (objective_id);
CREATE INDEX ix_po_lines_account_code ON public.po_lines USING btree (account_code);
CREATE INDEX ix_po_lines_item_id ON public.po_lines USING btree (item_id);
CREATE INDEX ix_po_orders_vendor_id ON public.po_orders USING btree (vendor_id);
CREATE INDEX ix_quote_comparisons_inq ON public.quote_comparisons USING btree (inquiry_id, created_at DESC);
CREATE INDEX ix_regulations_supersedes_id ON public.regulations USING btree (supersedes_id);
CREATE INDEX ix_sec_audit_at ON public.security_audit_log USING btree (at DESC);
CREATE INDEX ix_sec_audit_tbl ON public.security_audit_log USING btree (table_name, at DESC);
CREATE INDEX kb_chunks_cat ON public.kb_chunks USING btree (category);
CREATE INDEX kb_chunks_category_norm_idx ON public.kb_chunks USING btree (category_norm);
CREATE INDEX kb_chunks_emb_hnsw ON public.kb_chunks USING hnsw (embedding_gte vector_cosine_ops);
CREATE INDEX kb_chunks_fts ON public.kb_chunks USING gin (fts);
CREATE INDEX kb_usage_log_created ON public.kb_usage_log USING btree (created_at);
CREATE UNIQUE INDEX knowledge_kpi_snap_day ON public.knowledge_kpi_snapshots USING btree (snapshot_date);
CREATE UNIQUE INDEX leads_claim_token_key ON public.leads USING btree (claim_token);
CREATE INDEX leads_claimed_by_idx ON public.leads USING btree (claimed_by);
CREATE INDEX leads_email_idx ON public.leads USING btree (email);
CREATE INDEX leads_embedding_idx ON public.leads USING hnsw (embedding vector_cosine_ops);
CREATE INDEX leads_emirate_idx ON public.leads USING btree (emirate);
CREATE UNIQUE INDEX leads_founding_rank_uidx ON public.leads USING btree (founding_rank) WHERE (founding_rank IS NOT NULL);
CREATE INDEX leads_has_email_idx ON public.leads USING btree (((email IS NOT NULL)));
CREATE INDEX leads_invite_status_idx ON public.leads USING btree (invite_status);
CREATE UNIQUE INDEX leads_place_id_uidx ON public.leads USING btree (place_id) WHERE (place_id IS NOT NULL);
CREATE INDEX leads_sector_idx ON public.leads USING btree (sector);
CREATE UNIQUE INDEX legal_kpi_snap_day ON public.legal_kpi_snapshots USING btree (snapshot_date);
CREATE INDEX llm_calls_created_idx ON public.llm_calls USING btree (created_at DESC);
CREATE INDEX llm_calls_fn_idx ON public.llm_calls USING btree (fn, created_at DESC);
CREATE UNIQUE INDEX marketing_snap_day ON public.marketing_snapshots USING btree (snapshot_date);
CREATE INDEX materials_cat ON public.materials USING btree (category);
CREATE INDEX messages_thread_idx ON public.messages USING btree (inquiry_id, supplier_id, created_at);
CREATE INDEX notifications_status_idx ON public.notifications USING btree (status, created_at);
CREATE UNIQUE INDEX ops_kpi_snap_day ON public.ops_kpi_snapshots USING btree (snapshot_date);
CREATE UNIQUE INDEX outreach_lead_uq ON public.outreach USING btree (lead_id) WHERE (lead_id IS NOT NULL);
CREATE INDEX outreach_status_idx ON public.outreach USING btree (status, id DESC);
CREATE INDEX projects_customer ON public.projects USING btree (customer_id);
CREATE INDEX q_inq_sup_idx ON public.questions USING btree (inquiry_id, supplier_id);
CREATE INDEX q_sup_idx ON public.questions USING btree (supplier_id, answered_at);
CREATE INDEX regulations_cats ON public.regulations USING gin (categories);
CREATE INDEX rl_hits_k_at ON public.rl_hits USING btree (k, at);
CREATE INDEX security_events_idx ON public.security_events USING btree (created_at DESC);
CREATE UNIQUE INDEX security_kpi_snap_day ON public.security_kpi_snapshots USING btree (snapshot_date);
CREATE UNIQUE INDEX supplier_dues_stripe_session_key ON public.supplier_dues USING btree (stripe_session_id) WHERE (stripe_session_id IS NOT NULL);
CREATE UNIQUE INDEX supplier_kpi_snap_day ON public.supplier_kpi_snapshots USING btree (snapshot_date);
CREATE INDEX undo_log_created_idx ON public.undo_log USING btree (created_at DESC);
CREATE UNIQUE INDEX uq_company_faq_q ON public.company_faq USING btree (question);
CREATE UNIQUE INDEX uq_doc_backups_dedupe ON public.doc_backups USING btree (dedupe_key);
CREATE UNIQUE INDEX uq_leads_email_lower ON public.leads USING btree (lower(email)) WHERE ((email IS NOT NULL) AND (email <> ''::text));
CREATE INDEX yello_email_idx ON public.yello_staging USING btree (email);

-- ===== VIEWS =====
CREATE OR REPLACE VIEW public.ai_agent_quality AS  WITH runs AS (
         SELECT agent_runs.agent,
            count(*) AS runs_30d,
            count(*) FILTER (WHERE (agent_runs.status = ANY (ARRAY['error'::text, 'failed'::text]))) AS errors
           FROM agent_runs
          WHERE (agent_runs.started_at >= (now() - '30 days'::interval))
          GROUP BY agent_runs.agent
        ), acts AS (
         SELECT agent_actions.agent,
            count(*) AS actions_30d,
            count(*) FILTER (WHERE (agent_actions.status = ANY (ARRAY['pending'::text, 'needs_review'::text]))) AS open_escalations,
            count(*) FILTER (WHERE (agent_actions.status = 'rejected'::text)) AS rejected,
            count(*) FILTER (WHERE (agent_actions.status = ANY (ARRAY['approved'::text, 'done'::text, 'auto_done'::text]))) AS accepted
           FROM agent_actions
          WHERE (agent_actions.created_at >= (now() - '30 days'::interval))
          GROUP BY agent_actions.agent
        )
 SELECT COALESCE(r.agent, a.agent) AS agent,
    COALESCE(r.runs_30d, (0)::bigint) AS runs_30d,
    COALESCE(r.errors, (0)::bigint) AS errors,
    round(((100.0 * ((COALESCE(r.runs_30d, (0)::bigint) - COALESCE(r.errors, (0)::bigint)))::numeric) / (NULLIF(r.runs_30d, 0))::numeric), 1) AS run_success_pct,
    COALESCE(a.actions_30d, (0)::bigint) AS actions_30d,
    COALESCE(a.open_escalations, (0)::bigint) AS open_escalations,
    COALESCE(a.rejected, (0)::bigint) AS rejected,
    COALESCE(a.accepted, (0)::bigint) AS accepted,
    round(((100.0 * (a.rejected)::numeric) / (NULLIF((a.rejected + a.accepted), 0))::numeric), 1) AS rejection_rate_pct
   FROM (runs r
     FULL JOIN acts a ON ((a.agent = r.agent)));

CREATE OR REPLACE VIEW public.ap_aging AS  SELECT v.name AS vendor,
    sum(
        CASE
            WHEN (CURRENT_DATE <= COALESCE(b.due_date, b.bill_date)) THEN (b.total - b.amount_paid)
            ELSE (0)::numeric
        END) AS current_due,
    sum(
        CASE
            WHEN (((CURRENT_DATE - COALESCE(b.due_date, b.bill_date)) >= 1) AND ((CURRENT_DATE - COALESCE(b.due_date, b.bill_date)) <= 30)) THEN (b.total - b.amount_paid)
            ELSE (0)::numeric
        END) AS d1_30,
    sum(
        CASE
            WHEN (((CURRENT_DATE - COALESCE(b.due_date, b.bill_date)) >= 31) AND ((CURRENT_DATE - COALESCE(b.due_date, b.bill_date)) <= 60)) THEN (b.total - b.amount_paid)
            ELSE (0)::numeric
        END) AS d31_60,
    sum(
        CASE
            WHEN (((CURRENT_DATE - COALESCE(b.due_date, b.bill_date)) >= 61) AND ((CURRENT_DATE - COALESCE(b.due_date, b.bill_date)) <= 90)) THEN (b.total - b.amount_paid)
            ELSE (0)::numeric
        END) AS d61_90,
    sum(
        CASE
            WHEN ((CURRENT_DATE - COALESCE(b.due_date, b.bill_date)) > 90) THEN (b.total - b.amount_paid)
            ELSE (0)::numeric
        END) AS d90_plus,
    sum((b.total - b.amount_paid)) AS total_due
   FROM (ap_bills b
     JOIN po_vendors v ON ((v.id = b.vendor_id)))
  WHERE (b.status = ANY (ARRAY['open'::text, 'partial'::text]))
  GROUP BY v.name;

CREATE OR REPLACE VIEW public.ap_open_bills AS  SELECT b.id,
    b.bill_no,
    v.name AS vendor,
    b.bill_date,
    b.due_date,
    b.total,
    b.amount_paid,
    (b.total - b.amount_paid) AS balance_due,
    b.status,
    (CURRENT_DATE - b.due_date) AS days_overdue
   FROM (ap_bills b
     JOIN po_vendors v ON ((v.id = b.vendor_id)))
  WHERE (b.status = ANY (ARRAY['open'::text, 'partial'::text]))
  ORDER BY b.due_date;

CREATE OR REPLACE VIEW public.budget_vs_actual AS  WITH actual AS (
         SELECT l.account_code,
            (date_trunc('month'::text, (j.entry_date)::timestamp with time zone))::date AS period_month,
            sum(l.debit) AS dr,
            sum(l.credit) AS cr
           FROM (gl_journal_lines l
             JOIN gl_journal j ON (((j.id = l.journal_id) AND (j.status = 'posted'::text))))
          GROUP BY l.account_code, ((date_trunc('month'::text, (j.entry_date)::timestamp with time zone))::date)
        )
 SELECT b.id AS budget_id,
    b.name AS budget_name,
    b.fiscal_year,
    bl.account_code,
    ga.name AS account_name,
    ga.type,
    bl.period_month,
    bl.amount AS budget_amount,
    COALESCE(
        CASE
            WHEN (ga.normal_balance = 'D'::bpchar) THEN (a.dr - a.cr)
            ELSE (a.cr - a.dr)
        END, (0)::numeric) AS actual_amount,
    (bl.amount - COALESCE(
        CASE
            WHEN (ga.normal_balance = 'D'::bpchar) THEN (a.dr - a.cr)
            ELSE (a.cr - a.dr)
        END, (0)::numeric)) AS variance
   FROM (((budget_lines bl
     JOIN budgets b ON ((b.id = bl.budget_id)))
     JOIN gl_accounts ga ON ((ga.code = bl.account_code)))
     LEFT JOIN actual a ON (((a.account_code = bl.account_code) AND (a.period_month = bl.period_month))));

CREATE OR REPLACE VIEW public.budget_vs_actual_summary AS  SELECT budget_id,
    budget_name,
    fiscal_year,
    account_code,
    account_name,
    type,
    sum(budget_amount) AS budget_ytd,
    sum(actual_amount) AS actual_ytd,
    sum(variance) AS variance_ytd,
        CASE
            WHEN (sum(budget_amount) <> (0)::numeric) THEN round(((100.0 * sum(actual_amount)) / sum(budget_amount)), 1)
            ELSE NULL::numeric
        END AS pct_of_budget
   FROM budget_vs_actual
  GROUP BY budget_id, budget_name, fiscal_year, account_code, account_name, type
  ORDER BY account_code;

CREATE OR REPLACE VIEW public.category_price_stats AS  SELECT i.category,
    count(qq.quote_amount) AS n,
    round((percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((qq.quote_amount)::double precision)))::numeric, 0) AS median,
    round((percentile_cont((0.25)::double precision) WITHIN GROUP (ORDER BY ((qq.quote_amount)::double precision)))::numeric, 0) AS p25,
    round((percentile_cont((0.75)::double precision) WITHIN GROUP (ORDER BY ((qq.quote_amount)::double precision)))::numeric, 0) AS p75,
    round(avg(qq.quote_amount), 0) AS mean,
    round(COALESCE(stddev_pop(qq.quote_amount), (0)::numeric), 0) AS sd
   FROM (quotes qq
     JOIN inquiries i ON ((i.id = qq.inquiry_id)))
  WHERE ((qq.quote_amount IS NOT NULL) AND (qq.quote_amount > (0)::numeric) AND (i.category IS NOT NULL))
  GROUP BY i.category;

CREATE OR REPLACE VIEW public.crm_deal_kpis AS  SELECT (( SELECT count(*) AS count
           FROM (inquiries i
             JOIN crm_stages s ON ((s.key = i.pipeline_stage)))
          WHERE ((NOT s.is_won) AND (NOT s.is_lost))))::integer AS open_deals,
    (( SELECT count(*) AS count
           FROM (inquiries i
             JOIN crm_stages s ON ((s.key = i.pipeline_stage)))
          WHERE s.is_won))::integer AS won_deals,
    (( SELECT count(*) AS count
           FROM (inquiries i
             JOIN crm_stages s ON ((s.key = i.pipeline_stage)))
          WHERE s.is_lost))::integer AS lost_deals,
    ( SELECT round(avg((EXTRACT(epoch FROM (COALESCE(i.completed_at, now()) - i.created_at)) / 86400.0)), 1) AS round
           FROM (inquiries i
             JOIN crm_stages s ON ((s.key = i.pipeline_stage)))
          WHERE s.is_won) AS avg_cycle_days,
    ( SELECT round(COALESCE(sum(((i.expected_value * (s.probability)::numeric) / 100.0)), (0)::numeric), 2) AS round
           FROM (inquiries i
             JOIN crm_stages s ON ((s.key = i.pipeline_stage)))
          WHERE ((NOT s.is_won) AND (NOT s.is_lost))) AS weighted_forecast,
    (( SELECT count(*) AS count
           FROM crm_activities
          WHERE ((crm_activities.done = false) AND (crm_activities.due_at IS NOT NULL) AND (crm_activities.due_at < now()))))::integer AS overdue_activities;

CREATE OR REPLACE VIEW public.crm_pipeline_report AS  SELECT s.key,
    s.label,
    s.sort_order,
    s.probability,
    s.is_won,
    s.is_lost,
    (count(i.id))::integer AS deals,
    round(COALESCE(sum(i.expected_value), (0)::numeric), 2) AS value,
    round(COALESCE(sum(((i.expected_value * (s.probability)::numeric) / 100.0)), (0)::numeric), 2) AS weighted
   FROM (crm_stages s
     LEFT JOIN inquiries i ON ((i.pipeline_stage = s.key)))
  WHERE s.active
  GROUP BY s.key, s.label, s.sort_order, s.probability, s.is_won, s.is_lost
  ORDER BY s.sort_order;

CREATE OR REPLACE VIEW public.customer_health AS  WITH inq AS (
         SELECT i.id,
            i.customer_id,
            i.status,
            i.pipeline_stage,
            i.created_at,
            i.completed_at,
            i.outcome,
            i.stage_changed_at,
            ( SELECT min(q.created_at) AS min
                   FROM quotes q
                  WHERE (q.inquiry_id = i.id)) AS first_quote_at,
            ( SELECT count(*) AS count
                   FROM quotes q
                  WHERE (q.inquiry_id = i.id)) AS n_quotes
           FROM inquiries i
        ), inq2 AS (
         SELECT inq.id,
            inq.customer_id,
            inq.status,
            inq.pipeline_stage,
            inq.created_at,
            inq.completed_at,
            inq.outcome,
            inq.stage_changed_at,
            inq.first_quote_at,
            inq.n_quotes,
            (EXTRACT(epoch FROM (inq.first_quote_at - inq.created_at)) / 3600.0) AS resp_hrs,
                CASE
                    WHEN ((inq.status = 'revealed'::text) AND (inq.completed_at IS NULL) AND (inq.created_at < (now() - '30 days'::interval))) THEN true
                    WHEN ((inq.status = 'quoted'::text) AND (inq.created_at < (now() - '7 days'::interval))) THEN true
                    WHEN ((COALESCE(inq.pipeline_stage, ''::text) = 'qualifying'::text) AND (inq.n_quotes = 0) AND (inq.created_at < (now() - '2 days'::interval))) THEN true
                    ELSE false
                END AS stalled,
            ((inq.completed_at IS NOT NULL) OR (inq.outcome = 'won'::text)) AS completed,
            ((inq.status = 'revealed'::text) OR (inq.completed_at IS NOT NULL) OR (inq.outcome = 'won'::text)) AS progressed
           FROM inq
        ), cust AS (
         SELECT c.id AS customer_id,
            c.full_name,
            c.email,
            COALESCE(c.banned, false) AS banned,
            COALESCE(c.chat_strikes, 0) AS strikes,
            ( SELECT count(*) AS count
                   FROM inq2 x
                  WHERE (x.customer_id = c.id)) AS total_inq,
            ( SELECT count(*) AS count
                   FROM inq2 x
                  WHERE ((x.customer_id = c.id) AND (x.status <> 'cancelled'::text) AND (COALESCE(x.pipeline_stage, ''::text) <> 'lost'::text))) AS active_inq,
            ( SELECT count(*) AS count
                   FROM inq2 x
                  WHERE ((x.customer_id = c.id) AND x.progressed)) AS progressed_inq,
            ( SELECT count(*) AS count
                   FROM inq2 x
                  WHERE ((x.customer_id = c.id) AND x.completed)) AS completed_inq,
            ( SELECT count(*) AS count
                   FROM inq2 x
                  WHERE ((x.customer_id = c.id) AND x.stalled)) AS stalled_inq,
            ( SELECT max(GREATEST(x.created_at, COALESCE(x.stage_changed_at, x.created_at))) AS max
                   FROM inq2 x
                  WHERE (x.customer_id = c.id)) AS last_activity,
            ( SELECT round(avg(x.resp_hrs), 1) AS round
                   FROM inq2 x
                  WHERE ((x.customer_id = c.id) AND (x.resp_hrs IS NOT NULL))) AS avg_resp_hrs,
            ( SELECT round(avg(r.rating), 2) AS round
                   FROM reviews r
                  WHERE (r.customer_id = c.id)) AS avg_review,
            ( SELECT count(*) AS count
                   FROM reviews r
                  WHERE ((r.customer_id = c.id) AND (r.rating <= 2))) AS bad_reviews,
            ( SELECT count(*) AS count
                   FROM transactions t
                  WHERE ((t.customer_id = c.id) AND ((t.refund_status IS NOT NULL) OR (t.refund_requested_at IS NOT NULL)))) AS disputes
           FROM customers c
        ), scored AS (
         SELECT cust.customer_id,
            cust.full_name,
            cust.email,
            cust.banned,
            cust.strikes,
            cust.total_inq,
            cust.active_inq,
            cust.progressed_inq,
            cust.completed_inq,
            cust.stalled_inq,
            cust.last_activity,
            cust.avg_resp_hrs,
            cust.avg_review,
            cust.bad_reviews,
            cust.disputes,
            ((cust.last_activity IS NOT NULL) AND (cust.last_activity < (now() - '45 days'::interval))) AS dormant,
            round(LEAST((100)::numeric, ((
                CASE
                    WHEN (cust.last_activity >= (now() - '30 days'::interval)) THEN 60
                    WHEN (cust.last_activity >= (now() - '60 days'::interval)) THEN 40
                    WHEN (cust.last_activity >= (now() - '120 days'::interval)) THEN 20
                    ELSE 5
                END)::numeric + (((LEAST(cust.total_inq, (5)::bigint))::numeric / 5.0) * (40)::numeric))), 1) AS engagement,
            round(GREATEST((0)::numeric, LEAST((100)::numeric, (((
                CASE
                    WHEN (cust.avg_review IS NOT NULL) THEN ((cust.avg_review / 5.0) * (100)::numeric)
                    ELSE (70)::numeric
                END - (
                CASE
                    WHEN (cust.disputes > 0) THEN 30
                    ELSE 0
                END)::numeric) - ((cust.bad_reviews * 15))::numeric) - ((LEAST(cust.strikes, 3) * 10))::numeric))), 1) AS satisfaction,
            round(
                CASE
                    WHEN (cust.active_inq > 0) THEN (((cust.progressed_inq)::numeric / (cust.active_inq)::numeric) * (100)::numeric)
                    WHEN (cust.total_inq = 0) THEN (50)::numeric
                    ELSE (20)::numeric
                END, 1) AS progress,
            round((GREATEST(0, (
                CASE
                    WHEN (cust.avg_resp_hrs IS NULL) THEN 60
                    WHEN (cust.avg_resp_hrs < (24)::numeric) THEN 100
                    WHEN (cust.avg_resp_hrs < (72)::numeric) THEN 70
                    WHEN (cust.avg_resp_hrs < (168)::numeric) THEN 40
                    ELSE 20
                END -
                CASE
                    WHEN (cust.disputes > 0) THEN 40
                    ELSE 0
                END)))::numeric, 1) AS service
           FROM cust
        )
 SELECT customer_id,
    full_name,
    email,
    total_inq,
    active_inq,
    progressed_inq,
    completed_inq,
    stalled_inq,
    avg_resp_hrs,
    avg_review,
    bad_reviews,
    disputes,
    dormant,
    strikes,
    banned,
    last_activity,
    engagement,
    satisfaction,
    progress,
    service,
    round(((((engagement * 0.25) + (satisfaction * 0.30)) + (progress * 0.25)) + (service * 0.20)), 1) AS health,
        CASE
            WHEN (banned OR (disputes > 0) OR (bad_reviews > 0) OR ((total_inq > 0) AND (active_inq = 0)) OR (round(((((engagement * 0.25) + (satisfaction * 0.30)) + (progress * 0.25)) + (service * 0.20)), 1) < (40)::numeric)) THEN 'high'::text
            WHEN ((stalled_inq > 0) OR (strikes > 0) OR dormant OR (round(((((engagement * 0.25) + (satisfaction * 0.30)) + (progress * 0.25)) + (service * 0.20)), 1) < (65)::numeric)) THEN 'medium'::text
            ELSE 'low'::text
        END AS risk_tier
   FROM scored;

CREATE OR REPLACE VIEW public.customer_kpis AS  SELECT count(*) AS customers,
    round(avg(health), 1) AS avg_health,
    round(avg(satisfaction), 1) AS avg_satisfaction,
    round(avg(avg_resp_hrs) FILTER (WHERE (avg_resp_hrs IS NOT NULL)), 1) AS avg_response_hrs,
    round(((100.0 * (count(*) FILTER (WHERE (progress >= (60)::numeric)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS pct_progressing,
    count(*) FILTER (WHERE (disputes > 0)) AS open_disputes,
    count(*) FILTER (WHERE (stalled_inq > 0)) AS with_stalled,
    count(*) FILTER (WHERE dormant) AS dormant_count,
    count(*) FILTER (WHERE (risk_tier = 'high'::text)) AS risk_high,
    count(*) FILTER (WHERE (risk_tier = 'medium'::text)) AS risk_medium,
    count(*) FILTER (WHERE (risk_tier = 'low'::text)) AS risk_low
   FROM customer_health;

CREATE OR REPLACE VIEW public.document_inventory AS  SELECT o.bucket_id AS bucket,
    o.name AS path,
    COALESCE(((o.metadata ->> 'size'::text))::bigint, (0)::bigint) AS bytes,
    COALESCE((o.metadata ->> 'mimetype'::text), ''::text) AS mime,
    o.created_at,
    rp.retention_days,
    rp.class AS retention_class,
    ((rp.retention_days IS NOT NULL) AND (o.created_at < (now() - ((rp.retention_days || ' days'::text))::interval))) AS past_retention,
    (EXISTS ( SELECT 1
           FROM documents d
          WHERE ((d.bucket = o.bucket_id) AND (d.path = o.name)))) AS registered,
    (EXISTS ( SELECT 1
           FROM documents d
          WHERE ((d.bucket = o.bucket_id) AND (d.path = o.name) AND (d.extracted IS NOT NULL)))) AS ocr_done
   FROM (storage.objects o
     LEFT JOIN retention_policy rp ON ((rp.bucket = o.bucket_id)))
  WHERE ((o.name IS NOT NULL) AND ("right"(o.name, 1) <> '/'::text));

CREATE OR REPLACE VIEW public.document_kpis AS  SELECT ( SELECT count(*) AS count
           FROM document_inventory) AS total_documents,
    ( SELECT COALESCE(sum(document_inventory.bytes), (0)::numeric) AS "coalesce"
           FROM document_inventory) AS total_bytes,
    ( SELECT count(DISTINCT document_inventory.bucket) AS count
           FROM document_inventory) AS buckets,
    ( SELECT count(*) AS count
           FROM document_inventory
          WHERE document_inventory.past_retention) AS past_retention,
    ( SELECT count(*) AS count
           FROM document_inventory
          WHERE (document_inventory.bytes > ((30 * 1024) * 1024))) AS oversized,
    ( SELECT count(*) AS count
           FROM documents) AS registered_docs,
    ( SELECT count(*) AS count
           FROM documents
          WHERE (documents.extracted IS NOT NULL)) AS ocr_done,
    ( SELECT count(*) AS count
           FROM documents
          WHERE ((COALESCE(documents.status, ''::text) <> ALL (ARRAY['done'::text, 'skipped'::text])) OR (COALESCE(documents.error, ''::text) <> ''::text))) AS ocr_backlog,
    round(((100.0 * (( SELECT count(*) AS count
           FROM documents
          WHERE (documents.extracted IS NOT NULL)))::numeric) / (NULLIF(( SELECT count(*) AS count
           FROM documents), 0))::numeric), 1) AS ocr_coverage_pct,
    ( SELECT count(*) AS count
           FROM doc_versions) AS version_records,
    ( SELECT max(objects.created_at) AS max
           FROM storage.objects
          WHERE (objects.bucket_id = 'backups'::text)) AS last_backup_at,
    ( SELECT ((EXTRACT(epoch FROM (now() - max(objects.created_at))) / (86400)::numeric))::integer AS int4
           FROM storage.objects
          WHERE (objects.bucket_id = 'backups'::text)) AS days_since_backup,
    ( SELECT count(*) AS count
           FROM legal_documents) AS legal_documents,
    ( SELECT count(*) AS count
           FROM dropbox_files
          WHERE (NOT dropbox_files.is_folder)) AS dropbox_files,
    ( SELECT count(*) AS count
           FROM dropbox_files
          WHERE dropbox_files.is_folder) AS dropbox_folders,
    ( SELECT COALESCE(sum(dropbox_files.size), (0)::numeric) AS "coalesce"
           FROM dropbox_files) AS dropbox_bytes,
    ( SELECT max(dropbox_files.synced_at) AS max
           FROM dropbox_files) AS dropbox_last_sync;

CREATE OR REPLACE VIEW public.fa_register AS  SELECT id,
    asset_no,
    name,
    category,
    acquire_date,
    in_service_date,
    cost,
    salvage_value,
    useful_life_months,
    accumulated_depreciation,
    (cost - accumulated_depreciation) AS net_book_value,
    status,
    disposed_date
   FROM fa_assets
  ORDER BY asset_no;

CREATE OR REPLACE VIEW public.finance_kpis AS  WITH rr AS (
         SELECT COALESCE(sum(
                CASE
                    WHEN (ga.type = 'revenue'::text) THEN (l.credit - l.debit)
                    ELSE (0)::numeric
                END), (0)::numeric) AS rev30,
            COALESCE(sum(
                CASE
                    WHEN (ga.type = 'expense'::text) THEN (l.debit - l.credit)
                    ELSE (0)::numeric
                END), (0)::numeric) AS exp30
           FROM ((gl_journal_lines l
             JOIN gl_journal j ON (((j.id = l.journal_id) AND (j.status = 'posted'::text))))
             JOIN gl_accounts ga ON ((ga.code = l.account_code)))
          WHERE (j.entry_date >= (CURRENT_DATE - 30))
        ), ar AS (
         SELECT COALESCE(sum(supplier_dues.amount_due) FILTER (WHERE (supplier_dues.status <> ALL (ARRAY['paid'::text, 'waived'::text]))), (0)::numeric) AS ar_outstanding,
            COALESCE(sum(supplier_dues.amount_due) FILTER (WHERE ((supplier_dues.status <> ALL (ARRAY['paid'::text, 'waived'::text])) AND (supplier_dues.due_date_30 < CURRENT_DATE))), (0)::numeric) AS ar_overdue,
            COALESCE(sum(supplier_dues.amount_due) FILTER (WHERE (supplier_dues.status = 'paid'::text)), (0)::numeric) AS ar_collected
           FROM supplier_dues
        ), ap AS (
         SELECT COALESCE(sum(ap_open_bills.balance_due), (0)::numeric) AS ap_outstanding,
            COALESCE(sum(ap_open_bills.balance_due) FILTER (WHERE (ap_open_bills.days_overdue > 0)), (0)::numeric) AS ap_overdue
           FROM ap_open_bills
        ), bud AS (
         SELECT count(*) FILTER (WHERE ((budget_vs_actual_summary.type = 'expense'::text) AND (budget_vs_actual_summary.pct_of_budget > (110)::numeric))) AS budget_overruns
           FROM budget_vs_actual_summary
        )
 SELECT ( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
           FROM gl_account_balances
          WHERE (gl_account_balances.code = ANY (ARRAY['1000'::text, '1050'::text]))) AS cash,
    ( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
           FROM gl_account_balances
          WHERE (gl_account_balances.type = 'revenue'::text)) AS revenue_total,
    ( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
           FROM gl_account_balances
          WHERE (gl_account_balances.type = 'expense'::text)) AS expense_total,
    (( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
           FROM gl_account_balances
          WHERE (gl_account_balances.type = 'revenue'::text)) - ( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
           FROM gl_account_balances
          WHERE (gl_account_balances.type = 'expense'::text))) AS net_income,
        CASE
            WHEN (( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.type = 'revenue'::text)) > (0)::numeric) THEN round(((100.0 * (( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.type = 'revenue'::text)) - ( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.type = 'expense'::text)))) / ( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.type = 'revenue'::text))), 1)
            ELSE NULL::numeric
        END AS margin_pct,
    rr.rev30 AS revenue_30d,
    rr.exp30 AS expense_30d,
    (rr.exp30 - rr.rev30) AS monthly_burn,
        CASE
            WHEN (((rr.exp30 - rr.rev30) > (0)::numeric) AND (( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.code = ANY (ARRAY['1000'::text, '1050'::text]))) > (0)::numeric)) THEN round((( SELECT COALESCE(sum(gl_account_balances.balance), (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.code = ANY (ARRAY['1000'::text, '1050'::text]))) / (rr.exp30 - rr.rev30)), 1)
            ELSE NULL::numeric
        END AS runway_months,
    ar.ar_outstanding,
    ar.ar_overdue,
    ar.ar_collected,
        CASE
            WHEN ((ar.ar_collected + ar.ar_outstanding) > (0)::numeric) THEN round(((100.0 * ar.ar_collected) / (ar.ar_collected + ar.ar_outstanding)), 1)
            ELSE NULL::numeric
        END AS collection_rate,
    ap.ap_outstanding,
    ap.ap_overdue,
    bud.budget_overruns
   FROM rr,
    ar,
    ap,
    bud;

CREATE OR REPLACE VIEW public.gl_account_balances AS  SELECT a.code,
    a.name,
    a.type,
    a.normal_balance,
    COALESCE(sum(l.debit), (0)::numeric) AS debit_total,
    COALESCE(sum(l.credit), (0)::numeric) AS credit_total,
        CASE
            WHEN (a.normal_balance = 'D'::bpchar) THEN (COALESCE(sum(l.debit), (0)::numeric) - COALESCE(sum(l.credit), (0)::numeric))
            ELSE (COALESCE(sum(l.credit), (0)::numeric) - COALESCE(sum(l.debit), (0)::numeric))
        END AS balance
   FROM ((gl_accounts a
     LEFT JOIN gl_journal_lines l ON ((l.account_code = a.code)))
     LEFT JOIN gl_journal j ON (((j.id = l.journal_id) AND (j.status = 'posted'::text))))
  GROUP BY a.code, a.name, a.type, a.normal_balance;

CREATE OR REPLACE VIEW public.gl_balance_sheet AS  SELECT type,
    code,
    name,
    balance AS amount
   FROM gl_account_balances
  WHERE (type = ANY (ARRAY['asset'::text, 'liability'::text, 'equity'::text]))
  ORDER BY type, code;

CREATE OR REPLACE VIEW public.gl_ledger AS  SELECT j.id AS journal_id,
    j.entry_no,
    j.entry_date,
    j.source,
    j.source_ref,
    j.memo,
    l.account_code,
    a.name AS account_name,
    a.type AS account_type,
    l.debit,
    l.credit
   FROM ((gl_journal j
     JOIN gl_journal_lines l ON ((l.journal_id = j.id)))
     JOIN gl_accounts a ON ((a.code = l.account_code)))
  WHERE (j.status = 'posted'::text);

CREATE OR REPLACE VIEW public.gl_pnl AS  SELECT type,
    code,
    name,
    balance AS amount
   FROM gl_account_balances
  WHERE (type = ANY (ARRAY['revenue'::text, 'expense'::text]))
  ORDER BY type DESC, code;

CREATE OR REPLACE VIEW public.gl_trial_balance AS  SELECT code,
    name,
    type,
        CASE
            WHEN ((balance >= (0)::numeric) AND (normal_balance = 'D'::bpchar)) THEN balance
            ELSE (0)::numeric
        END AS debit,
        CASE
            WHEN ((balance >= (0)::numeric) AND (normal_balance = 'C'::bpchar)) THEN balance
            ELSE (0)::numeric
        END AS credit,
    balance
   FROM gl_account_balances
  WHERE ((debit_total <> (0)::numeric) OR (credit_total <> (0)::numeric))
  ORDER BY code;

CREATE OR REPLACE VIEW public.governance_kpis AS  WITH agents AS (
         SELECT category_agents.slug,
            category_agents.persona
           FROM category_agents
          WHERE category_agents.active
        ), kn AS (
         SELECT DISTINCT agent_knowledge.agent_key
           FROM agent_knowledge
        ), act30 AS (
         SELECT agent_actions.id,
            agent_actions.agent,
            agent_actions.kind,
            agent_actions.status,
            agent_actions.risk,
            agent_actions.title,
            agent_actions.recommendation,
            agent_actions.detail,
            agent_actions.target_table,
            agent_actions.target_id,
            agent_actions.created_at,
            agent_actions.decided_at,
            agent_actions.decided_by,
            agent_actions.confidence,
            agent_actions.evidence,
            agent_actions.escalated,
            agent_actions.escalation_reason
           FROM agent_actions
          WHERE (agent_actions.created_at > (now() - '30 days'::interval))
        )
 SELECT ( SELECT count(*) AS count
           FROM agents) AS active_agents,
    ( SELECT count(*) AS count
           FROM agents
          WHERE ((agents.persona IS NOT NULL) AND (length(agents.persona) > 40))) AS agents_with_persona,
    ( SELECT count(*) AS count
           FROM agent_knowledge
          WHERE (agent_knowledge.agent_key = '_global'::text)) AS global_rules,
    ( SELECT count(*) AS count
           FROM agent_knowledge) AS knowledge_items,
    ( SELECT agent_governance.version
           FROM agent_governance
          WHERE agent_governance.active
          ORDER BY agent_governance.version DESC
         LIMIT 1) AS governance_version,
    ( SELECT count(*) AS count
           FROM act30) AS decisions_30d,
    ( SELECT count(*) AS count
           FROM act30
          WHERE (act30.confidence IS NOT NULL)) AS decisions_with_confidence,
    ( SELECT round(avg(act30.confidence), 2) AS round
           FROM act30
          WHERE (act30.confidence IS NOT NULL)) AS avg_confidence,
    ( SELECT count(*) AS count
           FROM act30
          WHERE act30.escalated) AS escalated_30d,
    ( SELECT count(*) AS count
           FROM agent_actions
          WHERE (agent_actions.status = ANY (ARRAY['pending'::text, 'needs_review'::text]))) AS open_for_review,
    ( SELECT count(*) AS count
           FROM agent_actions) AS audit_trail_total,
    ( SELECT count(DISTINCT agent_actions.agent) AS count
           FROM agent_actions) AS agents_with_audit_trail;

CREATE OR REPLACE VIEW public.inv_on_hand AS  SELECT i.id,
    i.sku,
    i.name,
    i.uom,
    i.category,
    COALESCE(sum(m.qty_delta), (0)::numeric) AS qty_on_hand,
    COALESCE(sum(m.cost_delta), (0)::numeric) AS inventory_value,
        CASE
            WHEN (COALESCE(sum(m.qty_delta), (0)::numeric) <> (0)::numeric) THEN round((sum(m.cost_delta) / sum(m.qty_delta)), 4)
            ELSE (0)::numeric
        END AS avg_unit_cost,
    i.reorder_point,
    (COALESCE(sum(m.qty_delta), (0)::numeric) <= i.reorder_point) AS needs_reorder
   FROM (inv_items i
     LEFT JOIN inv_stock_moves m ON ((m.item_id = i.id)))
  GROUP BY i.id, i.sku, i.name, i.uom, i.category, i.reorder_point;

CREATE OR REPLACE VIEW public.inv_valuation AS  SELECT COALESCE(sum(cost_delta), (0)::numeric) AS total_inventory_value,
    count(DISTINCT item_id) FILTER (WHERE true) AS items_with_moves
   FROM inv_stock_moves;

CREATE OR REPLACE VIEW public.knowledge_kpis AS  WITH cats AS (
         SELECT category_agents.slug,
            category_agents.requires_regulation
           FROM category_agents
          WHERE (category_agents.active AND (category_agents.slug !~ '_'::text))
        ), base AS (
         SELECT ( SELECT count(*) AS count
                   FROM cats) AS categories_total,
            ( SELECT count(*) AS count
                   FROM cats c
                  WHERE (EXISTS ( SELECT 1
                           FROM agent_knowledge k
                          WHERE (k.agent_key = ('cat:'::text || c.slug))))) AS cat_with_knowledge,
            ( SELECT count(*) AS count
                   FROM cats c
                  WHERE (EXISTS ( SELECT 1
                           FROM qualification_playbooks p
                          WHERE ((p.category = c.slug) OR (c.slug ~~* (('%'::text || p.category) || '%'::text)) OR (p.category ~~* (('%'::text || c.slug) || '%'::text)))))) AS cat_with_playbook,
            ( SELECT count(*) AS count
                   FROM cats c
                  WHERE (EXISTS ( SELECT 1
                           FROM regulations r
                          WHERE ((r.status = 'active'::text) AND (r.approved_at IS NOT NULL) AND (c.slug = ANY (r.categories)))))) AS cat_with_regs,
            ( SELECT count(*) AS count
                   FROM cats c
                  WHERE c.requires_regulation) AS regs_required,
            ( SELECT count(*) AS count
                   FROM cats c
                  WHERE (c.requires_regulation AND (EXISTS ( SELECT 1
                           FROM regulations r
                          WHERE ((r.status = 'active'::text) AND (r.approved_at IS NOT NULL) AND (c.slug = ANY (r.categories))))))) AS cat_regulated_covered,
            ( SELECT count(*) AS count
                   FROM regulations) AS regulations,
            ( SELECT count(*) AS count
                   FROM regulations
                  WHERE ((regulations.status = 'active'::text) AND (regulations.approved_at IS NOT NULL))) AS regulations_published,
            ( SELECT count(*) AS count
                   FROM regulations
                  WHERE (regulations.approved_at IS NULL)) AS regulations_pending,
            ( SELECT count(*) AS count
                   FROM mdm_standards) AS standards,
            ( SELECT count(*) AS count
                   FROM mdm_manufacturers) AS manufacturers,
            ( SELECT count(*) AS count
                   FROM mdm_brands) AS brands,
            ( SELECT count(*) AS count
                   FROM materials) AS materials,
            ( SELECT count(*) AS count
                   FROM qualification_playbooks) AS playbooks,
            ( SELECT count(*) AS count
                   FROM category_specs) AS category_specs,
            ( SELECT count(*) AS count
                   FROM kb_chunks) AS chunks,
            ( SELECT count(*) AS count
                   FROM agent_knowledge) AS knowledge_entries,
            ( SELECT count(*) AS count
                   FROM kb_revisions) AS revisions,
            ( SELECT count(*) AS count
                   FROM kb_revisions
                  WHERE ((COALESCE((kb_revisions.ai_validation ->> 'result'::text), 'pass'::text) = ANY (ARRAY['fail'::text, 'flag'::text, 'warn'::text])) OR (kb_revisions.status = 'rejected'::text))) AS flagged_revisions,
            ( SELECT count(*) AS count
                   FROM compliance_sources
                  WHERE compliance_sources.active) AS compliance_active,
            ( SELECT count(*) AS count
                   FROM compliance_sources
                  WHERE (compliance_sources.active AND (compliance_sources.last_checked_at >= (now() - '45 days'::interval)))) AS compliance_fresh,
            ( SELECT count(*) AS count
                   FROM category_specs
                  WHERE (category_specs.updated_at >= (now() - '180 days'::interval))) AS specs_fresh,
            ( SELECT count(*) AS count
                   FROM regulations
                  WHERE (regulations.updated_at >= (now() - '365 days'::interval))) AS regs_fresh,
            ( SELECT count(*) AS count
                   FROM kb_usage_log
                  WHERE (kb_usage_log.created_at >= (now() - '30 days'::interval))) AS queries_30d,
            ( SELECT count(DISTINCT kb_usage_log.category) AS count
                   FROM kb_usage_log
                  WHERE (kb_usage_log.created_at >= (now() - '30 days'::interval))) AS topics_queried_30d
        )
 SELECT categories_total,
    cat_with_knowledge,
    cat_with_playbook,
    cat_with_regs,
    regulations,
    regulations_published,
    regulations_pending,
    standards,
    manufacturers,
    brands,
    materials,
    playbooks,
    category_specs,
    chunks,
    knowledge_entries,
    revisions,
    flagged_revisions,
    compliance_active,
    compliance_fresh,
    specs_fresh,
    regs_fresh,
    queries_30d,
    topics_queried_30d,
    round(((100.0 * ((((cat_with_knowledge)::numeric / (NULLIF(categories_total, 0))::numeric) + ((cat_with_playbook)::numeric / (NULLIF(categories_total, 0))::numeric)) + COALESCE(((cat_regulated_covered)::numeric / (NULLIF(regs_required, 0))::numeric), (1)::numeric))) / 3.0), 1) AS coverage_pct,
    round(((100.0 * (cat_with_knowledge)::numeric) / (NULLIF(categories_total, 0))::numeric), 1) AS knowledge_coverage_pct,
    round(((100.0 * (cat_with_playbook)::numeric) / (NULLIF(categories_total, 0))::numeric), 1) AS playbook_coverage_pct,
    round(((100.0 * ((revisions - flagged_revisions))::numeric) / (NULLIF(revisions, 0))::numeric), 1) AS accuracy_pct,
    round(((100.0 * ((COALESCE(((compliance_fresh)::numeric / (NULLIF(compliance_active, 0))::numeric), (1)::numeric) + COALESCE(((specs_fresh)::numeric / (NULLIF(category_specs, 0))::numeric), (1)::numeric)) + COALESCE(((regs_fresh)::numeric / (NULLIF(regulations, 0))::numeric), (1)::numeric))) / (3)::numeric), 1) AS freshness_pct,
    round(((100.0 * (cat_with_knowledge)::numeric) / (NULLIF(categories_total, 0))::numeric), 1) AS usage_reach_pct,
    round((100.0 * COALESCE(((cat_regulated_covered)::numeric / (NULLIF(regs_required, 0))::numeric), (1)::numeric)), 1) AS regulation_coverage_pct,
    regs_required,
    cat_regulated_covered
   FROM base b;

CREATE OR REPLACE VIEW public.legal_kpis AS  SELECT ( SELECT count(*) AS count
           FROM legal_documents) AS policies_published,
    ( SELECT count(*) AS count
           FROM legal_documents
          WHERE (legal_documents.updated_at < (now() - '365 days'::interval))) AS policies_stale,
    ( SELECT count(*) AS count
           FROM legal_checklist) AS required_total,
    ( SELECT count(*) AS count
           FROM legal_checklist
          WHERE legal_checklist.present) AS required_present,
    ( SELECT count(*) AS count
           FROM legal_checklist
          WHERE (NOT legal_checklist.present)) AS required_missing,
    ( SELECT count(*) AS count
           FROM legal_checklist
          WHERE ((NOT legal_checklist.present) AND (legal_checklist.priority = 1))) AS critical_missing,
    round(((100.0 * (( SELECT count(*) AS count
           FROM legal_checklist
          WHERE legal_checklist.present))::numeric) / (NULLIF(( SELECT count(*) AS count
           FROM legal_checklist), 0))::numeric), 1) AS coverage_pct,
    ( SELECT count(*) AS count
           FROM customers) AS customers,
    round(((100.0 * (( SELECT count(*) AS count
           FROM customers
          WHERE (customers.tos_accepted_at IS NOT NULL)))::numeric) / (NULLIF(( SELECT count(*) AS count
           FROM customers), 0))::numeric), 1) AS customer_terms_acceptance_pct,
    ( SELECT count(*) AS count
           FROM leads
          WHERE (leads.approval_status = 'approved'::text)) AS suppliers_approved,
    round(((100.0 * (( SELECT count(*) AS count
           FROM leads
          WHERE ((leads.approval_status = 'approved'::text) AND (leads.accepted_terms_at IS NOT NULL))))::numeric) / (NULLIF(( SELECT count(*) AS count
           FROM leads
          WHERE (leads.approval_status = 'approved'::text)), 0))::numeric), 1) AS supplier_terms_acceptance_pct,
    ( SELECT count(*) AS count
           FROM agent_actions
          WHERE ((agent_actions.kind = 'legal_flag'::text) AND (agent_actions.status = ANY (ARRAY['pending'::text, 'needs_review'::text])))) AS open_legal_flags,
    ( SELECT count(*) AS count
           FROM legal_reviews
          WHERE ((legal_reviews.risk_level = 'high'::text) AND legal_reviews.needs_licensed_review)) AS high_risk_reviews;

CREATE OR REPLACE VIEW public.marketing_category_demand AS  WITH cats AS (
         SELECT DISTINCT COALESCE(NULLIF(inquiries.category, ''::text), 'other'::text) AS c
           FROM inquiries
          WHERE (inquiries.category IS NOT NULL)
        UNION
         SELECT seo_categories.slug
           FROM seo_categories
        )
 SELECT c AS category,
    ( SELECT count(*) AS count
           FROM inquiries i
          WHERE ((COALESCE(NULLIF(i.category, ''::text), 'other'::text) = c.c) AND (i.created_at >= (now() - '90 days'::interval)))) AS inquiries_90d,
    ( SELECT count(*) AS count
           FROM leads l
          WHERE ((l.approval_status = 'approved'::text) AND (l.claimed = true) AND (l.categories ~~* (('%'::text || c.c) || '%'::text)))) AS suppliers,
    (EXISTS ( SELECT 1
           FROM seo_categories s
          WHERE ((s.slug = c.c) AND s.generated))) AS has_seo_page,
    (EXISTS ( SELECT 1
           FROM blog_posts b
          WHERE ((b.category = c.c) AND b.published))) AS has_blog
   FROM cats c;

CREATE OR REPLACE VIEW public.marketing_kpis AS  WITH f AS (
         SELECT funnel_metrics(30) AS fm
        ), mi AS (
         SELECT COALESCE(sum(meta_insights.spend), (0)::numeric) AS meta_spend,
            COALESCE(sum(meta_insights.impressions), (0)::numeric) AS meta_impr,
            COALESCE(sum(meta_insights.clicks), (0)::numeric) AS meta_clicks,
            COALESCE(sum(meta_insights.results), (0)::numeric) AS meta_results,
            count(*) FILTER (WHERE (meta_insights.effective_status = 'ACTIVE'::text)) AS meta_active
           FROM meta_insights
          WHERE ((meta_insights.time_window = 'last_30d'::text) AND (meta_insights.campaign_name ~~* '%quotesdone%'::text))
        )
 SELECT ((f.fm ->> 'inquiries'::text))::integer AS inquiries_30d,
    ((f.fm ->> 'matched'::text))::integer AS matched_30d,
    ((f.fm ->> 'quoted'::text))::integer AS quoted_30d,
    ((f.fm ->> 'revealed'::text))::integer AS revealed_30d,
    ((f.fm ->> 'reveal_fees'::text))::numeric AS revenue_30d,
        CASE
            WHEN (((f.fm ->> 'inquiries'::text))::integer > 0) THEN round(((100.0 * (((f.fm ->> 'quoted'::text))::integer)::numeric) / (((f.fm ->> 'inquiries'::text))::integer)::numeric), 1)
            ELSE NULL::numeric
        END AS inq_to_quote_pct,
        CASE
            WHEN (((f.fm ->> 'quoted'::text))::integer > 0) THEN round(((100.0 * (((f.fm ->> 'revealed'::text))::integer)::numeric) / (((f.fm ->> 'quoted'::text))::integer)::numeric), 1)
            ELSE NULL::numeric
        END AS quote_to_reveal_pct,
    ( SELECT count(*) AS count
           FROM blog_posts
          WHERE blog_posts.published) AS blog_published,
    ( SELECT count(*) AS count
           FROM blog_posts) AS blog_total,
    ( SELECT count(*) AS count
           FROM content_drafts
          WHERE (COALESCE(content_drafts.status, ''::text) <> ALL (ARRAY['published'::text, 'discarded'::text]))) AS drafts_pending,
    ( SELECT count(*) AS count
           FROM social_posts
          WHERE (COALESCE(social_posts.status, ''::text) = ANY (ARRAY['staged'::text, 'scheduled'::text, 'draft'::text, 'pending'::text]))) AS social_staged,
    ( SELECT count(*) AS count
           FROM social_posts
          WHERE (COALESCE(social_posts.status, ''::text) = ANY (ARRAY['published'::text, 'sent'::text]))) AS social_published,
    ( SELECT count(*) AS count
           FROM seo_categories) AS seo_pages,
    ( SELECT count(*) AS count
           FROM seo_categories
          WHERE seo_categories.generated) AS seo_generated,
    ( SELECT count(*) AS count
           FROM leads) AS leads_total,
    ( SELECT count(*) AS count
           FROM outreach) AS outreach_sent,
    ( SELECT COALESCE(gl_account_balances.balance, (0)::numeric) AS "coalesce"
           FROM gl_account_balances
          WHERE (gl_account_balances.code = '6200'::text)) AS mkt_spend,
    ( SELECT count(*) AS count
           FROM customers
          WHERE (customers.created_at >= (now() - '30 days'::interval))) AS new_customers_30d,
        CASE
            WHEN (mi.meta_spend > (0)::numeric) THEN round((mi.meta_spend / (NULLIF(( SELECT count(*) AS count
               FROM customers
              WHERE (customers.created_at >= (now() - '30 days'::interval))), 0))::numeric), 2)
            ELSE NULL::numeric
        END AS cac,
        CASE
            WHEN (mi.meta_spend > (0)::numeric) THEN round((((f.fm ->> 'reveal_fees'::text))::numeric / mi.meta_spend), 2)
            WHEN (( SELECT COALESCE(gl_account_balances.balance, (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.code = '6200'::text)) > (0)::numeric) THEN round((((f.fm ->> 'reveal_fees'::text))::numeric / ( SELECT COALESCE(gl_account_balances.balance, (0)::numeric) AS "coalesce"
               FROM gl_account_balances
              WHERE (gl_account_balances.code = '6200'::text))), 2)
            ELSE NULL::numeric
        END AS roi,
    ( SELECT count(*) AS count
           FROM marketing_category_demand
          WHERE ((marketing_category_demand.inquiries_90d > 0) AND (marketing_category_demand.suppliers = 0))) AS supply_gaps,
    ( SELECT count(*) AS count
           FROM marketing_category_demand
          WHERE (NOT marketing_category_demand.has_seo_page)) AS seo_gaps,
    mi.meta_spend AS meta_spend_30d,
    mi.meta_impr AS meta_impressions_30d,
    mi.meta_clicks AS meta_clicks_30d,
    mi.meta_results AS meta_results_30d,
    mi.meta_active AS meta_active_campaigns,
        CASE
            WHEN (mi.meta_results > (0)::numeric) THEN round((mi.meta_spend / mi.meta_results), 2)
            ELSE NULL::numeric
        END AS meta_cpl,
        CASE
            WHEN (mi.meta_spend > (0)::numeric) THEN round((((f.fm ->> 'reveal_fees'::text))::numeric / mi.meta_spend), 2)
            ELSE NULL::numeric
        END AS meta_roi
   FROM f,
    mi;

CREATE OR REPLACE VIEW public.marketplace_health AS  SELECT fn_health_index() AS health;

CREATE OR REPLACE VIEW public.ops_kpis AS  WITH m AS (
         SELECT fn_ops_metrics() AS j
        )
 SELECT ((j ->> 'open_rfqs_no_quotes_7d'::text))::integer AS no_quote_backlog,
    ((j ->> 'matched_not_quoted'::text))::integer AS matched_not_quoted,
    ((j ->> 'avg_first_quote_hours'::text))::numeric AS avg_first_quote_hours,
    ((j ->> 'response_rate_pct'::text))::numeric AS response_rate_pct,
    ((j ->> 'overdue_activities'::text))::integer AS overdue_activities,
    ( SELECT count(*) AS count
           FROM agent_actions
          WHERE (agent_actions.status = ANY (ARRAY['pending'::text, 'needs_review'::text]))) AS pending_approvals,
    ( SELECT count(*) AS count
           FROM agent_actions
          WHERE ((agent_actions.status = ANY (ARRAY['pending'::text, 'needs_review'::text])) AND (COALESCE(agent_actions.risk, ''::text) = ANY (ARRAY['high'::text, 'critical'::text])))) AS high_risk_pending,
    ( SELECT count(*) AS count
           FROM crm_tasks
          WHERE (COALESCE(crm_tasks.status, ''::text) <> 'done'::text)) AS open_tasks,
    ( SELECT count(*) AS count
           FROM crm_tasks
          WHERE ((COALESCE(crm_tasks.status, ''::text) <> 'done'::text) AND (crm_tasks.due_date < now()))) AS overdue_tasks,
    ( SELECT count(*) AS count
           FROM inquiries
          WHERE ((inquiries.status = 'quoted'::text) AND (NOT (EXISTS ( SELECT 1
                   FROM transactions t
                  WHERE ((t.inquiry_id = inquiries.id) AND (t.revealed_at IS NOT NULL))))))) AS awaiting_reveal,
    ( SELECT count(*) AS count
           FROM cron.job) AS cron_jobs,
    ( SELECT count(*) AS count
           FROM cron.job_run_details
          WHERE ((job_run_details.status <> 'succeeded'::text) AND (job_run_details.start_time >= (now() - '24:00:00'::interval)))) AS cron_failures_24h,
    ( SELECT count(*) AS count
           FROM agent_runs
          WHERE ((agent_runs.status = ANY (ARRAY['error'::text, 'failed'::text])) AND (agent_runs.started_at >= (now() - '24:00:00'::interval)))) AS agent_errors_24h,
    ( SELECT count(*) AS count
           FROM error_events
          WHERE (error_events.created_at >= (now() - '24:00:00'::interval))) AS app_errors_24h,
    ( SELECT count(*) AS count
           FROM agent_actions
          WHERE ((agent_actions.kind = ANY (ARRAY['incident'::text, 'security_incident'::text])) AND (agent_actions.status = ANY (ARRAY['pending'::text, 'needs_review'::text])))) AS open_incidents
   FROM m;

CREATE OR REPLACE VIEW public.po_open AS  SELECT o.id,
    o.po_no,
    v.name AS vendor,
    o.status,
    o.order_date,
    o.expected_date,
    o.subtotal,
    COALESCE(sum((l.qty * l.unit_price)), (0)::numeric) AS ordered_value,
    COALESCE(sum((l.qty_received * l.unit_price)), (0)::numeric) AS received_value,
    COALESCE(sum(((l.qty - l.qty_received) * l.unit_price)), (0)::numeric) AS outstanding_value
   FROM ((po_orders o
     JOIN po_vendors v ON ((v.id = o.vendor_id)))
     LEFT JOIN po_lines l ON ((l.po_id = o.id)))
  WHERE (o.status = ANY (ARRAY['draft'::text, 'approved'::text, 'partial'::text, 'received'::text]))
  GROUP BY o.id, o.po_no, v.name, o.status, o.order_date, o.expected_date, o.subtotal;

CREATE OR REPLACE VIEW public.project_summary AS  SELECT p.id AS project_id,
    p.customer_id,
    p.name,
    p.status,
    p.target_open_date,
    p.budget_total,
    p.created_at,
    count(i.id) AS rfq_count,
    count(i.id) FILTER (WHERE (i.status <> ALL (ARRAY['completed'::text, 'cancelled'::text]))) AS rfq_open,
    count(i.id) FILTER (WHERE (i.hired_supplier_id IS NOT NULL)) AS rfq_awarded,
    round(COALESCE(sum(i.expected_value), (0)::numeric), 0) AS pipeline_value
   FROM (projects p
     LEFT JOIN inquiries i ON ((i.project_id = p.id)))
  GROUP BY p.id, p.customer_id, p.name, p.status, p.target_open_date, p.budget_total, p.created_at;

CREATE OR REPLACE VIEW public.reg_coverage AS  SELECT count(*) FILTER (WHERE (copyright = 'free'::text)) AS free_codes,
    count(*) FILTER (WHERE ((copyright = 'free'::text) AND (status = 'indexed'::text))) AS indexed,
    count(*) FILTER (WHERE ((copyright = 'free'::text) AND (status <> 'indexed'::text))) AS missing,
    count(*) FILTER (WHERE ((priority = 1) AND (copyright = 'free'::text))) AS critical_total,
    count(*) FILTER (WHERE ((priority = 1) AND (copyright = 'free'::text) AND (status = 'indexed'::text))) AS critical_indexed,
    count(*) FILTER (WHERE (copyright = 'copyrighted'::text)) AS reference_only,
    round(((100.0 * (count(*) FILTER (WHERE ((copyright = 'free'::text) AND (status = 'indexed'::text))))::numeric) / (NULLIF(count(*) FILTER (WHERE (copyright = 'free'::text)), 0))::numeric), 1) AS coverage_pct
   FROM reg_catalog;

CREATE OR REPLACE VIEW public.report_kpis AS  WITH reg AS (
         SELECT report_registry.source,
            report_registry.report_type,
            report_registry.title,
            report_registry.period,
            report_registry.created_at,
            report_registry.id
           FROM report_registry
        ), lt AS (
         SELECT max(reg.created_at) FILTER (WHERE (reg.report_type = 'weekly'::text)) AS weekly_at,
            max(reg.created_at) FILTER (WHERE (reg.report_type = 'monthly'::text)) AS monthly_at,
            max(reg.created_at) FILTER (WHERE (reg.report_type = 'quarterly'::text)) AS quarterly_at,
            max(reg.created_at) FILTER (WHERE (reg.report_type = 'department'::text)) AS department_at,
            max(reg.created_at) FILTER (WHERE (reg.report_type = 'supplier'::text)) AS supplier_at,
            max(reg.created_at) FILTER (WHERE (reg.report_type = 'customer'::text)) AS customer_at,
            max(reg.created_at) FILTER (WHERE (reg.report_type = 'ai'::text)) AS ai_at,
            max(reg.created_at) FILTER (WHERE (reg.source = 'exec'::text)) AS exec_at,
            max(reg.created_at) FILTER (WHERE (reg.source = 'finance'::text)) AS finance_at
           FROM reg
        ), daily AS (
         SELECT max(agent_actions.created_at) AS daily_at
           FROM agent_actions
          WHERE (agent_actions.kind = 'exec_briefing'::text)
        )
 SELECT ( SELECT count(*) AS count
           FROM reg) AS total_reports,
    ( SELECT count(*) AS count
           FROM reg
          WHERE (reg.created_at > (now() - '30 days'::interval))) AS reports_30d,
    ( SELECT count(DISTINCT reg.report_type) AS count
           FROM reg) AS report_types,
    d.daily_at,
    lt.weekly_at,
    lt.monthly_at,
    lt.quarterly_at,
    lt.department_at,
    lt.supplier_at,
    lt.customer_at,
    lt.ai_at,
    lt.exec_at,
    lt.finance_at,
    (d.daily_at > (now() - '36:00:00'::interval)) AS daily_fresh,
    (lt.weekly_at > (now() - '8 days'::interval)) AS weekly_fresh,
    (lt.monthly_at > date_trunc('month'::text, now())) AS monthly_fresh,
    (lt.quarterly_at > (now() - '95 days'::interval)) AS quarterly_fresh,
    (lt.department_at > (now() - '2 days'::interval)) AS department_fresh,
    (lt.supplier_at > (now() - '2 days'::interval)) AS supplier_fresh,
    (lt.customer_at > (now() - '2 days'::interval)) AS customer_fresh,
    (lt.ai_at > (now() - '2 days'::interval)) AS ai_fresh,
    (((((((
        CASE
            WHEN COALESCE((d.daily_at > (now() - '36:00:00'::interval)), false) THEN 0
            ELSE 1
        END +
        CASE
            WHEN COALESCE((lt.weekly_at > (now() - '8 days'::interval)), false) THEN 0
            ELSE 1
        END) +
        CASE
            WHEN COALESCE((lt.monthly_at > date_trunc('month'::text, now())), false) THEN 0
            ELSE 1
        END) +
        CASE
            WHEN COALESCE((lt.quarterly_at > (now() - '95 days'::interval)), false) THEN 0
            ELSE 1
        END) +
        CASE
            WHEN COALESCE((lt.department_at > (now() - '2 days'::interval)), false) THEN 0
            ELSE 1
        END) +
        CASE
            WHEN COALESCE((lt.supplier_at > (now() - '2 days'::interval)), false) THEN 0
            ELSE 1
        END) +
        CASE
            WHEN COALESCE((lt.customer_at > (now() - '2 days'::interval)), false) THEN 0
            ELSE 1
        END) +
        CASE
            WHEN COALESCE((lt.ai_at > (now() - '2 days'::interval)), false) THEN 0
            ELSE 1
        END) AS stale_count
   FROM lt,
    daily d;

CREATE OR REPLACE VIEW public.report_registry AS  SELECT 'narrative'::text AS source,
    board_reports.report_type,
    board_reports.title,
    COALESCE((board_reports.week_start)::text, to_char(board_reports.created_at, 'YYYY-MM-DD'::text)) AS period,
    board_reports.created_at,
    board_reports.id
   FROM board_reports
UNION ALL
 SELECT 'exec'::text AS source,
    'exec_summary'::text AS report_type,
    ((exec_reports.officer || ' — '::text) || exec_reports.period) AS title,
    exec_reports.period,
    exec_reports.created_at,
    exec_reports.id
   FROM exec_reports
UNION ALL
 SELECT 'finance'::text AS source,
    COALESCE(finance_reports.kind, 'financial'::text) AS report_type,
    ((('Financial — '::text || COALESCE(finance_reports.kind, ''::text)) || ' '::text) || COALESCE((finance_reports.period_start)::text, ''::text)) AS title,
    COALESCE((finance_reports.period_start)::text, to_char(finance_reports.created_at, 'YYYY-MM-DD'::text)) AS period,
    finance_reports.created_at,
    finance_reports.id
   FROM finance_reports;

CREATE OR REPLACE VIEW public.security_kpis AS  SELECT ( SELECT count(*) AS count
           FROM (pg_class c
             JOIN pg_namespace n ON ((n.oid = c.relnamespace)))
          WHERE ((n.nspname = 'public'::name) AND (c.relkind = 'r'::"char"))) AS tables,
    ( SELECT count(*) AS count
           FROM (pg_class c
             JOIN pg_namespace n ON ((n.oid = c.relnamespace)))
          WHERE ((n.nspname = 'public'::name) AND (c.relkind = 'r'::"char") AND c.relrowsecurity)) AS rls_enabled,
    round(((100.0 * (( SELECT count(*) AS count
           FROM (pg_class c
             JOIN pg_namespace n ON ((n.oid = c.relnamespace)))
          WHERE ((n.nspname = 'public'::name) AND (c.relkind = 'r'::"char") AND c.relrowsecurity)))::numeric) / (NULLIF(( SELECT count(*) AS count
           FROM (pg_class c
             JOIN pg_namespace n ON ((n.oid = c.relnamespace)))
          WHERE ((n.nspname = 'public'::name) AND (c.relkind = 'r'::"char"))), 0))::numeric), 1) AS rls_coverage_pct,
    ( SELECT count(*) AS count
           FROM (pg_class c
             JOIN pg_namespace n ON ((n.oid = c.relnamespace)))
          WHERE ((n.nspname = 'public'::name) AND (c.relkind = 'r'::"char") AND c.relrowsecurity AND (NOT (EXISTS ( SELECT 1
                   FROM pg_policy pol
                  WHERE (pol.polrelid = c.oid)))))) AS rls_deny_default,
    ( SELECT count(*) AS count
           FROM (pg_proc p
             JOIN pg_namespace n ON ((n.oid = p.pronamespace)))
          WHERE ((n.nspname = 'public'::name) AND p.prosecdef AND ((p.proconfig IS NULL) OR (NOT (EXISTS ( SELECT 1
                   FROM unnest(p.proconfig) cc(cc)
                  WHERE (cc.cc ~~ 'search_path=%'::text))))))) AS secdef_mutable_searchpath,
    ( SELECT count(*) AS count
           FROM security_events
          WHERE ((security_events.severity = ANY (ARRAY['high'::text, 'critical'::text])) AND (security_events.created_at >= (now() - '7 days'::interval)))) AS high_sev_events_7d,
    ( SELECT count(*) AS count
           FROM security_events
          WHERE (security_events.created_at >= (now() - '7 days'::interval))) AS events_7d,
    ( SELECT count(*) AS count
           FROM fraud_flags
          WHERE (COALESCE(fraud_flags.status, ''::text) <> ALL (ARRAY['resolved'::text, 'dismissed'::text]))) AS open_fraud_flags,
    ( SELECT count(*) AS count
           FROM agent_actions
          WHERE ((agent_actions.kind = 'security_incident'::text) AND (agent_actions.status = ANY (ARRAY['pending'::text, 'needs_review'::text])))) AS open_incidents,
    ( SELECT count(*) AS count
           FROM error_events
          WHERE (error_events.created_at >= (now() - '24:00:00'::interval))) AS errors_24h,
    ( SELECT count(*) AS count
           FROM auth.users
          WHERE (users.banned_until IS NOT NULL)) AS banned_users,
    ( SELECT count(*) AS count
           FROM auth.users
          WHERE (users.last_sign_in_at >= (now() - '7 days'::interval))) AS active_users_7d,
    COALESCE(( SELECT count(*) AS count
           FROM auth.audit_log_entries
          WHERE ((audit_log_entries.created_at >= (now() - '7 days'::interval)) AND ((audit_log_entries.payload ->> 'action'::text) ~~* '%fail%'::text))), (0)::bigint) AS failed_logins_7d,
    ( SELECT count(*) AS count
           FROM app_secrets) AS secrets_count;

CREATE OR REPLACE VIEW public.strategy_kpis AS  WITH sup AS (
         SELECT quotes.supplier_id,
            count(*) AS c
           FROM quotes
          WHERE ((quotes.created_at > (now() - '90 days'::interval)) AND (quotes.supplier_id IS NOT NULL))
          GROUP BY quotes.supplier_id
        ), agg AS (
         SELECT count(*) AS active,
            COALESCE(round(((100.0 * (max(sup.c))::numeric) / NULLIF(sum(sup.c), (0)::numeric)), 1), (0)::numeric) AS top_share
           FROM sup
        ), fin AS (
         SELECT finance_kpis.cash,
            finance_kpis.monthly_burn,
            finance_kpis.runway_months,
            finance_kpis.revenue_30d,
            finance_kpis.margin_pct
           FROM finance_kpis
        ), rk AS (
         SELECT count(*) FILTER (WHERE (strategy_risks.status = 'open'::text)) AS open_risks,
            max(strategy_risks.score) AS top_score,
            (array_agg(strategy_risks.title ORDER BY strategy_risks.score DESC))[1] AS top_title
           FROM strategy_risks
          WHERE (strategy_risks.status = 'open'::text)
        )
 SELECT agg.active AS active_suppliers_90d,
    agg.top_share AS top_supplier_share_pct,
    jsonb_array_length(COALESCE((fn_strategy_metrics() -> 'under_supplied'::text), '[]'::jsonb)) AS under_supplied_categories,
    fin.cash,
    fin.monthly_burn,
        CASE
            WHEN ((fin.cash > (0)::numeric) AND (fin.monthly_burn > (0)::numeric)) THEN round((fin.cash / fin.monthly_burn), 1)
            ELSE fin.runway_months
        END AS runway_months,
    fin.revenue_30d,
    fin.margin_pct,
    COALESCE(rk.open_risks, (0)::bigint) AS open_risks,
    COALESCE(rk.top_score, 0) AS top_risk_score,
    rk.top_title AS top_risk,
    ( SELECT count(*) AS count
           FROM market_intel
          WHERE ((market_intel.kind = 'competitor'::text) AND (market_intel.status <> 'dismissed'::text))) AS competitor_intel,
    ( SELECT count(*) AS count
           FROM market_intel
          WHERE ((market_intel.kind = 'trend'::text) AND (market_intel.status <> 'dismissed'::text))) AS market_trends,
    ( SELECT count(*) AS count
           FROM market_intel
          WHERE (market_intel.status = 'open'::text)) AS open_intel,
    ( SELECT max(simulations.created_at) AS max
           FROM simulations) AS last_simulation_at
   FROM agg,
    fin,
    rk;

CREATE OR REPLACE VIEW public.supplier_health AS  WITH s AS (
         SELECT l.id AS supplier_id,
            l.company_name,
            l.banned,
            l.matching_blocked,
            COALESCE(l.chat_strikes, 0) AS strikes,
            l.approval_status,
            l.claimed,
            l.license_expiry,
            l.license_doc_path,
            l.insurance_expiry,
            l.insurance_doc_path,
            l.egr_doc_path,
            l.trn,
            l.iso_expiry,
            l.manufacturer_auth_expiry,
            l.registration_expires_at,
            l.portal_updated_at,
            COALESCE(l.rv_response_rate, (0)::numeric) AS rv_rate,
            ((l.rv_responded IS NOT NULL) OR (l.rv_reveals IS NOT NULL)) AS has_rv,
            p.perf_score,
            p.rating,
            p.quoted,
            p.quote_rate,
            ( SELECT max(q.created_at) AS max
                   FROM quotes q
                  WHERE (q.supplier_id = l.id)) AS last_quote_at,
            ( SELECT round(avg(((((COALESCE((r.r_quality)::integer, r.rating) + COALESCE((r.r_documentation)::integer, r.rating)) + COALESCE((r.r_compliance)::integer, r.rating)))::numeric / 3.0)), 2) AS round
                   FROM reviews r
                  WHERE (r.supplier_id = l.id)) AS review_quality
           FROM (leads l
             LEFT JOIN supplier_perf p ON ((p.supplier_id = l.id)))
          WHERE ((l.claimed = true) AND (COALESCE(l.approval_status, ''::text) = 'approved'::text))
        ), scored AS (
         SELECT s.supplier_id,
            s.company_name,
            s.banned,
            s.matching_blocked,
            s.strikes,
            s.approval_status,
            s.claimed,
            s.license_expiry,
            s.license_doc_path,
            s.insurance_expiry,
            s.insurance_doc_path,
            s.egr_doc_path,
            s.trn,
            s.iso_expiry,
            s.manufacturer_auth_expiry,
            s.registration_expires_at,
            s.portal_updated_at,
            s.rv_rate,
            s.has_rv,
            s.perf_score,
            s.rating,
            s.quoted,
            s.quote_rate,
            s.last_quote_at,
            s.review_quality,
            round(GREATEST((COALESCE(s.perf_score, (0)::numeric) * (100)::numeric), ((COALESCE(s.review_quality, (0)::numeric) / 5.0) * (100)::numeric), ((COALESCE(s.rating, (0)::numeric) / 5.0) * (100)::numeric)), 1) AS quality,
            round((GREATEST(0, ((((((
                CASE
                    WHEN ((s.license_doc_path IS NOT NULL) AND ((s.license_expiry IS NULL) OR (s.license_expiry >= CURRENT_DATE))) THEN 25
                    ELSE 0
                END +
                CASE
                    WHEN ((s.insurance_doc_path IS NOT NULL) AND ((s.insurance_expiry IS NULL) OR (s.insurance_expiry >= CURRENT_DATE))) THEN 25
                    ELSE 0
                END) +
                CASE
                    WHEN (s.egr_doc_path IS NOT NULL) THEN 25
                    ELSE 0
                END) +
                CASE
                    WHEN (s.trn IS NOT NULL) THEN 25
                    ELSE 0
                END) - (LEAST(s.strikes, 3) * 8)) -
                CASE
                    WHEN ((s.iso_expiry IS NOT NULL) AND (s.iso_expiry < CURRENT_DATE)) THEN 10
                    ELSE 0
                END) -
                CASE
                    WHEN ((s.manufacturer_auth_expiry IS NOT NULL) AND (s.manufacturer_auth_expiry < CURRENT_DATE)) THEN 10
                    ELSE 0
                END)))::numeric, 1) AS compliance,
            round((
                CASE
                    WHEN s.has_rv THEN s.rv_rate
                    ELSE COALESCE(s.quote_rate, (0)::numeric)
                END * (100)::numeric), 1) AS response,
            round(((
                CASE
                    WHEN (GREATEST(COALESCE(s.last_quote_at, s.portal_updated_at), s.portal_updated_at) >= (now() - '30 days'::interval)) THEN 60
                    WHEN (GREATEST(COALESCE(s.last_quote_at, s.portal_updated_at), s.portal_updated_at) >= (now() - '60 days'::interval)) THEN 40
                    WHEN (GREATEST(COALESCE(s.last_quote_at, s.portal_updated_at), s.portal_updated_at) >= (now() - '120 days'::interval)) THEN 20
                    ELSE 5
                END +
                CASE
                    WHEN ((s.registration_expires_at IS NULL) OR (s.registration_expires_at >= now())) THEN 40
                    ELSE 0
                END))::numeric, 1) AS retention
           FROM s
        )
 SELECT supplier_id,
    company_name,
    quality,
    compliance,
    response,
    retention,
    round(((((quality * 0.30) + (compliance * 0.30)) + (response * 0.20)) + (retention * 0.20)), 1) AS health,
        CASE
            WHEN (banned OR matching_blocked OR (strikes >= 3) OR (compliance < (40)::numeric) OR (round(((((quality * 0.30) + (compliance * 0.30)) + (response * 0.20)) + (retention * 0.20)), 1) < (40)::numeric)) THEN 'high'::text
            WHEN ((compliance < (75)::numeric) OR (strikes > 0) OR (retention < (30)::numeric) OR (round(((((quality * 0.30) + (compliance * 0.30)) + (response * 0.20)) + (retention * 0.20)), 1) < (65)::numeric)) THEN 'medium'::text
            ELSE 'low'::text
        END AS risk_tier,
    ((last_quote_at IS NULL) AND (portal_updated_at < (now() - '45 days'::interval))) AS dormant,
    strikes,
    banned,
    matching_blocked,
    last_quote_at,
    portal_updated_at
   FROM scored;

CREATE OR REPLACE VIEW public.supplier_kpis AS  SELECT count(*) AS active_suppliers,
    round(avg(quality), 1) AS avg_quality,
    round(avg(response), 1) AS avg_response_score,
    round(((100.0 * (count(*) FILTER (WHERE (compliance >= (80)::numeric)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS pct_compliant,
    round(((100.0 * (count(*) FILTER (WHERE (NOT dormant)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS retention_rate,
    count(*) FILTER (WHERE (risk_tier = 'high'::text)) AS risk_high,
    count(*) FILTER (WHERE (risk_tier = 'medium'::text)) AS risk_medium,
    count(*) FILTER (WHERE (risk_tier = 'low'::text)) AS risk_low,
    count(*) FILTER (WHERE dormant) AS dormant_count,
    round(avg(health), 1) AS avg_health
   FROM supplier_health;

CREATE OR REPLACE VIEW public.supplier_perf AS  WITH base AS (
         SELECT l.id AS supplier_id,
            l.company_name,
            COALESCE(l.app_rating, l.rating) AS rating,
            ( SELECT count(*) AS count
                   FROM inquiry_matches m
                  WHERE (m.supplier_id = l.id)) AS matched,
            ( SELECT count(*) AS count
                   FROM quotes q
                  WHERE (q.supplier_id = l.id)) AS quoted,
            ( SELECT count(*) AS count
                   FROM inquiries i
                  WHERE (i.hired_supplier_id = l.id)) AS won,
            ( SELECT count(*) AS count
                   FROM reviews r
                  WHERE (r.supplier_id = l.id)) AS review_count
           FROM leads l
          WHERE (l.claimed = true)
        )
 SELECT supplier_id,
    company_name,
    rating,
    matched,
    quoted,
    won,
    review_count,
    round(((quoted)::numeric / (NULLIF(matched, 0))::numeric), 3) AS quote_rate,
    round(((won)::numeric / (NULLIF(quoted, 0))::numeric), 3) AS win_rate,
    round(((((COALESCE(rating, (0)::numeric) / 5.0) * 0.50) + (COALESCE(((won)::numeric / (NULLIF(quoted, 0))::numeric), (0)::numeric) * 0.35)) + (((LEAST(quoted, (10)::bigint))::numeric / 10.0) * 0.15)), 3) AS perf_score
   FROM base b;

CREATE OR REPLACE VIEW public.supplier_reputation AS  WITH disp AS (
         SELECT transactions.supplier_id,
            count(*) FILTER (WHERE ((transactions.refund_status IS NOT NULL) AND (transactions.refund_status <> 'none'::text))) AS disputes,
            count(*) AS reveals
           FROM transactions
          GROUP BY transactions.supplier_id
        )
 SELECT l.id AS supplier_id,
    l.company_name,
    count(r.id) AS review_count,
    round(avg(r.rating), 2) AS overall,
    round(avg(r.r_communication), 2) AS communication,
    round(avg(r.r_quality), 2) AS quality,
    round(avg(r.r_punctuality), 2) AS punctuality,
    round(avg(r.r_documentation), 2) AS documentation,
    round(avg(r.r_after_sales), 2) AS after_sales,
    round(avg(r.r_compliance), 2) AS compliance,
    COALESCE(sp.quote_rate, (0)::numeric) AS responsiveness,
    COALESCE(d.disputes, (0)::bigint) AS disputes,
        CASE
            WHEN (COALESCE(d.reveals, (0)::bigint) > 0) THEN round(((100.0 * (d.disputes)::numeric) / (d.reveals)::numeric), 1)
            ELSE (0)::numeric
        END AS dispute_rate_pct,
    round(LEAST((100)::numeric, GREATEST((0)::numeric, (((COALESCE(avg(r.rating), (0)::numeric) * (16)::numeric) + (COALESCE(sp.quote_rate, (0)::numeric) * 0.2)) -
        CASE
            WHEN (COALESCE(d.reveals, (0)::bigint) > 0) THEN (((100.0 * (d.disputes)::numeric) / (d.reveals)::numeric) * 0.3)
            ELSE (0)::numeric
        END))), 1) AS reputation_index
   FROM (((leads l
     LEFT JOIN reviews r ON ((r.supplier_id = l.id)))
     LEFT JOIN supplier_perf sp ON ((sp.supplier_id = l.id)))
     LEFT JOIN disp d ON ((d.supplier_id = l.id)))
  GROUP BY l.id, l.company_name, sp.quote_rate, d.disputes, d.reveals;

CREATE OR REPLACE VIEW public.supplier_twin AS  SELECT l.id AS supplier_id,
    l.company_name,
    l.emirate AS home_emirate,
    l.categories AS specialties,
    sp.matched,
    sp.quoted,
    sp.won,
    sp.quote_rate,
    sp.win_rate,
    sp.perf_score,
    rep.reputation_index,
    rep.overall AS avg_rating,
    rep.review_count,
    rep.disputes,
    rep.dispute_rate_pct,
    q.quotes_count,
    q.avg_quote_value,
    q.min_quote_value,
    q.max_quote_value,
    q.avg_response_hours,
    q.busiest_month,
    wq.typical_project_size,
    pr.preferred_regions
   FROM (((((leads l
     LEFT JOIN supplier_perf sp ON ((sp.supplier_id = l.id)))
     LEFT JOIN supplier_reputation rep ON ((rep.supplier_id = l.id)))
     LEFT JOIN LATERAL ( SELECT count(*) AS quotes_count,
            round(avg(qq.quote_amount), 0) AS avg_quote_value,
            min(qq.quote_amount) AS min_quote_value,
            max(qq.quote_amount) AS max_quote_value,
            round(avg((EXTRACT(epoch FROM (qq.created_at - i.created_at)) / 3600.0)), 1) AS avg_response_hours,
            mode() WITHIN GROUP (ORDER BY ((EXTRACT(month FROM qq.created_at))::integer)) AS busiest_month
           FROM (quotes qq
             JOIN inquiries i ON ((i.id = qq.inquiry_id)))
          WHERE (qq.supplier_id = l.id)) q ON (true))
     LEFT JOIN LATERAL ( SELECT round(avg(qq.quote_amount), 0) AS typical_project_size
           FROM (quotes qq
             JOIN inquiries i ON ((i.id = qq.inquiry_id)))
          WHERE ((qq.supplier_id = l.id) AND (i.hired_supplier_id = l.id))) wq ON (true))
     LEFT JOIN LATERAL ( SELECT array_agg(DISTINCT i.emirate) FILTER (WHERE (i.emirate IS NOT NULL)) AS preferred_regions
           FROM (quotes qq
             JOIN inquiries i ON ((i.id = qq.inquiry_id)))
          WHERE (qq.supplier_id = l.id)) pr ON (true));

CREATE OR REPLACE VIEW public.v_ai_agent_health AS  WITH runs AS (
         SELECT agent_runs.agent,
            count(*) FILTER (WHERE (agent_runs.started_at > (now() - '30 days'::interval))) AS runs_30d,
            count(*) FILTER (WHERE ((agent_runs.started_at > (now() - '30 days'::interval)) AND (agent_runs.status = 'error'::text))) AS errors_30d,
            max(agent_runs.started_at) AS last_run
           FROM agent_runs
          GROUP BY agent_runs.agent
        ), acts AS (
         SELECT agent_actions.agent,
            count(*) FILTER (WHERE (agent_actions.created_at > (now() - '30 days'::interval))) AS actions_30d,
            count(*) FILTER (WHERE ((agent_actions.created_at > (now() - '30 days'::interval)) AND (agent_actions.decided_at IS NOT NULL))) AS decided_30d,
            count(*) FILTER (WHERE ((agent_actions.created_at > (now() - '30 days'::interval)) AND (lower(COALESCE(agent_actions.status, ''::text)) = ANY (ARRAY['rejected'::text, 'dismissed'::text, 'declined'::text, 'overridden'::text])))) AS rejected_30d,
            round(avg(agent_actions.confidence) FILTER (WHERE (agent_actions.created_at > (now() - '30 days'::interval))), 1) AS avg_confidence
           FROM agent_actions
          GROUP BY agent_actions.agent
        )
 SELECT COALESCE(r.agent, a.agent) AS agent,
    COALESCE(r.runs_30d, (0)::bigint) AS runs_30d,
    COALESCE(r.errors_30d, (0)::bigint) AS errors_30d,
    r.last_run,
    COALESCE(a.decided_30d, (0)::bigint) AS decided_30d,
    COALESCE(a.rejected_30d, (0)::bigint) AS rejected_30d,
    round(
        CASE
            WHEN (a.actions_30d > 0) THEN (((a.rejected_30d)::numeric / (a.actions_30d)::numeric) * (100)::numeric)
            ELSE NULL::numeric
        END, 1) AS override_pct,
    a.avg_confidence,
    COALESCE(a.actions_30d, (0)::bigint) AS actions_30d
   FROM (runs r
     FULL JOIN acts a ON ((a.agent = r.agent)))
  ORDER BY (round(
        CASE
            WHEN (a.actions_30d > 0) THEN (((a.rejected_30d)::numeric / (a.actions_30d)::numeric) * (100)::numeric)
            ELSE NULL::numeric
        END, 1)) DESC NULLS LAST, COALESCE(r.runs_30d, (0)::bigint) DESC;

CREATE OR REPLACE VIEW public.v_ai_observability AS  SELECT ( SELECT count(*) AS count
           FROM agent_runs
          WHERE (agent_runs.started_at > (now() - '24:00:00'::interval))) AS runs_24h,
    ( SELECT count(*) AS count
           FROM agent_runs
          WHERE ((agent_runs.started_at > (now() - '24:00:00'::interval)) AND (agent_runs.status = 'error'::text))) AS errors_24h,
    ( SELECT count(*) AS count
           FROM agent_actions
          WHERE (lower(COALESCE(agent_actions.status, ''::text)) = ANY (ARRAY['pending'::text, 'needs_review'::text]))) AS open_approvals,
    ( SELECT round(avg(v_ai_agent_health.override_pct), 1) AS round
           FROM v_ai_agent_health
          WHERE (v_ai_agent_health.override_pct IS NOT NULL)) AS avg_override_pct,
    ( SELECT round(avg(v_eval_latest.score), 1) AS round
           FROM v_eval_latest) AS avg_eval_score,
    ( SELECT round(avg(v_kb_confidence.confidence), 1) AS round
           FROM v_kb_confidence) AS kb_avg_confidence,
    ( SELECT count(*) AS count
           FROM v_kb_review_due) AS kb_review_due,
    ( SELECT count(*) AS count
           FROM kb_chunks
          WHERE (kb_chunks.embedding_gte IS NOT NULL)) AS kb_embedded,
    ( SELECT count(*) AS count
           FROM kb_chunks) AS kb_total,
    ( SELECT count(*) AS count
           FROM kb_usage_log
          WHERE (kb_usage_log.created_at > (now() - '7 days'::interval))) AS kb_queries_7d;

CREATE OR REPLACE VIEW public.v_ai_quality_proxy AS  SELECT agent,
    count(*) FILTER (WHERE (decided_at IS NOT NULL)) AS decided_30d,
    count(*) FILTER (WHERE (lower(COALESCE(status, ''::text)) = ANY (ARRAY['rejected'::text, 'dismissed'::text, 'declined'::text, 'overridden'::text]))) AS rejected_30d,
    round(
        CASE
            WHEN (count(*) FILTER (WHERE (decided_at IS NOT NULL)) > 0) THEN (((count(*) FILTER (WHERE (lower(COALESCE(status, ''::text)) = ANY (ARRAY['rejected'::text, 'dismissed'::text, 'declined'::text, 'overridden'::text]))))::numeric / (count(*) FILTER (WHERE (decided_at IS NOT NULL)))::numeric) * (100)::numeric)
            ELSE NULL::numeric
        END, 1) AS override_pct
   FROM agent_actions
  WHERE (created_at > (now() - '30 days'::interval))
  GROUP BY agent
  ORDER BY (round(
        CASE
            WHEN (count(*) FILTER (WHERE (decided_at IS NOT NULL)) > 0) THEN (((count(*) FILTER (WHERE (lower(COALESCE(status, ''::text)) = ANY (ARRAY['rejected'::text, 'dismissed'::text, 'declined'::text, 'overridden'::text]))))::numeric / (count(*) FILTER (WHERE (decided_at IS NOT NULL)))::numeric) * (100)::numeric)
            ELSE NULL::numeric
        END, 1)) DESC NULLS LAST;

CREATE OR REPLACE VIEW public.v_auth_watch AS  SELECT customer_phone_otps.created_at AS at,
    'otp_high_attempts'::text AS signal,
        CASE
            WHEN (customer_phone_otps.attempts >= 5) THEN 'high'::text
            ELSE 'medium'::text
        END AS severity,
    COALESCE(customer_phone_otps.phone, ''::text) AS subject,
    jsonb_build_object('table', 'customer_phone_otps', 'attempts', customer_phone_otps.attempts, 'consumed', customer_phone_otps.consumed, 'customer_id', customer_phone_otps.customer_id) AS detail
   FROM customer_phone_otps
  WHERE ((customer_phone_otps.attempts >= 3) AND (customer_phone_otps.created_at > (now() - '30 days'::interval)))
UNION ALL
 SELECT phone_verifications.created_at AS at,
    'verify_high_attempts'::text AS signal,
        CASE
            WHEN (phone_verifications.attempts >= 5) THEN 'high'::text
            ELSE 'medium'::text
        END AS severity,
    COALESCE(phone_verifications.email, phone_verifications.phone, ''::text) AS subject,
    jsonb_build_object('table', 'phone_verifications', 'attempts', phone_verifications.attempts, 'user_kind', phone_verifications.user_kind, 'used', (phone_verifications.used_at IS NOT NULL)) AS detail
   FROM phone_verifications
  WHERE ((phone_verifications.attempts >= 3) AND (phone_verifications.created_at > (now() - '30 days'::interval)))
UNION ALL
 SELECT security_events.created_at AS at,
    security_events.kind AS signal,
    COALESCE(security_events.severity,
        CASE
            WHEN (security_events.kind = 'login_failed'::text) THEN 'medium'::text
            ELSE 'info'::text
        END) AS severity,
    COALESCE(security_events.subject, ''::text) AS subject,
    COALESCE(security_events.detail, '{}'::jsonb) AS detail
   FROM security_events
  WHERE ((security_events.kind = ANY (ARRAY['admin_login'::text, 'login_failed'::text])) AND (security_events.created_at > (now() - '30 days'::interval)));

CREATE OR REPLACE VIEW public.v_customer_ltv AS  SELECT id AS customer_id,
    full_name,
    email,
    ( SELECT count(*) AS count
           FROM inquiries i
          WHERE (i.customer_id = c.id)) AS inquiries,
    ( SELECT count(*) AS count
           FROM inquiries i
          WHERE ((i.customer_id = c.id) AND ((i.completed_at IS NOT NULL) OR (i.outcome = 'won'::text)))) AS completed,
    ( SELECT count(*) AS count
           FROM transactions t
          WHERE ((t.customer_id = c.id) AND (t.fee_status = 'paid'::text))) AS paid_reveals,
    (COALESCE(( SELECT sum(t.reveal_fee) AS sum
           FROM transactions t
          WHERE ((t.customer_id = c.id) AND (t.fee_status = 'paid'::text))), (0)::numeric))::numeric(12,2) AS revenue_to_date_aed,
    GREATEST(( SELECT max(i.created_at) AS max
           FROM inquiries i
          WHERE (i.customer_id = c.id)), ( SELECT max(t.revealed_at) AS max
           FROM transactions t
          WHERE (t.customer_id = c.id))) AS last_activity,
        CASE
            WHEN (COALESCE(( SELECT sum(t.reveal_fee) AS sum
               FROM transactions t
              WHERE ((t.customer_id = c.id) AND (t.fee_status = 'paid'::text))), (0)::numeric) >= (2000)::numeric) THEN 'high'::text
            WHEN (COALESCE(( SELECT sum(t.reveal_fee) AS sum
               FROM transactions t
              WHERE ((t.customer_id = c.id) AND (t.fee_status = 'paid'::text))), (0)::numeric) >= (500)::numeric) THEN 'medium'::text
            WHEN (COALESCE(( SELECT sum(t.reveal_fee) AS sum
               FROM transactions t
              WHERE ((t.customer_id = c.id) AND (t.fee_status = 'paid'::text))), (0)::numeric) > (0)::numeric) THEN 'low'::text
            ELSE 'none'::text
        END AS value_tier
   FROM customers c
  ORDER BY ((COALESCE(( SELECT sum(t.reveal_fee) AS sum
           FROM transactions t
          WHERE ((t.customer_id = c.id) AND (t.fee_status = 'paid'::text))), (0)::numeric))::numeric(12,2)) DESC;

CREATE OR REPLACE VIEW public.v_email_deadletter AS  SELECT id,
    type,
    to_email,
    to_role,
    subject,
    attempts,
    last_error,
    created_at
   FROM notifications
  WHERE (status = 'failed'::text)
  ORDER BY created_at DESC;

CREATE OR REPLACE VIEW public.v_eval_latest AS  SELECT prompt_key,
    score,
    cases_total,
    created_at
   FROM ( SELECT prompt_eval_runs.id,
            prompt_eval_runs.prompt_key,
            prompt_eval_runs.version,
            prompt_eval_runs.score,
            prompt_eval_runs.cases_total,
            prompt_eval_runs.detail,
            prompt_eval_runs.created_at,
            row_number() OVER (PARTITION BY prompt_eval_runs.prompt_key ORDER BY prompt_eval_runs.created_at DESC) AS rn
           FROM prompt_eval_runs) x
  WHERE (rn = 1)
  ORDER BY score NULLS FIRST;

CREATE OR REPLACE VIEW public.v_fraud_score AS  SELECT subject_type,
    subject_id,
    open_flags,
    latest_flag,
    reasons,
    (LEAST((100)::bigint, raw))::integer AS score,
        CASE
            WHEN (LEAST((100)::bigint, raw) >= 60) THEN 'high'::text
            WHEN (LEAST((100)::bigint, raw) >= 25) THEN 'medium'::text
            ELSE 'low'::text
        END AS tier
   FROM ( SELECT fraud_flags.subject_type,
            fraud_flags.subject_id,
            count(*) AS open_flags,
            max(fraud_flags.created_at) AS latest_flag,
            array_agg(DISTINCT fraud_flags.kind) AS reasons,
            sum(
                CASE lower(fraud_flags.severity)
                    WHEN 'critical'::text THEN 60
                    WHEN 'high'::text THEN 40
                    WHEN 'medium'::text THEN 15
                    WHEN 'low'::text THEN 5
                    ELSE 10
                END) AS raw
           FROM fraud_flags
          WHERE (COALESCE(fraud_flags.status, 'open'::text) <> ALL (ARRAY['resolved'::text, 'dismissed'::text, 'closed'::text, 'false_positive'::text]))
          GROUP BY fraud_flags.subject_type, fraud_flags.subject_id) s
  ORDER BY ((LEAST((100)::bigint, raw))::integer) DESC;

CREATE OR REPLACE VIEW public.v_invite_funnel AS  SELECT COALESCE(tt.label, u.code) AS trade,
    u.code AS trade_code,
    count(DISTINCT l.id) AS invited,
    count(DISTINCT l.id) FILTER (WHERE (l.invite_status = 'sent'::text)) AS delivered,
    count(DISTINCT l.id) FILTER (WHERE (l.invite_status = 'bounced'::text)) AS bounced,
    count(DISTINCT l.id) FILTER (WHERE ((COALESCE(l.claimed, false) = true) OR (l.registration_status IS NOT NULL))) AS registered
   FROM leads l,
    (LATERAL unnest(
        CASE
            WHEN (cardinality(l.invite_trades) = 0) THEN ARRAY['(unclassified)'::text]
            ELSE l.invite_trades
        END) u(code)
     LEFT JOIN taxonomy_trade tt ON ((tt.code = u.code)))
  WHERE (l.invite_status IS NOT NULL)
  GROUP BY COALESCE(tt.label, u.code), u.code;

CREATE OR REPLACE VIEW public.v_invite_nonresponders AS  SELECT id,
    company_name,
    email,
    COALESCE(phone_e164, phone) AS phone,
    invite_trades,
    invited_at,
    ((now())::date - (invited_at)::date) AS days_since_invite
   FROM leads l
  WHERE ((invite_status = ANY (ARRAY['sent'::text, 'queued'::text])) AND (COALESCE(claimed, false) = false) AND (invited_at IS NOT NULL) AND (invited_at < (now() - '7 days'::interval)))
  ORDER BY invited_at;

CREATE OR REPLACE VIEW public.v_kb_citation_check AS  SELECT id,
    category,
    "left"(title, 80) AS title,
    citation,
    source_kind,
    source_id,
    created_at
   FROM kb_chunks
  WHERE ((citation IS NULL) OR (length(btrim(COALESCE(citation, ''::text))) < 8))
  ORDER BY created_at DESC;

CREATE OR REPLACE VIEW public.v_kb_confidence AS  SELECT id,
    category,
    title,
    confidence,
    has_citation,
    effective_date,
    created_at,
        CASE
            WHEN (confidence >= 75) THEN 'high'::text
            WHEN (confidence >= 50) THEN 'medium'::text
            ELSE 'low'::text
        END AS band
   FROM ( SELECT kb_chunks.id,
            kb_chunks.category,
            "left"(kb_chunks.title, 80) AS title,
            LEAST(100, (((
                CASE
                    WHEN ((kb_chunks.citation IS NOT NULL) AND (length(btrim(kb_chunks.citation)) >= 8)) THEN 40
                    ELSE 0
                END +
                CASE
                    WHEN ((kb_chunks.title IS NOT NULL) AND (btrim(kb_chunks.title) <> ''::text)) THEN 20
                    ELSE 0
                END) +
                CASE
                    WHEN (length(COALESCE(kb_chunks.content, ''::text)) >= 200) THEN 20
                    ELSE 0
                END) +
                CASE
                    WHEN ((kb_chunks.effective_date IS NOT NULL) AND (kb_chunks.effective_date >= CURRENT_DATE)) THEN 20
                    WHEN (kb_chunks.effective_date IS NOT NULL) THEN 10
                    ELSE 0
                END)) AS confidence,
            ((kb_chunks.citation IS NOT NULL) AND (length(btrim(COALESCE(kb_chunks.citation, ''::text))) >= 8)) AS has_citation,
            kb_chunks.effective_date,
            kb_chunks.created_at
           FROM kb_chunks) s;

CREATE OR REPLACE VIEW public.v_kb_regulation_gaps AS  SELECT slug AS category,
    name,
    ( SELECT count(*) AS count
           FROM kb_chunks k
          WHERE ((k.category_norm = regexp_replace(lower(c.slug), '^cat:'::text, ''::text)) AND (k.source_kind = 'trade'::text))) AS trade_chunks
   FROM category_agents c
  WHERE ((requires_regulation IS TRUE) AND (NOT (EXISTS ( SELECT 1
           FROM kb_chunks k
          WHERE ((k.source_kind = 'regulation'::text) AND (k.category_norm IN ( SELECT regexp_replace(lower(c.slug), '^cat:'::text, ''::text) AS regexp_replace
                UNION
                 SELECT a.maps_to
                   FROM kb_category_aliases a
                  WHERE (a.category = regexp_replace(lower(c.slug), '^cat:'::text, ''::text)))))))))
  ORDER BY slug;

CREATE OR REPLACE VIEW public.v_kb_review_due AS  SELECT id,
    category,
    "left"(title, 80) AS title,
    effective_date,
    created_at,
    array_remove(ARRAY[
        CASE
            WHEN ((source_kind = 'regulation'::text) AND (effective_date IS NULL)) THEN 'undated'::text
            ELSE NULL::text
        END,
        CASE
            WHEN ((source_kind = 'regulation'::text) AND ((citation IS NULL) OR (length(btrim(COALESCE(citation, ''::text))) < 8))) THEN 'weak_citation'::text
            ELSE NULL::text
        END,
        CASE
            WHEN ((source_kind = 'regulation'::text) AND (effective_date IS NOT NULL) AND (effective_date < (CURRENT_DATE - '3 years'::interval))) THEN 'aging_regulation'::text
            ELSE NULL::text
        END], NULL::text) AS reasons
   FROM kb_chunks
  WHERE (((source_kind = 'regulation'::text) AND (effective_date IS NULL)) OR ((source_kind = 'regulation'::text) AND ((citation IS NULL) OR (length(btrim(COALESCE(citation, ''::text))) < 8))) OR ((source_kind = 'regulation'::text) AND (effective_date IS NOT NULL) AND (effective_date < (CURRENT_DATE - '3 years'::interval))))
  ORDER BY created_at DESC;

CREATE OR REPLACE VIEW public.v_kb_risk AS  SELECT id,
    category,
    source_kind,
    "left"(title, 80) AS title,
    effective_date,
        CASE
            WHEN (source_kind = 'regulation'::text) THEN 'high'::text
            WHEN (source_kind = ANY (ARRAY['material'::text, 'trade'::text])) THEN 'medium'::text
            ELSE 'low'::text
        END AS risk_tier,
        CASE
            WHEN (source_kind = 'regulation'::text) THEN 'compliance/legal'::text
            WHEN (source_kind = ANY (ARRAY['material'::text, 'trade'::text])) THEN 'technical/spec'::text
            ELSE 'general'::text
        END AS risk_reason
   FROM kb_chunks;

CREATE OR REPLACE VIEW public.v_llm_model_mix AS  SELECT fn,
    COALESCE(model_used, model_wanted) AS model,
    count(*) AS calls,
    count(*) FILTER (WHERE fell_back) AS fallbacks,
    count(*) FILTER (WHERE (NOT ok)) AS failures,
    round(avg(latency_ms)) AS avg_ms,
    sum(COALESCE(prompt_tokens, 0)) AS prompt_tokens,
    sum(COALESCE(output_tokens, 0)) AS output_tokens,
    sum(COALESCE(cached_tokens, 0)) AS cached_tokens,
    bool_or(COALESCE(cached, false)) AS uses_caching,
    max(created_at) AS last_seen
   FROM llm_calls
  WHERE (created_at > (now() - '30 days'::interval))
  GROUP BY fn, COALESCE(model_used, model_wanted);

CREATE OR REPLACE VIEW public.v_llm_offpolicy AS  SELECT m.fn,
    m.model,
    m.calls,
    m.last_seen
   FROM (v_llm_model_mix m
     LEFT JOIN llm_policy p ON (((p.model = m.model) AND p.approved)))
  WHERE (p.model IS NULL);

CREATE OR REPLACE VIEW public.v_memory_promotion_candidates AS  SELECT id,
    agent_key,
    kind,
    importance,
    source,
    created_at,
    "left"(content, 240) AS preview,
    length(content) AS content_len
   FROM agent_memory m
  WHERE (NOT (EXISTS ( SELECT 1
           FROM memory_promotions p
          WHERE (p.memory_id = m.id))))
  ORDER BY importance DESC NULLS LAST, created_at DESC;

CREATE OR REPLACE VIEW public.v_mkt_brand_by_category AS  SELECT i.category,
    qi.brand,
    count(*) AS line_count,
    count(DISTINCT q.supplier_id) AS suppliers,
    round(sum(COALESCE(qi.amount, (0)::numeric)), 2) AS total_amount
   FROM ((quote_items qi
     JOIN quotes q ON (((q.id)::text = qi.quote_id)))
     JOIN inquiries i ON ((i.id = q.inquiry_id)))
  WHERE ((qi.brand IS NOT NULL) AND (btrim(qi.brand) <> ''::text) AND (i.category IS NOT NULL))
  GROUP BY i.category, qi.brand
  ORDER BY i.category, (count(*)) DESC;

CREATE OR REPLACE VIEW public.v_mkt_over_budget AS  SELECT id AS inquiry_id,
    category,
    budget_aed,
    min_quote,
    (min_quote - budget_aed) AS overrun,
    created_at
   FROM ( SELECT i.id,
            i.category,
            i.created_at,
            (NULLIF(regexp_replace(COALESCE((regexp_match(i.budget, '([0-9][0-9,\.]{2,})'::text))[1], ''::text), '[^0-9]'::text, ''::text, 'g'::text), ''::text))::numeric AS budget_aed,
            ( SELECT min(q.quote_amount) AS min
                   FROM quotes q
                  WHERE ((q.inquiry_id = i.id) AND (COALESCE(q.status, ''::text) <> 'draft'::text))) AS min_quote
           FROM inquiries i
          WHERE ((i.budget IS NOT NULL) AND (btrim(i.budget) <> ''::text))) s
  WHERE ((budget_aed IS NOT NULL) AND (budget_aed >= (100)::numeric) AND (min_quote IS NOT NULL) AND (min_quote > budget_aed))
  ORDER BY (min_quote - budget_aed) DESC;

CREATE OR REPLACE VIEW public.v_mkt_response_by_category AS  WITH fq AS (
         SELECT i.id,
            i.category,
            i.created_at,
            ( SELECT min(q.created_at) AS min
                   FROM quotes q
                  WHERE (q.inquiry_id = i.id)) AS first_quote_at
           FROM inquiries i
          WHERE (i.category IS NOT NULL)
        )
 SELECT category,
    count(*) AS rfqs,
    count(first_quote_at) AS rfqs_quoted,
    round(avg((EXTRACT(epoch FROM (first_quote_at - created_at)) / 3600.0)) FILTER (WHERE (first_quote_at IS NOT NULL)), 1) AS avg_first_quote_hrs,
    round((((count(*) FILTER (WHERE (first_quote_at IS NULL)))::numeric / (NULLIF(count(*), 0))::numeric) * (100)::numeric), 1) AS no_quote_pct
   FROM fq
  GROUP BY category
  ORDER BY (round(avg((EXTRACT(epoch FROM (first_quote_at - created_at)) / 3600.0)) FILTER (WHERE (first_quote_at IS NOT NULL)), 1)) DESC NULLS LAST;

CREATE OR REPLACE VIEW public.v_mkt_underpriced AS  SELECT q.id AS quote_id,
    q.inquiry_id,
    i.category,
    q.supplier_id,
    q.quote_amount,
    (x.pc ->> 'median'::text) AS category_median,
    q.created_at
   FROM ((quotes q
     JOIN inquiries i ON ((i.id = q.inquiry_id)))
     CROSS JOIN LATERAL ( SELECT fn_price_confidence(i.category, q.quote_amount) AS pc) x)
  WHERE ((COALESCE(q.status, ''::text) <> 'draft'::text) AND (i.category IS NOT NULL) AND ((x.pc ->> 'band'::text) = 'suspiciously_low'::text))
  ORDER BY q.created_at DESC;

CREATE OR REPLACE VIEW public.v_slow_queries AS  SELECT queryid,
    calls,
    round((total_exec_time)::numeric, 1) AS total_ms,
    round((mean_exec_time)::numeric, 2) AS mean_ms,
    round((max_exec_time)::numeric, 2) AS max_ms,
    rows,
    "left"(query, 240) AS query
   FROM pg_stat_statements
  WHERE (calls > 1)
  ORDER BY mean_exec_time DESC
 LIMIT 50;

CREATE OR REPLACE VIEW public.v_supplier_billing AS  WITH cfg AS (
         SELECT COALESCE(( SELECT (NULLIF(app_secrets.value, ''::text))::date AS "nullif"
                   FROM app_secrets
                  WHERE (app_secrets.key = 'supplier_subscription_start'::text)), '2027-08-01'::date) AS start_date,
            COALESCE(( SELECT (NULLIF(app_secrets.value, ''::text))::numeric AS "nullif"
                   FROM app_secrets
                  WHERE (app_secrets.key = 'supplier_subscription_aed'::text)), (1000)::numeric) AS fee,
            COALESCE(( SELECT (NULLIF(app_secrets.value, ''::text))::integer AS "nullif"
                   FROM app_secrets
                  WHERE (app_secrets.key = 'founding_free_limit'::text)), 1000) AS free_limit,
            COALESCE(( SELECT (lower(app_secrets.value) = 'true'::text)
                   FROM app_secrets
                  WHERE (app_secrets.key = 'subscription_honour_12m'::text)), false) AS honour_12m
        ), s AS (
         SELECT l.id AS supplier_id,
            l.company_name,
            l.claimed_by AS email,
            l.founding_rank,
            l.subscription_exempt,
            l.subscription_paid_until,
            l.banned,
            l.matching_blocked,
            (COALESCE(l.registration_submitted_at, l.approved_at, l.created_at))::date AS registered_on,
            c.start_date,
            c.fee,
            c.free_limit,
            c.honour_12m
           FROM (leads l
             CROSS JOIN cfg c)
          WHERE ((COALESCE(l.claimed, false) = true) AND (l.approval_status = 'approved'::text))
        )
 SELECT supplier_id,
    company_name,
    email,
    founding_rank,
    subscription_exempt,
    registered_on,
    subscription_paid_until,
        CASE
            WHEN honour_12m THEN GREATEST(start_date, ((registered_on + '1 year'::interval))::date)
            ELSE start_date
        END AS billing_starts_on,
        CASE
            WHEN subscription_exempt THEN 'exempt'::text
            WHEN (CURRENT_DATE <
            CASE
                WHEN honour_12m THEN GREATEST(start_date, ((registered_on + '1 year'::interval))::date)
                ELSE start_date
            END) THEN 'not_due'::text
            WHEN ((subscription_paid_until IS NOT NULL) AND (subscription_paid_until >= CURRENT_DATE)) THEN 'active'::text
            WHEN (subscription_paid_until IS NULL) THEN 'due'::text
            ELSE 'past_due'::text
        END AS billing_status,
        CASE
            WHEN subscription_exempt THEN (0)::numeric
            WHEN (CURRENT_DATE <
            CASE
                WHEN honour_12m THEN GREATEST(start_date, ((registered_on + '1 year'::interval))::date)
                ELSE start_date
            END) THEN (0)::numeric
            WHEN ((subscription_paid_until IS NOT NULL) AND (subscription_paid_until >= CURRENT_DATE)) THEN (0)::numeric
            ELSE fee
        END AS amount_due_aed,
    fee AS annual_fee_aed,
    free_limit
   FROM s;

CREATE OR REPLACE VIEW public.v_supplier_coi AS  WITH sup AS (
         SELECT leads.id,
            leads.company_name,
            NULLIF(regexp_replace(COALESCE(leads.phone, ''::text), '\D'::text, ''::text, 'g'::text), ''::text) AS ph,
            NULLIF(regexp_replace(COALESCE(leads.whatsapp, ''::text), '\D'::text, ''::text, 'g'::text), ''::text) AS wa,
            lower(NULLIF(leads.email, ''::text)) AS em,
            NULLIF(leads.trn, ''::text) AS trn,
            NULLIF(leads.trade_license_no, ''::text) AS lic
           FROM leads
          WHERE (leads.claimed = true)
        ), ids AS (
         SELECT sup.id,
            sup.company_name,
            'phone'::text AS k,
            sup.ph AS v
           FROM sup
          WHERE ((sup.ph IS NOT NULL) AND (length(sup.ph) >= 7))
        UNION ALL
         SELECT sup.id,
            sup.company_name,
            'whatsapp'::text,
            sup.wa
           FROM sup
          WHERE ((sup.wa IS NOT NULL) AND (length(sup.wa) >= 7))
        UNION ALL
         SELECT sup.id,
            sup.company_name,
            'email'::text,
            sup.em
           FROM sup
          WHERE (sup.em IS NOT NULL)
        UNION ALL
         SELECT sup.id,
            sup.company_name,
            'trn'::text,
            sup.trn
           FROM sup
          WHERE (sup.trn IS NOT NULL)
        UNION ALL
         SELECT sup.id,
            sup.company_name,
            'license'::text,
            sup.lic
           FROM sup
          WHERE (sup.lic IS NOT NULL)
        )
 SELECT k AS shared_field,
    v AS shared_value,
    count(DISTINCT id) AS supplier_count,
    array_agg(DISTINCT id) AS supplier_ids,
    array_agg(DISTINCT company_name) AS companies
   FROM ids
  GROUP BY k, v
 HAVING (count(DISTINCT id) > 1)
  ORDER BY (count(DISTINCT id)) DESC, k;

CREATE OR REPLACE VIEW public.v_supplier_load AS  SELECT l.id AS supplier_id,
    l.company_name,
    count(DISTINCT im.inquiry_id) FILTER (WHERE ((i.completed_at IS NULL) AND (COALESCE(i.status, ''::text) <> 'cancelled'::text))) AS active_matched,
    count(DISTINCT im.inquiry_id) AS total_matched,
    sh.response AS response_rate,
    sh.risk_tier,
    ((count(DISTINCT im.inquiry_id) FILTER (WHERE ((i.completed_at IS NULL) AND (COALESCE(i.status, ''::text) <> 'cancelled'::text))) >= 10) AND (COALESCE(sh.response, (100)::numeric) < (50)::numeric)) AS overloaded
   FROM (((leads l
     JOIN inquiry_matches im ON ((im.supplier_id = l.id)))
     LEFT JOIN inquiries i ON ((i.id = im.inquiry_id)))
     LEFT JOIN supplier_health sh ON ((sh.supplier_id = l.id)))
  WHERE (l.claimed = true)
  GROUP BY l.id, l.company_name, sh.response, sh.risk_tier
  ORDER BY (count(DISTINCT im.inquiry_id) FILTER (WHERE ((i.completed_at IS NULL) AND (COALESCE(i.status, ''::text) <> 'cancelled'::text)))) DESC;

-- ===== FUNCTIONS =====
CREATE OR REPLACE FUNCTION public._kb_next_ver(k text, r text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select coalesce(max(version),0)+1 from public.kb_revisions where entry_kind=k and entry_ref=r $function$


CREATE OR REPLACE FUNCTION public._next_docver(p_type text, p_id text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select coalesce(max(version),0)+1 from public.doc_versions where entity_type=p_type and entity_id=p_id $function$


CREATE OR REPLACE FUNCTION public.add_working_days(d date, n integer)
 RETURNS date
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare cur date := d; added int := 0;
begin
  while added < n loop
    cur := cur + 1;
    if public.fn_is_working_day(cur) then added := added + 1; end if;
  end loop;
  return cur;
end;$function$


CREATE OR REPLACE FUNCTION public.ai_rec(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='ai_improvement' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values ('ai_trainer','ai_improvement','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'ai',p_sig);
  end if;
end $function$


CREATE OR REPLACE FUNCTION public.auth_uid_by_email(p_email text)
 RETURNS uuid
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'auth', 'public'
AS $function$
  select id from auth.users where lower(email) = lower(p_email) limit 1;
$function$


CREATE OR REPLACE FUNCTION public.block_disposable_signup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare em text;
begin
  if TG_TABLE_NAME = 'customers' then
    em := NEW.email;
  else
    -- only gate genuine supplier signups; leave scraped leads (claimed false/null) untouched
    if NEW.claimed is distinct from true then return NEW; end if;
    em := coalesce(NEW.claimed_by, NEW.email);
  end if;
  if em is not null and is_disposable_email(em) then
    raise exception 'Please use a permanent email address; temporary inboxes are not allowed.' using errcode = '23514';
  end if;
  return NEW;
end$function$


CREATE OR REPLACE FUNCTION public.canary_scan(haystack text)
 RETURNS TABLE(kind text, label text, fingerprint text, matched text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select c.kind, c.label, c.fingerprint,
    case
      when position(lower(c.fingerprint) in lower(haystack))>0 then 'fingerprint'
      when position(lower(c.label) in lower(haystack))>0 then 'company name'
      when c.honeytoken_email is not null and position(lower(c.honeytoken_email) in lower(haystack))>0 then 'honeytoken email'
    end as matched
  from canary_records c
  where position(lower(c.fingerprint) in lower(haystack))>0
     or position(lower(c.label) in lower(haystack))>0
     or (c.honeytoken_email is not null and position(lower(c.honeytoken_email) in lower(haystack))>0);
$function$


CREATE OR REPLACE FUNCTION public.dedupe_it_incident()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.agent='it' and NEW.kind='incident' and coalesce(NEW.status,'pending')='pending' then
    if exists (
      select 1 from public.agent_actions a
      where a.agent='it' and a.kind='incident' and a.status='pending'
        and coalesce(a.target_table,'')=coalesce(NEW.target_table,'')
    ) then
      return null; -- duplicate open incident; skip
    end if;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.doc_rec(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='doc_task' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values ('document_controller','doc_task','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'documents',p_sig);
  end if;
end $function$


CREATE OR REPLACE FUNCTION public.enqueue_supplier_invites(p_cap integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_today date := (now() at time zone 'UTC')::date;
  v_planned int; v_used int; v_remaining int; v_subj text; v_body text; v_count int;
  v_inv_recent int; v_bounced_recent int; v_rate numeric; v_max_rate numeric; v_target int; v_cap int;
begin
  if coalesce((select value from app_secrets where key='invite_enabled'),'false') <> 'true' then return 0; end if;

  v_cap := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), 10);
  insert into invite_schedule(day, planned, status) values (v_today, v_cap, 'approved')
    on conflict (day) do update set planned = excluded.planned, status = 'approved';
  v_planned := least(coalesce(p_cap, v_cap), v_cap);
  if v_planned <= 0 then return 0; end if;

  v_max_rate := coalesce((select nullif(value,'')::numeric from app_secrets where key='invite_max_bounce_rate'), 0.08);
  select count(*) into v_inv_recent from leads where invited_at > now() - interval '3 days';
  select count(*) into v_bounced_recent from leads where invite_status='bounced' and invited_at > now() - interval '3 days';
  if v_inv_recent >= 50 and (v_bounced_recent::numeric / greatest(v_inv_recent,1)) > v_max_rate then
    v_rate := round(v_bounced_recent::numeric / greatest(v_inv_recent,1), 3);
    update app_secrets set value='false' where key='invite_enabled';
    if not exists (select 1 from founder_alerts where event='invite_paused_bounce' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values('crit','invite_paused_bounce','Supplier invites AUTO-PAUSED: bounce rate '||(v_rate*100)||'% over 3 days ('||v_bounced_recent||'/'||v_inv_recent||') exceeds the '||(v_max_rate*100)||'% limit. Clean the list before resuming.','system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('invite_paused_bounce', coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com'),'admin','email','Supplier invites paused — high bounce rate','Invites were auto-paused: '||(v_rate*100)||'% bounced in the last 3 days. Clean/validate the list, then re-enable in the OS.','queued');
    end if;
    return 0;
  end if;

  select value into v_subj from app_secrets where key='invite_subject';
  select value into v_body from app_secrets where key='invite_body';
  select count(*) into v_used from notifications where type='supplier_invite' and (created_at at time zone 'UTC')::date = v_today;
  v_remaining := greatest(0, v_planned - v_used);
  if v_remaining <= 0 then return 0; end if;

  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 5);

  with activated as (
    select code, count(distinct l.id) ct from leads l, lateral unnest(l.invite_trades) code
    where coalesce(l.claimed,false) = true group by code
  ),
  under as (
    select t.code from taxonomy_trade t left join activated a on a.code = t.code
    where t.active and coalesce(a.ct,0) < v_target
  ),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.invite_trades
    from leads l
    where l.email is not null and l.email <> '' and l.invite_status is null
      and coalesce(l.source,'') <> 'self_registered' and coalesce(l.claimed,false) = false
      and lower(l.email) not in (select lower(email) from email_suppressions)
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name,
      coalesce((select u.code from under u where u.code = any(c.invite_trades) limit 1), '~none') as ptrade
    from cand c
  ),
  elig as (
    select id, email, company_name from (
      select id, email, company_name, ptrade,
        case when ptrade='~none' then 1 else 0 end as is_none,
        row_number() over (partition by ptrade order by id) as rk
      from prio
    ) r
    order by is_none, rk, ptrade
    limit v_remaining
  ),
  ins as (
    insert into notifications(type,to_email,to_role,lead_id,subject,body,status,created_at)
    select 'supplier_invite', email, 'supplier', id, v_subj,
           replace(v_body, '{{company}}', coalesce(nullif(btrim(company_name),''), 'there')), 'queued', now()
    from elig returning to_email
  )
  update leads set invite_status='queued', invited_at=now()
  where invite_status is null and lower(email) in (select lower(to_email) from ins);
  get diagnostics v_count = row_count;
  update invite_schedule set sent = sent + v_count where day = v_today;
  return v_count;
end; $function$


CREATE OR REPLACE FUNCTION public.ensure_category_agent()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not exists (select 1 from public.category_agents where slug = NEW.slug) then
    insert into public.category_agents(slug, name, active, created_at)
    values (
      NEW.slug,
      coalesce(NEW.name, initcap(replace(NEW.slug, '-', ' '))),
      true,
      now()
    );
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fin_alert(p_sig text, p_risk text, p_title text, p_reco text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not exists (select 1 from agent_actions where kind='finance_alert' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values ('finance_ai','finance_alert','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'finance',p_sig);
  end if;
end $function$


CREATE OR REPLACE FUNCTION public.fn_accrue_dues_interest()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_rate numeric; v_updated int := 0;
begin
  v_rate := coalesce((select num_value from public.gl_settings where key='clawback_interest_monthly_pct'), 0.75) / 100.0;

  with calc as (
    select d.id,
           round(coalesce(d.amount_due,0) * v_rate *
                 greatest(0, (date_part('year',  age(current_date, d.due_date::date)) * 12
                            + date_part('month', age(current_date, d.due_date::date)))::int), 2) as want
    from public.supplier_dues d
    where d.paid_at is null
      -- H6 (OS audit): once collections_legal has escalated a due it FREEZES the interest; the monthly
      -- accrual must not overwrite that frozen figure, so exclude legal-stage dues here.
      and coalesce(d.status,'') not in ('paid','settled','waived','cancelled','legal')
      and d.legal_stage is null
      and coalesce(d.amount_due,0) > 0
      and d.due_date is not null
  )
  update public.supplier_dues d
     set interest_amount = c.want
    from calc c
   where c.id = d.id
     and coalesce(d.interest_amount,0) is distinct from c.want;

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_add_working_days(p_from timestamp with time zone, p_days integer)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d date; left_ int := greatest(0, coalesce(p_days,0)); tod time; res timestamptz;
begin
  if p_from is null then return null; end if;
  d   := (p_from at time zone 'Asia/Dubai')::date;
  tod := (p_from at time zone 'Asia/Dubai')::time;
  while left_ > 0 loop
    d := d + 1;
    if public.fn_is_working_day(d) then left_ := left_ - 1; end if;
  end loop;
  -- if we consumed no days and landed on a non-working day, roll forward
  while not public.fn_is_working_day(d) loop d := d + 1; end loop;
  res := ((d::text || ' ' || tod::text)::timestamp) at time zone 'Asia/Dubai';
  return res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_agent_context(p_agent_key text DEFAULT NULL::text, p_max_chars integer DEFAULT 9000)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out text := ''; r record; piece text; cap int; own_cap int;
        v_dept text; v_role text; v_charter text; v_north text; v_health_fn text;
        v_status text; v_state jsonb; v_l4 text := '';
begin
  cap := greatest(coalesce(p_max_chars,9000), 22000);
  own_cap := least(cap/2, 6000);
  if p_agent_key is not null then
    select a.department, a.role into v_dept, v_role from org_agents a where a.agent_key=p_agent_key;
    select d.charter, d.north_star, d.health_fn into v_charter, v_north, v_health_fn
      from org_departments d where d.dept_key=v_dept;
    select status into v_status from org_onboarding where agent_key=p_agent_key;
    out := out || '# YOUR IDENTITY AT QUOTESDONE'||E'\n'
      ||'You are '||coalesce(v_role, p_agent_key||' (senior specialist)')
      ||case when v_charter is not null then '. Department charter: '||v_charter else '' end
      ||case when v_north is not null then ' North star: '||v_north||'.' else '' end
      ||' Employment status: '||coalesce(v_status,'onboarding')||'.'||E'\n'
      ||'POSTURE: You are a senior executive employee, not an assistant. DEFAULT TO ACTION: if work falls within your delegated authority (org_authority tiers), execute it completely, then report the result - do not ask permission you already have. Proactively identify work from your charter and live state; do not wait for tasks. Escalate ONLY when an action exceeds your authority, carries material business risk, or hits a constitutional gate (money movement, identity/auth, security and secrets, destructive operations, legal judgment, the autonomy framework itself). Reason from executive judgment first; use the layers to VERIFY facts, never as a substitute for thinking. Quote operational numbers ONLY from LIVE STATE. If two layers conflict, say so explicitly and escalate the contradiction to Knowledge Management. Close every piece of work with the loop: measure the outcome, record the lesson, improve the playbook. If your employment status is not certified, mark your outputs as provisional.'||E'\n\n';
  end if;
  if p_agent_key is not null then
    out := out || '# LAYER 2 - YOUR PROFESSIONAL EXPERTISE'||E'\n\n';
    for r in select topic,content from agent_knowledge
             where agent_key=p_agent_key and coalesce(layer,'profession') in ('profession','state')
             order by priority desc nulls last, updated_at desc loop
      piece := '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
      if length(out)+length(piece) <= own_cap + 2200 then out := out||piece; end if;
    end loop;
  end if;
  out := out || '# LAYER 1 - COMPANY KNOWLEDGE (authoritative; pricing marked LIVE overrides any other figure)'||E'\n\n';
  for r in select topic,content from agent_knowledge
           where agent_key='_global' and coalesce(priority,0)>=90 order by priority desc nulls last, updated_at desc loop
    piece := '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
    if length(out)+length(piece) <= cap then out := out||piece; end if;
  end loop;
  for r in select topic,content from agent_knowledge
           where agent_key='_global' and coalesce(priority,0)<90 order by priority desc nulls last, updated_at desc loop
    piece := '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
    if length(out)+length(piece) <= cap then out := out||piece; end if;
  end loop;
  if v_health_fn is not null then
    begin
      execute format('select %I()', v_health_fn) into v_state;
      piece := '# LAYER 3 - LIVE OPERATIONAL STATE (from '||v_health_fn||' at '||now()::timestamptz(0)||'; the ONLY valid source for operational numbers)'||E'\n'
               ||left(coalesce(v_state::text,'{}'), 2600)||E'\n\n';
      if length(out)+length(piece) <= cap + 3000 then out := out||piece; end if;
    exception when others then
      out := out || '# LAYER 3 - LIVE OPERATIONAL STATE unavailable ('||sqlerrm||'); do not quote operational numbers this turn.'||E'\n\n';
    end;
  end if;
  if p_agent_key is not null then
    for r in select topic, content from agent_knowledge
             where layer='experience' and agent_key in (p_agent_key,'_global')
             order by updated_at desc limit 12 loop
      v_l4 := v_l4 || '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
    end loop;
    for r in select kind, content from agent_memory m
             where m.agent_key=p_agent_key and m.importance >= 5
               and not exists (select 1 from policy_rules p where p.active and m.content ~* p.forbid_regex)
             order by m.importance desc, m.created_at desc limit 8 loop
      v_l4 := v_l4 || '## memory ('||r.kind||')'||E'\n'||r.content||E'\n\n';
    end loop;
    if v_l4 <> '' then
      out := out || '# LAYER 4 - WHAT THIS ORGANIZATION HAS LEARNED'||E'\n\n'|| left(v_l4, 3500);
    end if;
  end if;
  return out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_agent_decision(p_agent text, p_kind text, p_title text, p_recommendation text, p_confidence numeric DEFAULT NULL::numeric, p_evidence jsonb DEFAULT '[]'::jsonb, p_risk text DEFAULT 'low'::text, p_detail jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_sensitive boolean; v_escalate boolean; v_reason text; v_status text; v_id bigint;
begin
  v_sensitive := (p_kind ~* 'legal|financ|complian|security|payment|refund|payout|pricing|price'
                  or p_agent ~* 'legal|security|finance|compliance');
  v_escalate := (coalesce(p_confidence,0) < 0.6) or v_sensitive;
  v_reason := case
    when coalesce(p_confidence,0) < 0.6 and v_sensitive then 'Low confidence and sensitive domain — human review required.'
    when coalesce(p_confidence,0) < 0.6 then 'Confidence below 0.60 threshold — human review required.'
    when v_sensitive then 'Sensitive domain (legal/financial/compliance/security) — human review required.'
    else null end;
  v_status := case when v_escalate then 'needs_review' else 'pending' end;

  insert into public.agent_actions(agent,kind,status,risk,title,recommendation,detail,
                                   confidence,evidence,escalated,escalation_reason,created_at)
  values (p_agent,p_kind,v_status,p_risk,p_title,p_recommendation,p_detail,
          p_confidence,coalesce(p_evidence,'[]'::jsonb),v_escalate,v_reason, now())
  returning id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_agent_silence_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int:=0; f int:=0; g int:=0; nr int:=0; v_email text; v_run bigint;
begin
  insert into agent_runs(agent, started_at) values ('agent_silence_watch', clock_timestamp()) returning id into v_run;

  select to_email into v_email from notifications
   where type='founder_brief' and to_email is not null order by created_at desc limit 1;

  insert into cron_job_seen (jobid, jobname, schedule)
  select j.jobid, j.jobname, j.schedule from cron.job j where j.active
  on conflict (jobid) do update set last_seen = now(), jobname = excluded.jobname, schedule = excluded.schedule;

  -- Record successes BEFORE evaluating, so they survive the 14-day history prune.
  update cron_job_seen s
     set last_success = h.last_ok
    from (select jobid, max(start_time) as last_ok
            from cron.job_run_details where status='succeeded' group by jobid) h
   where h.jobid = s.jobid
     and (s.last_success is null or s.last_success < h.last_ok);

  for r in
    select j.jobid, j.jobname,
           case when split_part(j.schedule,' ',5) <> '*' then 336
                when split_part(j.schedule,' ',3) <> '*' then 1440
                when split_part(j.schedule,' ',2) =  '*' then 6
                else 72 end as thresh_h,
           (select count(*) from cron.job_run_details d where d.jobid=j.jobid) as history_rows,
           -- effective last success: live history OR the value we persisted before pruning
           greatest(
             (select max(d.start_time) from cron.job_run_details d
               where d.jobid=j.jobid and d.status='succeeded'),
             (select s.last_success from cron_job_seen s where s.jobid=j.jobid)
           ) as last_ok,
           (select count(*) from cron.job_run_details d
             where d.jobid=j.jobid and d.status='failed'
               and d.start_time > now() - interval '24 hours') as fails_24h,
           (select s.first_seen from cron_job_seen s where s.jobid=j.jobid) as first_seen,
           (select s.last_success from cron_job_seen s where s.jobid=j.jobid) as stored_ok
      from cron.job j where j.active
  loop
    -- Never-run: only when there is NO history AND we have never recorded a success.
    -- Previously a pruned-history monthly job hit this branch and false-alarmed.
    if r.history_rows = 0 and r.stored_ok is null then
      if r.first_seen is not null and r.first_seen < now() - (r.thresh_h||' hours')::interval then
        if not exists (select 1 from founder_alerts where event='cron_never_ran'
                        and detail like '%"'||r.jobname||'"%'
                        and created_at > now() - interval '24 hours') then
          insert into founder_alerts(level,event,detail,channel)
          values ('high','cron_never_ran', jsonb_build_object(
            'job', r.jobname,
            'first_seen', r.first_seen::text,
            'known_for_hours', round(extract(epoch from (now()-r.first_seen))/3600),
            'expected_within_hours', r.thresh_h)::text, 'email');
          if v_email is not null then
            insert into notifications(type,to_email,subject,body,status)
            values ('agent_silence', v_email, 'Scheduled job has never run: '||r.jobname,
              'Job "'||r.jobname||'" is active but has no run history at all. It has been registered since '||
              r.first_seen::text||' and should have run at least every '||r.thresh_h||' hours. It is likely misregistered.','pending');
          end if;
          nr := nr + 1;
        end if;
      else
        g := g + 1;
      end if;
      continue;
    end if;

    if r.last_ok is null or r.last_ok < now() - (r.thresh_h||' hours')::interval then
      if not exists (select 1 from founder_alerts where event='cron_silent'
                      and detail like '%"'||r.jobname||'"%'
                      and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level,event,detail,channel)
        values ('high','cron_silent', jsonb_build_object(
          'job',r.jobname,'last_success',coalesce(r.last_ok::text,'no success on record'),
          'silent_hours',round(extract(epoch from (now()-r.last_ok))/3600),
          'expected_within_hours',r.thresh_h)::text,'email');
        if v_email is not null then
          insert into notifications(type,to_email,subject,body,status)
          values ('agent_silence',v_email,'Scheduled job stopped: '||r.jobname,
            'Job "'||r.jobname||'" last succeeded '||coalesce(r.last_ok::text,'unknown')||
            '. Expected at least every '||r.thresh_h||' hours.','pending');
        end if;
        n := n + 1;
      end if;
    end if;

    if r.fails_24h > 0 then
      if not exists (select 1 from founder_alerts where event='cron_failing'
                      and detail like '%"'||r.jobname||'"%'
                      and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level,event,detail,channel)
        values ('high','cron_failing',
          jsonb_build_object('job',r.jobname,'failures_24h',r.fails_24h,
                             'last_success',coalesce(r.last_ok::text,'unknown'))::text,'email');
        if v_email is not null then
          insert into notifications(type,to_email,subject,body,status)
          values ('agent_silence',v_email,'Scheduled job failing: '||r.jobname,
            'Job "'||r.jobname||'" has failed '||r.fails_24h||' time(s) in the last 24 hours. Last success: '||
            coalesce(r.last_ok::text,'unknown')||'. Check cron.job_run_details for the error text.','pending');
        end if;
        f := f + 1;
      end if;
    end if;
  end loop;

  update agent_runs
     set finished_at=clock_timestamp(), status='ok',
         counts=jsonb_build_object('active_jobs',(select count(*) from cron.job where active),
                                   'in_grace',g,'silent',n,'failing',f,'never_ran',nr)
   where id=v_run;

  return jsonb_build_object('ran_at',now(),
    'active_jobs',(select count(*) from cron.job where active),
    'in_grace',g,'silent_alerts',n,'failing_alerts',f,'never_ran_alerts',nr);
exception when others then
  update agent_runs set finished_at=clock_timestamp(), status='error', note=left(sqlerrm,500) where id=v_run;
  raise;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ai_gate(p_answer text, p_sources jsonb DEFAULT '[]'::jsonb, p_confidence numeric DEFAULT NULL::numeric, p_action text DEFAULT 'run_agent_action'::text, p_actor text DEFAULT 'agent'::text, p_attrs jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare g jsonb; a jsonb; esc jsonb; conf_min numeric; viol text[]:='{}'; approved boolean; route text;
begin
  g := public.fn_require_grounding(p_answer, p_sources);
  if not (g->>'grounded')::boolean then viol := array_append(viol,'ungrounded: retrieve knowledge and cite a source'); end if;
  select value::numeric into conf_min from decision_policy where key='confidence_min';
  if p_confidence is not null and p_confidence < coalesce(conf_min,0.6) then
     viol := array_append(viol,'low_confidence: below '||coalesce(conf_min,0.6)||' — ask a clarifying question or escalate'); end if;
  a := public.fn_authorize(p_actor, p_action, p_attrs);
  if not (a->>'allowed')::boolean then viol := array_append(viol,'unauthorized: '||(a->>'reason')); end if;
  esc := public.fn_should_escalate(p_attrs || jsonb_build_object('confidence',p_confidence));
  route := esc->>'route_to';
  approved := (array_length(viol,1) is null) and not (esc->>'escalate')::boolean;
  -- log the governance decision (immutable)
  insert into decision_log(actor,kind,ctx,decision,confidence,reasons,sources,route_to)
  values (p_actor,'ai_gate', jsonb_build_object('action',p_action,'attrs',p_attrs),
          case when approved then 'approved' else 'blocked' end, p_confidence,
          to_jsonb(viol || array(select jsonb_array_elements_text(coalesce(esc->'reasons','[]')))), p_sources, route);
  return jsonb_build_object('approved',approved,'violations',to_jsonb(viol),
    'grounding',g,'authorization',a,'escalation',esc,'route_to',route,
    'directive', case when approved then 'emit' when (esc->>'escalate')::boolean then 'escalate to '||coalesce(route,'Secretary') else 'revise before emitting' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ai_quality_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_regs int:=0; v_spikes int:=0; v_detail jsonb; v_open int; v_owner text;
begin
  -- 1. snapshot current per-agent override rate (builds history for spike detection)
  insert into public.ai_quality_snapshots(agent,override_pct,actions_30d)
    select agent, override_pct, actions_30d from public.v_ai_agent_health where override_pct is not null;

  -- 2. eval regressions: latest run worse than previous, or below 70 absolute
  with ranked as (
    select prompt_key, score, created_at,
           row_number() over(partition by prompt_key order by created_at desc) rn
    from public.prompt_eval_runs
  ),
  reg as (
    select c.prompt_key, c.score cur, p.score prev
    from ranked c join ranked p on p.prompt_key=c.prompt_key and p.rn=2
    where c.rn=1 and (c.score < p.score - 5 or c.score < 70)
  ),
  ins as (
    insert into public.security_events(kind,severity,source,subject,detail)
    select 'eval_regression', case when cur<70 then 'high' else 'medium' end, 'ai_quality_watch', prompt_key,
           jsonb_build_object('current',cur,'previous',prev)
    from reg returning 1
  )
  select count(*) into v_regs from ins;

  -- 3. override spikes: human-facing agents whose override jumped >20pts above their trailing average
  with cur as (
    select agent, override_pct, actions_30d from public.v_ai_agent_health
    where override_pct is not null and actions_30d>=5 and agent not in ('security','onboarding','email')
  ),
  hist as (
    select agent, avg(override_pct) avg_prev, count(*) n
    from public.ai_quality_snapshots where at < now()-interval '12 hours' group by agent
  ),
  spike as (
    select c.agent, c.override_pct, round(h.avg_prev,1) avg_prev
    from cur c join hist h on h.agent=c.agent
    where h.n>=1 and c.override_pct > coalesce(h.avg_prev,0)+20
  ),
  ins2 as (
    insert into public.security_events(kind,severity,source,subject,detail)
    select 'override_spike','medium','ai_quality_watch', agent,
           jsonb_build_object('override_pct',override_pct,'trailing_avg',avg_prev)
    from spike returning 1
  )
  select count(*) into v_spikes from ins2;

  v_detail := jsonb_build_object('eval_regressions',v_regs,'override_spikes',v_spikes);

  -- 4. surface + email the founder (deduped, mirrors fn_backup_watch), only if something fired
  if v_regs+v_spikes > 0 then
    select count(*) into v_open from public.agent_actions
      where kind='ai_quality_alert' and coalesce(status,'') in ('pending','needs_review')
        and created_at > now()-interval '24 hours';
    if v_open = 0 then
      insert into public.agent_actions(agent,kind,status,risk,title,recommendation,target_table,detail)
      values('ai_trainer','ai_quality_alert','pending','medium',
        'AI quality alert: '||v_regs||' eval regression(s), '||v_spikes||' override spike(s)',
        'Open the AI Observability dashboard and review security_events of kind eval_regression / override_spike. Consider rolling back the regressed prompt version, or investigating why a human-facing agent''s suggestions are being rejected.',
        'security_events', v_detail);
      select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner
        from public.app_secrets where key='admin_emails';
      insert into public.notifications(type,to_email,to_role,channel,subject,body,status)
      values('ai_quality_alert', v_owner,'admin','email','QuotesDone: AI quality alert',
        'The AI quality watch flagged '||v_regs||' eval regression(s) and '||v_spikes||' override spike(s). Open the AI Observability dashboard and check security_events (kind eval_regression / override_spike).','queued');
    end if;
  end if;
  return v_detail;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ai_trainer()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_runs int; v_err int; v_run_ok numeric;
  v_open int; v_rej int; v_acc int; v_reject_rate numeric; v_esc_rate numeric;
  v_qa_total int; v_qa_failed int; v_qa_pass numeric;
  v_sat numeric; v_halluc numeric; v_clarif numeric;
  v_quote_q numeric; v_match_cov numeric;
  v_health numeric; v_kpis jsonb; n_rec int; v_weak text; v_secret text; n_drafted int:=0;
begin
  select count(*), count(*) filter (where status in ('error','failed')) into v_runs, v_err from agent_runs where started_at>=now()-interval '30 days';
  v_run_ok := round(100.0*(v_runs-v_err)/nullif(v_runs,0),1);
  select count(*) filter (where status in ('pending','needs_review')),
         count(*) filter (where status='rejected'),
         count(*) filter (where status in ('approved','done','auto_done'))
    into v_open, v_rej, v_acc from agent_actions where created_at>=now()-interval '30 days';
  v_reject_rate := round(100.0*v_rej/nullif(v_rej+v_acc,0),1);
  v_esc_rate := round(100.0*v_open/nullif(v_open+v_acc+v_rej,0),1);
  select total, failed into v_qa_total, v_qa_failed from qa_results order by run_at desc limit 1;
  v_qa_pass := round(100.0*(coalesce(v_qa_total,0)-coalesce(v_qa_failed,0))/nullif(v_qa_total,0),1);
  select avg_satisfaction into v_sat from customer_kpis;
  v_halluc := round(100.0*(coalesce(v_rej,0)+coalesce(v_qa_failed,0))/nullif(coalesce(v_acc,0)+coalesce(v_rej,0)+coalesce(v_qa_total,0),0),1);
  select round(100.0*count(*) filter (where rfq_ready)/nullif(count(*),0),1) into v_clarif from inquiries where created_at>=now()-interval '90 days';
  select (kpis->>'quote_quality_avg')::numeric, (kpis->>'match_coverage_pct')::numeric into v_quote_q, v_match_cov from agent_evals order by snapshot_at desc limit 1;

  v_kpis := jsonb_build_object(
    'window_days',30,'run_success_pct',v_run_ok,'escalation_rate_pct',v_esc_rate,'rejection_rate_pct',v_reject_rate,
    'qa_pass_pct',v_qa_pass,'qa_cases',v_qa_total,'customer_satisfaction',v_sat,
    'hallucination_proxy_pct',v_halluc,'clarification_efficiency_pct',v_clarif,
    'quote_quality_avg',v_quote_q,'match_coverage_pct',v_match_cov,
    'runs_30d',v_runs,'errors_30d',v_err,'open_escalations',v_open,'rejected',v_rej,'accepted',v_acc);

  insert into agent_evals(snapshot_at, window_days, kpis) values (now(), 30, v_kpis);
  v_health := round(coalesce(v_run_ok,100)*0.30 + (100-coalesce(v_halluc,0))*0.25 + coalesce(v_sat,70)*0.20 + coalesce(v_qa_pass,100)*0.15 + coalesce((select coverage_pct from knowledge_kpis),60)*0.10,1);
  insert into ai_trainer_snapshots(snapshot_date, kpis) values (current_date, v_kpis || jsonb_build_object('ai_health',v_health))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  select string_agg(agent||' ('||coalesce(run_success_pct,0)||'% ok, '||coalesce(rejection_rate_pct,0)||'% rejected)', '; ')
    into v_weak from ai_agent_quality where runs_30d>=20 and (coalesce(run_success_pct,100)<90 or coalesce(rejection_rate_pct,0)>30);
  perform ai_rec('weak_agents', v_weak is not null, 'medium', 'Under-performing agents',
    'These agents need attention: '||v_weak||'. Review their logic/prompt or the knowledge they rely on.');
  perform ai_rec('low_quote_quality', coalesce(v_quote_q,100) < 60, 'medium', 'Quote-review quality is low',
    'Structured quote quality is averaging '||coalesce(v_quote_q,0)||'/100. The Trainer is drafting an improved quote_review prompt for your approval; also strengthening category knowledge helps.');
  perform ai_rec('thin_benchmarks', coalesce(v_qa_total,0) < 20, 'low', 'Add more test benchmarks',
    'The QA suite has only '||coalesce(v_qa_total,0)||' cases. Add benchmark cases (quotes, RFQ qualification, compliance answers) so regressions are caught automatically.');
  perform ai_rec('prompts_unbenchmarked', (select count(*) from prompt_versions where status='active' and eval_score is null)>0, 'low', 'Prompts have no eval score',
    (select count(*)::text from prompt_versions where status='active' and eval_score is null)||' active prompt(s) have never been benchmarked. Run an eval so future changes can be compared objectively.');
  perform ai_rec('accuracy_watch', coalesce(v_halluc,0) > 15, 'high', 'Accuracy watch — high correction rate',
    'The AI was corrected/failed '||coalesce(v_halluc,0)||'% of the time (founder rejections + QA failures). Review the rejected actions to find the pattern and fix the responsible prompt or knowledge.');

  -- CLOSED LOOP: when quote quality is low and no draft is already awaiting approval, ask the LLM to author an improved
  -- quote_review prompt DRAFT (founder still approves before rollout). De-duped so it drafts once per open cycle.
  if coalesce(v_quote_q,100) < 60
     and not exists (select 1 from agent_actions where kind='prompt_approval' and detail->>'key'='quote_review.system' and status in ('pending','needs_review'))
     and not exists (select 1 from prompt_versions where prompt_key='quote_review.system' and status='draft') then
    select value into v_secret from app_secrets where key='inbound_secret';
    perform net.http_post(
      url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/prompt_improve',
      headers:='{"Content-Type":"application/json"}'::jsonb,
      body:=jsonb_build_object('__secret',v_secret,'key','quote_review.system',
        'reason','Structured quote quality is averaging '||coalesce(v_quote_q,0)||'/100 — quotes lack itemised detail (brand/model/spec/unit price) and clear scope; the prompt should require full line-item detail and flag missing fields.'));
    n_drafted := 1;
  end if;

  select count(*) into n_rec from agent_actions where agent='ai_trainer' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'ai_health',v_health,'kpis',v_kpis,'open_recommendations',n_rec,'auto_drafted',n_drafted);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ap_pay(p_bill bigint, p_date date DEFAULT NULL::date, p_amount numeric DEFAULT NULL::numeric, p_from_account text DEFAULT '1000'::text, p_by text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare b record; pay numeric(18,2); j bigint; newpaid numeric(18,2);
begin
  select * into b from public.ap_bills where id=p_bill;
  if b.id is null then raise exception 'bill % not found', p_bill; end if;
  if b.status in ('paid','void') then raise exception 'bill % is %', p_bill, b.status; end if;
  pay := coalesce(round(p_amount,2), b.total - b.amount_paid);
  if pay <= 0 then raise exception 'nothing to pay on bill %', p_bill; end if;
  if b.amount_paid + pay > b.total then raise exception 'overpay bill %: %/%', p_bill, b.amount_paid+pay, b.total; end if;

  j := public.fn_gl_entry(coalesce(p_date,current_date),
         'Payment '||coalesce(b.bill_no,'bill '||p_bill),
         'ap_payment', p_bill::text,
         jsonb_build_array(jsonb_build_object('account','2000','debit', pay),
                           jsonb_build_object('account',p_from_account,'credit', pay)),
         p_by);
  newpaid := b.amount_paid + pay;
  update public.ap_bills
     set amount_paid = newpaid,
         status = case when newpaid >= total then 'paid' else 'partial' end,
         pay_journal_id = j
   where id=p_bill;
  return j;
end $function$


CREATE OR REPLACE FUNCTION public.fn_assign_founding_rank()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_limit int; v_rank int;
begin
  -- Only rank a supplier once, and only once they are a real registered supplier.
  if coalesce(new.claimed,false) is not true then return new; end if;
  if new.founding_rank is not null then return new; end if;

  v_limit := coalesce((select nullif(value,'')::int from public.app_secrets where key='founding_free_limit'), 1000);

  -- Serialise rank assignment so two concurrent registrations cannot take the same number.
  perform pg_advisory_xact_lock(hashtext('qd_founding_rank'));
  select coalesce(max(founding_rank),0) + 1 into v_rank from public.leads;

  new.founding_rank := v_rank;
  -- Exemption is permanent: it is stamped at registration and never recalculated, so a supplier
  -- who was inside the first 1,000 stays exempt even as the base grows.
  new.subscription_exempt := (v_rank <= v_limit);
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_assign_founding_ranks()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_limit int; v_max int; v_assigned int := 0;
begin
  v_limit := coalesce((select nullif(value,'')::int from app_secrets where key='founding_free_limit'), 1000);
  select coalesce(max(founding_rank),0) into v_max from leads;
  with candidates as (
    select id, row_number() over (
             order by coalesce(registration_submitted_at, approved_at, created_at) asc, id asc) + v_max as new_rank
    from leads
    where founding_rank is null
      and coalesce(claimed,false) = true
      and approval_status = 'approved'
      and coalesce(banned,false) = false
  )
  update leads l set founding_rank = c.new_rank,
                     subscription_exempt = (c.new_rank <= v_limit)
  from candidates c where l.id = c.id;
  get diagnostics v_assigned = row_count;
  return json_build_object('newly_ranked', v_assigned, 'highest_rank', (select coalesce(max(founding_rank),0) from leads),
                           'founding_slots_left', greatest(0, v_limit - (select count(*) from leads where founding_rank is not null)),
                           'free_limit', v_limit);
end $function$


CREATE OR REPLACE FUNCTION public.fn_authorize(p_email text, p_action text, p_attrs jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_role text; c jsonb; ok boolean:=false; reason text; maxamt numeric; amt numeric;
begin
  v_role := public.fn_role_of(p_email);
  if v_role='owner' then return jsonb_build_object('allowed',true,'role',v_role,'reason','owner has full access'); end if;
  select rp.constraint_json into c from role_permissions rp where rp.role=v_role and rp.action=p_action;
  if c is null then
    if exists(select 1 from role_permissions rp where rp.role=v_role and rp.action='*') then
      return jsonb_build_object('allowed',true,'role',v_role,'reason','role wildcard'); end if;
    return jsonb_build_object('allowed',false,'role',v_role,'reason','role "'||v_role||'" lacks permission "'||p_action||'"');
  end if;
  ok := true; reason := 'granted';
  if c ? 'max_amount_aed' then
    maxamt := (c->>'max_amount_aed')::numeric; amt := nullif(p_attrs->>'amount_aed','')::numeric;
    if amt is not null and amt > maxamt then ok:=false; reason:='amount '||amt||' exceeds role limit '||maxamt; end if;
  end if;
  if c ? 'purpose' and coalesce(p_attrs->>'purpose','') <> (c->>'purpose') then ok:=false; reason:='purpose must be '||(c->>'purpose'); end if;
  return jsonb_build_object('allowed',ok,'role',v_role,'reason',reason,'constraint',c);
end $function$


CREATE OR REPLACE FUNCTION public.fn_autonomy_audit()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with per as (
    select d.dept_key, d.name,
      (select max(created_at) from org_memory m where m.scope=d.dept_key and m.kind='plan')   as last_plan,
      (select max(created_at) from org_memory m where m.scope=d.dept_key and m.kind='lesson') as last_lesson,
      (select count(*) from org_tasks t where t.dept_key=d.dept_key and t.status in ('assigned','proposed','in_progress')) as open_tasks,
      (select count(*) from org_tasks t where t.dept_key=d.dept_key and t.status='done' and t.updated_at > now()-interval '7 days') as done_7d
    from org_departments d where d.active
  )
  select jsonb_build_object(
    'as_of', now(),
    'departments', (select jsonb_agg(jsonb_build_object(
        'dept', dept_key, 'name', name,
        'last_plan', last_plan, 'last_lesson', last_lesson, 'open_tasks', open_tasks, 'done_7d', done_7d,
        'status', case
          when (last_plan is null or last_plan < now()-interval '4 days') and open_tasks=0 and done_7d=0 then 'red'
          when (last_plan is null or last_plan < now()-interval '3 days') then 'amber'
          else 'green' end
      ) order by dept_key) from per),
    'summary', (select jsonb_build_object(
        'green', count(*) filter (where (last_plan is not null and last_plan >= now()-interval '3 days')),
        'stalled', count(*) filter (where (last_plan is null or last_plan < now()-interval '4 days') and open_tasks=0 and done_7d=0))
      from per)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_autonomy_audit_run()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a jsonb; stalled int;
begin
  a := fn_autonomy_audit();
  stalled := coalesce((a->'summary'->>'stalled')::int, 0);
  insert into org_memory(scope,kind,content,source)
    values ('exec','audit','Autonomy self-audit: '||(a->'summary')::text||' — '||stalled||' department loop(s) stalled.', 'autonomy_audit');
  if stalled > 0 then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail)
    values ('brief','autonomy_stall','pending','medium',
      stalled||' department loop(s) have stalled',
      'One or more departments have not planned in 4+ days and have no open or recent work. Check fn_autonomy_audit().',
      a);
  end if;
  return a;
end $function$


CREATE OR REPLACE FUNCTION public.fn_autonomy_check(p_kind text, p_target_table text, p_recommendation text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select case
    when p_kind ~* 'refund|payout|payment|withdraw|transfer|invoice_pay|money|charge' then 'approve'
    when p_kind ~* 'delete|purge|remove_record' and coalesce(p_target_table,'') in ('leads','customers') then 'approve'
    when p_kind = 'approve_supplier' and coalesce(p_recommendation,'') <> 'approve' then 'approve'
    else 'auto'
  end;
$function$


CREATE OR REPLACE FUNCTION public.fn_autonomy_class(p_kind text, p_target_table text, p_recommendation text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare pol jsonb; d text;
begin
  -- Policy-bounded carve-out (chairman doctrine 2026-07-24): a refund fully inside
  -- the published policy window is routine work, not an executive decision.
  if p_kind = 'refund_within_window' then return 'ack'; end if;
  -- HARD RAILS: money, destructive, and supplier approval can never be auto-cleared by policy.
  if p_kind ~* 'refund|payout|payment|withdraw|transfer|invoice_pay|money|charge' then return 'founder'; end if;
  if p_kind ~* 'delete|purge|remove_record' and coalesce(p_target_table,'') in ('leads','customers') then return 'founder'; end if;
  if p_kind='approve_supplier' and coalesce(p_recommendation,'')='approve' then return 'clean_supplier'; end if;
  if p_kind='approve_supplier' then return 'founder'; end if;
  -- POLICY: founder-editable per-kind disposition.
  select value into pol from public.decision_policy where key='action_autonomy';
  d := pol->>p_kind;
  if d in ('ack','founder','keep') then return d; end if;
  -- LEGACY FALLBACK
  if p_kind in ('security_alert','compliance_update','incident','supply_health','sla_no_supply') then return 'ack'; end if;
  return 'keep';
end $function$


CREATE OR REPLACE FUNCTION public.fn_autonomy_dispose()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare r record; n_appr int:=0; n_ack int:=0; n_queue int:=0; c text;
begin
  for r in select * from public.agent_actions
           where status in ('pending','held_for_review','proposed','open','needs_review')
  loop
    c := public.fn_autonomy_class(r.kind, r.target_table, r.recommendation);
    if c='clean_supplier' and r.target_id ~ '^\d+$' then
      update public.leads set approval_status='approved', approved_at=now(),
             approval_decided_by='chief_of_staff (auto)', lifecycle_stage='active'
       where id=r.target_id::bigint and approval_status='pending' and coalesce(banned,false)=false;
      update public.agent_actions set status='approved', decided_by='chief_of_staff (auto)', decided_at=now() where id=r.id;
      n_appr := n_appr+1;
    elsif c='ack' then
      update public.agent_actions set status='auto_done', decided_by='chief_of_staff (auto)', decided_at=now() where id=r.id;
      n_ack := n_ack+1;
    else  -- 'founder' or 'keep' → remains visible in the queue
      n_queue := n_queue+1;
    end if;
  end loop;
  return jsonb_build_object('approved_suppliers',n_appr,'auto_cleared_logged',n_ack,'in_your_queue',n_queue);
end $function$


CREATE OR REPLACE FUNCTION public.fn_backup_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_last timestamptz; v_status text; v_stale boolean; v_owner text; v_open int;
begin
  select started_at, status into v_last, v_status
    from agent_runs where agent='backup' order by started_at desc limit 1;
  v_stale := (v_last is null) or (v_last < now() - interval '26 hours') or (coalesce(v_status,'')='error');
  if not v_stale then
    return jsonb_build_object('ok',true,'last',v_last,'status',v_status);
  end if;
  select count(*) into v_open from agent_actions
    where kind='backup_alert' and coalesce(status,'') in ('pending','needs_review')
      and created_at > now()-interval '24 hours';
  if v_open = 0 then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,target_table,detail)
    values('security','backup_alert','pending','high',
      'Backup may have failed or is overdue',
      'The daily logical backup has not completed successfully in the last 26 hours (last: '||coalesce(v_last::text,'never')||', status: '||coalesce(v_status,'unknown')||'). Check the backup function and logs. Managed daily backups and the Dropbox mirror remain as fallbacks.',
      'agent_runs', jsonb_build_object('last_backup',v_last,'last_status',v_status));
    insert into security_events(kind,severity,source,subject,detail)
    values('backup_overdue','high','backup','logical backup',
      jsonb_build_object('last_backup',v_last,'last_status',v_status));
    select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner
      from app_secrets where key='admin_emails';
    insert into notifications(type,to_email,to_role,channel,subject,body,status)
    values('backup_alert', v_owner, 'admin','email','QuotesDone: backup overdue or failed',
      'The daily logical backup has not completed in the last 26 hours (last: '||coalesce(v_last::text,'never')||', status: '||coalesce(v_status,'unknown')||'). Please check. Managed daily backups + the Dropbox mirror remain as fallbacks.','queued');
  end if;
  return jsonb_build_object('alerted',true,'last',v_last,'status',v_status,'existing_open',v_open);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ban_overdue_dues()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_days int; v_n int := 0; v_admin text;
begin
  v_days  := coalesce((select num_value from public.gl_settings where key='clawback_ban_days'), 90)::int;
  v_admin := coalesce((select split_part(value,',',1) from public.app_secrets where key='admin_emails'),'management@quotesdone.com');

  for r in
    select d.id, d.supplier_id, d.amount_due, d.admin_fee, d.interest_amount, d.due_date,
           l.company_name, coalesce(l.claimed_by,l.email) as email,
           l.accepted_terms_at, l.accepted_terms_version, l.signed_terms_path, l.banned
    from public.supplier_dues d
    join public.leads l on l.id = d.supplier_id
    where d.paid_at is null
      and coalesce(d.status,'') not in ('paid','settled','waived','cancelled')
      and coalesce(d.amount_due,0) > 0
      and d.due_date is not null
      and current_date >= (d.due_date::date + v_days)
      and d.legal_escalated_at is null
  loop
    update public.supplier_dues
       set status = 'legal', legal_stage = 'pending_case', legal_escalated_at = now()
     where id = r.id;

    update public.leads
       set banned = true,
           banned_reason = 'Unpaid refund clawback of AED ' ||
                           round(coalesce(r.amount_due,0)+coalesce(r.admin_fee,0)+coalesce(r.interest_amount,0),2) ||
                           ' more than ' || v_days || ' days past due (due ' || r.due_date::date || ').',
           matching_blocked = true,
           matching_block_reason = 'Banned: unpaid refund clawback escalated to legal'
     where id = r.supplier_id;

    insert into public.founder_alerts(level, event, detail, channel)
    values ('crit', 'supplier_banned_legal',
      coalesce(r.company_name,'Supplier #'||r.supplier_id) || ' has been banned and due #' || r.id ||
      ' escalated to legal: AED ' || round(coalesce(r.amount_due,0)+coalesce(r.admin_fee,0)+coalesce(r.interest_amount,0),2) ||
      ' unpaid for over ' || v_days || ' days. ' ||
      case when r.accepted_terms_at is null
           then '*** NO SIGNED TERMS ON RECORD - the supplier agreement cannot be produced as evidence, so a filing may not be supportable. Verify before instructing the legal agent. ***'
           else 'Terms accepted ' || r.accepted_terms_at::date || ' (version ' || coalesce(r.accepted_terms_version,'?') || ') - available as supporting evidence.'
      end, 'system');

    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_board_report()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  inq_t int; inq_p int; q_t int; q_p int; c_t int; c_p int; s_t int; s_p int;
  rev_t numeric; rev_p numeric; conv numeric; qpr numeric;
  gap int; expired int; crit int; gatepass numeric;
  health jsonb; eval jsonb; officer text; topcats text;
  wtrend text; body text; owner text; d jsonb;
begin
  select count(*) filter (where created_at>=now()-interval '7 days'),
         count(*) filter (where created_at>=now()-interval '14 days' and created_at<now()-interval '7 days')
    into inq_t, inq_p from inquiries;
  select count(*) filter (where created_at>=now()-interval '7 days'),
         count(*) filter (where created_at>=now()-interval '14 days' and created_at<now()-interval '7 days')
    into q_t, q_p from quotes;
  select count(*) filter (where created_at>=now()-interval '7 days'),
         count(*) filter (where created_at>=now()-interval '14 days' and created_at<now()-interval '7 days')
    into c_t, c_p from customers;
  select count(*) filter (where registration_submitted_at>=now()-interval '7 days'),
         count(*) filter (where registration_submitted_at>=now()-interval '14 days' and registration_submitted_at<now()-interval '7 days')
    into s_t, s_p from leads;
  select coalesce(sum(reveal_fee) filter (where revealed_at>=now()-interval '7 days'),0),
         coalesce(sum(reveal_fee) filter (where revealed_at>=now()-interval '14 days' and revealed_at<now()-interval '7 days'),0)
    into rev_t, rev_p from transactions where coalesce(refund_status,'')<>'approved';
  select round(100.0*count(distinct t.inquiry_id)/nullif(count(distinct i.id),0),1) into conv
    from inquiries i left join transactions t on t.inquiry_id=i.id where i.created_at>=now()-interval '30 days';
  select round(avg(qc),1) into qpr from (select count(*) qc from quotes q join inquiries i on i.id=q.inquiry_id where i.created_at>=now()-interval '30 days' group by q.inquiry_id) z;
  select count(*) into gap from inquiries i where i.status not in ('completed','accepted','closed','cancelled') and not exists(select 1 from inquiry_matches m where m.inquiry_id=i.id);
  begin select count(*) into expired from leads where license_expiry<current_date and coalesce(approval_status,'')='approved'; exception when others then expired:=0; end;
  select count(*) into crit from founder_alerts where level='critical' and created_at>=now()-interval '7 days';
  select round(100.0*count(*) filter (where nullif(quality->>'score','')::numeric>=60)/nullif(count(*) filter (where quality is not null),0),1) into gatepass
    from quotes where created_at>=now()-interval '7 days';
  begin select public.fn_health_index() into health; exception when others then health:=null; end;
  begin select public.fn_eval_snapshot(30) into eval; exception when others then eval:=null; end;
  select string_agg(cat,', ') into topcats from (select coalesce(nullif(category,''),'(uncat)') cat, count(*) n from inquiries where created_at>=now()-interval '7 days' group by 1 order by n desc limit 5) z;
  officer := public.fn_officer_recs(8);

  wtrend :=
    '- RFQs: '||inq_t||' (prev '||inq_p||')'||E'\n'||
    '- Quotes: '||q_t||' (prev '||q_p||')'||E'\n'||
    '- New customers: '||c_t||' (prev '||c_p||')'||E'\n'||
    '- New supplier registrations: '||s_t||' (prev '||s_p||')'||E'\n'||
    '- Revenue: AED '||round(rev_t)||' (prev AED '||round(rev_p)||')';

  d := jsonb_build_array();
  if expired>0 then d := d||to_jsonb('Review '||expired||' supplier(s) with expired trade licence'::text); end if;
  if crit>0 then d := d||to_jsonb('Address '||crit||' critical alert(s) from this week'::text); end if;
  if gap>0 then d := d||to_jsonb('Decide sourcing for '||gap||' unmatched demand item(s)'::text); end if;

  body := public.fn_report_skeleton(
    'QuotesDone Weekly Board Report — '||to_char(current_date,'DD Mon YYYY'),
    'Marketplace health '||coalesce(health->>'index','—')||'/100 ('||coalesce(health->>'band','no data')||'). '||
      inq_t||' RFQs and '||q_t||' quotes this week; revenue AED '||round(rev_t)||'; 30-day conversion '||coalesce(conv::text,'—')||'%.',
    jsonb_build_array(
      jsonb_build_object('heading','Key Metrics (this week)','body',
        'RFQs '||inq_t||' · Quotes '||q_t||' · Avg quotes/RFQ (30d) '||coalesce(qpr::text,'—')||' · Conversion (30d) '||coalesce(conv::text,'—')||'% · Revenue AED '||round(rev_t)||' · Quote-gate pass '||coalesce(gatepass::text,'—')||'%'),
      jsonb_build_object('heading','Trends (WoW)','body',wtrend),
      jsonb_build_object('heading','Growth','body','Top categories: '||coalesce(topcats,'—')),
      jsonb_build_object('heading','AI Performance','body','Health index '||coalesce(health->>'index','—')||'/100; eval sample '||coalesce(eval->'samples'->>'quotes','0')||' quotes, gate pass '||coalesce(gatepass::text,'—')||'%.'),
      jsonb_build_object('heading','Issues','body','Supply gaps: '||gap||' · Expired licences: '||expired||' · Critical alerts (7d): '||crit),
      jsonb_build_object('heading','Recommendations (officers)','body',coalesce(officer,'No officer recommendations available yet.'))
    ),
    d,
    'Health: '||coalesce(health::text,'n/a')||E'\n'||'Eval: '||coalesce(eval::text,'n/a'));

  insert into public.board_reports(week_start, title, body, kpis)
  values (date_trunc('week',current_date)::date,
          'QuotesDone Weekly Board Report — '||to_char(current_date,'DD Mon YYYY'), body,
          jsonb_build_object('rfqs',inq_t,'quotes',q_t,'customers',c_t,'suppliers',s_t,'revenue',rev_t,'conversion',conv,'gate_pass',gatepass,'health',(health->>'index')));

  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into owner from app_secrets where key='admin_emails';
  insert into notifications(type,to_email,to_role,channel,subject,body)
  values ('board_report', coalesce(owner,'management@quotesdone.com'),'admin','email',
          'QuotesDone Weekly Board Report — '||to_char(current_date,'DD Mon'), body);
end $function$


CREATE OR REPLACE FUNCTION public.fn_budget_create(p_name text, p_year integer, p_by text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare b bigint;
begin
  insert into public.budgets(name,fiscal_year,created_by) values (p_name,p_year,p_by) returning id into b;
  return b;
end $function$


CREATE OR REPLACE FUNCTION public.fn_budget_set(p_budget bigint, p_account text, p_month date, p_amount numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
  insert into public.budget_lines(budget_id,account_code,period_month,amount)
    values (p_budget, p_account, date_trunc('month',p_month)::date, round(p_amount,2))
  on conflict (budget_id,account_code,period_month)
    do update set amount = excluded.amount;
end $function$


CREATE OR REPLACE FUNCTION public.fn_budget_set_annual(p_budget bigint, p_account text, p_amount numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare yr int; base numeric(18,2); rem numeric(18,2); mth date; i int; amt numeric(18,2);
begin
  select fiscal_year into yr from public.budgets where id=p_budget;
  if yr is null then raise exception 'budget % not found', p_budget; end if;
  base := round(round(p_amount,2)/12, 2);
  rem  := round(p_amount,2) - base*12;                 -- rounding remainder to last month
  for i in 0..11 loop
    mth := make_date(yr,1,1) + (i||' months')::interval;
    amt := base + case when i=11 then rem else 0 end;
    perform public.fn_budget_set(p_budget, p_account, mth, amt);
  end loop;
end $function$


CREATE OR REPLACE FUNCTION public.fn_cancel_inquiry(p_inquiry uuid, p_customer uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v inquiries%rowtype; v_paid boolean; v_cnt int; v_warned boolean:=false; v_email text;
begin
  select * into v from inquiries where id=p_inquiry;
  if not found then return jsonb_build_object('error','inquiry_not_found'); end if;
  if p_customer is not null and v.customer_id is distinct from p_customer then
    return jsonb_build_object('error','not_your_inquiry'); end if;
  if v.status='cancelled' or v.pipeline_stage='cancelled' then
    return jsonb_build_object('ok',true,'already_cancelled',true); end if;
  select exists(select 1 from transactions where inquiry_id=p_inquiry) into v_paid;
  if v_paid or v.status in ('revealed','completed') or v.pipeline_stage in ('revealed','won') then
    return jsonb_build_object('error','already_revealed',
      'message','This request already has an active revealed deal and cannot be cancelled. You can close it instead.'); end if;

  update inquiries set status='cancelled', pipeline_stage='cancelled', outcome='cancelled',
      lost_reason=coalesce(p_reason,'customer_cancelled'), completed_at=now(), stage_changed_at=now()
    where id=p_inquiry;
  insert into inquiry_cancellations(inquiry_id,customer_id,reason) values (p_inquiry, v.customer_id, p_reason);

  select count(*) into v_cnt from inquiry_cancellations where customer_id=v.customer_id and created_at > now()-interval '30 days';
  if v.customer_id is not null and v_cnt >= 3 then
    select email into v_email from customers where id=v.customer_id;
    if v_email is not null and position('@' in v_email)>1
       and not exists (select 1 from notifications where type='cancel_warning' and to_email=v_email and created_at > now()-interval '30 days') then
      insert into notifications(type,to_email,to_role,inquiry_id,subject,body,channel,status)
      values('cancel_warning', v_email, 'customer', p_inquiry,
        'A quick note about cancelled requests',
        'We noticed a few of your recent requests were cancelled. That is completely fine — but every request you post is prepared and quoted by suppliers who set aside real time for it. To keep things fair for them, we kindly ask that you post requests you intend to proceed with. If you would like help scoping a job before posting, our team is glad to assist.',
        'email','queued');
      v_warned:=true;
    end if;
  end if;
  return jsonb_build_object('ok',true,'cancelled',true,'cancellations_30d',v_cnt,'warned',v_warned);
end $function$


CREATE OR REPLACE FUNCTION public.fn_category_expert_ref(p_category text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_slug text; v_txt text;
begin
  v_slug := case
    when p_category ~* 'cctv|security|surveillance' then 'cctv-security'
    when p_category ~* 'hvac|air.?con|ac-' then 'ac-maintenance'
    when p_category ~* 'duct' then 'ac-duct-cleaning'
    when p_category ~* 'glass|glaz|alumin' then 'aluminium-glass'
    when p_category = 'carpentry' then 'carpentry-joinery'
    when p_category ~* 'joinery|kitchen' then 'joinery-kitchens'
    when p_category ~* 'tiling|tile|marble|granite' then 'tiling-marble'
    when p_category ~* 'gypsum|false.?ceiling|ceiling' then 'false-ceiling'
    when p_category ~* 'upholstery|blind|curtain' then 'curtains-blinds'
    when p_category ~* 'fit.?out' then 'commercial-retail-fitout'
    when p_category ~* 'combined.?mep|^mep$' then 'combined-mep'
    when p_category ~* 'steel|fabrication' then 'structural-steel-fabrication'
    when p_category ~* 'pest' then 'pest-control'
    when p_category ~* 'tent|shade' then 'tents-and-shade-structures'
    when p_category ~* 'general|other|handyman|facilit' then coalesce(
        (select 'general-services-other' where exists (select 1 from agent_knowledge where agent_key='cat:general-services-other')), p_category)
    else p_category end;
  select string_agg('## '||topic||E'\n'||content, E'\n\n')
    into v_txt from agent_knowledge
    where agent_key = 'cat:'||v_slug
      and topic in ('Pricing benchmarks & red flags','Quote analysis & comparison',
                    'Standards, materials & specifications','Field expertise — UAE codes, standards & specs');
  return left(coalesce(v_txt,''), 4500);
end $function$


CREATE OR REPLACE FUNCTION public.fn_category_knowledge_promote()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_slug text; v_know text; v_name text; r jsonb;
begin
  if NEW.kind='category_knowledge' and NEW.status in ('approved','done')
     and coalesce(OLD.status,'') not in ('approved','done') then
    v_slug := NEW.detail->>'slug'; v_know := NEW.detail->>'knowledge'; v_name := NEW.detail->>'name';
    if v_slug is not null and v_know is not null then
      -- publish the quoting-knowledge blob live (full parity) if not already present
      if not exists (select 1 from agent_knowledge where agent_key='cat:'||v_slug) then
        insert into agent_knowledge(agent_key,topic,content,priority,created_at,updated_at)
        values ('cat:'||v_slug, coalesce(v_name,v_slug), v_know, 100, now(), now());
      else
        update agent_knowledge set content=v_know, updated_at=now() where agent_key='cat:'||v_slug;
      end if;
      -- apply the proposed regulation -> category mapping
      for r in select * from jsonb_array_elements(coalesce(NEW.detail->'reg_matches','[]'::jsonb)) loop
        update regulations
          set categories = array(select distinct e from unnest(coalesce(categories,'{}'::text[]) || array[v_slug]) e)
          where id::text = (r->>'id') and not (v_slug = any(coalesce(categories,'{}'::text[])));
      end loop;
    end if;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_category_sales(p_min_age_hours integer DEFAULT 24)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  rec record; v_hot int := 0; v_gap int := 0; v_cats int := 0; v_slug text; v_label text;
begin
  ---------------------------------------------------------------- HOT LEADS
  -- Quotes are in, the customer has not revealed. Every one of these is uncollected revenue.
  for rec in
    select i.id, i.category, i.emirate, count(q.id) as n_quotes, min(q.created_at) as first_quote
      from inquiries i
      join quotes q on q.inquiry_id = i.id and q.status = 'submitted'
     where not exists (select 1 from transactions tr where tr.inquiry_id = i.id and tr.revealed_at is not null)
       and coalesce(i.status,'') <> 'split'
     group by i.id, i.category, i.emirate
    having min(q.created_at) < now() - make_interval(hours => p_min_age_hours)
  loop
    v_slug := 'cat:' || lower(coalesce(nullif(trim(rec.category),''),'uncategorised'));
    v_label := coalesce(nullif(trim(rec.category),''),'Uncategorised');
    -- one open hot_lead per inquiry
    if not exists (select 1 from agent_actions
                    where kind = 'hot_lead' and target_id = rec.id::text
                      and status in ('needs_review','pending','open','proposed')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
      values (v_slug,'hot_lead','needs_review','medium',
              'Hot lead — ' || v_label || ' / ' || coalesce(nullif(trim(rec.emirate),''),'UAE') ||
                ': ' || rec.n_quotes || ' quote(s), not revealed',
              'nudge the customer to reveal',
              jsonb_build_object('inquiry_id',rec.id,'category',rec.category,'emirate',rec.emirate,
                                 'quotes',rec.n_quotes,'waiting_since',rec.first_quote),
              'inquiries', rec.id::text);
      v_hot := v_hot + 1;
    end if;
  end loop;

  ---------------------------------------------------------------- SUPPLY GAPS
  -- Category+emirate combinations where finalized demand found nobody. Feeds supplier activation.
  for rec in
    select coalesce(nullif(trim(i.category),''),'uncategorised') as category,
           coalesce(nullif(trim(i.emirate),''),'UAE') as emirate,
           count(*) as n_inquiries
      from inquiries i
     where i.rfq_ready is true
       and coalesce(i.status,'') <> 'split'
       and not exists (select 1 from inquiry_matches m where m.inquiry_id = i.id)
       and i.created_at > now() - interval '30 days'
     group by 1,2
  loop
    v_slug := 'cat:' || lower(rec.category);
    if not exists (select 1 from agent_actions
                    where kind = 'supply_gap' and agent = v_slug
                      and detail->>'emirate' = rec.emirate
                      and status in ('needs_review','pending','open','proposed')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
      values (v_slug,'supply_gap','needs_review','high',
              'Supply gap — ' || rec.category || ' / ' || rec.emirate || ': no suppliers matched',
              'source or activate suppliers in this category',
              jsonb_build_object('category',rec.category,'emirate',rec.emirate,'inquiries',rec.n_inquiries),
              'inquiries', null);
      v_gap := v_gap + 1;
    end if;
  end loop;

  select count(distinct coalesce(nullif(trim(category),''),'uncategorised')) into v_cats from inquiries;

  insert into agent_runs(agent,status,counts,note,started_at,finished_at)
  values ('category_sales','ok',
          jsonb_build_object('hot',v_hot,'gaps',v_gap,'categories',v_cats),
          'category sweep: ' || v_hot || ' new hot lead(s), ' || v_gap || ' new supply gap(s) across ' || v_cats || ' categories',
          now(), now());

  return json_build_object('hot',v_hot,'gaps',v_gap,'categories',v_cats);
end $function$


CREATE OR REPLACE FUNCTION public.fn_chief_of_staff()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare disp jsonb; exec jsonb; health jsonb; ops jsonb; rev jsonb;
  n_pending int; n_aging int; n_depts int; brief text; recs text; dept_txt text; esc_txt text; owner text;
  prioritized jsonb; run_id bigint;
begin
  disp := public.fn_autonomy_dispose();
  exec := public.fn_ws_exec();
  health := exec->'command'->'health'; ops := exec->'command'->'ops'; rev := ops->'revenue';

  select count(*) into n_pending from public.agent_actions where status in ('pending','held_for_review','proposed','open','needs_review');
  select count(*) into n_aging from public.agent_actions
    where status in ('pending','held_for_review','proposed','open','needs_review') and created_at < now()-interval '3 days';
  select count(distinct agent) into n_depts from public.agent_runs where started_at > now()-interval '24 hours';

  select string_agg(line, E'\n' order by line) into dept_txt from (
    select '- '||agent||': '||count(*)||' runs'||
           case when count(*) filter (where status='error')>0 then ' ('||count(*) filter (where status='error')||' failed)' else '' end as line
    from public.agent_runs where started_at > now()-interval '24 hours' group by agent
  ) d;

  select string_agg('- ['||coalesce(risk,'?')||'] '||coalesce(title,kind)||' ('||agent||')', E'\n') into esc_txt from (
    select agent,risk,title,kind from public.agent_actions
     where status in ('pending','held_for_review','proposed','open','needs_review') order by created_at asc limit 10
  ) e;

  select coalesce(jsonb_agg(x order by cat asc),'[]'::jsonb) into prioritized from (
    select jsonb_build_object('id',id,'agent',agent,'risk',risk,'title',title,
             'age_days',round(extract(epoch from (now()-created_at))/86400)) x, created_at cat
    from public.agent_actions where status in ('pending','held_for_review','proposed','open','needs_review')
    order by created_at asc limit 15
  ) s;

  recs := '';
  if n_pending>0 then recs := recs||'1) '||n_pending||' item(s) in your queue (payments, deletions, flagged suppliers, marketing to post, BD to enable, to-dos).'||E'\n'; end if;
  if n_aging>0 then recs := recs||'2) '||n_aging||' waited >3 days — action or dismiss.'||E'\n'; end if;
  if (health->>'band') is not null and lower(health->>'band')<>'good'
     then recs := recs||'3) Health "'||(health->>'band')||'" ('||coalesce(health->>'index','?')||'/100).'||E'\n'; end if;
  if recs='' then recs := 'Queue clear. Everything auto-handled where safe.'; end if;

  brief := 'Chief of Staff — daily briefing ('||to_char(now(),'DD Mon YYYY')||')'||E'\n\n'
    ||'HEADLINE: auto-approved '||coalesce(disp->>'approved_suppliers','0')||' clean supplier(s), auto-cleared '
      ||coalesce(disp->>'auto_cleared_logged','0')||' logged alert(s). '||n_pending||' item(s) in your queue. Health '
      ||coalesce(health->>'index','?')||'/100 ('||coalesce(health->>'band','?')||').'||E'\n\n'
    ||'YOUR QUEUE:'||E'\n'||coalesce(esc_txt,'- Empty.')||E'\n\n'
    ||'DEPARTMENTS (24h):'||E'\n'||coalesce(dept_txt,'- No agent runs in the last 24h.')||E'\n\n'
    ||'KPIs: revenue month '||coalesce(rev->>'month_aed','0')||' AED, cash received '||coalesce(rev->>'cash_received_aed','0')
      ||' AED, pending fees '||coalesce(rev->>'pending_fees_aed','0')||' AED, active RFQs '||coalesce(ops->'marketplace'->>'active_rfqs','0')||'.'||E'\n\n'
    ||'RECOMMENDATIONS:'||E'\n'||recs;

  insert into public.agent_runs(agent,started_at,finished_at,status,counts,note)
    values('chief_of_staff',now(),now(),'ok',
      jsonb_build_object('approved_suppliers',disp->>'approved_suppliers','auto_cleared',disp->>'auto_cleared_logged',
        'in_queue',n_pending,'aging',n_aging,'departments',n_depts),'coordination + autonomy v2')
    returning id into run_id;

  insert into public.agent_actions(agent,kind,status,risk,title,recommendation,target_table,target_id,detail)
    values('chief_of_staff','exec_briefing','auto_done','low',
      'Chief of Staff briefing — '||n_pending||' in queue, '||coalesce(disp->>'auto_cleared_logged','0')||' auto-cleared',
      'Informational.', null, null,
      jsonb_build_object('briefing',brief,'prioritized',prioritized,'autonomy',disp,'health',health->>'index','in_queue',n_pending));

  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into owner from public.app_secrets where key='admin_emails';
  owner := coalesce(nullif(trim(owner),''),'management@quotesdone.com');
  insert into public.notifications(type,to_email,to_role,channel,subject,body)
    values('chief_of_staff', owner, 'admin','email',
      'Chief of Staff — '||n_pending||' in your queue, health '||coalesce(health->>'index','?')||'/100', brief);

  return jsonb_build_object('ok',true,'autonomy',disp,'in_queue',n_pending,'aging',n_aging,'departments',n_depts,'run_id',run_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_collections()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_run bigint; v_reminded int:=0; r record;
begin
  insert into agent_runs(agent, started_at) values ('collections', now()) returning id into v_run;
  -- NO commission is charged on won jobs (founder policy: zero commission). This engine never creates dues.
  -- The only supplier charge is the non-response fine (= the refunded reveal fee), created by qd_on_refund_resolved,
  -- and enforced by a matching block until settled. Here we only send a gentle reminder; no extra fees are added.
  for r in select d.*, l.claimed_by, l.email as lead_email, l.company_name
           from supplier_dues d join leads l on l.id=d.supplier_id
           where d.status in ('due','pending','reminded')
             and (d.last_reminder_at is null or d.last_reminder_at < now()-interval '4 days')
             and d.reminders < 3
  loop
    update supplier_dues set status='reminded', reminders=reminders+1, last_reminder_at=now() where id=r.id;
    insert into notifications(type,to_email,to_role,channel,status,lead_id,subject,body)
      values ('nonresponse_reminder', coalesce(r.claimed_by,r.lead_email), 'supplier', 'portal', 'portal', r.supplier_id,
        'Reminder: outstanding non-response charge',
        'Reminder: a non-response charge of AED '||round(r.amount_due)||' is outstanding on your account. This equals the reveal fee that was refunded to a customer because a paid reveal was not responded to. Please settle it on the portal to lift the hold on new matches. QuotesDone charges no commission on won jobs.');
    v_reminded := v_reminded + 1;
  end loop;
  update agent_runs set finished_at=now(), status='ok', counts=jsonb_build_object('reminders',v_reminded,'commission_charged',0) where id=v_run;
end;$function$


CREATE OR REPLACE FUNCTION public.fn_company_brief(p_max_chars integer DEFAULT 1600)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s jsonb; out text; d jsonb;
begin
  s := fn_company_state();
  out := 'COMPANY SELF-KNOWLEDGE (authoritative org facts — you may answer any question about the company from this):'||E'\n'
       ||'Vision: '||(s->>'vision')||E'\n'
       ||'Totals: '||(s->'totals'->>'departments')||' departments, '||(s->'totals'->>'brain_agents')||' brain agents, '
       ||(s->'totals'->>'category_sales_agents')||' category sales agents, '||(s->'totals'->>'tools_wired')||' wired tools, '
       ||(s->'totals'->>'open_objectives')||' open objectives, '||(s->'totals'->>'open_tasks')||' open tasks.'||E'\n'
       ||'Departments (lead · brain agents · north star):'||E'\n';
  for d in select * from jsonb_array_elements(s->'departments') loop
    out := out || '- '||(d->>'name')||' ['||(d->>'dept')||']: lead '||coalesce(d->>'lead_agent','—')
                || ', '||(d->>'headcount')||' agent(s)';
    if jsonb_array_length(d->'brain_agents') > 0 then
      out := out || ' ('||replace(replace(replace((d->'brain_agents')::text,'"',''),'[',''),']','')||')';
    end if;
    out := out || ', north star: '||coalesce(d->>'north_star','—')||E'\n';
    exit when length(out) > p_max_chars;
  end loop;
  return left(out, greatest(p_max_chars, 400));
end $function$


CREATE OR REPLACE FUNCTION public.fn_company_facts_sync()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c record; pct text; capnote text; txt text;
begin
  select * into c from pricing_config where id=1; if c is null then return; end if;
  pct := trim(to_char(coalesce(c.standard_reveal_rate,0)*100,'FM990.##'))||'%';
  capnote := case when coalesce(c.standard_reveal_cap,0) >= 1000000 then 'no cap' else 'capped at AED '||trim(to_char(c.standard_reveal_cap,'FM999999990')) end;
  txt := 'PRICING & FEES — LIVE, AUTO-SYNCED FROM pricing_config (authoritative; OVERRIDES any pricing figure stated elsewhere). '
    ||'Customer REVEAL FEE: '||pct||' of the accepted quotation value ('||capnote||'), paid by the customer to unlock their chosen supplier. '
    ||'Suppliers pay NO commission on won jobs. Supplier registration: first '||c.supplier_free_count||' suppliers FREE, then AED '||trim(to_char(c.supplier_reg_fee,'FM999990.##'))||'/'||c.supplier_reg_period||'. '
    ||'Non-response window: '||c.refund_window_working_days||' working days — if a revealed supplier does not respond in that window and cannot be reached, the customer reveal fee is refunded and the supplier is charged a non-response fee equal to that reveal fee and blocked from matching until paid. '
    ||'There is NO 2% fee and NO supplier commission — never quote those. (Auto-updated '||to_char(now(),'YYYY-MM-DD HH24:MI')||' UTC.)';
  update agent_knowledge set content=txt, priority=100, updated_at=now() where agent_key='_global' and topic='Pricing & fees (LIVE — auto-synced)';
  if not found then insert into agent_knowledge(agent_key,topic,content,priority,updated_at) values ('_global','Pricing & fees (LIVE — auto-synced)',txt,100,now()); end if;
end $function$


CREATE OR REPLACE FUNCTION public.fn_company_faq_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_body text; n int;
begin
  select count(*) into n from company_faq where status='approved';
  select 'QUOTESDONE COMPANY FAQ — canonical answers every agent must use verbatim-in-spirit (founder-approved). '||
         'If asked anything here, answer consistently with this. Do not contradict it or invent beyond it.'||E'\n\n'||
         coalesce(string_agg(
           '## ['||section||'] '||question||E'\n'||coalesce(answer,'(no answer yet)')||
           case when audience<>'all' then E'\n(Audience: '||audience||')' else '' end,
           E'\n\n' order by section, sort, id), '')
    into v_body
  from company_faq where status='approved';

  if n=0 then
    delete from agent_knowledge where agent_key='_global' and topic='Company FAQ (canonical answers)';
    return jsonb_build_object('synced',0);
  end if;
  if exists(select 1 from agent_knowledge where agent_key='_global' and topic='Company FAQ (canonical answers)') then
    update agent_knowledge set content=v_body, updated_at=now()
      where agent_key='_global' and topic='Company FAQ (canonical answers)';
  else
    insert into agent_knowledge(agent_key,topic,content,priority,created_at,updated_at)
      values('_global','Company FAQ (canonical answers)', v_body, 96, now(), now());
  end if;
  return jsonb_build_object('synced', n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_company_state()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with depts as (
    select d.dept_key, d.name, d.charter, d.north_star, d.lead_agent, d.active,
           coalesce((select array_agg(a.agent_key order by a.agent_key) from org_agents a where a.department=d.dept_key and a.active), '{}') as brain_agents,
           (select count(*) from org_agents a where a.department=d.dept_key and a.active) as brain_count,
           (select count(*) from org_action_executor e where e.department=d.dept_key and e.active) as tool_count
    from org_departments d where d.active
  )
  select jsonb_build_object(
    'vision', (select vision from company_vision where id=1),
    'mission', (select mission from company_vision where id=1),
    'as_of', now(),
    'totals', jsonb_build_object(
      'departments', (select count(*) from depts),
      'brain_agents', (select count(*) from org_agents where active),
      'category_sales_agents', (select count(*) from category_agents),
      'tools_wired', (select count(*) from org_action_executor where active),
      'open_objectives', (select count(*) from org_objectives where status not in ('done','cancelled')),
      'open_tasks', (select count(*) from org_tasks where status in ('assigned','proposed','in_progress'))
    ),
    'departments', (select jsonb_agg(jsonb_build_object(
        'dept', dept_key, 'name', name, 'charter', charter, 'north_star', north_star,
        'lead_agent', lead_agent, 'brain_agents', brain_agents,
        'headcount', brain_count + case when dept_key='procurement' then (select count(*) from category_agents) else 0 end,
        'tools_wired', tool_count) order by dept_key) from depts)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_cron_liveness()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog', 'cron'
AS $function$
declare v_age numeric; v_last timestamptz;
begin
  select max(start_time) into v_last from cron.job_run_details;
  if v_last is null then
    return jsonb_build_object('healthy', false, 'newest_run_age_min', null, 'note', 'no cron run history');
  end if;
  v_age := extract(epoch from (now() - v_last))/60.0;
  return jsonb_build_object(
    'healthy', v_age <= 20,               -- crons run every few minutes; >20min silence = scheduler down
    'newest_run_age_min', round(v_age,1),
    'checked_at', now());
exception when others then
  return jsonb_build_object('healthy', null, 'error', sqlerrm);
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_stats(p_customer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb; v_inq int; v_open int; v_quotes int; v_deals int; v_spend numeric; v_list jsonb; v_hist jsonb;
begin
  select count(*) into v_inq from inquiries where customer_id=p_customer and parent_inquiry_id is null;
  select count(*) into v_open from inquiries where customer_id=p_customer and parent_inquiry_id is null and coalesce(status,'') not in ('completed','closed','cancelled','split');
  select count(*) into v_quotes from quotes q where q.status <> 'draft' and q.inquiry_id in (select id from inquiries where customer_id=p_customer);
  select count(*) into v_deals from transactions where customer_id=p_customer;
  select coalesce(sum(coalesce(reveal_fee,0)+coalesce(app_fee,0)),0) into v_spend from transactions where customer_id=p_customer and coalesce(refund_status,'')<>'approved';
  select jsonb_agg(x order by (x->>'created_at') desc) into v_list from (
    select jsonb_build_object(
      'id', i.id, 'category', i.category, 'emirate', i.emirate, 'status', i.status,
      'created_at', i.created_at, 'pipeline_stage', i.pipeline_stage, 'outcome', i.outcome,
      'has_drawing', (i.drawing_file_path is not null), 'boq_confidence', i.boq_confidence,
      'quotes_count', (select count(*) from quotes q where q.inquiry_id=i.id and q.status <> 'draft'),
      'minutes_since', round(extract(epoch from (now()-i.created_at))/60.0)::int,
      'editable', (i.status='sent') and (now()-i.created_at) < interval '60 minutes',
      'edit_minutes_left', greatest(0, 60 - round(extract(epoch from (now()-i.created_at))/60.0)::int)
    ) x from inquiries i where i.customer_id=p_customer and i.parent_inquiry_id is null
  ) t;
  with months as (select date_trunc('month',(now()-(n||' month')::interval)) m from generate_series(0,11) n),
  ib as (select date_trunc('month',created_at) m, count(*) c from inquiries where customer_id=p_customer and parent_inquiry_id is null group by 1)
  select jsonb_agg(jsonb_build_object('month',to_char(months.m,'Mon YY'),'inquiries',coalesce(ib.c,0)) order by months.m)
    into v_hist from months left join ib on ib.m=months.m;
  v := jsonb_build_object(
    'customer_id', p_customer,'inquiries_total', v_inq,'open_inquiries', v_open,
    'quotes_received', v_quotes,'avg_quotes_per_inquiry', round(v_quotes::numeric/nullif(v_inq,0),1),
    'deals', v_deals,'total_spend', v_spend,
    'inquiries', coalesce(v_list,'[]'::jsonb),'history_12m', v_hist);
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_customer_success()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_kpis jsonb; n_checkin int:=0; n_reengage int:=0; n_esc int:=0; rec record; v_subject text; v_body text;
begin
  -- snapshot KPIs
  select to_jsonb(k) into v_kpis from public.customer_kpis k;
  insert into public.customer_kpi_snapshots(snapshot_date,kpis) values(current_date,coalesce(v_kpis,'{}'::jsonb))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  -- FOLLOW-UP (operational, auto-send): project check-in — revealed but not completed for 7+ days
  for rec in
    select i.id as inquiry_id, i.customer_id, c.full_name, c.email, i.category
    from inquiries i join customers c on c.id=i.customer_id
    where i.status='revealed' and i.completed_at is null
      and coalesce(i.stage_changed_at,i.created_at) < now()-interval '7 days'
      and coalesce(c.banned,false)=false and c.email like '%@%'
      and not exists (select 1 from notifications n where n.type='customer_checkin' and n.body like '%'||i.id::text||'%' and n.created_at>now()-interval '21 days')
    limit 200
  loop
    v_subject:='How is your '||coalesce(rec.category,'project')||' going?';
    v_body:='Hi '||coalesce(rec.full_name,'there')||E',\n\nWe wanted to check in on your '||coalesce(rec.category,'project')||' booked through QuotesDone. Is everything going well with your supplier?\n\nIf you need anything — a hand resolving an issue, another quote, or help with your next project — just reply to this email. We are here to help.\n\n(ref '||rec.inquiry_id||')';
    insert into notifications(type,to_email,to_role,channel,subject,body,status)
    values('customer_checkin',rec.email,'customer','email',v_subject,v_body,'queued');
    n_checkin:=n_checkin+1;
  end loop;

  -- FOLLOW-UP (operational, auto-send): re-engagement — last project 30+ days ago, no new inquiry since
  for rec in
    select c.id as customer_id, c.full_name, c.email
    from customers c
    where coalesce(c.banned,false)=false and c.email like '%@%'
      and exists (select 1 from inquiries i where i.customer_id=c.id and (i.status='revealed' or i.completed_at is not null))
      and (select max(created_at) from inquiries i where i.customer_id=c.id) < now()-interval '30 days'
      and not exists (select 1 from notifications n where n.type='customer_reengage' and n.to_email=c.email and n.created_at>now()-interval '45 days')
    limit 200
  loop
    v_subject:='Planning your next project?';
    v_body:='Hi '||coalesce(rec.full_name,'there')||E',\n\nIt has been a little while since your last project on QuotesDone. Whenever you are planning your next one — big or small — post it in a minute and compare anonymous quotes from vetted UAE suppliers.\n\nStart here: https://quotesdone.com/app\n\nHappy to help anytime.';
    insert into notifications(type,to_email,to_role,channel,subject,body,status)
    values('customer_reengage',rec.email,'customer','email',v_subject,v_body,'queued');
    n_reengage:=n_reengage+1;
  end loop;

  -- ESCALATIONS to founder (never auto-resolve): disputes/refunds, reveal non-response, bad reviews, complaints
  for rec in
    select 'dispute' as sig, t.customer_id as cid, coalesce(c.full_name,'customer') as who, t.id::text as ref,
      'Refund/dispute open — review and resolve.' as msg, 'high' as risk
    from transactions t join customers c on c.id=t.customer_id
    where (t.refund_status is not null or (t.refund_requested_at is not null and t.refund_resolved_at is null))
    union all
    select 'reveal_no_response', t.customer_id, coalesce(c.full_name,'customer'), t.id::text,
      'Customer paid to reveal but supplier has not acknowledged within 48h — service risk.', 'high'
    from transactions t join customers c on c.id=t.customer_id
    where t.supplier_ack_at is null and t.revealed_at is not null and t.revealed_at < now()-interval '48 hours' and t.refund_status is null
    union all
    select 'bad_review', r.customer_id, coalesce(c.full_name,'customer'), r.id::text,
      'Low review left ('||r.rating||'/5) — follow up on dissatisfaction.', 'medium'
    from reviews r join customers c on c.id=r.customer_id where r.rating<=2
    union all
    select 'complaint', c.id, coalesce(c.full_name,'customer'), im.id::text,
      'Inbound complaint from customer — needs attention.', 'high'
    from inbound_messages im join customers c on lower(c.email)=lower(im.from_email)
    where im.ai_category ilike '%complaint%' and im.replied_at is null
  loop
    if not exists (select 1 from agent_actions a where a.kind='customer_escalation' and a.detail->>'signal'=rec.sig and a.detail->>'ref'=rec.ref and a.status in ('pending','needs_review')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
      values('customer_success','customer_escalation','pending',rec.risk,
        'Customer '||rec.sig||': '||rec.who, rec.msg,
        jsonb_build_object('signal',rec.sig,'ref',rec.ref,'customer',rec.who),
        'customers', rec.cid::text);
      n_esc:=n_esc+1;
    end if;
  end loop;

  return jsonb_build_object('ran_at',now(),'kpis',v_kpis,'checkins_queued',n_checkin,'reengage_queued',n_reengage,'escalations',n_esc);
end $function$


CREATE OR REPLACE FUNCTION public.fn_data_metrics()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare res jsonb;
begin
  select jsonb_build_object(
    'category_growth', (select coalesce(fn_marketplace_analytics()->'category_growth','[]'::jsonb)),
    'competitive_categories', (select coalesce(fn_marketplace_analytics()->'competitive_categories','[]'::jsonb)),
    'price_spread', (select coalesce(jsonb_agg(jsonb_build_object('category',category,'n',n,'median',median,'p25',p25,'p75',p75) order by n desc),'[]'::jsonb)
        from (select * from category_price_stats order by n desc limit 10) z),
    'monthly_volume', (select coalesce(jsonb_agg(jsonb_build_object('month',m,'rfqs',c) order by m),'[]'::jsonb)
        from (select to_char(date_trunc('month',created_at),'YYYY-MM') m, count(*) c from inquiries where created_at > now()-interval '6 months' group by 1) z)
  ) into res;
  return res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_dbx_safe(x text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select btrim(regexp_replace(regexp_replace(coalesce(x,''),'[\\/:*?"<>|\r\n\t]+',' ','g'),'\s+',' ','g'))
$function$


CREATE OR REPLACE FUNCTION public.fn_decide(p_kind text, p_ctx jsonb, p_actor text DEFAULT 'agent'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare res jsonb; conf numeric; reasons jsonb:='[]'; route text; decision text; sources jsonb:='[]';
begin
  if p_kind='escalate' then
    res := public.fn_should_escalate(p_ctx);
    decision := case when (res->>'escalate')::boolean then 'escalate' else 'proceed' end;
    reasons := res->'reasons'; route := res->>'route_to';
    conf := case when (res->>'escalate')::boolean then 0.9 else 0.8 end;
    sources := to_jsonb(array['decision_policy']);

  elsif p_kind='price' then
    res := public.fn_price_confidence(coalesce(p_ctx->>'category','default'), nullif(p_ctx->>'amount_aed','')::numeric);
    decision := 'priced'; conf := coalesce((res->>'confidence')::numeric, 0.5);
    reasons := jsonb_build_array(coalesce(res->>'band', 'price band computed')); sources := to_jsonb(array['price_confidence']);
    route := 'none';

  elsif p_kind='route_category' then
    route := public.fn_resolve_cat_agent(coalesce(p_ctx->>'category',''));
    decision := coalesce(route,'unmatched'); conf := case when route is null then 0.3 else 0.85 end;
    reasons := jsonb_build_array('mapped category "'||coalesce(p_ctx->>'category','')||'" to agent '||coalesce(route,'(none)'));
    sources := to_jsonb(array['category_agents']);

  elsif p_kind='invite' then
    -- rank approved suppliers for a category (+ optional emirate)
    with pool as (
      select id, company_name, coalesce(capability_score,0) cap, coalesce(app_rating,rating,0) rat, coalesce(rv_response_rate,0) resp
      from leads
      where coalesce(approval_status,'')='approved'
        and (coalesce(p_ctx->>'category','')='' or lower(coalesce(categories,''))||' '||lower(coalesce(sub_type,'')) like '%'||lower(p_ctx->>'category')||'%')
        and (coalesce(p_ctx->>'emirate','')='' or coalesce(p_ctx->>'emirate')= any(coalesce(service_emirates,array[emirate])))
      order by (coalesce(capability_score,0)*0.5 + coalesce(app_rating,rating,0)*8 + coalesce(rv_response_rate,0)*0.3) desc
      limit coalesce((p_ctx->>'n')::int, 5))
    select jsonb_agg(jsonb_build_object('id',id,'name',company_name,'cap',cap,'rating',rat,'response',resp)) into res from pool;
    decision := 'invite_ranked'; conf := case when res is null then 0.2 when jsonb_array_length(res)>=3 then 0.8 else 0.5 end;
    reasons := jsonb_build_array('ranked by capability_score, rating and response rate');
    sources := to_jsonb(array['leads','supplier_capability','response_rate']);
    res := jsonb_build_object('suppliers', coalesce(res,'[]'));

  elsif p_kind='approve' then
    res := public.fn_should_escalate(p_ctx);
    if (res->>'escalate')::boolean then decision:='human_review'; conf:=0.9; reasons:=res->'reasons';
    else decision:='auto_approve'; conf:=0.85; reasons:=jsonb_build_array('within autonomous thresholds'); end if;
    route := res->>'route_to'; sources := to_jsonb(array['decision_policy']);

  else
    decision := 'unsupported_kind'; conf := 0; reasons := jsonb_build_array('no handler for kind '||p_kind); route:='Secretary';
  end if;

  insert into public.decision_log(actor,kind,ctx,decision,confidence,reasons,sources,route_to)
  values (p_actor,p_kind,p_ctx,decision,conf,reasons,sources,route);

  return jsonb_build_object('kind',p_kind,'decision',decision,'confidence',conf,'reasons',reasons,'route_to',route,'sources',sources,'detail',res);
end $function$


CREATE OR REPLACE FUNCTION public.fn_dept_authority(p_dept text, p_action_class text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_tier text; v_thr numeric; v_cap text; v_tier_rk int; v_cap_rk int;
begin
  select max_tier, threshold_aed into v_tier, v_thr
    from public.org_authority where dept_key=p_dept and action_class=p_action_class;
  if v_tier is null then v_tier := 'gated'; end if;   -- unknown action -> default to gated (ask a human)

  -- HARD CAPS (the escalation constitution): these classes can never exceed the cap.
  if p_action_class ~* 'money|payout|payment|gl_|data_delete|delete|purge|secret|auth|password|code_deploy|supplier_ban|ban' then
    v_cap := 'gated';
  elsif p_action_class ~* 'legal_review|recommend' then
    v_cap := 'advisory';
  end if;

  v_tier_rk := case v_tier when 'advisory' then 0 when 'gated' then 1 when 'supervised' then 2 when 'autonomous' then 3 else 1 end;
  if v_cap is not null then
    v_cap_rk := case v_cap when 'advisory' then 0 when 'gated' then 1 when 'supervised' then 2 else 3 end;
    if v_tier_rk > v_cap_rk then v_tier := v_cap; end if;
  end if;
  return jsonb_build_object('dept',p_dept,'action_class',p_action_class,'tier',v_tier,'threshold_aed',v_thr,'capped', v_cap is not null);
end $function$


CREATE OR REPLACE FUNCTION public.fn_dept_library_search(p_dept text, p_query text, p_limit integer DEFAULT 5)
 RETURNS TABLE(id bigint, department text, title text, content text, rank real)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare q_or tsquery; words text[];
begin
  words := array(select w from unnest(regexp_split_to_array(lower(regexp_replace(coalesce(p_query,''),'[^a-z0-9 ]',' ','g')),'\s+')) w where length(w)>2);
  if array_length(words,1) is null then return; end if;
  begin q_or := to_tsquery('english', array_to_string(words,' | ')); exception when others then return; end;
  return query
    select l.id, l.department, l.title, l.content, ts_rank(l.tsv, q_or) as rank
    from dept_library l
    where (p_dept is null or l.department = p_dept) and l.tsv @@ q_or
    order by ts_rank(l.tsv, q_or) desc, l.id
    limit greatest(1, least(coalesce(p_limit,5),20));
end $function$


CREATE OR REPLACE FUNCTION public.fn_doc_control()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_run bigint; v_remind int := 0; v_expired int := 0; r record; v_days int;
begin
  insert into agent_runs(agent, started_at) values ('docs', now()) returning id into v_run;
  for r in select id, company_name, claimed_by, email, license_expiry from leads
           where approval_status='approved' and claimed=true and license_expiry is not null
  loop
    v_days := r.license_expiry - current_date;
    if v_days between 0 and 7 then
      if not exists (select 1 from notifications where lead_id=r.id and type='licence_expiry_reminder' and created_at > now()-interval '6 days') then
        insert into notifications(type,to_email,to_role,channel,lead_id,subject,body)
          values ('licence_expiry_reminder', coalesce(r.claimed_by,r.email), 'supplier', 'email', r.id,
            'Your trade licence expires in '||v_days||' day(s) - QuotesDone',
            'Dear '||coalesce(r.company_name,'partner')||', our records show your trade licence expires on '||to_char(r.license_expiry,'DD Mon YYYY')||' ('||v_days||' day(s) away). Please upload your renewed trade licence in your supplier portal to keep your account active and continue receiving job matches. Portal: https://quotesdone.com/suppliers/');
        v_remind := v_remind + 1;
      end if;
    elsif v_days < 0 then
      if not exists (select 1 from notifications where lead_id=r.id and type='licence_expired' and created_at > now()-interval '7 days') then
        insert into notifications(type,to_email,to_role,channel,lead_id,subject,body)
          values ('licence_expired', coalesce(r.claimed_by,r.email), 'supplier', 'email', r.id,
            'Action needed: your trade licence has expired - QuotesDone',
            'Dear '||coalesce(r.company_name,'partner')||', our records show your trade licence expired on '||to_char(r.license_expiry,'DD Mon YYYY')||'. To keep receiving jobs on QuotesDone, please upload your renewed licence in your portal as soon as possible: https://quotesdone.com/suppliers/');
        insert into agent_actions(agent,kind,status,risk,title,recommendation,target_table,target_id,detail)
          values ('docs','licence_expired','pending','medium',coalesce(r.company_name,'Supplier #'||r.id)||' - trade licence EXPIRED','suspend or chase renewal','leads',r.id::text,jsonb_build_object('expiry',r.license_expiry));
        v_expired := v_expired + 1;
      end if;
    end if;
  end loop;
  update agent_runs set finished_at=now(), status='ok', counts=jsonb_build_object('reminders',v_remind,'expired',v_expired) where id=v_run;
end;$function$


CREATE OR REPLACE FUNCTION public.fn_doc_diff(p_type text, p_id text, p_va integer, p_vb integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a jsonb; b jsonb; k text; res jsonb := '{}';
begin
  select snapshot into a from public.doc_versions where entity_type=p_type and entity_id=p_id and version=p_va;
  select snapshot into b from public.doc_versions where entity_type=p_type and entity_id=p_id and version=p_vb;
  if a is null or b is null then return jsonb_build_object('error','version not found'); end if;
  for k in select distinct key from (select jsonb_object_keys(a) key union select jsonb_object_keys(b)) z loop
    if (a->k) is distinct from (b->k) then
      res := res || jsonb_build_object(k, jsonb_build_object('from', a->k, 'to', b->k));
    end if;
  end loop;
  return jsonb_build_object('entity',p_type||':'||p_id,'from_version',p_va,'to_version',p_vb,'changes',res);
end $function$


CREATE OR REPLACE FUNCTION public.fn_doc_expiry_scan()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare rec record; n int:=0; owner text;
begin
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into owner from app_secrets where key='admin_emails';
  for rec in
    select id, company_name, 'trade licence' as doc, license_expiry as exp from leads where license_expiry is not null and license_expiry <= current_date+30 and coalesce(approval_status,'')='approved'
    union all
    select id, company_name, 'insurance', insurance_expiry from leads where insurance_expiry is not null and insurance_expiry <= current_date+30 and coalesce(approval_status,'')='approved'
    union all
    select id, company_name, 'registration', registration_expires_at::date from leads where registration_expires_at is not null and registration_expires_at::date <= current_date+30 and coalesce(approval_status,'')='approved'
    union all
    select id, company_name, 'ISO certification', iso_expiry from leads where iso_expiry is not null and iso_expiry <= current_date+30 and coalesce(approval_status,'')='approved'
    union all
    select id, company_name, 'manufacturer authorisation', manufacturer_auth_expiry from leads where manufacturer_auth_expiry is not null and manufacturer_auth_expiry <= current_date+30 and coalesce(approval_status,'')='approved'
  loop
    if not exists (select 1 from notifications where type='doc_expiry' and lead_id=rec.id and subject like '%'||rec.doc||'%' and created_at > now()-interval '20 days') then
      insert into notifications(type,to_email,to_role,lead_id,channel,subject,body)
      values ('doc_expiry', owner, 'admin', rec.id, 'email',
        'Supplier document expiring: '||rec.doc,
        coalesce(rec.company_name,'Supplier #'||rec.id)||' — '||rec.doc||' expires '||rec.exp||'. Follow up for renewal.');
      n:=n+1;
    end if;
  end loop;
  return jsonb_build_object('flagged',n,'scanned_at',now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_doc_final_notice(p_days integer DEFAULT 7)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  rec record; v_email int := 0; v_wa int := 0; v_skipped int := 0;
  v_horizon date := current_date + make_interval(days => p_days);
  v_phone text; v_to text; v_label text; v_exp date;
begin
  for rec in
    select id, company_name, claimed_by, email, phone, whatsapp,
           license_expiry, insurance_expiry
      from leads
     where approval_status = 'approved'
       and coalesce(banned,false) = false
       and coalesce(matching_blocked,false) = false
       and ((license_expiry   is not null and license_expiry   between current_date and v_horizon)
         or (insurance_expiry is not null and insurance_expiry between current_date and v_horizon))
  loop
    -- Whichever gating document expires first is the one we lead with.
    if rec.license_expiry is not null and rec.license_expiry between current_date and v_horizon
       and (rec.insurance_expiry is null or rec.license_expiry <= rec.insurance_expiry) then
      v_label := 'trade licence'; v_exp := rec.license_expiry;
    else
      v_label := 'insurance certificate'; v_exp := rec.insurance_expiry;
    end if;

    -- One final notice per document per expiry cycle. Without this the daily cron would send
    -- the same warning seven days running.
    if exists (select 1 from notifications
                where type = 'doc_final_notice' and lead_id = rec.id
                  and subject like '%' || v_label || '%'
                  and created_at > now() - interval '20 days') then
      v_skipped := v_skipped + 1; continue;
    end if;

    v_to := nullif(trim(coalesce(rec.claimed_by, rec.email)), '');
    if v_to is null or position('@' in v_to) = 0 then v_skipped := v_skipped + 1; continue; end if;

    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('doc_final_notice', v_to, 'supplier', rec.id, 'email',
      'Final reminder: your ' || v_label || ' expires on ' || v_exp,
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      'Your ' || v_label || ' on file with QuotesDone expires on ' || v_exp || '.' || chr(10) || chr(10) ||
      'If we do not have a valid copy by then, your account will be paused automatically and you will stop receiving customer requests until it is renewed. This is temporary and there is no fee to restore it.' || chr(10) || chr(10) ||
      'Two ways to fix it, either is fine:' || chr(10) ||
      '  1. Reply to this email with the renewed document attached. Our system reads it and updates your profile automatically.' || chr(10) ||
      '  2. Upload it in the Documents tab of your supplier portal: https://quotesdone.com/portal' || chr(10) || chr(10) ||
      'If you have already renewed, please send us the latest copy so our records match.',
      'queued');
    v_email := v_email + 1;

    -- WhatsApp: queued for the same supplier when we hold a number. Delivery depends on the
    -- approved template described in the header comment.
    v_phone := nullif(trim(coalesce(rec.whatsapp, rec.phone)), '');
    if v_phone is not null then
      insert into notifications(type,to_email,to_role,lead_id,channel,to_phone,subject,body,status)
      values ('supplier_doc_expiry', v_to, 'supplier', rec.id, 'whatsapp', v_phone,
        'Your ' || v_label || ' expires on ' || v_exp,
        'Your ' || v_label || ' expires on ' || v_exp || '. Renew it to keep receiving QuotesDone requests: https://quotesdone.com/portal',
        'queued');
      v_wa := v_wa + 1;
    end if;
  end loop;

  return json_build_object('emails_queued', v_email, 'whatsapp_queued', v_wa,
                           'skipped', v_skipped, 'days_ahead', p_days,
                           'whatsapp_deliverable', false,
                           'whatsapp_note', 'Queued but not deliverable until a supplier_doc_expiry template SID is registered in wa_template_sids.',
                           'ran_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_doc_history(p_type text, p_id text)
 RETURNS TABLE(version integer, changed_fields text[], checksum text, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select version, changed_fields, checksum, created_at from public.doc_versions
   where entity_type=p_type and entity_id=p_id order by version desc $function$


CREATE OR REPLACE FUNCTION public.fn_document_controller()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k record; v_health numeric; v_ret numeric; v_backup numeric; n int;
begin
  select * into k from document_kpis;
  v_ret := round(100.0*(k.total_documents - coalesce(k.past_retention,0))/nullif(k.total_documents,0),1);
  v_backup := case when coalesce(k.days_since_backup,999) <= 10 then 100 when coalesce(k.days_since_backup,999) <= 20 then 60 else 20 end;
  v_health := round(coalesce(k.ocr_coverage_pct,100)*0.30 + coalesce(v_ret,100)*0.35 + v_backup*0.20 + greatest(0,100-coalesce(k.oversized,0)*5)*0.15,1);

  insert into document_kpi_snapshots(snapshot_date,kpis) values (current_date, to_jsonb(k)||jsonb_build_object('doc_health',v_health))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  -- recommendations (founder-visible; the Controller NEVER deletes a document on its own)
  perform doc_rec('past_retention', coalesce(k.past_retention,0) > 0, 'medium', 'Documents past retention period',
    k.past_retention||' document(s) are older than their retention class. Review for archival or deletion — the Controller flags only and never deletes on its own.');
  perform doc_rec('ocr_backlog', coalesce(k.ocr_backlog,0) > 0, 'low', 'Documents pending OCR/processing',
    k.ocr_backlog||' registered document(s) are not fully processed/extracted. Re-run the doc processing pipeline.');
  perform doc_rec('backup_stale', coalesce(k.days_since_backup,999) > 10, 'high', 'Backup may be stale',
    'The last backup to the backups bucket was '||coalesce(k.days_since_backup::text,'never')||' day(s) ago. Confirm the weekly Dropbox backup job is running.');
  perform doc_rec('oversized', coalesce(k.oversized,0) > 0, 'low', 'Oversized files',
    k.oversized||' file(s) exceed 30MB. Consider compressing or archiving to control storage cost.');

  select count(*) into n from agent_actions where agent='document_controller' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'doc_health',v_health,'kpis',to_jsonb(k),'open_tasks',n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_dropbox_list(p_prefix text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'prefix', p_prefix,
    'items', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.is_folder desc, lower(t.name))
      from (
        select id, path, name, is_folder, size, server_modified
        from dropbox_files
        where substring(path, 1, length(path) - length(split_part(path,'/', -1)) - 1) = p_prefix
      ) t
    ), '[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_dues_to_escalate(p_days integer)
 RETURNS TABLE(due_id bigint, supplier_id bigint, principal numeric, currency text, reveal_date date, due_date date, days_overdue integer, company_name text, contact_name text, email text, phone text, trade_license_no text, emirate text, category text, signed_terms_path text, claimed_by text, accepted_terms_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select d.id, d.supplier_id, d.amount_due, coalesce(d.currency,'AED'), d.reveal_date, d.due_date::date,
         (current_date - d.due_date::date) as days_overdue,
         l.company_name, l.contact_name, coalesce(l.claimed_by,l.email) as email, coalesce(l.phone_e164,l.phone),
         l.trade_license_no, l.emirate,
         coalesce(nullif(btrim(split_part(coalesce(l.categories,''),',',1)),''), nullif(l.sector,''),'Uncategorized') as category,
         l.signed_terms_path, l.claimed_by, l.accepted_terms_at
  from public.supplier_dues d
  join public.leads l on l.id = d.supplier_id
  where d.status not in ('paid','waived','cancelled','legal')
    and d.legal_escalated_at is null
    and coalesce(d.amount_due,0) > 0
    and current_date >= add_working_days(d.due_date::date, p_days);
$function$


CREATE OR REPLACE FUNCTION public.fn_ea_agenda(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'as_of', now(),
    'today', jsonb_build_object(
      'events', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'starts_at',starts_at,'location',location,'attendees',attendees) order by starts_at)
          from ea_events where status='scheduled' and coalesce(starts_at, now())::date = current_date),'[]'::jsonb),
      'reminders_due', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'remind_at',remind_at) order by remind_at)
          from ea_reminders where not done and remind_at <= now()+interval '1 day'),'[]'::jsonb)
    ),
    'upcoming_events', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'starts_at',starts_at,'location',location) order by starts_at)
        from ea_events where status='scheduled' and starts_at > current_date and starts_at <= (current_date + (p_days||' days')::interval)),'[]'::jsonb),
    'open_tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'priority',priority,'due',due_date,'source',source) order by (due_date is null), due_date)
        from (select * from crm_tasks where coalesce(status,'')<>'done' order by (due_date is null), due_date limit 15) t),'[]'::jsonb),
    'overdue_tasks', (select count(*) from crm_tasks where coalesce(status,'')<>'done' and due_date < now()),
    'approvals_to_clear', jsonb_build_object(
      'total',(select count(*) from agent_actions where status in ('pending','needs_review')),
      'high_risk',(select count(*) from agent_actions where status in ('pending','needs_review') and coalesce(risk,'') in ('high','critical')),
      'top', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'title',title,'risk',risk) order by (coalesce(risk,'')='high') desc, created_at desc)
          from (select * from agent_actions where status in ('pending','needs_review') order by (coalesce(risk,'')='high') desc, created_at desc limit 8) a),'[]'::jsonb)
    ),
    'recent_meetings', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'meeting_at',meeting_at,'summary',left(summary,240)) order by meeting_at desc)
        from (select * from ea_meetings order by meeting_at desc limit 5) m),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ea_assistant()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_agenda jsonb; n_rem int:=0; n_nudge int:=0; rec record;
begin
  v_agenda := fn_ea_agenda(7);
  insert into ea_snapshots(snapshot_date, agenda) values (current_date, v_agenda)
    on conflict (snapshot_date) do update set agenda=excluded.agenda, created_at=now();

  -- mark due reminders as notified (they surface in the agenda; internal only)
  update ea_reminders set notified_at=now() where not done and remind_at <= now() and notified_at is null;
  select count(*) into n_rem from ea_reminders where not done and remind_at <= now();

  -- nudge: overdue tasks/follow-ups -> founder-visible EA reminder action (de-duped daily)
  if (select count(*) from crm_tasks where coalesce(status,'')<>'done' and due_date < now()) > 0
     and not exists (select 1 from agent_actions where agent='executive_assistant' and detail->>'signal'='overdue_followups' and status in ('pending','needs_review') and created_at::date=current_date) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values('executive_assistant','handoff','pending','low','Overdue follow-ups need your attention',
      (select count(*)::text from crm_tasks where coalesce(status,'')<>'done' and due_date < now())||' task(s)/follow-up(s) are past due. Review your open items in the agenda.',
      jsonb_build_object('signal','overdue_followups'),'ea','overdue');
    n_nudge:=1;
  end if;

  return jsonb_build_object('ran_at',now(),'reminders_due',n_rem,'nudged',n_nudge,'agenda',v_agenda);
end $function$


CREATE OR REPLACE FUNCTION public.fn_edit_inquiry(p_inquiry uuid, p_customer uuid, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v inquiries%rowtype; v_paid boolean; v_deadline timestamptz;
begin
  select * into v from inquiries where id=p_inquiry;
  if not found then return jsonb_build_object('error','inquiry_not_found'); end if;
  if p_customer is not null and v.customer_id is distinct from p_customer then
    return jsonb_build_object('error','not_your_inquiry'); end if;
  select exists(select 1 from transactions where inquiry_id=p_inquiry) into v_paid;
  if v_paid or v.status in ('revealed','completed','cancelled','closed') or v.pipeline_stage in ('revealed','won','cancelled') then
    return jsonb_build_object('error','not_editable','status',v.status,
      'message','This request can no longer be edited.'); end if;
  v_deadline := v.created_at + interval '1 hour';
  if now() > v_deadline then
    return jsonb_build_object('error','edit_window_closed','editable_until',v_deadline,
      'message','Inquiries can be edited within 1 hour of submitting. Please create a new request for changes after that.'); end if;

  update inquiries set
    summary   = coalesce(p_patch->>'summary', summary),
    raw_input = coalesce(p_patch->>'raw_input', raw_input),
    budget    = coalesce(p_patch->>'budget', budget),
    emirate   = coalesce(p_patch->>'emirate', emirate),
    scope_type= coalesce(p_patch->>'scope_type', scope_type),
    spec      = case when p_patch ? 'spec' then p_patch->'spec' else spec end,
    boq       = case when p_patch ? 'boq' then p_patch->'boq' else boq end,
    trades    = case when p_patch ? 'trades' then array(select jsonb_array_elements_text(p_patch->'trades')) else trades end,
    keywords  = case when p_patch ? 'keywords' then array(select jsonb_array_elements_text(p_patch->'keywords')) else keywords end
    where id=p_inquiry;
  return jsonb_build_object('ok',true,'edited',true,'editable_until',v_deadline);
end $function$


CREATE OR REPLACE FUNCTION public.fn_enable_dropbox_sync()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare jid int; begin
  select jobid into jid from cron.job where jobname='dropbox_sync_daily';
  if jid is not null then perform cron.alter_job(jid, active:=true); return 'enabled'; end if;
  return 'not_found';
end $function$


CREATE OR REPLACE FUNCTION public.fn_enforce_rls_on_new_tables()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare r record;
begin
  for r in
    select object_identity, schema_name, object_type
    from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE','CREATE TABLE AS','SELECT INTO')
      and object_type = 'table'
      and schema_name = 'public'
  loop
    execute format('alter table %s enable row level security', r.object_identity);
  end loop;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_enqueue_doc_backups()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare n integer := 0; m integer;
begin
  with s as (
    select l.*,
      '/QuotesDone Backup/Suppliers/'
        || fn_dbx_safe(coalesce(nullif(btrim(split_part(coalesce(l.categories,''),',',1)),''), nullif(l.sector,''), 'Uncategorized'))
        || '/' || fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
    from public.leads l
    where l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false)
  ),
  sd as (
    select s.id, s.base, v.doc_type, v.bucket, v.path
    from s cross join lateral (values
      ('Trade licence','supplier-docs', s.license_doc_path),
      ('Bank IBAN','supplier-docs', s.iban_doc_path),
      ('Establishment card','supplier-docs', s.egr_doc_path),
      ('Insurance','supplier-docs', s.insurance_doc_path),
      ('VAT certificate','supplier-docs', s.vat_doc_path),
      ('ISO certificate','supplier-docs', s.iso_doc_path),
      ('Manufacturer authorization','supplier-docs', s.manufacturer_auth_doc_path),
      ('Company profile','supplier-docs', s.company_profile_doc_path),
      ('Signed Terms & Conditions','signed-terms', s.signed_terms_path)
    ) v(doc_type,bucket,path)
    where v.path is not null and length(v.path)>0
  )
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'supplier', sd.id::text, sd.doc_type, sd.bucket, sd.path,
         regexp_replace(sd.path,'^.*/',''),
         sd.base || sd.doc_type || ' - ' || regexp_replace(sd.path,'^.*/',''),
         'storage', 'S:'||sd.id||':'||sd.doc_type||':'||sd.path
  from sd on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'supplier', s.id::text, 'Catalogue', 'supplier-docs', cat,
         regexp_replace(cat,'^.*/',''), s.base || 'Catalogue - ' || regexp_replace(cat,'^.*/',''),
         'storage', 'S:'||s.id||':cat:'||cat
  from ( select l.id,
      '/QuotesDone Backup/Suppliers/'
        || fn_dbx_safe(coalesce(nullif(btrim(split_part(coalesce(l.categories,''),',',1)),''), nullif(l.sector,''), 'Uncategorized'))
        || '/' || fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base, l.catalog_doc_paths
    from public.leads l
    where (l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false)) and l.catalog_doc_paths is not null ) s,
    unnest(s.catalog_doc_paths) cat
  where cat is not null and length(cat)>0 on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'supplier', s.id::text, 'Company Details','generated','supplier_details', s.id::text,
         s.base || 'Company Details.pdf', 'S:'||s.id||':details'
  from ( select l.id,
      '/QuotesDone Backup/Suppliers/'
        || fn_dbx_safe(coalesce(nullif(btrim(split_part(coalesce(l.categories,''),',',1)),''), nullif(l.sector,''), 'Uncategorized'))
        || '/' || fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
    from public.leads l
    where l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false) ) s
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'customer', c.id::text, 'Signed Terms & Conditions','signed-terms', c.signed_terms_path,
         regexp_replace(c.signed_terms_path,'^.*/',''),
         '/QuotesDone Backup/Customers/'||fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Signed Terms & Conditions - '||regexp_replace(c.signed_terms_path,'^.*/',''),
         'storage', 'C:'||c.id||':terms:'||c.signed_terms_path
  from public.customers c where c.signed_terms_path is not null and length(c.signed_terms_path)>0
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'customer', c.id::text, 'Customer Details','generated','customer_details', c.id::text,
         '/QuotesDone Backup/Customers/'||fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Customer Details.pdf',
         'C:'||c.id||':details'
  from public.customers c on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'inquiry', i.id::text, 'RFQ drawing','drawing-files', i.drawing_file_path,
         coalesce(i.drawing_file_name, regexp_replace(i.drawing_file_path,'^.*/','')),
         '/QuotesDone Backup/Customers/'||fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Drawing - '||coalesce(i.drawing_file_name, regexp_replace(i.drawing_file_path,'^.*/','')),
         'storage', 'I:'||i.id||':drawing:'||i.drawing_file_path
  from public.inquiries i join public.customers c on c.id=i.customer_id
  where i.drawing_file_path is not null and length(i.drawing_file_path)>0
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'inquiry', i.id::text, 'Inquiry Summary','generated','inquiry_summary', i.id::text,
         '/QuotesDone Backup/Customers/'||fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Inquiry Summary.pdf', 'I:'||i.id||':summary'
  from public.inquiries i join public.customers c on c.id=i.customer_id
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  -- Quote comparison reports: one PDF per distinct quote-set (>=2 live quotes). Anonymized A/B/C.
  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'inquiry', i.id::text, 'Quote Comparison','generated','comparison', i.id::text,
         '/QuotesDone Backup/Customers/'||fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Quote Comparison Report '||to_char(now(),'YYYY-MM-DD')||' '||left(sig.sig,8)||'.pdf',
         'CMP:'||i.id||':'||sig.sig
  from public.inquiries i
  join public.customers c on c.id=i.customer_id
  join lateral ( select md5(coalesce(string_agg(q.quote_amount::text||':'||coalesce(q.status,''),'|' order by q.quote_amount),'')) as sig,
                        count(*) as nq
                 from public.quotes q where q.inquiry_id=i.id and q.status<>'draft' ) sig on true
  where sig.nq >= 2
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_entity_files(p_entity text, p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare out jsonb := '[]'::jsonb; l public.leads%rowtype;
begin
  if p_entity = 'supplier' then
    select * into l from public.leads where id = p_id::bigint;
    if l.id is not null then
      if l.license_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Trade licence','name',coalesce(l.license_doc_name,'trade licence'),'bucket','supplier-docs','path',l.license_doc_path); end if;
      if l.iban_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Bank / IBAN','name',coalesce(l.iban_doc_name,'iban letter'),'bucket','supplier-docs','path',l.iban_doc_path); end if;
      if l.egr_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Establishment card','name',coalesce(l.egr_doc_name,'establishment card'),'bucket','supplier-docs','path',l.egr_doc_path); end if;
      if l.insurance_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Insurance','name','insurance','bucket','supplier-docs','path',l.insurance_doc_path); end if;
      if l.vat_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','VAT certificate','name','vat certificate','bucket','supplier-docs','path',l.vat_doc_path); end if;
      if l.company_profile_doc_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Company profile','name','company profile','bucket','supplier-docs','path',l.company_profile_doc_path); end if;
      if l.signed_terms_path is not null then out := out || jsonb_build_object('group','Compliance documents','type','Signed terms','name','signed terms','bucket','signed-terms','path',l.signed_terms_path); end if;
      if l.catalog_doc_paths is not null then
        out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Catalogues','type','Catalogue','name','catalogue','bucket','supplier-docs','path',x)) from unnest(l.catalog_doc_paths) x),'[]'::jsonb);
      end if;
    end if;
    out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Quotations submitted','type','Quote #'||q.id,'name',coalesce(q.original_file_name,'quote file'),'bucket','quote-files','path',q.original_file_path) order by q.created_at desc)
                            from public.quotes q where q.supplier_id = p_id::bigint and q.original_file_path is not null),'[]'::jsonb);

  elsif p_entity = 'customer' then
    out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Drawings & RFQ files','type','RFQ drawing','name',coalesce(i.drawing_file_name,'drawing'),'bucket','drawing-files','path',i.drawing_file_path) order by i.created_at desc)
                            from public.inquiries i where i.customer_id = p_id::uuid and i.drawing_file_path is not null),'[]'::jsonb);
    out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Quotations received','type','Quote #'||q.id,'name',coalesce(q.original_file_name,'quote file'),'bucket','quote-files','path',q.original_file_path) order by q.created_at desc)
                            from public.quotes q join public.inquiries i on i.id = q.inquiry_id where i.customer_id = p_id::uuid and q.original_file_path is not null),'[]'::jsonb);

  elsif p_entity in ('rfq','inquiry') then
    out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Drawing','type','RFQ drawing','name',coalesce(i.drawing_file_name,'drawing'),'bucket','drawing-files','path',i.drawing_file_path))
                            from public.inquiries i where i.id = p_id::uuid and i.drawing_file_path is not null),'[]'::jsonb);
    out := out || coalesce((select jsonb_agg(jsonb_build_object('group','Quotations','type','Quote #'||q.id,'name',coalesce(q.original_file_name,'quote file'),'bucket','quote-files','path',q.original_file_path) order by q.created_at desc)
                            from public.quotes q where q.inquiry_id = p_id::uuid and q.original_file_path is not null),'[]'::jsonb);
  end if;
  return out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_eval_run()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k jsonb;
begin
  k := public.fn_eval_snapshot(30);
  insert into public.agent_evals(window_days,kpis) values (30,k);
end $function$


CREATE OR REPLACE FUNCTION public.fn_eval_snapshot(p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  intake_total int; intake_complete int; q_total int; q_scored int; q_pass numeric; q_avg numeric;
  inq_matched int; inq_all int; inq_done int; inq_open int; esc_pending int; esc_total int; lat_avg numeric;
  dec_total int; dec_grounded int; k jsonb;
begin
  select count(*) filter (where created_at > now()-(p_days||' days')::interval),
         count(*) filter (where created_at > now()-(p_days||' days')::interval and coalesce(rfq_ready,false))
    into intake_total, intake_complete from inquiries;
  select count(*) filter (where created_at > now()-(p_days||' days')::interval),
         count(*) filter (where created_at > now()-(p_days||' days')::interval and quality is not null),
         avg(nullif(quality->>'score','')::numeric) filter (where created_at > now()-(p_days||' days')::interval),
         count(*) filter (where created_at > now()-(p_days||' days')::interval and nullif(quality->>'score','')::numeric >= 60)
    into q_total, q_scored, q_avg, q_pass from quotes;
  select count(*) filter (where i.created_at > now()-(p_days||' days')::interval),
         count(*) filter (where i.created_at > now()-(p_days||' days')::interval and exists(select 1 from inquiry_matches m where m.inquiry_id=i.id))
    into inq_all, inq_matched from inquiries i;
  select count(*) filter (where created_at > now()-(p_days||' days')::interval and (status in ('completed','accepted','closed') or completed_at is not null)),
         count(*) filter (where created_at > now()-(p_days||' days')::interval) into inq_done, inq_open from inquiries;
  begin select count(*) filter (where created_at > now()-(p_days||' days')::interval and status='pending'), count(*) filter (where created_at > now()-(p_days||' days')::interval) into esc_pending, esc_total from agent_actions; exception when others then esc_pending:=0; esc_total:=0; end;
  begin select round(avg(extract(epoch from (finished_at-started_at)))::numeric,1) into lat_avg from agent_runs where started_at > now()-(p_days||' days')::interval and finished_at is not null; exception when others then lat_avg:=null; end;
  begin select count(*), count(*) filter (where jsonb_array_length(coalesce(sources,'[]'))>0) into dec_total, dec_grounded from decision_log where created_at > now()-(p_days||' days')::interval; exception when others then dec_total:=0; dec_grounded:=0; end;

  k := jsonb_build_object(
    'window_days', p_days,
    'rfq_completeness_pct', case when intake_total=0 then null else round(intake_complete::numeric/intake_total*100,1) end,
    'quote_gate_pass_pct',  case when q_scored=0 then null else round(q_pass::numeric/q_scored*100,1) end,
    'quote_quality_avg',    round(coalesce(q_avg,0),1),
    'match_coverage_pct',   case when inq_all=0 then null else round(inq_matched::numeric/inq_all*100,1) end,
    'resolution_pct',       case when inq_open=0 then null else round(inq_done::numeric/inq_open*100,1) end,
    'escalation_rate_pct',  case when esc_total=0 then null else round(esc_pending::numeric/esc_total*100,1) end,
    'agent_latency_sec_avg',lat_avg,
    'decision_grounding_pct', case when dec_total=0 then null else round(dec_grounded::numeric/dec_total*100,1) end,
    'clarification_efficiency', null, 'hallucination_rate_pct', null, 'customer_satisfaction', null,
    'samples', jsonb_build_object('inquiries',intake_total,'quotes',q_total,'agent_actions',esc_total,'decisions',dec_total));
  return k;
end $function$


CREATE OR REPLACE FUNCTION public.fn_exception_alerts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  rev_today numeric; rev_prev numeric;
  gw_bad int; q24 int; qpass24 int; last_backup timestamptz;
  fired text[] := '{}';
  procedure_note text;
begin
  -- helper: only fire if same event not raised in last 12h
  -- 1) revenue drop > 20% day-over-day (needs a meaningful prior day)
  select coalesce(sum(reveal_fee),0) into rev_today from transactions
    where revealed_at::date = current_date and coalesce(refund_status,'')<>'approved';
  select coalesce(sum(reveal_fee),0) into rev_prev from transactions
    where revealed_at::date = current_date-1 and coalesce(refund_status,'')<>'approved';
  if rev_prev >= 100 and rev_today < rev_prev*0.8 then
     if not exists(select 1 from founder_alerts where event='revenue_drop' and created_at>now()-interval '12 hours') then
        insert into founder_alerts(level,event,detail,channel) values
          ('critical','revenue_drop','Revenue AED '||round(rev_today)||' today vs AED '||round(rev_prev)||' yesterday (>20% drop).','email');
        fired := array_append(fired,'revenue_drop'); end if;
  end if;

  -- 2) payment gateway offline (latest stripe health check failing in last hour)
  select count(*) into gw_bad from health_checks
    where created_at>now()-interval '1 hour' and not ok
      and (lower(coalesce(check_kind,'')) like '%stripe%' or lower(coalesce(target,'')) like '%stripe%' or lower(coalesce(check_kind,'')) like '%pay%');
  if gw_bad > 0 then
     if not exists(select 1 from founder_alerts where event='gateway_offline' and created_at>now()-interval '3 hours') then
        insert into founder_alerts(level,event,detail,channel) values
          ('critical','gateway_offline','Payment gateway health check failing in the last hour.','email');
        fired := array_append(fired,'gateway_offline'); end if;
  end if;

  -- 3) AI confidence / quote-quality below threshold (proxy: gate pass-rate collapse with volume)
  select count(*) filter (where quality is not null),
         count(*) filter (where nullif(quality->>'score','')::numeric >= 60)
    into q24, qpass24 from quotes where created_at>now()-interval '24 hours';
  if q24 >= 5 and qpass24::numeric/nullif(q24,0) < 0.5 then
     if not exists(select 1 from founder_alerts where event='ai_confidence_low' and created_at>now()-interval '12 hours') then
        insert into founder_alerts(level,event,detail,channel) values
          ('warning','ai_confidence_low','Quote-quality gate pass rate '||round(qpass24::numeric/q24*100)||'% over last 24h ('||q24||' quotes) — below 50% threshold.','email');
        fired := array_append(fired,'ai_confidence_low'); end if;
  end if;

  -- 4) backup stale (no backup manifest in > 8 days)
  select max(updated_at) into last_backup from storage.objects where bucket_id='backups' and name like '%/_manifest.json';
  if last_backup is null or last_backup < now()-interval '8 days' then
     if not exists(select 1 from founder_alerts where event='backup_stale' and created_at>now()-interval '24 hours') then
        insert into founder_alerts(level,event,detail,channel) values
          ('critical','backup_stale','No fresh backup manifest in over 8 days (last: '||coalesce(last_backup::text,'never')||').','email');
        fired := array_append(fired,'backup_stale'); end if;
  end if;

  -- surface criticals as founder notifications too
  insert into notifications(type,to_role,channel,subject,body)
  select 'exception_alert','admin','email','QuotesDone ALERT: '||event, detail
  from founder_alerts fa
  where fa.created_at>now()-interval '2 minutes' and fa.level='critical'
    and not exists(select 1 from notifications n where n.type='exception_alert' and n.subject='QuotesDone ALERT: '||fa.event and n.created_at>now()-interval '3 hours');

  return jsonb_build_object('fired', to_jsonb(fired), 'rev_today',rev_today,'rev_prev',rev_prev,'checked_at',now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_experience_promote()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_promoted int:=0; v_rejected int:=0; v_agent text;
begin
  for r in select m.* from org_memory m
           where m.active and m.kind='lesson'
             and m.created_at < now() - interval '7 days'
             and not exists (select 1 from agent_knowledge k
                             where k.layer='experience' and k.topic like '%[org#'||m.id||']')
  loop
    if exists (select 1 from policy_rules p where p.active and r.content ~* p.forbid_regex) then
      v_rejected := v_rejected + 1;
      insert into founder_alerts(level,event,detail,channel)
        values ('warn','experience_promotion_blocked',
                'org_memory lesson #'||r.id||' contradicts policy_rules and was NOT promoted: '||left(r.content,300),'system');
    else
      select coalesce(d.brain_agent,'_global') into v_agent from org_departments d where d.dept_key=r.scope;
      insert into agent_knowledge(agent_key, topic, content, priority, layer)
        values (coalesce(v_agent,'_global'),
                'Experience: '||left(regexp_replace(r.content,'^\[[a-z]+\]\s*',''),60)||' [org#'||r.id||']',
                r.content, 5, 'experience');
      v_promoted := v_promoted + 1;
    end if;
  end loop;
  return jsonb_build_object('promoted', v_promoted, 'lint_rejected', v_rejected);
end $function$


CREATE OR REPLACE FUNCTION public.fn_experiment_assign(p_key text, p_subject text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare e record; existing text; roll int; acc int:=0; v jsonb; chosen text;
begin
  select * into e from experiments where key=p_key and status='running';
  if e is null then return null; end if;
  select variant into existing from experiment_assignments where experiment=p_key and subject=p_subject;
  if existing is not null then return existing; end if;
  roll := (abs(('x'||substr(md5(p_key||':'||p_subject),1,8))::bit(32)::int) % 100);
  for v in select * from jsonb_array_elements(e.variants) loop
    acc := acc + coalesce((v->>'weight')::int,0);
    if roll < acc then chosen := v->>'name'; exit; end if;
  end loop;
  chosen := coalesce(chosen, (e.variants->0->>'name'));
  insert into experiment_assignments(experiment,subject,variant) values(p_key,p_subject,chosen) on conflict do nothing;
  return chosen;
end $function$


CREATE OR REPLACE FUNCTION public.fn_experiment_record(p_key text, p_subject text, p_event text, p_value numeric DEFAULT 1)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v text;
begin
  select variant into v from experiment_assignments where experiment=p_key and subject=p_subject;
  insert into experiment_events(experiment,subject,variant,event,value) values(p_key,p_subject,v,p_event,p_value);
end $function$


CREATE OR REPLACE FUNCTION public.fn_experiment_results(p_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_object_agg(variant, stats) from (
    select a.variant,
      jsonb_build_object(
        'subjects', count(distinct a.subject),
        'conversions', count(distinct e.subject) filter (where e.event='convert'),
        'conv_rate_pct', round(100.0*count(distinct e.subject) filter (where e.event='convert')/nullif(count(distinct a.subject),0),1)
      ) stats
    from experiment_assignments a left join experiment_events e on e.experiment=a.experiment and e.subject=a.subject
    where a.experiment=p_key group by a.variant) z;
$function$


CREATE OR REPLACE FUNCTION public.fn_expiring_docs(p_days integer DEFAULT 60)
 RETURNS TABLE(id bigint, company_name text, sector text, doc text, expiry date, days_left integer, status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select l.id, l.company_name, l.sector, d.label, d.exp, (d.exp-current_date),
    case when d.exp<current_date then 'expired' when d.exp<=current_date+30 then 'expiring' else 'soon' end
  from leads l, lateral (values ('Trade license',l.license_expiry),('ISO certification',l.iso_expiry),
     ('Insurance',l.insurance_expiry),('Manufacturer authorization',l.manufacturer_auth_expiry)) d(label,exp)
  where d.exp is not null and d.exp <= current_date + p_days
    and coalesce(l.approval_status,'')='approved'
  order by d.exp asc;
$function$


CREATE OR REPLACE FUNCTION public.fn_fa_acquire(p_name text, p_category text, p_acquire_date date, p_cost numeric, p_salvage numeric, p_life_months integer, p_in_service date DEFAULT NULL::date, p_fund_account text DEFAULT '1000'::text, p_post_gl boolean DEFAULT true, p_by text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare a bigint; j bigint;
begin
  insert into public.fa_assets(name,category,acquire_date,in_service_date,cost,salvage_value,
        useful_life_months,created_by)
    values (p_name,p_category,coalesce(p_acquire_date,current_date),
            coalesce(p_in_service,p_acquire_date,current_date),
            round(p_cost,2),round(coalesce(p_salvage,0),2),p_life_months,p_by)
    returning id into a;
  update public.fa_assets set asset_no='FA-'||lpad(a::text,6,'0') where id=a;
  if p_post_gl then                                  -- Dr Fixed Asset  Cr funding account
    j := public.fn_gl_entry(coalesce(p_acquire_date,current_date),
           'Asset acquisition '||p_name, 'fa_acquire', a::text,
           jsonb_build_array(jsonb_build_object('account','1600','debit',round(p_cost,2)),
                             jsonb_build_object('account',p_fund_account,'credit',round(p_cost,2))), p_by);
  end if;
  return a;
end $function$


CREATE OR REPLACE FUNCTION public.fn_fa_depreciate(p_asset bigint, p_period date)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare a record; depreciable numeric(18,2); remaining numeric(18,2);
        monthly numeric(18,2); amt numeric(18,2); j bigint;
begin
  select * into a from public.fa_assets where id=p_asset;
  if a.id is null then raise exception 'asset % not found', p_asset; end if;
  if a.status <> 'active' then return null; end if;
  if p_period < a.in_service_date then return null; end if;               -- not yet in service
  if exists (select 1 from public.fa_depreciation where asset_id=p_asset and period=p_period) then
    return null;                                                          -- already booked
  end if;
  depreciable := a.cost - a.salvage_value;
  remaining := depreciable - a.accumulated_depreciation;
  if remaining <= 0 then
    update public.fa_assets set status='fully_depreciated' where id=p_asset; return null;
  end if;
  monthly := round(depreciable / a.useful_life_months, 2);
  amt := least(monthly, remaining);                                       -- final period soaks rounding
  j := public.fn_gl_entry(p_period, 'Depreciation '||a.asset_no||' '||to_char(p_period,'YYYY-MM'),
         'fa_deprec', p_asset::text,
         jsonb_build_array(jsonb_build_object('account',a.expense_account,'debit',amt),
                           jsonb_build_object('account',a.accum_account,'credit',amt)), null);
  insert into public.fa_depreciation(asset_id,period,amount,gl_journal_id) values (p_asset,p_period,amt,j);
  update public.fa_assets
     set accumulated_depreciation = accumulated_depreciation + amt,
         status = case when accumulated_depreciation + amt >= depreciable then 'fully_depreciated' else 'active' end
   where id=p_asset;
  return j;
end $function$


CREATE OR REPLACE FUNCTION public.fn_fa_dispose(p_asset bigint, p_date date, p_proceeds numeric DEFAULT 0, p_proceeds_account text DEFAULT '1000'::text, p_by text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare a record; nbv numeric(18,2); proceeds numeric(18,2); gainloss numeric(18,2);
        gl_lines jsonb; j bigint;
begin
  select * into a from public.fa_assets where id=p_asset;
  if a.id is null then raise exception 'asset % not found', p_asset; end if;
  if a.status='disposed' then raise exception 'asset % already disposed', p_asset; end if;
  proceeds := round(coalesce(p_proceeds,0),2);
  nbv := a.cost - a.accumulated_depreciation;
  gainloss := proceeds - nbv;                          -- +gain / -loss
  gl_lines := jsonb_build_array(
      jsonb_build_object('account',a.accum_account,'debit',a.accumulated_depreciation),  -- clear accum
      jsonb_build_object('account',a.asset_account,'credit',a.cost));                     -- remove cost
  if proceeds > 0 then
    gl_lines := gl_lines || jsonb_build_object('account',p_proceeds_account,'debit',proceeds);
  end if;
  if gainloss > 0 then
    gl_lines := gl_lines || jsonb_build_object('account','4300','credit',gainloss);       -- gain
  elsif gainloss < 0 then
    gl_lines := gl_lines || jsonb_build_object('account','6500','debit',-gainloss);       -- loss
  end if;
  j := public.fn_gl_entry(coalesce(p_date,current_date), 'Disposal '||a.asset_no,
         'fa_dispose', p_asset::text, gl_lines, p_by);
  update public.fa_assets set status='disposed', disposed_date=coalesce(p_date,current_date) where id=p_asset;
  return j;
end $function$


CREATE OR REPLACE FUNCTION public.fn_fa_run_depreciation(p_period date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare per date := coalesce(p_period, (date_trunc('month',current_date)+interval '1 month -1 day')::date);
        r record; n int := 0; j bigint;
begin
  for r in select id from public.fa_assets where status='active' and in_service_date <= per loop
    j := public.fn_fa_depreciate(r.id, per);
    if j is not null then n := n + 1; end if;
  end loop;
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_finance_ai()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k record; fc jsonb; v_health numeric; n_esc int;
  s_run numeric; s_prof numeric; s_coll numeric; s_bud numeric;
begin
  select * into k from finance_kpis;
  fc := fn_finance_forecast();

  s_run := case when k.runway_months is null then (case when k.cash>0 then 80 else 10 end)
                when k.runway_months>=6 then 100 when k.runway_months>=3 then 70 when k.runway_months>=1 then 40 else 10 end;
  s_prof := case when k.net_income>0 then 100 when k.margin_pct is null then 50 else greatest(10, least(100, 60 + k.margin_pct/5)) end;
  s_coll := coalesce(k.collection_rate, 70);
  s_bud := greatest(0, 100 - coalesce(k.budget_overruns,0)*20);
  v_health := round(s_run*0.35 + s_prof*0.25 + s_coll*0.20 + s_bud*0.20, 1);

  insert into finance_kpi_snapshots(snapshot_date, kpis, forecast)
  values (current_date, to_jsonb(k) || jsonb_build_object('health',v_health), fc)
  on conflict (snapshot_date) do update set kpis=excluded.kpis, forecast=excluded.forecast, created_at=now();

  -- ESCALATIONS to founder (never auto-resolved; agent never moves money)
  if k.cash <= 0 then
    perform fin_alert('cash_negative','high','Book cash is negative',
      'Book cash is '||to_char(k.cash,'FM999999990.00')||' AED and owner capital is 0. Record a capital injection or fund operations to restore a positive position.');
  elsif k.runway_months is not null and k.runway_months < 3 then
    perform fin_alert('low_runway','high','Low cash runway',
      'Runway is ~'||k.runway_months||' months at the current burn. Increase revenue, cut spend, or add capital.');
  end if;
  if k.ar_overdue > 0 then
    perform fin_alert('ar_overdue', case when k.ar_overdue>=500 then 'high' else 'medium' end, 'Overdue collections',
      'AED '||to_char(k.ar_overdue,'FM999999990.00')||' in supplier commission is overdue. Reminders are automated; review whether to escalate or apply fines.');
  end if;
  if k.ap_overdue > 0 then
    perform fin_alert('ap_overdue','high','Overdue bills to pay',
      'AED '||to_char(k.ap_overdue,'FM999999990.00')||' in supplier bills is overdue. Review and pay — money movement is yours to action.');
  end if;
  if coalesce(k.budget_overruns,0) > 0 then
    perform fin_alert('budget_overrun','medium','Budget overrun',
      k.budget_overruns||' expense budget line(s) are over 110% of plan. Review spend or re-budget.');
  end if;

  select count(*) into n_esc from agent_actions where agent='finance_ai' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'health',v_health,'kpis',to_jsonb(k),'forecast',fc,'open_alerts',n_esc);
end $function$


CREATE OR REPLACE FUNCTION public.fn_finance_forecast()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with base as (
    select (select coalesce(sum(balance),0) from gl_account_balances where code in ('1000','1050')) as cash,
           (select coalesce(sum(case when ga.type='revenue' then l.credit-l.debit else 0 end),0)
              from gl_journal_lines l join gl_journal j on j.id=l.journal_id and j.status='posted'
              join gl_accounts ga on ga.code=l.account_code where j.entry_date>=current_date-30) as rev30,
           (select coalesce(sum(case when ga.type='expense' then l.debit-l.credit else 0 end),0)
              from gl_journal_lines l join gl_journal j on j.id=l.journal_id and j.status='posted'
              join gl_accounts ga on ga.code=l.account_code where j.entry_date>=current_date-30) as exp30
  ),
  hz as (
    select h,
      (select coalesce(sum(amount_due),0) from supplier_dues where status not in ('paid','waived') and coalesce(due_date_30,reveal_date+30) <= current_date + h) as ar_in,
      (select coalesce(sum(balance_due),0) from ap_open_bills where coalesce(due_date, bill_date) <= current_date + h) as ap_out
    from (values (30),(60),(90)) v(h)
  )
  select jsonb_build_object(
    'as_of', now(),
    'cash_now', (select cash from base),
    'assumptions', jsonb_build_object('revenue_run_rate_30d',(select rev30 from base),'expense_run_rate_30d',(select exp30 from base)),
    'horizons', (select jsonb_agg(jsonb_build_object(
        'days', h,
        'expected_inflows', round(ar_in + (select rev30 from base)*(h/30.0), 2),
        'expected_outflows', round(ap_out + (select exp30 from base)*(h/30.0), 2),
        'projected_cash', round((select cash from base) + ar_in + (select rev30 from base)*(h/30.0) - ap_out - (select exp30 from base)*(h/30.0), 2),
        'revenue_forecast', round((select rev30 from base)*(h/30.0), 2)
      ) order by h) from hz)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_flag(p_key text, p_ctx jsonb DEFAULT '{}'::jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare f record; aud jsonb; h int; subj text;
begin
  select * into f from feature_flags where key=p_key;
  if f is null or not f.enabled then return false; end if;
  aud := coalesce(f.audience,'{}');
  -- audience gates
  if aud ? 'country' and not (upper(coalesce(p_ctx->>'country','')) = any(select upper(jsonb_array_elements_text(aud->'country')))) then return false; end if;
  if aud ? 'category' and not (lower(coalesce(p_ctx->>'category','')) = any(select lower(jsonb_array_elements_text(aud->'category')))) then return false; end if;
  if aud ? 'role' and not (lower(coalesce(p_ctx->>'role','')) = any(select lower(jsonb_array_elements_text(aud->'role')))) then return false; end if;
  if coalesce((aud->>'enterprise')::boolean,false) and not coalesce((p_ctx->>'enterprise')::boolean,false) then return false; end if;
  -- percentage rollout, deterministic by subject
  subj := coalesce(p_ctx->>'subject', p_ctx->>'email', p_ctx->>'id', 'anon');
  h := (abs(('x'||substr(md5(p_key||':'||subj),1,8))::bit(32)::int) % 100);
  return h < coalesce(f.rollout_pct,100);
end $function$


CREATE OR REPLACE FUNCTION public.fn_founder_brief()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_owner text; v_run bigint;
  v_reg int; v_cust int; v_inq7 int; v_q7 int; v_deals int; v_rev numeric;
  v_pend int; v_kyc int; v_refunds int; v_reviews int;
  v_hot int; v_gap int; v_newsup int; v_newcust int;
  v_bd_q int; v_bd_sent int; v_chat_open int; v_viol int;
  v_officer text; v_health jsonb;
  v_topcats text; v_qpr numeric; v_conv numeric;
  v_expired int; v_crit int; v_decisions text; v_dn int := 0;
  v_body text; v_subj text;
  v_auto_cleared int; v_auto_appr int; v_handled text;   -- Phase B additions
  v_obj_open int := 0; v_obj_await int := 0; v_obj_done24 int := 0; v_task_done24 int := 0; v_obj_line text;  -- Org-foundation additions
begin
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';
  if v_owner is null then v_owner := 'management@quotesdone.com'; end if;
  insert into agent_runs(agent, started_at) values ('brief', now()) returning id into v_run;

  begin select coalesce(registered_supplier_count(),0) into v_reg; exception when others then v_reg := 0; end;
  select count(*) into v_cust from customers;
  select count(*) into v_inq7 from inquiries where created_at >= now()-interval '7 days';
  select count(*) into v_q7 from quotes where created_at >= now()-interval '7 days';
  select count(*) into v_deals from transactions;
  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where coalesce(fee_status,'')<>'refunded' and coalesce(refund_status,'')<>'approved';
  select count(*) into v_pend from agent_actions where status in ('pending','held_for_review','proposed','open','needs_review');
  select count(*) into v_kyc from leads where approval_status='pending';
  select count(*) into v_refunds from transactions where refund_status='requested';
  select count(*) into v_reviews from inbound_messages where needs_review=true;
  select count(distinct i.id) into v_hot from inquiries i join quotes q on q.inquiry_id=i.id left join transactions t on t.inquiry_id=i.id where t.id is null and i.status not in ('completed','accepted','closed','cancelled');
  select count(*) into v_gap from inquiries i where i.status not in ('completed','accepted','closed','cancelled') and not exists (select 1 from inquiry_matches m where m.inquiry_id=i.id);
  select count(*) into v_newsup from leads where registration_submitted_at >= now()-interval '7 days';
  select count(*) into v_newcust from customers where created_at >= now()-interval '7 days';
  select count(*) into v_bd_q from outreach where status='queued';
  select count(*) into v_bd_sent from outreach where status='sent';
  select count(*) into v_chat_open from chat_threads where status='open';
  select count(*) into v_viol from chat_violations where created_at >= now()-interval '7 days';

  begin select public.fn_health_index() into v_health; exception when others then v_health := null; end;

  begin
    select string_agg(cat,', ') into v_topcats from (
      select coalesce(nullif(category,''),'(uncategorized)') cat, count(*) n
      from inquiries where created_at>=now()-interval '7 days'
      group by 1 order by n desc limit 3) z;
  exception when others then v_topcats := null; end;

  begin
    select round(avg(qc),1) into v_qpr from (
      select count(*) qc from quotes q join inquiries i on i.id=q.inquiry_id
      where i.created_at>=now()-interval '30 days' group by q.inquiry_id) z;
  exception when others then v_qpr := null; end;
  begin
    select round(100.0*count(distinct t.inquiry_id)/nullif(count(distinct i.id),0),1) into v_conv
    from inquiries i left join transactions t on t.inquiry_id=i.id
    where i.created_at>=now()-interval '30 days';
  exception when others then v_conv := null; end;

  begin select count(*) into v_expired from leads where license_expiry is not null and license_expiry < current_date and coalesce(approval_status,'')='approved'; exception when others then v_expired:=0; end;
  select count(*) into v_crit from founder_alerts where level='critical' and created_at>=now()-interval '24 hours';

  begin
    select string_agg('- ['||label||'] '||act, E'\n')
    into v_officer
    from (
      select case er.officer
               when 'strategy' then 'Strategy' when 'operations' then 'Ops'
               when 'procurement_quality' then 'Quality' when 'data_science' then 'Data'
               when 'product_ux' then 'Product' when 'competitive' then 'Compete' else er.officer end as label,
             left(coalesce(rec->>'action',''),160) as act,
             case lower(coalesce(rec->>'impact','')) when 'high' then 0 when 'medium' then 1 else 2 end as ord
      from (select distinct on (officer) officer, recommendations, created_at from exec_reports order by officer, created_at desc) er,
           lateral jsonb_array_elements(er.recommendations) rec
      where coalesce(rec->>'action','') <> ''
      order by ord, label limit 5
    ) z;
  exception when others then v_officer := null; end;

  -- Phase B: what the Chief of Staff handled autonomously in the last 24h.
  select count(*) into v_auto_cleared from agent_actions
    where decided_by='chief_of_staff (auto)' and decided_at >= now()-interval '24 hours';
  begin
    select count(*) into v_auto_appr from leads
      where approval_decided_by='chief_of_staff (auto)' and approved_at >= now()-interval '24 hours';
  exception when others then v_auto_appr := 0; end;
  begin
    select string_agg('- '||type||': '||n, E'\n' order by n desc)
      into v_handled
    from (select type, count(*) n from notifications
          where status='digest' and created_at >= now()-interval '24 hours'
          group by type) z;
  exception when others then v_handled := null; end;

  -- Org foundation: the founder's objectives and how the organization is executing them.
  begin
    select count(*) into v_obj_open from org_objectives where status in ('open','in_progress','blocked');
    select count(*) into v_obj_done24 from org_objectives where status='done' and closed_at >= now()-interval '24 hours';
    select count(*) into v_task_done24 from org_tasks where status='done' and updated_at >= now()-interval '24 hours';
    select count(*) into v_obj_await from org_tasks t
      where t.status in ('proposed','escalated')
        and exists (select 1 from org_objectives o where o.id=t.objective_id and o.status in ('open','in_progress','blocked'));
    select string_agg(
        '- "'||left(o.objective,80)||'" — '||
        (select count(*) from org_tasks t where t.objective_id=o.id and t.status='done')||'/'||
        (select count(*) from org_tasks t where t.objective_id=o.id)||' tasks done'||
        case when (select count(*) from org_tasks t where t.objective_id=o.id and t.status in ('proposed','escalated'))>0
             then ', '||(select count(*) from org_tasks t where t.objective_id=o.id and t.status in ('proposed','escalated'))||' awaiting you'
             else '' end,
        E'\n' order by o.id desc)
      into v_obj_line from org_objectives o where o.status in ('open','in_progress','blocked');
  exception when others then v_obj_open:=0; v_obj_await:=0; v_obj_done24:=0; v_task_done24:=0; v_obj_line:=null; end;

  v_decisions := '';
  if v_kyc > 0 then v_dn:=v_dn+1; v_decisions := v_decisions||v_dn||'. Approve/deny '||v_kyc||' supplier KYC application(s)'||E'\n'; end if;
  if v_refunds > 0 then v_dn:=v_dn+1; v_decisions := v_decisions||v_dn||'. Resolve '||v_refunds||' refund request(s)'||E'\n'; end if;
  if v_obj_await > 0 then v_dn:=v_dn+1; v_decisions := v_decisions||v_dn||'. '||v_obj_await||' objective step(s) awaiting your approval/input'||E'\n'; end if;
  if v_expired > 0 then v_dn:=v_dn+1; v_decisions := v_decisions||v_dn||'. Review '||v_expired||' supplier(s) with EXPIRED trade licence'||E'\n'; end if;
  if v_crit > 0 then v_dn:=v_dn+1; v_decisions := v_decisions||v_dn||'. Address '||v_crit||' critical alert(s) raised in last 24h'||E'\n'; end if;
  if v_dn = 0 then v_decisions := 'None outstanding.'||E'\n'; end if;

  v_subj := 'QuotesDone daily brief — '||to_char(now() at time zone 'Asia/Dubai','Dy DD Mon');
  v_body :=
    'Good morning. Here is your QuotesDone snapshot.'||E'\n\n'||
    'HANDLED FOR YOU (last 24h): auto-cleared '||v_auto_cleared||' routine item(s)'||
      case when v_auto_appr>0 then ', auto-approved '||v_auto_appr||' licence-clean supplier(s)' else '' end||'.'||
      case when v_handled is not null then E'\n'||v_handled else '' end||E'\n\n'||
    'MARKETPLACE HEALTH: '||coalesce(v_health->>'index','—')||'/100 ('||coalesce(v_health->>'band','no data')||')'||
      case when coalesce(v_health->>'note','')<>'' then '  — '||(v_health->>'note') else '' end||E'\n\n'||
    'OBJECTIVES (what the organization is driving for you)'||E'\n'||
    '- Active objectives: '||v_obj_open||'  ·  tasks completed (24h): '||v_task_done24||'  ·  objectives closed (24h): '||v_obj_done24||E'\n'||
      case when v_obj_line is not null and v_obj_line<>'' then v_obj_line||E'\n' else '' end||E'\n'||
    'NEEDS YOU TODAY'||E'\n'||
    '- Approvals waiting: '||v_pend||' (incl. '||v_kyc||' supplier KYC)'||E'\n'||
    '- Refund requests: '||v_refunds||E'\n'||
    '- Inbound emails to review: '||v_reviews||E'\n'||
    '- Hot leads (quotes in, not revealed): '||v_hot||E'\n'||
    '- Supply gaps (demand, no supplier matched): '||v_gap||E'\n'||
    '- Chat: '||v_chat_open||' open, '||v_viol||' policy flag(s) this week'||E'\n\n'||
    'THIS WEEK'||E'\n'||
    '- New inquiries: '||v_inq7||'  ·  quotes: '||v_q7||E'\n'||
    '- Avg quotes/RFQ (30d): '||coalesce(v_qpr::text,'—')||'  ·  Conversion (30d): '||coalesce(v_conv::text,'—')||'%'||E'\n'||
    '- New customers: '||v_newcust||'  ·  new supplier registrations: '||v_newsup||E'\n'||
    '- Deals (reveals) all-time: '||v_deals||'  ·  revenue recognized: AED '||round(v_rev)||E'\n'||
    '- Top categories (7d): '||coalesce(v_topcats,'—')||E'\n\n'||
    'GROWTH'||E'\n'||
    '- Suppliers registered: '||v_reg||'  ·  BD invites queued: '||v_bd_q||'  ·  sent: '||v_bd_sent||E'\n'||
    case when v_officer is not null and v_officer <> '' then E'\n'||'OFFICER PRIORITIES (from weekly analysis)'||E'\n'||v_officer||E'\n' else '' end ||
    E'\n'||'DECISIONS NEEDED'||E'\n'||v_decisions||
    E'\n'||'Open your dashboard: https://quotesdone.com/os  (Ops for live status; Governance for officer reports).';

  insert into notifications(type,to_email,to_role,channel,subject,body) values ('founder_brief',v_owner,'admin','email',v_subj,v_body);

  update notifications set status='digested' where status='digest' and created_at <= now();

  update agent_runs set finished_at=now(), status='ok', counts=jsonb_build_object('approvals',v_pend,'hot',v_hot,'gaps',v_gap,'bd_queued',v_bd_q,'kyc',v_kyc,'health',(v_health->>'index'),'decisions',v_dn,'auto_cleared_24h',v_auto_cleared,'objectives_open',v_obj_open) where id=v_run;
end;$function$


CREATE OR REPLACE FUNCTION public.fn_fraud_resolve(p_subject_type text, p_subject_id text, p_action text, p_by text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_ok boolean := true; v_msg text := '';
begin
  if p_action = 'ban' then
    begin
      if p_subject_type in ('customer','customers') then
        update customers set banned=true, banned_reason=coalesce(banned_reason,'fraud: manual ban by '||coalesce(p_by,'admin')) where id = p_subject_id::uuid;
      elsif p_subject_type in ('supplier','lead','leads') then
        update leads set banned=true, matching_blocked=true, matching_block_reason=coalesce(matching_block_reason,'fraud ban'), banned_reason=coalesce(banned_reason,'fraud: manual ban by '||coalesce(p_by,'admin')) where id = p_subject_id::bigint;
      else v_ok:=false; v_msg:='unknown subject_type';
      end if;
    exception when others then v_ok:=false; v_msg:=SQLERRM;
    end;
    update fraud_flags set status='resolved', updated_at=now() where subject_type=p_subject_type and subject_id=p_subject_id;
  elsif p_action = 'unban' then
    begin
      if p_subject_type in ('customer','customers') then update customers set banned=false, banned_reason=null where id=p_subject_id::uuid;
      elsif p_subject_type in ('supplier','lead','leads') then update leads set banned=false, matching_blocked=false where id=p_subject_id::bigint;
      end if;
    exception when others then v_ok:=false; v_msg:=SQLERRM; end;
    update fraud_flags set status='resolved', updated_at=now() where subject_type=p_subject_type and subject_id=p_subject_id;
  elsif p_action = 'dismiss' then
    update fraud_flags set status='dismissed', updated_at=now() where subject_type=p_subject_type and subject_id=p_subject_id;
  else v_ok:=false; v_msg:='unknown action';
  end if;
  return jsonb_build_object('ok', v_ok, 'action', p_action, 'subject', p_subject_type||':'||p_subject_id, 'error', nullif(v_msg,''), 'by', p_by, 'at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_fraud_scan()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare before_ct int; after_ct int;
begin
  select count(*) into before_ct from fraud_flags;

  -- Abnormal pricing vs category benchmark (uses fn_price_confidence bands)
  insert into fraud_flags(kind,severity,subject_type,subject_id,detail,updated_at)
  select 'abnormal_price',
         case when (x.pc->>'band')='suspiciously_low' then 'high' else 'medium' end,
         'quote', q.id::text,
         jsonb_build_object('band',x.pc->>'band','amount',q.quote_amount,'category',i.category,'median',x.pc->>'median'), now()
  from quotes q join inquiries i on i.id=q.inquiry_id
  cross join lateral (select fn_price_confidence(i.category, q.quote_amount) as pc) x
  where (x.pc->>'band') in ('suspiciously_low','suspiciously_high')
  on conflict (kind,subject_type,subject_id) do update set detail=excluded.detail, severity=excluded.severity, updated_at=now();

  -- Duplicate registered-supplier phones
  insert into fraud_flags(kind,severity,subject_type,subject_id,detail,updated_at)
  select 'dup_supplier_phone','medium','phone', phone,
         jsonb_build_object('supplier_ids', array_agg(id), 'count', count(*)), now()
  from leads where claimed = true and coalesce(phone,'') <> '' group by phone having count(*) > 1
  on conflict (kind,subject_type,subject_id) do update set detail=excluded.detail, updated_at=now();

  -- Duplicate customer phones
  insert into fraud_flags(kind,severity,subject_type,subject_id,detail,updated_at)
  select 'dup_customer_phone','medium','cphone', phone,
         jsonb_build_object('customer_ids', array_agg(id), 'count', count(*)), now()
  from customers where coalesce(phone,'') <> '' group by phone having count(*) > 1
  on conflict (kind,subject_type,subject_id) do update set detail=excluded.detail, updated_at=now();

  -- Identical bid amounts on the same RFQ from different suppliers (possible collusion/copy)
  insert into fraud_flags(kind,severity,subject_type,subject_id,detail,updated_at)
  select 'identical_bids','high','inquiry', inquiry_id::text,
         jsonb_build_object('amount', quote_amount, 'suppliers', array_agg(distinct supplier_id)), now()
  from quotes where quote_amount > 0
  group by inquiry_id, quote_amount having count(distinct supplier_id) > 1
  on conflict (kind,subject_type,subject_id) do update set detail=excluded.detail, updated_at=now();

  -- Copied quotations: same committed_hash across different suppliers
  insert into fraud_flags(kind,severity,subject_type,subject_id,detail,updated_at)
  select 'copied_quote','high','hash', committed_hash,
         jsonb_build_object('quote_ids', array_agg(id), 'suppliers', array_agg(distinct supplier_id)), now()
  from quotes where coalesce(committed_hash,'') <> ''
  group by committed_hash having count(distinct supplier_id) > 1
  on conflict (kind,subject_type,subject_id) do update set detail=excluded.detail, updated_at=now();

  select count(*) into after_ct from fraud_flags;
  return jsonb_build_object('total_flags', after_ct, 'new_flags', after_ct - before_ct);
end $function$


CREATE OR REPLACE FUNCTION public.fn_gl_entry(p_date date, p_memo text, p_source text, p_ref text, p_lines jsonb, p_created_by text DEFAULT 'system'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare jid bigint; ln jsonb; i int := 0;
begin
  insert into public.gl_journal(entry_date, memo, source, source_ref, created_by)
    values (coalesce(p_date, (now() at time zone 'utc')::date), p_memo, coalesce(p_source,'manual'), p_ref, p_created_by)
    returning id into jid;
  for ln in select * from jsonb_array_elements(p_lines) loop
    i := i + 1;
    insert into public.gl_journal_lines(journal_id, line_no, account_code, debit, credit, memo)
      values (jid, i, (ln->>'account'),
              round(coalesce((ln->>'debit')::numeric,0),2),
              round(coalesce((ln->>'credit')::numeric,0),2),
              ln->>'memo');
  end loop;
  perform public.fn_gl_post(jid);
  return jid;
end $function$


CREATE OR REPLACE FUNCTION public.fn_gl_journal_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
  if tg_op in ('UPDATE','DELETE') and old.status = 'posted'
     and not (tg_op='UPDATE' and new.status='void' and old.status='posted' and new.reverses is not null) then
    -- allow only the controlled void marking done by fn_gl_reverse (new.status='void')
    if tg_op='DELETE' or (tg_op='UPDATE' and old.status='posted' and new.status='posted'
         and (new.entry_date<>old.entry_date or new.memo is distinct from old.memo or new.source<>old.source)) then
      raise exception 'Posted journal % is immutable (reverse it instead)', old.id;
    end if;
  end if;
  return case when tg_op='DELETE' then old else new end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_gl_lines_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare st text;
begin
  select status into st from public.gl_journal where id = coalesce(new.journal_id, old.journal_id);
  if st = 'posted' then
    raise exception 'Cannot modify lines of a posted journal (reverse it instead)';
  end if;
  return case when tg_op='DELETE' then old else new end;
end $function$


CREATE OR REPLACE FUNCTION public.fn_gl_net_income()
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select coalesce(sum(case when type='revenue' then balance else -balance end),0)
  from public.gl_account_balances where type in ('revenue','expense');
$function$


CREATE OR REPLACE FUNCTION public.fn_gl_post(p_journal bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare d numeric(18,2); c numeric(18,2); n int; st text;
begin
  select status into st from public.gl_journal where id=p_journal;
  if st is null then raise exception 'journal % not found', p_journal; end if;
  if st='posted' then return p_journal; end if;
  select coalesce(sum(debit),0), coalesce(sum(credit),0), count(*) into d,c,n from public.gl_journal_lines where journal_id=p_journal;
  if n < 2 then raise exception 'journal % needs at least 2 lines', p_journal; end if;
  if d <> c then raise exception 'journal % out of balance: debits % <> credits %', p_journal, to_char(d,'FM999999990.00'), to_char(c,'FM999999990.00'); end if;
  if d = 0 then raise exception 'journal % has zero amount', p_journal; end if;
  update public.gl_journal
     set status='posted', posted_at=now(),
         entry_no = coalesce(entry_no, 'JE-'||lpad(p_journal::text,6,'0'))
   where id=p_journal;
  return p_journal;
end $function$


CREATE OR REPLACE FUNCTION public.fn_gl_reverse(p_journal bigint, p_date date, p_memo text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare jid bigint; r record;
begin
  if (select status from public.gl_journal where id=p_journal) <> 'posted' then
    raise exception 'can only reverse a posted journal'; end if;
  insert into public.gl_journal(entry_date, memo, source, source_ref, reverses, created_by)
    values (coalesce(p_date,(now() at time zone 'utc')::date),
            coalesce(p_memo,'Reversal of JE '||p_journal), 'reversal', p_journal::text, p_journal, 'system')
    returning id into jid;
  for r in select account_code, debit, credit, line_no from public.gl_journal_lines where journal_id=p_journal loop
    insert into public.gl_journal_lines(journal_id, line_no, account_code, debit, credit)
      values (jid, r.line_no, r.account_code, r.credit, r.debit);  -- swap
  end loop;
  perform public.fn_gl_post(jid);
  return jid;
end $function$


CREATE OR REPLACE FUNCTION public.fn_gl_sync_business()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int := 0; acct text;
        fee_pct numeric; fee_fixed numeric; fee numeric(18,2); gross numeric(18,2); net numeric(18,2);
        fx numeric; amt_aed numeric(18,2); diff numeric(18,2); extra numeric(18,2); lines jsonb;
begin
  select num_value into fee_pct   from public.gl_settings where key='stripe_fee_pct';
  select num_value into fee_fixed from public.gl_settings where key='stripe_fee_fixed';
  select num_value into fx        from public.gl_settings where key='usd_to_aed';
  fee_pct   := coalesce(fee_pct,0);
  fee_fixed := coalesce(fee_fixed,0);
  fx        := coalesce(fx, 3.6725);

  -- 1) Reveal-fee revenue with Stripe fee split (refunded transactions excluded)
  for r in
    select id, reveal_fee, coalesce(revealed_at::date, current_date) as d
    from public.transactions
    where fee_status='paid' and coalesce(reveal_fee,0) > 0
      and coalesce(refund_status,'') not in ('refunded','refund_approved')
      and not exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=transactions.id::text)
  loop
    gross := round(r.reveal_fee,2);
    fee   := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net   := gross - fee;
    perform public.fn_gl_entry(r.d, 'Reveal fee (net of Stripe fee)', 'reveal_fee', r.id::text,
      case when fee > 0 then
        jsonb_build_array(
          jsonb_build_object('account','1050','debit',net),
          jsonb_build_object('account','6100','debit',fee),
          jsonb_build_object('account','4000','credit',gross))
      else
        jsonb_build_array(
          jsonb_build_object('account','1050','debit',gross),
          jsonb_build_object('account','4000','credit',gross))
      end, 'gl_sync');
    n := n + 1;
  end loop;

  -- 1b) REFUND PAID OUT TO THE CUSTOMER (previously never posted at all).
  -- If revenue was booked before the refund, this also reverses its effect on the P&L.
  for r in
    select t.id, coalesce(t.reveal_fee, t.app_fee, 0) as amt,
           coalesce(t.refund_resolved_at::date, t.revealed_at::date, current_date) as d
    from public.transactions t
    where coalesce(t.refund_status,'') in ('refunded','refund_approved')
      and coalesce(coalesce(t.reveal_fee, t.app_fee), 0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='refund_paid' and g.source_ref=t.id::text)
  loop
    gross := round(r.amt,2);
    perform public.fn_gl_entry(r.d, 'Reveal fee refunded to customer (paid from our balance)',
      'refund_paid', r.id::text,
      jsonb_build_array(jsonb_build_object('account','6900','debit',gross),
                        jsonb_build_object('account','1050','credit',gross)), 'gl_sync');
    n := n + 1;
  end loop;

  -- 2) Clawback RAISED on the supplier. Credits 6900 (recovering the refund), NOT 4100.
  --    Any admin fee / interest assessed at the same time is genuine income -> 4400.
  for r in
    select id, amount_due,
           coalesce(admin_fee,0) + coalesce(interest_amount,0) as extra_owed,
           coalesce(reveal_date, created_at::date, current_date) as d
    from public.supplier_dues
    where coalesce(amount_due,0) > 0
      and coalesce(status,'') not in ('waived','cancelled','reversed')
      and not exists (select 1 from public.gl_journal g where g.source='commission_accrue' and g.source_ref=supplier_dues.id::text)
  loop
    extra := round(coalesce(r.extra_owed,0),2);
    lines := jsonb_build_array(
      jsonb_build_object('account','1110','debit', round(r.amount_due,2) + extra),
      jsonb_build_object('account','6900','credit', round(r.amount_due,2)));
    if extra > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','4400','credit', extra)); end if;
    perform public.fn_gl_entry(r.d,
      'Refund clawback raised on supplier' || case when extra > 0 then ' (incl. ' || extra || ' admin fee/interest)' else '' end,
      'commission_accrue', r.id::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 2b) Supplier SETTLES via Stripe.
  for r in
    select id, amount_due,
           coalesce(fine_amount,0) + coalesce(interest_amount,0) + coalesce(admin_fee,0) as extra_owed,
           paid_at::date as d
    from public.supplier_dues
    where status in ('paid','settled') and paid_at is not null and coalesce(amount_due,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='commission_collect' and g.source_ref=supplier_dues.id::text)
  loop
    extra := round(coalesce(r.extra_owed,0),2);
    gross := round(r.amount_due,2) + extra;
    fee   := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net   := gross - fee;

    lines := jsonb_build_array(jsonb_build_object('account','1050','debit',net));
    if fee > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6100','debit',fee)); end if;
    lines := lines || jsonb_build_array(jsonb_build_object('account','1110','credit', gross));

    perform public.fn_gl_entry(r.d,
      'Refund clawback settled by supplier via Stripe' || case when extra > 0 then ' (incl. ' || extra || ' admin fee/interest)' else '' end,
      'commission_collect', r.id::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 2c) SUBSCRIPTION revenue (RULE 1). Previously never posted - 4200 sat unused.
  for r in
    select l.id, l.registration_fee_due, l.registration_paid_at::date as d
    from public.leads l
    where l.registration_status = 'paid'
      and l.registration_paid_at is not null
      and coalesce(l.registration_fee_due,0) >= 0
      and coalesce(l.subscription_exempt,false) = false
      and not exists (select 1 from public.gl_journal g
                      where g.source='subscription' and g.source_ref = l.id::text || ':' || l.registration_paid_at::date)
  loop
    gross := round(coalesce(r.registration_fee_due,0),2);
    if gross <= 0 then continue; end if;
    fee := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net := gross - fee;
    lines := jsonb_build_array(jsonb_build_object('account','1050','debit',net));
    if fee > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6100','debit',fee)); end if;
    lines := lines || jsonb_build_array(jsonb_build_object('account','4200','credit',gross));
    perform public.fn_gl_entry(r.d, 'Annual supplier subscription', 'subscription',
      r.id::text || ':' || r.d::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 3) Expense charges, converted to AED (the ledger currency)
  for r in
    select e.id, e.amount, upper(coalesce(e.currency,'AED')) as cur, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d
    from public.expense_entries e
    where coalesce(e.amount,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
  loop
    if r.cur not in ('AED','USD') then
      begin
        insert into public.founder_alerts(level, event, detail, channel)
        values ('warn', 'gl_unconvertible_currency',
                'Expense #'||r.id||' from '||coalesce(r.vendor,'?')||' is in '||r.cur||
                ', which has no rate in gl_settings, so it was NOT posted. Expenses are understated by '||
                r.amount||' '||r.cur||' until a rate is added. Skipped rather than booked at 1:1.', 'system');
      exception when others then null; end;
      continue;
    end if;
    amt_aed := round(r.amount * case when r.cur='USD' then fx else 1 end, 2);
    acct := coalesce((select account_code from public.gl_expense_map m where m.category=r.category), '6300');
    perform public.fn_gl_entry(r.d,
      'Expense: '||coalesce(r.category,'G&A')||case when r.cur='USD' then ' ('||r.amount||' USD @ '||fx||')' else '' end,
      'expense', r.id::text,
      jsonb_build_array(jsonb_build_object('account',acct,'debit',amt_aed),
                        jsonb_build_object('account','1000','credit',amt_aed)), 'gl_sync');
    n := n + 1;
  end loop;

  -- 3b) One-off FX correction for USD expenses posted at 1:1 before the 19 Jul 2026 fix.
  for r in
    select e.id, e.amount, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d,
           (select sum(jl.debit) from public.gl_journal g
              join public.gl_journal_lines jl on jl.journal_id = g.id
             where g.source='expense' and g.source_ref = e.id::text and jl.debit > 0) as posted_aed
    from public.expense_entries e
    where upper(coalesce(e.currency,'AED')) = 'USD'
      and coalesce(e.amount,0) > 0
      and exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
      and not exists (select 1 from public.gl_journal g where g.source='expense_fx_adj' and g.source_ref=e.id::text)
  loop
    diff := round(r.amount * fx, 2) - coalesce(r.posted_aed, 0);
    if diff is null or diff = 0 then continue; end if;
    acct := coalesce((select account_code from public.gl_expense_map m where m.category=r.category), '6300');
    perform public.fn_gl_entry(r.d,
      'FX correction: expense #'||r.id||' ('||coalesce(r.vendor,'?')||') was booked at 1:1; restated at USD/AED '||fx,
      'expense_fx_adj', r.id::text,
      jsonb_build_array(jsonb_build_object('account',acct,'debit',diff),
                        jsonb_build_object('account','1000','credit',diff)), 'gl_fx_fix');
    n := n + 1;
  end loop;

  return n;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_governance_stamp()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_sensitive boolean;
begin
  v_sensitive := (coalesce(NEW.agent,'') ~* 'legal|financ|complian|security'
                  or coalesce(NEW.kind,'') ~* 'legal|financ|complian|security|payment|refund|payout|pricing|price');

  -- Explainability: stamp a confidence + evidence basis when the caller did not provide one.
  -- These agents derive recommendations deterministically from live platform data, so the
  -- factual basis is high-confidence; the evidence line records exactly why.
  if NEW.confidence is null then
    NEW.confidence := 0.9;
    if NEW.evidence is null then
      NEW.evidence := jsonb_build_object('basis','deterministic rule from live platform data',
                                         'agent',NEW.agent,'kind',NEW.kind);
    end if;
  end if;

  -- Escalation marker (does not reroute status): low confidence or sensitive domain.
  if NEW.escalated is not true and (coalesce(NEW.confidence,0) < 0.6 or v_sensitive) then
    NEW.escalated := true;
    NEW.escalation_reason := coalesce(NEW.escalation_reason,
      case when coalesce(NEW.confidence,0) < 0.6
           then 'Confidence below 0.60 threshold — human review required.'
           else 'Sensitive domain (legal/financial/compliance/security) — human review required.' end);
  end if;

  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_graph_rebuild()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n_nodes int; n_edges int;
begin
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select distinct 'category', category, category, '{}'::jsonb, now()
    from inquiries where category is not null
    on conflict (kind,ref_id) do update set updated_at=now();
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'rfq', id::text, coalesce(summary,category), jsonb_build_object('status',status,'stage',pipeline_stage,'emirate',emirate,'budget',budget), now() from inquiries
    on conflict (kind,ref_id) do update set label=excluded.label, props=excluded.props, updated_at=now();
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'customer', c.id::text, coalesce(c.full_name,c.email), '{}'::jsonb, now()
    from customers c where c.id in (select distinct customer_id from inquiries where customer_id is not null)
    on conflict (kind,ref_id) do update set updated_at=now();
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'supplier', l.id::text, l.company_name, jsonb_build_object('emirate',l.emirate), now()
    from leads l where l.id in (
      select supplier_id from inquiry_matches where supplier_id is not null
      union select supplier_id from quotes where supplier_id is not null
      union select hired_supplier_id from inquiries where hired_supplier_id is not null)
    on conflict (kind,ref_id) do update set label=excluded.label, updated_at=now();
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'regulation', id::text, coalesce(title, doc_ref, 'regulation '||id),
           jsonb_build_object('authority',authority,'status',status,'version',version,'effective_date',effective_date,'doc_ref',doc_ref), now()
    from regulations
    on conflict (kind,ref_id) do update set label=excluded.label, props=excluded.props, updated_at=now();
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select distinct 'category', c, c, '{}'::jsonb, now()
    from regulations r, unnest(r.categories) c where c is not null and c<>''
    on conflict (kind,ref_id) do update set updated_at=now();

  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'customer', customer_id::text, 'created', 'rfq', id::text, '{}'::jsonb, now() from inquiries where customer_id is not null
    on conflict do nothing;
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'rfq', id::text, 'in_category', 'category', category, '{}'::jsonb, now() from inquiries where category is not null
    on conflict do nothing;
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'rfq', inquiry_id::text, 'invited', 'supplier', supplier_id::text, '{}'::jsonb, now() from inquiry_matches where supplier_id is not null
    on conflict do nothing;
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'supplier', q.supplier_id::text, 'quoted', 'rfq', q.inquiry_id::text,
           jsonb_build_object('amount',q.quote_amount), now()
    from (select distinct on (supplier_id, inquiry_id) supplier_id, inquiry_id, quote_amount
            from quotes where supplier_id is not null
           order by supplier_id, inquiry_id) q
    on conflict (src_kind,src_ref,rel,dst_kind,dst_ref) do update set props=excluded.props, updated_at=now();
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'rfq', id::text, 'hired', 'supplier', hired_supplier_id::text, '{}'::jsonb, now() from inquiries where hired_supplier_id is not null
    on conflict do nothing;
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'customer', rv.customer_id::text, 'reviewed', 'supplier', rv.supplier_id::text,
           jsonb_build_object('rating',rv.rating), now()
    from (select distinct on (customer_id, supplier_id) customer_id, supplier_id, rating
            from reviews where supplier_id is not null and customer_id is not null
           order by customer_id, supplier_id) rv
    on conflict (src_kind,src_ref,rel,dst_kind,dst_ref) do update set props=excluded.props, updated_at=now();
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select distinct 'regulation', r.id::text, 'applies_to', 'category', c, '{}'::jsonb, now()
    from regulations r, unnest(r.categories) c where c is not null and c<>''
    on conflict do nothing;
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'regulation', id::text, 'supersedes', 'regulation', supersedes_id::text, '{}'::jsonb, now()
    from regulations where supersedes_id is not null
    on conflict do nothing;

  select count(*) into n_nodes from graph_nodes;
  select count(*) into n_edges from graph_edges;
  return jsonb_build_object('nodes',n_nodes,'edges',n_edges);
end $function$


CREATE OR REPLACE FUNCTION public.fn_health_index()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  s_acq numeric; s_supp numeric; s_rfq numeric; s_qual numeric;
  s_resp numeric; s_disp numeric; s_up numeric;
  signups_7d int; quotes_7d int; approved_suppliers int;
  inq_total int; inq_done int; avg_qual numeric; avg_resp numeric;
  blocked_30d int; msgs_30d int; up_ok int; up_tot int;
  parts numeric[]; overall numeric; band text; present int;
begin
  select count(*) into signups_7d from customers where created_at > now()-interval '7 days';
  select count(*) into quotes_7d  from quotes    where created_at > now()-interval '7 days';
  select count(*) into approved_suppliers from leads
     where coalesce(approval_status,'')='approved' or claimed=true;
  -- RFQ completion: real RFQs only (exclude split-parent containers and customer-cancelled),
  -- success = completed/won or closed-with-a-hire (a "closed, not hired" is NOT a completion).
  select count(*) filter (where created_at > now()-interval '90 days'
                            and coalesce(status,'')<>'split' and coalesce(category,'')<>'combined'
                            and coalesce(status,'')<>'cancelled'),
         count(*) filter (where created_at > now()-interval '90 days'
                            and coalesce(status,'')<>'split' and coalesce(category,'')<>'combined'
                            and (status in ('completed','won')
                                 or (status='closed' and coalesce(outcome,'') in ('hired','hired_elsewhere'))))
    into inq_total, inq_done from inquiries;
  select avg(nullif(quality->>'score','')::numeric) into avg_qual
    from quotes where quality is not null and created_at > now()-interval '90 days';
  select avg(nullif(rv_response_rate,0)) into avg_resp
    from leads where coalesce(rv_reveals,0) > 0;
  select count(*) filter (where coalesce(blocked,false)),
         count(*) into blocked_30d, msgs_30d
    from messages where created_at > now()-interval '30 days';
  select count(*) filter (where ok), count(*) into up_ok, up_tot
    from health_checks where created_at > now()-interval '24 hours';

  s_acq  := least(100, signups_7d * 10.0);
  s_supp := case when approved_suppliers=0 and quotes_7d=0 then null
                 else least(100, quotes_7d * 5.0) end;
  s_rfq  := case when inq_total=0 then null else round(inq_done::numeric/inq_total*100,1) end;
  s_qual := avg_qual;
  s_resp := case when avg_resp is null then null
                 when avg_resp <= 1 then round(avg_resp*100,1) else round(avg_resp,1) end;
  s_disp := case when msgs_30d=0 then null
                 else greatest(0, 100 - least(100, blocked_30d*5.0)) end;
  s_up   := case when up_tot=0 then null else round(up_ok::numeric/up_tot*100,1) end;

  parts := array_remove(array[s_acq,s_supp,s_rfq,s_qual,s_resp,s_disp,s_up], null);
  present := coalesce(array_length(parts,1),0);
  overall := case when present=0 then null else round((select avg(x) from unnest(parts) x),1) end;
  band := case when overall is null then 'no data'
               when overall >= 75 then 'healthy'
               when overall >= 50 then 'watch'
               else 'attention' end;

  return jsonb_build_object(
    'index', overall, 'band', band, 'components_present', present,
    'note', case when present < 3 then 'insufficient data — pre-traction; index will firm up with volume' else null end,
    'components', jsonb_build_object(
       'customer_acquisition', s_acq, 'supplier_activity', s_supp, 'rfq_completion', s_rfq,
       'quote_quality', s_qual, 'response_time', s_resp, 'dispute_health', s_disp,
       'uptime', s_up, 'revenue', null),
    'raw', jsonb_build_object(
       'signups_7d', signups_7d, 'quotes_7d', quotes_7d, 'approved_suppliers', approved_suppliers,
       'inquiries_eligible_90d', inq_total, 'completed_90d', inq_done,
       'blocked_msgs_30d', blocked_30d, 'uptime_ok', up_ok, 'uptime_checks', up_tot),
    'computed_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_identify_contact(p_phone text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_d text; v_tail text; v_name text; v_sid bigint; v_cid text; v_claimed boolean; v_appr boolean;
begin
  v_d := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  if length(v_d) < 7 then return json_build_object('audience','unknown'); end if;
  v_tail := right(v_d, 9);   -- tolerate +9715..., 05..., 5... variants

  select id, company_name, coalesce(claimed,false), (approval_status='approved')
    into v_sid, v_name, v_claimed, v_appr
   from leads
   where right(regexp_replace(coalesce(phone_e164,''),'[^0-9]','','g'),9) = v_tail
      or right(regexp_replace(coalesce(phone,''),'[^0-9]','','g'),9) = v_tail
      or right(regexp_replace(coalesce(whatsapp,''),'[^0-9]','','g'),9) = v_tail
   limit 1;
  if v_sid is not null then
    return json_build_object('audience','supplier','name',v_name,'claimed',v_claimed,'approved',coalesce(v_appr,false));
  end if;

  select id::text, full_name into v_cid, v_name from customers
   where right(regexp_replace(coalesce(phone,''),'[^0-9]','','g'),9) = v_tail
   limit 1;
  if v_cid is not null then
    return json_build_object('audience','customer','name',v_name);
  end if;

  return json_build_object('audience','unknown');
end $function$


CREATE OR REPLACE FUNCTION public.fn_inbox_list()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'needs_review', (select count(*) from public.inbound_messages where needs_review=true and replied_at is null),
      'untriaged', (select count(*) from public.inbound_messages where needs_review=true and triaged_at is null and replied_at is null),
      'replied_7d', (select count(*) from public.inbound_messages where replied_at > now()-interval '7 days')),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'id',id,'from_email',from_email,'subject',subject,'body',left(coalesce(body,''),1200),
        'category',ai_category,'summary',ai_summary,'draft',ai_draft_reply,
        'triaged_at',triaged_at,'created_at',created_at) order by created_at desc)
      from (select * from public.inbound_messages
             where needs_review=true and replied_at is null order by created_at desc limit 50) m),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_inbox_send(p_id bigint, p_body text, p_by text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare m public.inbound_messages%rowtype;
begin
  select * into m from public.inbound_messages where id=p_id;
  if m.id is null then return jsonb_build_object('error','message not found'); end if;
  if m.from_email is null then return jsonb_build_object('error','no sender address'); end if;
  if coalesce(trim(p_body),'')='' then return jsonb_build_object('error','empty reply'); end if;

  insert into public.notifications(type,to_email,to_role,channel,subject,body)
    values('inbound_reply', m.from_email, null, 'email',
           case when coalesce(m.subject,'') ilike 're:%' then m.subject else 'Re: '||coalesce(m.subject,'your message') end,
           p_body);

  update public.inbound_messages set replied_at=now(), replied_by=coalesce(p_by,'founder'), needs_review=false where id=p_id;
  update public.agent_actions set status='approved', decided_by=coalesce(p_by,'founder'), decided_at=now()
   where target_table='inbound_messages' and target_id=p_id::text
     and status in ('pending','held_for_review','proposed','open');
  return jsonb_build_object('ok',true, 'to', m.from_email);
end $function$


CREATE OR REPLACE FUNCTION public.fn_inv_adjust(p_item bigint, p_qty_delta numeric, p_unit_cost numeric DEFAULT NULL::numeric, p_offset_account text DEFAULT '6300'::text, p_date date DEFAULT NULL::date, p_memo text DEFAULT NULL::text, p_by text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare onq numeric(18,4); onv numeric(18,2); avg_c numeric(18,4);
        uc numeric(18,4); amt numeric(18,2); j bigint; inv_acct text; m bigint;
begin
  if p_qty_delta = 0 then raise exception 'adjustment qty_delta cannot be 0'; end if;
  select coalesce(sum(qty_delta),0), coalesce(sum(cost_delta),0)
    into onq, onv from public.inv_stock_moves where item_id=p_item;
  avg_c := case when onq <> 0 then onv/onq else 0 end;
  uc := coalesce(p_unit_cost, avg_c);                 -- default to current avg for reductions
  amt := round(p_qty_delta * uc, 2);                  -- signed
  select inventory_account into inv_acct from public.inv_items where id=p_item;
  if inv_acct is null then raise exception 'item % not found', p_item; end if;
  -- positive delta: Dr Inventory / Cr offset ; negative: Dr offset / Cr Inventory
  if amt >= 0 then
    j := public.fn_gl_entry(coalesce(p_date,current_date), coalesce(p_memo,'Inventory adjustment'),
           'inv_adjust', p_item::text,
           jsonb_build_array(jsonb_build_object('account',inv_acct,'debit',amt),
                             jsonb_build_object('account',p_offset_account,'credit',amt)), p_by);
  else
    j := public.fn_gl_entry(coalesce(p_date,current_date), coalesce(p_memo,'Inventory adjustment'),
           'inv_adjust', p_item::text,
           jsonb_build_array(jsonb_build_object('account',p_offset_account,'debit',-amt),
                             jsonb_build_object('account',inv_acct,'credit',-amt)), p_by);
  end if;
  insert into public.inv_stock_moves(item_id,move_date,move_type,qty_delta,cost_delta,
       unit_cost,ref_type,ref_id,gl_journal_id,memo,created_by)
    values (p_item, coalesce(p_date,current_date),'adjust', p_qty_delta, amt, uc,
            'adjust', p_item::text, j, p_memo, p_by)
    returning id into m;
  return m;
end $function$


CREATE OR REPLACE FUNCTION public.fn_inv_issue(p_item bigint, p_qty numeric, p_date date DEFAULT NULL::date, p_ref_type text DEFAULT 'manual'::text, p_ref_id text DEFAULT NULL::text, p_by text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare onq numeric(18,4); onv numeric(18,2); avg_c numeric(18,4);
        amt numeric(18,2); j bigint; inv_acct text; cogs_acct text; m bigint;
begin
  select coalesce(sum(qty_delta),0), coalesce(sum(cost_delta),0)
    into onq, onv from public.inv_stock_moves where item_id=p_item;
  if p_qty <= 0 then raise exception 'issue qty must be > 0'; end if;
  if p_qty > onq then raise exception 'insufficient stock for item %: have %, need %', p_item, onq, p_qty; end if;
  avg_c := case when onq <> 0 then onv/onq else 0 end;
  amt := round(p_qty * avg_c, 2);
  select inventory_account, cogs_account into inv_acct, cogs_acct from public.inv_items where id=p_item;
  j := public.fn_gl_entry(coalesce(p_date,current_date),
         'Inventory issue item '||p_item, 'inv_issue', p_ref_id,
         jsonb_build_array(jsonb_build_object('account',cogs_acct,'debit',amt),
                           jsonb_build_object('account',inv_acct,'credit',amt)), p_by);
  insert into public.inv_stock_moves(item_id,move_date,move_type,qty_delta,cost_delta,
       unit_cost,ref_type,ref_id,gl_journal_id,created_by)
    values (p_item, coalesce(p_date,current_date),'out', -p_qty, -amt, avg_c,
            p_ref_type, p_ref_id, j, p_by)
    returning id into m;
  return m;
end $function$


CREATE OR REPLACE FUNCTION public.fn_inv_receive(p_item bigint, p_qty numeric, p_unit_cost numeric, p_date date DEFAULT NULL::date, p_ref_type text DEFAULT 'manual'::text, p_ref_id text DEFAULT NULL::text, p_post_gl boolean DEFAULT true, p_by text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare amt numeric(18,2); j bigint; inv_acct text; m bigint;
begin
  if p_qty <= 0 then raise exception 'receive qty must be > 0'; end if;
  select inventory_account into inv_acct from public.inv_items where id=p_item;
  if inv_acct is null then raise exception 'item % not found', p_item; end if;
  amt := round(p_qty * p_unit_cost, 2);
  if p_post_gl then                                   -- Dr Inventory  Cr Cash(1000)
    j := public.fn_gl_entry(coalesce(p_date,current_date),
           'Inventory receipt item '||p_item, 'inv_receipt', p_ref_id,
           jsonb_build_array(jsonb_build_object('account',inv_acct,'debit',amt),
                             jsonb_build_object('account','1000','credit',amt)), p_by);
  end if;
  insert into public.inv_stock_moves(item_id,move_date,move_type,qty_delta,cost_delta,
       unit_cost,ref_type,ref_id,gl_journal_id,created_by)
    values (p_item, coalesce(p_date,current_date),'in', p_qty, amt, p_unit_cost,
            p_ref_type, p_ref_id, j, p_by)
    returning id into m;
  return m;
end $function$


CREATE OR REPLACE FUNCTION public.fn_invite_ramp()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_base int := 10; v_ceiling int := 200;
  v_start date; v_days int; v_stage int;
  v_sent7 int; v_bounced7 int; v_rate numeric;
  v_cur int; v_new int; v_note text;
begin
  -- only manage the cap while the campaign is on; if paused, leave it as-is
  if coalesce((select value from app_secrets where key='invite_enabled'),'false') <> 'true' then
    return coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), v_base);
  end if;

  v_cur := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), v_base);
  select min(invited_at)::date into v_start from leads where invited_at is not null;

  if v_start is null then
    v_new := v_base;                              -- nothing sent yet
  else
    v_days := (now() at time zone 'UTC')::date - v_start;
    v_stage := case when v_days < 7 then 10 when v_days < 14 then 25
                    when v_days < 21 then 50 when v_days < 28 then 100 else v_ceiling end;
    select count(*) into v_sent7    from leads where invited_at > now() - interval '7 days';
    select count(*) into v_bounced7 from leads where invite_status='bounced' and invited_at > now() - interval '7 days';
    v_rate := v_bounced7::numeric / greatest(v_sent7,1);

    if v_sent7 >= 20 and v_rate >= 0.05 then
      v_new := greatest(v_base, floor(v_cur * 0.5)::int);   -- deliverability wobble: throttle down
      v_note := 'throttle: 7d bounce '||round(v_rate*100,1)||'% ('||v_bounced7||'/'||v_sent7||') >= 5%; cap '||v_cur||'->'||v_new;
    else
      v_new := least(v_stage, v_cur * 2);                   -- healthy: warm up, at most 2x/day, capped by the day-stage
      v_note := 'healthy: day '||v_days||', stage '||v_stage||', 7d bounce '||round(v_rate*100,1)||'% ('||v_bounced7||'/'||greatest(v_sent7,0)||'); cap '||v_cur||'->'||v_new;
    end if;
  end if;

  v_new := greatest(v_base, least(v_new, v_ceiling));
  if v_new <> v_cur then
    update app_secrets set value = v_new::text where key='invite_daily_cap';
    insert into agent_runs(agent,status,counts,note,finished_at)
      values('invite_ramp','ok',jsonb_build_object('old_cap',v_cur,'new_cap',v_new),coalesce(v_note,''),now());
    if v_new < v_cur then
      insert into founder_alerts(level,event,detail,channel)
        values('warn','invite_cap_throttled','Supplier-invite cap reduced '||v_cur||'->'||v_new||' — '||coalesce(v_note,'')||'. Hard auto-pause still triggers at 8%.','system');
    end if;
  end if;
  return v_new;
end; $function$


CREATE OR REPLACE FUNCTION public.fn_invite_week_activate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.kind = 'invite_campaign_week'
     and NEW.status in ('approved','done','auto_done','accepted','resolved','closed','completed')
     and coalesce(OLD.status,'') is distinct from NEW.status then
    update invite_schedule set status='approved' where status='pending' and day >= (now() at time zone 'UTC')::date;
    update app_secrets set value='true' where key in ('invite_enabled','supplier_emails_enabled');
    insert into founder_alerts(level,event,detail,channel)
      values('info','invite_week_approved','Supplier invite week approved in OS — schedule activated and sending enabled.','system');
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_is_working_day(p_date date)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select extract(isodow from p_date) < 6
     and not exists (select 1 from public.public_holidays h where h.holiday_date = p_date);
$function$


CREATE OR REPLACE FUNCTION public.fn_kb_approve(p_revision bigint, p_reviewer text, p_notes text DEFAULT NULL::text, p_publish boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record;
begin
  select * into r from public.kb_revisions where id=p_revision;
  if r is null then return jsonb_build_object('error','revision not found'); end if;
  update public.kb_revisions set status=case when p_publish then 'published' else 'approved' end,
    reviewer=p_reviewer, review_notes=p_notes, decided_at=now() where id=p_revision;
  -- apply to live agent_knowledge when publishing that kind
  if p_publish and r.entry_kind='agent_knowledge' and position(' :: ' in r.entry_ref)>0 then
    update agent_knowledge set content=r.content
     where agent_key=split_part(r.entry_ref,' :: ',1) and topic=split_part(r.entry_ref,' :: ',2);
  end if;
  return jsonb_build_object('ok',true,'revision',p_revision,'status',case when p_publish then 'published' else 'approved' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_kb_gov_approve(p_kind text, p_id text, p_by text DEFAULT 'founder'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  if p_kind = 'regulation' then
    update regulations set approved_at = now(), approved_by = p_by where id::text = p_id and approved_at is null;
    get diagnostics n = row_count;
    perform kb_sync();
    update agent_actions set status='approved', decided_at=now(), decided_by=p_by
      where kind='knowledge_approval' and detail->>'ref'=p_id and detail->>'kind'='regulation' and status in ('pending','needs_review');
    return jsonb_build_object('approved', n, 'kind', p_kind, 'id', p_id);
  end if;
  return jsonb_build_object('error','unsupported_kind', 'kind', p_kind);
end $function$


CREATE OR REPLACE FUNCTION public.fn_kb_reconcile()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_stripped int:=0; v_aliased int:=0; v_uncat int; v_noncanon int;
begin
  with upd as (
    update public.kb_chunks c set category = substring(c.category from 5)
    where c.category like 'cat:%'
      and ( substring(c.category from 5) in (select slug from public.category_agents where active)
         or substring(c.category from 5) in (select category from public.category_specs) )
    returning 1
  ) select count(*) into v_stripped from upd;

  with oneone as (
    select category, min(maps_to) as target
    from public.kb_category_aliases group by category having count(distinct maps_to)=1
  ), upd2 as (
    update public.kb_chunks c set category = o.target
    from oneone o where c.category = o.category and c.category <> o.target
    returning 1
  ) select count(*) into v_aliased from upd2;

  select count(*) into v_uncat from public.kb_chunks where category is null or category='';
  select count(distinct category) into v_noncanon from public.kb_chunks
    where category is not null and category<>'' and category not like 'cat:%'
      and category not in (select slug from public.category_agents where active)
      and category not in (select category from public.category_specs);

  return jsonb_build_object('cat_prefix_stripped',v_stripped,'alias_remapped',v_aliased,
    'uncategorized_left',v_uncat,'noncanonical_categories_left',v_noncanon,
    'note','Normalized kb_chunks categories: stripped '||v_stripped||' cat: prefix(es), remapped '||v_aliased||' via curated 1:1 aliases. '||v_uncat||' chunk(s) remain uncategorized (global knowledge — still semantically retrievable).');
end $function$


CREATE OR REPLACE FUNCTION public.fn_kb_submit_revision(p_kind text, p_ref text, p_content text, p_author text DEFAULT 'agent'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare id bigint;
begin
  insert into public.kb_revisions(entry_kind,entry_ref,version,content,status,author,ai_validation)
  values (p_kind,p_ref, public._kb_next_ver(p_kind,p_ref), p_content, 'in_review', p_author, public.fn_kb_validate(p_content))
  returning id into id;
  return id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_kb_validate(p_content text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare flags text[]:='{}'; ok boolean:=true;
begin
  if length(coalesce(p_content,'')) < 40 then flags:=array_append(flags,'too_short'); ok:=false; end if;
  if p_content !~* '(source|per |according to|standard|code|regulation|SIRA|DCD|DEWA|ISO|IEC|BS |EN |NFPA|Estidama|ESMA|[0-9])' then
     flags:=array_append(flags,'no_citation_or_specifics'); ok:=false; end if;
  if p_content ~* '(always|never|guaranteed|100%|best in the world)' then flags:=array_append(flags,'absolute_claim_review'); end if;
  return jsonb_build_object('passed',ok,'flags',to_jsonb(flags),'checked_at',now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_knowledge_curator()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k record; v_health numeric; n_task int; n_appr int:=0; rec record; rc record;
begin
  select * into k from knowledge_kpis;
  select * into rc from reg_coverage;
  v_health := round(coalesce(k.coverage_pct,0)*0.30 + coalesce(k.accuracy_pct,0)*0.25 + coalesce(k.freshness_pct,0)*0.25 + coalesce(k.usage_reach_pct,0)*0.20,1);
  insert into knowledge_kpi_snapshots(snapshot_date,kpis) values (current_date, to_jsonb(k) || jsonb_build_object('health',v_health,'reg_coverage',to_jsonb(rc)))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  perform kn_task('playbook_gap', (k.categories_total - k.cat_with_playbook) > 0, 'medium', 'Qualification playbook gaps',
    (k.categories_total - k.cat_with_playbook)||' of '||k.categories_total||' categories lack a qualification playbook. Generating them sharpens RFQ qualification quality.');
  perform kn_task('stale_compliance', (k.compliance_active - k.compliance_fresh) > 0, 'low', 'Stale compliance sources',
    (k.compliance_active - k.compliance_fresh)||' compliance sources have not been re-checked in 45 days.');
  perform kn_task('low_accuracy', coalesce(k.flagged_revisions,0) > 0, 'medium', 'Knowledge flagged by validation',
    k.flagged_revisions||' knowledge revisions failed or were flagged by AI validation. Review before they can mislead the agents.');
  perform kn_task('reg_coverage', rc.missing > 0, 'high', 'UAE codes not yet indexed as full documents',
    'Regulatory library is '||rc.coverage_pct||'% complete ('||rc.indexed||'/'||rc.free_codes||' free-published codes fully indexed; '||rc.critical_indexed||'/'||rc.critical_total||' critical). Still missing (critical first): '
    ||coalesce((select string_agg(authority||' — '||code_name, '; ') from (select authority,code_name from reg_catalog where copyright='free' and status<>'indexed' order by priority, authority limit 10) g),'none')
    ||'. Many are portal/viewer-gated or scanned — supply official full PDFs (or a licensed copy) to index them.');

  for rec in select id::text as rid, title, authority from regulations where approved_at is null loop
    if not exists (select 1 from agent_actions where kind='knowledge_approval' and detail->>'ref'=rec.rid and detail->>'kind'='regulation' and status in ('pending','needs_review')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
      values ('knowledge_curator','knowledge_approval','pending','high',
        'Approve regulation: '||coalesce(rec.title,'#'||rec.rid),
        'A new/updated high-stakes regulation ('||coalesce(rec.authority,'')||') is awaiting your approval before it publishes to the knowledge base.',
        jsonb_build_object('kind','regulation','ref',rec.rid,'authority',rec.authority),'regulations', rec.rid);
      n_appr := n_appr + 1;
    end if;
  end loop;

  select count(*) into n_task from agent_actions where agent='knowledge_curator' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'health',v_health,'kpis',to_jsonb(k),'reg_coverage',to_jsonb(rc),'open_items',n_task,'new_approvals',n_appr);
end $function$


CREATE OR REPLACE FUNCTION public.fn_kv_block(obj jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k text; v text; out text := ''; begin
  if obj is null then return '  (no data)'; end if;
  for k, v in select key, value from jsonb_each_text(obj) loop
    if v is null or k in ('id','snapshot_date','created_at','captured_at') then continue; end if;
    out := out || '  ' || initcap(replace(k,'_',' ')) || ': ' || v || E'\n';
  end loop;
  if out = '' then out := '  (no data)'; end if;
  return rtrim(out, E'\n');
end $function$


CREATE OR REPLACE FUNCTION public.fn_legal_ai()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k record; v_health numeric; v_terms numeric; v_fresh numeric; n int; v_missing text; v_regchg int;
begin
  select * into k from legal_kpis;
  -- refresh checklist presence
  update legal_checklist lc set present = exists(select 1 from legal_documents d where d.slug = lc.match_slug);

  v_terms := round((coalesce(k.customer_terms_acceptance_pct,0)+coalesce(k.supplier_terms_acceptance_pct,0))/2,1);
  v_fresh := case when k.policies_published=0 then 0 else round(100.0*(k.policies_published-k.policies_stale)/k.policies_published,1) end;
  v_health := round(coalesce(k.coverage_pct,0)*0.35 + v_terms*0.30 + v_fresh*0.20 + greatest(0,100-coalesce(k.open_legal_flags,0)*10)*0.15,1);

  insert into legal_kpi_snapshots(snapshot_date,kpis) values (current_date, to_jsonb(k)||jsonb_build_object('legal_health',v_health,'terms_acceptance_avg',v_terms))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  select string_agg(requirement,'; ') into v_missing from legal_checklist where not present and priority=1;
  select count(*) into v_regchg from compliance_sources where last_changed_at >= now()-interval '30 days';

  -- ESCALATIONS (founder-visible legal_flag; never legal advice)
  perform leg_flag('missing_core_docs', coalesce(k.critical_missing,0)>0, 'high', 'Core legal documents missing',
    'The platform is operating without these core documents: '||coalesce(v_missing,'')||'. They govern your contractual relationship with customers and suppliers (liability, governing law, dispute resolution). Have a licensed UAE lawyer prepare and approve them, then publish as versioned legal documents.');
  perform leg_flag('supplier_terms_acceptance', coalesce(k.suppliers_approved,0)>0 and coalesce(k.supplier_terms_acceptance_pct,0) < 90, 'high', 'Suppliers have not accepted current terms',
    'Only '||coalesce(k.supplier_terms_acceptance_pct,0)||'% of approved suppliers have accepted the current terms. Enforce terms acceptance (click-wrap / signed) at onboarding so agreements are enforceable.');
  perform leg_flag('customer_terms_acceptance', coalesce(k.customer_terms_acceptance_pct,0) < 90, 'medium', 'Customers have not accepted current terms',
    'Only '||coalesce(k.customer_terms_acceptance_pct,0)||'% of customers have accepted the current terms. Gate key actions (posting an inquiry / paying to reveal) behind explicit terms acceptance.');
  perform leg_flag('stale_policies', coalesce(k.policies_stale,0)>0, 'low', 'Policies due for annual review',
    k.policies_stale||' published policy(ies) have not been reviewed in over a year. Schedule an annual legal review.');
  perform leg_flag('reg_change_review', v_regchg>0, 'medium', 'Regulatory change may affect your terms/policies',
    v_regchg||' monitored authority source(s) changed in the last 30 days. Review whether your terms, privacy or compliance policies need updating with a lawyer.');

  select count(*) into n from agent_actions where agent='legal_ai' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'legal_health',v_health,'kpis',to_jsonb(k),'open_flags',n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_lint_outbound(p_hours integer DEFAULT 24)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'hits', count(*),
    'sample', coalesce(jsonb_agg(jsonb_build_object('when',a.created_at,'rule',p.name,'reply',left(a.reply,160))) filter (where p.id is not null), '[]'::jsonb)
  )
  from assistant_logs a
  left join policy_rules p on p.active and a.reply ~* p.forbid_regex
  where a.created_at > now() - make_interval(hours => p_hours)
    and p.id is not null;
$function$


CREATE OR REPLACE FUNCTION public.fn_llm_drift_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb := '[]'::jsonb; v_off int; v_fb numeric; v_fail int; v_owner text; v_recent int;
begin
  select count(*) into v_recent from llm_calls where created_at > now() - interval '24 hours';
  if v_recent = 0 then
    return jsonb_build_object('checked_at', now(), 'calls_24h', 0, 'findings', 0,
                              'note','no llm traffic in 24h - nothing to judge');
  end if;

  -- 1. any model not on the approved list
  select count(*) into v_off from v_llm_offpolicy;
  if v_off > 0 then
    v := v || jsonb_build_object('issue','off_policy_model','severity','high',
         'detail',(select jsonb_agg(jsonb_build_object('fn',fn,'model',model,'calls',calls)) from v_llm_offpolicy));
  end if;

  -- 2. fallback rate: Opus answering when Sonnet was asked means Sonnet is failing
  select round(100.0 * count(*) filter (where fell_back) / nullif(count(*),0), 1)
    into v_fb from llm_calls where created_at > now() - interval '24 hours';
  if coalesce(v_fb,0) > 20 then
    v := v || jsonb_build_object('issue','high_fallback_rate','severity','high','pct',v_fb,
         'detail','the primary model is failing often - you are paying fallback prices silently');
  end if;

  -- 3. outright failures
  select count(*) into v_fail from llm_calls
   where created_at > now() - interval '24 hours' and not ok;
  if v_fail > 5 then
    v := v || jsonb_build_object('issue','llm_failures','severity','medium','count',v_fail);
  end if;

  if jsonb_array_length(v) > 0 then
    v_owner := split_part(coalesce((select value from app_secrets where key='admin_emails'),
                                   'management@quotesdone.com'), ',', 1);
    -- once per 24h only, so a standing problem does not spam (lesson from the smoke check)
    if not exists (select 1 from founder_alerts
                    where event='llm_drift' and created_at > now() - interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values ('warn','llm_drift','Model policy drift: '||v::text, 'system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values ('llm_drift', v_owner, 'admin', 'email', 'QuotesDone: AI model drift detected',
                'The model-policy watch found issues in the last 24h:'||chr(10)||chr(10)||
                jsonb_pretty(v)||chr(10)||chr(10)||
                'Check the AI Observability view (v_llm_model_mix / v_llm_offpolicy).', 'queued');
    end if;
  end if;

  return jsonb_build_object('checked_at', now(), 'calls_24h', v_recent,
                            'findings', jsonb_array_length(v), 'detail', v);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_ai()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k record; v_plan jsonb; v_health numeric; n_rec int; push jsonb; contentgaps jsonb; topcats text;
  s_cadence numeric; s_reach numeric; s_funnel numeric; s_pipeline numeric; v_meta_idle boolean; v_meta_has boolean;
begin
  select * into k from marketing_kpis;
  v_meta_has := exists(select 1 from meta_insights where campaign_name ilike '%quotesdone%');
  v_meta_idle := v_meta_has and (coalesce(k.meta_active_campaigns,0)=0 or coalesce(k.meta_spend_30d,0)=0);

  select coalesce(jsonb_agg(jsonb_build_object('category',category,'inquiries_90d',inquiries_90d,'suppliers',suppliers) order by inquiries_90d desc, suppliers asc),'[]'::jsonb)
    into push from (select * from marketing_category_demand where inquiries_90d>0 and suppliers=0 order by inquiries_90d desc, suppliers asc limit 8) t;
  select coalesce(jsonb_agg(jsonb_build_object('category',category,'has_seo',has_seo_page,'has_blog',has_blog) order by inquiries_90d desc),'[]'::jsonb)
    into contentgaps from (select * from marketing_category_demand where (not has_seo_page or not has_blog) order by inquiries_90d desc limit 8) t;
  select string_agg(category,', ') into topcats from (select category from marketing_category_demand where inquiries_90d>0 and suppliers=0 order by inquiries_90d desc limit 5) t;

  v_plan := jsonb_build_object(
    'as_of', now(),
    'push_supply', push,
    'content_gaps', contentgaps,
    'cadence', jsonb_build_object('blog_published',k.blog_published,'drafts_pending',k.drafts_pending,'social_staged',k.social_staged),
    'funnel', jsonb_build_object('inq_to_quote_pct',k.inq_to_quote_pct,'quote_to_reveal_pct',k.quote_to_reveal_pct,'revenue_30d',k.revenue_30d),
    'meta', jsonb_build_object('spend_30d',k.meta_spend_30d,'clicks_30d',k.meta_clicks_30d,'results_30d',k.meta_results_30d,'active_campaigns',k.meta_active_campaigns,'cpl',k.meta_cpl,'roi',k.meta_roi,'idle',v_meta_idle),
    'priorities', (
      select coalesce(jsonb_agg(p),'[]'::jsonb) from (
        select 'Launch & fund your paused QuotesDone Meta campaign to generate leads' as p where v_meta_idle
        union all select 'Onboard suppliers in: '||coalesce(topcats,'—') where k.supply_gaps>0
        union all select 'Review & publish '||k.drafts_pending||' pending content drafts' where k.drafts_pending>0
        union all select 'Stage social posts for this week' where coalesce(k.social_staged,0)=0
        union all select 'Generate SEO pages for '||k.seo_gaps||' uncovered categories' where k.seo_gaps>0
      ) x
    )
  );

  s_cadence := least(100, (case when k.blog_published>0 then 50 else 0 end) + (case when k.social_staged>0 then 30 else 0 end) + (case when k.drafts_pending between 1 and 10 then 20 when k.drafts_pending=0 then 10 else 5 end));
  s_reach := least(100, coalesce(k.seo_generated,0)*3);
  s_funnel := coalesce(k.quote_to_reveal_pct, 40);
  s_pipeline := least(100, (case when k.leads_total>1000 then 60 else k.leads_total/20.0 end) + least(40, k.outreach_sent));
  v_health := round(s_cadence*0.30 + s_reach*0.25 + s_funnel*0.25 + s_pipeline*0.20,1);

  insert into marketing_snapshots(snapshot_date, kpis, plan)
  values (current_date, to_jsonb(k) || jsonb_build_object('health',v_health), v_plan)
  on conflict (snapshot_date) do update set kpis=excluded.kpis, plan=excluded.plan, created_at=now();

  perform mkt_rec('supply_gap', coalesce(k.supply_gaps,0)>0, 'medium', 'Demand without supply',
    coalesce(k.supply_gaps,0)||' categor'||(case when k.supply_gaps=1 then 'y has' else 'ies have' end)||' customer demand but no approved suppliers'||(case when topcats is not null then ' ('||topcats||')' else '' end)||'. Prioritise supplier onboarding / BD there.');
  perform mkt_rec('drafts_backlog', coalesce(k.drafts_pending,0)>10, 'low', 'Content drafts awaiting review',
    k.drafts_pending||' content drafts are pending your review. Approve or publish to grow organic reach.');
  perform mkt_rec('no_social', coalesce(k.social_staged,0)=0, 'low', 'No social posts queued',
    'No social posts are staged. Queue this week''s posts to keep the channels active.');
  perform mkt_rec('seo_gap', coalesce(k.seo_gaps,0)>0, 'low', 'SEO coverage gaps',
    k.seo_gaps||' categories lack an SEO page. Generate them to capture search demand.');
  perform mkt_rec('meta_idle', v_meta_idle, 'medium', 'Meta ad campaign idle',
    'Your QuotesDone Meta campaign is paused / not spending. Launch and fund it to start generating leads — the platform will track spend, results, CPL and ROI automatically once a Meta access token is added.');

  select count(*) into n_rec from agent_actions where agent='marketing_ai' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'health',v_health,'kpis',to_jsonb(k),'plan',v_plan,'open_recommendations',n_rec);
end $function$


CREATE OR REPLACE FUNCTION public.fn_marketing_library_search(p_query text, p_limit integer DEFAULT 5)
 RETURNS TABLE(id bigint, category text, title text, content text, rank real)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare q_or tsquery; words text[];
begin
  words := array(
    select w from unnest(
      regexp_split_to_array(lower(regexp_replace(coalesce(p_query,''),'[^a-z0-9 ]',' ','g')), '\s+')
    ) w where length(w) > 2);
  if array_length(words,1) is null then return; end if;
  begin
    q_or := to_tsquery('english', array_to_string(words, ' | '));
  exception when others then return; end;
  return query
    select l.id, l.category, l.title, l.content, ts_rank(l.tsv, q_or) as rank
    from public.marketing_library l
    where l.tsv @@ q_or
    order by ts_rank(l.tsv, q_or) desc, l.id
    limit greatest(1, least(coalesce(p_limit,5), 20));
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_marketplace_analytics()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare res jsonb;
begin
  with q_first as (  -- first quote latency per rfq
    select i.id, min(qq.created_at) as first_quote_at, i.created_at, i.category
    from inquiries i left join quotes qq on qq.inquiry_id = i.id group by i.id, i.created_at, i.category
  ),
  spread as (  -- savings potential per rfq with >=2 quotes
    select inquiry_id, min(quote_amount) lo, max(quote_amount) hi, count(*) n
    from quotes where quote_amount > 0 group by inquiry_id having count(*) >= 2
  )
  select jsonb_build_object(
    'rfqs_today',   (select count(*) from inquiries where created_at >= date_trunc('day', now())),
    'rfqs_7d',      (select count(*) from inquiries where created_at >= now() - interval '7 days'),
    'rfqs_30d',     (select count(*) from inquiries where created_at >= now() - interval '30 days'),
    'avg_first_quote_hours', (select round(avg(extract(epoch from (first_quote_at - created_at))/3600.0)::numeric,1) from q_first where first_quote_at is not null),
    'response_rate_pct', (
      select case when count(*)>0 then round(100.0 * count(*) filter (where exists (
        select 1 from quotes q where q.inquiry_id = m.inquiry_id and q.supplier_id = m.supplier_id)) / count(*), 1) else null end
      from inquiry_matches m),
    'avg_savings_pct', (select round(avg(case when hi>0 then 100.0*(hi-lo)/hi else 0 end)::numeric,1) from spread),
    'abandoned_rfqs', (select count(*) from inquiries i where i.created_at < now() - interval '7 days'
                        and coalesce(i.status,'') not in ('completed','cancelled')
                        and not exists (select 1 from quotes q where q.inquiry_id = i.id)),
    'active_suppliers_30d', (select count(distinct supplier_id) from quotes where created_at >= now() - interval '30 days'),
    'supplier_capacity_avg', (select round(avg(c)::numeric,1) from (select supplier_id, count(*) c from quotes where created_at >= now() - interval '30 days' group by supplier_id) s),
    'competitive_categories', (
      select coalesce(jsonb_agg(x order by x.avg_quotes desc), '[]'::jsonb) from (
        select i.category, round(avg(qc.c)::numeric,2) as avg_quotes, count(*) as rfqs
        from inquiries i join (select inquiry_id, count(*) c from quotes group by inquiry_id) qc on qc.inquiry_id=i.id
        where i.created_at >= now() - interval '90 days' and i.category is not null
        group by i.category order by avg_quotes desc limit 8) x),
    'category_growth', (
      select coalesce(jsonb_agg(g), '[]'::jsonb) from (
        select category,
          count(*) filter (where created_at >= now() - interval '30 days') as this_30d,
          count(*) filter (where created_at >= now() - interval '60 days' and created_at < now() - interval '30 days') as prev_30d
        from inquiries where category is not null and created_at >= now() - interval '60 days'
        group by category order by this_30d desc limit 10) g),
    'generated_at', now()
  ) into res;
  return res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_match_capability(p_trades text[], p_need text DEFAULT 'executes'::text, p_products text[] DEFAULT '{}'::text[], p_brands text[] DEFAULT '{}'::text[], p_project_type text DEFAULT NULL::text, p_value numeric DEFAULT NULL::numeric, p_emirate text DEFAULT NULL::text, p_limit integer DEFAULT 12)
 RETURNS TABLE(supplier_id bigint, company_name text, score numeric, trades text[], roles text[], product_hits integer, brand_hit boolean, ptype_hit boolean, track numeric, why text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
with w as (
  select coalesce((select value::text::numeric from decision_policy where key='score_w_product'),40)      as w_prod,
         coalesce((select value::text::numeric from decision_policy where key='score_w_brand'),20)        as w_brand,
         coalesce((select value::text::numeric from decision_policy where key='score_w_project_type'),15) as w_ptype,
         coalesce((select value::text::numeric from decision_policy where key='score_w_track_record'),15) as w_track,
         coalesce((select value::text::numeric from decision_policy where key='score_w_size_fit'),10)     as w_size
),
req_auth as (   -- authorities legally mandated by the requested trades
  select coalesce(array_agg(distinct a),'{}') as codes
  from public.taxonomy_trade t, unnest(t.authority_required) a
  where t.code = any(p_trades)
),
cand as (
  select sc.supplier_id, sc.trades, sc.roles, sc.products_norm, sc.brands, sc.project_types,
         sc.min_project_value, sc.max_project_value,
         l.company_name,
         least(1, greatest(0, coalesce(sp.quote_rate, sp.perf_score, 0))) as track
  from public.supplier_capabilities sc
  join public.leads l on l.id = sc.supplier_id
  left join public.supplier_perf sp on sp.supplier_id = sc.supplier_id
  where sc.confirmed_at is not null                        -- GATE: supplier confirmed their own scope
    and sc.trades && p_trades                              -- GATE: trade intersection
    and not (sc.excluded_trades && p_trades)               -- GATE: declared negative scope
    and coalesce(l.banned,false) = false                   -- GATE: not banned
    and coalesce(l.matching_blocked,false) = false         -- GATE: docs valid / not suspended
    and coalesce(l.approval_status,'') = 'approved'        -- GATE: approved
    and exists (                                            -- GATE: role can actually do this kind of work
      select 1 from public.taxonomy_role r
      where r.code = any(sc.roles)
        and case p_need when 'supplies'    then r.supplies
                        when 'whole_scope' then r.whole_scope
                        else r.executes end
    )
    and not exists (                                        -- GATE: every mandatory authority held
      select 1 from unnest((select codes from req_auth)) a
      where not (sc.authority_approvals ? a)
    )
    and (p_value is null or (                               -- GATE: job size inside their range
          (sc.min_project_value is null or p_value >= sc.min_project_value)
      and (sc.max_project_value is null or p_value <= sc.max_project_value)))
),
scored as (
  select c.*,
    (select count(distinct pq) from unnest(p_products) pq
      where exists (select 1 from unnest(c.products_norm) pp
                    where pp ilike '%'||pq||'%' or pq ilike '%'||pp||'%'))::int as product_hits,
    (cardinality(p_brands) > 0 and exists (
       select 1 from unnest(p_brands) bq join unnest(c.brands) bb on bb ilike '%'||bq||'%' or bq ilike '%'||bb||'%'
     )) as brand_hit,
    (p_project_type is not null and exists (
       select 1 from unnest(c.project_types) pt
       where pt ilike '%'||p_project_type||'%' or p_project_type ilike '%'||pt||'%'
     )) as ptype_hit,
    (p_value is not null and c.min_project_value is not null and c.max_project_value is not null) as size_known
  from cand c
)
select s.supplier_id, s.company_name,
  round(
      w.w_prod  * (case when cardinality(p_products) > 0
                        then s.product_hits::numeric / cardinality(p_products) else 0 end)
    + w.w_brand * (case when s.brand_hit then 1 else 0 end)
    + w.w_ptype * (case when s.ptype_hit then 1 else 0 end)
    + w.w_track * s.track
    + w.w_size  * (case when s.size_known then 1 else 0.5 end)   -- unknown range is neutral, not punished
  , 1) as score,
  s.trades, s.roles, s.product_hits, s.brand_hit, s.ptype_hit, round(s.track,3) as track,
  concat_ws(' · ',
    'trades ' || array_to_string(array(select unnest(s.trades) intersect select unnest(p_trades)), '+'),
    case when s.product_hits > 0 then s.product_hits||'/'||cardinality(p_products)||' products' end,
    case when s.brand_hit then 'brand match' end,
    case when s.ptype_hit then 'project type' end
  ) as why
from scored s, w
order by score desc, s.track desc, s.supplier_id
limit greatest(1, p_limit);

$function$


CREATE OR REPLACE FUNCTION public.fn_memory_search(p_q text, p_kinds text[] DEFAULT NULL::text[], p_lim integer DEFAULT 20)
 RETURNS TABLE(kind text, ref text, snippet text, ts timestamp with time zone, score real)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with qy as (select plainto_tsquery('english', coalesce(p_q,'')) q)
  select s.kind, s.ref, s.snippet, s.ts, s.score from (
    select 'rfq'::text kind, i.id::text ref, left(coalesce(i.summary, i.raw_input, i.spec::text),220) snippet,
           i.created_at ts, ts_rank(to_tsvector('english', coalesce(i.summary,'')||' '||coalesce(i.raw_input,'')||' '||coalesce(i.spec::text,'')||' '||coalesce(i.category,'')), qy.q) score
    from inquiries i, qy where (p_kinds is null or 'rfq'=any(p_kinds))
      and to_tsvector('english', coalesce(i.summary,'')||' '||coalesce(i.raw_input,'')||' '||coalesce(i.spec::text,'')||' '||coalesce(i.category,'')) @@ qy.q
    union all
    select 'quote', q.id::text, left(coalesce(q.scope, q.notes),220), q.created_at,
           ts_rank(to_tsvector('english', coalesce(q.scope,'')||' '||coalesce(q.notes,'')||' '||coalesce(q.conditions,'')), qy.q)
    from quotes q, qy where (p_kinds is null or 'quote'=any(p_kinds))
      and to_tsvector('english', coalesce(q.scope,'')||' '||coalesce(q.notes,'')||' '||coalesce(q.conditions,'')) @@ qy.q
    union all
    select 'supplier', l.id::text, left(coalesce(l.company_name,'')||' — '||coalesce(l.capability_summary, l.description, l.services),220), l.created_at,
           ts_rank(to_tsvector('english', coalesce(l.company_name,'')||' '||coalesce(l.capability_summary,'')||' '||coalesce(l.services,'')||' '||coalesce(l.description,'')||' '||coalesce(l.categories,'')), qy.q)
    from leads l, qy where (p_kinds is null or 'supplier'=any(p_kinds))
      and to_tsvector('english', coalesce(l.company_name,'')||' '||coalesce(l.capability_summary,'')||' '||coalesce(l.services,'')||' '||coalesce(l.description,'')||' '||coalesce(l.categories,'')) @@ qy.q
    union all
    select 'customer', c.id::text, left(coalesce(c.full_name,'')||' '||coalesce(c.email,''),220), c.created_at,
           ts_rank(to_tsvector('english', coalesce(c.full_name,'')||' '||coalesce(c.email,'')), qy.q)
    from customers c, qy where (p_kinds is null or 'customer'=any(p_kinds))
      and to_tsvector('english', coalesce(c.full_name,'')||' '||coalesce(c.email,'')) @@ qy.q
    union all
    select 'case', a.rfq_id, left(coalesce(a.ai_summary->>'summary',''),220), a.created_at,
           ts_rank(to_tsvector('english', coalesce(a.ai_summary->>'summary','')||' '||coalesce(a.category,'')), qy.q)
    from rfq_archives a, qy where (p_kinds is null or 'case'=any(p_kinds))
      and to_tsvector('english', coalesce(a.ai_summary->>'summary','')||' '||coalesce(a.category,'')) @@ qy.q
    union all
    select 'knowledge', k.agent_key||' :: '||k.topic, left(k.content,220), k.created_at,
           ts_rank(to_tsvector('english', coalesce(k.topic,'')||' '||coalesce(k.content,'')), qy.q)
    from agent_knowledge k, qy where (p_kinds is null or 'knowledge'=any(p_kinds))
      and to_tsvector('english', coalesce(k.topic,'')||' '||coalesce(k.content,'')) @@ qy.q
    union all
    select 'decision', dl.id::text, left(dl.kind||' -> '||coalesce(dl.decision,'')||' '||coalesce(dl.reasons::text,''),220), dl.created_at,
           ts_rank(to_tsvector('english', coalesce(dl.kind,'')||' '||coalesce(dl.decision,'')||' '||coalesce(dl.reasons::text,'')), qy.q)
    from decision_log dl, qy where (p_kinds is null or 'decision'=any(p_kinds))
      and to_tsvector('english', coalesce(dl.kind,'')||' '||coalesce(dl.decision,'')||' '||coalesce(dl.reasons::text,'')) @@ qy.q
  ) s
  order by s.score desc, s.ts desc
  limit greatest(1, coalesce(p_lim,20));
$function$


CREATE OR REPLACE FUNCTION public.fn_monthly_report()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_period_report('monthly'); $function$


CREATE OR REPLACE FUNCTION public.fn_norm_roles(p_text text)
 RETURNS text[]
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(array_agg(distinct r.code order by r.code), '{}')
  from public.taxonomy_role r
  where r.active
    and exists (
      select 1 from unnest(r.aliases || r.code) a
      where length(a) >= 3
        and coalesce(p_text,'') ~* ('\m' || regexp_replace(a, '([.*+?^${}()|\[\]\\])', '\\\1', 'g'))
    );
$function$


CREATE OR REPLACE FUNCTION public.fn_norm_trades(p_text text)
 RETURNS text[]
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(array_agg(distinct t.code order by t.code), '{}')
  from public.taxonomy_trade t
  where t.active
    and exists (
      select 1 from unnest(t.aliases || t.code) a
      where length(a) >= 3
        and coalesce(p_text,'') ~* ('\m' || regexp_replace(a, '([.*+?^${}()|\[\]\\])', '\\\1', 'g'))
    );
$function$


CREATE OR REPLACE FUNCTION public.fn_normalize_founder_alert_level()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF lower(coalesce(NEW.level,'')) = 'crit' THEN NEW.level := 'critical'; END IF;
  RETURN NEW;
END
$function$


CREATE OR REPLACE FUNCTION public.fn_notifications_digest()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare types jsonb;
begin
  if coalesce(NEW.channel,'email') <> 'email' then return NEW; end if;
  if NEW.status is not null and NEW.status not in ('queued','pending') then return NEW; end if;
  if coalesce(NEW.to_role,'') not in ('admin','founder','owner') then return NEW; end if;
  -- HARD EXCLUSIONS: these always send immediately regardless of policy.
  if coalesce(NEW.type,'') ~* 'money|refund|security|legal|fraud|critical|founder_alert|chief_of_staff|founder_brief|verify|otp|reset|password' then return NEW; end if;
  if coalesce(NEW.subject,'') ~* 'critical|urgent|fraud|breach|\mdown\M|failed|failure' then return NEW; end if;
  -- POLICY allowlist of routine types to fold into the brief.
  select value into types from public.decision_policy where key='alert_digest_types';
  if types is not null and types ? coalesce(NEW.type,'') then
    NEW.status := 'digest';
  end if;
  return NEW;
exception when others then
  return NEW;  -- a classifier error must never block a notification insert
end $function$


CREATE OR REPLACE FUNCTION public.fn_notify_matched_supplier()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_email text; v_cat text; v_em text;
begin
  select email into v_email from leads where id=NEW.supplier_id;
  select category, emirate into v_cat, v_em from inquiries where id=NEW.inquiry_id;
  if v_email is not null and position('@' in v_email) > 1 then
    insert into notifications(type,to_email,to_role,lead_id,inquiry_id,subject,body,channel,status)
    values('new_inquiry', v_email, 'supplier', NEW.supplier_id, NEW.inquiry_id,
      'New job request on QuotesDone',
      'A customer is requesting quotes for: '||coalesce(v_cat,'a project')||coalesce(' ('||v_em||')','')||
      '. Log in to your QuotesDone supplier portal to view the brief and submit your quote.',
      'email','queued');
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_notify_supplier(p_transaction uuid, p_actor text DEFAULT 'customer'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t record; st jsonb; sup record; cust_email text; v_admin text; v_subject text; v_body text;
        v_call_days int; v_claim_days int; v_new_deadline timestamptz;
begin
  st := public.fn_refund_state(p_transaction);
  if st ? 'error' then return st; end if;
  if (st->>'can_notify') <> 'true' then
    return jsonb_build_object('ok', false, 'error', 'not_available', 'state', st->>'state',
                              'notify_available_at', st->>'notify_available_at');
  end if;

  select * into t from transactions where id = p_transaction;
  select company_name, coalesce(claimed_by, email) as email into sup from leads where id = t.supplier_id;
  select email into cust_email from customers where id = t.customer_id;
  v_admin := coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),
                      'management@quotesdone.com');

  v_call_days  := coalesce((select value::text::int from decision_policy where key='refund_call_after_working_days'), 3);
  v_claim_days := coalesce((select value::text::int from decision_policy where key='refund_claim_after_call_working_days'), 3);

  v_subject := 'Awaiting your response — QuotesDone reveal #' || left(t.id::text, 8);
  v_body :=
    'Hello,' || chr(10) || chr(10) ||
    'A customer paid to reveal your contact details on QuotesDone on ' ||
      to_char(t.revealed_at at time zone 'Asia/Dubai','DD Mon YYYY') ||
      ' and has not yet heard from you.' || chr(10) || chr(10) ||
    'Everyone is copied on this email so you can simply reply to all and pick it up here.' || chr(10) || chr(10) ||
    'If we have not heard from you within ' || v_call_days::text ||
      ' working days, we will call you. If we still cannot reach you and the customer is refunded, the reveal fee is recovered from your account under the supplier terms.' || chr(10) || chr(10) ||
    'If you have already been in touch with this customer, reply here and we will close this off.' || chr(10) || chr(10) ||
    'QuotesDone';

  insert into notifications(type, to_email, cc_emails, to_role, lead_id, inquiry_id, channel, subject, body, status)
  values ('reveal_no_response_notice', sup.email,
          array_remove(array[cust_email, v_admin], null),
          'supplier', t.supplier_id, t.inquiry_id, 'email', v_subject, v_body, 'queued');

  -- Deadline must outlive the ladder the customer is being asked to follow.
  v_new_deadline := public.fn_add_working_days(
                      public.fn_add_working_days(now(), v_call_days), v_claim_days);

  update transactions
     set customer_notified_at = now(),
         refund_deadline = greatest(coalesce(refund_deadline, now()), v_new_deadline)
   where id = p_transaction;

  insert into agent_actions(agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('customer_success','supplier_unresponsive','needs_review','high',
          'Supplier not responding after a paid reveal: ' || coalesce(sup.company_name,'#'||t.supplier_id),
          'Customer has formally notified them. Call the supplier after the working-day window; a refund may only be approved once that has elapsed.',
          jsonb_build_object('transaction_id', t.id, 'supplier_id', t.supplier_id,
                             'inquiry_id', t.inquiry_id, 'notified_at', now(),
                             'call_due_at', public.fn_add_working_days(now(), v_call_days),
                             'refund_claim_until', v_new_deadline),
          'transactions', t.id::text);

  return jsonb_build_object('ok', true, 'notified_at', now(),
                            'recipients', jsonb_build_array(sup.email, cust_email, v_admin),
                            'refund_claim_until', v_new_deadline,
                            'state', public.fn_refund_state(p_transaction));
end $function$


CREATE OR REPLACE FUNCTION public.fn_officer_recs(n integer DEFAULT 8)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select string_agg(line, E'\n') from (
    select '- ['||er.officer||'] '||left(coalesce(rec->>'action',''),150) as line
    from (select distinct on (officer) officer, recommendations from exec_reports order by officer, created_at desc) er,
         lateral jsonb_array_elements(er.recommendations) rec
    where coalesce(rec->>'action','')<>''
    limit n) z;
$function$


CREATE OR REPLACE FUNCTION public.fn_onboarding_gate(p_agent text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    (select jsonb_build_object('agent',agent_key,'status',status,
       'outputs_need_review', status <> 'certified',
       'reason', case status
         when 'certified' then 'fully onboarded'
         when 'probation' then 'passed exams; first '||probation_reviews_required||' outputs need founder/lead review ('||probation_reviews_done||' done)'
         when 'recert_due' then 'certification expired; re-examination pending'
         else 'not yet examined on the four knowledge layers' end)
     from org_onboarding where agent_key=p_agent),
    jsonb_build_object('agent',p_agent,'status','unknown','outputs_need_review',true,
      'reason','no onboarding record - treat as uncertified'));
$function$


CREATE OR REPLACE FUNCTION public.fn_onboarding_ingest_runs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_updated int := 0;
begin
  for r in select agent, score_pct, run_at from canon_eval_runs where run_at > now() - interval '8 days' loop
    insert into org_onboarding(agent_key, department)
      values (r.agent, (select department from org_agents where agent_key=r.agent))
      on conflict (agent_key) do nothing;
    update org_onboarding set l1_score=r.score_pct, l1_at=r.run_at, updated_at=now()
      where agent_key=r.agent and (l1_at is null or l1_at < r.run_at);
    v_updated := v_updated + 1;
  end loop;
  update org_onboarding o set status='probation', updated_at=now()
    where o.status in ('onboarding','recert_due')
      and o.l1_score >= o.pass_threshold and o.l2_score >= o.pass_threshold;
  update org_onboarding o set status='certified', certified_at=now(),
      recert_due=(now()+interval '90 days')::date, updated_at=now()
    where o.status='probation' and o.probation_reviews_done >= o.probation_reviews_required;
  update org_onboarding o set status='recert_due', updated_at=now()
    where o.status='certified' and o.recert_due is not null and o.recert_due < current_date;
  return jsonb_build_object('runs_ingested', v_updated);
end $function$


CREATE OR REPLACE FUNCTION public.fn_operations_ai()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k record; v_health numeric; n int;
begin
  select * into k from ops_kpis;
  v_health := round(greatest(0, 100
    - least(30, coalesce(k.no_quote_backlog,0)*3)
    - (case when coalesce(k.avg_first_quote_hours,0) > 72 then 20 when coalesce(k.avg_first_quote_hours,0) > 48 then 10 else 0 end)
    - (case when coalesce(k.response_rate_pct,100) < 40 then 15 when coalesce(k.response_rate_pct,100) < 60 then 7 else 0 end)
    - least(15, coalesce(k.overdue_tasks,0)*3)
    - coalesce(k.cron_failures_24h,0)*4
    - least(10, coalesce(k.agent_errors_24h,0)*2)
    - (case when coalesce(k.high_risk_pending,0) > 5 then 8 else 0 end)),1);

  insert into ops_kpi_snapshots(snapshot_date,kpis) values (current_date, to_jsonb(k)||jsonb_build_object('ops_health',v_health))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  perform ops_rec('no_quote_backlog', coalesce(k.no_quote_backlog,0) > 0, 'medium', 'Inquiries stuck without quotes',
    k.no_quote_backlog||' inquir(y/ies) older than 7 days have no quotes — a supply/response bottleneck. Chase matched suppliers or onboard supply in those categories.');
  perform ops_rec('slow_first_quote', coalesce(k.avg_first_quote_hours,0) > 48, 'medium', 'First quotes are slow',
    'First quotes are averaging '||coalesce(k.avg_first_quote_hours,0)||' hours. Tighten supplier response SLAs / nudges to speed the funnel.');
  perform ops_rec('low_response_rate', coalesce(k.response_rate_pct,100) < 60, 'medium', 'Supplier response rate is low',
    'Supplier response rate is '||coalesce(k.response_rate_pct,0)||'%. Improve matching quality and supplier enablement.');
  perform ops_rec('approvals_backlog', coalesce(k.pending_approvals,0) > 15, 'low', 'Approval queue building up',
    k.pending_approvals||' items are awaiting your decision ('||coalesce(k.high_risk_pending,0)||' high-risk). Clear the queue so the agents can proceed.');
  perform ops_rec('overdue_tasks', coalesce(k.overdue_tasks,0) > 0, 'low', 'Overdue tasks',
    k.overdue_tasks||' task(s) are past due. Reschedule or action them.');
  perform ops_rec('automation_failures', coalesce(k.cron_failures_24h,0) > 0 or coalesce(k.agent_errors_24h,0) > 5, 'high', 'Automation failures detected',
    coalesce(k.cron_failures_24h,0)||' scheduled-job failure(s) and '||coalesce(k.agent_errors_24h,0)||' agent error(s) in 24h. Investigate the failing jobs.');

  select count(*) into n from agent_actions where agent='operations_ai' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'ops_health',v_health,'kpis',to_jsonb(k),'open_recommendations',n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_ops_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  active_rfqs int; rfqs_today int; done_today int; ttfq numeric; qpr numeric;
  accept_rate numeric; conv numeric;
  rev_today numeric; rev_month numeric; pending_fees numeric; outstanding_inv int; cash_recv numeric;
  ai_conf numeric; waiting int; onboard_q int; disputes int; escalations int;
  uptime numeric; queue_size int; failed int; last_backup timestamptz; api_lat numeric;
  health jsonb;
begin
  -- MARKETPLACE
  select count(*) into active_rfqs from inquiries where status not in ('completed','accepted','closed','cancelled');
  select count(*) into rfqs_today from inquiries where created_at::date=current_date;
  select count(*) into done_today from inquiries where (completed_at::date=current_date) or (status in ('completed','accepted') and stage_changed_at::date=current_date);
  select round(avg(extract(epoch from (fq - ic))/3600.0),1) into ttfq from (
    select i.created_at ic, min(q.created_at) fq from inquiries i join quotes q on q.inquiry_id=i.id
    where i.created_at>=now()-interval '30 days' group by i.id) z where fq is not null;
  select round(avg(qc),1) into qpr from (select count(*) qc from quotes q join inquiries i on i.id=q.inquiry_id where i.created_at>=now()-interval '30 days' group by q.inquiry_id) z;
  select round(avg(nullif(rv_response_rate,0)) ,1) into accept_rate from leads where coalesce(rv_reveals,0)>0;
  select round(100.0*count(distinct t.inquiry_id)/nullif(count(distinct i.id),0),1) into conv
    from inquiries i left join transactions t on t.inquiry_id=i.id where i.created_at>=now()-interval '30 days';

  -- REVENUE
  select coalesce(sum(reveal_fee),0) into rev_today from transactions where revealed_at::date=current_date and coalesce(refund_status,'')<>'approved';
  select coalesce(sum(reveal_fee),0) into rev_month from transactions where date_trunc('month',revealed_at)=date_trunc('month',now()) and coalesce(refund_status,'')<>'approved';
  begin select coalesce(sum(amount_due),0) into pending_fees from supplier_dues where coalesce(status,'')<>'paid'; exception when others then pending_fees:=0; end;
  begin select count(*) into outstanding_inv from reveal_invoices ri left join transactions t on t.id=ri.transaction_id where coalesce(t.fee_status,'')<>'paid'; exception when others then outstanding_inv:=0; end;
  select coalesce(sum(reveal_fee),0) into cash_recv from transactions where coalesce(fee_status,'')='paid';

  -- OPERATIONS
  begin select public.fn_health_index() into health; exception when others then health:=null; end;
  select round(100.0*count(*) filter (where nullif(quality->>'score','')::numeric>=60)/nullif(count(*) filter (where quality is not null),0),1) into ai_conf
    from quotes where created_at>=now()-interval '7 days';
  select count(*) into waiting from inquiries where status in ('clarify','clarifying','awaiting_customer','needs_info');
  select count(*) into onboard_q from leads where approval_status='pending';
  select count(*) into disputes from transactions where refund_status='requested';
  select (select count(*) from agent_actions where status='pending')
        + (select count(*) from founder_alerts where level='critical' and created_at>=now()-interval '24 hours') into escalations;

  -- INFRASTRUCTURE
  select round(100.0*count(*) filter (where ok)/nullif(count(*),0),1) into uptime from health_checks where created_at>=now()-interval '24 hours';
  select count(*) into queue_size from notifications where coalesce(status,'')in('queued','pending','');
  begin select count(*) into failed from agent_runs where status='error' and coalesce(finished_at,started_at)>=now()-interval '24 hours'; exception when others then failed:=0; end;
  select max(updated_at) into last_backup from storage.objects where bucket_id='backups' and name like '%/_manifest.json';
  select round(avg(latency_ms),0) into api_lat from health_checks where created_at>=now()-interval '1 hour' and latency_ms is not null;

  return jsonb_build_object(
    'as_of', now(),
    'marketplace', jsonb_build_object('active_rfqs',active_rfqs,'rfqs_today',rfqs_today,'completed_today',done_today,
        'avg_hours_to_first_quote',ttfq,'avg_quotes_per_rfq',qpr,'supplier_acceptance_pct',accept_rate,'conversion_pct',conv),
    'revenue', jsonb_build_object('today_aed',rev_today,'month_aed',rev_month,'pending_fees_aed',pending_fees,
        'outstanding_invoices',outstanding_inv,'cash_received_aed',cash_recv),
    'operations', jsonb_build_object('ai_confidence_pct',ai_conf,'rfqs_waiting_clarification',waiting,
        'onboarding_queue',onboard_q,'disputes',disputes,'escalations',escalations),
    'infrastructure', jsonb_build_object('uptime_pct',uptime,'queue_size',queue_size,'failed_jobs_24h',failed,
        'backup_age_hours', case when last_backup is null then null else round(extract(epoch from (now()-last_backup))/3600.0,1) end,
        'api_latency_ms',api_lat),
    'health_index', coalesce(health->>'index',null));
end $function$


CREATE OR REPLACE FUNCTION public.fn_ops_metrics()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare res jsonb;
begin
  select jsonb_build_object(
    'open_rfqs_no_quotes_7d', (select count(*) from inquiries i where i.created_at < now()-interval '7 days'
        and coalesce(i.status,'') not in ('completed','cancelled','closed')
        and not exists (select 1 from quotes q where q.inquiry_id=i.id)),
    'matched_not_quoted', (select count(*) from inquiry_matches m
        where not exists (select 1 from quotes q where q.inquiry_id=m.inquiry_id and q.supplier_id=m.supplier_id)),
    'avg_first_quote_hours', (select (fn_marketplace_analytics()->>'avg_first_quote_hours')::numeric),
    'response_rate_pct', (select (fn_marketplace_analytics()->>'response_rate_pct')::numeric),
    'pipeline_by_stage', (select coalesce(jsonb_agg(jsonb_build_object('stage',label,'deals',deals,'value',value) order by sort_order),'[]'::jsonb) from crm_pipeline_report),
    'overdue_activities', (select overdue_activities from crm_deal_kpis)
  ) into res;
  return res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ops_watch()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_run bigint; v_ai_1h int; v_ai_24h int; v_top_email text; v_top_cnt int; v_err6h int; v_runerr6h int; v_spammer record; v_owner text; v_alerts int:=0;
  function_alerted boolean;
  v_wd_last timestamptz; v_wd_seen timestamptz;
begin
  insert into agent_runs(agent,started_at) values('ops_watch',clock_timestamp()) returning id into v_run;
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';
  select count(*) into v_ai_1h from ai_usage where created_at>=now()-interval '1 hour';
  select count(*) into v_ai_24h from ai_usage where created_at>=now()-interval '24 hours';
  select email,count(*) into v_top_email,v_top_cnt from ai_usage where created_at>=now()-interval '24 hours' group by email order by count(*) desc limit 1;
  select count(*) into v_err6h from error_events where created_at>=now()-interval '6 hours' and severity in ('error','high','critical');
  select count(*) into v_runerr6h from agent_runs where status='error' and started_at>=now()-interval '6 hours';

  if (v_ai_1h > coalesce((select value::int from app_secrets where key='ai_cost_alert_hourly'),300))
     or (v_ai_24h > coalesce((select value::int from app_secrets where key='ai_cost_alert_daily'),2500)) then
    insert into error_events(source,kind,severity,detail) values('ops_watch','ai_cost_spike','high',jsonb_build_object('last_hour',v_ai_1h,'last_24h',v_ai_24h,'top_email',v_top_email,'top_count',v_top_cnt));
    select exists(select 1 from notifications where type='ops_alert' and subject like 'QuotesDone: AI usage spike%' and created_at>=now()-interval '6 hours') into function_alerted;
    if v_owner is not null and not function_alerted then
      insert into notifications(type,to_email,to_role,channel,subject,body) values('ops_alert',v_owner,'admin','email','QuotesDone: AI usage spike',
        'AI calls in last hour: '||v_ai_1h||', last 24h: '||v_ai_24h||'. Heaviest user: '||coalesce(v_top_email,'?')||' ('||coalesce(v_top_cnt,0)||'). Check for abuse or runaway cost. You can set ai_kill_switch=true to pause AI.');
      v_alerts:=v_alerts+1;
    end if;
  end if;

  if v_err6h > 20 or v_runerr6h > 10 then
    select exists(select 1 from notifications where type='ops_alert' and subject like 'QuotesDone: error spike%' and created_at>=now()-interval '6 hours') into function_alerted;
    if v_owner is not null and not function_alerted then
      insert into notifications(type,to_email,to_role,channel,subject,body) values('ops_alert',v_owner,'admin','email','QuotesDone: error spike',
        'Errors in last 6h: '||v_err6h||' app errors, '||v_runerr6h||' failed agent runs. Open the IT agent to investigate.');
      v_alerts:=v_alerts+1;
    end if;
  end if;

  for v_spammer in select customer_id, count(*) c from inquiries where created_at>=now()-interval '24 hours' group by customer_id having count(*)>40 loop
    insert into error_events(source,kind,severity,detail) values('ops_watch','inquiry_spam','medium',jsonb_build_object('customer_id',v_spammer.customer_id,'count',v_spammer.c));
    v_alerts:=v_alerts+1;
  end loop;

  select max(started_at) into v_wd_last from agent_runs
    where agent='agent_silence_watch' and status='ok' and started_at >= now()-interval '48 hours';
  select first_seen into v_wd_seen from cron_job_seen where jobname='agent_silence_watch_daily';

  if v_wd_last is null and v_wd_seen is not null and v_wd_seen < now()-interval '48 hours' then
    insert into error_events(source,kind,severity,detail)
      values('ops_watch','watchdog_silent','critical',
             jsonb_build_object('agent','agent_silence_watch','registered_since',v_wd_seen,
                                'note','no successful run in 48h - cron failures are going unobserved'));
    select exists(select 1 from notifications where type='ops_alert' and subject like 'QuotesDone: cron watchdog is down%' and created_at>=now()-interval '6 hours') into function_alerted;
    if v_owner is not null and not function_alerted then
      insert into notifications(type,to_email,to_role,channel,subject,body) values('ops_alert',v_owner,'admin','email','QuotesDone: cron watchdog is down',
        'agent_silence_watch has not completed successfully in 48 hours. While it is down, failing or stalled scheduled jobs will not raise alerts. Check that the agent_silence_watch_daily cron job is registered and running.');
      v_alerts:=v_alerts+1;
    end if;
  end if;

  update agent_runs set finished_at=clock_timestamp(),status='ok',counts=jsonb_build_object('ai_1h',v_ai_1h,'ai_24h',v_ai_24h,'err6h',v_err6h,'run_err6h',v_runerr6h,'alerts',v_alerts,'watchdog_ok',(v_wd_last is not null)) where id=v_run;
end; $function$


CREATE OR REPLACE FUNCTION public.fn_org_exec_invite(p_cap integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_enabled boolean; v_cap int; v_sent int;
begin
  v_enabled := coalesce((select value from app_secrets where key='invite_enabled'),'false')='true';
  v_cap := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), 10);
  select public.enqueue_supplier_invites(p_cap) into v_sent;
  return jsonb_build_object(
    'invited', coalesce(v_sent,0),
    'campaign_enabled', v_enabled,
    'daily_cap', v_cap,
    'note', case when not v_enabled then 'Invite campaign is not enabled yet — 0 sent. It starts on its scheduled date; the deliverability-gated ramp will then send within the daily cap.'
                 else 'Enqueued '||coalesce(v_sent,0)||' invite(s) this run, within the daily cap of '||v_cap||' and bounce-rate guard.' end
  );
end $function$


CREATE OR REPLACE FUNCTION public.fn_org_exec_knowledge_fill(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_gaps int; v_req bigint; v_recon jsonb;
begin
  -- self-heal the taxonomy every run (fast, synchronous)
  v_recon := public.fn_kb_reconcile();
  -- how many service categories still have zero knowledge chunks
  select count(*) into v_gaps from public.category_specs s
    where not exists (select 1 from public.kb_chunks k where k.category = s.category);
  -- trigger the (slow) generator in the background
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/kb_autofill_gaps',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from public.app_secrets where key='inbound_secret'),'limit',greatest(1,least(coalesce(p_limit,5),5))),
    timeout_milliseconds:=280000
  ) into v_req;
  return jsonb_build_object('empty_categories', v_gaps, 'autofill_triggered', true, 'reconcile', v_recon,
    'note', case when v_gaps=0 then 'Knowledge base complete: 0 empty categories. Taxonomy reconciled ('||coalesce(v_recon->>'cat_prefix_stripped','0')||' prefixes stripped, '||coalesce(v_recon->>'alias_remapped','0')||' aliased).'
                 else 'Triggered background gap-fill for '||v_gaps||' empty category(ies); taxonomy reconciled. Generation runs in the background and logs to agent_runs.' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_org_export()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
select jsonb_build_object(
 'exported_at', now(),
 'org_departments', (select jsonb_agg(to_jsonb(t) order by t.sort) from org_departments t),
 'org_agents', (select jsonb_agg(to_jsonb(t) order by t.agent_key) from org_agents t),
 'org_authority', (select jsonb_agg(to_jsonb(t) order by t.dept_key, t.action_class) from org_authority t),
 'org_onboarding', (select jsonb_agg(to_jsonb(t) order by t.agent_key) from org_onboarding t),
 'decision_policy', (select jsonb_agg(to_jsonb(t) order by t.key) from decision_policy t),
 'policy_rules', (select jsonb_agg(to_jsonb(t) order by t.id) from policy_rules t),
 'canon_eval_questions', (select jsonb_agg(to_jsonb(t) order by t.id) from canon_eval_questions t),
 'agent_knowledge', (select jsonb_agg(jsonb_build_object('agent_key',agent_key,'topic',topic,'layer',layer,'priority',priority,'content',content) order by agent_key, priority desc, topic) from agent_knowledge t),
 'company_vision', (select jsonb_agg(to_jsonb(t)) from company_vision t),
 'ai_constitution', (select jsonb_agg(to_jsonb(t)) from ai_constitution t where active),
 'migrations', (select jsonb_agg(jsonb_build_object('version',version,'name',name) order by version) from supabase_migrations.schema_migrations)
)
$function$


CREATE OR REPLACE FUNCTION public.fn_org_scorecard()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select coalesce(jsonb_agg(row_to_json(x) order by x.sort),'[]'::jsonb) from (
    select d.dept_key, d.name, d.north_star, d.lead_agent, d.sort,
      (select count(*) from public.org_tasks t where t.dept_key=d.dept_key and t.status in ('proposed','assigned','in_progress','blocked')) as open_tasks,
      (select count(*) from public.org_tasks t where t.dept_key=d.dept_key and (t.needs_founder or t.status='escalated') and t.status not in ('done','failed')) as escalations,
      (select count(*) from public.agent_actions a where a.status in ('pending','needs_review','open') and (
          (d.dept_key='finance' and a.kind ~* 'finance|refund|dues') or
          (d.dept_key='legal' and a.kind ~* 'legal|compliance') or
          (d.dept_key='supplier_success' and a.kind ~* 'supplier|approve|licence|kyc') or
          (d.dept_key='customer_success' and a.kind ~* 'customer|refund|escalation') or
          (d.dept_key='it' and a.kind ~* 'incident|security') or
          (d.dept_key='marketing' and a.kind ~* 'market|content') or
          (d.dept_key='knowledge' and a.kind ~* 'knowledge|coverage')
        )) as dept_queue
    from public.org_departments d where d.active
  ) x;
$function$


CREATE OR REPLACE FUNCTION public.fn_os_command()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_health jsonb; v_ops jsonb; v_counts jsonb; v_attention jsonb; v_pipeline jsonb;
begin
  v_health := to_jsonb(fn_health_index());
  v_ops    := to_jsonb(fn_ops_dashboard());

  select jsonb_build_object(
    'suppliers_total', (select count(*) from leads),
    'rfqs_total',      (select count(*) from inquiries),
    'rfqs_active',     (select count(*) from inquiries where status = 'quoted'),
    'rfqs_revealed',   (select count(*) from inquiries where status = 'revealed'),
    'rfqs_cancelled',  (select count(*) from inquiries where status = 'cancelled'),
    'quotes_total',    (select count(*) from quotes),
    'decisions_7d',    (select count(*) from decision_log where created_at > now() - interval '7 days'),
    'decisions_24h',   (select count(*) from decision_log where created_at > now() - interval '24 hours')
  ) into v_counts;

  select jsonb_build_object(
    'sent',      (select count(*) from inquiries where status = 'sent' and parent_inquiry_id is null),
    'matched',   (select count(distinct im.inquiry_id) from inquiry_matches im join inquiries i on i.id = im.inquiry_id where i.status = 'sent'),
    'quoted',    (select count(*) from inquiries where status = 'quoted'),
    'revealed',  (select count(*) from inquiries where status = 'revealed'),
    'completed', (select count(*) from inquiries where status in ('completed','won'))
  ) into v_pipeline;

  select coalesce(jsonb_agg(x order by created_at desc), '[]'::jsonb) into v_attention
  from (
    select id, actor, kind, decision, confidence, route_to, created_at,
           jsonb_build_object('id', id, 'actor', actor, 'kind', kind, 'decision', decision,
             'confidence', confidence, 'route_to', route_to, 'created_at', created_at) as x
    from decision_log where route_to is not null and route_to <> 'auto'
    order by created_at desc limit 8
  ) t;

  return jsonb_build_object(
    'ok', true, 'generated_at', now(),
    'health', v_health, 'ops', v_ops, 'counts', v_counts,
    'pipeline', v_pipeline, 'attention', v_attention
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_os_detail(p_entity text, p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_tbl text; v_idcol text := 'id'; v_row jsonb;
begin
  case p_entity
    when 'inquiries' then v_tbl:='inquiries';
    when 'quotes' then v_tbl:='quotes';
    when 'transactions' then v_tbl:='transactions';
    when 'customers' then v_tbl:='customers';
    when 'suppliers' then v_tbl:='leads';
    when 'agent_actions' then v_tbl:='agent_actions';
    when 'doc_reviews' then v_tbl:='doc_reviews';
    when 'kb_revisions' then v_tbl:='kb_revisions';
    when 'inbox' then v_tbl:='inbound_messages';
    when 'documents' then v_tbl:='documents';
    when 'dropbox' then v_tbl:='dropbox_files';
    when 'invoices' then v_tbl:='reveal_invoices'; v_idcol:='transaction_id';
    when 'notifications' then v_tbl:='notifications';
    when 'tasks' then v_tbl:='crm_tasks';
    when 'po' then v_tbl:='po_orders';
    when 'expenses' then v_tbl:='expenses';
    when 'agent_runs' then v_tbl:='agent_runs';
    when 'fraud' then v_tbl:='fraud_flags'; v_idcol:='subject_id';
    else return jsonb_build_object('error','unknown_entity');
  end case;
  execute format('select to_jsonb(t) from %I t where %I::text = %L limit 1', v_tbl, v_idcol, p_id) into v_row;
  if v_row is null then return jsonb_build_object('error','not_found'); end if;
  return jsonb_build_object('entity',p_entity,'record',v_row);
end $function$


CREATE OR REPLACE FUNCTION public.fn_os_list(p_entity text, p_params jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_tbl text; v_cols text; v_search text[]; v_status text; v_order text; v_idcol text := 'id';
  v_q text := coalesce(nullif(trim(p_params->>'q'),''), null);
  v_st text := coalesce(nullif(trim(p_params->>'status'),''), null);
  v_limit int := least(coalesce((p_params->>'limit')::int, 60), 300);
  v_offset int := greatest(coalesce((p_params->>'offset')::int, 0), 0);
  v_where text := ' where true'; v_rows jsonb; v_total bigint; v_sql text; v_fk text; v_fv text;
begin
  case p_entity
    when 'inquiries' then v_tbl:='inquiries'; v_cols:='id,category,emirate,status,pipeline_stage,scope_type,budget,expected_value,rfq_ready,customer_id,hired_supplier_id,outcome,created_at'; v_search:=array['category','emirate','summary','role_needed']; v_status:='status'; v_order:=' order by created_at desc';
    when 'quotes' then v_tbl:='quotes'; v_cols:='id,inquiry_id,supplier_id,quote_amount,customer_price,app_fee,status,review_status,lead_time,warranty,created_at,expires_at'; v_search:=array['notes','scope','payment_terms']; v_status:='status'; v_order:=' order by created_at desc';
    when 'transactions' then v_tbl:='transactions'; v_cols:='id,inquiry_id,supplier_id,customer_id,quote_amount,reveal_fee,app_fee,fee_status,refund_status,revealed_at,payment_ref'; v_search:=array['payment_ref','refund_reason']; v_status:='fee_status'; v_order:=' order by revealed_at desc nulls last';
    when 'customers' then v_tbl:='customers'; v_cols:='id,full_name,email,phone,email_verified,phone_verified,banned,chat_strikes,locale,created_at'; v_search:=array['full_name','email','phone']; v_status:=null; v_order:=' order by created_at desc';
    when 'suppliers' then v_tbl:='leads'; v_cols:='id,company_name,sector,emirate,city,approval_status,verification_status,verified,matching_blocked,banned,rating,app_rating,capability_score,registration_status,contact_name,email,phone,created_at'; v_search:=array['company_name','email','sector','phone']; v_status:='approval_status'; v_order:=' order by created_at desc';
    when 'agent_actions' then v_tbl:='agent_actions'; v_cols:='id,agent,kind,title,status,risk,confidence,target_table,target_id,escalated,created_at,decided_at,decided_by'; v_search:=array['title','recommendation','agent','kind']; v_status:='status'; v_order:=' order by (status=''pending'') desc, created_at desc';
    when 'doc_reviews' then v_tbl:='doc_reviews'; v_cols:='id,from_email,subject,file_name,ai_category,ai_suggested_field,ai_confidence,status,auto_applied,created_at,file_path'; v_search:=array['subject','from_email','file_name','ai_category']; v_status:='status'; v_order:=' order by created_at desc';
    when 'kb_revisions' then v_tbl:='kb_revisions'; v_cols:='id,entry_kind,entry_ref,version,status,author,reviewer,created_at,decided_at'; v_search:=array['entry_ref','entry_kind','author']; v_status:='status'; v_order:=' order by created_at desc';
    when 'inbox' then v_tbl:='inbound_messages'; v_cols:='id,from_email,to_email,subject,ai_category,needs_review,attachments_count,replied_at,created_at'; v_search:=array['subject','from_email','ai_summary']; v_status:='ai_category'; v_order:=' order by created_at desc';
    when 'documents' then v_tbl:='documents'; v_cols:='id,file_name,kind,ref_table,ref_id,mime,status,indexed,bucket,path,created_at'; v_search:=array['file_name','kind','ref_table']; v_status:='status'; v_order:=' order by created_at desc';
    when 'dropbox' then v_tbl:='dropbox_files'; v_cols:='id,path,name,is_folder,size,server_modified,synced_at'; v_search:=array['path','name']; v_status:=null; v_order:=' order by is_folder desc, name asc';
    when 'invoices' then v_tbl:='reveal_invoices'; v_cols:='transaction_id,invoice_no,bucket,path,created_at'; v_search:=array['invoice_no']; v_status:=null; v_order:=' order by created_at desc'; v_idcol:='transaction_id';
    when 'notifications' then v_tbl:='notifications'; v_cols:='id,type,to_email,to_role,subject,status,channel,created_at,sent_at,last_error'; v_search:=array['subject','to_email','type']; v_status:='status'; v_order:=' order by created_at desc';
    when 'tasks' then v_tbl:='crm_tasks'; v_cols:='id,title,status,priority,entity,entity_id,due_date,created_at,done_at'; v_search:=array['title','detail']; v_status:='status'; v_order:=' order by (status<>''done'') desc, due_date asc nulls last';
    when 'notes' then v_tbl:='crm_notes'; v_cols:='id,entity,entity_id,body,author,created_at'; v_search:=array['body','author']; v_status:=null; v_order:=' order by created_at desc';
    when 'po' then v_tbl:='po_orders'; v_cols:='id,po_no,vendor_id,status,subtotal,currency,order_date,expected_date,approved_by,approved_at,created_at'; v_search:=array['po_no','memo']; v_status:='status'; v_order:=' order by created_at desc';
    when 'expenses' then v_tbl:='expenses'; v_cols:='id,vendor,category,description,amount,currency,cadence,expense_date,active,created_at'; v_search:=array['vendor','description','category']; v_status:=null; v_order:=' order by expense_date desc nulls last';
    when 'agent_runs' then v_tbl:='agent_runs'; v_cols:='id,agent,status,started_at,finished_at,note'; v_search:=array['agent','note']; v_status:='status'; v_order:=' order by started_at desc nulls last';
    when 'fraud' then v_tbl:='fraud_flags'; v_cols:='kind,subject_type,subject_id,severity,status,detail,created_at'; v_search:=array['kind','subject_type','subject_id']; v_status:='status'; v_order:=' order by created_at desc'; v_idcol:='subject_id';
    else return jsonb_build_object('error','unknown_entity','entity',p_entity);
  end case;

  if v_st is not null and v_status is not null then v_where := v_where || format(' and %I = %L', v_status, v_st); end if;
  if v_q is not null then
    v_where := v_where || ' and (' || array_to_string(array(select format('coalesce(%I::text,'''') ilike %L', c, '%'||v_q||'%') from unnest(v_search) c), ' or ') || ')';
  end if;
  if p_params ? 'filters' then
    for v_fk, v_fv in select key, value from jsonb_each_text(p_params->'filters') loop
      if v_fk = any(array['inquiry_id','supplier_id','customer_id','quote_id','ref_table','ref_id','agent','entity','entity_id','category','emirate','lead_id','vendor_id','target_table','target_id']) and position(v_fk in v_cols) > 0 and v_fv is not null then
        v_where := v_where || format(' and %I::text = %L', v_fk, v_fv);
      end if;
    end loop;
  end if;

  execute format('select count(*) from %I%s', v_tbl, v_where) into v_total;
  v_sql := format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from (select %s from %I%s%s limit %s offset %s) t', v_cols, v_tbl, v_where, v_order, v_limit, v_offset);
  execute v_sql into v_rows;
  return jsonb_build_object('entity',p_entity,'id_col',v_idcol,'columns',string_to_array(v_cols, ','),'total',v_total,'rows',v_rows);
end $function$


CREATE OR REPLACE FUNCTION public.fn_os_nav()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'badges', jsonb_build_object(
      'approvals', (select count(*) from agent_actions where status='pending'),
      'tasks', (select count(*) from crm_tasks where coalesce(status,'') <> 'done'),
      'suppliers_review', (select count(*) from leads where coalesce(approval_status,'') in ('submitted','pending','under_review','pending_review')),
      'notifications', (select count(*) from notifications where coalesce(status,'') not in ('sent','delivered','read')),
      'knowledge_review', (select count(*) from kb_revisions where coalesce(status,'')='pending'),
      'documents_review', (select count(*) from doc_reviews where coalesce(status,'')='pending'),
      'disputes', (select count(*) from transactions where coalesce(refund_status,'') in ('requested','pending')),
      'fraud_open', (select count(*) from fraud_flags where coalesce(status,'open') not in ('dismissed','resolved','closed')),
      'rfqs_active', (select count(*) from inquiries where coalesce(status,'') not in ('completed','cancelled','closed'))
    ),
    'generated_at', now()
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_os_record(p_entity text, p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v jsonb;
begin
  if p_entity='supplier' then select to_jsonb(l) into v from leads l where l.id = p_id::bigint;
  elsif p_entity='rfq' then select to_jsonb(i) into v from inquiries i where i.id = p_id::uuid;
  elsif p_entity='customer' then select to_jsonb(c) into v from customers c where c.id = p_id::uuid;
  elsif p_entity='quote' then select to_jsonb(q) into v from quotes q where q.id = p_id::uuid;
  elsif p_entity='agent_action' then select to_jsonb(a) into v from agent_actions a where a.id = p_id::bigint;
  elsif p_entity='task' then select to_jsonb(t) into v from crm_tasks t where t.id = p_id::bigint;
  else v := null; end if;
  return jsonb_build_object('entity',p_entity,'id',p_id,'record',v);
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_os_search(p_q text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'suppliers', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',company_name,'sub',emirate||' · '||coalesce(sector,''))) from (
        select id,company_name,emirate,sector from leads where p_q<>'' and company_name ilike '%'||p_q||'%' order by capability_score desc nulls last limit 6) s),'[]'::jsonb),
    'rfqs', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',coalesce(summary,category),'sub',category)) from (
        select id,summary,category from inquiries where p_q<>'' and (summary ilike '%'||p_q||'%' or category ilike '%'||p_q||'%') order by created_at desc limit 6) r),'[]'::jsonb),
    'customers', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',full_name,'sub',email)) from (
        select id,full_name,email from customers where p_q<>'' and (full_name ilike '%'||p_q||'%' or email ilike '%'||p_q||'%') limit 6) c),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_page_high_agent_action()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_founder text;
BEGIN
  IF lower(coalesce(NEW.risk,'')) IN ('high','critical')
     AND NEW.agent IN ('finance_ai','security_ai','operations_ai')
     AND lower(coalesce(NEW.status,'pending')) = 'pending' THEN
    v_founder := coalesce(
      (SELECT value FROM app_secrets WHERE key='founder_email'),
      nullif(split_part((SELECT value FROM app_secrets WHERE key='admin_emails'), ',', 1), ''),
      'management@quotesdone.com');
    IF NOT EXISTS (
      SELECT 1 FROM notifications
      WHERE type='agent_escalation' AND body LIKE '%action #'||NEW.id||'%'
        AND created_at > now() - interval '24 hours'
    ) THEN
      INSERT INTO notifications(type, to_email, to_role, channel, status, subject, body)
      VALUES('agent_escalation', v_founder, 'admin', 'email', 'queued',
        '['||upper(NEW.risk)||'] '||coalesce(NEW.title, NEW.kind, 'Agent escalation'),
        coalesce(NEW.recommendation, NEW.title, '')||E'\n\nAgent: '||coalesce(NEW.agent,'?')||' · action #'||NEW.id||' · open the OS to decide.');
    END IF;
  END IF;
  RETURN NEW;
END
$function$


CREATE OR REPLACE FUNCTION public.fn_pdpl_erase_plan(p_email text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'subject', p_email,
    'customers',           (select count(*) from public.customers where email=p_email),
    'inquiries',           (select count(*) from public.inquiries where customer_id in (select id from public.customers where email=p_email)),
    'supplier_leads',      (select count(*) from public.leads where email=p_email),
    'notifications',       (select count(*) from public.notifications where to_email=p_email),
    'outreach',            (select count(*) from public.outreach where email=p_email),
    'email_verifications', (select count(*) from public.email_verifications where email=p_email),
    'phone_verifications', (select count(*) from public.phone_verifications where email=p_email),
    'ai_usage',            (select count(*) from public.ai_usage where email=p_email),
    'note','Redaction anonymises personal fields (name/phone/email/DOB) and keeps financial/audit records as legally required. email_suppressions is deliberately retained as a do-not-contact record.'
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_pdpl_export(p_email text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'subject', p_email,
    'generated_at', now(),
    'customers',           (select coalesce(jsonb_agg(to_jsonb(c)),'[]'::jsonb) from public.customers c where c.email=p_email),
    'inquiries',           (select coalesce(jsonb_agg(to_jsonb(i)),'[]'::jsonb) from public.inquiries i where i.customer_id in (select id from public.customers where email=p_email)),
    'supplier_leads',      (select coalesce(jsonb_agg(to_jsonb(l)),'[]'::jsonb) from public.leads l where l.email=p_email),
    'notifications',       (select coalesce(jsonb_agg(to_jsonb(n)),'[]'::jsonb) from public.notifications n where n.to_email=p_email),
    'outreach',            (select coalesce(jsonb_agg(to_jsonb(o)),'[]'::jsonb) from public.outreach o where o.email=p_email),
    'email_verifications', (select coalesce(jsonb_agg(to_jsonb(e)),'[]'::jsonb) from public.email_verifications e where e.email=p_email),
    'phone_verifications', (select coalesce(jsonb_agg(to_jsonb(p)),'[]'::jsonb) from public.phone_verifications p where p.email=p_email),
    'email_suppressions',  (select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) from public.email_suppressions s where s.email=p_email),
    'ai_usage',            (select coalesce(jsonb_agg(to_jsonb(a)),'[]'::jsonb) from public.ai_usage a where a.email=p_email)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_pdpl_redact(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_email text; v_status text;
  v_cust_ids uuid[]; v_phones text[]; v_inq_ids uuid[]; v_quote_ids uuid[];
  c_cust int:=0; c_lead int:=0; c_notif int:=0; c_out int:=0; c_ev int:=0; c_pv int:=0; c_ai int:=0;
  c_msg int:=0; c_inb int:=0; c_wa int:=0; c_inq int:=0; c_rfq int:=0; c_doc int:=0; c_files int:=0;
begin
  select email, status into v_email, v_status from public.pdpl_requests where id=p_request_id;
  if not found then raise exception 'pdpl request % not found', p_request_id; end if;
  if coalesce(v_status,'') <> 'approved' then
    raise exception 'pdpl request % must be status=approved before redaction (current: %)', p_request_id, coalesce(v_status,'null');
  end if;
  if v_email is null then raise exception 'pdpl request % has no email', p_request_id; end if;

  -- resolve subject linkage BEFORE mutating identity fields
  select coalesce(array_agg(id),'{}'), coalesce(array_agg(phone) filter (where phone is not null),'{}')
    into v_cust_ids, v_phones from public.customers where email=v_email;
  select coalesce(array_agg(id),'{}') into v_inq_ids from public.inquiries where customer_id = any(v_cust_ids);
  select coalesce(array_agg(id),'{}') into v_quote_ids from public.quotes where inquiry_id = any(v_inq_ids);

  -- queue Dropbox/storage copies for external erasure BEFORE nulling any file paths
  insert into public.pdpl_erase_files(request_id,subject_email,bucket,storage_path,dropbox_path,origin)
  select p_request_id, v_email, db.bucket, db.path, db.dropbox_path, 'doc_backups:'||coalesce(db.entity,'?')
    from public.doc_backups db
   where (db.entity='customer' and db.entity_id = any(v_cust_ids::text[]))
      or (db.entity='inquiry'  and db.entity_id = any(v_inq_ids::text[]))
      or (db.entity='quote'    and db.entity_id = any(v_quote_ids::text[]));
  insert into public.pdpl_erase_files(request_id,subject_email,bucket,storage_path,dropbox_path,origin)
  select p_request_id, v_email, d.bucket, d.path,
         (select db.dropbox_path from public.doc_backups db where db.bucket=d.bucket and db.path=d.path limit 1),
         'documents:'||coalesce(d.ref_table,'?')
    from public.documents d
   where (d.ref_table='inquiries' and d.ref_id = any(v_inq_ids::text[]))
      or (d.ref_table='quotes'    and d.ref_id = any(v_quote_ids::text[]))
      or (d.ref_table='customers' and d.ref_id = any(v_cust_ids::text[]));
  insert into public.pdpl_erase_files(request_id,subject_email,bucket,storage_path,dropbox_path,origin)
  select p_request_id, v_email, r.bucket, r.archive_path,
         (select db.dropbox_path from public.doc_backups db where db.bucket=r.bucket and db.path=r.archive_path limit 1),
         'rfq_archive'
    from public.rfq_archives r
   where r.customer_id = any(v_cust_ids::text[]);

  -- structured identity tables (existing behaviour, unchanged)
  update public.customers set full_name='[erased-PDPL]', phone=null, date_of_birth=null,
         email='erased_'||id||'@removed.invalid' where email=v_email;
  get diagnostics c_cust = row_count;
  update public.leads set phone=null, whatsapp=null, email=null, matching_blocked=true where email=v_email;
  get diagnostics c_lead = row_count;
  update public.notifications set to_email='[erased]', to_phone=null where to_email=v_email;
  get diagnostics c_notif = row_count;
  update public.outreach set email='[erased]' where email=v_email;
  get diagnostics c_out = row_count;
  update public.email_verifications set email='[erased]' where email=v_email;
  get diagnostics c_ev = row_count;
  update public.phone_verifications set email='[erased]' where email=v_email;
  get diagnostics c_pv = row_count;
  update public.ai_usage set email='[erased]' where email=v_email;
  get diagnostics c_ai = row_count;

  -- free-text conversation / archive surfaces (C2 closure)
  update public.messages set body='[erased-PDPL]', redacted_body='[erased-PDPL]'
    where customer_id = any(v_cust_ids);
  get diagnostics c_msg = row_count;
  update public.inbound_messages set from_email='[erased]', to_email='[erased]', subject='[erased]',
         body='[erased-PDPL]', ai_draft_reply=null, ai_summary=null, ai_notes=null, raw='{}'::jsonb
    where from_email=v_email or to_email=v_email;
  get diagnostics c_inb = row_count;
  if array_length(v_phones,1) is not null then
    update public.wa_messages set wa_from='[erased]', wa_to='[erased]', profile_name='[erased]',
           inbound='[erased-PDPL]', reply='[erased-PDPL]', meta='{}'::jsonb
      where wa_from = any(v_phones) or wa_to = any(v_phones);
    get diagnostics c_wa = row_count;
  end if;
  update public.inquiries set raw_input='[erased-PDPL]', summary='[erased-PDPL]', spec='{}'::jsonb,
         drawing_file_name=null, drawing_file_path=null
    where id = any(v_inq_ids);
  get diagnostics c_inq = row_count;
  update public.rfq_archives set ai_summary='{}'::jsonb where customer_id = any(v_cust_ids::text[]);
  get diagnostics c_rfq = row_count;
  update public.documents set extracted='{}'::jsonb, status='erased'
    where (ref_table='inquiries' and ref_id = any(v_inq_ids::text[]))
       or (ref_table='quotes'    and ref_id = any(v_quote_ids::text[]))
       or (ref_table='customers' and ref_id = any(v_cust_ids::text[]));
  get diagnostics c_doc = row_count;

  update public.pdpl_requests set status='completed', handled_at=now(),
         handled_by=coalesce(handled_by,'fn_pdpl_redact') where id=p_request_id;
  select count(*) into c_files from public.pdpl_erase_files where request_id=p_request_id;

  insert into public.security_events(kind,severity,source,subject,detail)
  values('pdpl_redaction','high','pdpl', v_email,
    jsonb_build_object('request_id',p_request_id,'customers',c_cust,'leads',c_lead,'notifications',c_notif,
      'outreach',c_out,'email_verifications',c_ev,'phone_verifications',c_pv,'ai_usage',c_ai,
      'messages',c_msg,'inbound_messages',c_inb,'wa_messages',c_wa,'inquiries',c_inq,'rfq_archives',c_rfq,
      'documents',c_doc,'files_queued_for_erasure',c_files));

  return jsonb_build_object('subject',v_email,
    'redacted', jsonb_build_object('customers',c_cust,'supplier_leads',c_lead,'notifications',c_notif,
      'outreach',c_out,'email_verifications',c_ev,'phone_verifications',c_pv,'ai_usage',c_ai,
      'messages',c_msg,'inbound_messages',c_inb,'wa_messages',c_wa,'inquiries',c_inq,
      'rfq_archives',c_rfq,'documents',c_doc),
    'files_queued_for_erasure', c_files,
    'files_note','Dropbox/storage copies queued in pdpl_erase_files; run dropbox_backup {op:pdpl_erase, request_id} to delete them.',
    'kept','email_suppressions retained as do-not-contact');
end $function$


CREATE OR REPLACE FUNCTION public.fn_period_report(p_type text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  d_this interval; d_prev_start interval; d_prev_end interval; label text;
  inq_t int; inq_p int; q_t int; q_p int; c_t int; c_p int; s_t int; s_p int; rev_t numeric; rev_p numeric;
  conv numeric; health jsonb; officer text; topcats text; owner text; body text; d jsonb; extra text;
begin
  if p_type='monthly' then d_this:='30 days'; d_prev_start:='60 days'; d_prev_end:='30 days'; label:='Monthly Business Report';
  else d_this:='90 days'; d_prev_start:='180 days'; d_prev_end:='90 days'; label:='Quarterly Strategy Report'; end if;

  select count(*) filter (where created_at>=now()-d_this), count(*) filter (where created_at>=now()-d_prev_start and created_at<now()-d_prev_end) into inq_t,inq_p from inquiries;
  select count(*) filter (where created_at>=now()-d_this), count(*) filter (where created_at>=now()-d_prev_start and created_at<now()-d_prev_end) into q_t,q_p from quotes;
  select count(*) filter (where created_at>=now()-d_this), count(*) filter (where created_at>=now()-d_prev_start and created_at<now()-d_prev_end) into c_t,c_p from customers;
  select count(*) filter (where registration_submitted_at>=now()-d_this), count(*) filter (where registration_submitted_at>=now()-d_prev_start and registration_submitted_at<now()-d_prev_end) into s_t,s_p from leads;
  select coalesce(sum(reveal_fee) filter (where revealed_at>=now()-d_this),0), coalesce(sum(reveal_fee) filter (where revealed_at>=now()-d_prev_start and revealed_at<now()-d_prev_end),0) into rev_t,rev_p from transactions where coalesce(refund_status,'')<>'approved';
  select round(100.0*count(distinct t.inquiry_id)/nullif(count(distinct i.id),0),1) into conv from inquiries i left join transactions t on t.inquiry_id=i.id where i.created_at>=now()-d_this;
  begin select public.fn_health_index() into health; exception when others then health:=null; end;
  select string_agg(cat,', ') into topcats from (select coalesce(nullif(category,''),'(uncat)') cat, count(*) n from inquiries where created_at>=now()-d_this group by 1 order by n desc limit 6) z;
  officer := public.fn_officer_recs(10);

  d := jsonb_build_array();
  if rev_t < rev_p then d := d||to_jsonb('Revenue down vs prior period — review demand and conversion'::text); end if;
  if inq_t < inq_p then d := d||to_jsonb('RFQ volume down vs prior period — assess top-of-funnel'::text); end if;
  if p_type='quarterly' then d := d||to_jsonb('Set next-quarter category focus and supply-activation targets'::text); end if;

  extra := 'RFQs '||inq_t||' (prev '||inq_p||') · Quotes '||q_t||' (prev '||q_p||') · New customers '||c_t||' (prev '||c_p||') · New suppliers '||s_t||' (prev '||s_p||') · Revenue AED '||round(rev_t)||' (prev AED '||round(rev_p)||')';

  body := public.fn_report_skeleton(
    'QuotesDone '||label||' — '||to_char(current_date,'Mon YYYY'),
    'Marketplace health '||coalesce(health->>'index','—')||'/100. Period totals: '||inq_t||' RFQs, '||q_t||' quotes, revenue AED '||round(rev_t)||', 30-day conversion '||coalesce(conv::text,'—')||'%.',
    jsonb_build_array(
      jsonb_build_object('heading','Key Metrics','body',extra),
      jsonb_build_object('heading','Trends (period over period)','body','Demand '||inq_t||' vs '||inq_p||' · Revenue AED '||round(rev_t)||' vs '||round(rev_p)||' · Suppliers +'||s_t||' vs +'||s_p),
      jsonb_build_object('heading','Growth & Categories','body','Top categories: '||coalesce(topcats,'—')),
      jsonb_build_object('heading',case when p_type='quarterly' then 'Strategy & Recommendations' else 'Recommendations' end,'body',coalesce(officer,'No officer recommendations yet.')),
      jsonb_build_object('heading','Risks & Opportunities','body','Primary risk remains marketplace liquidity (activated supply + paying demand). Opportunity: convert the supplier database into an activated, quoting network in the top categories.')
    ), d,
    'Health: '||coalesce(health::text,'n/a'));

  insert into public.board_reports(week_start,title,body,kpis,report_type)
  values (date_trunc('month',current_date)::date, 'QuotesDone '||label||' — '||to_char(current_date,'Mon YYYY'), body,
    jsonb_build_object('rfqs',inq_t,'quotes',q_t,'customers',c_t,'suppliers',s_t,'revenue',rev_t,'conversion',conv,'health',(health->>'index')), p_type);

  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into owner from app_secrets where key='admin_emails';
  insert into notifications(type,to_email,to_role,channel,subject,body)
  values ('period_report', coalesce(owner,'management@quotesdone.com'),'admin','email','QuotesDone '||label||' — '||to_char(current_date,'Mon YYYY'), body);
end $function$


CREATE OR REPLACE FUNCTION public.fn_po_approve(p_po bigint, p_by text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare st text;
begin
  select status into st from public.po_orders where id=p_po;
  if st is null then raise exception 'PO % not found', p_po; end if;
  if st <> 'draft' then raise exception 'PO % is % (only draft can be approved)', p_po, st; end if;
  update public.po_orders set status='approved', approved_by=p_by, approved_at=now() where id=p_po;
  return p_po;
end $function$


CREATE OR REPLACE FUNCTION public.fn_po_bill(p_po bigint, p_bill_no text, p_bill_date date, p_due date, p_vat numeric DEFAULT 0, p_by text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare r record; q numeric(18,4); amt numeric(18,2); sub numeric(18,2) := 0;
        vat numeric(18,2) := coalesce(round(p_vat,2),0); tot numeric(18,2);
        gl_lines jsonb := '[]'::jsonb; j bigint; v_bill bigint; v_vendor bigint;
        all_billed boolean;
begin
  select vendor_id into v_vendor from public.po_orders where id=p_po;
  if v_vendor is null then raise exception 'PO % not found', p_po; end if;

  for r in select * from public.po_lines where po_id=p_po order by line_no loop
    q := r.qty_received - r.qty_billed;                   -- received not yet billed
    if q <= 0 then continue; end if;
    amt := round(q * r.unit_price, 2);
    sub := sub + amt;
    update public.po_lines set qty_billed = qty_billed + q where id=r.id;
  end loop;
  if sub = 0 then raise exception 'PO % has no received-unbilled qty to bill', p_po; end if;
  tot := sub + vat;

  gl_lines := jsonb_build_array(jsonb_build_object('account','2250','debit', sub));  -- clear GRNI
  if vat > 0 then
    gl_lines := gl_lines || jsonb_build_object('account','1150','debit', vat); end if;
  gl_lines := gl_lines || jsonb_build_object('account','2000','credit', tot);        -- AP

  j := public.fn_gl_entry(coalesce(p_bill_date,current_date),
         'Vendor bill '||coalesce(p_bill_no,'(PO-'||p_po||')'),
         'ap_bill', p_po::text, gl_lines, p_by);

  insert into public.ap_bills(bill_no,vendor_id,po_id,bill_date,due_date,
        subtotal,vat_amount,total,gl_journal_id,created_by)
    values (p_bill_no, v_vendor, p_po, coalesce(p_bill_date,current_date), p_due,
            sub, vat, tot, j, p_by)
    returning id into v_bill;
  update public.ap_bills set bill_no = coalesce(bill_no,'BILL-'||lpad(v_bill::text,6,'0')) where id=v_bill;

  select bool_and(qty_billed >= qty) into all_billed from public.po_lines where po_id=p_po;
  update public.po_orders set status = case when all_billed then 'billed' else status end where id=p_po;
  return v_bill;
end $function$


CREATE OR REPLACE FUNCTION public.fn_po_create(p_vendor bigint, p_order_date date, p_expected date, p_memo text, p_lines jsonb, p_created_by text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_po bigint; ln jsonb; i int := 0; sub numeric(18,2) := 0;
begin
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'PO needs at least one line';
  end if;
  insert into public.po_orders(vendor_id,order_date,expected_date,memo,created_by)
    values (p_vendor, coalesce(p_order_date,current_date), p_expected, p_memo, p_created_by)
    returning id into v_po;
  update public.po_orders set po_no = 'PO-'||lpad(v_po::text,6,'0') where id=v_po;
  for ln in select * from jsonb_array_elements(p_lines) loop
    i := i + 1;
    insert into public.po_lines(po_id,line_no,description,account_code,item_id,qty,unit_price)
      values (v_po, i, ln->>'description', ln->>'account',
              nullif(ln->>'item','')::bigint,
              (ln->>'qty')::numeric, coalesce((ln->>'unit_price')::numeric,0));
    sub := sub + (ln->>'qty')::numeric * coalesce((ln->>'unit_price')::numeric,0);
  end loop;
  update public.po_orders set subtotal = sub where id=v_po;
  return v_po;
end $function$


CREATE OR REPLACE FUNCTION public.fn_po_receive(p_po bigint, p_recv jsonb DEFAULT NULL::jsonb, p_date date DEFAULT NULL::date, p_by text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare r record; q numeric(18,4); amt numeric(18,2); gl_lines jsonb := '[]'::jsonb;
        total numeric(18,2) := 0; j bigint; st text; all_recv boolean;
        recv_items jsonb := '[]'::jsonb;   -- {item, qty, unit_cost}
begin
  select status into st from public.po_orders where id=p_po;
  if st is null then raise exception 'PO % not found', p_po; end if;
  if st not in ('approved','partial') then
    raise exception 'PO % is % (must be approved before receiving)', p_po, st; end if;

  for r in select * from public.po_lines where po_id=p_po order by line_no loop
    if p_recv is null then
      q := r.qty - r.qty_received;
    else
      q := coalesce((select (e->>'qty')::numeric
             from jsonb_array_elements(p_recv) e
             where (e->>'line_no')::int = r.line_no), 0);
    end if;
    if q <= 0 then continue; end if;
    if r.qty_received + q > r.qty then
      raise exception 'line % over-receipt: %/%', r.line_no, r.qty_received+q, r.qty; end if;
    amt := round(q * r.unit_price, 2);
    total := total + amt;
    gl_lines := gl_lines || jsonb_build_object('account', r.account_code, 'debit', amt);
    update public.po_lines set qty_received = qty_received + q where id=r.id;
    if r.item_id is not null then
      recv_items := recv_items || jsonb_build_object('item', r.item_id, 'qty', q, 'unit_cost', r.unit_price);
    end if;
  end loop;

  if total = 0 then raise exception 'nothing to receive on PO %', p_po; end if;
  gl_lines := gl_lines || jsonb_build_object('account','2250','credit', total);
  j := public.fn_gl_entry(coalesce(p_date,current_date),
         'Goods receipt '||(select po_no from public.po_orders where id=p_po),
         'po_receipt', p_po::text, gl_lines, p_by);

  -- record inventory stock moves (GL already posted above; no double entry)
  insert into public.inv_stock_moves(item_id,move_date,move_type,qty_delta,cost_delta,
       unit_cost,ref_type,ref_id,gl_journal_id,created_by)
  select (e->>'item')::bigint, coalesce(p_date,current_date), 'in',
         (e->>'qty')::numeric, round((e->>'qty')::numeric*(e->>'unit_cost')::numeric,2),
         (e->>'unit_cost')::numeric, 'po_receipt', p_po::text, j, p_by
  from jsonb_array_elements(recv_items) e;

  select bool_and(qty_received >= qty) into all_recv from public.po_lines where po_id=p_po;
  update public.po_orders set status = case when all_recv then 'received' else 'partial' end where id=p_po;
  return j;
end $function$


CREATE OR REPLACE FUNCTION public.fn_policy_consistency_check()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; f jsonb := '[]'::jsonb; n int := 0; v_admin text; v_crit int := 0;
begin
  for r in select * from policy_rules where active loop
    if r.scope in ('all','site') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','site','location',path))
             from qd_deploy_src where path not like '\_archive/%' and data ~* r.forbid_regex), '[]'::jsonb);
    end if;
    if r.scope in ('all','faq') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','company_faq','location','#'||id||' '||question))
             from company_faq where status='approved' and answer ~* r.forbid_regex), '[]'::jsonb);
    end if;
    if r.scope in ('all','email') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','email','location',key))
             from app_secrets where key in ('invite_body','invite_subject') and value ~* r.forbid_regex), '[]'::jsonb);
    end if;
    if r.scope in ('all','kb') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','agent_knowledge','location',agent_key||' / '||topic||' (#'||id||')'))
             from agent_knowledge where content ~* r.forbid_regex), '[]'::jsonb);
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','dept_library','location',department||' / '||title||' (#'||id||')'))
             from dept_library where content ~* r.forbid_regex), '[]'::jsonb);
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','agent_memory','location',agent_key||' / '||kind||' (#'||id||')'))
             from agent_memory where content ~* r.forbid_regex), '[]'::jsonb);
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','org_memory','location',scope||' / '||kind||' (#'||id||')'))
             from org_memory where active and content ~* r.forbid_regex), '[]'::jsonb);
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','kb_chunks','location',coalesce(category,'?')||' (#'||id||')'))
             from kb_chunks where content ~* r.forbid_regex), '[]'::jsonb);
    end if;
  end loop;
  n := jsonb_array_length(f);
  select count(*) into v_crit from jsonb_array_elements(f) e where e->>'severity'='critical';
  if n > 0 then
    v_admin := coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com');
    if not exists (select 1 from founder_alerts where event='policy_inconsistency' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values(case when v_crit>0 then 'crit' else 'warn' end,'policy_inconsistency',
          n||' policy contradiction(s) found across site, FAQ, email, agent knowledge, library, memories and retrieval chunks: '||left(f::text,600),'system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('policy_inconsistency', v_admin,'admin','email','Policy contradiction detected',
          n||' place(s) now contradict current QuotesDone policy. Scan covers 8 stores incl. kb_chunks retrieval. Details: '||left(f::text,1500),'queued');
    end if;
  end if;
  return json_build_object('findings', n, 'critical', v_crit, 'detail', f, 'checked_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_policy_lint_kb_chunks()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 select jsonb_build_object('kb_chunks_dirty', count(*)) from kb_chunks k
 where exists (select 1 from policy_rules p where p.active and k.content ~* p.forbid_regex)
$function$


CREATE OR REPLACE FUNCTION public.fn_price_confidence(p_category text, p_amount numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s record; iqr numeric; z numeric; conf int; band text;
begin
  select * into s from category_price_stats where category = p_category;
  if s is null or s.n < 4 then
    return jsonb_build_object('confidence', null, 'band', 'insufficient_data', 'n', coalesce(s.n,0));
  end if;
  iqr := nullif(s.p75 - s.p25, 0);
  if iqr is null then iqr := nullif(s.sd, 0); end if;
  if iqr is null then
    return jsonb_build_object('confidence', null, 'band', 'insufficient_data', 'n', s.n);
  end if;
  z := abs(p_amount - s.median) / iqr;
  conf := greatest(5, least(99, round(100 * exp(-0.6 * z))::int));
  if    p_amount < s.p25 - 1.5*iqr then band := 'suspiciously_low';
  elsif p_amount > s.p75 + 1.5*iqr then band := 'suspiciously_high';
  elsif p_amount between s.p25 and s.p75 then band := 'fair';
  else band := 'within_range';
  end if;
  return jsonb_build_object('confidence', conf, 'band', band,
    'median', s.median, 'p25', s.p25, 'p75', s.p75, 'n', s.n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_procurement_analysis(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare minp numeric; maxp numeric; medp numeric; nq int;
        matrix jsonb := '[]'::jsonb; r record; rec jsonb := null; best numeric := -1;
        price_score numeric; qual numeric; rep numeric; warr_m int; warr_score numeric;
        lead_w int; lead_score numeric; comp numeric; value numeric; risks text[]; letter text; idx int := 0;
begin
  select count(*), min(quote_amount), max(quote_amount), percentile_cont(0.5) within group (order by quote_amount)
    into nq, minp, maxp, medp
  from public.quotes where inquiry_id=p_id and coalesce(quote_amount,0) > 0
    and coalesce(status,'') not in ('withdrawn','rejected','expired');
  if nq = 0 then return jsonb_build_object('ready',false,'quote_count',0,'note','No priced quotes yet.'); end if;

  for r in
    select q.*, l.company_name, l.rating,
           rp.reputation_index, rp.dispute_rate_pct
    from public.quotes q
    left join public.leads l on l.id=q.supplier_id
    left join public.supplier_reputation rp on rp.supplier_id=q.supplier_id
    where q.inquiry_id=p_id and coalesce(q.quote_amount,0) > 0
      and coalesce(q.status,'') not in ('withdrawn','rejected','expired')
    order by q.quote_amount asc
  loop
    idx := idx + 1; letter := chr(64+idx);  -- A, B, C...
    price_score := case when maxp=minp then 100 else round((maxp - r.quote_amount)/(maxp-minp)*100) end;
    qual := coalesce((r.quality->>'score')::numeric, 0);
    rep := coalesce(r.reputation_index, r.rating*20, 50);
    warr_m := coalesce((regexp_match(coalesce(r.warranty,''),'(\d+)'))[1]::int, 0);
    warr_score := case when r.warranty is null then 0 else least(100, warr_m::numeric/24*100) end;
    lead_w := coalesce((regexp_match(coalesce(r.lead_time,''),'(\d+)'))[1]::int, null);
    lead_score := case when lead_w is null then 50 else greatest(0, 100 - lead_w*8) end;
    comp := case when (r.quality->>'mandatory_total') is not null and (r.quality->>'mandatory_total')::numeric>0
                 then round((r.quality->>'mandatory_present')::numeric/(r.quality->>'mandatory_total')::numeric*100) else qual end;
    value := round(0.35*qual + 0.30*price_score + 0.15*rep + 0.10*warr_score + 0.10*lead_score);

    risks := '{}';
    if qual < 50 then risks := array_append(risks,'Quote incomplete — low quality score ('||qual||'/100)'); end if;
    if r.expires_at is not null and r.expires_at < now() then risks := array_append(risks,'Quote has expired'); end if;
    if medp>0 and r.quote_amount < 0.75*medp then risks := array_append(risks,'Price well below median — verify the scope is not under-quoted'); end if;
    if r.warranty is null then risks := array_append(risks,'No warranty stated'); end if;
    if coalesce(r.payment_terms,'')='' then risks := array_append(risks,'No payment terms stated'); end if;
    if coalesce(r.dispute_rate_pct,0) > 10 then risks := array_append(risks,'Supplier has a dispute history ('||round(r.dispute_rate_pct)||'%)'); end if;
    if array_length(risks,1) is null then risks := array_append(risks,'No major risks flagged'); end if;

    matrix := matrix || jsonb_build_object(
      'label','Supplier '||letter, 'quote_id',r.id, 'supplier_id',r.supplier_id, 'company_name',r.company_name,
      'price', r.quote_amount, 'price_vs_low_pct', case when minp>0 then round((r.quote_amount-minp)/minp*100,1) else 0 end,
      'lead_time', r.lead_time, 'warranty', r.warranty, 'payment_terms', r.payment_terms, 'validity', r.validity,
      'quality_score', qual, 'completeness_pct', comp, 'reputation', round(rep),
      'value_score', value, 'risks', to_jsonb(risks));

    if value > best then best := value;
      rec := jsonb_build_object('label','Supplier '||letter,'supplier_id',r.supplier_id,'company_name',r.company_name,
        'value_score',value,'price',r.quote_amount,
        'why','Best overall value: quality '||qual||'/100, price score '||price_score||'/100'
          ||case when qual>=70 then ', well-documented' else ', but confirm the missing quote details' end
          ||case when r.quote_amount=minp then ', and it is the lowest price' else '' end||'.');
    end if;
  end loop;

  return jsonb_build_object(
    'ready', nq>=2, 'quote_count', nq,
    'price_range', jsonb_build_object('low',minp,'median',medp,'high',maxp,'spread_pct',case when minp>0 then round((maxp-minp)/minp*100,1) else 0 end),
    'matrix', matrix,
    'recommendation', rec,
    'note', case when nq=1 then 'Only one quote so far — comparison needs at least two.' else null end
  );
end $function$


CREATE OR REPLACE FUNCTION public.fn_promote_memory(p_memory_id bigint, p_category text, p_by text DEFAULT 'founder'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare m record; v_chunk_id bigint;
begin
  select * into m from public.agent_memory where id = p_memory_id;
  if not found then raise exception 'memory % not found', p_memory_id; end if;
  if exists (select 1 from public.memory_promotions where memory_id = p_memory_id) then
    raise exception 'memory % already promoted', p_memory_id;
  end if;
  insert into public.kb_chunks(source_kind, source_id, category, title, content, citation, effective_date)
  values('memory', p_memory_id::text, coalesce(nullif(p_category,''),'general'),
         left(m.content, 80), m.content,
         'agent_memory #'||p_memory_id||' ('||coalesce(m.agent_key,'?')||')', current_date)
  returning id into v_chunk_id;
  insert into public.memory_promotions(memory_id, kb_chunk_id, category, promoted_by)
  values(p_memory_id, v_chunk_id, coalesce(nullif(p_category,''),'general'), p_by);
  return v_chunk_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_prompt_approve_draft(p_key text, p_version integer, p_by text DEFAULT 'founder'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not exists(select 1 from prompt_versions where prompt_key=p_key and version=p_version and status='draft') then
    return jsonb_build_object('error','draft_not_found'); end if;
  update prompt_versions set status='deprecated' where prompt_key=p_key and status='active';
  update prompt_versions set status='active', rollout_pct=100, approved_by=p_by where prompt_key=p_key and version=p_version;
  update prompts set active_version=p_version, updated_at=now() where key=p_key;
  update agent_actions set status='approved', decided_at=now(), decided_by=p_by
    where kind='prompt_approval' and detail->>'key'=p_key and (detail->>'version')::int=p_version and status in ('pending','needs_review');
  return jsonb_build_object('ok',true,'active_version',p_version);
end $function$


CREATE OR REPLACE FUNCTION public.fn_prompt_draft(p_key text, p_content text, p_by text DEFAULT 'ai_trainer'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v int;
begin
  insert into public.prompts(key,owner) values(p_key,p_by) on conflict(key) do update set updated_at=now();
  select coalesce(max(version),0)+1 into v from prompt_versions where prompt_key=p_key;
  insert into prompt_versions(prompt_key,version,content,status,rollout_pct,approved_by)
    values(p_key,v,p_content,'draft',0,null);
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_prompt_get(p_key text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select content from prompt_versions pv join prompts p on p.key=pv.prompt_key
  where pv.prompt_key=p_key and pv.version=p.active_version limit 1;
$function$


CREATE OR REPLACE FUNCTION public.fn_prompt_publish(p_key text, p_content text, p_owner text DEFAULT 'agent'::text, p_rollout integer DEFAULT 100)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v int;
begin
  insert into public.prompts(key,owner) values(p_key,p_owner) on conflict(key) do update set updated_at=now();
  select coalesce(max(version),0)+1 into v from prompt_versions where prompt_key=p_key;
  insert into prompt_versions(prompt_key,version,content,status,rollout_pct,approved_by) values(p_key,v,p_content,'active',p_rollout,p_owner);
  update prompt_versions set status='deprecated' where prompt_key=p_key and version<v and status='active';
  update prompts set active_version=v, updated_at=now() where key=p_key;
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_prompt_reject_draft(p_key text, p_version integer, p_by text DEFAULT 'founder'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update prompt_versions set status='discarded' where prompt_key=p_key and version=p_version and status='draft';
  update agent_actions set status='rejected', decided_at=now(), decided_by=p_by
    where kind='prompt_approval' and detail->>'key'=p_key and (detail->>'version')::int=p_version and status in ('pending','needs_review');
  return jsonb_build_object('ok',true);
end $function$


CREATE OR REPLACE FUNCTION public.fn_prompt_rollback(p_key text, p_to_version integer, p_by text DEFAULT 'agent'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not exists(select 1 from prompt_versions where prompt_key=p_key and version=p_to_version) then
     return jsonb_build_object('error','version not found'); end if;
  update prompt_versions set status='deprecated' where prompt_key=p_key and status='active';
  update prompt_versions set status='active', approved_by=p_by where prompt_key=p_key and version=p_to_version;
  update prompts set active_version=p_to_version, updated_at=now() where key=p_key;
  return jsonb_build_object('ok',true,'active_version',p_to_version);
end $function$


CREATE OR REPLACE FUNCTION public.fn_protect_gate_secrets()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  -- Keys that are used as an authentication gate somewhere in the edge-function fleet.
  gate_keys text[] := array[
    'inbound_secret',
    'content_secret',
    'resend_inbound_token',
    'resend_webhook_key',
    'postiz_publish_key',
    'stripe_webhook_secret'
  ];
begin
  if tg_op = 'DELETE' then
    if old.key = any(gate_keys) then
      raise exception
        'app_secrets.% is a protected authentication gate key and cannot be deleted. Removing it would cause edge functions that compare (body.__secret !== sec(%)) to authorise unauthenticated callers, because an absent key and an absent field are both undefined. To rotate it, UPDATE the value in place instead.',
        old.key, old.key
        using errcode = 'raise_exception';
    end if;
    return old;
  end if;

  if new.key = any(gate_keys) and (new.value is null or length(btrim(new.value)) = 0) then
    raise exception
      'app_secrets.% is a protected authentication gate key and cannot be set to null or blank. A blank gate secret makes the comparison (body.__secret !== sec(%)) pass for callers sending an empty or absent secret. Set a non-empty value.',
      new.key, new.key
      using errcode = 'raise_exception';
  end if;

  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_provision_category_call(p_raw text, p_lead bigint, p_hint text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_secret text;
begin
  if coalesce(trim(p_raw),'')='' then return; end if;
  select value into v_secret from app_secrets where key='inbound_secret';
  perform net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/category_provision',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('__secret',v_secret,'raw_category',p_raw,'lead_id',p_lead,'hint_services',coalesce(p_hint,''))
  );
end $function$


CREATE OR REPLACE FUNCTION public.fn_quality_metrics()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare res jsonb;
begin
  select jsonb_build_object(
    'rfqs_missing_fields_30d', (select count(*) from inquiries where created_at > now()-interval '30 days'
        and (category is null or coalesce(summary,'')='' or emirate is null)),
    'rfqs_few_suppliers_30d', (select count(*) from inquiries i where i.created_at > now()-interval '30 days'
        and (select count(*) from inquiry_matches m where m.inquiry_id=i.id) < 3),
    'avg_quote_completeness', (select round(avg((quality->>'score')::numeric),1) from quotes where quality is not null),
    'low_quality_quotes', (select count(*) from quotes where (quality->>'score')::numeric < 50),
    'rfqs_not_comparable', (select count(*) from (select inquiry_id from quotes group by inquiry_id having count(*)=1) z)
  ) into res;
  return res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_quarterly_report()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_period_report('quarterly'); $function$


CREATE OR REPLACE FUNCTION public.fn_query_platform(p_topic text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb;
begin
  case lower(coalesce(p_topic,''))
    when 'topics' then
      v := jsonb_build_object('topics', jsonb_build_array(
        'knowledge','agents','agent_ops','ai','analytics','company','customers','documents',
        'ea','exec','finance','fraud','governance','marketing','marketplace','operations',
        'refunds','reports','strategy','suppliers','supplier_360','customer_360','rfq_360','funnel'));
    when 'knowledge'   then v := to_jsonb(fn_ws_knowledge());
    when 'agents'      then v := to_jsonb(fn_ws_agents());
    when 'agent_ops'   then v := to_jsonb(fn_ws_agent_ops(coalesce(p_args->>'agent','')));
    when 'ai'          then v := to_jsonb(fn_ws_ai());
    when 'analytics'   then v := to_jsonb(fn_ws_analytics());
    when 'company'     then v := to_jsonb(fn_ws_company());
    when 'customers'   then v := to_jsonb(fn_ws_customers());
    when 'documents'   then v := to_jsonb(fn_ws_documents());
    when 'ea'          then v := to_jsonb(fn_ws_ea());
    when 'exec'        then v := to_jsonb(fn_ws_exec());
    when 'finance'     then v := to_jsonb(fn_ws_finance());
    when 'fraud'       then v := to_jsonb(fn_ws_fraud());
    when 'governance'  then v := to_jsonb(fn_ws_governance());
    when 'marketing'   then v := to_jsonb(fn_ws_marketing());
    when 'marketplace' then v := to_jsonb(fn_ws_marketplace());
    when 'operations'  then v := to_jsonb(fn_ws_operations());
    when 'refunds'     then v := to_jsonb(fn_ws_refunds());
    when 'reports'     then v := to_jsonb(fn_ws_reports());
    when 'strategy'    then v := to_jsonb(fn_ws_strategy());
    when 'suppliers'   then v := to_jsonb(fn_ws_suppliers(coalesce(p_args,'{}'::jsonb)));
    when 'supplier_360' then v := to_jsonb(fn_ws_supplier_360((p_args->>'id')::bigint));
    when 'customer_360' then v := to_jsonb(fn_ws_customer_360((p_args->>'id')::uuid));
    when 'rfq_360'      then v := to_jsonb(fn_ws_rfq_360((p_args->>'id')::uuid));
    when 'funnel'       then v := to_jsonb(funnel_metrics(coalesce((p_args->>'days')::int,30)));
    else v := jsonb_build_object('error','unknown_topic','hint','call with topic=topics to list valid topics');
  end case;
  return coalesce(v,'{}'::jsonb);
exception when others then
  return jsonb_build_object('error','query_failed','topic',p_topic,'detail',sqlerrm);
end $function$


CREATE OR REPLACE FUNCTION public.fn_quote_category_score(p_quote text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare q record; grp text; blob text; r record;
        tot int:=0; okc int:=0; miss jsonb:='[]'::jsonb; pres jsonb:='[]'::jsonb; mand_missing int:=0;
begin
  select * into q from quotes where id=p_quote::uuid;
  if q is null then return jsonb_build_object('applicable',false,'reason','quote not found'); end if;
  grp := fn_quote_spec_group(coalesce((select category from inquiries where id=q.inquiry_id),''));
  if grp is null then return jsonb_build_object('applicable',false,'reason','no category spec group'); end if;
  if not exists (select 1 from category_quote_specs where spec_group=grp) then
    return jsonb_build_object('applicable',false,'reason','no specs defined for '||grp); end if;

  select lower(concat_ws(' ', q.scope, q.conditions, q.exclusions, q.notes, q.warranty,
           q.payment_terms, q.lead_time, q.validity,
           (select string_agg(concat_ws(' ',description,brand,model,specification),' ')
              from quote_items where quote_id=p_quote)))
    into blob;
  blob := coalesce(blob,'');

  for r in select * from category_quote_specs where spec_group=grp order by mandatory desc, aspect loop
    tot := tot + 1;
    if blob ~* r.match_regex then
      okc := okc + 1; pres := pres || to_jsonb(r.aspect);
    else
      miss := miss || jsonb_build_object('aspect',r.aspect,'label',r.label,'mandatory',r.mandatory);
      if r.mandatory then mand_missing := mand_missing + 1; end if;
    end if;
  end loop;

  return jsonb_build_object(
    'applicable', true, 'group', grp,
    'aspects_total', tot, 'aspects_present', okc,
    'mandatory_missing', mand_missing,
    'category_pass', (mand_missing = 0),
    'present', pres, 'missing', miss);
end $function$


CREATE OR REPLACE FUNCTION public.fn_quote_category_score_text(p_category text, p_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare grp text; blob text; r record; tot int:=0; okc int:=0; mand_missing int:=0; miss jsonb:='[]'::jsonb;
begin
  grp := fn_quote_spec_group(coalesce(p_category,''));
  if grp is null or not exists (select 1 from category_quote_specs where spec_group=grp) then
    return jsonb_build_object('applicable',false); end if;
  blob := lower(coalesce(p_text,''));
  for r in select * from category_quote_specs where spec_group=grp loop
    tot := tot + 1;
    if blob ~* r.match_regex then okc := okc + 1;
    else miss := miss || jsonb_build_object('aspect',r.aspect,'mandatory',r.mandatory);
      if r.mandatory then mand_missing := mand_missing + 1; end if; end if;
  end loop;
  return jsonb_build_object('applicable',true,'group',grp,'aspects_total',tot,'aspects_present',okc,
    'mandatory_missing',mand_missing,'category_pass',(mand_missing=0),'missing',miss);
end $function$


CREATE OR REPLACE FUNCTION public.fn_quote_coach(p_quote uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare sc jsonb; lbls text[]; miss text; sup record; co text; subject text; msg text;
begin
  sc := public.fn_quote_structured_score(p_quote::text);
  if (sc->>'submittable')::boolean then return jsonb_build_object('ok',true,'submittable',true); end if;
  lbls := '{}';
  for miss in select jsonb_array_elements_text(sc->'missing') loop
    lbls := array_append(lbls, case miss
      when 'line_items' then 'an itemised breakdown — add each item as a line'
      when 'unit_prices_on_all_items' then 'a unit price on every line item'
      when 'brand_model_per_item' then 'the brand and model for each item'
      when 'specifications' then 'technical specifications for the items'
      when 'labour_or_installation' then 'labour / installation cost'
      when 'warranty' then 'the warranty offered'
      when 'lead_time' then 'the lead time / delivery timeline'
      when 'payment_terms' then 'your payment terms'
      when 'exclusions' then 'what is excluded from the quote'
      when 'validity' then 'how long the quote is valid'
      else miss end);
  end loop;
  select l.company_name, l.claimed_by, l.email into sup
    from public.quotes q join public.leads l on l.id=q.supplier_id where q.id=p_quote;
  co := coalesce(sup.company_name,'there');
  if not exists (select 1 from public.notifications n where n.type='quote_coaching'
                   and n.to_email=coalesce(sup.claimed_by,sup.email) and n.created_at > now()-interval '24 hours'
                   and n.body like '%'||p_quote::text||'%') then
    subject := 'Your quote needs a few more details before we can send it';
    msg := 'Hi '||co||','||E'\n\n'||'Thanks for your quote. To make it competitive and send it to the customer, please add the following in your supplier portal:'||E'\n\n'
      ||'• '||array_to_string(lbls, E'\n• ')||E'\n\n'
      ||'Detailed quotes (with brands, specifications and a clear itemised breakdown) win far more often. Open your portal, complete these, and we will send it to the customer right away.'||E'\n\n'||'(ref '||p_quote::text||')';
    insert into public.notifications(type,to_email,to_role,channel,subject,body,status)
      values('quote_coaching', coalesce(sup.claimed_by,sup.email), 'supplier','email',subject,msg,'queued');
  end if;
  return jsonb_build_object('ok',true,'submittable',false,'missing',lbls,'score',sc->>'score');
end $function$


CREATE OR REPLACE FUNCTION public.fn_quote_coach_text(p_quote text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare gen jsonb; cat jsonb; asks text[] := '{}'; m jsonb; lbl text;
        gen_labels jsonb := jsonb_build_object(
          'line_items','an itemised breakdown (not just a lump sum)',
          'unit_prices_on_all_items','a unit price on every line',
          'brand_model_per_item','the brand/model for each item',
          'specifications','the key specifications',
          'labour_or_installation','the labour / installation cost',
          'warranty','the warranty period','lead_time','the lead / delivery time',
          'payment_terms','the payment terms','exclusions','what is excluded',
          'validity','how long the quote is valid');
begin
  select quality into gen from quotes where id = p_quote::uuid;
  -- generic completeness gaps
  if gen ? 'missing' then
    for m in select * from jsonb_array_elements(gen->'missing') loop
      lbl := gen_labels->>(m #>> '{}'); if lbl is null then lbl := m #>> '{}'; end if;
      asks := asks || lbl;
    end loop;
  end if;
  -- category-specific domain gaps (mandatory only)
  cat := fn_quote_category_score(p_quote);
  if (cat->>'applicable')::boolean and cat ? 'missing' then
    for m in select * from jsonb_array_elements(cat->'missing') loop
      if (m->>'mandatory')::boolean then asks := asks || lower(m->>'label'); end if;
    end loop;
  end if;
  asks := (select array_agg(distinct a) from unnest(asks) a);
  if coalesce(array_length(asks,1),0) = 0 then
    return jsonb_build_object('complete', true, 'message',
      'Your quote looks complete — thank you. Customers will be able to compare it fairly.');
  end if;
  return jsonb_build_object('complete', false, 'missing_count', array_length(asks,1),
    'message', 'Almost there. To help customers compare your quote fairly and pick you, please add: '
      || array_to_string(asks, '; ') || '. This makes your quote stronger, not harder — complete quotes win more often.',
    'asks', to_jsonb(asks));
end $function$


CREATE OR REPLACE FUNCTION public.fn_quote_recompute_submittable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare qid uuid; sc jsonb; cat jsonb; ok boolean;
begin
  qid := coalesce(NEW.quote_id, OLD.quote_id);
  begin sc := public.fn_quote_structured_score(qid::text); exception when others then sc := null; end;
  begin cat := public.fn_quote_category_score(qid::text); exception when others then cat := null; end;
  if sc is not null then
    ok := (sc->>'submittable')::boolean
          and (cat is null or (cat->>'applicable')::boolean is not true or (cat->>'category_pass')::boolean);
    update public.quotes set submittable = ok
      where id = qid and submittable is distinct from ok;
  end if;
  return coalesce(NEW, OLD);
end $function$


CREATE OR REPLACE FUNCTION public.fn_quote_score_json(p_quote jsonb, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int; priced int; branded int; laboured int; spec_n int; pts int:=0; miss text[]:='{}'; it jsonb;
begin
  n:=0; priced:=0; branded:=0; laboured:=0; spec_n:=0;
  for it in select * from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    n:=n+1;
    if coalesce((it->>'unit_price')::numeric,0) > 0 then priced:=priced+1; end if;
    if coalesce(it->>'brand','')<>'' and coalesce(it->>'model','')<>'' then branded:=branded+1; end if;
    if (it->>'labour') is not null or (it->>'install') is not null then laboured:=laboured+1; end if;
    if coalesce(it->>'specification','')<>'' then spec_n:=spec_n+1; end if;
  end loop;
  if n=0 then miss:=array_append(miss,'line_items');
  else pts:=pts+15; if priced=n then pts:=pts+20; else miss:=array_append(miss,'unit_prices_on_all_items'); end if; end if;
  if n>0 and branded=n then pts:=pts+15; else miss:=array_append(miss,'brand_model_per_item'); end if;
  if n>0 and spec_n>=greatest(1,n/2) then pts:=pts+10; else miss:=array_append(miss,'specifications'); end if;
  if laboured>0 then pts:=pts+10; else miss:=array_append(miss,'labour_or_installation'); end if;
  if coalesce(p_quote->>'warranty','')<>'' then pts:=pts+6; else miss:=array_append(miss,'warranty'); end if;
  if coalesce(p_quote->>'lead_time','')<>'' then pts:=pts+6; else miss:=array_append(miss,'lead_time'); end if;
  if coalesce(p_quote->>'payment_terms','')<>'' then pts:=pts+6; else miss:=array_append(miss,'payment_terms'); end if;
  if coalesce(p_quote->>'exclusions','')<>'' then pts:=pts+6; else miss:=array_append(miss,'exclusions'); end if;
  if coalesce(p_quote->>'validity','')<>'' then pts:=pts+6; else miss:=array_append(miss,'validity'); end if;
  return jsonb_build_object('score',pts,'submittable',pts>=70,'items',n,'missing',to_jsonb(miss));
end $function$


CREATE OR REPLACE FUNCTION public.fn_quote_spec_group(p_category text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p_category ~* 'duct.?clean|ac.?duct' then 'acduct'
    when p_category ~* 'facade.?clean|facade cleaning' then 'facade'
    when p_category ~* 'water.?tank' then 'watertank'
    when p_category ~* 'cctv|surveillance|security|access.?control|intercom|alarm' then 'security'
    when p_category ~* 'fire|safety|sprinkler|extinguisher|civil.?defen' then 'fire'
    when p_category ~* 'scaffold' then 'scaffolding'
    when p_category ~* 'demolition|strip.?out' then 'demolition'
    when p_category ~* 'garage.?door|shutter|rolling' then 'shutters'
    when p_category ~* 'elevator|escalator|^lift|lifts' then 'elevators'
    when p_category ~* 'generator' then 'generators'
    when p_category ~* 'solar|photovolt|shams' then 'solar'
    when p_category ~* 'swimming|pool' then 'pools'
    when p_category ~* 'tent|shade|pergola|awning|gazebo' then 'shade'
    when p_category ~* 'landscap|garden|softscape|hardscape|irrigation' then 'landscaping'
    when p_category ~* 'pest' then 'pestcontrol'
    when p_category ~* 'mover|moving|relocation|packing' then 'movers'
    when p_category ~* 'upholstery|curtain|blind|sofa' then 'upholstery'
    when p_category ~* 'wallpaper|wall covering' then 'wallpaper'
    when p_category ~* 'carpet' then 'carpet'
    when p_category ~* 'tiling|tile|marble|granite' then 'tiling'
    when p_category ~* 'floor|spc|vinyl|lvt|epoxy.?floor|parquet|laminate' then 'flooring'
    when p_category ~* 'paint' then 'painting'
    when p_category ~* 'gypsum|false.?ceiling|ceiling|drywall|plasterboard|partition' then 'gypsum'
    when p_category ~* 'waterproof' then 'waterproofing'
    when p_category ~* 'insulation' then 'insulation'
    when p_category ~* 'roofing|^roof|roof ' then 'roofing'
    when p_category ~* 'steel|fabrication' then 'steel'
    when p_category ~* 'masonry|block|^plaster' then 'masonry'
    when p_category ~* 'smart.?home|home.?automation|automation|knx' then 'smarthome'
    when p_category ~* 'av.?system|audio.?visual|audio visual' then 'avsystems'
    when p_category ~* 'network|structured.?cabl' then 'networking'
    when p_category ~* 'signage|sign.?board|3d letter' then 'signage'
    when p_category ~* 'acrylic|perspex|plexiglass' then 'acrylic'
    when p_category ~* 'interior.?design' then 'interiordesign'
    when p_category ~* 'fit.?out' then 'fitout'
    when p_category ~* 'combined.?mep|^mep$|mep' then 'mep'
    when p_category ~* 'glass|glaz|alumin|curtain.?wall|shopfront|balustrad' then 'glazing'
    when p_category ~* 'joinery|kitchen|furniture|carpentr|cabinet|wardrobe|cupboard' then 'joinery'
    when p_category ~* 'hvac|^ac-|air.?con|duct|chiller|cooling|ac.?maintenance' then 'hvac'
    when p_category ~* 'electric|wiring|dewa' then 'electrical'
    when p_category ~* 'plumb|sanitary|drainage' then 'plumbing'
    when p_category ~* 'facade' then 'glazing'
    when p_category ~* 'clean|housekeep' then 'cleaning'
    when p_category ~* 'handyman' then 'handyman'
    when p_category ~* 'facilit|general.?service|miscellaneous|^other|^general' then 'general'
    else null end;
$function$


CREATE OR REPLACE FUNCTION public.fn_quote_structured_score(p_quote text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int; priced int; branded int; laboured int; spec_n int; q record; pts int:=0; miss text[]:='{}';
begin
  select count(*), count(*) filter (where unit_price is not null and unit_price>0),
         count(*) filter (where coalesce(brand,'')<>'' and coalesce(model,'')<>''),
         count(*) filter (where labour is not null or install is not null),
         count(*) filter (where coalesce(specification,'')<>'')
    into n, priced, branded, laboured, spec_n from quote_items where quote_id=p_quote;
  select * into q from quotes where id=p_quote::uuid;
  if n=0 then miss:=array_append(miss,'line_items');
  else pts:=pts+15; if priced=n then pts:=pts+20; else miss:=array_append(miss,'unit_prices_on_all_items'); end if; end if;
  if n>0 and branded=n then pts:=pts+15; else miss:=array_append(miss,'brand_model_per_item'); end if;
  if n>0 and spec_n>=greatest(1,n/2) then pts:=pts+10; else miss:=array_append(miss,'specifications'); end if;
  if laboured>0 then pts:=pts+10; else miss:=array_append(miss,'labour_or_installation'); end if;
  if coalesce(q.warranty,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'warranty'); end if;
  if coalesce(q.lead_time,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'lead_time'); end if;
  if coalesce(q.payment_terms,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'payment_terms'); end if;
  if coalesce(q.exclusions,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'exclusions'); end if;
  if coalesce(q.validity,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'validity'); end if;
  return jsonb_build_object('score',pts,'submittable',pts>=70,'items',n,'priced_items',priced,'missing',to_jsonb(miss),'scored_at',now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_recert_rotate()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_agent text; v_secret text;
begin
  perform fn_onboarding_ingest_runs();
  select agent_key into v_agent from org_onboarding
    order by coalesce(greatest(l1_at,l2_at,l3_at,l4_at), 'epoch'::timestamptz) asc limit 1;
  if v_agent is null then return jsonb_build_object('skipped','no onboarding records'); end if;
  select value into v_secret from app_secrets where key='inbound_secret';
  perform net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/canon_eval',
    body:=jsonb_build_object('__secret', v_secret, 'agent', v_agent, 'limit', 8),
    headers:='{"Content-Type":"application/json"}'::jsonb, timeout_milliseconds:=150000);
  return jsonb_build_object('examined', v_agent);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reconcile_doc_blocks(p_grace_days integer DEFAULT 0)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_lic_susp int := 0; v_ins_susp int := 0; v_restored int := 0;
  v_cut date := current_date - make_interval(days => p_grace_days);
  rec record;
begin
  -- ---- SUSPEND: trade licence expired -------------------------------------------------
  -- Only touches rows that are unblocked or already blocked for a document reason, so a
  -- manual block set by the team is never overwritten or silently cleared.
  for rec in
    select id, company_name, claimed_by, email, phone, whatsapp, license_expiry
      from leads
     where approval_status = 'approved' and coalesce(banned,false) = false
       and license_expiry is not null and license_expiry < v_cut
       and (coalesce(matching_blocked,false) = false
            or matching_block_reason in ('licence_expired','insurance_expired'))
       and coalesce(matching_block_reason,'') is distinct from 'licence_expired'
  loop
    update leads set matching_blocked = true, matching_block_reason = 'licence_expired'
     where id = rec.id;
    v_lic_susp := v_lic_susp + 1;
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('doc_suspended', coalesce(rec.claimed_by, rec.email), 'supplier', rec.id, 'email',
      'Your QuotesDone account is paused - trade licence expired',
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      'Your trade licence expired on ' || rec.license_expiry || ', so your account has been temporarily paused and you will not receive new customer requests until it is renewed.' || chr(10) || chr(10) ||
      'To restore your account: reply to this email with the renewed licence attached, or upload it in the Documents tab of your supplier portal. Your account is restored automatically as soon as we have a valid copy - nothing else is needed and no fee applies.',
      'queued');
  end loop;

  -- ---- SUSPEND: insurance expired -----------------------------------------------------
  for rec in
    select id, company_name, claimed_by, email, insurance_expiry
      from leads
     where approval_status = 'approved' and coalesce(banned,false) = false
       and insurance_expiry is not null and insurance_expiry < v_cut
       and (coalesce(matching_blocked,false) = false
            or matching_block_reason in ('licence_expired','insurance_expired'))
       and coalesce(matching_block_reason,'') is distinct from 'insurance_expired'
       -- a licence block is the more serious of the two, so do not downgrade its reason
       and coalesce(matching_block_reason,'') is distinct from 'licence_expired'
  loop
    update leads set matching_blocked = true, matching_block_reason = 'insurance_expired'
     where id = rec.id;
    v_ins_susp := v_ins_susp + 1;
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('doc_suspended', coalesce(rec.claimed_by, rec.email), 'supplier', rec.id, 'email',
      'Your QuotesDone account is paused - insurance expired',
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      'Your insurance certificate expired on ' || rec.insurance_expiry || ', so your account has been temporarily paused and you will not receive new customer requests until it is renewed.' || chr(10) || chr(10) ||
      'To restore your account: reply to this email with the renewed certificate attached, or upload it in the Documents tab of your supplier portal. Your account is restored automatically as soon as we have a valid copy.',
      'queued');
  end loop;

  -- ---- RESTORE: the blocking document is valid again -----------------------------------
  -- Only clears blocks this job set. A manual block stays put.
  for rec in
    select id, company_name, claimed_by, email, matching_block_reason
      from leads
     where matching_block_reason in ('licence_expired','insurance_expired')
       and ((matching_block_reason = 'licence_expired'
             and (license_expiry is null or license_expiry >= v_cut))
         or (matching_block_reason = 'insurance_expired'
             and (insurance_expiry is null or insurance_expiry >= v_cut)))
  loop
    update leads set matching_blocked = false, matching_block_reason = null where id = rec.id;
    v_restored := v_restored + 1;
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('doc_restored', coalesce(rec.claimed_by, rec.email), 'supplier', rec.id, 'email',
      'Your QuotesDone account is active again',
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      'Thank you - your documents are up to date and your account is active again. You will start receiving matching customer requests immediately.',
      'queued');
  end loop;

  return json_build_object('licence_suspended', v_lic_susp, 'insurance_suspended', v_ins_susp,
                           'restored', v_restored, 'grace_days', p_grace_days, 'ran_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_reconcile_licence_blocks(p_grace_days integer DEFAULT 0)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_suspended int; v_restored int;
begin
  -- Suspend approved, non-banned suppliers whose trade licence is expired (beyond grace),
  -- WITHOUT clobbering manual blocks (only touch rows that are unblocked or already licence-blocked).
  update leads set matching_blocked=true, matching_block_reason='licence_expired'
   where approval_status='approved' and coalesce(banned,false)=false
     and license_expiry is not null
     and license_expiry < (current_date - make_interval(days => p_grace_days))
     and (coalesce(matching_blocked,false)=false or matching_block_reason='licence_expired');
  get diagnostics v_suspended = row_count;
  -- Restore suppliers we auto-blocked once their licence is valid again (renewal-by-reply updates license_expiry).
  update leads set matching_blocked=false, matching_block_reason=null
   where matching_block_reason='licence_expired'
     and (license_expiry is null or license_expiry >= (current_date - make_interval(days => p_grace_days)));
  get diagnostics v_restored = row_count;
  return json_build_object('suspended', v_suspended, 'restored', v_restored, 'grace_days', p_grace_days, 'ran_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_refund_state(p_transaction uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t record; v_notify_days int; v_call_days int;
        v_responded boolean; v_notify_at timestamptz; v_call_at timestamptz; v_state text;
begin
  select * into t from transactions where id = p_transaction;
  if not found then return jsonb_build_object('error','transaction_not_found'); end if;

  v_notify_days := coalesce((select value::text::int from decision_policy where key='refund_notify_after_working_days'),1);
  v_call_days   := coalesce((select value::text::int from decision_policy where key='refund_call_after_working_days'),3);

  v_responded := t.supplier_ack_at is not null
    or exists (select 1 from messages m
               where m.inquiry_id = t.inquiry_id and m.supplier_id = t.supplier_id
                 and m.sender = 'supplier' and coalesce(m.blocked,false) = false
                 and m.created_at > t.revealed_at);

  v_notify_at := case when t.revealed_at is null then null
                      else public.fn_add_working_days(t.revealed_at, v_notify_days) end;
  -- the clock to a refund starts at the CUSTOMER's notice, never at the automatic nudge
  v_call_at   := case when t.customer_notified_at is null then null
                      else public.fn_add_working_days(t.customer_notified_at, v_call_days) end;

  v_state := case
    when t.revealed_at is null                              then 'not_revealed'
    when v_responded                                        then 'supplier_responded'
    when t.refund_status in ('approved','refunded')         then 'refunded'
    when t.customer_notified_at is null and now() < v_notify_at then 'waiting'
    when t.customer_notified_at is null                     then 'notify_available'
    when now() < v_call_at                                  then 'notified_waiting'
    else 'call_due' end;

  return jsonb_build_object(
    'transaction_id', t.id,
    'state', v_state,
    'revealed_at', t.revealed_at,
    'supplier_responded', v_responded,
    'notify_available_at', v_notify_at,
    'can_notify', v_state = 'notify_available',
    'notified_at', t.customer_notified_at,
    'auto_nudged_at', t.nudged_24_at,
    'founder_call_due_at', v_call_at,
    'refund_approvable', v_state = 'call_due',
    'refund_status', t.refund_status,
    'working_days_since_notice', case when t.customer_notified_at is null then 0
                                      else public.fn_working_days_between(t.customer_notified_at, now()) end
  );
end $function$


CREATE OR REPLACE FUNCTION public.fn_register_document(p_bucket text, p_path text, p_kind text, p_ref_table text, p_ref_id text, p_file_name text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_path is null or p_path = '' then return; end if;
  insert into public.documents(bucket,path,kind,ref_table,ref_id,file_name)
  values (p_bucket,p_path,p_kind,p_ref_table,p_ref_id, coalesce(p_file_name, split_part(p_path,'/',array_length(string_to_array(p_path,'/'),1))))
  on conflict (bucket,path) do nothing;
end $function$


CREATE OR REPLACE FUNCTION public.fn_report_flag(p_title text, p_risk text, p_rec text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not exists (
    select 1 from public.agent_actions
    where agent='reporting_ai' and kind='report_task' and title=p_title
      and status in ('pending','needs_review')
  ) then
    insert into public.agent_actions(agent, kind, status, risk, title, recommendation, created_at)
    values ('reporting_ai','report_task','needs_review',p_risk,p_title,p_rec, now());
  end if;
end $function$


CREATE OR REPLACE FUNCTION public.fn_report_generate(p_kind text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_title text; v_body text; v_kpis jsonb; v_sections jsonb; v_exec text; v_id bigint;
  j_deal jsonb; j_sup jsonb; j_fin jsonb; j_mkt jsonb; j_ops jsonb; j_cust jsonb; j_ai jsonb;
begin
  if p_kind = 'department' then
    select to_jsonb(k.*) into j_deal from public.crm_deal_kpis k limit 1;
    select to_jsonb(k.*) into j_sup  from public.supplier_kpis  k limit 1;
    select to_jsonb(k.*) into j_fin  from public.finance_kpis   k limit 1;
    select to_jsonb(k.*) into j_mkt  from public.marketing_kpis k limit 1;
    select to_jsonb(k.*) into j_ops  from public.ops_kpis       k limit 1;
    v_sections := jsonb_build_array(
      jsonb_build_object('heading','Sales & Pipeline','body', public.fn_kv_block(j_deal)),
      jsonb_build_object('heading','Supply',          'body', public.fn_kv_block(j_sup)),
      jsonb_build_object('heading','Finance',         'body', public.fn_kv_block(j_fin)),
      jsonb_build_object('heading','Marketing',       'body', public.fn_kv_block(j_mkt)),
      jsonb_build_object('heading','Operations',      'body', public.fn_kv_block(j_ops)));
    v_title := 'Department Report — '||to_char(now(),'YYYY-MM-DD');
    v_exec  := 'Cross-department KPI rollup: Sales/Pipeline, Supply, Finance, Marketing, Operations.';
    v_kpis  := jsonb_build_object('sales',j_deal,'supply',j_sup,'finance',j_fin,'marketing',j_mkt,'operations',j_ops);

  elsif p_kind = 'supplier' then
    select to_jsonb(k.*) into j_sup from public.supplier_kpis k limit 1;
    v_sections := jsonb_build_array(jsonb_build_object('heading','Supplier Base','body', public.fn_kv_block(j_sup)));
    v_title := 'Supplier Report — '||to_char(now(),'YYYY-MM-DD');
    v_exec  := 'Supplier base health, coverage and compliance snapshot.';
    v_kpis  := j_sup;

  elsif p_kind = 'customer' then
    select to_jsonb(k.*) into j_cust from public.customer_kpis k limit 1;
    v_sections := jsonb_build_array(jsonb_build_object('heading','Customer Base','body', public.fn_kv_block(j_cust)));
    v_title := 'Customer Report — '||to_char(now(),'YYYY-MM-DD');
    v_exec  := 'Customer base health, activity and retention snapshot.';
    v_kpis  := j_cust;

  elsif p_kind = 'ai' then
    j_ai := jsonb_build_object(
      'active_agents',     (select count(*) from public.category_agents where active),
      'actions_pending',   (select count(*) from public.agent_actions where status in ('pending','needs_review')),
      'actions_done_7d',   (select count(*) from public.agent_actions where status in ('done','auto_done') and created_at > now()-interval '7 days'),
      'actions_rejected_30d',(select count(*) from public.agent_actions where status='rejected' and created_at > now()-interval '30 days'),
      'avg_run_success_pct',(select round(avg(run_success_pct)::numeric,1) from public.ai_agent_quality),
      'total_open_escalations',(select coalesce(sum(open_escalations),0) from public.ai_agent_quality),
      'cron_jobs_active',  (select count(*) from cron.job where active),
      'cron_failures_24h', (select count(*) from cron.job_run_details where status='failed' and start_time > now()-interval '24 hours'));
    v_sections := jsonb_build_array(
      jsonb_build_object('heading','AI Agent Fleet','body', public.fn_kv_block(j_ai)),
      jsonb_build_object('heading','Latest Trainer Snapshot','body',
        public.fn_kv_block((select kpis from public.ai_trainer_snapshots order by created_at desc limit 1))));
    v_title := 'AI Report — '||to_char(now(),'YYYY-MM-DD');
    v_exec  := 'AI agent fleet activity, autonomy queue, training quality and automation health.';
    v_kpis  := j_ai;
  else
    raise exception 'unknown report kind: % (supported: department, supplier, customer, ai)', p_kind;
  end if;

  v_body := public.fn_report_skeleton(v_title, v_exec, v_sections, '[]'::jsonb, null);
  insert into public.board_reports(week_start, title, body, kpis, report_type, created_at)
    values (current_date, v_title, v_body, v_kpis, p_kind, now())
    returning id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_report_skeleton(p_title text, p_exec text, p_sections jsonb, p_decisions jsonb, p_appendix text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out text; s jsonb; d text; i int := 0;
begin
  out := p_title||E'\n'||repeat('=',length(p_title))||E'\n\n';
  out := out||'EXECUTIVE SUMMARY'||E'\n'||coalesce(p_exec,'—')||E'\n\n';
  for s in select * from jsonb_array_elements(coalesce(p_sections,'[]')) loop
     out := out||upper(coalesce(s->>'heading',''))||E'\n'||coalesce(s->>'body','')||E'\n\n';
  end loop;
  out := out||'DECISIONS REQUIRED'||E'\n';
  if jsonb_array_length(coalesce(p_decisions,'[]'))=0 then out := out||'None outstanding.'||E'\n';
  else for d in select jsonb_array_elements_text(p_decisions) loop i:=i+1; out := out||i||'. '||d||E'\n'; end loop; end if;
  if p_appendix is not null then out := out||E'\n'||'APPENDIX'||E'\n'||p_appendix||E'\n'; end if;
  return out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_reporting_ai()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k record; v_gen text[] := '{}'; v_flags int := 0; kind text;
begin
  -- Refresh the four agent-owned report types once per calendar day (no intra-day duplicates)
  foreach kind in array array['department','supplier','customer','ai'] loop
    if not exists (select 1 from public.board_reports where report_type=kind and created_at::date=current_date) then
      perform public.fn_report_generate(kind);
      v_gen := v_gen || kind;
    end if;
  end loop;

  select * into k from public.report_kpis;
  insert into public.report_kpi_snapshots(kpis) values (to_jsonb(k));

  -- Flag any scheduled report that is stale or missing (founder-visible, de-duped)
  if coalesce(k.daily_fresh,false) = false then
    perform public.fn_report_flag('Daily briefing is stale or missing','high',
      'No founder daily briefing in the last 36 hours — check the founder_brief_daily cron and fn_founder_brief.'); v_flags:=v_flags+1;
  end if;
  if coalesce(k.weekly_fresh,false) = false then
    perform public.fn_report_flag('Weekly board report overdue','medium',
      'No weekly board report in the last 8 days — check the board_report_weekly cron and fn_board_report.'); v_flags:=v_flags+1;
  end if;
  if coalesce(k.monthly_fresh,false) = false then
    perform public.fn_report_flag('Monthly report not generated this month','medium',
      'No monthly report for the current month yet — fn_monthly_report / monthly_report cron.'); v_flags:=v_flags+1;
  end if;
  if coalesce(k.quarterly_fresh,false) = false then
    perform public.fn_report_flag('Quarterly report missing','medium',
      'No quarterly report in the last ~95 days — run fn_quarterly_report() or check the quarterly_report cron.'); v_flags:=v_flags+1;
  end if;

  return jsonb_build_object('generated', to_jsonb(v_gen), 'new_flags', v_flags,
    'stale_count', k.stale_count, 'total_reports', k.total_reports, 'report_types', k.report_types);
end $function$


CREATE OR REPLACE FUNCTION public.fn_require_grounding(p_answer text, p_sources jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare grounded boolean:=false; reason text;
begin
  if p_sources is not null and jsonb_typeof(p_sources)='array' and jsonb_array_length(p_sources)>0 then
     grounded:=true; reason:='sources provided';
  elsif coalesce(p_answer,'') ~* '(per |according to|source:|standard |code |regulation|SIRA|DCD|ADCD|DEWA|Estidama|Al Sa|ESMA|ISO |IEC |BS |EN |NFPA|knowledge base|checklist)' then
     grounded:=true; reason:='inline citation detected';
  else reason:='no sources or citation — retrieve from knowledge base and cite before answering'; end if;
  return jsonb_build_object('grounded',grounded,'reason',reason);
end $function$


CREATE OR REPLACE FUNCTION public.fn_resilience_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_run bigint; v_owner text; v_secret text;
  v_base text := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/';
  v_email_backlog int := 0; v_prev_backlog int; v_flushed boolean := false;
  v_email_on text; v_stripe text; v_kill text;
  v_last_ops timestamptz; v_last_ai timestamptz; v_match_stuck int := 0;
  v_missing text[] := '{}'; k text; v_issues text := ''; v_heals int := 0; v_alerts int := 0;
  v_deduped boolean;
begin
  select value into v_secret from app_secrets where key='inbound_secret';
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';
  v_owner := coalesce(nullif(btrim(v_owner),''),'management@quotesdone.com');
  insert into agent_runs(agent,started_at) values('resilience_watch',clock_timestamp()) returning id into v_run;

  -- 1. EMAIL PIPELINE liveness + safe self-heal (idempotent flush; respects cap/suppressions).
  select value into v_email_on from app_secrets where key='email_enabled';
  select count(*) into v_email_backlog from notifications
    where channel='email' and coalesce(status,'queued') in ('queued','pending') and created_at < now()-interval '15 minutes';
  if v_email_backlog>0 and coalesce(v_email_on,'')='true' and v_secret is not null then
    perform net.http_post(url:=v_base||'send_outbox',
      headers:='{"Content-Type":"application/json"}'::jsonb,
      body:=jsonb_build_object('__secret',v_secret,'limit',50), timeout_milliseconds:=20000);
    v_flushed := true; v_heals := v_heals+1;
    select (counts->>'email_backlog')::int into v_prev_backlog from agent_runs
      where agent='resilience_watch' and id<>v_run order by id desc limit 1;
    if coalesce(v_prev_backlog,0)>0 then
      v_issues := v_issues||'- Email pipeline STUCK: '||v_email_backlog||' message(s) undelivered >15min despite auto-flush.'||E'\n';
    end if;
  end if;

  -- 2. CRITICAL credentials present (a missing one silently kills a whole flow).
  foreach k in array array['openrouter_api_key','resend_api_key','stripe_secret_key','inbound_secret'] loop
    if not exists(select 1 from app_secrets where key=k and value is not null and length(btrim(value))>0) then
      v_missing := array_append(v_missing,k);
    end if;
  end loop;
  if array_length(v_missing,1)>0 then
    v_issues := v_issues||'- CRITICAL credential(s) MISSING: '||array_to_string(v_missing,', ')||' — dependent flows are down.'||E'\n';
  end if;
  select left(value,8) into v_stripe from app_secrets where key='stripe_secret_key';
  if v_stripe is not null and v_stripe not like 'sk_live_%' then
    v_issues := v_issues||'- Stripe key is NOT live mode — payments will not settle.'||E'\n';
  end if;
  select value into v_kill from app_secrets where key='ai_kill_switch';
  if coalesce(v_kill,'')='true' then
    v_issues := v_issues||'- AI kill-switch is ON — every AI agent is paused.'||E'\n';
  end if;

  -- 3. SCHEDULER heartbeat via always-logging agents (catches a degraded pg_cron while it still partly runs).
  select max(started_at) into v_last_ops from agent_runs where agent='ops_watch' and started_at>now()-interval '4 hours';
  select max(started_at) into v_last_ai  from agent_runs where agent='ai_health' and started_at>now()-interval '4 hours';
  if v_last_ops is null or v_last_ops < now()-interval '90 minutes' then
    v_issues := v_issues||'- Ops-watch heartbeat stale (>90min) — the scheduler may be degraded.'||E'\n';
  end if;
  if v_last_ai is null or v_last_ai < now()-interval '45 minutes' then
    v_issues := v_issues||'- AI-health heartbeat stale (>45min) — the scheduler or AI monitor may be down.'||E'\n';
  end if;

  -- 4. MATCHING liveness: open inquiries with no shortlist after 6h.
  select count(*) into v_match_stuck from inquiries i
    where i.created_at between now()-interval '24 hours' and now()-interval '6 hours'
      and i.status not in ('completed','accepted','closed','cancelled','draft')
      and not exists(select 1 from inquiry_matches m where m.inquiry_id=i.id);
  if v_match_stuck>0 then
    v_issues := v_issues||'- '||v_match_stuck||' inquiry(ies) unmatched for >6h — the matcher may be stuck.'||E'\n';
  end if;

  -- ESCALATE: resilience failures would actually STOP the business, so page immediately
  -- (bypasses the Phase-B digest) — deduped to once per 3h via a silent marker row.
  if v_issues<>'' then
    select exists(select 1 from notifications where type='resilience_alert' and created_at>now()-interval '3 hours') into v_deduped;
    if not v_deduped and v_secret is not null then
      perform net.http_post(url:=v_base||'alert_founder',
        headers:='{"Content-Type":"application/json"}'::jsonb,
        body:=jsonb_build_object('__secret',v_secret,'event','Resilience: the platform needs attention',
          'level','critical','dedupe_key','resilience',
          'detail','The self-healing watchdog found issues it could not auto-fix:'||E'\n'||v_issues),
        timeout_milliseconds:=20000);
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('resilience_alert',v_owner,'admin','email','QuotesDone resilience: action needed',v_issues,'digested');
      v_alerts := v_alerts+1;
    end if;
  end if;

  update agent_runs set finished_at=clock_timestamp(),
    status=case when v_issues<>'' then 'error' else 'ok' end,
    counts=jsonb_build_object('email_backlog',v_email_backlog,'flushed',v_flushed,'heals',v_heals,'alerts',v_alerts,'has_issues',(v_issues<>'')),
    note=coalesce(nullif(v_issues,''),'all critical pipelines healthy')
    where id=v_run;
  return jsonb_build_object('ok',true,'email_backlog',v_email_backlog,'flushed',v_flushed,'issues',nullif(v_issues,''),'alerts',v_alerts);
end $function$


CREATE OR REPLACE FUNCTION public.fn_resolve_cat_agent(cat text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k text; c text := lower(trim(coalesce(cat,'')));
begin
  if c = '' then return null; end if;
  if exists(select 1 from category_agents where slug=c and coalesce(active,true)) then return 'cat:'||c; end if;
  if exists(select 1 from agent_knowledge where agent_key='cat:'||c limit 1) then return 'cat:'||c; end if;
  select 'cat:'||slug into k from category_agents
    where coalesce(active,true) and (lower(name) like '%'||c||'%' or c like '%'||slug||'%' or lower(name)=c)
    order by length(slug) desc limit 1;
  return k;
end $function$


CREATE OR REPLACE FUNCTION public.fn_review_decide(p_kind text, p_ref_id bigint, p_decision text, p_comment text DEFAULT NULL::text, p_by text DEFAULT 'founder'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare dec text := lower(coalesce(p_decision,'')); ok boolean := false;
begin
  if dec not in ('approve','changes','reject') then return jsonb_build_object('error','decision must be approve|changes|reject'); end if;

  if p_kind = 'marketing_post' then
    update content_drafts set
      review_status = case dec when 'approve' then 'approved' when 'changes' then 'changes_requested' else 'rejected' end,
      founder_comment = coalesce(p_comment, founder_comment), reviewed_at = now()
    where id = p_ref_id and status='draft';
    ok := found;
    -- On approve, social_stage will publish it live (gated by marketing_golive). On changes, the marketing loop revises it.

  elsif p_kind = 'refund' then
    update transactions set
      refund_status = case dec when 'approve' then 'approved' when 'reject' then 'declined' else 'requested' end,
      refund_note = coalesce(p_comment, refund_note),
      refund_resolved_at = case when dec in ('approve','reject') then now() else refund_resolved_at end
    where id = p_ref_id and refund_status='requested';
    ok := found;

  elsif p_kind = 'boost_budget' then
    update review_queue set
      status = case dec when 'approve' then 'approved' when 'changes' then 'changes_requested' else 'rejected' end,
      founder_comment = coalesce(p_comment, founder_comment), decided_at = now(), decided_by = p_by
    where id = p_ref_id and status='pending';
    ok := found;
  else
    return jsonb_build_object('error','unknown kind '||p_kind);
  end if;

  return jsonb_build_object('ok', ok, 'kind', p_kind, 'ref_id', p_ref_id, 'decision', dec);
end $function$


CREATE OR REPLACE FUNCTION public.fn_review_pending()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'marketing_posts', coalesce((select jsonb_agg(jsonb_build_object(
        'kind','marketing_post','ref_id',c.id,'title',c.title,'channel',c.channel,'body',c.body,'image_url',c.image_url,'created_at',c.created_at)
        order by c.created_at desc)
      from content_drafts c where c.status='draft' and coalesce(c.review_status,'pending')='pending'), '[]'::jsonb),
    'refunds', coalesce((select jsonb_agg(jsonb_build_object(
        'kind','refund','ref_id',t.id,'customer_id',t.customer_id,'reason',t.refund_reason,'requested_at',t.refund_requested_at)
        order by t.refund_requested_at desc)
      from transactions t where t.refund_status='requested'), '[]'::jsonb),
    'boost_budgets', coalesce((select jsonb_agg(jsonb_build_object(
        'kind','boost_budget','ref_id',r.id,'title',r.title,'summary',r.summary,'payload',r.payload,'created_at',r.created_at)
        order by r.created_at desc)
      from review_queue r where r.kind='boost_budget' and r.status='pending'), '[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_rfq_score(i inquiries)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare pts int:=0; miss text[]:='{}'; have text[]:='{}'; spectxt text;
begin
  spectxt := coalesce(i.spec::text,'');
  if coalesce(i.category,'')<>'' then pts:=pts+20; have:=array_append(have,'category'); else miss:=array_append(miss,'category'); end if;
  if coalesce(i.emirate,'')<>'' then pts:=pts+10; have:=array_append(have,'emirate'); else miss:=array_append(miss,'emirate'); end if;
  if length(regexp_replace(spectxt,'[^a-zA-Z0-9]','','g')) > 20 then pts:=pts+25; have:=array_append(have,'scope_detail'); else miss:=array_append(miss,'scope_detail'); end if;
  if coalesce(i.scope_type,'')<>'' then pts:=pts+15; have:=array_append(have,'scope_type'); else miss:=array_append(miss,'scope_type'); end if;
  if i.budget is not null then pts:=pts+15; have:=array_append(have,'budget'); else miss:=array_append(miss,'budget'); end if;
  if coalesce(array_length(i.trades,1),0)>0 or coalesce(i.drawing_file_path,'')<>'' or i.boq is not null then
     pts:=pts+15; have:=array_append(have,'supporting_detail'); else miss:=array_append(miss,'supporting_detail'); end if;
  return jsonb_build_object('score',pts,'ready',pts>=70,'have',to_jsonb(have),'missing',to_jsonb(miss),'scored_at',now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_role_of(p_email text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare e text := lower(trim(coalesce(p_email,''))); v_role text;
begin
  if e='' then return 'guest'; end if;
  select ur.role into v_role from user_roles ur where ur.email=e order by array_position(array['owner','admin','ops','finance','support','agent'],ur.role) limit 1;
  if v_role is not null then return v_role; end if;
  if e = any (string_to_array(lower(coalesce((select value from app_secrets where key='admin_emails'),'')),',')) then return 'owner'; end if;
  if exists(select 1 from leads where lower(coalesce(claimed_by,''))=e) then return 'supplier'; end if;
  if exists(select 1 from customers where lower(coalesce(email,''))=e) then return 'customer'; end if;
  return 'guest';
end $function$


CREATE OR REPLACE FUNCTION public.fn_rules_eval(p_ctx jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; matched jsonb:='[]'; reqs text[]:='{}'; ok boolean; k text; cond jsonb; want text; got text;
begin
  for r in select * from business_rules where active order by priority loop
    ok := true;
    for k in select jsonb_object_keys(r.when_json) loop
      cond := r.when_json->k;
      if jsonb_typeof(cond)='object' and cond ? 'gt' then
        if coalesce(nullif(p_ctx->>k,'')::numeric,0) <= (cond->>'gt')::numeric then ok:=false; end if;
      elsif jsonb_typeof(cond)='object' and cond ? 'gte' then
        if coalesce(nullif(p_ctx->>k,'')::numeric,0) < (cond->>'gte')::numeric then ok:=false; end if;
      elsif jsonb_typeof(cond)='object' and cond ? 'in' then
        if not (lower(coalesce(p_ctx->>k,'')) = any(select lower(jsonb_array_elements_text(cond->'in')))) then ok:=false; end if;
      else
        if lower(coalesce(p_ctx->>k,'')) <> lower(cond#>>'{}') then ok:=false; end if;
      end if;
      exit when not ok;
    end loop;
    if ok then
      matched := matched || jsonb_build_object('rule',r.name,'then',r.then_json);
      if r.then_json ? 'require' then
        reqs := reqs || array(select jsonb_array_elements_text(r.then_json->'require'));
      end if;
    end if;
  end loop;
  return jsonb_build_object('matched',matched,'required',to_jsonb((select array_agg(distinct x) from unnest(reqs) x)));
end $function$


CREATE OR REPLACE FUNCTION public.fn_run_vt()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_secret text; v_files jsonb;
begin
  select value into v_secret from app_secrets where key='inbound_secret';
  select coalesce(jsonb_agg(jsonb_build_object('bucket', o.bucket_id, 'path', o.name, 'size', coalesce((o.metadata->>'size')::bigint,0))), '[]'::jsonb)
    into v_files
  from (
    select bucket_id, name, metadata, created_at
    from storage.objects
    where bucket_id in ('quote-files','drawing-files','supplier-docs','receipt-files')
      and right(name,1) <> '/'
      and name not in (select path from vt_results where path is not null)
    order by created_at desc
    limit 4
  ) o;
  perform net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/vt_scan',
    body := jsonb_build_object('__secret', v_secret, 'files', v_files),
    headers := '{"Content-Type":"application/json"}'::jsonb
  );
end;$function$


CREATE OR REPLACE FUNCTION public.fn_scan_new_supplier_categories()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int:=0;
begin
  for r in
    select l.id, l.categories, l.services
    from leads l
    where l.source='self_registered'
      and coalesce(trim(l.categories),'')<>''
      and not exists (select 1 from category_agents a where a.active and a.slug=l.categories)
      -- not already handled: no provisioning card referencing this lead
      and not exists (
        select 1 from agent_actions aa
        where aa.kind='category_knowledge' and (aa.detail->>'lead_id')=l.id::text)
    limit 25
  loop
    perform public.fn_provision_category_call(r.categories, r.id, r.services);
    n := n + 1;
  end loop;
  return jsonb_build_object('ran_at',now(),'dispatched',n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_security_ai()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k record; v_score numeric; n int;
begin
  select * into k from security_kpis;
  v_score := round(greatest(0, 100
    - (100-coalesce(k.rls_coverage_pct,100))
    - coalesce(k.secdef_mutable_searchpath,0)*4
    - coalesce(k.high_sev_events_7d,0)*12
    - coalesce(k.open_fraud_flags,0)*6
    - (case when coalesce(k.errors_24h,0)>200 then 10 when coalesce(k.errors_24h,0)>50 then 5 else 0 end)
    - (case when coalesce(k.failed_logins_7d,0)>50 then 10 else 0 end)),1);
  insert into security_kpi_snapshots(snapshot_date,kpis) values (current_date, to_jsonb(k)||jsonb_build_object('security_score',v_score))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();
  perform sec_incident('rls_gap', coalesce(k.rls_coverage_pct,100) < 100, 'high', 'RLS coverage gap',
    'Row-Level Security is not enabled on every public table ('||k.rls_coverage_pct||'%). The auto-RLS trigger should prevent this — investigate immediately.');
  perform sec_incident('mutable_searchpath', coalesce(k.secdef_mutable_searchpath,0) > 0, 'medium', 'Functions with mutable search_path',
    k.secdef_mutable_searchpath||' SECURITY DEFINER function(s) do not pin search_path — a privilege-escalation risk. Pin search_path on each.');
  perform sec_incident('high_sev_events', coalesce(k.high_sev_events_7d,0) > 0, 'high', 'High-severity security events',
    k.high_sev_events_7d||' high/critical security event(s) in the last 7 days (malware/dangerous uploads etc.). Review and quarantine.');
  perform sec_incident('open_fraud', coalesce(k.open_fraud_flags,0) > 0, 'high', 'Open fraud flags',
    k.open_fraud_flags||' unresolved fraud flag(s). Review the flagged accounts/transactions.');
  perform sec_incident('error_spike', coalesce(k.errors_24h,0) > 200, 'medium', 'Application error spike',
    k.errors_24h||' application errors in 24h — investigate for abuse or a fault.');
  perform sec_incident('failed_login_spike', coalesce(k.failed_logins_7d,0) > 50, 'high', 'Failed-login spike',
    k.failed_logins_7d||' failed logins in 7 days — possible credential-stuffing/brute force. Consider rate-limiting/MFA.');
  perform sec_incident('auth_hardening', true, 'low', 'Auth hardening review',
    'Confirm in Supabase Auth settings: leaked-password protection ON, MFA enforced for admin, sensible OTP expiry, least-privilege API keys.');
  select count(*) into n from agent_actions where agent='security_ai' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'security_score',v_score,'kpis',to_jsonb(k),'open_incidents',n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_security_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_old jsonb; v_new jsonb; v_pk text;
begin
  v_old := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;
  v_new := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end;
  if tg_table_name = 'app_secrets' then
    if v_old ? 'value' then v_old := jsonb_set(v_old, '{value}', '"***REDACTED***"'); end if;
    if v_new ? 'value' then v_new := jsonb_set(v_new, '{value}', '"***REDACTED***"'); end if;
  end if;
  v_pk := coalesce(v_new->>'id', v_old->>'id', v_new->>'key', v_old->>'key',
                   v_new->>'name', v_old->>'name', v_new->>'role', v_old->>'role');
  insert into public.security_audit_log(action, table_name, row_pk, old_data, new_data)
  values (tg_op, tg_table_name, v_pk, v_old, v_new);
  return coalesce(new, old);
end $function$


CREATE OR REPLACE FUNCTION public.fn_security_audit_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  raise exception 'security_audit_log is append-only; % is not permitted', tg_op;
end $function$


CREATE OR REPLACE FUNCTION public.fn_security_scan()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_run bigint; v_scanned int := 0; v_susp int := 0; v_high int := 0; v_viol int; v_banned int; v_owner text;
  r record; v_path text; v_sev text; v_why text; v_size bigint; v_mime text;
begin
  insert into agent_runs(agent, started_at) values ('security', now()) returning id into v_run;
  for r in
    select bucket_id, name, coalesce((metadata->>'size')::bigint,0) as size, coalesce(metadata->>'mimetype','') as mime
    from storage.objects
    where bucket_id in ('quote-files','drawing-files','supplier-docs')   -- receipt-files removed: system/owner-generated, not a threat surface
    order by created_at desc limit 400
  loop
    v_path := r.name; if v_path is null or v_path = '' or right(v_path,1) = '/' then continue; end if;
    v_scanned := v_scanned + 1; v_size := r.size; v_mime := r.mime; v_sev := null; v_why := null;
    if v_path ~* '\.[a-z0-9]{2,5}\.(exe|js|scr|bat|html?|svg|hta)$' then v_sev := 'high'; v_why := 'double extension';
    elsif v_path ~* '\.(exe|bat|cmd|com|scr|msi|ps1|vbs|js|jar|sh|apk|dll|hta|wsf|docm|xlsm|pptm|iso|img)$' then v_sev := 'high'; v_why := 'dangerous file type';
    elsif v_path ~* '\.(html?|svg)$' then v_sev := 'high'; v_why := 'active-content file';
    elsif v_size > 30*1024*1024 then v_sev := 'medium'; v_why := 'oversized';
    end if;
    -- dedupe: only flag a file the FIRST time it is seen
    if v_sev is not null and not exists (select 1 from security_events se where se.kind='suspicious_upload' and se.subject=left(v_path,200)) then
      v_susp := v_susp + 1;
      insert into security_events(kind,severity,source,subject,detail) values ('suspicious_upload',v_sev,r.bucket_id,left(v_path,200),jsonb_build_object('mime',v_mime,'size',v_size,'why',v_why));
      if v_sev = 'high' then
        v_high := v_high + 1;
        insert into agent_actions(agent,kind,status,risk,title,recommendation,target_table,detail)
        values ('security','security_alert','pending','high','Suspicious upload ('||v_why||'): '||left(v_path,80),'inspect/remove the file in storage; do NOT open it directly','security_events',jsonb_build_object('bucket',r.bucket_id,'path',v_path,'why',v_why,'size',v_size));
      end if;
    end if;
  end loop;
  select count(*) into v_viol from chat_violations where created_at >= now()-interval '7 days';
  select (select count(*) from leads where banned=true)+(select count(*) from customers where banned=true) into v_banned;
  if v_viol > 0 then insert into security_events(kind,severity,source,subject,detail) values ('contact_disclosure','medium','chat',v_viol||' contact-sharing attempt(s) in 7d',jsonb_build_object('count',v_viol)); end if;
  if v_susp > 0 then
    select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';
    insert into notifications(type,to_email,to_role,channel,subject,body) values ('security_alert',coalesce(v_owner,'management@quotesdone.com'),'admin','email','QuotesDone security: '||v_susp||' suspicious file(s) flagged','The Security agent flagged '||v_susp||' newly uploaded file(s) ('||v_high||' high-severity). Open the Security agent in admin. Do not open flagged files directly.');
  end if;
  update agent_runs set finished_at=now(), status='ok', counts=jsonb_build_object('scanned',v_scanned,'suspicious',v_susp,'high',v_high,'violations7d',v_viol,'banned',v_banned) where id=v_run;
end;$function$


CREATE OR REPLACE FUNCTION public.fn_security_selfaudit()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_rls_off int; v_no_pol int; v_secviews int; v_secfns int;
        v_anon_tbl int; v_anon_views int; v_anon_defaults int; v_drift text[];
begin
  select count(*) into v_rls_off from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and not c.relrowsecurity;
  select count(*) into v_no_pol from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and c.relrowsecurity
      and not exists (select 1 from pg_policy p where p.polrelid=c.oid);
  select count(*) into v_secviews from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='v'
      and not (coalesce(c.reloptions,'{}') @> array['security_invoker=on'] or coalesce(c.reloptions,'{}') @> array['security_invoker=true']);
  select count(*) into v_secfns from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef and has_function_privilege('anon', p.oid, 'EXECUTE');
  -- allowlist: category_specs (open reference data) + blog_posts (public blog; RLS limits to published=true)
  select count(*) into v_anon_tbl from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and c.relname not in ('category_specs','blog_posts')
      and (has_table_privilege('anon',c.oid,'SELECT') or has_table_privilege('authenticated',c.oid,'SELECT'));
  select count(*) into v_anon_views from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind in ('v','m')
      and (has_table_privilege('anon',c.oid,'SELECT') or has_table_privilege('authenticated',c.oid,'SELECT'));
  select count(*) into v_anon_defaults from pg_default_acl d
    where d.defaclnamespace='public'::regnamespace and d.defaclrole='postgres'::regrole
      and (d.defaclacl::text like '%anon=%' or d.defaclacl::text like '%authenticated=%');

  insert into public.security_selfaudit_snapshots
    (rls_disabled_tables,rls_no_policy,secdef_views,secdef_fns_anon,anon_tables,anon_views,anon_defaults)
    values (v_rls_off, v_no_pol, v_secviews, v_secfns, v_anon_tbl, v_anon_views, v_anon_defaults);

  v_drift := array[]::text[];
  if v_rls_off       > 0 then v_drift := v_drift || ('rls_disabled_tables='||v_rls_off); end if;
  if v_anon_views    > 0 then v_drift := v_drift || ('anon_readable_views='||v_anon_views); end if;
  if v_anon_tbl      > 0 then v_drift := v_drift || ('anon_readable_tables='||v_anon_tbl); end if;
  if v_secfns        > 0 then v_drift := v_drift || ('anon_executable_secdef_fns='||v_secfns); end if;
  if v_anon_defaults > 0 then v_drift := v_drift || ('anon_default_privileges_postgres='||v_anon_defaults); end if;

  if array_length(v_drift,1) is not null then
    insert into public.security_events(kind,severity,source,subject,detail)
      values ('anon_exposure_drift','high','selfaudit','public schema',
              jsonb_build_object('drift',v_drift,'note','Anonymity-by-construction invariant broke: something in public is reachable by anon/authenticated beyond category_specs + blog_posts(published). See docs/upgrade/hotfix-2026-07-19.'));
    insert into public.founder_alerts(level,event,detail,channel)
      values ('high','Security drift: public data reachable by anon',
              'Daily self-audit found: '||array_to_string(v_drift,', ')||'. Anon/authenticated should only reach category_specs and published blog_posts. Review recent migrations/views/grants (see the 2026-07-19 hotfix).','selfaudit');
  end if;

  return jsonb_build_object('rls_disabled_tables',v_rls_off,'rls_no_policy',v_no_pol,'secdef_views',v_secviews,
    'secdef_fns_anon',v_secfns,'anon_tables',v_anon_tbl,'anon_views',v_anon_views,'anon_defaults',v_anon_defaults,'drift',v_drift);
end $function$


CREATE OR REPLACE FUNCTION public.fn_should_escalate(ctx jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  reasons text[] := '{}';
  conf_min numeric; fin_review numeric; auto_max numeric; fraud_max numeric;
  legal jsonb; sens jsonb; owner text;
  c_conf numeric := nullif(ctx->>'confidence','')::numeric;
  c_amt  numeric := nullif(ctx->>'amount_aed','')::numeric;
  c_fraud numeric := nullif(ctx->>'fraud_score','')::numeric;
  c_cat  text := lower(coalesce(ctx->>'category',''));
  c_txt  text := lower(coalesce(ctx->>'text',''));
  c_money boolean := coalesce((ctx->>'moves_money')::boolean,false);
  trg text;
begin
  select value::numeric into conf_min   from decision_policy where key='confidence_min';
  select value::numeric into fin_review  from decision_policy where key='financial_review_aed';
  select value::numeric into auto_max    from decision_policy where key='auto_action_max_aed';
  select value::numeric into fraud_max   from decision_policy where key='fraud_score_max';
  select value into legal                from decision_policy where key='legal_triggers';
  select value into sens                 from decision_policy where key='sensitive_categories';
  select value #>> '{}' into owner       from decision_policy where key='review_owner';

  if c_conf is not null and c_conf < conf_min then
     reasons := array_append(reasons, 'confidence '||round(c_conf,2)::text||' < min '||round(conf_min,2)::text); end if;
  if c_amt is not null and c_amt >= fin_review then
     reasons := array_append(reasons, 'amount AED '||c_amt::text||' >= review threshold '||fin_review::text); end if;
  if c_money and (c_amt is null or c_amt > auto_max) then
     reasons := array_append(reasons, 'action moves money beyond autonomous limit'); end if;
  if c_fraud is not null and c_fraud >= fraud_max then
     reasons := array_append(reasons, 'fraud score '||round(c_fraud,2)::text||' >= max '||round(fraud_max,2)::text); end if;
  if c_cat <> '' and sens ? c_cat and (c_conf is null or c_conf < conf_min) then
     reasons := array_append(reasons, 'sensitive category "'||c_cat||'" with low/absent confidence'); end if;
  for trg in select jsonb_array_elements_text(legal) loop
     if c_txt <> '' and position(trg in c_txt) > 0 then
        reasons := array_append(reasons, 'legal trigger: "'||trg||'"'); end if;
  end loop;

  return jsonb_build_object(
    'escalate', array_length(reasons,1) is not null,
    'reasons', to_jsonb(reasons),
    'route_to', owner);
end $function$


CREATE OR REPLACE FUNCTION public.fn_simulate(p_scenario jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  typ text := coalesce(p_scenario->>'type','');
  aov numeric; cur_fee numeric; suppliers int; deals_pm numeric; res jsonb; conf text; assum jsonb;
begin
  select round(avg(quote_amount),0) into aov from quotes where quote_amount is not null and quote_amount>0;
  aov := coalesce(aov, 45000);  -- fallback UAE mid-size job
  begin select coalesce((value->>'reveal_pct')::numeric, 3)/100 into cur_fee from pricing_config limit 1; exception when others then cur_fee:=0.03; end;
  cur_fee := coalesce(cur_fee,0.03);
  select count(*) into suppliers from leads where coalesce(approval_status,'')='approved';
  deals_pm := coalesce((p_scenario->>'deals_per_month')::numeric, 100);  -- modelled target if provided, else 100

  if typ='fee_change' then
    declare new_fee numeric := coalesce((p_scenario->>'new_fee_pct')::numeric,4)/100; elasticity numeric := 0.6; drop_pct numeric;
    begin
      drop_pct := greatest(0, (new_fee-cur_fee)/nullif(cur_fee,0)) * elasticity;   -- higher fee -> fewer reveals
      res := jsonb_build_object(
        'current_fee_pct', round(cur_fee*100,2), 'new_fee_pct', round(new_fee*100,2),
        'assumed_deals_per_month', deals_pm, 'avg_job_aed', aov,
        'reveal_volume_change_pct', round(-drop_pct*100,1),
        'projected_monthly_revenue_aed', round(deals_pm*(1-drop_pct)*aov*new_fee),
        'projected_annual_revenue_aed', round(12*deals_pm*(1-drop_pct)*aov*new_fee),
        'vs_current_fee_annual_aed', round(12*deals_pm*aov*(new_fee*(1-drop_pct) - cur_fee)));
      assum := jsonb_build_array('Demand elasticity 0.6 (a fee rise reduces reveals proportionally)','Deals/month is a modelled target, not current run-rate','Average job value from live quote data with fallback');
      conf := 'low'; end;

  elsif typ='supply_double' then
    declare qpr_now numeric; qpr_new numeric;
    begin
      select round(avg(qc),1) into qpr_now from (select count(*) qc from quotes q join inquiries i on i.id=q.inquiry_id group by q.inquiry_id) z;
      qpr_now := coalesce(qpr_now,1.5); qpr_new := least(qpr_now*1.6, 6);   -- more supply -> more quotes/RFQ, capped
      res := jsonb_build_object(
        'approved_suppliers_now', suppliers, 'approved_suppliers_after', suppliers*2,
        'quotes_per_rfq_now', qpr_now, 'quotes_per_rfq_after', qpr_new,
        'expected_conversion_uplift_pct', round((qpr_new-qpr_now)/nullif(qpr_now,0)*25,1),
        'note', 'More competitive quotes per RFQ typically lifts buyer conversion and win rates.');
      assum := jsonb_build_array('Quotes/RFQ scales ~0.6x with supply, capped at 6','Conversion uplift ~25% of the quotes/RFQ uplift');
      conf := 'low'; end;

  elsif typ='new_market' then
    declare market text := coalesce(p_scenario->>'market','KSA'); pen numeric := coalesce((p_scenario->>'penetration_pct')::numeric,0.5)/100; tam numeric := coalesce((p_scenario->>'annual_market_aed')::numeric, 5000000000);
    begin
      res := jsonb_build_object('market',market,'assumed_annual_procurement_aed',tam,'assumed_penetration_pct',round(pen*100,3),
        'gmv_captured_aed', round(tam*pen), 'platform_revenue_aed', round(tam*pen*cur_fee),
        'note','Rough top-down sizing; requires local supply activation, licensing and compliance before any revenue.');
      assum := jsonb_build_array('Top-down TAM * penetration (very rough)','Same fee applies','Ignores CAC, localisation and regulatory cost/time');
      conf := 'very low'; end;
  else
    res := jsonb_build_object('error','unknown scenario type; use fee_change | supply_double | new_market');
    assum := '[]'; conf := 'n/a';
  end if;

  res := res || jsonb_build_object('confidence',conf,'assumptions',assum,'basis','modelled — QuotesDone is pre-traction, so treat all figures as directional, not forecasts.','computed_at',now());
  insert into simulations(scenario,result) values(p_scenario,res);
  return res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_sla_watch()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_hours int;
  v_admin text;
  v_flagged int := 0;
  r record;
begin
  v_hours := coalesce((select nullif(value,'')::int from app_secrets where key='sla_quote_hours'), 24);
  v_admin := coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'), 'management@quotesdone.com');
  for r in
    select i.id, i.category, i.emirate, i.created_at
    from inquiries i
    where i.status = 'sent'
      and i.created_at < (now() - make_interval(hours => v_hours))
      and coalesce(i.scope_type,'') <> 'combined'
      and not exists (
        select 1 from quotes q where q.inquiry_id = i.id
          and coalesce(q.status,'') not in ('draft','rejected','void','cancelled'))
      and not exists (
        select 1 from founder_alerts fa where fa.event='rfq_sla_breach'
          and fa.detail like ('%inquiry '||i.id||':%')
          and fa.created_at > (now() - interval '48 hours'))
    order by i.created_at asc
    limit 50
  loop
    insert into founder_alerts(level, event, detail, channel)
      values('warn','rfq_sla_breach',
        'inquiry '||r.id||': no supplier quote after '||v_hours||'h ('||coalesce(r.category,'?')||' / '||coalesce(r.emirate,'?')||'). Widen the pool or recruit this category.',
        'system');
    insert into notifications(type, to_email, to_role, channel, subject, body, status)
      values('rfq_sla_breach', v_admin, 'admin', 'email',
        'RFQ past SLA — no quotes yet',
        'Inquiry #'||r.id||' ('||coalesce(r.category,'?')||' in '||coalesce(r.emirate,'?')||') has had NO supplier quote for over '||v_hours||' hours. Consider widening the emirate/trade or recruiting suppliers in this category. Open it in the OS to re-dispatch.',
        'queued');
    v_flagged := v_flagged + 1;
  end loop;
  return json_build_object('sla_hours', v_hours, 'flagged', v_flagged, 'ran_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_smoke()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_run bigint; v_owner text; v jsonb:='[]'::jsonb; v_fail int:=0; v_sig text;
  a int; b int; c int; d int; e int;
begin
  insert into agent_runs(agent,started_at) values('smoke',now()) returning id into v_run;
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';

  select count(*) into a from quotes q where q.status='revealed' and not exists(select 1 from transactions t where t.quote_id=q.id);
  if a>0 then v:=v||jsonb_build_object('check','revealed_quote_without_transaction','count',a); v_fail:=v_fail+1; end if;

  select count(*) into b from transactions where fee_status='paid' and coalesce(reveal_fee,0)<=0;
  if b>0 then v:=v||jsonb_build_object('check','paid_tx_zero_fee','count',b); v_fail:=v_fail+1; end if;

  select count(*) into c from notifications where status='queued' and channel<>'portal' and created_at < now()-interval '2 hours';
  if c>0 then v:=v||jsonb_build_object('check','email_backlog_stuck','count',c); v_fail:=v_fail+1; end if;

  select count(*) into d from supplier_dues where coalesce(amount_due,0)<0 or amount_due is null;
  if d>0 then v:=v||jsonb_build_object('check','bad_due_amount','count',d); v_fail:=v_fail+1; end if;

  select count(*) into e from inquiries i where i.status='revealed' and not exists(select 1 from transactions t where t.inquiry_id=i.id);
  if e>0 then v:=v||jsonb_build_object('check','revealed_inquiry_without_tx','count',e); v_fail:=v_fail+1; end if;

  if v_fail>0 then
    insert into error_events(source,kind,severity,detail) values('smoke','integrity_violation','high',v);
    select coalesce(string_agg(x->>'check', ',' order by x->>'check'),'') into v_sig from jsonb_array_elements(v) x;
    if v_owner is not null and not exists(
         select 1 from notifications where type='smoke_alert'
           and created_at >= now() - interval '24 hours'
           and body like '%[sig:'||v_sig||']%') then
      insert into notifications(type,to_email,to_role,channel,subject,body)
        values('smoke_alert',v_owner,'admin','email','QuotesDone: data-integrity check failed',
          v_fail||' integrity check(s) failed: '||v::text||'. This usually means a recent change broke a write path. Open the IT agent. [sig:'||v_sig||']');
    end if;
  end if;
  update agent_runs set finished_at=now(),status='ok',counts=jsonb_build_object('checks',5,'failures',v_fail,'detail',v) where id=v_run;
  return jsonb_build_object('checks',5,'failures',v_fail,'detail',v);
end; $function$


CREATE OR REPLACE FUNCTION public.fn_split_inquiry(p_parent uuid, p_trades text[])
 RETURNS TABLE(child_id uuid, trade text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p record; t text; new_id uuid; label text;
begin
  select * into p from public.inquiries where id = p_parent;
  if not found then raise exception 'inquiry % not found', p_parent; end if;
  if coalesce(array_length(p_trades,1),0) < 2 then raise exception 'split needs at least 2 trades'; end if;

  -- idempotent: never split the same parent twice
  if exists (select 1 from public.inquiries where parent_inquiry_id = p_parent) then
    return query select i.id, coalesce(i.trades[1], i.category) from public.inquiries i where i.parent_inquiry_id = p_parent;
    return;
  end if;

  foreach t in array p_trades loop
    select coalesce(tt.label, t) into label from public.taxonomy_trade tt where tt.code = t;
    insert into public.inquiries (
      customer_id, category, emirate, role_needed, raw_input, spec, summary, keywords,
      status, boq, budget, scope_type, trades, brief_source, drawing_file_path, drawing_file_name,
      drawing_redacted_paths, urgency, project_id, parent_inquiry_id, completeness, rfq_ready, provenance
    ) values (
      p.customer_id, t, p.emirate, p.role_needed, p.raw_input, p.spec,
      coalesce(label,t) || ' — ' || coalesce(p.summary, 'part of a combined request'),
      p.keywords, 'new', p.boq, p.budget, 'single', array[t], p.brief_source,
      p.drawing_file_path, p.drawing_file_name, p.drawing_redacted_paths, p.urgency,
      p.project_id, p_parent, p.completeness, false,
      coalesce(p.provenance,'{}'::jsonb) || jsonb_build_object('split_from', p_parent, 'split_trade', t, 'split_at', now())
    ) returning id into new_id;
    child_id := new_id; trade := t; return next;
  end loop;

  -- parent becomes the grouping record only: never dispatched itself
  update public.inquiries
     set scope_type = 'multi',
         trades = p_trades,
         rfq_ready = false,
         status = 'split',
         routing = coalesce(routing,'{}'::jsonb) || jsonb_build_object(
                     'outcome','split_by_trade','split_at',now(),'split_trades',to_jsonb(p_trades))
   where id = p_parent;
end $function$


CREATE OR REPLACE FUNCTION public.fn_strategy_ai()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k record; r record; v_recs int := 0;
begin
  perform public.fn_strategy_scan();               -- refresh internal risk signals
  select * into k from public.strategy_kpis;
  insert into public.strategy_kpi_snapshots(kpis) values (to_jsonb(k));

  -- Recommend on material open risks (score >= 12)
  for r in select category,title,score,mitigation from public.strategy_risks
           where status='open' and score >= 12 order by score desc loop
    perform public.fn_strategy_rec('Strategic risk: '||r.title,
      case when r.score>=16 then 'high' else 'medium' end,
      '['||upper(r.category)||' · risk score '||r.score||'/25] '||coalesce(r.mitigation,'Review and decide a mitigation.'));
    v_recs := v_recs + 1;
  end loop;

  -- Expansion signal: under-supplied high-demand categories
  if coalesce(k.under_supplied_categories,0) > 0 then
    perform public.fn_strategy_rec('Expansion: recruit suppliers in under-supplied categories','medium',
      k.under_supplied_categories||' categories have demand outstripping supplier coverage. Targeted supplier acquisition here is the highest-ROI growth lever — see the Marketplace supply-gap list.');
  end if;

  -- Pricing: standing review of the reveal fee vs average job value (recommend, never change)
  perform public.fn_strategy_rec('Pricing review: reveal fee vs average job value','low',
    'Periodically re-test the reveal fee and supplier registration pricing against average job value and willingness-to-pay. Use fn_simulate to model options before any change — pricing changes stay a founder decision.');

  -- Market intelligence gap
  if coalesce(k.competitor_intel,0) = 0 then
    perform public.fn_strategy_rec('Add a competitor / market-intelligence source','medium',
      'No competitor records on file (market_intel is empty). Connect a web-research or market-data source, or add competitors manually, so positioning, pricing and expansion calls are evidence-based rather than assumed.');
  end if;

  return jsonb_build_object('open_risks',k.open_risks,'top_risk',k.top_risk,'top_risk_score',k.top_risk_score,
    'new_or_open_recs', v_recs, 'competitor_intel', k.competitor_intel, 'under_supplied', k.under_supplied_categories);
end $function$


CREATE OR REPLACE FUNCTION public.fn_strategy_metrics()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare res jsonb;
begin
  with dem as (select category, count(*) rfqs from inquiries where created_at > now()-interval '90 days' and category is not null group by category),
  sup as (select i.category, count(distinct q.supplier_id) sups from quotes q join inquiries i on i.id=q.inquiry_id where q.created_at > now()-interval '90 days' and i.category is not null group by i.category)
  select jsonb_build_object(
    'under_supplied', (select coalesce(jsonb_agg(x order by x.rfqs desc),'[]'::jsonb) from (
        select d.category, d.rfqs, coalesce(s.sups,0) as active_suppliers
        from dem d left join sup s on s.category=d.category
        where coalesce(s.sups,0) < greatest(2, d.rfqs/3) order by d.rfqs desc limit 12) x),
    'coverage', jsonb_build_object(
        'categories_total', (select count(*) from category_specs),
        'with_requirements', (select count(*) from category_specs where supplier_requirements is not null),
        'with_playbook', (select count(distinct category) from qualification_playbooks where status='active'),
        'regulation_category_tags', (select count(distinct c) from regulations r, unnest(coalesce(r.categories,'{}')) c where r.status='active')),
    'funnel', (select coalesce(fn_marketplace_analytics(),'{}'::jsonb))
  ) into res;
  return res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_strategy_rec(p_title text, p_risk text, p_rec text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not exists (
    select 1 from public.agent_actions
    where agent='strategy_ai' and kind='strategy_rec' and title=p_title and status in ('pending','needs_review')
  ) then
    insert into public.agent_actions(agent,kind,status,risk,title,recommendation,created_at)
    values ('strategy_ai','strategy_rec','needs_review',p_risk,p_title,p_rec, now());
  end if;
end $function$


CREATE OR REPLACE FUNCTION public.fn_strategy_risk(p_cat text, p_title text, p_like integer, p_impact integer, p_mit text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  insert into public.strategy_risks(category,title,likelihood,impact,mitigation)
  values (p_cat,p_title, greatest(1,least(5,p_like)), greatest(1,least(5,p_impact)), p_mit)
  on conflict (category,title) do update
    set likelihood=excluded.likelihood, impact=excluded.impact, mitigation=excluded.mitigation, updated_at=now();
end $function$


CREATE OR REPLACE FUNCTION public.fn_strategy_scan()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_active int; v_top_share numeric; v_under int; v_cash numeric; v_burn numeric; v_rev numeric; v_intel int; v_risks int;
begin
  select count(distinct supplier_id) into v_active from public.quotes
    where created_at > now()-interval '90 days' and supplier_id is not null;
  select round(100.0*max(c)/nullif(sum(c),0),1) into v_top_share from (
    select supplier_id, count(*) c from public.quotes
    where created_at > now()-interval '90 days' and supplier_id is not null group by supplier_id) s;
  select jsonb_array_length(coalesce(fn_strategy_metrics()->'under_supplied','[]'::jsonb)) into v_under;
  select cash, monthly_burn, revenue_30d into v_cash, v_burn, v_rev from public.finance_kpis;
  select count(*) into v_intel from public.market_intel where kind='competitor' and status<>'dismissed';

  -- Supplier concentration / thin marketplace
  if coalesce(v_active,0) < 5 then
    perform public.fn_strategy_risk('supply','Thin supplier base — marketplace liquidity risk',
      case when coalesce(v_active,0)<=2 then 5 else 4 end, 4,
      'Recruit suppliers across active categories; a marketplace with <5 active suppliers cannot reliably fulfil demand or sustain competitive quoting.');
  end if;
  if coalesce(v_top_share,0) >= 50 then
    perform public.fn_strategy_risk('concentration','Supplier concentration — one supplier dominates quoting',
      4, 4, 'One supplier accounts for '||v_top_share||'% of recent quotes. Diversify to reduce dependency and pricing power imbalance.');
  end if;
  -- Demand not being served
  if coalesce(v_under,0) > 0 then
    perform public.fn_strategy_risk('market','Under-supplied high-demand categories',
      4, 3, v_under||' categories have demand outstripping supplier coverage — targeted supplier acquisition converts lost RFQs into revenue.');
  end if;
  -- Cash / runway
  if coalesce(v_cash,0) <= 0 then
    perform public.fn_strategy_risk('financial','Negative cash position',
      4, 5, 'Cash position is '||coalesce(v_cash,0)||' AED. Prioritise fee collection, control burn, and validate the monetisation model before scaling spend.');
  elsif v_burn is not null and v_burn > 0 and v_cash/v_burn < 6 then
    perform public.fn_strategy_risk('financial','Short cash runway (<6 months)',
      3, 5, 'At current burn the runway is under 6 months. Extend runway via revenue, cost control, or funding before committing to expansion.');
  end if;
  -- Early-stage revenue scale
  if coalesce(v_rev,0) < 5000 then
    perform public.fn_strategy_risk('market','Pre-scale revenue — monetisation unproven',
      3, 4, 'Monthly revenue is still small; validate willingness-to-pay on the reveal fee and supplier registration before heavy growth investment.');
  end if;
  -- No competitor intelligence on file
  if coalesce(v_intel,0) = 0 then
    perform public.fn_strategy_risk('market','No competitor intelligence on file',
      3, 3, 'No competitor records in market_intel. Add a competitor/market-trend source (web research or a connector) so positioning and pricing decisions are evidence-based.');
  end if;

  select count(*) into v_risks from public.strategy_risks where status='open';
  return jsonb_build_object('active_suppliers_90d',v_active,'top_supplier_share_pct',v_top_share,
    'under_supplied',v_under,'cash',v_cash,'competitor_intel',v_intel,'open_risks',v_risks);
end $function$


CREATE OR REPLACE FUNCTION public.fn_stripe_event_seen(p_event_id text, p_type text, p_status text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  INSERT INTO public.stripe_events (event_id, type, payment_status)
  VALUES (p_event_id, p_type, p_status)
  ON CONFLICT (event_id) DO UPDATE
    SET last_seen_at = now(),
        delivery_count = public.stripe_events.delivery_count + 1;
$function$


CREATE OR REPLACE FUNCTION public.fn_subscription_billing_run(p_dry_run boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_flagged int := 0; v_fee numeric; v_start date; v_admin text;
begin
  v_start := coalesce((select nullif(value,'')::date from app_secrets where key='supplier_subscription_start'),'2027-08-01'::date);
  v_fee   := coalesce((select nullif(value,'')::numeric from app_secrets where key='supplier_subscription_aed'),1000);
  v_admin := coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com');

  for r in
    select b.* from v_supplier_billing b
    where b.billing_status in ('due','past_due')
      and coalesce(b.email,'') <> ''
      and not exists (   -- one invoice per supplier per 30 days
        select 1 from notifications n
        where n.type='subscription_due' and n.lead_id = b.supplier_id
          and n.created_at > now() - interval '30 days')
  loop
    if not p_dry_run then
      update leads set registration_fee_due = v_fee, registration_status = 'due' where id = r.supplier_id;
      insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
      values('subscription_due', r.email, 'supplier', r.supplier_id, 'email',
        'Your QuotesDone annual subscription is due',
        'Dear '||coalesce(r.company_name,'there')||E',\n\nYour QuotesDone annual supplier subscription of AED '||v_fee||E' is now due.\n\nYou keep paying no commission on the jobs you win — this is the annual subscription only. You can settle it securely on the supplier portal: https://quotesdone.com/suppliers\n\nIf it is not settled, your profile is paused from receiving new customer requests until it is.\n\nThank you for being part of QuotesDone.',
        'queued');
    end if;
    v_flagged := v_flagged + 1;
  end loop;

  if v_flagged > 0 and not p_dry_run then
    insert into notifications(type,to_email,to_role,channel,subject,body,status)
    values('subscription_billing_summary', v_admin,'admin','email','Supplier subscriptions invoiced',
      v_flagged||' supplier(s) were invoiced AED '||v_fee||' for their annual subscription. Founding suppliers (first '||
      (select free_limit from v_supplier_billing limit 1)||') are exempt and were not billed.','queued');
  end if;

  return json_build_object('billing_starts', v_start, 'fee_aed', v_fee, 'invoiced', v_flagged,
    'dry_run', p_dry_run, 'ran_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_autoapprove_clean(p_limit integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_ids bigint[]; v_approved int := 0; v_scanned int; r record;
begin
  -- how many genuine applicants are waiting a decision (for reporting)
  select count(*) into v_scanned from leads
    where approval_status in ('pending','submitted') and coalesce(banned,false)=false;

  -- pick the fully-clean ones
  select array_agg(id) into v_ids from (
    select id from leads
    where approval_status in ('pending','submitted')
      and coalesce(banned,false) = false
      and registration_submitted_at is not null
      and license_doc_path is not null          -- trade licence uploaded
      and doc_extracted_at is not null           -- OCR has run on the docs
      and trade_license_no is not null and length(trade_license_no) > 3   -- licence number extracted
      and license_expiry is not null and license_expiry > current_date + 30  -- valid, not near expiry
      and coalesce(owner_email_verified,false) = true                         -- verified contact
    order by registration_submitted_at
    limit greatest(1, coalesce(p_limit,25))
  ) z;

  if v_ids is null then
    return jsonb_build_object('approved',0,'candidates_scanned',v_scanned,'note','No licence-OCR-clean applicants to auto-approve; any remaining applicants need manual review.');
  end if;

  for r in select id, company_name, coalesce(claimed_by,email) as contact from leads where id = any(v_ids) loop
    update leads set approval_status='approved', verified=true, verification_status='verified',
      lifecycle_stage='active', approved_at=now(), approval_decided_by='chief_of_staff (auto)'
      where id = r.id;
    if r.contact is not null then
      insert into notifications(type,to_email,to_role,lead_id,channel,subject,body)
      values('registration_approved', r.contact, 'supplier', r.id, 'email',
        'You''re verified on QuotesDone',
        'Good news — '||coalesce(r.company_name,'your company')||' has been verified on QuotesDone (trade licence checks passed). You can now receive inquiries and quote: https://quotesdone.com/suppliers/');
    end if;
    v_approved := v_approved + 1;
  end loop;

  return jsonb_build_object('approved',v_approved,'candidates_scanned',v_scanned,'approved_ids',v_ids,
    'note','Auto-approved '||v_approved||' licence-OCR-clean supplier(s); '||(v_scanned - v_approved)||' applicant(s) left for manual review.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_capability_chase(p_days integer DEFAULT 3, p_max_chases integer DEFAULT 3)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  rec record; v_sent int := 0; v_skipped int := 0; v_escalated int := 0; v_orphans int := 0;
  v_to text; v_chases int; v_ask text;
begin
  ---------------------------------------------------------------- A. stalled records
  for rec in
    select sc.supplier_id, sc.review_status, sc.missing_fields, sc.updated_at,
           l.company_name, l.claimed_by, l.email
      from supplier_capabilities sc
      join leads l on l.id = sc.supplier_id
     where sc.confirmed_at is null
       and sc.review_status in ('insufficient','awaiting_confirmation')
       and sc.updated_at < now() - make_interval(days => p_days)
       and coalesce(l.banned,false) = false
       and coalesce(l.permanently_closed,false) = false
  loop
    select count(*) into v_chases from notifications
     where type = 'capability_chase' and lead_id = rec.supplier_id;

    -- Stop emailing after p_max_chases and hand to supplier_success as an action instead.
    if v_chases >= p_max_chases then
      if not exists (select 1 from agent_actions
                      where agent='supplier_success' and kind='capability_stalled'
                        and target_id = rec.supplier_id::text and status in ('needs_review','pending')) then
        insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
        values ('supplier_success','capability_stalled','needs_review','medium',
                'Supplier stalled in onboarding: ' || coalesce(rec.company_name,'#'||rec.supplier_id),
                'Chased ' || v_chases || ' times with no response. They cannot receive any inquiry until their scope is confirmed. Consider a call, or retire the registration.',
                jsonb_build_object('supplier_id',rec.supplier_id,'review_status',rec.review_status,
                                   'missing',to_jsonb(rec.missing_fields),'chases',v_chases),
                'leads', rec.supplier_id::text);
        v_escalated := v_escalated + 1;
      end if;
      continue;
    end if;

    -- one chase per 5 days
    if exists (select 1 from notifications where type='capability_chase' and lead_id=rec.supplier_id
                 and created_at > now() - interval '5 days') then
      v_skipped := v_skipped + 1; continue;
    end if;

    v_to := nullif(trim(coalesce(rec.claimed_by, rec.email)), '');
    if v_to is null or position('@' in v_to) = 0 then v_skipped := v_skipped + 1; continue; end if;

    -- Reuse the agent's own wording. A generic "please complete your profile" is why these stall.
    v_ask := coalesce(
      (select string_agg('  • ' || m, chr(10)) from unnest(rec.missing_fields) m),
      '  • a company profile or catalogue describing the products and services you supply');

    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('capability_chase', v_to, 'supplier', rec.supplier_id, 'email',
      case when rec.review_status='awaiting_confirmation'
           then 'One step left — confirm what your company does'
           else 'We need a little more to start sending you work' end,
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      case when rec.review_status='awaiting_confirmation'
        then 'We have read your documents and prepared a summary of what your company does. We just need you to confirm it is correct before we start matching you to customer requests.'
        else 'We have reviewed the documents you uploaded, but we cannot yet tell precisely what work to send you. Until we can, you will not receive customer requests — we would rather send you nothing than send you jobs you do not do.'
      end || chr(10) || chr(10) ||
      case when rec.review_status='awaiting_confirmation' then 'Open the Profile tab in your supplier portal to confirm.'
           else 'What we still need:' || chr(10) || v_ask end || chr(10) || chr(10) ||
      'This takes a couple of minutes and only needs doing once.' || chr(10) || chr(10) ||
      'QuotesDone',
      'queued');
    v_sent := v_sent + 1;
  end loop;

  ---------------------------------------------------------------- B. approved but no record at all
  for rec in
    select l.id as supplier_id, l.company_name
      from leads l
      left join supplier_capabilities sc on sc.supplier_id = l.id
     where l.approval_status = 'approved'
       and coalesce(l.banned,false) = false
       and coalesce(l.matching_blocked,false) = false
       and sc.supplier_id is null
  loop
    if not exists (select 1 from agent_actions
                    where agent='supplier_success' and kind='capability_missing'
                      and target_id = rec.supplier_id::text and status in ('needs_review','pending')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
      values ('supplier_success','capability_missing','needs_review','high',
              'Approved supplier has no capability record: ' || coalesce(rec.company_name,'#'||rec.supplier_id),
              'This supplier is approved but invisible to matching, because fn_match_capability requires a supplier-confirmed capability record. They will receive zero inquiries and will conclude the platform does not work. Run capability_agent analyze for them.',
              jsonb_build_object('supplier_id',rec.supplier_id),
              'leads', rec.supplier_id::text);
      v_orphans := v_orphans + 1;
    end if;
  end loop;

  insert into agent_runs(agent,status,counts,note,started_at,finished_at)
  values ('supplier_success','ok',
          jsonb_build_object('chased',v_sent,'skipped',v_skipped,'escalated',v_escalated,'no_capability_record',v_orphans),
          'capability chase: ' || v_sent || ' chased, ' || v_escalated || ' escalated after ' || p_max_chases ||
          ' attempts, ' || v_orphans || ' approved supplier(s) flagged with no capability record at all',
          now(), now());

  return json_build_object('chased',v_sent,'skipped',v_skipped,'escalated',v_escalated,'no_capability_record',v_orphans);
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_capability_score(l leads)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare pts int:=0; miss text[]:='{}';
begin
  if coalesce(l.trade_license_no,'')<>'' then pts:=pts+15; else miss:=array_append(miss,'trade_licence'); end if;
  if coalesce(l.trn,'')<>'' or coalesce(l.vat_number,'')<>'' then pts:=pts+10; else miss:=array_append(miss,'vat_trn'); end if;
  if coalesce(l.insurance_doc_path,'')<>'' then pts:=pts+10; else miss:=array_append(miss,'insurance'); end if;
  if l.iso_certifications is not null and jsonb_array_length(l.iso_certifications)>0 then pts:=pts+10; else miss:=array_append(miss,'certifications'); end if;
  if l.manufacturer_authorizations is not null and jsonb_array_length(l.manufacturer_authorizations)>0 then pts:=pts+10; else miss:=array_append(miss,'manufacturer_authorizations'); end if;
  if coalesce(l.team_size,0)>0 then pts:=pts+8; else miss:=array_append(miss,'team_size'); end if;
  if coalesce(l.engineers_count,0)>0 then pts:=pts+7; else miss:=array_append(miss,'engineers'); end if;
  if l.brands_carried is not null and jsonb_array_length(l.brands_carried)>0 then pts:=pts+8; else miss:=array_append(miss,'brands_carried'); end if;
  if l.client_references is not null and jsonb_array_length(l.client_references)>0 then pts:=pts+12; else miss:=array_append(miss,'references'); end if;
  if coalesce(array_length(l.service_emirates,1),0)>0 then pts:=pts+5; else miss:=array_append(miss,'coverage_area'); end if;
  if coalesce(l.warehouse_area,'')<>'' or (l.machinery is not null and jsonb_array_length(l.machinery)>0) then pts:=pts+5; else miss:=array_append(miss,'facilities'); end if;
  return jsonb_build_object('score',pts,'missing',to_jsonb(miss),'scored_at',now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_expiries(p_supplier_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with l as (select * from leads where id=p_supplier_id)
  select coalesce(jsonb_agg(e order by (e->>'days_left')::int), '[]'::jsonb) from (
    select jsonb_build_object('doc',d.label,'expiry',d.exp,
      'days_left',(d.exp - current_date),
      'status', case when d.exp < current_date then 'expired'
                     when d.exp <= current_date + 30 then 'expiring'
                     when d.exp <= current_date + 90 then 'soon' else 'ok' end) e
    from l, lateral (values
      ('Trade license', l.license_expiry),
      ('ISO certification', l.iso_expiry),
      ('Insurance', l.insurance_expiry),
      ('Manufacturer authorization', l.manufacturer_auth_expiry)
    ) as d(label,exp)
    where d.exp is not null
  ) q;
$function$


CREATE OR REPLACE FUNCTION public.fn_supplier_stats(p_supplier_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v jsonb; v_quotes int; v_reveals int; v_hired int; v_lost int;
  v_qd_rev numeric; v_deal_val numeric; v_avg_lead numeric;
  v_pos jsonb; v_hist jsonb; v_rating numeric; v_rating_pct numeric; v_resp numeric;
  v_pending_reviews int; v_active_rfqs int;
begin
  select count(*) into v_quotes from quotes where supplier_id=p_supplier_id;
  select count(*) into v_reveals from transactions where supplier_id=p_supplier_id;
  select count(*) into v_hired from inquiries where hired_supplier_id=p_supplier_id;
  select count(*) into v_lost from inquiries i
     where i.hired_supplier_id is not null and i.hired_supplier_id<>p_supplier_id
       and exists (select 1 from quotes q where q.inquiry_id=i.id and q.supplier_id=p_supplier_id);
  select coalesce(sum(coalesce(reveal_fee,0)+coalesce(app_fee,0)),0),
         coalesce(sum(coalesce(quote_amount,0)),0)
    into v_qd_rev, v_deal_val
    from transactions where supplier_id=p_supplier_id and coalesce(refund_status,'')<>'approved';
  select round(avg(nullif(regexp_replace(coalesce(lead_time,''),'[^0-9.]','','g'),'')::numeric),1)
    into v_avg_lead from quotes where supplier_id=p_supplier_id and lead_time ~ '[0-9]';
  select coalesce(app_rating,rating), rv_response_rate into v_rating, v_resp from leads where id=p_supplier_id;
  select round(100.0*(count(*) filter (where coalesce(l2.app_rating,l2.rating,0) <= coalesce(v_rating,0)))/nullif(count(*),0),0)
    into v_rating_pct
    from leads l2 where l2.sector = (select sector from leads where id=p_supplier_id) and coalesce(l2.app_rating,l2.rating) is not null;
  select count(*) into v_pending_reviews from quotes where supplier_id=p_supplier_id and coalesce(review_status,'')='pending';
  select count(distinct q.inquiry_id) into v_active_rfqs from quotes q join inquiries i on i.id=q.inquiry_id
    where q.supplier_id=p_supplier_id and coalesce(i.status,'') in ('open','active','collecting','live');
  with myq as (select inquiry_id, quote_amount from quotes where supplier_id=p_supplier_id and quote_amount is not null and quote_amount>0),
  peer as (select inquiry_id, min(quote_amount) lo, avg(quote_amount) av, count(*) n
             from quotes where quote_amount is not null and quote_amount>0 group by inquiry_id),
  pos as (select m.quote_amount, p.lo, p.av,
                 case when p.lo>0 then (m.quote_amount-p.lo)/p.lo*100 end pct_low,
                 case when p.av>0 then (m.quote_amount-p.av)/p.av*100 end pct_avg,
                 (m.quote_amount<=p.lo*1.0001) as is_lowest
            from myq m join peer p using(inquiry_id) where p.n>=2)
  select jsonb_build_object('competitive_rfqs', count(*),'times_lowest', count(*) filter (where is_lowest),
    'lowest_rate', round(100.0*count(*) filter (where is_lowest)/nullif(count(*),0),0),
    'avg_pct_above_lowest', round(avg(pct_low)::numeric,1),'avg_pct_vs_average', round(avg(pct_avg)::numeric,1),
    'band', case when count(*)=0 then 'not enough data' when avg(pct_avg) <= -4 then 'below market average'
                 when avg(pct_avg) < 5 then 'around market average' else 'above market average' end
  ) into v_pos from pos;
  with months as (select date_trunc('month', (now() - (n||' month')::interval)) m from generate_series(0,11) n),
  qb as (select date_trunc('month',created_at) m, count(*) c from quotes where supplier_id=p_supplier_id group by 1),
  rb as (select date_trunc('month',revealed_at) m, count(*) c from transactions where supplier_id=p_supplier_id group by 1)
  select jsonb_agg(jsonb_build_object('month', to_char(months.m,'Mon YY'),'quotes', coalesce(qb.c,0), 'reveals', coalesce(rb.c,0)) order by months.m)
    into v_hist from months left join qb on qb.m=months.m left join rb on rb.m=months.m;
  v := jsonb_build_object('supplier_id', p_supplier_id,'quotes_total', v_quotes,'reveals', v_reveals,'hired', v_hired,
    'lost_to_others', v_lost,'win_ratio', round(100.0*v_hired/nullif(v_quotes,0),1),'reveal_ratio', round(100.0*v_reveals/nullif(v_quotes,0),1),
    'qd_revenue', v_qd_rev,'deal_value_awarded', v_deal_val,'avg_lead_time_days', v_avg_lead,'rating', v_rating,
    'rating_percentile', v_rating_pct,'response_rate', v_resp,'pending_reviews', v_pending_reviews,'active_rfqs', v_active_rfqs,
    'price_positioning', v_pos,'history_12m', v_hist,'document_expiries', fn_supplier_expiries(p_supplier_id));
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_supplier_success()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_kpis jsonb;
  n_enable int:=0; n_reengage int:=0; n_risk int:=0;
  rec record;
  v_tips text; v_subject text; v_body text;
begin
  -- 1) snapshot portfolio KPIs (one row per day)
  select to_jsonb(k) into v_kpis from public.supplier_kpis k;
  insert into public.supplier_kpi_snapshots(snapshot_date, kpis)
  values (current_date, coalesce(v_kpis,'{}'::jsonb))
  on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  -- 2) ENABLEMENT (operational, auto-sends once supplier emails enabled) — low quality/response/compliance
  for rec in
    select h.supplier_id, h.quality, h.response, h.compliance, l.company_name as co,
           coalesce(l.claimed_by,l.email) as to_email
    from public.supplier_health h join public.leads l on l.id=h.supplier_id
    where coalesce(l.banned,false)=false
      and (h.quality < 50 or h.response < 50 or h.compliance < 80)
      and coalesce(l.claimed_by,l.email) like '%@%'
      and not exists (select 1 from notifications n where n.lead_id=h.supplier_id and n.type='supplier_enablement' and n.created_at > now()-interval '30 days')
    limit 200
  loop
    v_tips := '';
    if rec.compliance < 80 then v_tips := v_tips || E'\n• Complete your documents (licence, insurance, TRN, establishment card) so you stay eligible for matches.'; end if;
    if rec.response < 50 then v_tips := v_tips || E'\n• Respond faster to job requests — quick, complete quotes win more often.'; end if;
    if rec.quality < 50 then v_tips := v_tips || E'\n• Add full itemised detail (brand, model, spec, unit price) to every quote — detailed quotes convert best.'; end if;
    v_subject := 'Tips to win more jobs on QuotesDone — ' || coalesce(rec.co,'your business');
    v_body := 'Dear ' || coalesce(rec.co,'there') || E',\n\nHere are a few quick things that will help you win more customer jobs on QuotesDone:' || v_tips || E'\n\nUpdate your profile any time from your supplier portal. We are here to help you grow. Thank you for being part of QuotesDone.';
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('supplier_enablement', rec.to_email, 'supplier', rec.supplier_id, 'email', v_subject, v_body, 'queued');
    n_enable := n_enable + 1;
  end loop;

  -- 3) RETENTION / re-engagement (operational) — dormant suppliers
  for rec in
    select h.supplier_id, l.company_name as co, coalesce(l.claimed_by,l.email) as to_email
    from public.supplier_health h join public.leads l on l.id=h.supplier_id
    where h.dormant and coalesce(l.banned,false)=false
      and coalesce(l.claimed_by,l.email) like '%@%'
      and not exists (select 1 from notifications n where n.lead_id=h.supplier_id and n.type='supplier_reengage' and n.created_at > now()-interval '30 days')
    limit 200
  loop
    v_subject := 'We miss you on QuotesDone — new jobs are waiting';
    v_body := 'Dear ' || coalesce(rec.co,'there') || E',\n\nWe have not seen you quoting recently. Customers are posting jobs in your category on QuotesDone right now. Log in to your supplier portal to see your latest matches and send a quick quote.\n\nMake sure your documents and profile are up to date so you keep receiving matches. We would love to help you win more work.';
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('supplier_reengage', rec.to_email, 'supplier', rec.supplier_id, 'email', v_subject, v_body, 'queued');
    n_reengage := n_reengage + 1;
  end loop;

  -- 4) RISK — high-risk suppliers queued for FOUNDER decision (never auto-suspend/ban/delete)
  for rec in
    select h.supplier_id, h.compliance, h.strikes, h.banned, h.health, h.risk_tier, l.company_name as co
    from public.supplier_health h join public.leads l on l.id=h.supplier_id
    where h.risk_tier='high'
      and not exists (
        select 1 from agent_actions a
        where a.kind='supplier_risk' and a.target_table='leads' and a.target_id=h.supplier_id::text
          and a.status in ('pending','needs_review'))
    limit 100
  loop
    insert into agent_actions(agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('supplier_success','supplier_risk','pending','high',
      'High-risk supplier: '||coalesce(rec.co,'#'||rec.supplier_id),
      case when rec.banned then 'Already banned — review whether to remove from marketplace.'
           when rec.strikes>=3 then 'Repeated chat strikes — consider suspending matching pending review.'
           when rec.compliance<40 then 'Compliance failing (missing/expired documents) — hold matches until resolved.'
           else 'Low overall health — review account, coach or pause.' end,
      jsonb_build_object('company',rec.co,'health',rec.health,'compliance',rec.compliance,'strikes',rec.strikes,'banned',rec.banned),
      'leads', rec.supplier_id::text);
    n_risk := n_risk + 1;
  end loop;

  return jsonb_build_object('ran_at',now(),'kpis',v_kpis,'enablement_queued',n_enable,'reengage_queued',n_reengage,'risk_flagged',n_risk);
end $function$


CREATE OR REPLACE FUNCTION public.fn_supply_health()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_run bigint; s timestamptz := now()-interval '30 days'; v_total int; v_matched int; v_quoted int; v_nosupply int; v_ttfq numeric; v_fill numeric; v_owner text; v_gaps jsonb; v_gapcount int;
begin
  insert into agent_runs(agent,started_at) values('supply_health',now()) returning id into v_run;
  select count(*) into v_total from inquiries where created_at>=s;
  select count(*) into v_matched from inquiries i where i.created_at>=s and exists(select 1 from inquiry_matches m where m.inquiry_id=i.id);
  select count(*) into v_quoted from inquiries i where i.created_at>=s and exists(select 1 from quotes q where q.inquiry_id=i.id);
  select count(*) into v_nosupply from inquiries i where i.created_at>=s and not exists(select 1 from inquiry_matches m where m.inquiry_id=i.id);
  v_fill := case when v_total>0 then round(v_quoted::numeric/v_total,3) else null end;
  select round(percentile_cont(0.5) within group (order by extract(epoch from (fq.first_q - i.created_at))/3600)::numeric,1)
    into v_ttfq
    from inquiries i join lateral (select min(q.created_at) first_q from quotes q where q.inquiry_id=i.id) fq on true
    where i.created_at>=s and fq.first_q is not null;
  -- coverage gaps: categories with >=3 inquiries in 30d and quote-rate < 50%
  select coalesce(jsonb_agg(g),'[]'::jsonb), count(*) into v_gaps, v_gapcount from (
    select i.category,
      count(*) as inquiries,
      count(*) filter (where exists(select 1 from quotes q where q.inquiry_id=i.id)) as quoted,
      round(count(*) filter (where exists(select 1 from quotes q where q.inquiry_id=i.id))::numeric/count(*),2) as quote_rate
    from inquiries i where i.created_at>=s and i.category is not null
    group by i.category
    having count(*)>=3 and count(*) filter (where exists(select 1 from quotes q where q.inquiry_id=i.id))::numeric/count(*) < 0.5
    order by count(*) desc limit 20
  ) g;
  insert into supply_health_snapshots(period_end,metrics) values (current_date,
    jsonb_build_object('inquiries_30d',v_total,'matched',v_matched,'quoted',v_quoted,'no_supply',v_nosupply,'fill_rate',v_fill,'median_hours_to_first_quote',v_ttfq,'coverage_gaps',v_gaps));
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';
  -- queue a report for the Follow-up agent when health is weak
  if v_total>=5 and (coalesce(v_fill,0) < 0.5 or v_gapcount>0 or v_nosupply>0) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table)
      values('followup','supply_health','pending','medium',
        'Supply health: '||coalesce(round(v_fill*100)::text,'?')||'% of requests got a quote (30d)',
        'Source/activate suppliers in low-coverage categories; '||v_nosupply||' request(s) had no supplier match.',
        jsonb_build_object('fill_rate',v_fill,'no_supply',v_nosupply,'median_hours_to_first_quote',v_ttfq,'gaps',v_gaps),'inquiries');
    if v_owner is not null then
      insert into notifications(type,to_email,to_role,channel,subject,body)
        values('supply_health',v_owner,'admin','email','QuotesDone supply-health alert',
          'In the last 30 days: '||v_total||' requests, '||coalesce(round(v_fill*100)::text,'?')||'% received a quote, '||v_nosupply||' had no matched supplier, median time-to-first-quote '||coalesce(v_ttfq::text,'n/a')||'h, '||v_gapcount||' low-coverage categor(ies). Open the Secretary or Follow-up agent for the breakdown.');
    end if;
  end if;
  update agent_runs set finished_at=now(),status='ok',counts=jsonb_build_object('inquiries_30d',v_total,'fill_rate',v_fill,'no_supply',v_nosupply,'gaps',v_gapcount) where id=v_run;
end; $function$


CREATE OR REPLACE FUNCTION public.fn_twin(p_kind text, p_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare res jsonb;
begin
  if p_kind='customer' then
    select jsonb_build_object('kind','customer','id',c.id,'name',c.full_name,'email',c.email,
      'rfqs',(select count(*) from inquiries where customer_id=c.id),
      'deals',(select count(*) from transactions where customer_id=c.id),
      'spend_aed',(select coalesce(sum(reveal_fee),0) from transactions where customer_id=c.id and coalesce(fee_status,'')='paid'),
      'categories',(select coalesce(jsonb_agg(distinct category),'[]') from inquiries where customer_id=c.id),
      'last_active',(select max(created_at) from inquiries where customer_id=c.id),
      'banned',c.banned) into res from customers c where c.id::text=p_id;

  elsif p_kind='rfq' then
    select jsonb_build_object('kind','rfq','id',i.id,'category',i.category,'emirate',i.emirate,'status',i.status,
      'completeness',i.completeness,'ready',i.rfq_ready,'budget',i.budget,
      'quotes',(select count(*) from quotes where inquiry_id=i.id),
      'avg_quote_quality',(select round(avg(nullif(quality->>'score','')::numeric),1) from quotes where inquiry_id=i.id),
      'matched_suppliers',(select count(*) from inquiry_matches where inquiry_id=i.id),
      'created',i.created_at,'completed',i.completed_at,'outcome',i.outcome) into res from inquiries i where i.id::text=p_id;

  elsif p_kind='category' then
    res := jsonb_build_object('kind','category','category',p_id,
      'demand_rfqs',(select count(*) from inquiries where category=p_id),
      'approved_suppliers',(select count(*) from leads where coalesce(approval_status,'')='approved' and (lower(coalesce(categories,''))||' '||lower(coalesce(sub_type,'')) like '%'||lower(p_id)||'%')),
      'supplier_pool_total',(select count(*) from leads where lower(coalesce(categories,''))||' '||lower(coalesce(sub_type,'')) like '%'||lower(p_id)||'%'),
      'avg_quote_quality',(select round(avg(nullif(q.quality->>'score','')::numeric),1) from quotes q join inquiries i on i.id=q.inquiry_id where i.category=p_id),
      'agent',public.fn_resolve_cat_agent(p_id));

  elsif p_kind='company' then
    res := jsonb_build_object('kind','company','name','QuotesDone',
      'health',public.fn_health_index(),
      'suppliers_total',(select count(*) from leads),'suppliers_approved',(select count(*) from leads where coalesce(approval_status,'')='approved'),
      'customers',(select count(*) from customers),'rfqs',(select count(*) from inquiries),'quotes',(select count(*) from quotes),
      'revenue_paid_aed',(select coalesce(sum(reveal_fee),0) from transactions where coalesce(fee_status,'')='paid'),
      'eval',public.fn_eval_snapshot(30));
  else
    res := jsonb_build_object('error','kind must be customer|rfq|category|company');
  end if;
  return coalesce(res, jsonb_build_object('error','not found','kind',p_kind,'id',p_id));
end $function$


CREATE OR REPLACE FUNCTION public.fn_voice_metrics()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare res jsonb;
begin
  select jsonb_build_object(
    'low_ratings_90d', (select count(*) from reviews where created_at > now()-interval '90 days' and rating is not null and rating <= 2),
    'recent_low_comments', (select coalesce(jsonb_agg(comment),'[]'::jsonb) from (select comment from reviews where rating <= 2 and coalesce(comment,'')<>'' order by created_at desc limit 8) z),
    'disputes', (select coalesce(jsonb_object_agg(coalesce(refund_status,'none'), c),'{}'::jsonb) from (select refund_status, count(*) c from transactions group by refund_status) z),
    'abandoned_rfqs', (select (fn_marketplace_analytics()->>'abandoned_rfqs')::int),
    'repeat_customers', (select count(*) from (select customer_id from inquiries where customer_id is not null group by customer_id having count(*)>1) z)
  ) into res;
  return res;
end $function$


CREATE OR REPLACE FUNCTION public.fn_wa_fanout()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare ph text; opt boolean := false;
begin
  -- only fan out plain email rows; never recurse on whatsapp rows
  if coalesce(NEW.channel,'email') <> 'email' then return NEW; end if;
  if NEW.to_email is null then return NEW; end if;

  if NEW.to_role = 'supplier' then
    select coalesce(nullif(btrim(l.whatsapp),''), l.phone), coalesce(l.wa_optin,false)
      into ph, opt from leads l
      where (NEW.lead_id is not null and l.id = NEW.lead_id)
         or (NEW.lead_id is null and lower(l.email) = lower(NEW.to_email))
      order by (l.id = NEW.lead_id) desc nulls last
      limit 1;
  elsif NEW.to_role = 'customer' then
    select c.phone, coalesce(c.wa_optin,false)
      into ph, opt from customers c where lower(c.email) = lower(NEW.to_email) limit 1;
  else
    return NEW;
  end if;

  if opt is true and ph is not null and length(regexp_replace(ph, '[^0-9]', '', 'g')) >= 8 then
    insert into notifications(type, to_email, to_role, to_phone, lead_id, inquiry_id, quote_id, subject, body, channel, status)
    values (NEW.type, NEW.to_email, NEW.to_role, ph, NEW.lead_id, NEW.inquiry_id, NEW.quote_id, NEW.subject, NEW.body, 'whatsapp', 'queued');
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_working_days_between(p_from timestamp with time zone, p_to timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d date; n int := 0; last date;
begin
  if p_from is null or p_to is null or p_to <= p_from then return 0; end if;
  d := (p_from at time zone 'Asia/Dubai')::date + 1;
  last := (p_to at time zone 'Asia/Dubai')::date;
  while d <= last loop
    if public.fn_is_working_day(d) then n := n + 1; end if;
    d := d + 1;
  end loop;
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ws_agent_ops(p_agent text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare ca public.category_agents%rowtype; pr public.prompts%rowtype;
  runs_total int; runs_24h int; runs_7d int; ok_runs int; last_run timestamptz; last_status text;
  avg_ms numeric; kn_updated timestamptz; kn_count int; mem_count int; health text;
begin
  select * into ca from public.category_agents where slug=p_agent;
  select * into pr from public.prompts where key=p_agent;
  select count(*), count(*) filter (where started_at>now()-interval '24 hours'),
         count(*) filter (where started_at>now()-interval '7 days'),
         count(*) filter (where status='ok'),
         max(started_at),
         coalesce(round(avg(extract(epoch from (finished_at-started_at))*1000) filter (where finished_at is not null),0),0)
    into runs_total, runs_24h, runs_7d, ok_runs, last_run, avg_ms
    from public.agent_runs where agent=p_agent;
  select status into last_status from public.agent_runs where agent=p_agent order by started_at desc limit 1;
  select count(*), max(updated_at) into kn_count, kn_updated from public.agent_knowledge where agent_key=p_agent;
  select count(*) into mem_count from public.agent_memory where agent_key=p_agent;
  health := case
    when last_status is null then 'idle'
    when last_status in ('error','failed') then 'degraded'
    when last_run < now()-interval '3 days' then 'stale'
    else 'healthy' end;

  return jsonb_build_object(
    'identity', jsonb_build_object('key',p_agent,'name',coalesce(ca.name,pr.description,p_agent),
       'emoji',ca.emoji,'active',coalesce(ca.active,true),'persona',ca.persona,
       'prompt_version',pr.active_version,'prompt_desc',pr.description,'prompt_owner',pr.owner,'prompt_updated',pr.updated_at,
       'knowledge_updated',kn_updated),
    'health', jsonb_build_object('status',health,'last_run',last_run,'last_status',last_status),
    'performance', jsonb_build_object('runs_total',runs_total,'runs_24h',runs_24h,'runs_7d',runs_7d,
       'ok_rate', case when runs_total>0 then round(100.0*ok_runs/runs_total,1) else null end,
       'avg_duration_ms',avg_ms),
    'knowledge', jsonb_build_object('count',kn_count,'updated',kn_updated,
       'topics', coalesce((select jsonb_agg(distinct topic) from public.agent_knowledge where agent_key=p_agent and topic is not null),'[]'::jsonb),
       'recent', coalesce((select jsonb_agg(jsonb_build_object('topic',topic,'priority',priority,'updated',updated_at) order by updated_at desc)
                    from (select * from public.agent_knowledge where agent_key=p_agent order by updated_at desc limit 6) x),'[]'::jsonb)),
    'memory', jsonb_build_object('count',mem_count,
       'recent', coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'content',left(content,140),'importance',importance,'at',created_at) order by created_at desc)
                    from (select * from public.agent_memory where agent_key=p_agent order by created_at desc limit 6) x),'[]'::jsonb)),
    'queue', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'risk',risk,'status',status,'recommendation',recommendation,'created_at',created_at) order by created_at desc)
                 from (select * from public.agent_actions where agent=p_agent and status in ('pending','held_for_review','proposed','open') order by created_at desc limit 12) x),'[]'::jsonb),
    'conversations', coalesce((select jsonb_agg(jsonb_build_object('role',role,'content',left(content,160),'at',created_at) order by created_at desc)
                 from (select * from public.agent_chats where agent_key=p_agent order by created_at desc limit 8) x),'[]'::jsonb),
    'recommendations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'recommendation',left(recommendation,180),'risk',risk,'at',created_at) order by created_at desc)
                 from (select * from public.agent_actions where agent=p_agent and recommendation is not null order by created_at desc limit 6) x),'[]'::jsonb),
    'audit', coalesce((select jsonb_agg(jsonb_build_object('title',title,'kind',kind,'status',status,'decided_by',decided_by,'decided_at',decided_at,'at',created_at) order by created_at desc)
                 from (select * from public.agent_actions where agent=p_agent order by created_at desc limit 12) x),'[]'::jsonb),
    'recent_runs', coalesce((select jsonb_agg(jsonb_build_object('id',id,'status',status,'note',note,'started_at',started_at,'finished_at',finished_at) order by started_at desc)
                 from (select * from public.agent_runs where agent=p_agent order by started_at desc limit 8) x),'[]'::jsonb)
  );
end $function$


CREATE OR REPLACE FUNCTION public.fn_ws_agents()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_minds jsonb;
begin
  -- The registry of real minds: org executives, category experts, intel officers,
  -- and any key that holds its own knowledge (covers secretary/designer).
  create temp table if not exists _minds (k text primary key) on commit drop;
  insert into _minds
    select agent_key from public.org_agents where active
    union select 'cat:'||slug from public.category_agents where active
    union select slug from public.category_agents where active
    union select distinct agent_key from public.agent_knowledge where agent_key <> '_global'
  on conflict do nothing;

  return jsonb_build_object(
    'kpis', jsonb_build_object(
      'agents', (select count(distinct case when m.k like 'cat:%' then m.k
                                            when exists (select 1 from _minds m2 where m2.k='cat:'||m.k) then 'cat:'||m.k
                                            else m.k end) from _minds m),
      'automations', (select count(distinct ar.agent) from public.agent_runs ar
                      where ar.agent is not null and ar.agent <> ''
                        and not exists (select 1 from _minds m where m.k=ar.agent)),
      'runs_24h', (select count(*) from public.agent_runs where started_at > now()-interval '24 hours'),
      'actions_total', (select count(*) from public.agent_actions),
      'actions_pending', (select count(*) from public.agent_actions where status in ('pending','held_for_review','proposed','open')),
      'memory_items', (select count(*) from public.agent_memory),
      'knowledge_items', (select count(*) from public.agent_knowledge)
    ),
    'rows', (
      with keys as (
        select distinct k from (
          select agent k from public.agent_runs where agent is not null and agent <> ''
          union select agent from public.agent_actions where agent is not null
          union select key from public.prompts where key is not null
          union select slug from public.category_agents where slug is not null
          union select agent_key from public.org_agents where active
        ) u
      )
      select coalesce(jsonb_agg(r order by (r->>'runs_total')::int desc nulls last, r->>'name'),'[]'::jsonb)
      from (
        select jsonb_build_object(
          'key', k.k,
          'name', coalesce(ca.name, pr.description, k.k),
          'emoji', ca.emoji,
          'kind', case when exists (select 1 from _minds m where m.k=k.k) then 'agent' else 'automation' end,
          'active', coalesce(ca.active, true),
          'prompt_version', pr.active_version,
          'runs_total', (select count(*) from public.agent_runs ar where ar.agent=k.k),
          'runs_24h', (select count(*) from public.agent_runs ar where ar.agent=k.k and ar.started_at>now()-interval '24 hours'),
          'last_run', (select max(started_at) from public.agent_runs ar where ar.agent=k.k),
          'last_status', (select status from public.agent_runs ar where ar.agent=k.k order by started_at desc limit 1),
          'actions_pending', (select count(*) from public.agent_actions aa where aa.agent=k.k and aa.status in ('pending','held_for_review','proposed','open')),
          'memory', (select count(*) from public.agent_memory am where am.agent_key=k.k),
          'knowledge', (select count(*) from public.agent_knowledge ak where ak.agent_key in (k.k, 'cat:'||k.k))
        ) r
        from keys k
        left join public.category_agents ca on ca.slug=k.k
        left join public.prompts pr on pr.key=k.k
      ) s
    )
  );
end $function$


CREATE OR REPLACE FUNCTION public.fn_ws_ai()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'agents',(select count(*) from category_agents),
      'agents_active',(select count(*) from category_agents where active is true),
      'actions_total',(select count(*) from agent_actions),
      'actions_pending',(select count(*) from agent_actions where status='pending'),
      'runs_24h',(select count(*) from agent_runs where started_at > now()-interval '24 hours'),
      'avg_confidence',(select round(avg(confidence)::numeric,2) from decision_log where confidence is not null)
    ),
    'trainer', jsonb_build_object(
      'ai_health', (select (kpis->>'ai_health')::numeric from ai_trainer_snapshots order by snapshot_date desc limit 1),
      'metrics', (select kpis from ai_trainer_snapshots order by snapshot_date desc limit 1),
      'weak_agents', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'run_success_pct',run_success_pct,'rejection_rate_pct',rejection_rate_pct,'errors',errors) order by run_success_pct nulls last)
          from ai_agent_quality where runs_30d>=20 and (coalesce(run_success_pct,100)<95 or coalesce(rejection_rate_pct,0)>20)),'[]'::jsonb),
      'proposals', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation))
          from agent_actions where agent='ai_trainer' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'prompt_reviews', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'key', detail->>'key', 'version', (detail->>'version')::int,
        'reason', detail->>'reason',
        'active_version', (select active_version from prompts p where p.key = a.detail->>'key'),
        'active_score', (a.detail->'eval'->>'active_score'),
        'candidate_score', (a.detail->'eval'->>'candidate_score'),
        'delta', (a.detail->'eval'->>'delta'),
        'decision', a.detail->'eval'->>'decision',
        'sensitive', (a.detail->'eval'->>'sensitive'),
        'scored', (a.detail ? 'eval')
      ) order by created_at desc)
      from agent_actions a where kind='prompt_approval' and status in ('pending','needs_review')),'[]'::jsonb),
    'agents', coalesce((select jsonb_agg(jsonb_build_object('slug',ca.slug,'name',ca.name,'emoji',ca.emoji,'active',ca.active,
        'actions',(select count(*) from agent_actions a where a.agent=ca.slug),
        'pending',(select count(*) from agent_actions a where a.agent=ca.slug and a.status='pending')) order by ca.name) from category_agents ca),'[]'::jsonb),
    'kinds', coalesce((select jsonb_agg(jsonb_build_object('key',k,'count',c) order by c desc) from (
        select coalesce(nullif(kind,''),'other') k, count(*) c from agent_actions group by 1 order by 2 desc limit 12) kk),'[]'::jsonb),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'status',status,'started_at',started_at,'finished_at',finished_at,'note',note)) from (select * from agent_runs order by started_at desc limit 12) r),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_analytics()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'marketplace', fn_marketplace_analytics(),
    'supplier_funnel', jsonb_build_object(
      'directory',(select count(*) from leads),
      'claimed',(select count(*) from leads where claimed is true),
      'registered',(select count(*) from leads where registration_paid_at is not null),
      'submitted',(select count(*) from leads where coalesce(approval_status,'') in ('submitted','under_review','pending','pending_review')),
      'approved',(select count(*) from leads where approval_status='approved')
    ),
    'top_sectors', coalesce((select jsonb_agg(jsonb_build_object('key',s,'count',c) order by c desc) from (
        select coalesce(nullif(sector,''),'other') s, count(*) c from leads group by 1 order by 2 desc limit 12) x),'[]'::jsonb),
    'top_emirates', coalesce((select jsonb_agg(jsonb_build_object('key',e,'count',c) order by c desc) from (
        select coalesce(nullif(emirate,''),'—') e, count(*) c from leads group by 1 order by 2 desc limit 8) x),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_company()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'legal', jsonb_build_object(
      'health', (select (kpis->>'legal_health')::numeric from legal_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from legal_kpis k),
      'missing_docs', coalesce((select jsonb_agg(jsonb_build_object('requirement',requirement,'priority',priority,'applies_to',applies_to) order by priority) from legal_checklist where not present),'[]'::jsonb),
      'flags', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk)) from agent_actions where agent='legal_ai' and status in ('pending','needs_review')),'[]'::jsonb),
      'reviews', coalesce((select jsonb_agg(jsonb_build_object('title',title,'kind',doc_kind,'risk',risk_level,'at',reviewed_at) order by reviewed_at desc) from (select * from legal_reviews order by reviewed_at desc limit 10) r),'[]'::jsonb)
    ),
    'departments', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'actions',c,'pending',pend,'last_active',la) order by c desc) from (
        select coalesce(agent,'—') agent, count(*) c,
               count(*) filter (where status='pending') pend, max(created_at) la
        from agent_actions group by 1 order by 2 desc limit 20) d),'[]'::jsonb),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('agent',agent,'status',status,'started_at',started_at,'note',note)) from (select * from agent_runs order by started_at desc limit 12) r),'[]'::jsonb),
    'evals', coalesce((select jsonb_agg(jsonb_build_object('snapshot_at',snapshot_at,'window_days',window_days,'kpis',kpis)) from (select * from agent_evals order by snapshot_at desc limit 4) e),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_customer_360(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare c public.customers%rowtype; j jsonb;
  ltv numeric(18,2); deal_value numeric(18,2); reveals int;
  rfqs_total int; rfqs_active int; rfqs_done int; avg_budget numeric(18,2);
  last_act timestamptz; score int; cats text; docs jsonb := '[]'::jsonb; summary text;
begin
  select * into c from public.customers where id=p_id;
  if c.id is null then return jsonb_build_object('error','customer not found'); end if;

  select coalesce(sum(reveal_fee) filter (where fee_status='paid'),0), coalesce(sum(quote_amount),0), count(*)
    into ltv, deal_value, reveals from public.transactions where customer_id=p_id;
  select count(*), count(*) filter (where status not in ('completed','cancelled','closed','lost')),
         count(*) filter (where status in ('completed','closed') or outcome='completed'),
         coalesce(round(avg(nullif(expected_value,0)),2),0)
    into rfqs_total, rfqs_active, rfqs_done, avg_budget from public.inquiries where customer_id=p_id;
  select string_agg(distinct category, ', ') into cats from public.inquiries where customer_id=p_id and category is not null;

  select greatest(coalesce(max(i.created_at), c.created_at),
                  coalesce((select max(revealed_at) from public.transactions where customer_id=p_id), c.created_at),
                  c.created_at)
    into last_act from public.inquiries i where i.customer_id=p_id;
  last_act := coalesce(last_act, c.created_at);

  score := least(100, greatest(0,
      coalesce(rfqs_total,0)*12 + coalesce(reveals,0)*25 + round(coalesce(ltv,0)/20)::int
      + (case when last_act > now() - interval '30 days' then 15 else 0 end)));

  docs := coalesce((select jsonb_agg(jsonb_build_object('type','Drawing','name',coalesce(drawing_file_name,'drawing'),'path',drawing_file_path))
                    from public.inquiries where customer_id=p_id and drawing_file_path is not null),'[]'::jsonb);
  if c.signed_terms_path is not null then docs := docs || jsonb_build_object('type','Signed terms','name','terms','path',c.signed_terms_path); end if;

  summary := c.full_name||' joined '||to_char(c.created_at,'Mon YYYY')||'. '
    ||coalesce(rfqs_total,0)||' RFQ(s)'||coalesce(' across '||cats,'')||'. '
    ||coalesce(reveals,0)||' reveal(s), AED '||to_char(coalesce(ltv,0),'FM999999990.00')||' paid to date.'
    ||(case when avg_budget>0 then ' Avg project budget AED '||to_char(avg_budget,'FM999999990') else '' end)
    ||(case when c.banned then ' [BANNED]' when not coalesce(c.email_verified,false) then ' Email unverified.' else '' end);

  j := jsonb_build_object(
    'profile', jsonb_build_object('id',c.id,'full_name',c.full_name,'email',c.email,'phone',c.phone,
       'created_at',c.created_at,'phone_verified',c.phone_verified,'email_verified',c.email_verified,
       'banned',c.banned,'banned_reason',c.banned_reason,'wa_optin',c.wa_optin,'tos_accepted_at',c.tos_accepted_at,
       'chat_strikes',c.chat_strikes),
    'metrics', jsonb_build_object('ltv',ltv,'total_deal_value',deal_value,'reveals',reveals,
       'rfqs_total',rfqs_total,'rfqs_active',rfqs_active,'rfqs_completed',rfqs_done,
       'avg_project_budget',avg_budget,'relationship_score',score),
    'ai_summary', summary,
    'preferences', jsonb_build_object(
       'categories', coalesce((select jsonb_agg(distinct category) from public.inquiries where customer_id=p_id and category is not null),'[]'::jsonb),
       'emirates', coalesce((select jsonb_agg(distinct emirate) from public.inquiries where customer_id=p_id and emirate is not null),'[]'::jsonb)),
    'rfqs', coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'category',i.category,'emirate',i.emirate,
       'status',i.status,'pipeline_stage',i.pipeline_stage,'budget',i.expected_value,
       'outcome',i.outcome,'created_at',i.created_at) order by i.created_at desc)
       from (select * from public.inquiries where customer_id=p_id order by created_at desc limit 15) i),'[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'amount',q.quote_amount,'status',q.status,'created_at',q.created_at) order by q.created_at desc)
       from public.quotes q join public.inquiries i on i.id=q.inquiry_id where i.customer_id=p_id),'[]'::jsonb),
    'transactions', coalesce((select jsonb_agg(jsonb_build_object('quote_amount',t.quote_amount,'reveal_fee',t.reveal_fee,'fee_status',t.fee_status,'revealed_at',t.revealed_at) order by t.revealed_at desc)
       from public.transactions t where t.customer_id=p_id),'[]'::jsonb),
    'documents', docs,
    'timeline', (select jsonb_agg(e order by e->>'at' desc) from (
        select jsonb_build_object('at',c.created_at,'event','Signed up') e
        union all select jsonb_build_object('at',i.created_at,'event','RFQ: '||coalesce(i.category,'inquiry')) from public.inquiries i where i.customer_id=p_id
        union all select jsonb_build_object('at',t.revealed_at,'event','Revealed supplier · AED '||coalesce(t.reveal_fee::text,'0')||' fee') from public.transactions t where t.customer_id=p_id and t.revealed_at is not null
      ) tl)
  );
  return j;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ws_customers()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'total',(select count(*) from customers),
      'verified',(select count(*) from customers where phone_verified is true or email_verified is true),
      'banned',(select count(*) from customers where banned is true),
      'with_rfqs',(select count(distinct customer_id) from inquiries where customer_id is not null)
    ),
    'success', jsonb_build_object(
      'kpis', coalesce((select to_jsonb(k) from customer_kpis k),'{}'::jsonb),
      'open_escalations', (select count(*) from agent_actions where kind='customer_escalation' and status in ('pending','needs_review')),
      'attention', coalesce((select jsonb_agg(a) from (
          select jsonb_build_object('id',customer_id,'name',coalesce(full_name,email),'health',health,
            'engagement',engagement,'satisfaction',satisfaction,'progress',progress,'service',service,
            'risk_tier',risk_tier,'stalled',stalled_inq,'disputes',disputes,'dormant',dormant) a
          from customer_health where risk_tier in ('high','medium') order by health asc limit 10) t),'[]'::jsonb),
      'trend', coalesce((select jsonb_agg(jsonb_build_object('d',snapshot_date,'health',(kpis->>'avg_health')) order by snapshot_date)
          from (select snapshot_date, kpis from customer_kpi_snapshots order by snapshot_date desc limit 14) s),'[]'::jsonb)
    ),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'full_name',c.full_name,'email',c.email,'phone',c.phone,
        'phone_verified',c.phone_verified,'email_verified',c.email_verified,'banned',c.banned,'created_at',c.created_at,
        'rfqs',(select count(*) from inquiries i where i.customer_id=c.id),
        'projects',(select count(*) from projects p where p.customer_id=c.id))) from (select * from customers order by created_at desc limit 100) c),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_documents()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'documents',(select count(*) from documents),
      'inventory_total',(select count(*) from document_inventory),
      'dropbox_files',(select count(*) from dropbox_files where not is_folder),
      'indexed',(select count(*) from documents where indexed is true),
      'reviews_pending',(select count(*) from doc_reviews where coalesce(status,'')='pending'),
      'versions',(select count(*) from doc_versions)
    ),
    'controller', jsonb_build_object(
      'health', (select (kpis->>'doc_health')::numeric from document_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from document_kpis k),
      'by_bucket', coalesce((select jsonb_agg(jsonb_build_object('bucket',bucket,'docs',c,'bytes',b,'past_retention',pr,'class',cls) order by c desc)
          from (select bucket, count(*) c, sum(bytes) b, count(*) filter (where past_retention) pr, max(retention_class) cls from document_inventory group by bucket) t),'[]'::jsonb),
      'dropbox', jsonb_build_object(
        'connected', (select (max(synced_at) is not null) from dropbox_files),
        'files', (select count(*) from dropbox_files where not is_folder),
        'folders', (select count(*) from dropbox_files where is_folder),
        'bytes', (select coalesce(sum(size),0) from dropbox_files),
        'last_sync', (select max(synced_at) from dropbox_files),
        'top_folders', coalesce((select jsonb_agg(jsonb_build_object('path',path,'items',n) order by n desc)
            from (select split_part(path,'/',2) path, count(*) n from dropbox_files where path like '/%/%' group by 1 order by 2 desc limit 8) t),'[]'::jsonb)
      ),
      'retention', coalesce((select jsonb_agg(jsonb_build_object('bucket',bucket,'class',class,'retention_days',retention_days) order by bucket) from retention_policy),'[]'::jsonb),
      'tasks', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation)) from agent_actions where agent='document_controller' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'documents', coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'kind',kind,'ref_table',ref_table,'ref_id',ref_id,'status',status,'indexed',indexed,'created_at',created_at)) from (select * from documents order by created_at desc limit 40) d),'[]'::jsonb),
    'reviews', coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'ai_category',ai_category,'ai_summary',ai_summary,'ai_confidence',ai_confidence,'status',status,'created_at',created_at)) from (select * from doc_reviews order by created_at desc limit 20) r),'[]'::jsonb),
    'kinds', coalesce((select jsonb_agg(jsonb_build_object('key',k,'count',c) order by c desc) from (select coalesce(nullif(kind,''),'other') k, count(*) c from documents group by 1) kk),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_ea()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'today_events', a->'today'->'events',
    'reminders_due', a->'today'->'reminders_due',
    'upcoming_events', a->'upcoming_events',
    'open_tasks', a->'open_tasks',
    'overdue_tasks', (a->>'overdue_tasks')::int,
    'approvals_total', (a->'approvals_to_clear'->>'total')::int,
    'approvals_high_risk', (a->'approvals_to_clear'->>'high_risk')::int,
    'approvals_top', a->'approvals_to_clear'->'top',
    'recent_meetings', a->'recent_meetings'
  )
  from (select fn_ea_agenda(7) a) x;
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_exec()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'command', fn_os_command(),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'priority',priority,'due',due_date,'entity',entity)) from (select * from crm_tasks order by (coalesce(status,'')='done'), created_at desc limit 8) t),'[]'::jsonb),
    'approvals', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'title',title,'kind',kind,'risk',risk,'status',status,'created_at',created_at)) from (select * from agent_actions where status='pending' order by created_at desc limit 6) a),'[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object('actor',actor,'kind',kind,'decision',decision,'confidence',confidence,'route_to',route_to,'created_at',created_at)) from (select * from decision_log order by created_at desc limit 10) d),'[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(jsonb_build_object('type',type,'subject',subject,'status',status,'created_at',created_at)) from (select * from notifications order by created_at desc limit 6) n),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_finance()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  cash_total numeric(18,2); rev_total numeric(18,2); exp_total numeric(18,2);
  rev30 numeric(18,2); exp30 numeric(18,2); monthly_burn numeric(18,2); runway numeric(18,1);
  j jsonb;
begin
  select coalesce(sum(balance),0) into cash_total from public.gl_account_balances where code in ('1000','1050');
  select coalesce(sum(balance),0) into rev_total from public.gl_account_balances where type='revenue';
  select coalesce(sum(balance),0) into exp_total from public.gl_account_balances where type='expense';

  -- 30-day run-rate (posted activity)
  select
    coalesce(sum(case when ga.type='revenue' then l.credit-l.debit else 0 end),0),
    coalesce(sum(case when ga.type='expense' then l.debit-l.credit else 0 end),0)
    into rev30, exp30
  from public.gl_journal_lines l
  join public.gl_journal j2 on j2.id=l.journal_id and j2.status='posted'
  join public.gl_accounts ga on ga.code=l.account_code
  where j2.entry_date >= current_date - 30;

  monthly_burn := exp30 - rev30;                       -- net cash burn (positive = burning)
  runway := case when monthly_burn > 0 and cash_total > 0 then round(cash_total/monthly_burn,1) else null end;

  j := jsonb_build_object(
    'as_of', now(),
    'cash', jsonb_build_object(
      'total', cash_total,
      'accounts', coalesce((select jsonb_agg(jsonb_build_object('code',code,'name',name,'balance',balance) order by code)
                   from public.gl_account_balances where code in ('1000','1050','1100','1110','1150','1500','1600')),'[]'::jsonb)
    ),
    'pnl', jsonb_build_object(
      'revenue', rev_total, 'expenses', exp_total, 'net_income', rev_total-exp_total,
      'margin_pct', case when rev_total>0 then round(100.0*(rev_total-exp_total)/rev_total,1) else null end
    ),
    'run_rate', jsonb_build_object(
      'revenue_30d', rev30, 'expense_30d', exp30, 'net_30d', rev30-exp30,
      'arr_estimate', round(rev30*12,2), 'monthly_burn', monthly_burn,
      'runway_months', runway
    ),
    'monetization', jsonb_build_object(
      'reveal_fees', (select coalesce(balance,0) from public.gl_account_balances where code='4000'),
      'commissions', (select coalesce(balance,0) from public.gl_account_balances where code='4100'),
      'registration', (select coalesce(balance,0) from public.gl_account_balances where code='4200'),
      'stripe_fees', (select coalesce(balance,0) from public.gl_account_balances where code='6100')
    ),
    'revenue_breakdown', coalesce((select jsonb_agg(jsonb_build_object('code',code,'name',name,'amount',balance) order by balance desc)
        from public.gl_account_balances where type='revenue' and balance<>0),'[]'::jsonb),
    'expense_breakdown', coalesce((select jsonb_agg(jsonb_build_object('code',code,'name',name,'amount',balance) order by balance desc)
        from public.gl_account_balances where type='expense' and balance<>0),'[]'::jsonb),
    'receivables', jsonb_build_object(
      'commission_receivable', (select coalesce(balance,0) from public.gl_account_balances where code='1110'),
      'trade_receivable', (select coalesce(balance,0) from public.gl_account_balances where code='1100'),
      'overdue_commissions', (select coalesce(sum(amount_due),0) from public.supplier_dues
                              where status not in ('paid','settled') and coalesce(due_date,reveal_date) < current_date)
    ),
    'payables', jsonb_build_object(
      'ap_open', (select coalesce(sum(total-amount_paid),0) from public.ap_bills where status in ('open','partial')),
      'aging', coalesce((select jsonb_agg(to_jsonb(a)) from public.ap_aging a),'[]'::jsonb)
    ),
    'cashflow', coalesce((
      select jsonb_agg(x order by x->>'month')
      from (
        select jsonb_build_object(
          'month', to_char(date_trunc('month',j3.entry_date),'YYYY-MM'),
          'inflow', sum(l.debit), 'outflow', sum(l.credit), 'net', sum(l.debit-l.credit)
        ) x
        from public.gl_journal_lines l
        join public.gl_journal j3 on j3.id=l.journal_id and j3.status='posted'
        where l.account_code in ('1000','1050')
          and j3.entry_date >= (date_trunc('month',current_date) - interval '5 months')
        group by date_trunc('month',j3.entry_date)
      ) s
    ),'[]'::jsonb),
    'budgets', coalesce((select jsonb_agg(to_jsonb(b)) from public.budget_vs_actual_summary b),'[]'::jsonb)
  );
  j := j || jsonb_build_object('ai', jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.finance_kpis k),
    'forecast', public.fn_finance_forecast(),
    'health', (select (kpis->>'health')::numeric from public.finance_kpi_snapshots order by snapshot_date desc limit 1),
    'open_alerts', (select count(*) from public.agent_actions where agent='finance_ai' and status in ('pending','needs_review')),
    'alerts', coalesce((select jsonb_agg(jsonb_build_object('signal',detail->>'signal','risk',risk,'title',title,'reco',recommendation))
        from public.agent_actions where agent='finance_ai' and status in ('pending','needs_review')),'[]'::jsonb),
    'trend', coalesce((select jsonb_agg(jsonb_build_object('d',snapshot_date,'health',(kpis->>'health'),'cash',(kpis->>'cash')) order by snapshot_date)
        from (select snapshot_date,kpis from public.finance_kpi_snapshots order by snapshot_date desc limit 14) s),'[]'::jsonb)
  ));
  return j;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ws_fraud()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'open_flags', (select count(*) from fraud_flags where coalesce(status,'open') not in ('dismissed','resolved','closed')),
      'high_severity', (select count(*) from fraud_flags where lower(coalesce(severity,'')) in ('high','critical') and coalesce(status,'open') not in ('dismissed','resolved','closed')),
      'flags_7d', (select count(*) from fraud_flags where created_at > now() - interval '7 days'),
      'banned_actors', (select (select count(*) from customers where banned) + (select count(*) from leads where banned))
    ),
    'open_flags', (select coalesce(jsonb_agg(f order by f.created desc),'[]'::jsonb) from (
        select kind, subject_type, subject_id, coalesce(severity,'—') severity, coalesce(status,'open') status,
               to_char(created_at,'YYYY-MM-DD HH24:MI') created, detail
        from fraud_flags where coalesce(status,'open') not in ('dismissed','resolved','closed')
        order by created_at desc limit 100) f),
    'banned', (select coalesce(jsonb_agg(b),'[]'::jsonb) from (
        select 'customer' kind, id::text subject_id, full_name name, banned_reason reason from customers where banned
        union all
        select 'supplier', id::text, company_name, banned_reason from leads where banned limit 100) b)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_governance()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.governance_kpis k),
    'universal_rules', (select universal_rules from public.agent_governance where active order by version desc limit 1),
    'response_structure', (select response_structure from public.agent_governance where active order by version desc limit 1),
    'recent_escalations', (select coalesce(jsonb_agg(e),'[]'::jsonb) from (
        select agent, title, coalesce(escalation_reason,'—') as reason, confidence, to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions where escalated order by created_at desc limit 15) e),
    'agent_coverage', (select coalesce(jsonb_agg(c),'[]'::jsonb) from (
        select ca.name as agent, (ca.persona is not null) as has_persona,
               exists(select 1 from public.agent_knowledge k where k.agent_key='cat:'||ca.slug or k.agent_key=ca.slug) as has_knowledge,
               (select count(*) from public.agent_actions a where a.agent=ca.slug) as audit_items
        from public.category_agents ca where ca.active order by ca.name limit 60) c)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_knowledge()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'chunks',(select count(*) from kb_chunks),
      'document_chunks',(select count(*) from kb_chunks where source_kind='document'),
      'categories',(select count(distinct category) from kb_chunks),
      'category_specs',(select count(*) from category_specs)
    ),
    'curator', jsonb_build_object(
      'health', (select (kpis->>'health')::numeric from knowledge_kpi_snapshots order by snapshot_date desc limit 1),
      'coverage_pct', k.coverage_pct, 'knowledge_coverage_pct', k.knowledge_coverage_pct, 'playbook_coverage_pct', k.playbook_coverage_pct,
      'accuracy_pct', k.accuracy_pct, 'freshness_pct', k.freshness_pct, 'usage_reach_pct', k.usage_reach_pct,
      'regulations', k.regulations, 'regulations_pending', k.regulations_pending, 'standards', k.standards, 'manufacturers', k.manufacturers, 'brands', k.brands, 'materials', k.materials, 'playbooks', k.playbooks,
      'open_items', (select count(*) from agent_actions where agent='knowledge_curator' and status in ('pending','needs_review')),
      'tasks', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation))
          from agent_actions where agent='knowledge_curator' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'reg_library', jsonb_build_object(
      'coverage', (select to_jsonb(rc) from reg_coverage rc),
      'indexed', coalesce((select jsonb_agg(jsonb_build_object('authority',authority,'code',code_name,'domain',domain) order by authority) from reg_catalog where status='indexed'),'[]'::jsonb),
      'missing', coalesce((select jsonb_agg(jsonb_build_object('authority',authority,'code',code_name,'domain',domain,'priority',priority,'status',status) order by priority, authority) from reg_catalog where copyright='free' and status<>'indexed'),'[]'::jsonb),
      'reference_only', coalesce((select jsonb_agg(jsonb_build_object('authority',authority,'code',code_name) order by authority) from reg_catalog where copyright='copyrighted'),'[]'::jsonb)
    ),
    'regulations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'status',authority||coalesce(' · '||status,''),'source_url',source_url) order by coalesce(effective_date, created_at) desc)
        from (select * from regulations order by coalesce(effective_date, created_at) desc limit 20) rg),'[]'::jsonb),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('key',cat,'count',c) order by c desc) from (
        select coalesce(nullif(category,''),'general') cat, count(*) c from kb_chunks group by 1 order by 2 desc limit 16) kk),'[]'::jsonb),
    'coverage', coalesce((select jsonb_agg(jsonb_build_object('category',cs.category,'label',cs.label,'chunks',cc.n,'status',case when cc.n=0 then 'gap' when cc.n<3 then 'thin' else 'covered' end) order by cc.n asc, cs.category)
        from category_specs cs left join lateral (select count(*) n from kb_chunks kb where kb.category=cs.category) cc on true),'[]'::jsonb),
    'coverage_kpis', jsonb_build_object(
        'gaps',(select count(*) from category_specs cs where not exists(select 1 from kb_chunks kb where kb.category=cs.category)),
        'thin',(select count(*) from category_specs cs where (select count(*) from kb_chunks kb where kb.category=cs.category) between 1 and 2),
        'covered',(select count(*) from category_specs cs where (select count(*) from kb_chunks kb where kb.category=cs.category) >= 3),
        'total',(select count(*) from category_specs)
    ),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'category',category,'citation',citation)) from (select * from kb_chunks order by created_at desc limit 20) c),'[]'::jsonb)
  )
  from knowledge_kpis k;
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_marketing()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'health', (select (kpis->>'health')::numeric from marketing_snapshots order by snapshot_date desc limit 1),
    'inquiries_30d', k.inquiries_30d, 'quoted_30d', k.quoted_30d, 'revealed_30d', k.revealed_30d,
    'revenue_30d', k.revenue_30d, 'inq_to_quote_pct', k.inq_to_quote_pct, 'quote_to_reveal_pct', k.quote_to_reveal_pct,
    'blog_published', k.blog_published, 'drafts_pending', k.drafts_pending,
    'social_staged', k.social_staged, 'social_published', k.social_published,
    'seo_pages', k.seo_pages, 'seo_gaps', k.seo_gaps, 'supply_gaps', k.supply_gaps,
    'leads_total', k.leads_total, 'outreach_sent', k.outreach_sent,
    'meta', jsonb_build_object(
      'spend_30d', k.meta_spend_30d, 'clicks_30d', k.meta_clicks_30d, 'results_30d', k.meta_results_30d,
      'impressions_30d', k.meta_impressions_30d, 'active_campaigns', k.meta_active_campaigns,
      'cpl', k.meta_cpl, 'roi', k.meta_roi,
      'sync', (select case when (select value from app_secrets where key='meta_access_token') is not null then 'connected' else 'awaiting_token' end),
      'campaigns', coalesce((select jsonb_agg(jsonb_build_object('name',campaign_name,'status',effective_status,'spend',spend,'clicks',clicks,'results',results))
          from meta_insights where time_window='last_30d' and campaign_name ilike '%quotesdone%'),'[]'::jsonb)
    ),
    'priorities', coalesce((select plan->'priorities' from marketing_snapshots order by snapshot_date desc limit 1),'[]'::jsonb),
    'push_supply', coalesce((select jsonb_agg(jsonb_build_object('category',category,'inquiries_90d',inquiries_90d,'suppliers',suppliers) order by inquiries_90d desc)
        from (select * from marketing_category_demand where inquiries_90d>0 and suppliers=0 order by inquiries_90d desc limit 10) t),'[]'::jsonb),
    'recommendations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation))
        from agent_actions where agent='marketing_ai' and status in ('pending','needs_review')),'[]'::jsonb)
  )
  from marketing_kpis k;
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_marketplace()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'rfqs',(select count(*) from inquiries),
      'active',(select count(*) from inquiries where coalesce(status,'') not in ('completed','cancelled','closed')),
      'quotes',(select count(*) from quotes),
      'avg_value',(select round(avg(expected_value)) from inquiries where expected_value is not null),
      'hired',(select count(*) from inquiries where hired_supplier_id is not null),
      'transactions',(select count(*) from transactions)
    ),
    'kanban', coalesce((select jsonb_agg(jsonb_build_object('key',stg,'count',c) order by c desc) from (
        select coalesce(nullif(pipeline_stage,''),coalesce(nullif(status,''),'new')) stg, count(*) c from inquiries group by 1) k),'[]'::jsonb),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id',id,'category',category,'emirate',emirate,'summary',summary,
        'status',status,'pipeline_stage',pipeline_stage,'deal_owner',deal_owner,'expected_value',expected_value,
        'budget',budget,'rfq_ready',rfq_ready,'created_at',created_at) ) from (select * from inquiries order by created_at desc limit 50) i),'[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id',id,'inquiry_id',inquiry_id,'supplier_id',supplier_id,
        'quote_amount',quote_amount,'customer_price',customer_price,'status',status,'created_at',created_at)) from (select * from quotes order by created_at desc limit 30) q),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_operations()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'ops', jsonb_build_object(
      'health', (select (kpis->>'ops_health')::numeric from ops_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from ops_kpis k),
      'recommendations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation)) from agent_actions where agent='operations_ai' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'security', jsonb_build_object(
      'score', (select (kpis->>'security_score')::numeric from security_kpi_snapshots order by snapshot_date desc limit 1),
      'kpis', (select to_jsonb(k) from security_kpis k),
      'incidents', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk)) from agent_actions where agent='security_ai' and status in ('pending','needs_review')),'[]'::jsonb),
      'events', coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'severity',severity,'source',source,'at',created_at) order by created_at desc) from (select * from security_events order by created_at desc limit 10) e),'[]'::jsonb)
    ),
    'kpis', jsonb_build_object(
      'approvals_pending',(select count(*) from agent_actions where status='pending'),
      'high_risk',(select count(*) from agent_actions where status='pending' and coalesce(risk,'') in ('high','critical')),
      'tasks_open',(select count(*) from crm_tasks where coalesce(status,'')<>'done'),
      'decisions_24h',(select count(*) from decision_log where created_at > now()-interval '24 hours'),
      'disputes',(select count(*) from transactions where coalesce(refund_status,'') in ('requested','pending'))
    ),
    'approvals', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'kind',kind,'risk',risk,'title',title,
        'recommendation',recommendation,'status',status,'target_table',target_table,'created_at',created_at)) from (
        select * from agent_actions where status='pending' order by (coalesce(risk,'')='critical') desc, created_at desc limit 30) a),'[]'::jsonb),
    'decisions', coalesce((select jsonb_agg(jsonb_build_object('id',id,'actor',actor,'kind',kind,'decision',decision,
        'confidence',confidence,'route_to',route_to,'created_at',created_at)) from (select * from decision_log order by created_at desc limit 20) d),'[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'priority',priority,'due',due_date,'source',source,'entity',entity)) from (select * from crm_tasks order by (coalesce(status,'')='done'), created_at desc limit 20) t),'[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_refunds()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'pending', (select count(*) from transactions where refund_status in ('requested','pending')),
      'within_window', (select count(*) from transactions where refund_status in ('requested','pending') and refund_deadline > now()),
      'resolved_30d', (select count(*) from transactions where refund_resolved_at > now() - interval '30 days')
    ),
    'pending', (select coalesce(jsonb_agg(r order by r.requested desc),'[]'::jsonb) from (
        select t.id as transaction_id, t.quote_id, t.reveal_fee, coalesce(t.refund_status,'—') refund_status, coalesce(t.refund_reason,'—') reason,
               to_char(t.refund_requested_at,'YYYY-MM-DD') requested, to_char(t.refund_deadline,'YYYY-MM-DD') deadline,
               (t.refund_deadline > now()) in_window, coalesce(c.full_name,'—') customer, coalesce(l.company_name,'—') supplier
        from transactions t left join customers c on c.id=t.customer_id left join leads l on l.id=t.supplier_id
        where t.refund_status in ('requested','pending') order by t.refund_requested_at desc limit 100) r),
    'recent_resolved', (select coalesce(jsonb_agg(r order by r.resolved desc),'[]'::jsonb) from (
        select t.id as transaction_id, t.quote_id, coalesce(t.refund_status,'—') refund_status, coalesce(t.refund_note,'—') note,
               to_char(t.refund_resolved_at,'YYYY-MM-DD') resolved
        from transactions t where t.refund_resolved_at is not null order by t.refund_resolved_at desc limit 25) r)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_reports()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.report_kpis k),
    'freshness', (select jsonb_build_object(
        'daily', daily_fresh, 'weekly', weekly_fresh, 'monthly', monthly_fresh, 'quarterly', quarterly_fresh,
        'department', department_fresh, 'supplier', supplier_fresh, 'customer', customer_fresh, 'ai', ai_fresh
      ) from public.report_kpis),
    'recent', (select coalesce(jsonb_agg(r), '[]'::jsonb) from (
        select id, source, report_type, title, period,
               case source when 'exec' then 'exec' when 'narrative' then 'board' else source end as src,
               to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from public.report_registry order by created_at desc limit 25) r),
    'by_type', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
        select report_type, id, title,
               case source when 'exec' then 'exec' when 'narrative' then 'board' else source end as src,
               to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from (
          select distinct on (report_type) report_type, id, source, title, created_at
          from public.report_registry order by report_type, created_at desc
        ) x order by report_type) t),
    'flags', (select coalesce(jsonb_agg(f), '[]'::jsonb) from (
        select title, risk, status, to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions
        where agent='reporting_ai' and kind='report_task' and status in ('pending','needs_review')
        order by created_at desc) f)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_rfq_360(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare i public.inquiries%rowtype; j jsonb; docs jsonb := '[]'::jsonb; hired text;
begin
  select * into i from public.inquiries where id=p_id;
  if i.id is null then return jsonb_build_object('error','RFQ not found'); end if;
  if i.drawing_file_path is not null then docs := docs || jsonb_build_object('type','Drawing','name',coalesce(i.drawing_file_name,'drawing'),'path',i.drawing_file_path); end if;
  if i.drawing_redacted_paths is not null then
    docs := docs || coalesce((select jsonb_agg(jsonb_build_object('type','Drawing (redacted)','name','redacted','path',x)) from unnest(i.drawing_redacted_paths) x),'[]'::jsonb);
  end if;
  select company_name into hired from public.leads where id=i.hired_supplier_id;
  j := jsonb_build_object(
    'requirements', jsonb_build_object('category',i.category,'emirate',i.emirate,'role_needed',i.role_needed,
       'summary',i.summary,'spec',i.spec,'boq',i.boq,'boq_confidence',i.boq_confidence,'budget',i.budget,
       'scope_type',i.scope_type,'trades',i.trades,'keywords',i.keywords),
    'status', jsonb_build_object('status',i.status,'pipeline_stage',i.pipeline_stage,'deal_owner',i.deal_owner,
       'expected_value',i.expected_value,'outcome',i.outcome,'lost_reason',i.lost_reason,'completed_at',i.completed_at,
       'project_id',i.project_id,'created_at',i.created_at),
    'ai_qualification', jsonb_build_object('completeness',i.completeness,'rfq_ready',i.rfq_ready,'routing',i.routing,'brief_source',i.brief_source),
    'selected_supplier', case when i.hired_supplier_id is not null then jsonb_build_object('id',i.hired_supplier_id,'company_name',hired) else null end,
    'documents', docs,
    'matching', coalesce((select jsonb_agg(jsonb_build_object('supplier_id',m.supplier_id,'company_name',l.company_name,
       'similarity',m.similarity,'match_reason',m.match_reason,'sent_at',m.sent_at) order by m.similarity desc nulls last)
       from public.inquiry_matches m left join public.leads l on l.id=m.supplier_id where m.inquiry_id=p_id),'[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'supplier_id',q.supplier_id,'company_name',l.company_name,
       'amount',q.quote_amount,'status',q.status,'lead_time',q.lead_time,'validity',q.validity,'quality',q.quality,
       'created_at',q.created_at) order by q.quote_amount asc nulls last)
       from public.quotes q left join public.leads l on l.id=q.supplier_id where q.inquiry_id=p_id),'[]'::jsonb),
    'procurement', public.fn_procurement_analysis(p_id),
    'clarifications', coalesce((select jsonb_agg(jsonb_build_object('question',qn.question,'answer',qn.answer,
       'supplier_id',qn.supplier_id,'asked_at',qn.asked_at,'answered_at',qn.answered_at) order by qn.asked_at desc)
       from public.questions qn where qn.inquiry_id=p_id),'[]'::jsonb),
    'timeline', (select jsonb_agg(e order by e->>'at' desc) from (
        select jsonb_build_object('at',i.created_at,'event','RFQ created') e
        union all select jsonb_build_object('at',m.sent_at,'event','Matched supplier') from public.inquiry_matches m where m.inquiry_id=p_id and m.sent_at is not null
        union all select jsonb_build_object('at',q.created_at,'event','Quote received: AED '||coalesce(q.quote_amount::text,'?')) from public.quotes q where q.inquiry_id=p_id
        union all select jsonb_build_object('at',i.completed_at,'event','Completed'||coalesce(' ('||i.outcome||')','')) where i.completed_at is not null
      ) tl)
  );
  return j;
end $function$


CREATE OR REPLACE FUNCTION public.fn_ws_strategy()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from public.strategy_kpis k),
    'risks', (select coalesce(jsonb_agg(r),'[]'::jsonb) from (
        select title, category, score, likelihood, impact, status
        from public.strategy_risks where status<>'closed' order by score desc limit 20) r),
    'recommendations', (select coalesce(jsonb_agg(x),'[]'::jsonb) from (
        select title, risk, to_char(created_at,'YYYY-MM-DD') as created
        from public.agent_actions where agent='strategy_ai' and kind='strategy_rec'
          and status in ('pending','needs_review') order by array_position(array['high','medium','low']::text[],risk)) x),
    'under_supplied', coalesce(fn_strategy_metrics()->'under_supplied','[]'::jsonb),
    'market_intel', (select coalesce(jsonb_agg(m),'[]'::jsonb) from (
        select kind, title, impact, status, coalesce(source,'—') as source
        from public.market_intel where status<>'dismissed' order by created_at desc limit 20) m),
    'recent_simulations', (select coalesce(jsonb_agg(s),'[]'::jsonb) from (
        select coalesce(scenario->>'type','scenario') as title,
               to_char(created_at,'YYYY-MM-DD HH24:MI') as created
        from public.simulations order by created_at desc limit 8) s)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_ws_supplier_360(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
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
end $function$


CREATE OR REPLACE FUNCTION public.fn_ws_suppliers(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_q text := nullif(trim(coalesce(p->>'q','')),'');
  v_emirate text := nullif(p->>'emirate','');
  v_sector text := nullif(p->>'sector','');
  v_approval text := nullif(p->>'approval','');
  v_limit int := least(coalesce((p->>'limit')::int,50),100);
  v_offset int := greatest(coalesce((p->>'offset')::int,0),0);
  v_rows jsonb; v_total bigint;
begin
  select count(*) into v_total from leads
   where coalesce(source,'') <> 'canary'
     and (v_q is null or company_name ilike '%'||v_q||'%' or categories ilike '%'||v_q||'%')
     and (v_emirate is null or emirate=v_emirate)
     and (v_sector is null or sector=v_sector)
     and (v_approval is null or approval_status=v_approval);

  select coalesce(jsonb_agg(r),'[]'::jsonb) into v_rows from (
    select jsonb_build_object('id',id,'company_name',company_name,'sector',sector,'sub_type',sub_type,
      'emirate',emirate,'city',city,'rating',rating,'reviews',reviews,'categories',categories,
      'approval_status',approval_status,'lifecycle_stage',lifecycle_stage,'verified',verified,
      'verification_status',verification_status,'capability_score',capability_score,'invite_status',invite_status,
      'registration_status',registration_status,'license_expiry',license_expiry,'banned',banned,
      'matching_blocked',matching_blocked,'phone',phone,'website',website,'created_at',created_at) as r
    from leads
    where coalesce(source,'') <> 'canary'
      and (v_q is null or company_name ilike '%'||v_q||'%' or categories ilike '%'||v_q||'%')
      and (v_emirate is null or emirate=v_emirate)
      and (v_sector is null or sector=v_sector)
      and (v_approval is null or approval_status=v_approval)
    order by capability_score desc nulls last, reviews desc nulls last
    limit v_limit offset v_offset
  ) x;

  return jsonb_build_object(
    'kpis', jsonb_build_object(
      'total',(select count(*) from leads where coalesce(source,'') <> 'canary'),
      'approved',(select count(*) from leads where approval_status='approved'),
      'pending_review',(select count(*) from leads where coalesce(approval_status,'') in ('submitted','pending','under_review','pending_review')),
      'verified',(select count(*) from leads where verified is true),
      'registered',(select count(*) from leads where registration_paid_at is not null),
      'licenses_expiring',(select count(*) from leads where license_expiry is not null and license_expiry < (now()+interval '30 days')::date and license_expiry >= now()::date),
      'banned',(select count(*) from leads where banned is true),
      'matching_blocked',(select count(*) from leads where matching_blocked is true)
    ),
    'success', jsonb_build_object(
      'kpis', coalesce((select to_jsonb(k) from supplier_kpis k), '{}'::jsonb),
      'open_risk', (select count(*) from agent_actions where kind='supplier_risk' and status in ('pending','needs_review')),
      'attention', coalesce((select jsonb_agg(a) from (
          select jsonb_build_object('id',supplier_id,'company_name',company_name,'health',health,
            'quality',quality,'compliance',compliance,'response',response,'retention',retention,
            'risk_tier',risk_tier,'dormant',dormant) a
          from supplier_health where risk_tier in ('high','medium') order by health asc limit 10) t),'[]'::jsonb),
      'trend', coalesce((select jsonb_agg(jsonb_build_object('d',snapshot_date,'health',(kpis->>'avg_health')) order by snapshot_date)
          from (select snapshot_date, kpis from supplier_kpi_snapshots order by snapshot_date desc limit 14) s),'[]'::jsonb)
    ),
    'kanban', coalesce((select jsonb_agg(jsonb_build_object('key',stg,'count',c) order by c desc) from (
        select coalesce(nullif(lifecycle_stage,''),'directory') stg, count(*) c from leads where coalesce(source,'') <> 'canary' group by 1 order by 2 desc limit 8) k),'[]'::jsonb),
    'sectors', coalesce((select jsonb_agg(jsonb_build_object('key',s,'count',c) order by c desc) from (
        select coalesce(nullif(sector,''),'other') s, count(*) c from leads where coalesce(source,'') <> 'canary' group by 1 order by 2 desc limit 10) s),'[]'::jsonb),
    'emirates', coalesce((select jsonb_agg(jsonb_build_object('key',e,'count',c) order by c desc) from (
        select coalesce(nullif(emirate,''),'—') e, count(*) c from leads where coalesce(source,'') <> 'canary' group by 1 order by 2 desc limit 10) e),'[]'::jsonb),
    'total', v_total, 'limit', v_limit, 'offset', v_offset, 'rows', v_rows
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.funnel_metrics(days integer DEFAULT 30)
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with w as (select (now() - make_interval(days => days)) as since)
  select json_build_object(
    'days', days,
    'inquiries', (select count(*) from public.inquiries i, w where i.created_at>=w.since),
    'matched', (select count(distinct m.inquiry_id) from public.inquiry_matches m join public.inquiries i on i.id=m.inquiry_id, w where i.created_at>=w.since),
    'quoted', (select count(distinct q.inquiry_id) from public.quotes q join public.inquiries i on i.id=q.inquiry_id, w where i.created_at>=w.since),
    'revealed', (select count(*) from public.transactions t join public.inquiries i on i.id=t.inquiry_id, w where t.revealed_at is not null and i.created_at>=w.since),
    'completed', (select count(*) from public.inquiries i, w where i.status='completed' and i.created_at>=w.since),
    'cancelled', (select count(*) from public.inquiries i, w where i.status='cancelled' and i.created_at>=w.since),
    'reveal_fees', (select coalesce(sum(t.reveal_fee),0) from public.transactions t join public.inquiries i on i.id=t.inquiry_id, w where t.revealed_at is not null and i.created_at>=w.since)
  );
$function$


CREATE OR REPLACE FUNCTION public.hook_password_verification_attempt(event jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_uid uuid; v_valid boolean; v_email text; v_recent int;
begin
  begin v_uid := (event->>'user_id')::uuid; exception when others then v_uid := null; end;
  v_valid := coalesce((event->>'valid')::boolean, true);
  if not v_valid then
    begin select email into v_email from auth.users where id = v_uid; exception when others then v_email := null; end;
    select count(*) into v_recent from public.security_events
      where kind='login_failed' and subject = coalesce(v_email,'')
        and created_at > now() - interval '15 minutes';
    insert into public.security_events(kind, severity, source, subject, detail)
    values ('login_failed',
            case when v_recent >= 4 then 'high' else 'medium' end,
            'password',
            coalesce(v_email,''),
            jsonb_build_object('user_id', v_uid, 'recent_15m', v_recent + 1,
                               'why', 'password verification failed'));
  end if;
  return '{}'::jsonb;
end $function$


CREATE OR REPLACE FUNCTION public.is_disposable_email(p_email text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (
    select 1 from app_blocked_domains d
    where d.domain = lower(split_part(p_email,'@',2))
  );
$function$


CREATE OR REPLACE FUNCTION public.kb_match(query_embedding vector, match_count integer DEFAULT 8, p_category text DEFAULT NULL::text)
 RETURNS TABLE(id bigint, category text, title text, citation text, content text, similarity double precision)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with want as (
    select nullif(regexp_replace(lower(p_category),'^cat:',''),'') as c
  ), cats as (
    select c as cat from want where c is not null
    union
    select a.maps_to from kb_category_aliases a, want w where a.category = w.c
  ), src as materialized (
    select k.id, k.category, k.title, k.citation, k.content, k.embedding_gte
    from public.kb_chunks k
    where k.embedding_gte is not null
      and ((select c from want) is null or k.category_norm in (select cat from cats))
  )
  select s.id, s.category, s.title, s.citation, s.content,
         1 - (s.embedding_gte <=> query_embedding) as similarity
  from src s
  order by s.embedding_gte <=> query_embedding
  limit match_count;
$function$


CREATE OR REPLACE FUNCTION public.kb_query(p_query text, p_category text DEFAULT NULL::text, p_limit integer DEFAULT 8)
 RETURNS TABLE(source_kind text, category text, title text, snippet text, citation text, effective_date date, rank real)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with q as (select websearch_to_tsquery('english', coalesce(p_query,'')) as tsq)
  select c.source_kind, c.category, c.title, left(c.content, 700) as snippet, c.citation, c.effective_date,
    (ts_rank(c.fts, q.tsq) + case when p_category is not null and c.category = p_category then 0.4 else 0 end)::real as rank
  from kb_chunks c, q
  where coalesce(p_query,'') = '' or c.fts @@ q.tsq
  order by rank desc nulls last, c.effective_date desc nulls last
  limit greatest(1, least(coalesce(p_limit,8), 25));
$function$


CREATE OR REPLACE FUNCTION public.kb_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  delete from kb_chunks where source_kind in ('regulation','trade','material');
  insert into kb_chunks(source_kind,source_id,category,title,content,citation,effective_date)
  select 'regulation', r.id::text, cat, r.title,
    coalesce(r.summary,'') || case when jsonb_array_length(coalesce(r.key_requirements,'[]'::jsonb))>0
      then E'\nKey requirements: ' || (select string_agg(x, '; ') from jsonb_array_elements_text(r.key_requirements) x) else '' end,
    r.authority || ' — ' || r.title || coalesce(' [' || r.source_url || ']','') || coalesce(' (effective ' || r.effective_date::text || ')',''),
    r.effective_date
  from regulations r
  left join lateral unnest(case when array_length(r.categories,1) is null then array[null::text] else r.categories end) as cat on true
  where r.status = 'active' and r.approved_at is not null;
  insert into kb_chunks(source_kind,source_id,category,title,content,citation,effective_date)
  select 'trade', ak.id::text, ak.agent_key, ak.topic, ak.content,
    'QuotesDone trade knowledge: ' || coalesce(ak.agent_key,'') || ' / ' || coalesce(ak.topic,''), null
  from agent_knowledge ak;
  insert into kb_chunks(source_kind,source_id,category,title,content,citation,effective_date)
  select 'material', m.id::text, m.category, m.item,
    m.item || ' — ' || coalesce(m.properties::text,'') ||
      case when array_length(m.standards,1) is not null then E'\nStandards: ' || array_to_string(m.standards,', ') else '' end ||
      case when m.price_band is not null then E'\nPrice band: ' || m.price_band else '' end,
    'QuotesDone material library: ' || m.item, null
  from materials m;
  select count(*) into n from kb_chunks;
  return jsonb_build_object('chunks', n);
end $function$


CREATE OR REPLACE FUNCTION public.kn_task(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_cond then
    if not exists (select 1 from agent_actions where kind='knowledge_task' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
      values ('knowledge_curator','knowledge_task','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'knowledge',p_sig);
    end if;
  else
    update agent_actions
      set status='resolved', decided_at=now(), decided_by='knowledge_curator (auto-resolved)'
      where kind='knowledge_task' and detail->>'signal'=p_sig and status in ('pending','needs_review');
  end if;
end $function$


CREATE OR REPLACE FUNCTION public.leg_flag(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='legal_flag' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values ('legal_ai','legal_flag','pending',p_risk,p_title,
      p_reco||E'\n\n⚠️ Not legal advice — this is a flag for you to review with a licensed UAE lawyer.',
      jsonb_build_object('signal',p_sig),'legal',p_sig);
  end if;
end $function$


CREATE OR REPLACE FUNCTION public.margin_rate(amount numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case
    when amount < 2000  then 0.10
    when amount < 5000  then 0.08
    when amount < 10000 then 0.06
    when amount < 20000 then 0.05
    when amount < 50000 then 0.04
    else 0.03 end
$function$


CREATE OR REPLACE FUNCTION public.mark_site_dirty()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update public.site_publish_state set dirty=true, last_change_at=now() where id=1;
  return null;
end$function$


CREATE OR REPLACE FUNCTION public.mask_contact(s text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when s is null then s else
    regexp_replace(
    regexp_replace(
    regexp_replace(
    regexp_replace(s,
      '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}', '[hidden until reveal]', 'gi'),
      '(https?://|www\.)[^[:space:]]+', '[hidden until reveal]', 'gi'),
      '\y[[:alnum:]-]{2,}\.(com|ae|net|org|io|me)\y', '[hidden until reveal]', 'gi'),
      '(\+?971|00971|0)[[:space:].-]?[0-9]{1,2}[[:space:].-]?[0-9]{3}[[:space:].-]?[0-9]{4}', '[hidden until reveal]', 'gi')
  end
$function$


CREATE OR REPLACE FUNCTION public.mask_contacts(t text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s text := t;
begin
  if s is null or s = '' then return s; end if;
  -- emails
  s := regexp_replace(s, '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}', '[hidden]', 'gi');
  -- explicit URLs
  s := regexp_replace(s, '(https?://|www\.)[^[:space:]]+', '[hidden]', 'gi');
  -- bare social / messenger short links (no scheme)
  s := regexp_replace(s, '(wa\.me|t\.me|bit\.ly|instagram\.com|facebook\.com|fb\.com|linkedin\.com|twitter\.com|x\.com)/[^[:space:]]*', '[hidden]', 'gi');
  -- international UAE numbers (+971 ...)
  s := regexp_replace(s, '\+?971[ \-]?[0-9][0-9 \-]{6,}[0-9]', '[hidden]', 'g');
  -- local UAE mobile  05x xxx xxxx  (9 digits starting 5, optional separators) — bounded so prices/qtys are safe
  s := regexp_replace(s, '\y0?5[0-9][ \-]?[0-9]{3}[ \-]?[0-9]{4}\y', '[hidden]', 'g');
  return s;
end;
$function$


CREATE OR REPLACE FUNCTION public.match_suppliers(query_embedding vector, match_count integer DEFAULT 10, p_emirate text DEFAULT NULL::text, p_role text DEFAULT NULL::text, p_product text DEFAULT NULL::text, p_min_rating numeric DEFAULT NULL::numeric)
 RETURNS TABLE(id bigint, company_name text, emirate text, business_role text, products text, services text, phone text, email text, whatsapp text, website text, rating numeric, reviews integer, capability_summary text, similarity double precision)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select l.id, l.company_name, l.emirate, l.business_role, l.products, l.services,
         l.phone, l.email, l.whatsapp, l.website, l.rating, l.reviews, l.capability_summary,
         1 - (l.embedding_gte <=> query_embedding) as similarity
  from public.leads l
  left join public.supplier_perf sp on sp.supplier_id = l.id
  where l.embedding_gte is not null
    and coalesce(l.matching_blocked,false)=false
    and (p_emirate is null or l.emirate ilike p_emirate)
    and (p_role    is null or l.business_role = p_role)
    and (p_product is null or l.products ilike '%'||p_product||'%' or l.capability_summary ilike '%'||p_product||'%')
    and (p_min_rating is null or l.rating >= p_min_rating)
  order by ( (1 - (l.embedding_gte <=> query_embedding))
             + 0.05 * coalesce(sp.perf_score,0)
             + case when l.claimed then 0.03 else 0 end
             + case when l.approval_status = 'approved' then 0.02 else 0 end ) desc
  limit match_count;
$function$


CREATE OR REPLACE FUNCTION public.match_suppliers_kw(p_keywords text[] DEFAULT '{}'::text[], p_category text DEFAULT NULL::text, p_emirate text DEFAULT NULL::text, p_role text DEFAULT NULL::text, p_min_rating numeric DEFAULT NULL::numeric, p_limit integer DEFAULT 8)
 RETURNS TABLE(id bigint, company_name text, emirate text, business_role text, products text, services text, phone text, email text, whatsapp text, website text, rating numeric, reviews integer, capability_summary text, match_score integer, in_emirate boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with base as (
    select l.id, l.company_name, l.emirate, l.business_role, l.products, l.services,
           l.phone, l.email, l.whatsapp, l.website, l.rating, l.reviews, l.capability_summary,
           (
             (select count(*) from unnest(p_keywords) k
                where l.products ilike '%'||k||'%' or l.capability_summary ilike '%'||k||'%'
                   or l.categories ilike '%'||k||'%' or l.company_name ilike '%'||k||'%')::int
             + case when p_category is not null and l.sector = p_category then 2 else 0 end
           ) as match_score,
           coalesce(
             p_emirate is not null and (
               l.emirate ilike p_emirate
               or exists (select 1 from unnest(coalesce(l.service_emirates, '{}')) se where se ilike p_emirate)
             ), false) as in_emirate
    from public.leads l
    where coalesce(l.permanently_closed, false) = false
      and (p_role is null or l.business_role = p_role)
      and (p_min_rating is null or l.rating >= p_min_rating)
      and (
        (p_category is not null and l.sector = p_category)
        or exists (select 1 from unnest(p_keywords) k
                     where l.products ilike '%'||k||'%' or l.capability_summary ilike '%'||k||'%'
                        or l.categories ilike '%'||k||'%' or l.company_name ilike '%'||k||'%')
      )
  )
  select id, company_name, emirate, business_role, products, services, phone, email, whatsapp,
         website, rating, reviews, capability_summary, match_score, in_emirate
  from base
  order by in_emirate desc, match_score desc, rating desc nulls last, reviews desc nulls last
  limit coalesce(p_limit, 8);
$function$


CREATE OR REPLACE FUNCTION public.match_suppliers_kw(p_keywords text[] DEFAULT '{}'::text[], p_category text DEFAULT NULL::text, p_emirate text DEFAULT NULL::text, p_role text DEFAULT NULL::text, p_min_rating numeric DEFAULT NULL::numeric, p_limit integer DEFAULT 8, p_multi boolean DEFAULT false)
 RETURNS TABLE(id bigint, company_name text, emirate text, business_role text, products text, services text, phone text, email text, whatsapp text, website text, rating numeric, reviews integer, capability_summary text, match_score integer, in_emirate boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with base as (
    select l.id, l.company_name, l.emirate, l.business_role, l.products, l.services,
           l.phone, l.email, l.whatsapp, l.website, l.rating, l.reviews, l.capability_summary,
           (select count(*) from unnest(p_keywords) k
              where l.products ilike '%'||k||'%' or l.services ilike '%'||k||'%'
                 or l.categories ilike '%'||k||'%' or l.capability_summary ilike '%'||k||'%') as strong_hits,
           (select count(*) from unnest(p_keywords) k where l.company_name ilike '%'||k||'%') as name_hits,
           (p_category is not null and l.sector = p_category) as cat_match,
           (p_multi and (
                 l.sector='fitout'
                 or l.business_role ilike '%turnkey%' or l.business_role ilike '%contract%' or l.business_role ilike '%fit%out%' or l.business_role ilike '%interior%'
                 or l.capability_summary ilike '%turnkey%' or l.capability_summary ilike '%fit-out%' or l.capability_summary ilike '%fit out%' or l.capability_summary ilike '%fitout%' or l.capability_summary ilike '%renovation%' or l.capability_summary ilike '%general contract%' or l.capability_summary ilike '%main contract%'
                 or l.services ilike '%turnkey%' or l.services ilike '%fit-out%' or l.services ilike '%fit out%' or l.services ilike '%renovation%'
               )) as turnkey_match,
           coalesce(l.verified,false) as is_verified,
           (coalesce(l.app_reviews,0) > 0) as has_app_rev,
           coalesce(p_emirate is not null and l.emirate ilike p_emirate, false) as in_emirate
    from public.leads l
    where coalesce(l.permanently_closed,false)=false
      and coalesce(l.banned,false)=false
      and coalesce(l.matching_blocked,false)=false
      and (l.registration_submitted_at is not null or l.source='self_registered' or coalesce(l.approval_status,'')='approved')
      and coalesce(l.approval_status,'') <> 'rejected'
      and (p_role is null or l.business_role=p_role)
      and (p_min_rating is null or l.rating>=p_min_rating)
      and (
            (p_category is not null and l.sector=p_category)
         or exists (select 1 from unnest(p_keywords) k
              where l.products ilike '%'||k||'%' or l.services ilike '%'||k||'%'
                 or l.categories ilike '%'||k||'%' or l.capability_summary ilike '%'||k||'%' or l.company_name ilike '%'||k||'%')
         or (p_multi and (l.sector='fitout' or l.business_role ilike '%turnkey%' or l.business_role ilike '%contract%' or l.business_role ilike '%interior%' or l.capability_summary ilike '%turnkey%' or l.capability_summary ilike '%fit-out%' or l.capability_summary ilike '%fitout%' or l.capability_summary ilike '%renovation%'))
      )
  )
  select id, company_name, emirate, business_role, products, services, phone, email, whatsapp,
         website, rating, reviews, capability_summary,
         ( least(strong_hits,6)*2 + least(name_hits,2)
           + case when cat_match then 3 else 0 end
           + case when turnkey_match then 5 else 0 end
           + case when is_verified then 2 else 0 end
           + case when has_app_rev then 1 else 0 end )::int as match_score,
         in_emirate
  from base
  where cat_match or strong_hits > 0 or turnkey_match
  order by in_emirate desc, match_score desc, rating desc nulls last, reviews desc nulls last
  limit coalesce(p_limit,8);
$function$


CREATE OR REPLACE FUNCTION public.mdm_normalize(p_kind text, p_raw text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v text; r text := lower(trim(coalesce(p_raw,'')));
begin
  if r = '' then return null; end if;
  if p_kind = 'emirate' then
     select code into v from public.mdm_emirates where lower(name)=r or r = any(aliases) limit 1; return v;
  elsif p_kind = 'currency' then
     select code into v from public.mdm_currencies where lower(code)=r or lower(name)=r limit 1; return v;
  elsif p_kind = 'unit' then
     select code into v from public.mdm_units where lower(code)=r or r = any(aliases) limit 1; return v;
  elsif p_kind = 'brand' then
     select name into v from public.mdm_brands where lower(name)=r or r = any(aliases) limit 1; return v;
  elsif p_kind = 'manufacturer' then
     select name into v from public.mdm_manufacturers where lower(name)=r or r = any(aliases) limit 1; return v;
  elsif p_kind = 'standard' then
     select code into v from public.mdm_standards where lower(code)=r or r = any(aliases) limit 1; return v;
  end if;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.mkt_rec(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='marketing_recommendation' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values ('marketing_ai','marketing_recommendation','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'marketing',p_sig);
  end if;
end $function$


CREATE OR REPLACE FUNCTION public.notify_new_quote_sms()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare inq record; c record;
begin
  select i.summary, i.customer_id into inq from public.inquiries i where i.id = NEW.inquiry_id;
  if inq.customer_id is null then return NEW; end if;
  select email, phone, phone_verified into c from public.customers where id = inq.customer_id;
  if c.phone is not null and coalesce(c.phone_verified,false) then
    insert into public.notifications(type, channel, to_phone, to_role, inquiry_id, quote_id, subject, body, status)
    values ('new_quote_sms','sms', c.phone, 'customer', NEW.inquiry_id, NEW.id, '',
      'QuotesDone: you have a new quote on your request'||coalesce(': '||left(inq.summary,80),'')||'. View & compare at quotesdone.com/app', 'queued');
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.ops_rec(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='ops_recommendation' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values ('operations_ai','ops_recommendation','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'operations',p_sig);
  end if;
end $function$


CREATE OR REPLACE FUNCTION public.playbook_for(p_category text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select questions from qualification_playbooks
  where category = p_category and status = 'active'
  order by version desc limit 1;
$function$


CREATE OR REPLACE FUNCTION public.qd_norm_customer_ver()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin if NEW.tos_accepted_at is not null then NEW.tos_version := 'v3'; end if; return NEW; end $function$


CREATE OR REPLACE FUNCTION public.qd_norm_supplier_ver()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin if NEW.accepted_terms_at is not null then NEW.accepted_terms_version := 'v4'; end if; return NEW; end $function$


CREATE OR REPLACE FUNCTION public.qd_notify_refund_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_owner text; v_company text; v_sup text;
begin
  select value into v_owner from app_secrets where key='admin_emails';
  v_owner := split_part(coalesce(v_owner,'management@quotesdone.com'), ',', 1);
  select company_name into v_company from leads where id = NEW.supplier_id;
  insert into notifications(type, to_email, to_role, inquiry_id, subject, body)
  values('refund_complaint', v_owner, 'admin', NEW.inquiry_id,
    'Customer complaint — supplier not responding (reveal refund)',
    'A customer has raised a complaint that a revealed supplier is not responding.'||chr(10)||
    'Supplier: '||coalesce(v_company,'(id '||NEW.supplier_id::text||')')||chr(10)||
    'Inquiry: '||coalesce(NEW.inquiry_id::text,'')||' · Transaction: '||NEW.id::text||' · Reveal fee: AED '||coalesce(NEW.reveal_fee::text,'0')||chr(10)||chr(10)||
    'Action: reach out to the supplier. If they do not respond to you and the customer within 3 working days, issue the refund and record the 3% non-response charge against the supplier. Check supplier@quotesdone.com for the customer''s CC''d complaint email as proof.');
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.qd_on_due_paid()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if (coalesce(NEW.status,'')='paid' or NEW.paid_at is not null) and (OLD.status is distinct from NEW.status or OLD.paid_at is distinct from NEW.paid_at) then
    if not exists (select 1 from supplier_dues d where d.supplier_id=NEW.supplier_id and coalesce(d.status,'')<>'paid' and d.paid_at is null and d.id<>NEW.id) then
      update leads set matching_blocked=false, matching_block_reason=null where id=NEW.supplier_id and coalesce(rv_nonresponse_refunds,0)<2;
    end if;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.qd_on_refund_resolved()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_fee numeric; v_admin numeric;
begin
  if NEW.refund_status in ('refunded','approved') and (OLD.refund_status is distinct from NEW.refund_status) then
    v_fee   := coalesce(NEW.reveal_fee, NEW.app_fee, 0);
    v_admin := coalesce((select num_value from public.gl_settings where key='clawback_admin_fee_aed'), 250);

    if not exists (select 1 from public.supplier_dues where transaction_id=NEW.id and coalesce(status,'')<>'cancelled') then
      insert into public.supplier_dues(
        transaction_id, supplier_id, quote_id, quote_amount, commission_pct,
        amount_due, admin_fee, interest_amount, currency,
        reveal_date, due_date, due_date_30, status, created_at)
      values(
        NEW.id, NEW.supplier_id, NEW.quote_id, NEW.quote_amount, 3,
        v_fee,          -- the 3% reveal fee QuotesDone already refunded to the customer
        v_admin,        -- flat administration fee, charged immediately per the supplier terms
        0,              -- interest starts accruing only once the due date passes
        'AED',
        NEW.revealed_at, (now()+interval '7 days'), (now()+interval '30 days'), 'due', now());
    end if;

    update public.leads
      set matching_blocked = true,
          matching_block_reason = 'Unsettled non-response charge (customer refunded due to no response)',
          rv_nonresponse_refunds = coalesce(rv_nonresponse_refunds,0)+1
    where id = NEW.supplier_id;

    if NEW.refund_resolved_at is null then NEW.refund_resolved_at := now(); end if;
  end if;
  return NEW;
end;
$function$


CREATE OR REPLACE FUNCTION public.qd_recompute_response()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  with stats as (
    select t.supplier_id, count(*) as reveals,
      count(*) filter (where t.supplier_ack_at is not null
        or exists(select 1 from messages m where m.inquiry_id=t.inquiry_id and m.supplier_id=t.supplier_id and m.sender='supplier' and coalesce(m.blocked,false)=false and m.created_at>t.revealed_at)
        or exists(select 1 from inquiries i where i.id=t.inquiry_id and i.hired_supplier_id=t.supplier_id)
        or (t.refund_status is null and t.revealed_at < now()-interval '7 days')) as responded
    from transactions t where t.revealed_at is not null group by t.supplier_id
  )
  update leads l set rv_reveals=s.reveals, rv_responded=s.responded,
    rv_response_rate=case when s.reveals>0 then round(s.responded::numeric/s.reveals,3) else null end
  from stats s where s.supplier_id=l.id;
end $function$


CREATE OR REPLACE FUNCTION public.qd_reveal_nudges()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare base text := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/supplier_ack';
begin
  with due as (
    select t.id, t.inquiry_id, t.supplier_id, t.ack_token, l.email, coalesce(l.locale,'en') as locale
    from transactions t join leads l on l.id=t.supplier_id
    where t.revealed_at is not null and t.revealed_at < now()-interval '24 hours'
      and t.nudged_24_at is null and coalesce(t.fee_status,'')='paid' and t.refund_status is null and t.supplier_ack_at is null
      and not exists (select 1 from messages m where m.inquiry_id=t.inquiry_id and m.supplier_id=t.supplier_id and m.sender='supplier' and coalesce(m.blocked,false)=false and m.created_at>t.revealed_at)
      and l.email ~ '@'
  ), ins as (
    insert into notifications(type,to_email,to_role,inquiry_id,subject,body)
    select 'supplier_nudge', d.email, 'supplier', d.inquiry_id,
      case when d.locale='ar' then 'عميل دافع بانتظارك — يُرجى الرد'
           else 'A paying customer is waiting for you — please respond' end,
      (case when d.locale='ar'
        then 'دفع أحد العملاء لكشف بيانات تواصلك على QuotesDone وهو بانتظار ردك. يُرجى التواصل معه في أقرب وقت. وفقاً لاتفاقية المورّد، إذا لم ترد خلال ٣ أيام عمل وتم استرداد المبلغ للعميل، تُطبَّق رسوم عدم استجابة تعادل رسوم الكشف (٣٪ من قيمة العرض) على حسابك.'
        else 'A customer has paid to reveal your contact on QuotesDone and is waiting to hear from you. Please contact them as soon as possible. Under the Supplier Agreement, if you do not respond within 3 working days and the customer is refunded, a non-response charge equal to the reveal fee (3% of the quoted value) applies to your account.' end)
      || E'\n\n' ||
      (case when d.locale='ar' then 'هل تواصلت مع العميل بالفعل؟ أكّد هنا لإيقاف هذه التذكيرات: '
            else 'Already contacted this customer? Confirm here to stop these reminders: ' end)
      || base || '?tx=' || d.id || '&token=' || d.ack_token
    from due d returning 1
  )
  update transactions set nudged_24_at=now() where id in (select id from due);

  with due as (
    select t.id, t.inquiry_id, t.supplier_id, t.ack_token, l.email, coalesce(l.locale,'en') as locale
    from transactions t join leads l on l.id=t.supplier_id
    where t.revealed_at is not null and t.revealed_at < now()-interval '48 hours'
      and t.nudged_48_at is null and coalesce(t.fee_status,'')='paid' and t.refund_status is null and t.supplier_ack_at is null
      and not exists (select 1 from messages m where m.inquiry_id=t.inquiry_id and m.supplier_id=t.supplier_id and m.sender='supplier' and coalesce(m.blocked,false)=false and m.created_at>t.revealed_at)
      and l.email ~ '@'
  ), ins as (
    insert into notifications(type,to_email,to_role,inquiry_id,subject,body)
    select 'supplier_nudge', d.email, 'supplier', d.inquiry_id,
      case when d.locale='ar' then 'تذكير أخير: عميل لا يزال بانتظارك — يُرجى الرد اليوم'
           else 'Final reminder: a customer is still waiting — please respond today' end,
      (case when d.locale='ar'
        then 'هذا تذكير أخير بأن عميلاً دافعاً بانتظار ردك على QuotesDone. إذا لم ترد وتم استرداد المبلغ للعميل، تُطبَّق رسوم عدم استجابة تعادل رسوم الكشف (٣٪ من قيمة العرض)، وقد يؤدي تكرار عدم الرد إلى إزالتك من المنصّة.'
        else 'This is a final reminder that a paying customer is waiting for your response on QuotesDone. If you do not respond and the customer is refunded, a non-response charge equal to the reveal fee (3% of the quoted value) applies, and repeated non-response may lead to removal from the Platform.' end)
      || E'\n\n' ||
      (case when d.locale='ar' then 'هل تواصلت مع العميل بالفعل؟ أكّد هنا لإيقاف هذه التذكيرات: '
            else 'Already contacted this customer? Confirm here to stop these reminders: ' end)
      || base || '?tx=' || d.id || '&token=' || d.ack_token
    from due d returning 1
  )
  update transactions set nudged_48_at=now() where id in (select id from due);
end $function$


CREATE OR REPLACE FUNCTION public.qd_sign_customer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_secret text;
begin
  select value into v_secret from app_secrets where key='inbound_secret';
  perform net.http_post(
    'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/compliance_archive',
    jsonb_build_object('__secret', v_secret, 'action','sign','kind','customer','email', NEW.email),
    '{}'::jsonb, '{"Content-Type":"application/json"}'::jsonb, 8000);
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.qd_sign_supplier()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_secret text;
begin
  select value into v_secret from app_secrets where key='inbound_secret';
  perform net.http_post(
    'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/compliance_archive',
    jsonb_build_object('__secret', v_secret, 'action','sign','kind','supplier','email', NEW.claimed_by),
    '{}'::jsonb, '{"Content-Type":"application/json"}'::jsonb, 8000);
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.quote_gate(p_category text, p_quote jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare reqs jsonb; sec jsonb; k text; mand boolean; present boolean; v jsonb;
  miss jsonb := '[]'::jsonb; pres jsonb := '[]'::jsonb; tot_m int := 0; ok_m int := 0;
begin
  select required_sections into reqs from quote_requirements where category = p_category;
  if reqs is null then select required_sections into reqs from quote_requirements where category = 'default'; end if;
  if reqs is null then return jsonb_build_object('pass', true, 'score', 100, 'missing', '[]'::jsonb, 'note', 'no standard defined'); end if;
  for sec in select * from jsonb_array_elements(reqs) loop
    k := sec->>'key'; mand := coalesce((sec->>'mandatory')::boolean, false);
    v := p_quote -> k;
    present := (v is not null) and (
       (jsonb_typeof(v) = 'string'  and length(trim(v #>> '{}')) > 0) or
       (jsonb_typeof(v) = 'array'   and jsonb_array_length(v) > 0) or
       (jsonb_typeof(v) = 'object'  and v <> '{}'::jsonb) or
       (jsonb_typeof(v) in ('number','boolean')));
    if mand then tot_m := tot_m + 1; if present then ok_m := ok_m + 1; end if; end if;
    if present then pres := pres || to_jsonb(k);
    else miss := miss || jsonb_build_object('key', k, 'label', sec->>'label', 'mandatory', mand); end if;
  end loop;
  return jsonb_build_object(
    'pass', (tot_m = 0 or ok_m = tot_m),
    'mandatory_total', tot_m, 'mandatory_present', ok_m,
    'score', case when jsonb_array_length(reqs) > 0 then round(100.0 * jsonb_array_length(pres) / jsonb_array_length(reqs)) else 100 end,
    'present', pres, 'missing', miss);
end $function$


CREATE OR REPLACE FUNCTION public.recent_duplicate_inquiry(p_customer uuid, p_summary text, p_window interval DEFAULT '48:00:00'::interval)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select i.id
  from inquiries i
  where i.customer_id = p_customer
    and i.created_at > now() - p_window
    and p_summary is not null and length(p_summary) > 12
    and similarity(coalesce(i.summary,''), p_summary) > 0.55
  order by i.created_at desc
  limit 1;
$function$


CREATE OR REPLACE FUNCTION public.recompute_supplier_rating(p_supplier bigint)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'public'
AS $function$
  update public.leads l set
    app_rating  = (select round(avg(rating)::numeric, 2) from public.reviews r where r.supplier_id = p_supplier),
    app_reviews = (select count(*)::int from public.reviews r where r.supplier_id = p_supplier)
  where l.id = p_supplier;
$function$


CREATE OR REPLACE FUNCTION public.registered_supplier_count()
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select count(*)::int from public.leads
  where claimed = true or source in ('self_registered','email_inbound')
$function$


CREATE OR REPLACE FUNCTION public.reveal_fee(amount numeric, at_time timestamp with time zone DEFAULT now())
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select case when amount is null or amount <= 0 then 0 else (
    select least(
      round(amount * (case when c.promo_until is not null and at_time <= c.promo_until
                           then c.promo_reveal_rate else c.standard_reveal_rate end), 2),
      (case when c.promo_until is not null and at_time <= c.promo_until
            then c.promo_reveal_cap else c.standard_reveal_cap end)
    ) from public.pricing_config c where c.id = 1
  ) end
$function$


CREATE OR REPLACE FUNCTION public.rl_check(p_key text, p_limit integer, p_seconds integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  delete from rl_hits where at < now() - (p_seconds || ' seconds')::interval and k = p_key;
  select count(*) into n from rl_hits where k = p_key and at > now() - (p_seconds || ' seconds')::interval;
  if n >= p_limit then return false; end if;
  insert into rl_hits(k) values (p_key);
  return true;
end $function$


CREATE OR REPLACE FUNCTION public.run_agent(p_job text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s text;
begin
  select value into s from app_secrets where key='inbound_secret';
  perform net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/agents',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('__secret', s, 'job', p_job)
  );
end$function$


CREATE OR REPLACE FUNCTION public.run_auto_deploy()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d boolean; s text; ak text;
begin
  select dirty into d from public.deploy_state where id=1;
  if not coalesce(d,false) then return 'clean'; end if;
  select value into s from public.app_secrets where key='inbound_secret';
  select value into ak from public.app_secrets where key='anon_key';
  perform net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/site_deploy',
    headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||ak),
    body:=jsonb_build_object('__secret', s),
    timeout_milliseconds:=150000);
  update public.deploy_state set dirty=false, last_deploy=now(), last_status='triggered' where id=1;
  update public.site_publish_state set dirty=false, last_deploy_at=now() where id=1;
  return 'deploying';
end $function$


CREATE OR REPLACE FUNCTION public.run_doc_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s text;
begin
  select value into s from public.app_secrets where key='inbound_secret';
  perform net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/doc_reminder',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('__secret', s, 'days', 14));
end $function$


CREATE OR REPLACE FUNCTION public.run_health_check()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare issues text[] := '{}'; stuck int; failed int; dirty_stuck boolean; inq int; q int; pend int; sms_stuck int; alert_recent boolean;
begin
  select count(*) into stuck from public.notifications
    where coalesce(status,'queued')='queued' and coalesce(channel,'email')<>'sms' and created_at < now()-interval '60 minutes';
  select count(*) into failed from public.notifications where status='failed' and created_at > now()-interval '24 hours';
  select count(*) into sms_stuck from public.notifications where channel='sms' and coalesce(status,'queued')='queued' and created_at < now()-interval '30 minutes';
  select (dirty and coalesce(last_deploy, '2000-01-01') < now()-interval '20 minutes') into dirty_stuck from public.deploy_state where id=1;
  select count(*) into inq from public.inquiries where created_at > now()-interval '24 hours';
  select count(*) into q from public.quotes where created_at > now()-interval '24 hours';
  select count(*) into pend from public.transactions where refund_status='requested';

  if stuck > 0 then issues := issues || ('Email queue stuck: '||stuck||' email(s) queued >1h — the email cron / Resend may be down.'); end if;
  if failed > 25 then issues := issues || ('High email failures: '||failed||' failed in 24h — check Resend domain auth.'); end if;
  if coalesce(dirty_stuck,false) then issues := issues || ('Auto-deploy stuck: a page change has not deployed in 20+ min — check the Vercel token / cron.'); end if;
  -- sms only flagged if a sender is configured (else it is expected to sit)
  if sms_stuck > 0 and exists (select 1 from public.app_secrets where key='twilio_account_sid' and value is not null and value<>'') then
     issues := issues || ('SMS queue stuck: '||sms_stuck||' SMS queued >30min.'); end if;

  update public.health_state set last_run=now(), last_status=(case when array_length(issues,1) is null then 'ok' else 'issues' end) where id=1;
  select (last_alert_at > now()-interval '6 hours') into alert_recent from public.health_state where id=1;

  if array_length(issues,1) is not null and not coalesce(alert_recent,false) then
    insert into public.notifications(type,to_email,to_role,subject,body,status)
    select 'health_alert', trim(split_part(value,',',1)), 'admin', 'QuotesDone system health alert',
      'Automated check found issue(s):'||chr(10)||'- '||array_to_string(issues, chr(10)||'- ')||chr(10)||chr(10)||
      'Last 24h: '||inq||' inquiries, '||q||' quotes. Pending refund requests: '||pend||'.'||chr(10)||
      'Open the admin dashboard to investigate.', 'queued'
    from public.app_secrets where key='admin_emails';
    update public.health_state set last_alert_at=now() where id=1;
  end if;

  return json_build_object('ok',true,'status',(case when array_length(issues,1) is null then 'ok' else 'issues' end),'issues',to_jsonb(issues),'stuck_emails',stuck,'failed_24h',failed,'inq_24h',inq,'q_24h',q,'pending_refunds',pend);
end $function$


CREATE OR REPLACE FUNCTION public.run_no_quote_nudges()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int := 0; cemail text;
begin
  for r in
    select i.id, i.customer_id, i.summary, i.category from public.inquiries i
    where i.status='sent' and i.created_at < now() - interval '12 hours'
      and coalesce(i.no_quote_notified,false)=false
      and not exists (select 1 from public.quotes q where q.inquiry_id=i.id)
  loop
    select email into cemail from public.customers where id=r.customer_id;
    if cemail is not null then
      insert into public.notifications(type,to_email,to_role,inquiry_id,subject,body,status)
      values('no_quotes_yet', cemail,'customer', r.id,
        'We are still sourcing quotes for your request',
        'Thanks for your patience — no quote has come in yet for '||coalesce(r.summary,r.category)||'. Suppliers are still reviewing it. You can add detail or widen the request in the app, and we will email you the moment a quote arrives.','queued');
    end if;
    update public.inquiries set no_quote_notified=true where id=r.id;
    n := n+1;
  end loop;
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.run_pending_digest()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s text;
begin
  select value into s from public.app_secrets where key='inbound_secret';
  perform net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/pending_digest',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('__secret', s)
  );
end$function$


CREATE OR REPLACE FUNCTION public.run_reveal_nudges()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int := 0; cemail text; supemail text; comp text;
begin
  for r in
    select t.inquiry_id, t.supplier_id, t.customer_id
    from public.transactions t
    where t.revealed_at is not null
      and t.revealed_at < now() - interval '24 hours'
      and coalesce(t.refund_status,'') = 'window_open'
      and not exists (select 1 from public.messages m where m.inquiry_id=t.inquiry_id and m.supplier_id=t.supplier_id and m.sender='supplier')
      and not exists (select 1 from public.notifications x where x.type='reveal_nudge' and x.inquiry_id=t.inquiry_id)
  loop
    select email into cemail from public.customers where id=r.customer_id;
    select company_name, claimed_by into comp, supemail from public.leads where id=r.supplier_id;
    if cemail is not null then
      insert into public.notifications(type,to_email,to_role,inquiry_id,subject,body,status)
      values('reveal_nudge', cemail,'customer', r.inquiry_id,
        coalesce(comp,'Your supplier')||' has not replied yet',
        'It has been 24 hours and '||coalesce(comp,'the supplier')||' has not responded in the app. Try messaging again — or open the request and Report an issue to request a reveal-fee refund (within 72 hours of reveal).','queued');
    end if;
    if supemail is not null then
      insert into public.notifications(type,to_email,to_role,inquiry_id,subject,body,status)
      values('reveal_nudge_sup', supemail,'supplier', r.inquiry_id,
        'A customer is waiting for your reply',
        'A customer unlocked your quote on QuotesDone and is waiting to hear from you. Please log in and reply in the app to win the job.','queued');
    end if;
    n := n + 1;
  end loop;
  return n;
end $function$


CREATE OR REPLACE FUNCTION public.run_rfq_clarify(p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; lbl text; miss_labels text[]; body text; subject text; n int:=0; sample jsonb:='[]'::jsonb; co text;
begin
  for r in
    select i.id, i.summary, i.completeness, c.email cust_email, c.full_name
    from public.inquiries i join public.customers c on c.id=i.customer_id
    where coalesce(i.rfq_ready,false)=false
      and coalesce(i.status,'') not in ('completed','accepted','closed','cancelled','lost')
      and i.created_at > now()-interval '30 days'
      and c.email is not null and c.email <> ''
      and jsonb_array_length(coalesce(i.completeness->'missing','[]'::jsonb)) > 0
      and not exists (select 1 from public.notifications nz where nz.type='inquiry_incomplete'
                        and nz.inquiry_id=i.id and nz.created_at > now()-interval '2 days')
    limit 200
  loop
    miss_labels := '{}';
    for lbl in select jsonb_array_elements_text(r.completeness->'missing') loop
      miss_labels := array_append(miss_labels, case lbl
        when 'category' then 'the type of service / category you need'
        when 'emirate' then 'which emirate the work is in'
        when 'scope_detail' then 'a clear description of the work (scope)'
        when 'scope_type' then 'whether it is a single trade or a full / turnkey job'
        when 'budget' then 'your budget or budget range'
        when 'supporting_detail' then 'supporting details — the trades involved, a drawing, or a bill of quantities (BOQ)'
        else lbl end);
    end loop;
    n := n+1;
    if jsonb_array_length(sample) < 10 then
      sample := sample || jsonb_build_object('inquiry_id',r.id,'to',r.cust_email,'missing',to_jsonb(miss_labels));
    end if;
    if not p_dry_run then
      co := coalesce(nullif(split_part(coalesce(r.full_name,''),' ',1),''),'there');
      subject := 'A few details needed to get you quotes — QuotesDone';
      body := 'Hi '||co||','||E'\n\n'||'Thanks for your request'||coalesce(' ('||left(r.summary,80)||')','')
        ||'. Before we can send it to suppliers and collect quotes, we need a little more information:'||E'\n\n'
        ||'• '||array_to_string(miss_labels, E'\n• ')||E'\n\n'
        ||'Please open your request on QuotesDone and add these details so we can match you to the right suppliers:'||E'\n'
        ||'https://quotesdone.com/app/'||E'\n\n'||'As soon as it is complete we will start collecting quotes for you. Thank you!';
      insert into public.notifications(type,to_email,to_role,inquiry_id,channel,subject,body,status)
        values('inquiry_incomplete', r.cust_email, 'customer', r.id, 'email', subject, body, 'queued');
    end if;
  end loop;
  return jsonb_build_object('ok',true,'dry_run',p_dry_run,'to_notify',n,'sample',sample);
end $function$


CREATE OR REPLACE FUNCTION public.run_site_autodeploy()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp', 'net'
AS $function$
declare s text; d boolean; lastdep timestamptz; ak text;
begin
  select dirty, last_deploy_at into d, lastdep from public.site_publish_state where id=1;
  if not coalesce(d,false) then return; end if;
  if lastdep is not null and now()-lastdep < interval '50 seconds' then return; end if;
  select value into s from public.app_secrets where key='inbound_secret';
  select value into ak from public.app_secrets where key='anon_key';
  if s is null then return; end if;
  update public.site_publish_state set dirty=false, last_deploy_at=now() where id=1;
  update public.deploy_state set dirty=false, last_deploy=now(), last_status='triggered' where id=1;
  perform net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/site_deploy',
    body := jsonb_build_object('__secret', s),
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||ak),
    timeout_milliseconds := 150000
  );
end$function$


CREATE OR REPLACE FUNCTION public.scrub_quote_contacts()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare changed boolean := false;
begin
  if new.notes         is distinct from public.mask_contacts(new.notes)         then new.notes         := public.mask_contacts(new.notes);         changed := true; end if;
  if new.scope         is distinct from public.mask_contacts(new.scope)         then new.scope         := public.mask_contacts(new.scope);         changed := true; end if;
  if new.conditions    is distinct from public.mask_contacts(new.conditions)    then new.conditions    := public.mask_contacts(new.conditions);    changed := true; end if;
  if new.exclusions    is distinct from public.mask_contacts(new.exclusions)    then new.exclusions    := public.mask_contacts(new.exclusions);    changed := true; end if;
  if new.payment_terms is distinct from public.mask_contacts(new.payment_terms) then new.payment_terms := public.mask_contacts(new.payment_terms); changed := true; end if;
  if new.warranty      is distinct from public.mask_contacts(new.warranty)      then new.warranty      := public.mask_contacts(new.warranty);      changed := true; end if;
  if new.lead_time     is distinct from public.mask_contacts(new.lead_time)     then new.lead_time     := public.mask_contacts(new.lead_time);     changed := true; end if;
  if new.validity      is distinct from public.mask_contacts(new.validity)      then new.validity      := public.mask_contacts(new.validity);      changed := true; end if;
  if changed then
    begin
      insert into public.founder_alerts(level, event, detail, channel)
      values ('warn', 'quote_contact_masked',
              'Masked off-platform contact details in quote for inquiry '||coalesce(new.inquiry_id::text,'?')||' from supplier '||coalesce(new.supplier_id::text,'?')||'.',
              'system');
    exception when others then null; end;
  end if;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.sec_incident(p_sig text, p_cond boolean, p_sev text, p_title text, p_reco text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='security_incident' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
    values ('security_ai','security_incident','pending',p_sev,p_title,p_reco,jsonb_build_object('signal',p_sig),'security',p_sig);
  end if;
end $function$


CREATE OR REPLACE FUNCTION public.trg_action_gate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare attrs jsonb; action text; esc jsonb; authz jsonb; blocked boolean:=false; reasons text[]:='{}'; amt numeric;
begin
  -- build context defensively (detail may be jsonb or text)
  begin
    attrs := case when jsonb_typeof(to_jsonb(NEW.detail)) = 'object' then to_jsonb(NEW.detail) else '{}'::jsonb end;
  exception when others then attrs := '{}'::jsonb; end;
  begin amt := nullif(attrs->>'amount_aed','')::numeric; if amt is null then amt := nullif(attrs->>'amount','')::numeric; end if; exception when others then amt := null; end;
  attrs := attrs || jsonb_build_object('amount_aed', amt, 'text', lower(coalesce(NEW.title,'')||' '||coalesce(NEW.recommendation,'')),
                                       'category', coalesce(attrs->>'category',''), 'moves_money', (lower(coalesce(NEW.kind,'')) ~ '(refund|payout|charge|payment|transfer)'));
  -- map action kind to an RBAC action
  action := case
    when lower(coalesce(NEW.kind,'')) ~ 'refund' then 'issue_refund'
    when lower(coalesce(NEW.kind,'')) ~ 'approve.*suppl|suppl.*approve|kyc' then 'approve_supplier'
    when lower(coalesce(NEW.kind,'')) ~ 'price|fee|commission' then 'edit_pricing'
    when lower(coalesce(NEW.kind,'')) ~ 'publish|post|content|blog|campaign' then 'publish_content'
    when lower(coalesce(NEW.kind,'')) ~ 'message|email|notify|send' then 'send_message'
    else 'run_agent_action' end;

  begin
    esc  := public.fn_should_escalate(attrs);
    authz:= public.fn_authorize(coalesce(NEW.agent,'agent'), action, attrs);
    if (esc->>'escalate')::boolean then blocked:=true; reasons := reasons || array(select jsonb_array_elements_text(coalesce(esc->'reasons','[]'))); end if;
    if not (authz->>'allowed')::boolean then blocked:=true; reasons := array_append(reasons, authz->>'reason'); end if;
  exception when others then blocked:=true; reasons := array_append(reasons,'gate error — held for review: '||sqlerrm); end;

  -- enforce: a gated action can never be auto-approved; force human review
  if blocked and coalesce(NEW.status,'pending') in ('approved','auto','auto_approved','executed','done') then
    NEW.status := 'needs_review';
  elsif blocked and coalesce(NEW.status,'pending')='pending' then
    NEW.status := 'needs_review';
  end if;

  -- immutable audit
  begin
    insert into decision_log(actor,kind,ctx,decision,confidence,reasons,sources,route_to)
    values (coalesce(NEW.agent,'agent'),'action_gate',
            jsonb_build_object('action',action,'kind',NEW.kind,'risk',NEW.risk,'attrs',attrs),
            case when blocked then 'held_for_review' else 'permitted' end, null,
            to_jsonb(reasons), '[]'::jsonb, coalesce(esc->>'route_to','Secretary'));
  exception when others then null; end;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_autodispatch_inquiry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_secret text;
begin
  if NEW.rfq_ready is true
     and (TG_OP='INSERT' or OLD.rfq_ready is distinct from NEW.rfq_ready)
     and (NEW.routing is null or (NEW.routing->>'dispatched_at') is null) then
    select value into v_secret from app_secrets where key='inbound_secret';
    perform net.http_post(
      url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/dispatch_inquiry',
      headers := jsonb_build_object('Content-Type','application/json'),
      body := jsonb_build_object('__secret', v_secret, 'inquiry_id', NEW.id));
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_block_banned_inquiry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_banned boolean;
begin
  select banned into v_banned from customers where id = NEW.customer_id;
  if coalesce(v_banned, false) then
    raise exception 'Your account has been paused due to repeated cancelled requests. Please contact support@quotesdone.com to restore it.';
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_company_faq_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin perform public.fn_company_faq_sync(); return null; end $function$


CREATE OR REPLACE FUNCTION public.trg_customer_abandon_ban()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  if NEW.status = 'cancelled' and coalesce(OLD.status,'') <> 'cancelled' then
    select count(*) into n from inquiries i
      where i.customer_id = NEW.customer_id and i.status = 'cancelled'
        and not exists (select 1 from transactions t where t.inquiry_id = i.id);
    if n >= 4 then
      update customers set banned = true,
        banned_reason = 'Auto: ' || n || ' requests cancelled without proceeding (time-waster guard) — reversible by admin.'
        where id = NEW.customer_id and coalesce(banned,false) = false;
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
      select 'customer_success','customer_autoban','pending','medium',
        'Customer auto-paused ('||n||' cancelled requests)',
        'Review and unban if legitimate. Set customers.banned=false to restore.',
        jsonb_build_object('cancelled_count',n,'email',c.email), 'customers', NEW.customer_id::text
      from customers c where c.id = NEW.customer_id
      and not exists (select 1 from agent_actions a where a.kind='customer_autoban' and a.target_id=NEW.customer_id::text and a.status in ('pending','needs_review'));
    elsif n = 3 then
      insert into notifications(type,to_email,to_role,inquiry_id,channel,status,subject,body)
      select 'abandon_warning', c.email, 'customer', NEW.id, 'email', 'queued',
        'A quick note about your QuotesDone requests',
        'Hi ' || coalesce(c.full_name,'there') || ', we noticed a few of your requests were cancelled before proceeding. Suppliers put real effort into quoting, so please only post jobs you intend to follow through on. Repeated cancellations may temporarily pause your account. Thank you for understanding.'
      from customers c where c.id = NEW.customer_id and c.email like '%@%';
    end if;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_declog_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin raise exception 'decision_log is append-only'; end $function$


CREATE OR REPLACE FUNCTION public.trg_enrich_capability()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_secret text;
begin
  if NEW.approval_status='approved'
     and (TG_OP='INSERT' or OLD.approval_status is distinct from NEW.approval_status)
     and NEW.capability_enriched_at is null then
    select value into v_secret from app_secrets where key='inbound_secret';
    perform net.http_post(
      url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/enrich_capability',
      headers := jsonb_build_object('Content-Type','application/json'),
      body := jsonb_build_object('__secret', v_secret, 'lead_id', NEW.id));
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_gate_incomplete_match()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare ready boolean;
begin
  select rfq_ready into ready from public.inquiries where id = NEW.inquiry_id;
  if ready is not true then return null; end if;   -- silently skip: incomplete RFQs don't qualify for routing
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_ingest_case_lessons()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare les text; key text; n int := 0;
begin
  if NEW.ai_summary is null or jsonb_typeof(NEW.ai_summary->'lessons') <> 'array' then return NEW; end if;
  key := coalesce(public.fn_resolve_cat_agent(NEW.category), '_global');
  for les in select jsonb_array_elements_text(NEW.ai_summary->'lessons') loop
    les := trim(les);
    if length(les) < 12 then continue; end if;
    if not exists (select 1 from agent_knowledge where agent_key=key and content=les) then
      insert into agent_knowledge(agent_key, topic, content, priority)
      values (key, 'Closed-case lesson (RFQ-'||NEW.rfq_id||')', les, 60);
      n := n + 1;
    end if;
  end loop;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_inquiry_enrich()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare dup int;
begin
  if NEW.urgency is null and NEW.spec is not null and (NEW.spec ? 'urgency') then NEW.urgency := NEW.spec->>'urgency'; end if;
  if NEW.plausibility is null and NEW.spec is not null and (NEW.spec ? 'plausibility') then NEW.plausibility := NEW.spec->'plausibility'; end if;
  if NEW.provenance is null and NEW.spec is not null and (NEW.spec ? 'provenance') then NEW.provenance := NEW.spec->'provenance'; end if;
  select count(*) into dup from inquiries i
    where i.customer_id = NEW.customer_id and i.created_at > now() - interval '30 minutes'
      and coalesce(i.category,'') = coalesce(NEW.category,'')
      and (i.summary = NEW.summary or (length(coalesce(NEW.summary,'')) > 8 and i.summary ilike '%' || left(NEW.summary, 40) || '%'));
  if dup > 0 then
    NEW.plausibility := coalesce(NEW.plausibility, '{}'::jsonb) || jsonb_build_object('possible_duplicate', true);
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_inquiry_received()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare cemail text;
begin
  -- child sub-RFQs of a combined project do not get their own "received" notice
  if NEW.parent_inquiry_id is not null then return NEW; end if;
  select email into cemail from public.customers where id = NEW.customer_id;
  if cemail is not null then
    insert into public.notifications(type,to_email,to_role,inquiry_id,subject,body,status)
    values('inquiry_received', cemail, 'customer', NEW.id,
      'We have received your request',
      case
        when NEW.scope_type = 'multi' then
          'Thanks — your combined request'||coalesce(' for '||left(NEW.summary,80),'')||' is in. We have split it into separate requests per trade and are matching each to the right specialists'||coalesce(' in '||NEW.emirate,' in the UAE')||'. You will be notified as quotes come in — track everything in the app.'
        when NEW.scope_type = 'turnkey' then
          'Thanks — your combined request'||coalesce(' for '||left(NEW.summary,80),'')||' is in. We are matching it to turnkey fit-out companies that can handle the whole project'||coalesce(' in '||NEW.emirate,' in the UAE')||'. You will be notified as quotes come in — track everything in the app.'
        else
          'Thanks — your request'||coalesce(' for '||left(NEW.summary,80),'')||' is in. We are matching it to relevant '||coalesce(NEW.category,'')||' suppliers in '||coalesce(NEW.emirate,'the UAE')||'. You will be notified as quotes come in — track everything in the app.'
      end,
      'queued');
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_kb_version()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if TG_OP='INSERT' or NEW.content is distinct from OLD.content then
    insert into public.kb_revisions(entry_kind,entry_ref,version,content,status,author,ai_validation)
    values ('agent_knowledge', NEW.agent_key||' :: '||NEW.topic, public._kb_next_ver('agent_knowledge',NEW.agent_key||' :: '||NEW.topic),
            NEW.content,'published','system', public.fn_kb_validate(NEW.content))
    on conflict do nothing;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_mask_quote_contact()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.scope := mask_contact(new.scope);
  new.notes := mask_contact(new.notes);
  new.conditions := mask_contact(new.conditions);
  new.exclusions := mask_contact(new.exclusions);
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.trg_pages_dirty()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin update public.deploy_state set dirty=true where id=1; return null; end $function$


CREATE OR REPLACE FUNCTION public.trg_pricing_facts()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin perform fn_company_facts_sync(); return null; end $function$


CREATE OR REPLACE FUNCTION public.trg_quote_expiry()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare days int := 14; m text; n int;
begin
  if NEW.expires_at is null then
    m := lower(coalesce(NEW.validity,''));
    n := nullif((regexp_match(m,'(\d+)'))[1],'')::int;
    if n is not null and n > 0 then
      if m ~ 'week' then days := n*7;
      elsif m ~ 'month' then days := n*30;
      else days := n; end if;
    end if;
    if days < 1 then days := 14; end if;
    if days > 180 then days := 180; end if;
    NEW.expires_at := coalesce(NEW.created_at, now()) + make_interval(days => days);
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_quote_items_rescore()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update public.quotes set status = status where id::text = coalesce(NEW.quote_id, OLD.quote_id);
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_quote_items_roll()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare qid text; s jsonb;
begin
  qid := coalesce(NEW.quote_id, OLD.quote_id);
  s := public.fn_quote_structured_score(qid);
  update quotes set structured=s, submittable=(s->>'submittable')::boolean where id=qid::uuid;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.trg_quote_quality()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare cat text; grp text; blob text; v_items text;
  n int; priced int; branded int; spec_n int; laboured int;
  pts int := 0; gmiss text[] := '{}'; cmiss jsonb := '[]'::jsonb; cmand_missing int := 0;
  r record; cat_pass boolean := true;
begin
  select category into cat from inquiries where id = NEW.inquiry_id;

  select count(*),
    count(*) filter (where coalesce(unit_price,0)>0 and coalesce(qty,0)>0),
    count(*) filter (where coalesce(brand,'')<>'' and coalesce(model,'')<>''),
    count(*) filter (where coalesce(specification,'')<>''),
    count(*) filter (where coalesce(labour,0)>0 or coalesce(install,0)>0)
    into n, priced, branded, spec_n, laboured
    from public.quote_items where quote_id = NEW.id::text;

  if coalesce(n,0)=0 then gmiss := array_append(gmiss,'an itemised breakdown (not just a lump sum)');
  else pts:=pts+15; if priced=n then pts:=pts+20; else gmiss:=array_append(gmiss,'a unit price on every line'); end if; end if;
  if n>0 and branded=n then pts:=pts+15; else gmiss:=array_append(gmiss,'the brand/model for each item'); end if;
  if n>0 and spec_n>=greatest(1,n/2) then pts:=pts+10; else gmiss:=array_append(gmiss,'the key specifications'); end if;
  if coalesce(laboured,0)>0 then pts:=pts+10; else gmiss:=array_append(gmiss,'the labour / installation cost'); end if;
  if coalesce(btrim(NEW.warranty),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'the warranty period'); end if;
  if coalesce(btrim(NEW.lead_time),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'the lead / delivery time'); end if;
  if coalesce(btrim(NEW.payment_terms),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'the payment terms'); end if;
  if coalesce(btrim(NEW.exclusions),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'what is excluded'); end if;
  if coalesce(btrim(NEW.validity),'')<>'' then pts:=pts+6; else gmiss:=array_append(gmiss,'how long the quote is valid'); end if;

  grp := fn_quote_spec_group(coalesce(cat,''));
  if grp is not null and exists (select 1 from category_quote_specs where spec_group=grp) then
    select string_agg(concat_ws(' ',description,brand,model,specification),' ')
      into v_items from public.quote_items where quote_id = NEW.id::text;
    blob := lower(concat_ws(' ', NEW.scope, NEW.conditions, NEW.exclusions, NEW.notes,
             NEW.warranty, NEW.payment_terms, NEW.lead_time, NEW.validity, v_items));
    for r in select * from category_quote_specs where spec_group=grp order by mandatory desc, aspect loop
      if not (coalesce(blob,'') ~* r.match_regex) then
        cmiss := cmiss || jsonb_build_object('label', r.label, 'mandatory', r.mandatory);
        if r.mandatory then cmand_missing := cmand_missing + 1; end if;
      end if;
    end loop;
    cat_pass := (cmand_missing = 0);
  end if;

  NEW.quality := jsonb_build_object(
    'score', pts, 'pass', (pts >= 70 and cat_pass), 'submittable', (pts >= 70 and cat_pass),
    'missing', to_jsonb(gmiss),
    'category', case when grp is null then null else jsonb_build_object(
        'group', grp, 'pass', cat_pass, 'mandatory_missing', cmand_missing, 'missing', cmiss) end,
    'scored_at', now());
  NEW.submittable := (pts >= 70 and cat_pass);
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_reg_gov_fn()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if TG_OP = 'INSERT' then
    NEW.approved_at := null; NEW.approved_by := null;
  elsif (coalesce(NEW.title,'') is distinct from coalesce(OLD.title,'')
      or coalesce(NEW.summary,'') is distinct from coalesce(OLD.summary,'')
      or coalesce(NEW.key_requirements::text,'') is distinct from coalesce(OLD.key_requirements::text,'')
      or coalesce(NEW.body,'') is distinct from coalesce(OLD.body,'')
      or coalesce(NEW.source_url,'') is distinct from coalesce(OLD.source_url,'')
      or coalesce(NEW.effective_date::text,'') is distinct from coalesce(OLD.effective_date::text,'')
      or coalesce(NEW.status,'') is distinct from coalesce(OLD.status,'')) then
    NEW.approved_at := null; NEW.approved_by := null;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_reg_inquiry_doc()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.drawing_file_path is not null and (TG_OP='INSERT' or NEW.drawing_file_path is distinct from OLD.drawing_file_path) then
     perform public.fn_register_document('drawing-files', NEW.drawing_file_path, 'drawing', 'inquiries', NEW.id::text, NEW.drawing_file_name);
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_reg_lead_docs()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare p text;
begin
  if NEW.license_doc_path is not null and (TG_OP='INSERT' or NEW.license_doc_path is distinct from OLD.license_doc_path) then
     perform public.fn_register_document('supplier-docs', NEW.license_doc_path, 'licence', 'leads', NEW.id::text, NEW.license_doc_name); end if;
  if NEW.company_profile_doc_path is not null and (TG_OP='INSERT' or NEW.company_profile_doc_path is distinct from OLD.company_profile_doc_path) then
     perform public.fn_register_document('supplier-docs', NEW.company_profile_doc_path, 'profile', 'leads', NEW.id::text, null); end if;
  if NEW.egr_doc_path is not null and (TG_OP='INSERT' or NEW.egr_doc_path is distinct from OLD.egr_doc_path) then
     perform public.fn_register_document('supplier-docs', NEW.egr_doc_path, 'egr', 'leads', NEW.id::text, NEW.egr_doc_name); end if;
  if NEW.catalog_doc_paths is not null then
     foreach p in array NEW.catalog_doc_paths loop
        perform public.fn_register_document('supplier-docs', p, 'catalog', 'leads', NEW.id::text, null); end loop; end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_reg_quote_doc()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.original_file_path is not null and (TG_OP='INSERT' or NEW.original_file_path is distinct from OLD.original_file_path) then
     perform public.fn_register_document('quote-files', NEW.original_file_path, 'quote', 'quotes', NEW.id::text, NEW.original_file_name);
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_reveal_receipt()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare cemail text; comp text; inq record;
begin
  if NEW.revealed_at is not null and (TG_OP='INSERT' or OLD.revealed_at is null) then
    select email into cemail from public.customers where id = NEW.customer_id;
    select company_name into comp from public.leads where id = NEW.supplier_id;
    select summary, category into inq from public.inquiries where id = NEW.inquiry_id;
    if cemail is not null then
      insert into public.notifications(type,to_email,to_role,inquiry_id,subject,body,status)
      values('reveal_receipt', cemail, 'customer', NEW.inquiry_id,
        'Reveal confirmed — '||coalesce(comp,'supplier'),
        'You have unlocked '||coalesce(comp,'the supplier')||'''s contact details'||coalesce(' for: '||left(inq.summary,80),'')||'. You can now message them directly in the app. If they do not respond within 72 hours, open the request and Report an issue to request a refund of your reveal fee.',
        'queued');
    end if;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_reveal_window()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.revealed_at is not null and NEW.refund_deadline is null then
    NEW.refund_deadline := public.fn_add_working_days(NEW.revealed_at,
      coalesce((select value::text::int from decision_policy where key='refund_call_after_working_days'), 3));
    if NEW.refund_status is null then NEW.refund_status := 'window_open'; end if;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_rfq_complete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c jsonb;
begin
  c := public.fn_rfq_score(NEW);
  NEW.completeness := c; NEW.rfq_ready := (c->>'ready')::boolean;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_self_reg_category()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.source='self_registered' and coalesce(trim(NEW.categories),'')<>'' then
    -- skip if it already exactly equals an active category slug (known)
    if not exists (select 1 from category_agents where active and slug=NEW.categories) then
      -- only fire when the category actually changed (or on insert)
      if TG_OP='INSERT' or NEW.categories is distinct from OLD.categories then
        perform public.fn_provision_category_call(NEW.categories, NEW.id, NEW.services);
      end if;
    end if;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_supplier_capability()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin NEW.capability_score := (public.fn_supplier_capability_score(NEW)->>'score')::int; return NEW; end $function$


CREATE OR REPLACE FUNCTION public.trg_version_document()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.extracted is not null and (TG_OP='INSERT' or NEW.extracted is distinct from OLD.extracted) then
    insert into public.doc_versions(entity_type,entity_id,version,snapshot,checksum,changed_fields)
    values ('document', NEW.id::text, public._next_docver('document',NEW.id::text),
            jsonb_build_object('extracted',NEW.extracted,'kind',NEW.kind,'status',NEW.status),
            md5(coalesce(NEW.extracted::text,'')), array['extracted'])
    on conflict do nothing;
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_version_quote()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare snap jsonb; chg text[] := '{}';
begin
  snap := jsonb_build_object(
    'quote_amount',NEW.quote_amount,'customer_price',NEW.customer_price,'status',NEW.status,
    'scope',NEW.scope,'committed_items',NEW.committed_items,'quality',NEW.quality,
    'review_status',NEW.review_status,'lead_time',NEW.lead_time,'warranty',NEW.warranty,
    'payment_terms',NEW.payment_terms,'conditions',NEW.conditions,'exclusions',NEW.exclusions);
  if TG_OP='UPDATE' then
    if NEW.quote_amount   is distinct from OLD.quote_amount   then chg:=array_append(chg,'quote_amount'); end if;
    if NEW.customer_price is distinct from OLD.customer_price then chg:=array_append(chg,'customer_price'); end if;
    if NEW.status         is distinct from OLD.status         then chg:=array_append(chg,'status'); end if;
    if NEW.scope          is distinct from OLD.scope          then chg:=array_append(chg,'scope'); end if;
    if NEW.committed_items is distinct from OLD.committed_items then chg:=array_append(chg,'committed_items'); end if;
    if NEW.quality        is distinct from OLD.quality        then chg:=array_append(chg,'quality'); end if;
    if NEW.review_status  is distinct from OLD.review_status  then chg:=array_append(chg,'review_status'); end if;
    if NEW.lead_time      is distinct from OLD.lead_time      then chg:=array_append(chg,'lead_time'); end if;
    if NEW.warranty       is distinct from OLD.warranty       then chg:=array_append(chg,'warranty'); end if;
    if NEW.payment_terms  is distinct from OLD.payment_terms  then chg:=array_append(chg,'payment_terms'); end if;
    if array_length(chg,1) is null then return NEW; end if;   -- nothing meaningful changed
  end if;
  insert into public.doc_versions(entity_type,entity_id,version,snapshot,checksum,changed_fields)
  values ('quote', NEW.id::text, public._next_docver('quote',NEW.id::text), snap, md5(snap::text), chg)
  on conflict do nothing;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.trg_version_rfq()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare snap jsonb; chg text[] := '{}';
begin
  snap := jsonb_build_object('category',NEW.category,'emirate',NEW.emirate,'summary',NEW.summary,
    'spec',NEW.spec,'budget',NEW.budget,'scope_type',NEW.scope_type,'trades',NEW.trades,
    'boq',NEW.boq,'status',NEW.status,'pipeline_stage',NEW.pipeline_stage,'outcome',NEW.outcome);
  if TG_OP='UPDATE' then
    if NEW.spec is distinct from OLD.spec then chg:=array_append(chg,'spec'); end if;
    if NEW.budget is distinct from OLD.budget then chg:=array_append(chg,'budget'); end if;
    if NEW.scope_type is distinct from OLD.scope_type then chg:=array_append(chg,'scope_type'); end if;
    if NEW.trades is distinct from OLD.trades then chg:=array_append(chg,'trades'); end if;
    if NEW.boq is distinct from OLD.boq then chg:=array_append(chg,'boq'); end if;
    if NEW.status is distinct from OLD.status then chg:=array_append(chg,'status'); end if;
    if NEW.pipeline_stage is distinct from OLD.pipeline_stage then chg:=array_append(chg,'pipeline_stage'); end if;
    if NEW.category is distinct from OLD.category then chg:=array_append(chg,'category'); end if;
    if array_length(chg,1) is null then return NEW; end if;
  end if;
  insert into public.doc_versions(entity_type,entity_id,version,snapshot,checksum,changed_fields)
  values ('rfq', NEW.id::text, public._next_docver('rfq',NEW.id::text), snap, md5(snap::text), chg)
  on conflict do nothing;
  return NEW;
end $function$


-- ===== TRIGGERS =====
CREATE TRIGGER action_gate BEFORE INSERT ON public.agent_actions FOR EACH ROW EXECUTE FUNCTION trg_action_gate();
CREATE TRIGGER trg_governance_stamp BEFORE INSERT ON public.agent_actions FOR EACH ROW EXECUTE FUNCTION fn_governance_stamp();
CREATE TRIGGER trg_category_knowledge_promote AFTER UPDATE ON public.agent_actions FOR EACH ROW WHEN ((new.kind = 'category_knowledge'::text)) EXECUTE FUNCTION fn_category_knowledge_promote();
CREATE TRIGGER trg_dedupe_it_incident BEFORE INSERT ON public.agent_actions FOR EACH ROW EXECUTE FUNCTION dedupe_it_incident();
CREATE TRIGGER trg_invite_week_activate AFTER UPDATE ON public.agent_actions FOR EACH ROW EXECUTE FUNCTION fn_invite_week_activate();
CREATE TRIGGER trg_page_high_agent_action AFTER INSERT ON public.agent_actions FOR EACH ROW EXECUTE FUNCTION fn_page_high_agent_action();
CREATE TRIGGER kb_version AFTER INSERT OR UPDATE OF content ON public.agent_knowledge FOR EACH ROW EXECUTE FUNCTION trg_kb_version();
CREATE TRIGGER trg_audit_app_secrets AFTER INSERT OR DELETE OR UPDATE ON public.app_secrets FOR EACH ROW EXECUTE FUNCTION fn_security_audit();
CREATE TRIGGER trg_protect_gate_secrets_del BEFORE DELETE ON public.app_secrets FOR EACH ROW EXECUTE FUNCTION fn_protect_gate_secrets();
CREATE TRIGGER trg_protect_gate_secrets_upd BEFORE INSERT OR UPDATE ON public.app_secrets FOR EACH ROW EXECUTE FUNCTION fn_protect_gate_secrets();
CREATE TRIGGER trg_blog_dirty AFTER INSERT OR DELETE OR UPDATE ON public.blog_posts FOR EACH STATEMENT EXECUTE FUNCTION mark_site_dirty();
CREATE TRIGGER trg_audit_collections_config AFTER INSERT OR DELETE OR UPDATE ON public.collections_config FOR EACH ROW EXECUTE FUNCTION fn_security_audit();
CREATE TRIGGER company_faq_sync AFTER INSERT OR DELETE OR UPDATE ON public.company_faq FOR EACH STATEMENT EXECUTE FUNCTION trg_company_faq_sync();
CREATE TRIGGER trg_block_disposable_customers BEFORE INSERT ON public.customers FOR EACH ROW EXECUTE FUNCTION block_disposable_signup();
CREATE TRIGGER trg_norm_customer_ver BEFORE INSERT OR UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION qd_norm_customer_ver();
CREATE TRIGGER trg_sign_customer AFTER UPDATE ON public.customers FOR EACH ROW WHEN (((new.email_verified IS TRUE) AND (old.email_verified IS DISTINCT FROM new.email_verified) AND (new.signed_terms_url IS NULL))) EXECUTE FUNCTION qd_sign_customer();
CREATE TRIGGER trg_audit_data_owner AFTER INSERT OR DELETE OR UPDATE ON public.data_owner_registry FOR EACH ROW EXECUTE FUNCTION fn_security_audit();
CREATE TRIGGER declog_immutable BEFORE DELETE OR UPDATE ON public.decision_log FOR EACH ROW EXECUTE FUNCTION trg_declog_immutable();
CREATE TRIGGER version_document AFTER INSERT OR UPDATE OF extracted ON public.documents FOR EACH ROW EXECUTE FUNCTION trg_version_document();
CREATE TRIGGER trg_audit_feature_flags AFTER INSERT OR DELETE OR UPDATE ON public.feature_flags FOR EACH ROW EXECUTE FUNCTION fn_security_audit();
CREATE TRIGGER trg_normalize_founder_alert_level BEFORE INSERT OR UPDATE ON public.founder_alerts FOR EACH ROW EXECUTE FUNCTION fn_normalize_founder_alert_level();
CREATE TRIGGER trg_gl_journal_immutable BEFORE DELETE OR UPDATE ON public.gl_journal FOR EACH ROW EXECUTE FUNCTION fn_gl_journal_immutable();
CREATE TRIGGER trg_gl_lines_immutable BEFORE INSERT OR DELETE OR UPDATE ON public.gl_journal_lines FOR EACH ROW EXECUTE FUNCTION fn_gl_lines_immutable();
CREATE TRIGGER trg_audit_gl_settings AFTER INSERT OR DELETE OR UPDATE ON public.gl_settings FOR EACH ROW EXECUTE FUNCTION fn_security_audit();
CREATE TRIGGER rfq_complete BEFORE INSERT OR UPDATE ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_rfq_complete();
CREATE TRIGGER trg_inquiry_received_a AFTER INSERT ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_inquiry_received();
CREATE TRIGGER enrich_inquiry BEFORE INSERT ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_inquiry_enrich();
CREATE TRIGGER reg_inquiry_doc AFTER INSERT OR UPDATE OF drawing_file_path ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_reg_inquiry_doc();
CREATE TRIGGER version_rfq AFTER INSERT OR UPDATE ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_version_rfq();
CREATE TRIGGER autodispatch_inquiry AFTER INSERT OR UPDATE OF rfq_ready ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_autodispatch_inquiry();
CREATE TRIGGER customer_abandon_ban AFTER UPDATE ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_customer_abandon_ban();
CREATE TRIGGER block_banned_inquiry BEFORE INSERT ON public.inquiries FOR EACH ROW EXECUTE FUNCTION trg_block_banned_inquiry();
CREATE TRIGGER notify_matched_supplier AFTER INSERT ON public.inquiry_matches FOR EACH ROW EXECUTE FUNCTION fn_notify_matched_supplier();
CREATE TRIGGER gate_incomplete_match BEFORE INSERT ON public.inquiry_matches FOR EACH ROW EXECUTE FUNCTION trg_gate_incomplete_match();
CREATE TRIGGER trg_block_disposable_leads BEFORE INSERT ON public.leads FOR EACH ROW EXECUTE FUNCTION block_disposable_signup();
CREATE TRIGGER trg_assign_founding_rank BEFORE INSERT OR UPDATE OF claimed ON public.leads FOR EACH ROW EXECUTE FUNCTION fn_assign_founding_rank();
CREATE TRIGGER reg_lead_docs AFTER INSERT OR UPDATE OF license_doc_path, company_profile_doc_path, egr_doc_path, catalog_doc_paths ON public.leads FOR EACH ROW EXECUTE FUNCTION trg_reg_lead_docs();
CREATE TRIGGER trg_self_reg_category AFTER INSERT OR UPDATE OF categories, source ON public.leads FOR EACH ROW EXECUTE FUNCTION trg_self_reg_category();
CREATE TRIGGER enrich_capability_on_approve AFTER INSERT OR UPDATE OF approval_status ON public.leads FOR EACH ROW EXECUTE FUNCTION trg_enrich_capability();
CREATE TRIGGER trg_norm_supplier_ver BEFORE INSERT OR UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION qd_norm_supplier_ver();
CREATE TRIGGER trg_sign_supplier AFTER UPDATE ON public.leads FOR EACH ROW WHEN (((new.owner_email_verified IS TRUE) AND (old.owner_email_verified IS DISTINCT FROM new.owner_email_verified) AND (new.signed_terms_url IS NULL) AND (new.claimed_by IS NOT NULL))) EXECUTE FUNCTION qd_sign_supplier();
CREATE TRIGGER supplier_capability BEFORE INSERT OR UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION trg_supplier_capability();
CREATE TRIGGER trg_notifications_digest BEFORE INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_notifications_digest();
CREATE TRIGGER trg_wa_fanout AFTER INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION fn_wa_fanout();
CREATE TRIGGER trg_pages_dirty_a AFTER INSERT OR UPDATE ON public.pages FOR EACH ROW EXECUTE FUNCTION trg_pages_dirty();
CREATE TRIGGER trg_pages_dirty AFTER INSERT OR DELETE OR UPDATE ON public.pages FOR EACH STATEMENT EXECUTE FUNCTION mark_site_dirty();
CREATE TRIGGER trg_pricing_config_facts AFTER INSERT OR UPDATE ON public.pricing_config FOR EACH STATEMENT EXECUTE FUNCTION trg_pricing_facts();
CREATE TRIGGER trg_audit_pricing_config AFTER INSERT OR DELETE OR UPDATE ON public.pricing_config FOR EACH ROW EXECUTE FUNCTION fn_security_audit();
CREATE TRIGGER trg_items_submittable AFTER INSERT OR DELETE OR UPDATE ON public.quote_items FOR EACH ROW EXECUTE FUNCTION fn_quote_recompute_submittable();
CREATE TRIGGER quote_items_roll AFTER INSERT OR DELETE OR UPDATE ON public.quote_items FOR EACH ROW EXECUTE FUNCTION trg_quote_items_roll();
CREATE TRIGGER quote_items_rescore AFTER INSERT OR DELETE OR UPDATE ON public.quote_items FOR EACH ROW EXECUTE FUNCTION trg_quote_items_rescore();
CREATE TRIGGER trg_new_quote_sms AFTER INSERT ON public.quotes FOR EACH ROW EXECUTE FUNCTION notify_new_quote_sms();
CREATE TRIGGER mask_quote_contact BEFORE INSERT OR UPDATE ON public.quotes FOR EACH ROW EXECUTE FUNCTION trg_mask_quote_contact();
CREATE TRIGGER version_quote AFTER INSERT OR UPDATE ON public.quotes FOR EACH ROW EXECUTE FUNCTION trg_version_quote();
CREATE TRIGGER reg_quote_doc AFTER INSERT OR UPDATE OF original_file_path ON public.quotes FOR EACH ROW EXECUTE FUNCTION trg_reg_quote_doc();
CREATE TRIGGER quotes_quality BEFORE INSERT OR UPDATE ON public.quotes FOR EACH ROW EXECUTE FUNCTION trg_quote_quality();
CREATE TRIGGER trg_scrub_quote_contacts BEFORE INSERT OR UPDATE ON public.quotes FOR EACH ROW EXECUTE FUNCTION scrub_quote_contacts();
CREATE TRIGGER trg_quote_expiry_b BEFORE INSERT ON public.quotes FOR EACH ROW EXECUTE FUNCTION trg_quote_expiry();
CREATE TRIGGER trg_reg_gov BEFORE INSERT OR UPDATE ON public.regulations FOR EACH ROW EXECUTE FUNCTION trg_reg_gov_fn();
CREATE TRIGGER ingest_case_lessons AFTER INSERT OR UPDATE OF ai_summary ON public.rfq_archives FOR EACH ROW EXECUTE FUNCTION trg_ingest_case_lessons();
CREATE TRIGGER trg_audit_role_permissions AFTER INSERT OR DELETE OR UPDATE ON public.role_permissions FOR EACH ROW EXECUTE FUNCTION fn_security_audit();
CREATE TRIGGER trg_audit_roles AFTER INSERT OR DELETE OR UPDATE ON public.roles FOR EACH ROW EXECUTE FUNCTION fn_security_audit();
CREATE TRIGGER trg_sec_audit_immutable BEFORE DELETE OR UPDATE ON public.security_audit_log FOR EACH ROW EXECUTE FUNCTION fn_security_audit_immutable();
CREATE TRIGGER trg_ensure_category_agent AFTER INSERT ON public.seo_categories FOR EACH ROW EXECUTE FUNCTION ensure_category_agent();
CREATE TRIGGER trg_seo_dirty AFTER INSERT OR DELETE OR UPDATE ON public.seo_categories FOR EACH STATEMENT EXECUTE FUNCTION mark_site_dirty();
CREATE TRIGGER trg_due_paid AFTER UPDATE ON public.supplier_dues FOR EACH ROW EXECUTE FUNCTION qd_on_due_paid();
CREATE TRIGGER trg_refund_resolved BEFORE UPDATE ON public.transactions FOR EACH ROW EXECUTE FUNCTION qd_on_refund_resolved();
CREATE TRIGGER trg_reveal_receipt_a AFTER INSERT OR UPDATE ON public.transactions FOR EACH ROW EXECUTE FUNCTION trg_reveal_receipt();
CREATE TRIGGER trg_reveal_window_b BEFORE INSERT OR UPDATE ON public.transactions FOR EACH ROW EXECUTE FUNCTION trg_reveal_window();
CREATE TRIGGER trg_notify_refund AFTER UPDATE ON public.transactions FOR EACH ROW WHEN (((new.refund_status = 'requested'::text) AND (old.refund_status IS DISTINCT FROM new.refund_status))) EXECUTE FUNCTION qd_notify_refund_request();
CREATE TRIGGER trg_audit_user_roles AFTER INSERT OR DELETE OR UPDATE ON public.user_roles FOR EACH ROW EXECUTE FUNCTION fn_security_audit();

-- ===== ROW LEVEL SECURITY (enable) =====
ALTER TABLE public.admin_mfa_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_action_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_command_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_evals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_expectations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_governance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_knowledge ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_memory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_pending_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_constitution ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_qa_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_quality_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_trainer_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ap_bills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_blocked_domains ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_secrets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assistant_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blog_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.board_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.brand_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budget_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.canary_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.canon_eval_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.canon_eval_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category_agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category_quote_specs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category_specs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_violations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.collections_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_faq ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_vision ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.compliance_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_drafts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_drafts_backup_20260724 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_lost_reasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_stages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cron_job_seen ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_phone_otps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_owner_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.decision_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.decision_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deploy_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dept_library ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.doc_backups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.doc_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.doc_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dr_restore ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dropbox_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ea_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ea_meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ea_reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ea_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_suppressions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.error_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.escalations_archive_20260724 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exec_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.experiment_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.experiment_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.experiments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fa_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fa_depreciation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feature_flags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.finance_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.finance_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.finance_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.founder_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fraud_flags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gl_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gl_expense_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gl_journal ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gl_journal_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gl_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.graph_edges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.graph_nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.health_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.health_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hlm_digest_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hlm_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hlm_watchlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inbound_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_cancellations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_intake ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inquiry_requirement ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inv_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inv_stock_moves ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invite_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_category_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kb_usage_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_checklist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.llm_calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.llm_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.market_intel ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_library ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_eval_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mdm_brands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mdm_cities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mdm_currencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mdm_emirates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mdm_manufacturers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mdm_standards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mdm_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memory_promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meta_insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ops_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_action_executor ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_authority ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_memory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_objectives ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_onboarding ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_reset_backup_20260724 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outreach ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdpl_erase_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdpl_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.phone_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.po_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.po_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.po_vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.policy_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pricing_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prompt_benchmarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prompt_eval_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prompt_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prompts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.public_holidays ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qa_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qd_compare_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qd_deploy_src ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qd_i18n ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qd_i18n_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qualification_playbooks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_committed_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_comparisons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_pdf_cache ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_requirements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_review_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quote_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reg_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regulations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.report_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.retention_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reveal_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rfq_archives ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rl_hits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scrape_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_selfaudit_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seo_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.simulations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.site_publish_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.social_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.strategy_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.strategy_risks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stripe_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_capabilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_capability_confirmation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_dues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_kpi_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supply_health_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taxonomy_authority ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taxonomy_role ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.taxonomy_trade ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.undo_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vt_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wa_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.yello_staging ENABLE ROW LEVEL SECURITY;

-- ===== POLICIES =====
CREATE POLICY blog_posts_public_read ON public.blog_posts AS PERMISSIVE FOR SELECT TO anon USING ((published = true));
CREATE POLICY brand_assets_public_read ON public.brand_assets AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "specs readable" ON public.category_specs AS PERMISSIVE FOR SELECT TO anon USING (true);

-- ===== CRON JOBS =====
select cron.schedule('supplier_invites_daily','0 9 * * *',$CRON$ select enqueue_supplier_invites(); $CRON$);
select cron.schedule('sms_flush','*/2 * * * *',$CRON$select net.http_post(
     url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/send_sms',
     headers:='{"Content-Type":"application/json"}'::jsonb,
     body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'))
   )$CRON$);
select cron.schedule('auto_deploy','*/2 * * * *',$CRON$select public.run_auto_deploy()$CRON$);
select cron.schedule('no_quote_nudges','17 * * * *',$CRON$select public.run_no_quote_nudges()$CRON$);
select cron.schedule('health_check','*/30 * * * *',$CRON$select public.run_health_check()$CRON$);
select cron.schedule('agent_onboarding_hourly','23 * * * *',$CRON$select public.run_agent('onboarding')$CRON$);
select cron.schedule('agent_compliance_weekly','17 4 * * 1',$CRON$ select public.run_agent('compliance') $CRON$);
select cron.schedule('agent_followup_daily','37 5 * * *',$CRON$ select public.run_agent('followup') $CRON$);
select cron.schedule('agent_finance_weekly','0 4 * * 1',$CRON$ select public.run_agent('finance') $CRON$);
select cron.schedule('agent_marketing_weekly','0 6 * * 1',$CRON$ select run_agent('marketing') $CRON$);
select cron.schedule('founder_brief_daily','30 4 * * *',$CRON$ select fn_founder_brief() $CRON$);
select cron.schedule('agent_it_health_hourly','15 * * * *',$CRON$ select run_agent('it_health') $CRON$);
select cron.schedule('vt_scan_daily','0 3 * * *',$CRON$ select fn_run_vt() $CRON$);
select cron.schedule('agent_reflect_weekly','0 2 * * 0',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/reflect',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')),
    timeout_milliseconds:=120000
  )
$CRON$);
select cron.schedule('agent_supply_health_daily','40 6 * * *',$CRON$ select fn_supply_health() $CRON$);
select cron.schedule('ops_watch_hourly','25 * * * *',$CRON$ select fn_ops_watch() $CRON$);
select cron.schedule('smoke_test_30min','*/30 * * * *',$CRON$ select fn_smoke() $CRON$);
select cron.schedule('social_stage_hourly','17 * * * *',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/social_stage',
    headers:=jsonb_build_object('x-internal-key',(select value from app_secrets where key='postiz_publish_key'),'Content-Type','application/json'),
    body:='{}'::jsonb
  );
$CRON$);
select cron.schedule('qa_suite_daily','37 3 * * *',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/qa_suite',
    headers:=jsonb_build_object('x-internal-key',(select value from app_secrets where key='postiz_publish_key'),'Content-Type','application/json'),
    body:='{}'::jsonb
  );
$CRON$);
select cron.schedule('gen_category_knowledge_daily','17 3 * * *',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/gen_category_knowledge',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'),'limit',6)
  );
$CRON$);
select cron.schedule('site_autodeploy','* * * * *',$CRON$select public.run_site_autodeploy();$CRON$);
select cron.schedule('pending_suppliers_digest','30 4 * * *',$CRON$select public.run_pending_digest();$CRON$);
select cron.schedule('wa_flush','*/2 * * * *',$CRON$
  select net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/send_whatsapp',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select value from app_secrets where key='anon_key')),
    body := jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'))
  );
$CRON$);
select cron.schedule('uptime_check_15min','*/15 * * * *',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/uptime_check',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')),
    timeout_milliseconds:=120000)
$CRON$);
select cron.schedule('cost_snapshot_weekly','0 7 * * 1',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/cost_snapshot',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')),
    timeout_milliseconds:=120000)
$CRON$);
select cron.schedule('agent_autogen_daily','35 2 * * *',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/agent_autogen',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'),'job','run'),
    timeout_milliseconds:=300000)
$CRON$);
select cron.schedule('learn_gaps_weekly','15 3 * * 1',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/learn_gaps',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'),'job','run'),
    timeout_milliseconds:=300000)
$CRON$);
select cron.schedule('embed_suppliers_daily','50 2 * * *',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/embed_leads',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'),'scope','all'),
    timeout_milliseconds:=55000)
$CRON$);
select cron.schedule('wa_templates_watch','*/15 * * * *',$CRON$
  select net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/wa_templates_watch',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select value from app_secrets where key='anon_key')),
    body := '{}'::jsonb
  );
$CRON$);
select cron.schedule('money_tests_daily','30 3 * * *',$CRON$
  select net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/money_tests',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select value from app_secrets where key='anon_key')),
    body := jsonb_build_object('__secret', (select value from app_secrets where key='inbound_secret'))
  );
  $CRON$);
select cron.schedule('reveal-nudges','0 * * * *',$CRON$select qd_reveal_nudges();$CRON$);
select cron.schedule('response-recompute','30 2 * * *',$CRON$select qd_recompute_response();$CRON$);
select cron.schedule('assets_ingest_6h','15 */6 * * *',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/assets_ingest',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'))
  );
$CRON$);
select cron.schedule('blog_weekly_mon','30 6 * * 1',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/blog_weekly',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'),'publish',true)
  );
$CRON$);
select cron.schedule('graph_rebuild_daily','20 3 * * *',$CRON$select fn_graph_rebuild()$CRON$);
select cron.schedule('fraud_scan_daily','40 3 * * *',$CRON$select fn_fraud_scan()$CRON$);
select cron.schedule('exec-agents-weekly','0 6 * * 1',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/exec_agents',
    headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select value from app_secrets where key='anon_key')),
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'),'action','run_all'),
    timeout_milliseconds:=150000);
$CRON$);
select cron.schedule('kb_sync_daily','45 3 * * *',$CRON$select kb_sync()$CRON$);
select cron.schedule('doc_process','*/5 * * * *',$CRON$
do $inner$
declare i int;
begin
  for i in 1..3 loop
    perform net.http_post(
      url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/doc_extract',
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select value from app_secrets where key='anon_key')),
      body := jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')),
      timeout_milliseconds := 60000);
  end loop;
end $inner$;
$CRON$);
select cron.schedule('eval_weekly','0 5 * * 1',$CRON$select public.fn_eval_run();$CRON$);
select cron.schedule('dr_drill_monthly','50 3 1 * *',$CRON$
  select net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/dr_drill',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select value from app_secrets where key='anon_key')),
    body := jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')),
    timeout_milliseconds := 120000);
$CRON$);
select cron.schedule('exception_alerts_hourly','35 * * * *',$CRON$select public.fn_exception_alerts();$CRON$);
select cron.schedule('board_report_weekly','0 7 * * 1',$CRON$select public.fn_board_report();$CRON$);
select cron.schedule('archive_completed_daily','20 4 * * *',$CRON$
do $inner$
declare i int;
begin
  for i in 1..5 loop
    perform net.http_post(
      url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/archive_rfq',
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select value from app_secrets where key='anon_key')),
      body := jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')),
      timeout_milliseconds := 60000);
  end loop;
end $inner$;
$CRON$);
select cron.schedule('doc_expiry_daily','20 5 * * *',$CRON$select public.fn_doc_expiry_scan();$CRON$);
select cron.schedule('monthly_report','0 7 1 * *',$CRON$select public.fn_monthly_report();$CRON$);
select cron.schedule('quarterly_report','0 8 1 1,4,7,10 *',$CRON$select public.fn_quarterly_report();$CRON$);
select cron.schedule('gl_sync_nightly','0 2 * * *',$CRON$select public.fn_gl_sync_business();$CRON$);
select cron.schedule('autonomy_dispose_hourly','45 * * * *',$CRON$select public.fn_autonomy_dispose()$CRON$);
select cron.schedule('email_triage_hourly','20 * * * *',$CRON$select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/email_triage',
    headers:=jsonb_build_object('Content-Type','application/json'),
    body:=jsonb_build_object('__secret',(select value from public.app_secrets where key='inbound_secret')))$CRON$);
select cron.schedule('doc_reminders_daily','0 5 * * *',$CRON$select public.run_doc_reminders()$CRON$);
select cron.schedule('rfq_clarify_6h','30 */6 * * *',$CRON$select public.run_rfq_clarify(false)$CRON$);
select cron.schedule('supplier_success_daily','20 6 * * *',$CRON$select public.fn_supplier_success();$CRON$);
select cron.schedule('customer_success_daily','40 6 * * *',$CRON$select public.fn_customer_success();$CRON$);
select cron.schedule('finance_ai_daily','20 4 * * *',$CRON$select public.fn_finance_ai();$CRON$);
select cron.schedule('marketing_ai_daily','50 6 * * *',$CRON$select public.fn_marketing_ai();$CRON$);
select cron.schedule('meta_sync_daily','35 3 * * *',$CRON$select net.http_post(url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/meta_sync',
     headers:='{"Content-Type":"application/json"}'::jsonb,
     body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')));$CRON$);
select cron.schedule('knowledge_curator_daily','10 3 * * *',$CRON$select public.fn_knowledge_curator();$CRON$);
select cron.schedule('kb_ingest_queue','*/20 * * * *',$CRON$select net.http_post(url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/kb_ingest',
     headers:='{"Content-Type":"application/json"}'::jsonb,
     body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')));$CRON$);
select cron.schedule('ai_trainer_daily','30 5 * * *',$CRON$select public.fn_ai_trainer();$CRON$);
select cron.schedule('legal_ai_daily','15 5 * * *',$CRON$select public.fn_legal_ai();$CRON$);
select cron.schedule('security_ai_daily','5 5 * * *',$CRON$select public.fn_security_ai();$CRON$);
select cron.schedule('operations_ai_daily','45 4 * * *',$CRON$select public.fn_operations_ai();$CRON$);
select cron.schedule('ea_assistant_daily','0 4 * * *',$CRON$select public.fn_ea_assistant();$CRON$);
select cron.schedule('document_controller_daily','25 4 * * *',$CRON$select public.fn_document_controller();$CRON$);
select cron.schedule('dropbox_sync_daily','40 2 * * *',$CRON$select net.http_post(url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/dropbox_sync',
     headers:='{"Content-Type":"application/json"}'::jsonb,
     body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')));$CRON$);
select cron.schedule('reporting_ai_daily','20 4 * * *',$CRON$select public.fn_reporting_ai();$CRON$);
select cron.schedule('strategy_ai_daily','25 5 * * *',$CRON$select public.fn_strategy_ai();$CRON$);
select cron.schedule('scan_new_supplier_categories','20 3 * * *',$CRON$select public.fn_scan_new_supplier_categories();$CRON$);
select cron.schedule('capability_backfill_daily','40 2 * * *',$CRON$select net.http_post(
  url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/enrich_capability',
  headers:=jsonb_build_object('Content-Type','application/json'),
  body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'),'limit',20));$CRON$);
select cron.schedule('match_eval_weekly','0 5 * * 1',$CRON$select net.http_post(
  url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/match_eval',
  headers:=jsonb_build_object('Content-Type','application/json'),
  body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')));$CRON$);
select cron.schedule('dropbox_backup_scan','*/15 * * * *',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/dropbox_backup',
    headers:=jsonb_build_object('Content-Type','application/json'),
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'),'limit',12),
    timeout_milliseconds:=25000);
$CRON$);
select cron.schedule('collections_legal_daily','15 6 * * *',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/collections_legal',
    headers:=jsonb_build_object('Content-Type','application/json'),
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')),
    timeout_milliseconds:=25000);
$CRON$);
select cron.schedule('backup_watch_daily','0 8 * * *',$CRON$select public.fn_backup_watch();$CRON$);
select cron.schedule('security_selfaudit_daily','20 3 * * *',$CRON$select public.fn_security_selfaudit();$CRON$);
select cron.schedule('ai_quality_watch_daily','40 3 * * *',$CRON$select public.fn_ai_quality_watch();$CRON$);
select cron.schedule('cron_history_prune','20 0 * * *',$CRON$delete from cron.job_run_details where end_time < now() - interval '14 days'$CRON$);
select cron.schedule('finance_reminders_daily','0 5 * * *',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/finance_ingest',
    headers:=jsonb_build_object('Content-Type','application/json'),
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'),'action','remind','reminder_days',3),
    timeout_milliseconds:=30000);
$CRON$);
select cron.schedule('agent_learnings_weekly','0 6 * * 1',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/agent_learnings_report',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'),'notify',true),
    timeout_milliseconds:=120000
  )
$CRON$);
select cron.schedule('kb_autofill_gaps_weekly','0 4 * * *',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/kb_autofill_gaps',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'),'limit',5),
    timeout_milliseconds:=280000
  )
$CRON$);
select cron.schedule('retention_purge_weekly','0 3 * * 0',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/retention_purge',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object(
      '__secret',(select value from app_secrets where key='inbound_secret'),
      'months',6
    )
  )
  $CRON$);
select cron.schedule('email_cron_2min','*/2 * * * *',$CRON$
  select net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/email_cron',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'apikey',(select value from app_secrets where key='anon_key')
    ),
    body := jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'))
  );
$CRON$);
select cron.schedule('licence_block_reconcile_daily','15 3 * * *',$CRON$select public.fn_reconcile_doc_blocks(0)$CRON$);
select cron.schedule('sla_watch_hourly','20 * * * *',$CRON$select public.fn_sla_watch()$CRON$);
select cron.schedule('ai_health_15min','7,22,37,52 * * * *',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/ai_health',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')),
    timeout_milliseconds:=20000)
$CRON$);
select cron.schedule('policy_consistency_weekly','30 6 * * 1',$CRON$select public.fn_policy_consistency_check()$CRON$);
select cron.schedule('founding_rank_daily','10 2 * * *',$CRON$select public.fn_assign_founding_ranks()$CRON$);
select cron.schedule('subscription_billing_daily','40 2 * * *',$CRON$select public.fn_subscription_billing_run(false)$CRON$);
select cron.schedule('llm_drift_watch_daily','25 7 * * *',$CRON$select public.fn_llm_drift_watch()$CRON$);
select cron.schedule('gen_category_personas_daily','15 2 * * *',$CRON$ select net.http_post(
       url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/gen_category_personas',
       headers:='{"Content-Type":"application/json"}'::jsonb,
       body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'),'limit',8)
     ) $CRON$);
select cron.schedule('kb_embed_backfill','*/5 * * * *',$CRON$ select net.http_post(
       url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/kb_embed',
       headers:='{"Content-Type":"application/json"}'::jsonb,
       body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'))
     ) $CRON$);
select cron.schedule('backup_daily','30 3 * * *',$CRON$ select net.http_post(url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/backup',
       headers:='{"Content-Type":"application/json"}'::jsonb,
       body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'))) $CRON$);
select cron.schedule('agent_security_hourly','5 * * * *',$CRON$ select fn_security_scan() $CRON$);
select cron.schedule('agent_silence_watch_daily','40 6 * * *',$CRON$select public.fn_agent_silence_watch();$CRON$);
select cron.schedule('dues_interest_daily','15 3 * * *',$CRON$select public.fn_accrue_dues_interest();$CRON$);
select cron.schedule('dues_ban_overdue_daily','25 3 * * *',$CRON$select public.fn_ban_overdue_dues();$CRON$);
select cron.schedule('doc_final_notice_daily','10 5 * * *',$CRON$select public.fn_doc_final_notice(7)$CRON$);
select cron.schedule('supplier_capability_chase_daily','30 6 * * *',$CRON$select public.fn_supplier_capability_chase();$CRON$);
select cron.schedule('category_sales_daily','30 5 * * *',$CRON$select public.fn_category_sales();$CRON$);
select cron.schedule('backfill_invite_trades','15 4 * * *',$CRON$update public.leads set invite_trades = public.fn_norm_trades(coalesce(company_name,'')||' '||coalesce(categories,'')||' '||coalesce(sector,''))
    where id in (select id from public.leads where invite_trades is null and email is not null and email<>'' limit 3000)$CRON$);
select cron.schedule('invite_ramp_daily','45 8 * * *',$CRON$select public.fn_invite_ramp();$CRON$);
select cron.schedule('invite_campaign_start','45 4 27 7 *',$CRON$
update public.app_secrets set value='true' where key='invite_enabled';
insert into public.founder_alerts(level,event,detail,channel)
  values('info','invite_campaign_started','Supplier invite campaign auto-started Mon 27 Jul — 10/day, fully autonomous (auto-approve, auto-ramp, bounce breaker). No action needed.','system');
select cron.unschedule('invite_campaign_start');
$CRON$);
select cron.schedule('resilience_watch_10min','*/10 * * * *',$CRON$select public.fn_resilience_watch()$CRON$);
select cron.schedule('cos_execute_hourly','50 * * * *',$CRON$
  select net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/cos_execute',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('__secret', (select value from public.app_secrets where key='inbound_secret'))
  );
$CRON$);
select cron.schedule('kb_reconcile_daily','5 3 * * *',$CRON$select public.fn_kb_reconcile();$CRON$);
select cron.schedule('company_selfknowledge_refresh','13 */3 * * *',$CRON$update public.agent_knowledge set content=public.fn_company_brief(1800), updated_at=now() where agent_key='_global' and topic='company:self_knowledge'$CRON$);
select cron.schedule('dept_plan_daily','0 1 * * *',$CRON$select net.http_post(
  url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/dept_plan',
  body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'),'all',true),
  headers:='{"Content-Type":"application/json"}'::jsonb,
  timeout_milliseconds:=9000)$CRON$);
select cron.schedule('dept_learn_daily','30 0 * * *',$CRON$select net.http_post(
  url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/dept_learn',
  body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret'),'all',true),
  headers:='{"Content-Type":"application/json"}'::jsonb,
  timeout_milliseconds:=9000)$CRON$);
select cron.schedule('autonomy_audit_weekly','0 6 * * 1',$CRON$select public.fn_autonomy_audit_run()$CRON$);
select cron.schedule('boost_recommend_weekly','0 8 * * 3',$CRON$select net.http_post(url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/boost_recommend',
  body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')),
  headers:='{"Content-Type":"application/json"}'::jsonb, timeout_milliseconds:=40000)$CRON$);
select cron.schedule('content_revise_hourly','25 * * * *',$CRON$select net.http_post(url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/content_revise',
  body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')),
  headers:='{"Content-Type":"application/json"}'::jsonb, timeout_milliseconds:=60000)$CRON$);
select cron.schedule('canon_eval_weekly','40 6 * * 1',$CRON$select public.fn_recert_rotate()$CRON$);
select cron.schedule('experience_promote_weekly','0 5 * * 0',$CRON$select public.fn_experience_promote()$CRON$);
select cron.schedule('github_org_sync_nightly','10 4 * * *',$CRON$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/github_sync',
    body:=jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')),
    headers:='{"Content-Type":"application/json"}'::jsonb, timeout_milliseconds:=120000)
$CRON$);

-- ===== APP_SECRETS KEY NAMES (values intentionally excluded) =====
--   admin_emails
--   admin_mfa_phone
--   ai_health_fails
--   anon_key
--   apify_token
--   bd_daily_cap
--   bd_outreach_enabled
--   bd_source_mode
--   brand_avatar_url
--   brand_logo_on_navy_url
--   brand_logo_on_white_url
--   brand_mark_transparent_url
--   cloudconvert_api_key
--   company_trn
--   compliance_ref
--   content_secret
--   cos_frozen
--   daily_send_cap
--   default_post_image
--   dropbox_app_key
--   dropbox_app_secret
--   dropbox_oauth_key
--   dropbox_refresh_token
--   dropbox_roots
--   email_enabled
--   email_from_info
--   email_from_supplier
--   email_logo_url
--   email_reply_info
--   email_reply_supplier
--   email_reply_supplier_docs
--   email_signature_name
--   email_signature_title
--   excluded_job_scopes
--   expense_forwarders
--   founding_free_limit
--   github_token
--   inbound_secret
--   inbound_secret_rotated_from_20260719
--   inbound_webhook_secret
--   invite_body
--   invite_daily_cap
--   invite_enabled
--   invite_max_bounce_rate
--   invite_subject
--   invite_target_per_trade
--   job_eligibility_note
--   marketing_golive
--   meta_ad_account_id
--   meta_campaign_filter
--   meta_sync_enabled
--   min_job_value_aed
--   openrouter_api_key
--   otp_hmac_key
--   postiz_api_key
--   postiz_integrations
--   postiz_publish_key
--   public_site_url
--   qa_customer_email
--   qa_customer_password
--   qa_mint_enabled
--   require_structured_quotes
--   resend_api_key
--   resend_domain_id
--   resend_inbound_signing_secret
--   resend_inbound_token
--   resend_webhook_key
--   resend_webhook_signing_secret
--   sla_quote_hours
--   sms_enabled
--   stripe_publishable_key
--   stripe_secret_key
--   stripe_webhook_secret
--   subscription_honour_12m
--   supplier_emails_enabled
--   supplier_subscription_aed
--   supplier_subscription_start
--   supplier_subscription_term
--   supplier_terms_html
--   twilio_account_sid
--   twilio_api_key_secret
--   twilio_api_key_sid
--   twilio_from
--   twilio_verify_service_sid
--   twilio_wa_from
--   uptime_last_autoheal
--   vercel_project
--   vercel_team_id
--   vercel_token
--   virustotal_api_key
--   voice_capture_token
--   voice_otp_last
--   wa_autoreply_enabled
--   wa_template_sids
--   wa_templates_ready
