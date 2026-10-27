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
  WHERE ((qq.quote_amount IS NOT NULL) AND (qq.quote_amount > (0)::numeric) AND (i.category IS NOT NULL) AND (NOT fn_inquiry_is_demo(i.id)))
  GROUP BY i.category;

CREATE OR REPLACE VIEW public.crm_deal_kpis AS  SELECT (( SELECT count(*) AS count
           FROM (inquiries i
             JOIN crm_stages s ON ((s.key = i.pipeline_stage)))
          WHERE ((NOT s.is_won) AND (NOT s.is_lost) AND (NOT fn_inquiry_is_demo(i.id)))))::integer AS open_deals,
    (( SELECT count(*) AS count
           FROM (inquiries i
             JOIN crm_stages s ON ((s.key = i.pipeline_stage)))
          WHERE (s.is_won AND (NOT fn_inquiry_is_demo(i.id)))))::integer AS won_deals,
    (( SELECT count(*) AS count
           FROM (inquiries i
             JOIN crm_stages s ON ((s.key = i.pipeline_stage)))
          WHERE (s.is_lost AND (NOT fn_inquiry_is_demo(i.id)))))::integer AS lost_deals,
    ( SELECT round(avg((EXTRACT(epoch FROM (COALESCE(i.completed_at, now()) - i.created_at)) / 86400.0)), 1) AS round
           FROM (inquiries i
             JOIN crm_stages s ON ((s.key = i.pipeline_stage)))
          WHERE (s.is_won AND (NOT fn_inquiry_is_demo(i.id)))) AS avg_cycle_days,
    ( SELECT round(COALESCE(sum(((i.expected_value * (s.probability)::numeric) / 100.0)), (0)::numeric), 2) AS round
           FROM (inquiries i
             JOIN crm_stages s ON ((s.key = i.pipeline_stage)))
          WHERE ((NOT s.is_won) AND (NOT s.is_lost) AND (NOT fn_inquiry_is_demo(i.id)))) AS weighted_forecast,
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
   FROM customer_health h
  WHERE (NOT (EXISTS ( SELECT 1
           FROM customers c
          WHERE ((c.id = h.customer_id) AND c.is_demo))));

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
        ), rd AS (
         SELECT d.id,
            d.transaction_id,
            d.supplier_id,
            d.quote_id,
            d.quote_amount,
            d.commission_pct,
            d.amount_due,
            d.currency,
            d.reveal_date,
            d.due_date,
            d.due_date_30,
            d.status,
            d.reminders,
            d.last_reminder_at,
            d.overdue_emailed_at,
            d.fine_pct,
            d.fine_amount,
            d.paid_at,
            d.created_at,
            d.interest_amount,
            d.admin_fee,
            d.total_claim,
            d.legal_stage,
            d.legal_escalated_at,
            d.demand_letter_path,
            d.case_file_path,
            d.evidence_terms_path,
            d.payment_ref,
            d.stripe_session_id,
            d.payment_order_filed_on,
            d.payment_order_issued_on,
            d.payment_order_served_on,
            d.grievance_filed_on,
            d.court_reference,
            d.status_reason
           FROM supplier_dues d
          WHERE (COALESCE(fn_gl_fixture_or_orphan(d.transaction_id, d.supplier_id, NULL::uuid), ''::text) !~~ 'fixture:%'::text)
        ), ar AS (
         SELECT COALESCE(sum(rd.amount_due) FILTER (WHERE fn_supplier_due_is_owed(rd.status, rd.paid_at)), (0)::numeric) AS ar_outstanding,
            COALESCE(sum(rd.amount_due) FILTER (WHERE (fn_supplier_due_is_owed(rd.status, rd.paid_at) AND (rd.due_date_30 < CURRENT_DATE))), (0)::numeric) AS ar_overdue,
            COALESCE(sum(rd.amount_due) FILTER (WHERE (rd.status = 'paid'::text)), (0)::numeric) AS ar_collected
           FROM rd
        ), ap AS (
         SELECT COALESCE(sum(ap_open_bills.balance_due), (0)::numeric) AS ap_outstanding,
            COALESCE(sum(ap_open_bills.balance_due) FILTER (WHERE (ap_open_bills.days_overdue > 0)), (0)::numeric) AS ap_overdue
           FROM ap_open_bills
        ), bud AS (
         SELECT count(*) FILTER (WHERE ((budget_vs_actual_summary.type = 'expense'::text) AND (budget_vs_actual_summary.pct_of_budget > (110)::numeric))) AS budget_overruns
           FROM budget_vs_actual_summary
        ), gb AS (
         SELECT COALESCE(sum(b.balance) FILTER (WHERE (b.code = ANY (ARRAY['1000'::text, '1050'::text]))), (0)::numeric) AS cash,
            COALESCE(sum(b.balance) FILTER (WHERE (b.type = 'revenue'::text)), (0)::numeric) AS rev,
            COALESCE(sum(b.balance) FILTER (WHERE (b.type = 'expense'::text)), (0)::numeric) AS exp
           FROM gl_account_balances b
        )
 SELECT gb.cash,
    gb.rev AS revenue_total,
    gb.exp AS expense_total,
    (gb.rev - gb.exp) AS net_income,
        CASE
            WHEN (gb.rev > (0)::numeric) THEN round(((100.0 * (gb.rev - gb.exp)) / gb.rev), 1)
            ELSE NULL::numeric
        END AS margin_pct,
    rr.rev30 AS revenue_30d,
    rr.exp30 AS expense_30d,
    (rr.exp30 - rr.rev30) AS monthly_burn,
        CASE
            WHEN (((rr.exp30 - rr.rev30) > (0)::numeric) AND (gb.cash > (0)::numeric)) THEN round((gb.cash / (rr.exp30 - rr.rev30)), 1)
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
    bud,
    gb;

CREATE OR REPLACE VIEW public.gl_account_balances AS  SELECT a.code,
    a.name,
    a.type,
    a.normal_balance,
    COALESCE(sum(pl.debit), (0)::numeric) AS debit_total,
    COALESCE(sum(pl.credit), (0)::numeric) AS credit_total,
        CASE
            WHEN (a.normal_balance = 'D'::bpchar) THEN (COALESCE(sum(pl.debit), (0)::numeric) - COALESCE(sum(pl.credit), (0)::numeric))
            ELSE (COALESCE(sum(pl.credit), (0)::numeric) - COALESCE(sum(pl.debit), (0)::numeric))
        END AS balance
   FROM (gl_accounts a
     LEFT JOIN (gl_journal_lines pl
     JOIN gl_journal j ON (((j.id = pl.journal_id) AND (j.status = 'posted'::text)))) ON ((pl.account_code = a.code)))
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

CREATE OR REPLACE VIEW public.gl_revenue_lines_measured AS  SELECT l.id AS line_id,
    l.journal_id,
    j.entry_date,
    j.source,
    l.account_code,
    (l.credit - l.debit) AS revenue_aed,
    ((j.source = 'reversal'::text) OR (EXISTS ( SELECT 1
           FROM gl_journal o
          WHERE ((o.reverses = j.id) AND (o.status = 'posted'::text))))) AS is_reversal
   FROM ((gl_journal_lines l
     JOIN gl_journal j ON (((j.id = l.journal_id) AND (j.status = 'posted'::text))))
     JOIN gl_accounts a ON (((a.code = l.account_code) AND (a.type = 'revenue'::text))))
  WHERE (NOT ((j.source = 'reversal'::text) AND (EXISTS ( SELECT 1
           FROM gl_journal o
          WHERE ((o.id = COALESCE(j.reverses,
                CASE
                    WHEN (j.source_ref ~ '^[0-9]+$'::text) THEN (j.source_ref)::bigint
                    ELSE NULL::bigint
                END)) AND (o.status <> 'posted'::text))))));

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

CREATE OR REPLACE VIEW public.inquiries_supplier_live AS  SELECT id,
    category,
    emirate,
    role_needed,
    status,
    created_at,
    scope_type,
    trades,
    keywords,
    brief_source,
    urgency,
    boq_confidence,
    drawing_redacted_paths,
    outcome,
    hired_supplier_id,
    summary_masked AS summary,
    raw_input_masked AS raw_input,
    budget_masked AS budget,
    spec_masked AS spec,
    boq_masked AS boq,
    completeness_masked AS completeness
   FROM inquiries i;

CREATE OR REPLACE VIEW public.inquiries_supplier_safe AS  SELECT i.id,
        CASE
            WHEN (b.brief IS NOT NULL) THEN (b.brief ->> 'category'::text)
            ELSE i.category
        END AS category,
        CASE
            WHEN (b.brief IS NOT NULL) THEN (b.brief ->> 'emirate'::text)
            ELSE i.emirate
        END AS emirate,
        CASE
            WHEN (b.brief IS NOT NULL) THEN (b.brief ->> 'role_needed'::text)
            ELSE i.role_needed
        END AS role_needed,
    i.status,
        CASE
            WHEN (b.brief IS NOT NULL) THEN ((b.brief ->> 'created_at'::text))::timestamp with time zone
            ELSE i.created_at
        END AS created_at,
        CASE
            WHEN (b.brief IS NOT NULL) THEN (b.brief ->> 'scope_type'::text)
            ELSE i.scope_type
        END AS scope_type,
        CASE
            WHEN (b.brief IS NOT NULL) THEN fn_jsonb_text_array((b.brief -> 'trades'::text))
            ELSE i.trades
        END AS trades,
        CASE
            WHEN (b.brief IS NOT NULL) THEN fn_jsonb_text_array((b.brief -> 'keywords'::text))
            ELSE i.keywords
        END AS keywords,
        CASE
            WHEN (b.brief IS NOT NULL) THEN (b.brief ->> 'brief_source'::text)
            ELSE i.brief_source
        END AS brief_source,
        CASE
            WHEN (b.brief IS NOT NULL) THEN (b.brief ->> 'urgency'::text)
            ELSE i.urgency
        END AS urgency,
        CASE
            WHEN (b.brief IS NOT NULL) THEN (b.brief ->> 'boq_confidence'::text)
            ELSE i.boq_confidence
        END AS boq_confidence,
        CASE
            WHEN (b.brief IS NOT NULL) THEN fn_jsonb_text_array((b.brief -> 'drawing_redacted_paths'::text))
            ELSE i.drawing_redacted_paths
        END AS drawing_redacted_paths,
    i.outcome,
    i.hired_supplier_id,
        CASE
            WHEN (b.brief IS NOT NULL) THEN (b.brief ->> 'summary'::text)
            ELSE i.summary_masked
        END AS summary,
        CASE
            WHEN (b.brief IS NOT NULL) THEN (b.brief ->> 'raw_input'::text)
            ELSE i.raw_input_masked
        END AS raw_input,
        CASE
            WHEN (b.brief IS NOT NULL) THEN (b.brief ->> 'budget'::text)
            ELSE i.budget_masked
        END AS budget,
        CASE
            WHEN (b.brief IS NOT NULL) THEN (b.brief -> 'spec'::text)
            ELSE i.spec_masked
        END AS spec,
        CASE
            WHEN (b.brief IS NOT NULL) THEN (b.brief -> 'boq'::text)
            ELSE i.boq_masked
        END AS boq,
        CASE
            WHEN (b.brief IS NOT NULL) THEN (b.brief -> 'completeness'::text)
            ELSE i.completeness_masked
        END AS completeness
   FROM (inquiries i
     LEFT JOIN LATERAL ( SELECT b2.brief
           FROM inquiry_supplier_brief b2
          WHERE (b2.inquiry_id = i.id)
          ORDER BY b2.version DESC
         LIMIT 1) b ON (true));

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
           FROM customers
          WHERE (NOT COALESCE(customers.is_demo, false))) AS customers,
    round(((100.0 * (( SELECT count(*) AS count
           FROM customers
          WHERE ((customers.tos_accepted_at IS NOT NULL) AND (NOT COALESCE(customers.is_demo, false)))))::numeric) / (NULLIF(( SELECT count(*) AS count
           FROM customers
          WHERE (NOT COALESCE(customers.is_demo, false))), 0))::numeric), 1) AS customer_terms_acceptance_pct,
    ( SELECT count(*) AS count
           FROM leads
          WHERE ((leads.approval_status = 'approved'::text) AND (NOT COALESCE(leads.is_demo, false)))) AS suppliers_approved,
    round(((100.0 * (( SELECT count(*) AS count
           FROM leads
          WHERE ((leads.approval_status = 'approved'::text) AND (leads.accepted_terms_at IS NOT NULL) AND (NOT COALESCE(leads.is_demo, false)))))::numeric) / (NULLIF(( SELECT count(*) AS count
           FROM leads
          WHERE ((leads.approval_status = 'approved'::text) AND (NOT COALESCE(leads.is_demo, false)))), 0))::numeric), 1) AS supplier_terms_acceptance_pct,
    ( SELECT count(*) AS count
           FROM agent_actions
          WHERE ((agent_actions.kind = 'legal_flag'::text) AND (agent_actions.status = ANY (ARRAY['pending'::text, 'needs_review'::text])))) AS open_legal_flags,
    ( SELECT count(*) AS count
           FROM legal_reviews
          WHERE ((legal_reviews.risk_level = 'high'::text) AND legal_reviews.needs_licensed_review)) AS high_risk_reviews;

CREATE OR REPLACE VIEW public.marketing_bd_figures AS  SELECT ( SELECT count(*) AS count
           FROM marketing_prospect
          WHERE ((marketing_prospect.status = 'new'::text) AND (NOT marketing_prospect.is_demo))) AS prospects_waiting,
    ( SELECT count(*) AS count
           FROM marketing_outreach_message
          WHERE ((marketing_outreach_message.status = 'draft'::text) AND (NOT marketing_outreach_message.is_demo))) AS drafts_held,
    ( SELECT count(*) AS count
           FROM marketing_outreach_message
          WHERE ((marketing_outreach_message.kind = 'first'::text) AND (marketing_outreach_message.status <> 'draft'::text) AND (NOT marketing_outreach_message.is_demo) AND (marketing_outreach_message.listed_on >= (((now() AT TIME ZONE 'Asia/Dubai'::text))::date - 6)))) AS listed_7d,
    ( SELECT count(*) AS count
           FROM marketing_outreach_message
          WHERE ((marketing_outreach_message.sent_at >= (now() - '7 days'::interval)) AND (NOT marketing_outreach_message.is_demo))) AS sent_7d,
    ( SELECT count(*) AS count
           FROM marketing_outreach_message
          WHERE ((marketing_outreach_message.replied_at >= (now() - '7 days'::interval)) AND (NOT marketing_outreach_message.is_demo))) AS replied_7d,
    ( SELECT count(*) AS count
           FROM marketing_outreach_message
          WHERE ((marketing_outreach_message.converted_at >= (now() - '7 days'::interval)) AND (NOT marketing_outreach_message.is_demo))) AS converted_7d,
    ( SELECT count(*) AS count
           FROM marketing_prospect
          WHERE ((marketing_prospect.status = ANY (ARRAY['sent'::text, 'replied'::text, 'converted'::text, 'declined'::text])) AND (NOT marketing_prospect.is_demo))) AS people_contacted,
    ( SELECT count(*) AS count
           FROM marketing_prospect
          WHERE ((marketing_prospect.status = ANY (ARRAY['replied'::text, 'converted'::text])) AND (NOT marketing_prospect.is_demo))) AS people_replied,
    ( SELECT count(*) AS count
           FROM marketing_prospect
          WHERE ((marketing_prospect.status = 'converted'::text) AND (NOT marketing_prospect.is_demo))) AS people_converted,
    ( SELECT count(*) AS count
           FROM marketing_article
          WHERE ((marketing_article.status = 'draft'::text) AND (NOT marketing_article.is_demo))) AS articles_draft,
    ( SELECT count(*) AS count
           FROM marketing_article
          WHERE ((marketing_article.status = 'approved'::text) AND (NOT marketing_article.is_demo))) AS articles_approved,
    ( SELECT count(*) AS count
           FROM marketing_article
          WHERE ((marketing_article.status = ANY (ARRAY['released'::text, 'live'::text])) AND (NOT marketing_article.is_demo))) AS articles_released,
    ( SELECT count(*) AS count
           FROM marketing_article
          WHERE ((marketing_article.live_at >= (now() - '30 days'::interval)) AND (NOT marketing_article.is_demo))) AS articles_live_30d;

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
        ), nc AS (
         SELECT count(*) AS n
           FROM customers
          WHERE ((customers.created_at >= (now() - '30 days'::interval)) AND (NOT COALESCE(customers.is_demo, false)))
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
           FROM marketing_article
          WHERE ((marketing_article.status = 'live'::text) AND (NOT marketing_article.is_demo))) AS blog_published,
    ( SELECT count(*) AS count
           FROM marketing_article
          WHERE ((marketing_article.status <> 'withdrawn'::text) AND (NOT marketing_article.is_demo))) AS blog_total,
    ( SELECT count(*) AS count
           FROM content_drafts
          WHERE (COALESCE(content_drafts.status, ''::text) <> ALL (ARRAY['published'::text, 'discarded'::text]))) AS drafts_pending,
    ( SELECT count(*) AS count
           FROM social_posts
          WHERE ((COALESCE(social_posts.status, ''::text) = ANY (ARRAY['staged'::text, 'scheduled'::text, 'draft'::text, 'pending'::text])) OR ((social_posts.mode = 'draft'::text) AND (COALESCE(social_posts.status, ''::text) = ANY (ARRAY['published'::text, 'sent'::text]))))) AS social_staged,
    ( SELECT count(*) AS count
           FROM social_posts
          WHERE ((social_posts.mode = 'now'::text) AND (COALESCE(social_posts.status, ''::text) = ANY (ARRAY['published'::text, 'sent'::text])))) AS social_published,
    ( SELECT count(*) AS count
           FROM seo_categories) AS seo_pages,
    ( SELECT count(*) AS count
           FROM seo_categories
          WHERE seo_categories.generated) AS seo_generated,
    ( SELECT count(*) AS count
           FROM leads
          WHERE (NOT COALESCE(leads.is_demo, false))) AS leads_total,
    ( SELECT count(*) AS count
           FROM outreach) AS outreach_sent,
    ( SELECT COALESCE(gl_account_balances.balance, (0)::numeric) AS "coalesce"
           FROM gl_account_balances
          WHERE (gl_account_balances.code = '6200'::text)) AS mkt_spend,
    nc.n AS new_customers_30d,
        CASE
            WHEN (mi.meta_spend > (0)::numeric) THEN round((mi.meta_spend / (NULLIF(nc.n, 0))::numeric), 2)
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
        END AS meta_roi,
    ( SELECT count(*) AS count
           FROM marketing_article
          WHERE ((marketing_article.status = 'draft'::text) AND (NOT marketing_article.is_demo))) AS blog_drafts,
    ( SELECT count(*) AS count
           FROM blog_posts
          WHERE blog_posts.published) AS site_blog_pages
   FROM f,
    mi,
    nc;

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
          WHERE ((inquiries.status = 'quoted'::text) AND (NOT fn_inquiry_is_demo(inquiries.id)) AND (NOT (EXISTS ( SELECT 1
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
    round(COALESCE(sum(i.expected_value), (0)::numeric), 0) AS pipeline_value,
    ( SELECT COALESCE(jsonb_agg(s.b ORDER BY (s.b ->> 'category'::text)), '[]'::jsonb) AS "coalesce"
           FROM ( SELECT jsonb_build_object('category', COALESCE(i2.category, 'uncategorised'::text), 'rfqs', count(*), 'open', count(*) FILTER (WHERE (i2.status <> ALL (ARRAY['completed'::text, 'cancelled'::text]))), 'awarded', count(*) FILTER (WHERE (i2.hired_supplier_id IS NOT NULL)), 'value_aed', round(COALESCE(sum(i2.expected_value), (0)::numeric), 0)) AS b
                   FROM inquiries i2
                  WHERE (i2.project_id = p.id)
                  GROUP BY COALESCE(i2.category, 'uncategorised'::text)) s) AS trade_breakdown,
    ( SELECT count(DISTINCT m.supplier_id) AS count
           FROM (inquiry_matches m
             JOIN inquiries i3 ON ((i3.id = m.inquiry_id)))
          WHERE (i3.project_id = p.id)) AS supplier_count,
        CASE
            WHEN (p.target_open_date IS NULL) THEN NULL::numeric
            WHEN (p.target_open_date <= (p.created_at)::date) THEN (100)::numeric
            ELSE round(LEAST((100)::numeric, GREATEST((0)::numeric, (((100)::numeric * ((CURRENT_DATE - (p.created_at)::date))::numeric) / (NULLIF((p.target_open_date - (p.created_at)::date), 0))::numeric))), 0)
        END AS timeline_pct
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
         SELECT GREATEST(( SELECT max(a.created_at) AS max
                   FROM agent_actions a
                  WHERE (a.kind = 'exec_briefing'::text)), ( SELECT max(n.created_at) AS max
                   FROM notifications n
                  WHERE (n.type = 'founder_brief'::text))) AS daily_at
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
    b.report_type,
    b.title,
    COALESCE((b.week_start)::text, to_char(b.created_at, 'YYYY-MM-DD'::text)) AS period,
    b.created_at,
    b.id,
    b.pdf_path,
    b.pdf_generated_at
   FROM board_reports b
UNION ALL
 SELECT 'exec'::text AS source,
    'exec_summary'::text AS report_type,
    ((e.officer || ' — '::text) || e.period) AS title,
    e.period,
    e.created_at,
    e.id,
    e.pdf_path,
    e.pdf_generated_at
   FROM exec_reports e
UNION ALL
 SELECT 'finance'::text AS source,
    COALESCE(f.kind, 'financial'::text) AS report_type,
    ((('Financial — '::text || COALESCE(f.kind, ''::text)) || ' '::text) || COALESCE((f.period_start)::text, ''::text)) AS title,
    COALESCE((f.period_start)::text, to_char(f.created_at, 'YYYY-MM-DD'::text)) AS period,
    f.created_at,
    f.id,
    f.pdf_path,
    f.pdf_generated_at
   FROM finance_reports f;

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
         SELECT q.supplier_id,
            count(*) AS c
           FROM quotes q
          WHERE ((q.created_at > (now() - '90 days'::interval)) AND (q.supplier_id IS NOT NULL) AND (NOT fn_inquiry_is_demo(q.inquiry_id)) AND (NOT (EXISTS ( SELECT 1
                   FROM leads l
                  WHERE ((l.id = q.supplier_id) AND l.is_demo)))))
          GROUP BY q.supplier_id
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
            l.app_rating AS rating,
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
        CASE
            WHEN (rating IS NULL) THEN round((((COALESCE(((won)::numeric / (NULLIF(quoted, 0))::numeric), (0)::numeric) * 0.35) + (((LEAST(quoted, (10)::bigint))::numeric / 10.0) * 0.15)) / 0.50), 3)
            ELSE round(((((rating / 5.0) * 0.50) + (COALESCE(((won)::numeric / (NULLIF(quoted, 0))::numeric), (0)::numeric) * 0.35)) + (((LEAST(quoted, (10)::bigint))::numeric / 10.0) * 0.15)), 3)
        END AS perf_score
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

CREATE OR REPLACE VIEW public.v_accountant_issued_documents AS  SELECT d.id,
    d.document_kind,
    d.template_key,
    d.template_version,
    d.content_sha256,
    d.recipient,
    d.supplier_id,
    d.due_id,
    d.handoff_id,
    d.file_path,
    d.signed_as,
    d.stamp_required,
    d.signature_required,
    d.issued_at,
    dr.id AS delivery_request_id,
    n.id AS notification_id,
    n.status AS delivery_status,
    n.sent_at,
    n.provider_message_id
   FROM (((accountant_issued_document d
     LEFT JOIN agent_actions h ON ((h.id = d.handoff_id)))
     LEFT JOIN agent_actions dr ON ((dr.id = ((h.evidence ->> 'delivery_request'::text))::bigint)))
     LEFT JOIN notifications n ON ((n.id = ((dr.evidence ->> 'notification_id'::text))::bigint)));

CREATE OR REPLACE VIEW public.v_accountant_recovery_ledger AS  WITH p AS (
         SELECT ( SELECT ((decision_policy.value #>> '{}'::text[]))::integer AS int4
                   FROM decision_policy
                  WHERE (decision_policy.key = 'supplier_charge_final_demand_notice_days'::text)) AS notice_days,
            ( SELECT ((decision_policy.value #>> '{}'::text[]))::integer AS int4
                   FROM decision_policy
                  WHERE (decision_policy.key = 'supplier_charge_legal_minimum_notice_days'::text)) AS min_notice_days,
            ( SELECT ((decision_policy.value #>> '{}'::text[]))::integer AS int4
                   FROM decision_policy
                  WHERE (decision_policy.key = 'supplier_charge_payment_order_serve_months'::text)) AS serve_months,
            ( SELECT ((decision_policy.value #>> '{}'::text[]))::integer AS int4
                   FROM decision_policy
                  WHERE (decision_policy.key = 'supplier_charge_grievance_days'::text)) AS grievance_days,
            ( SELECT ((decision_policy.value #>> '{}'::text[]))::integer AS int4
                   FROM decision_policy
                  WHERE (decision_policy.key = 'supplier_charge_limitation_years'::text)) AS limitation_years
        )
 SELECT d.id AS due_id,
    d.supplier_id,
    l.company_name AS supplier,
    COALESCE(l.is_demo, false) AS demo,
    d.transaction_id,
    d.amount_due AS refund_aed,
    d.admin_fee AS admin_fee_aed,
    d.interest_amount AS interest_aed,
    COALESCE(d.total_claim, ((d.amount_due + COALESCE(d.admin_fee, (0)::numeric)) + COALESCE(d.interest_amount, (0)::numeric))) AS claim_aed,
    d.due_date,
        CASE
            WHEN ((d.paid_at IS NOT NULL) OR (COALESCE(d.status, ''::text) = 'paid'::text)) THEN 'paid'::text
            WHEN (NOT fn_supplier_due_is_owed(d.status, d.paid_at)) THEN d.status
            WHEN (d.grievance_filed_on IS NOT NULL) THEN 'grievance_filed'::text
            WHEN (d.payment_order_served_on IS NOT NULL) THEN 'order_served'::text
            WHEN (d.payment_order_issued_on IS NOT NULL) THEN 'order_issued'::text
            WHEN ((d.payment_order_filed_on IS NOT NULL) OR (COALESCE(d.legal_stage, ''::text) ~~ 'outcome:filed%'::text)) THEN 'filed'::text
            WHEN (d.legal_stage IS NOT NULL) THEN d.legal_stage
            WHEN (COALESCE(d.reminders, 0) > 0) THEN 'reminded'::text
            ELSE 'notice_sent'::text
        END AS stage,
    d.reminders,
    d.last_reminder_at,
        CASE
            WHEN (d.legal_stage IS NOT NULL) THEN d.legal_escalated_at
            ELSE NULL::timestamp with time zone
        END AS demand_sent_at,
        CASE
            WHEN (d.legal_stage IS NOT NULL) THEN (((d.legal_escalated_at AT TIME ZONE 'Asia/Dubai'::text))::date + GREATEST(p.notice_days, p.min_notice_days))
            ELSE NULL::date
        END AS payment_order_earliest_on,
    d.payment_order_filed_on,
    d.payment_order_issued_on,
    ((d.payment_order_issued_on + make_interval(months => p.serve_months)))::date AS serve_order_by,
    d.payment_order_served_on,
    (d.payment_order_served_on + p.grievance_days) AS grievance_until,
    d.grievance_filed_on,
    ((d.due_date + make_interval(years => p.limitation_years)))::date AS limitation_on,
    d.court_reference,
    d.demand_letter_path,
    d.case_file_path,
    d.paid_at,
    'docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md; the documents are rendered by supabase/functions/_shared/supplier_charge_documents.ts'::text AS legal_pack,
    '9% a year simple interest on the refund plus the AED 250 fee, from the due date, never compounded (CTL Arts 73, 86, 88; Supplier Agreement clauses 31 and 33)'::text AS interest_rule,
    fn_supplier_due_is_owed(d.status, d.paid_at) AS owed
   FROM ((supplier_dues d
     LEFT JOIN leads l ON ((l.id = d.supplier_id)))
     CROSS JOIN p);

CREATE OR REPLACE VIEW public.v_accountant_refund_reserve AS  WITH open_case AS (
         SELECT c_1.transaction_id,
            max(c_1.amount_aed) AS amount_aed,
            string_agg(((('refund '::text || COALESCE((c_1.refund_id)::text, '?'::text)) || ' '::text) || c_1.state), ', '::text) AS cases
           FROM refund_case c_1
          WHERE (c_1.state = ANY (ARRAY['requested'::text, 'investigating'::text, 'eligible'::text, 'ceo_authorized'::text, 'submitted'::text, 'provider_pending'::text, 'failed'::text]))
          GROUP BY c_1.transaction_id
        ), in_window AS (
         SELECT t_1.id AS transaction_id,
            COALESCE(t_1.total_charged, t_1.reveal_fee) AS amount_aed,
            t_1.refund_deadline
           FROM transactions t_1
          WHERE ((t_1.fee_status = 'paid'::text) AND (t_1.refund_deadline > now()) AND (COALESCE(t_1.refund_status, ''::text) <> ALL (ARRAY['refunded'::text, 'succeeded'::text, 'rejected'::text])))
        )
 SELECT COALESCE(o.transaction_id, w.transaction_id) AS transaction_id,
    GREATEST(COALESCE(o.amount_aed, (0)::numeric), COALESCE(w.amount_aed, (0)::numeric)) AS held_aed,
        CASE
            WHEN (o.transaction_id IS NOT NULL) THEN ('open refund case '::text || o.cases)
            ELSE ('inside the supplier-response window until '::text || to_char((w.refund_deadline AT TIME ZONE 'Asia/Dubai'::text), 'DD Mon YYYY HH24:MI'::text))
        END AS reason,
    COALESCE(c.is_demo, false) AS demo
   FROM (((open_case o
     FULL JOIN in_window w ON ((w.transaction_id = o.transaction_id)))
     LEFT JOIN transactions t ON ((t.id = COALESCE(o.transaction_id, w.transaction_id))))
     LEFT JOIN customers c ON ((c.id = t.customer_id)));

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

CREATE OR REPLACE VIEW public.v_bi_scorecard AS  WITH latest AS (
         SELECT DISTINCT ON (s.metric_key) s.metric_key,
            s.value,
            s.error,
            s.taken_at
           FROM metric_snapshot s
          ORDER BY s.metric_key, s.taken_at DESC
        )
 SELECT d.metric_key,
    d.label,
    d.domain,
    d.owner_dept,
    l.value,
    d.target,
    d.direction,
        CASE
            WHEN (l.error IS NOT NULL) THEN 'ERROR'::text
            WHEN ((l.value IS NULL) OR (d.target IS NULL)) THEN 'UNMEASURED'::text
            WHEN ((d.direction = 'up'::text) AND (l.value >= d.target)) THEN 'ON_TARGET'::text
            WHEN ((d.direction = 'down'::text) AND (l.value <= d.target)) THEN 'ON_TARGET'::text
            WHEN ((d.direction = 'up'::text) AND (l.value >= (d.target * 0.7))) THEN 'BEHIND'::text
            WHEN ((d.direction = 'down'::text) AND (l.value <= (d.target * 1.3))) THEN 'BEHIND'::text
            ELSE 'OFF_TARGET'::text
        END AS state,
    l.error,
    l.taken_at,
    d.definition
   FROM (metric_definition d
     LEFT JOIN latest l ON ((l.metric_key = d.metric_key)))
  WHERE d.active;

CREATE OR REPLACE VIEW public.v_category_coverage AS  SELECT c.num,
    c.slug AS catalog_slug,
    c.name,
    c.regulated,
    m.agent_slug,
    (m.agent_slug = c.slug) AS agent_is_canonical,
    COALESCE(( SELECT count(*) AS count
           FROM agent_knowledge k
          WHERE ((k.agent_key = ('cat:'::text || c.slug)) AND (k.topic IN ( SELECT knowledge_module_standard.module
                   FROM knowledge_module_standard
                  WHERE knowledge_module_standard.required)))), (0)::bigint) AS standard_modules,
    COALESCE(( SELECT count(*) AS count
           FROM agent_knowledge k
          WHERE (k.agent_key = ('cat:'::text || COALESCE(m.agent_slug, '~none~'::text)))), (0)::bigint) AS legacy_rows_elsewhere,
    ( SELECT count(DISTINCT l.id) AS count
           FROM (lead_trade_map t
             JOIN leads l ON ((l.invite_trades && ARRAY[t.trade_key])))
          WHERE (t.catalog_slug = c.slug)) AS supplier_supply,
        CASE
            WHEN (COALESCE(( SELECT count(*) AS count
               FROM agent_knowledge k
              WHERE ((k.agent_key = ('cat:'::text || c.slug)) AND (k.topic IN ( SELECT knowledge_module_standard.module
                       FROM knowledge_module_standard
                      WHERE knowledge_module_standard.required)))), (0)::bigint) = 14) THEN 'COMPLIANT'::text
            WHEN (m.status = 'mapped'::text) THEN 'MAPPED_NOT_TO_STANDARD'::text
            ELSE 'NO_AGENT'::text
        END AS coverage
   FROM (catalog_supplier_categories c
     LEFT JOIN category_agent_map m ON ((m.catalog_slug = c.slug)));

CREATE OR REPLACE VIEW public.v_category_open AS  SELECT c.num,
    c.slug,
    c.name,
    c.regulated,
    ( SELECT count(DISTINCT l.id) AS count
           FROM (leads l
             JOIN lead_trade_map t ON ((l.invite_trades && ARRAY[t.trade_key])))
          WHERE ((t.catalog_slug = c.slug) AND (l.registration_submitted_at IS NOT NULL) AND (l.approval_status = 'approved'::text) AND COALESCE(l.verified, false))) AS verified_registered_suppliers,
    p.category_open_min_suppliers AS min_required,
    (( SELECT count(DISTINCT l.id) AS count
           FROM (leads l
             JOIN lead_trade_map t ON ((l.invite_trades && ARRAY[t.trade_key])))
          WHERE ((t.catalog_slug = c.slug) AND (l.registration_submitted_at IS NOT NULL) AND (l.approval_status = 'approved'::text) AND COALESCE(l.verified, false))) >= p.category_open_min_suppliers) AS is_open
   FROM (catalog_supplier_categories c
     CROSS JOIN ( SELECT pricing_config.category_open_min_suppliers
           FROM pricing_config
          WHERE (pricing_config.id = 1)) p);

CREATE OR REPLACE VIEW public.v_company_subscriptions AS  WITH last_rcpt AS (
         SELECT lower(expense_entries.vendor) AS v,
            max(expense_entries.charged_on) AS last_charged,
            count(*) AS receipts
           FROM expense_entries
          GROUP BY (lower(expense_entries.vendor))
        )
 SELECT 'cost'::text AS kind,
    e.vendor AS item,
    e.amount,
    e.currency,
    e.cadence,
    COALESCE(r.last_charged, e.expense_date) AS last_charged,
    e.next_due AS renews_on,
    COALESCE(r.receipts, (0)::bigint) AS receipts,
    'accountant'::text AS owner_seat,
    'expenses'::text AS source
   FROM (expenses e
     LEFT JOIN last_rcpt r ON ((r.v = lower(e.vendor))))
  WHERE e.active
UNION ALL
 SELECT x.kind,
    x.item,
    NULL::numeric AS amount,
    NULL::text AS currency,
    'on expiry'::text AS cadence,
    NULL::date AS last_charged,
    x.expires_on AS renews_on,
    NULL::bigint AS receipts,
    x.owner_seat,
    'it_expiry'::text AS source
   FROM it_expiry x;

CREATE OR REPLACE VIEW public.v_conversation_message AS  SELECT 'inbound_messages'::text AS source_table,
    (m.id)::text AS source_id,
    'email'::text AS channel,
    'in'::text AS direction,
    m.created_at AS occurred_at,
    m.from_email AS from_addr,
    m.to_email AS to_addr,
    NULL::text AS cc,
    m.subject,
    m.body,
    m.html,
    jsonb_build_object('count', COALESCE(m.attachments_count, 0)) AS attachments,
    p.party_kind,
    p.party_id,
    p.inquiry_id,
    ((COALESCE(m.from_email, ''::text) ~* 'example\.invalid'::text) OR p.demo) AS is_demo
   FROM (inbound_messages m
     CROSS JOIN LATERAL fn_conversation_party(m.lead_id, NULL::uuid, NULL::uuid, m.from_email, NULL::text) p(party_kind, party_id, inquiry_id, demo))
UNION ALL
 SELECT 'notifications'::text AS source_table,
    (n.id)::text AS source_id,
    COALESCE(n.channel, 'email'::text) AS channel,
    'out'::text AS direction,
    COALESCE(n.sent_at, n.created_at) AS occurred_at,
    COALESCE(n.sender, 'QuotesDone'::text) AS from_addr,
    COALESCE(n.to_email, n.to_phone) AS to_addr,
    array_to_string(n.cc_emails, ', '::text) AS cc,
    n.subject,
    n.body,
    n.html,
    COALESCE(n.attachments, '[]'::jsonb) AS attachments,
    p.party_kind,
    p.party_id,
    COALESCE(p.inquiry_id, (n.inquiry_id)::text) AS inquiry_id,
    ((COALESCE(n.to_email, ''::text) ~* 'example\.invalid'::text) OR (COALESCE(n.subject, ''::text) ~* 'ZZ DEMO'::text) OR p.demo) AS is_demo
   FROM (notifications n
     CROSS JOIN LATERAL fn_conversation_party(n.lead_id, NULL::uuid, n.inquiry_id, n.to_email, n.to_phone) p(party_kind, party_id, inquiry_id, demo))
  WHERE ((n.status = 'sent'::text) AND (COALESCE(n.channel, 'email'::text) = ANY (ARRAY['email'::text, 'whatsapp'::text])))
UNION ALL
 SELECT 'wa_messages'::text AS source_table,
    (w.id)::text AS source_id,
    'whatsapp'::text AS channel,
    'in'::text AS direction,
    w.created_at AS occurred_at,
    w.wa_from AS from_addr,
    w.wa_to AS to_addr,
    NULL::text AS cc,
    ('WhatsApp'::text || COALESCE((' from '::text || NULLIF(w.profile_name, ''::text)), ''::text)) AS subject,
    ((('Received:'::text || '
'::text) || COALESCE(w.inbound, ''::text)) ||
        CASE
            WHEN (COALESCE(w.reply, ''::text) <> ''::text) THEN ((((('

'::text || 'Replied'::text) ||
            CASE
                WHEN w.sent THEN ''::text
                ELSE ' (not delivered)'::text
            END) || ':'::text) || '
'::text) || w.reply)
            ELSE ''::text
        END) AS body,
    NULL::text AS html,
    '[]'::jsonb AS attachments,
    p.party_kind,
    p.party_id,
    p.inquiry_id,
    p.demo AS is_demo
   FROM (wa_messages w
     CROSS JOIN LATERAL fn_conversation_party(NULL::bigint, NULL::uuid, NULL::uuid, NULL::text, w.wa_from) p(party_kind, party_id, inquiry_id, demo))
UNION ALL
 SELECT 'messages'::text AS source_table,
    (pm.id)::text AS source_id,
    'chat'::text AS channel,
        CASE
            WHEN (pm.sender = ANY (ARRAY['customer'::text, 'supplier'::text])) THEN 'in'::text
            ELSE 'out'::text
        END AS direction,
    pm.created_at AS occurred_at,
    pm.sender AS from_addr,
    NULL::text AS to_addr,
    NULL::text AS cc,
    ('Portal chat - '::text || COALESCE(pm.sender, ''::text)) AS subject,
    (pm.body || COALESCE((('

'::text || 'Attachment: '::text) || pm.attachment_path), ''::text)) AS body,
    NULL::text AS html,
        CASE
            WHEN (pm.attachment_path IS NULL) THEN '[]'::jsonb
            ELSE jsonb_build_array(jsonb_build_object('path', pm.attachment_path))
        END AS attachments,
    p.party_kind,
    p.party_id,
    COALESCE(p.inquiry_id, (pm.inquiry_id)::text) AS inquiry_id,
    p.demo AS is_demo
   FROM (messages pm
     CROSS JOIN LATERAL fn_conversation_party(pm.supplier_id, pm.customer_id, pm.inquiry_id, NULL::text, NULL::text) p(party_kind, party_id, inquiry_id, demo))
UNION ALL
 SELECT 'rfq_clarification'::text AS source_table,
    (r.id)::text AS source_id,
    'chat'::text AS channel,
    'in'::text AS direction,
    r.asked_at AS occurred_at,
    ('supplier '::text || COALESCE((r.supplier_id)::text, ''::text)) AS from_addr,
    NULL::text AS to_addr,
    NULL::text AS cc,
    ('Clarification - '::text || COALESCE(r.kind, ''::text)) AS subject,
    ((('Question:'::text || '
'::text) || COALESCE(r.question, ''::text)) ||
        CASE
            WHEN (r.answer IS NOT NULL) THEN ((('

'::text || 'Answer:'::text) || '
'::text) || r.answer)
            ELSE ''::text
        END) AS body,
    NULL::text AS html,
    '[]'::jsonb AS attachments,
    p.party_kind,
    p.party_id,
    COALESCE(p.inquiry_id, (r.inquiry_id)::text) AS inquiry_id,
    p.demo AS is_demo
   FROM (rfq_clarification r
     CROSS JOIN LATERAL fn_conversation_party(r.supplier_id, NULL::uuid, r.inquiry_id, NULL::text, NULL::text) p(party_kind, party_id, inquiry_id, demo))
UNION ALL
 SELECT 'assistant_logs'::text AS source_table,
    (a.id)::text AS source_id,
    'chat'::text AS channel,
    'in'::text AS direction,
    a.created_at AS occurred_at,
        CASE
            WHEN (a.audience ~ '^customer:'::text) THEN 'portal customer'::text
            ELSE 'website visitor'::text
        END AS from_addr,
    COALESCE(a.seat, 'customer_support'::text) AS to_addr,
    NULL::text AS cc,
    (
        CASE
            WHEN (a.seat = 'sales_engineer'::text) THEN 'Portal - sales engineer'::text
            ELSE 'Website assistant'::text
        END || COALESCE((' - '::text || a.path), ''::text)) AS subject,
    (((((('Asked:'::text || '
'::text) || COALESCE(a.message, ''::text)) || '

'::text) || 'Answered:'::text) || '
'::text) || COALESCE(a.reply, ''::text)) AS body,
    NULL::text AS html,
    '[]'::jsonb AS attachments,
    p.party_kind,
    p.party_id,
    p.inquiry_id,
    p.demo AS is_demo
   FROM (assistant_logs a
     CROSS JOIN LATERAL fn_conversation_party(NULL::bigint,
        CASE
            WHEN (a.audience ~ '^customer:[0-9a-f-]{36}$'::text) THEN (SUBSTRING(a.audience FROM 10))::uuid
            ELSE NULL::uuid
        END, NULL::uuid, NULL::text, NULL::text) p(party_kind, party_id, inquiry_id, demo))
UNION ALL
 SELECT 'contact_messages'::text AS source_table,
    (cm.id)::text AS source_id,
    'form'::text AS channel,
    'in'::text AS direction,
    cm.created_at AS occurred_at,
    COALESCE(cm.email, cm.phone) AS from_addr,
    NULL::text AS to_addr,
    NULL::text AS cc,
    ('Contact form'::text || COALESCE((' - '::text || cm.name), ''::text)) AS subject,
    cm.message AS body,
    NULL::text AS html,
    '[]'::jsonb AS attachments,
    p.party_kind,
    p.party_id,
    p.inquiry_id,
    ((COALESCE(cm.email, ''::text) ~* 'example\.invalid'::text) OR p.demo) AS is_demo
   FROM (contact_messages cm
     CROSS JOIN LATERAL fn_conversation_party(NULL::bigint, NULL::uuid, NULL::uuid, cm.email, cm.phone) p(party_kind, party_id, inquiry_id, demo))
UNION ALL
 SELECT 'complaint_tickets'::text AS source_table,
    (ct.id)::text AS source_id,
    'form'::text AS channel,
    'in'::text AS direction,
    ct.created_at AS occurred_at,
    ct.email AS from_addr,
    NULL::text AS to_addr,
    NULL::text AS cc,
    ('Complaint '::text || COALESCE(ct.ticket_no, ''::text)) AS subject,
    (COALESCE(ct.message, ''::text) ||
        CASE
            WHEN (ct.final_response IS NOT NULL) THEN ((('

'::text || 'Final response:'::text) || '
'::text) || ct.final_response)
            ELSE ''::text
        END) AS body,
    NULL::text AS html,
    '[]'::jsonb AS attachments,
    p.party_kind,
    p.party_id,
    p.inquiry_id,
    ((COALESCE(ct.email, ''::text) ~* 'example\.invalid'::text) OR p.demo) AS is_demo
   FROM (complaint_tickets ct
     CROSS JOIN LATERAL fn_conversation_party(NULL::bigint, NULL::uuid, NULL::uuid, ct.email, NULL::text) p(party_kind, party_id, inquiry_id, demo))
UNION ALL
 SELECT 'quote_review_messages'::text AS source_table,
    (q.id)::text AS source_id,
    'chat'::text AS channel,
        CASE
            WHEN (q.role = 'supplier'::text) THEN 'in'::text
            ELSE 'out'::text
        END AS direction,
    q.created_at AS occurred_at,
        CASE
            WHEN (q.role = 'supplier'::text) THEN ('supplier '::text || COALESCE((qr.supplier_id)::text, ''::text))
            ELSE COALESCE(q.role, ''::text)
        END AS from_addr,
    NULL::text AS to_addr,
    NULL::text AS cc,
    ((('Quotation review - job '::text || upper("left"(COALESCE((qr.inquiry_id)::text, ''::text), 8))) || ' - '::text) || COALESCE(q.role, ''::text)) AS subject,
    (COALESCE(q.body, ''::text) ||
        CASE
            WHEN (COALESCE(q.body_ar, ''::text) <> ''::text) THEN ('

'::text || q.body_ar)
            ELSE ''::text
        END) AS body,
    NULL::text AS html,
    COALESCE(q.attachments, '[]'::jsonb) AS attachments,
    p.party_kind,
    p.party_id,
    COALESCE(p.inquiry_id, (qr.inquiry_id)::text) AS inquiry_id,
    p.demo AS is_demo
   FROM ((quote_review_messages q
     JOIN quote_reviews qr ON ((qr.id = q.review_id)))
     CROSS JOIN LATERAL fn_conversation_party(qr.supplier_id, NULL::uuid, NULL::uuid, NULL::text, NULL::text) p(party_kind, party_id, inquiry_id, demo))
UNION ALL
 SELECT 'social_message'::text AS source_table,
    (sm.id)::text AS source_id,
    sc.platform AS channel,
    sm.direction,
    sm.occurred_at,
        CASE
            WHEN (sm.direction = 'in'::text) THEN COALESCE(NULLIF(sc.handle, ''::text), sc.user_id)
            WHEN (sm.author = 'human'::text) THEN 'QuotesDone (team)'::text
            ELSE 'QuotesDone (marketing, auto)'::text
        END AS from_addr,
        CASE
            WHEN (sm.direction = 'in'::text) THEN 'QuotesDone'::text
            ELSE COALESCE(NULLIF(sc.handle, ''::text), sc.user_id)
        END AS to_addr,
    NULL::text AS cc,
    ((((initcap(sc.platform) || ' '::text) ||
        CASE
            WHEN (sm.channel = 'dm'::text) THEN 'message'::text
            ELSE 'comment'::text
        END) || ' - '::text) || COALESCE(NULLIF(sc.handle, ''::text), sc.user_id)) AS subject,
    (sm.body ||
        CASE
            WHEN ((sm.direction = 'out'::text) AND (sm.author = 'seat'::text)) THEN (('

'::text || 'Delivery: '::text) || COALESCE(sm.send_status, 'pending'::text))
            ELSE ''::text
        END) AS body,
    NULL::text AS html,
    '[]'::jsonb AS attachments,
    p.party_kind,
    p.party_id,
    p.inquiry_id,
    sc.is_demo
   FROM ((social_message sm
     JOIN social_conversation sc ON ((sc.id = sm.conversation_id)))
     CROSS JOIN LATERAL fn_conversation_party(NULL::bigint, NULL::uuid, NULL::uuid, NULL::text, NULL::text) p(party_kind, party_id, inquiry_id, demo));

CREATE OR REPLACE VIEW public.v_critical_capability_tests AS  WITH latest AS (
         SELECT DISTINCT ON (agent_runs.agent) agent_runs.agent,
            agent_runs.status,
            agent_runs.started_at
           FROM agent_runs
          ORDER BY agent_runs.agent, agent_runs.started_at DESC
        )
 SELECT capability_key,
    capability,
    owner_dept,
    test_kind,
    test_ref,
    why_critical,
        CASE
            WHEN ((test_kind = 'none'::text) OR (test_ref IS NULL)) THEN 'UNTESTED'::text
            WHEN (test_kind = 'rpc_selftest'::text) THEN 'SELFTEST_ON_BUILD'::text
            WHEN (test_kind = 'scenario'::text) THEN COALESCE(( SELECT
                    CASE
                        WHEN (s.last_result = 'pass'::text) THEN 'PASSING'::text
                        WHEN (s.last_result = 'not_run'::text) THEN 'NEVER_RUN'::text
                        ELSE 'FAILING'::text
                    END AS "case"
               FROM scenario_library s
              WHERE (s.scenario_key = c.test_ref)), 'NEVER_RUN'::text)
            WHEN (test_kind = 'suite'::text) THEN COALESCE(( SELECT
                    CASE
                        WHEN (l.status = 'ok'::text) THEN 'PASSING'::text
                        ELSE 'FAILING'::text
                    END AS "case"
               FROM latest l
              WHERE (l.agent = c.test_ref)), 'NEVER_RUN'::text)
            ELSE 'UNKNOWN'::text
        END AS state,
        CASE
            WHEN ((test_kind = 'suite'::text) AND (COALESCE(( SELECT t.pass_pct
               FROM v_test_matrix t
              WHERE (t.suite = c.test_ref)), (100)::numeric) < (100)::numeric)) THEN true
            ELSE false
        END AS flaky_in_window,
    ( SELECT t.pass_pct
           FROM v_test_matrix t
          WHERE (t.suite = c.test_ref)) AS pass_pct_14d,
    ( SELECT l.started_at
           FROM latest l
          WHERE (l.agent = c.test_ref)) AS last_run
   FROM critical_capability c;

CREATE OR REPLACE VIEW public.v_cron_failing AS  SELECT j.jobname,
    j.schedule,
    j.active,
    count(*) FILTER (WHERE (d.status <> 'succeeded'::text)) AS failed_runs,
    count(*) AS total_runs,
    min(d.start_time) FILTER (WHERE (d.status <> 'succeeded'::text)) AS first_failure,
    max(d.start_time) FILTER (WHERE (d.status <> 'succeeded'::text)) AS last_failure,
    max(d.start_time) FILTER (WHERE (d.status = 'succeeded'::text)) AS last_success,
    "left"((array_agg(d.return_message ORDER BY d.start_time DESC) FILTER (WHERE (d.status <> 'succeeded'::text)))[1], 300) AS last_error
   FROM (cron.job j
     JOIN cron.job_run_details d ON ((d.jobid = j.jobid)))
  WHERE (d.start_time > (now() - '7 days'::interval))
  GROUP BY j.jobname, j.schedule, j.active
 HAVING (count(*) FILTER (WHERE (d.status <> 'succeeded'::text)) > 0);

CREATE OR REPLACE VIEW public.v_cron_stale AS  WITH j AS (
         SELECT job.jobid,
            job.jobname,
            job.schedule,
            split_part(job.schedule, ' '::text, 1) AS m,
            split_part(job.schedule, ' '::text, 2) AS h,
            split_part(job.schedule, ' '::text, 3) AS dom,
            split_part(job.schedule, ' '::text, 5) AS dow
           FROM cron.job
          WHERE job.active
        ), iv AS (
         SELECT j.jobid,
            j.jobname,
            j.schedule,
            j.m,
            j.h,
            j.dom,
            j.dow,
                CASE
                    WHEN ((j.m ~~ '*/%'::text) AND (j.m ~ '^\*/[0-9]+$'::text)) THEN (((substr(j.m, 3))::integer)::double precision * '00:01:00'::interval)
                    WHEN ((j.m ~ '^[0-9]+$'::text) AND (j.h = '*'::text)) THEN '01:00:00'::interval
                    WHEN ((j.h ~~ '*/%'::text) AND (j.h ~ '^\*/[0-9]+$'::text)) THEN (((substr(j.h, 3))::integer)::double precision * '01:00:00'::interval)
                    WHEN (j.dom ~ '^[0-9]+$'::text) THEN '31 days'::interval
                    WHEN (j.dow ~ '^[0-6]$'::text) THEN '7 days'::interval
                    ELSE '1 day'::interval
                END AS every
           FROM j
        ), runs AS (
         SELECT job_run_details.jobid,
            max(job_run_details.start_time) AS last_any,
            min(job_run_details.start_time) AS first_any
           FROM cron.job_run_details
          GROUP BY job_run_details.jobid
        ), act AS (
         SELECT iv.jobid,
            iv.jobname,
            iv.schedule,
            iv.m,
            iv.h,
            iv.dom,
            iv.dow,
            iv.every,
            runs.last_any,
            runs.first_any AS activated_at
           FROM (iv
             LEFT JOIN runs ON ((runs.jobid = iv.jobid)))
        )
 SELECT jobid,
    jobname,
    schedule,
    every,
    activated_at,
    last_any,
        CASE
            WHEN (activated_at IS NULL) THEN 'active with no wrapper and no run ever recorded'::text
            ELSE format('no run of any status since %s; schedule %s means one was due every %s'::text, COALESCE((last_any)::text, 'never'::text), schedule, every)
        END AS why
   FROM act
  WHERE (((activated_at IS NULL) OR (activated_at < (now() - ((2)::double precision * every)))) AND ((last_any IS NULL) OR (last_any < (now() - ((2)::double precision * every)))));

CREATE OR REPLACE VIEW public.v_department_health AS  WITH base AS (
         SELECT d.dept_key,
            d.name AS department,
            d.health_fn
           FROM org_departments d
        ), tasks AS (
         SELECT t.dept_key,
            count(*) AS n,
            count(*) FILTER (WHERE (t.status = 'done'::text)) AS done,
            count(*) FILTER (WHERE (t.status = ANY (ARRAY['failed'::text, 'blocked'::text]))) AS bad
           FROM org_tasks t
          WHERE (t.updated_at > (now() - '14 days'::interval))
          GROUP BY t.dept_key
        ), runs AS (
         SELECT a.department AS dept_key,
            count(*) AS n,
            count(*) FILTER (WHERE (r.status = 'ok'::text)) AS ok
           FROM (agent_runs r
             JOIN org_agents a ON ((a.agent_key = r.agent)))
          WHERE (r.started_at > (now() - '7 days'::interval))
          GROUP BY a.department
        ), scored AS (
         SELECT b.dept_key,
            b.department,
                CASE
                    WHEN ((COALESCE(t.n, (0)::bigint) > 0) AND (COALESCE(r.n, (0)::bigint) > 0)) THEN round(((((100.0 * ((t.done)::numeric + ((((t.n - t.done) - t.bad))::numeric * 0.5))) / (NULLIF(t.n, 0))::numeric) + ((100.0 * (r.ok)::numeric) / (NULLIF(r.n, 0))::numeric)) / (2)::numeric))
                    WHEN (COALESCE(t.n, (0)::bigint) > 0) THEN round(((100.0 * ((t.done)::numeric + ((((t.n - t.done) - t.bad))::numeric * 0.5))) / (NULLIF(t.n, 0))::numeric))
                    WHEN (COALESCE(r.n, (0)::bigint) > 0) THEN round(((100.0 * (r.ok)::numeric) / (NULLIF(r.n, 0))::numeric))
                    ELSE NULL::numeric
                END AS score,
                CASE
                    WHEN ((COALESCE(t.n, (0)::bigint) > 0) AND (COALESCE(r.n, (0)::bigint) > 0)) THEN (((((((('task throughput ('::text || t.done) || ' done of '::text) || t.n) || ', 14d) and run success ('::text) || r.ok) || ' ok of '::text) || r.n) || ', 7d)'::text)
                    WHEN (COALESCE(t.n, (0)::bigint) > 0) THEN (((('task throughput ('::text || t.done) || ' done of '::text) || t.n) || ', 14d); no runs recorded for its staff'::text)
                    WHEN (COALESCE(r.n, (0)::bigint) > 0) THEN (((('run success ('::text || r.ok) || ' ok of '::text) || r.n) || ', 7d); no tasks moved in 14d'::text)
                    ELSE 'no tasks moved and no runs recorded — nothing to measure yet'::text
                END AS basis
           FROM ((base b
             LEFT JOIN tasks t ON ((t.dept_key = b.dept_key)))
             LEFT JOIN runs r ON ((r.dept_key = b.dept_key)))
        )
 SELECT dept_key,
    department,
    GREATEST((0)::numeric, LEAST((100)::numeric, COALESCE(score, (0)::numeric))) AS score,
    basis,
        CASE
            WHEN (score IS NULL) THEN 'no data'::text
            WHEN (score >= (90)::numeric) THEN 'healthy'::text
            WHEN (score >= (70)::numeric) THEN 'watch'::text
            WHEN (score > (0)::numeric) THEN 'at risk'::text
            ELSE 'no data'::text
        END AS status
   FROM scored;

CREATE OR REPLACE VIEW public.v_digital_twin AS  SELECT ( SELECT count(*) AS count
           FROM org_agents
          WHERE org_agents.active) AS employees_active,
    ( SELECT count(*) AS count
           FROM org_departments
          WHERE org_departments.active) AS departments,
    ( SELECT count(*) AS count
           FROM company_goals
          WHERE company_goals.active) AS company_goals,
    ( SELECT count(*) AS count
           FROM catalog_supplier_categories) AS categories_target,
    ( SELECT count(*) AS count
           FROM category_agent_map
          WHERE (category_agent_map.status = 'mapped'::text)) AS categories_covered,
    ( SELECT count(*) AS count
           FROM v_knowledge_compliance
          WHERE (v_knowledge_compliance.verdict = 'COMPLIANT'::text)) AS knowledge_bases_compliant,
    ( SELECT count(*) AS count
           FROM leads) AS suppliers_in_pipeline,
    ( SELECT count(*) AS count
           FROM inquiries) AS inquiries_total,
    ( SELECT count(*) AS count
           FROM quotes) AS quotes_total,
    ( SELECT count(*) AS count
           FROM transactions) AS transactions_total,
    ( SELECT COALESCE(sum(z.amount_aed), (0)::numeric) AS "coalesce"
           FROM ( SELECT (0)::numeric AS amount_aed) z) AS revenue_placeholder,
    ( SELECT count(*) AS count
           FROM org_tasks
          WHERE (org_tasks.status = ANY (ARRAY['assigned'::text, 'in_progress'::text]))) AS work_in_progress,
    ( SELECT count(*) AS count
           FROM org_tasks
          WHERE (org_tasks.status = 'proposed'::text)) AS awaiting_founder,
    ( SELECT count(*) AS count
           FROM risk_register
          WHERE (risk_register.status = 'open'::text)) AS open_risks,
    ( SELECT count(*) AS count
           FROM institutional_memory) AS memories_held,
    ( SELECT count(*) AS count
           FROM company_event
          WHERE (company_event.occurred_at > (now() - '24:00:00'::interval))) AS events_24h,
    ( SELECT count(*) AS count
           FROM agent_runs
          WHERE (agent_runs.started_at > (now() - '24:00:00'::interval))) AS agent_runs_24h,
    ( SELECT count(*) AS count
           FROM agent_runs
          WHERE ((agent_runs.started_at > (now() - '24:00:00'::interval)) AND (agent_runs.status = 'error'::text))) AS agent_errors_24h,
    ( SELECT count(*) AS count
           FROM spec_backlog
          WHERE (spec_backlog.status = 'pending'::text)) AS open_backlog,
    ( SELECT count(*) AS count
           FROM spec_backlog
          WHERE ((spec_backlog.status = 'pending'::text) AND (spec_backlog.priority = 1))) AS open_p1;

CREATE OR REPLACE VIEW public.v_edge_function_health AS  WITH runs AS (
         SELECT SUBSTRING(agent_runs.agent FROM 4) AS fn,
            agent_runs.started_at,
            agent_runs.status,
            (NULLIF((agent_runs.counts ->> 'ms'::text), ''::text))::numeric AS ms,
            (NULLIF((agent_runs.counts ->> 'http'::text), ''::text))::integer AS http,
            agent_runs.note
           FROM agent_runs
          WHERE ((agent_runs.agent ~~ 'fn:%'::text) AND (agent_runs.started_at > (now() - '8 days'::interval)))
        ), recent AS (
         SELECT runs.fn,
            count(*) AS runs_1h,
            count(*) FILTER (WHERE (runs.status = 'error'::text)) AS errors_1h,
            count(*) FILTER (WHERE (runs.status = 'warn'::text)) AS warns_1h,
            percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((runs.ms)::double precision)) FILTER (WHERE (runs.status <> 'error'::text)) AS p50_ms_1h,
            percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY ((runs.ms)::double precision)) FILTER (WHERE (runs.status <> 'error'::text)) AS p95_ms_1h,
            max(runs.ms) AS max_ms_1h
           FROM runs
          WHERE (runs.started_at > (now() - '01:00:00'::interval))
          GROUP BY runs.fn
        ), baseline AS (
         SELECT runs.fn,
            count(*) AS runs_7d,
            percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((runs.ms)::double precision)) FILTER (WHERE (runs.status <> 'error'::text)) AS p50_ms_7d,
            percentile_cont((0.95)::double precision) WITHIN GROUP (ORDER BY ((runs.ms)::double precision)) FILTER (WHERE (runs.status <> 'error'::text)) AS p95_ms_7d
           FROM runs
          WHERE ((runs.started_at >= ((now() - '7 days'::interval) - '01:00:00'::interval)) AND (runs.started_at <= (now() - '01:00:00'::interval)))
          GROUP BY runs.fn
        ), day AS (
         SELECT runs.fn,
            count(*) AS runs_24h,
            count(*) FILTER (WHERE (runs.status = 'error'::text)) AS errors_24h,
            count(*) FILTER (WHERE (runs.status = 'warn'::text)) AS warns_24h,
            max(runs.started_at) AS last_run_at,
            max(runs.started_at) FILTER (WHERE (runs.status = 'error'::text)) AS last_error_at,
            (array_agg(runs.note ORDER BY runs.started_at DESC) FILTER (WHERE (runs.status = 'error'::text)))[1] AS last_error_note,
            (array_agg(runs.http ORDER BY runs.started_at DESC) FILTER (WHERE (runs.status = 'error'::text)))[1] AS last_error_http
           FROM runs
          WHERE (runs.started_at > (now() - '24:00:00'::interval))
          GROUP BY runs.fn
        )
 SELECT COALESCE(d.fn, r.fn, b.fn) AS fn,
    COALESCE(d.runs_24h, (0)::bigint) AS runs_24h,
    COALESCE(d.errors_24h, (0)::bigint) AS errors_24h,
    COALESCE(d.warns_24h, (0)::bigint) AS warns_24h,
    COALESCE(r.runs_1h, (0)::bigint) AS runs_1h,
    COALESCE(r.errors_1h, (0)::bigint) AS errors_1h,
    COALESCE(r.warns_1h, (0)::bigint) AS warns_1h,
    round(r.p50_ms_1h) AS p50_ms_1h,
    round(r.p95_ms_1h) AS p95_ms_1h,
    r.max_ms_1h,
    COALESCE(b.runs_7d, (0)::bigint) AS baseline_runs_7d,
    round(b.p50_ms_7d) AS baseline_p50_ms,
    round(b.p95_ms_7d) AS baseline_p95_ms,
        CASE
            WHEN ((b.p95_ms_7d IS NOT NULL) AND (b.p95_ms_7d > (0)::double precision) AND (r.p95_ms_1h IS NOT NULL)) THEN round(((r.p95_ms_1h / b.p95_ms_7d))::numeric, 2)
            ELSE NULL::numeric
        END AS lag_ratio,
    COALESCE(r.runs_1h, (0)::bigint) AS lag_sample_n,
    COALESCE(b.runs_7d, (0)::bigint) AS lag_baseline_n,
    d.last_run_at,
    d.last_error_at,
    d.last_error_http,
    d.last_error_note
   FROM ((day d
     FULL JOIN recent r ON ((r.fn = d.fn)))
     FULL JOIN baseline b ON ((b.fn = COALESCE(d.fn, r.fn))));

CREATE OR REPLACE VIEW public.v_event_backbone AS  SELECT event_type,
    count(DISTINCT agent_key) AS subscribers,
    ( SELECT count(*) AS count
           FROM company_event e
          WHERE (e.event_type = s.event_type)) AS events_ever,
    ( SELECT count(*) AS count
           FROM company_event e
          WHERE ((e.event_type = s.event_type) AND (e.occurred_at > (now() - '24:00:00'::interval)))) AS events_24h,
    ( SELECT count(*) AS count
           FROM event_delivery d
          WHERE (d.event_type = s.event_type)) AS deliveries,
        CASE
            WHEN (( SELECT count(*) AS count
               FROM company_event e
              WHERE (e.event_type = s.event_type)) = 0) THEN 'NO_EVENTS_EVER'::text
            WHEN (( SELECT count(*) AS count
               FROM event_delivery d
              WHERE (d.event_type = s.event_type)) = 0) THEN 'UNDELIVERED'::text
            ELSE 'LIVE'::text
        END AS state,
    ( SELECT count(*) AS count
           FROM event_rollup r
          WHERE (r.event_type = s.event_type)) AS chains,
    ( SELECT count(*) AS count
           FROM event_rollup r
          WHERE ((r.event_type = s.event_type) AND (r.outcome = ANY (ARRAY['open'::text, 'partial'::text])))) AS chains_open
   FROM event_subscription s
  WHERE active
  GROUP BY event_type
  ORDER BY event_type;

CREATE OR REPLACE VIEW public.v_executions_without_decision_trace AS  SELECT a.id,
    a.action_class,
    a.executor,
    a.correlation_id,
    a.status,
    a.created_at
   FROM (action_execution a
     LEFT JOIN decision_trace d ON ((d.correlation_id = a.correlation_id)))
  WHERE (d.id IS NULL);

CREATE OR REPLACE VIEW public.v_expense_documents AS  SELECT id,
    vendor,
    charged_on,
    amount,
    currency,
    category,
    source_msg_id,
        CASE
            WHEN (source_msg_id ~~ 'resend:%'::text) THEN 'resend'::text
            WHEN (source_msg_id ~~ 'gmail:%'::text) THEN 'gmail'::text
            WHEN (source_msg_id ~~ 'outlook:%'::text) THEN 'outlook'::text
            WHEN (source_msg_id IS NULL) THEN 'none'::text
            ELSE split_part(source_msg_id, ':'::text, 1)
        END AS source_channel,
    'receipt-files'::text AS doc_bucket,
    doc_path,
    doc_name,
    doc_content_type,
    doc_kind,
    doc_note,
        CASE
            WHEN (doc_path IS NULL) THEN 'missing'::text
            WHEN (doc_kind IS NULL) THEN 'unclassified'::text
            ELSE doc_kind
        END AS document_state,
    (doc_path IS NOT NULL) AS is_openable
   FROM expense_entries e;

CREATE OR REPLACE VIEW public.v_expense_receipt_gap AS  SELECT id,
    vendor,
    amount,
    currency,
    charged_on,
    source,
    doc_name,
    created_at,
    (CURRENT_DATE - charged_on) AS age_days,
    ((doc_name IS NOT NULL) AND (doc_name <> ''::text)) AS document_was_received,
        CASE
            WHEN ((doc_name IS NOT NULL) AND (doc_name <> ''::text)) THEN 'the receipt was received and read but the archive write was refused - re-forward the vendor email to the inbound address to retry'::text
            ELSE 'no receipt document was ever attached to this entry - retrieve the invoice from the vendor billing portal and attach it manually'::text
        END AS remedy
   FROM expense_entries e
  WHERE (doc_path IS NULL)
  ORDER BY charged_on DESC;

CREATE OR REPLACE VIEW public.v_file_quarantine AS  SELECT id,
    sha256,
    verdict,
    source,
    subject,
    filename,
    mime,
    size_bytes,
    bucket,
    path,
    engines_malicious,
    engines_suspicious,
    engines_total,
    vt_status,
    blocked,
    detail,
    created_at,
    rechecked_at
   FROM file_scan f
  WHERE (verdict <> 'clean'::text)
  ORDER BY created_at DESC;

CREATE OR REPLACE VIEW public.v_internal_credential_health AS  SELECT id,
    context,
    label,
    is_legacy,
    active,
    COALESCE(array_length(scope, 1), 0) AS scope_size,
    scope,
    use_count,
    last_used_at,
    last_function,
        CASE
            WHEN (last_used_at IS NULL) THEN NULL::integer
            ELSE ((EXTRACT(epoch FROM (now() - last_used_at)) / (86400)::numeric))::integer
        END AS days_since_use,
    ((EXTRACT(epoch FROM (now() - created_at)) / (86400)::numeric))::integer AS age_days,
    rotated_at,
    expires_at,
        CASE
            WHEN (expires_at IS NULL) THEN NULL::integer
            ELSE ((EXTRACT(epoch FROM (expires_at - now())) / (86400)::numeric))::integer
        END AS days_until_expiry,
    (active AND ((last_used_at IS NULL) OR (last_used_at < (now() - '30 days'::interval)))) AS unused_30d
   FROM internal_credential c;

CREATE OR REPLACE VIEW public.v_internal_secret_migration_progress AS  WITH j AS (
         SELECT job.jobid,
            job.jobname,
            job.active,
            (regexp_match(job.command, 'functions/v1/([a-z0-9_]+)'::text))[1] AS target_function,
            (job.command ~ 'key\s*=\s*''inbound_secret'''::text) AS on_shared_secret,
            (regexp_match(job.command, 'key\s*=\s*''(cred_[a-z0-9_]+)'''::text))[1] AS scoped_key
           FROM cron.job
        )
 SELECT ( SELECT count(*) AS count
           FROM j) AS cron_jobs_total,
    ( SELECT count(*) AS count
           FROM j
          WHERE j.on_shared_secret) AS still_on_shared_secret,
    ( SELECT count(*) AS count
           FROM j
          WHERE (j.on_shared_secret AND j.active)) AS still_on_shared_secret_active,
    ( SELECT count(*) AS count
           FROM j
          WHERE (j.scoped_key IS NOT NULL)) AS moved_to_scoped_credential,
    ( SELECT count(DISTINCT j.target_function) AS count
           FROM j
          WHERE (j.on_shared_secret AND (j.target_function IS NOT NULL))) AS functions_still_reachable_by_shared_secret,
    ( SELECT internal_credential.use_count
           FROM internal_credential
          WHERE (internal_credential.context = 'legacy.shared'::text)) AS shared_secret_use_count,
    ( SELECT internal_credential.last_used_at
           FROM internal_credential
          WHERE (internal_credential.context = 'legacy.shared'::text)) AS shared_secret_last_used,
    ( SELECT internal_credential.last_function
           FROM internal_credential
          WHERE (internal_credential.context = 'legacy.shared'::text)) AS shared_secret_last_function,
    ( SELECT count(*) AS count
           FROM internal_credential
          WHERE (internal_credential.active AND (NOT internal_credential.is_legacy))) AS scoped_credentials_issued,
    ((( SELECT count(*) AS count
           FROM j
          WHERE (j.on_shared_secret AND j.active)) = 0) AND (COALESCE(( SELECT internal_credential.last_used_at
           FROM internal_credential
          WHERE (internal_credential.context = 'legacy.shared'::text)), '1970-01-01 00:00:00+00'::timestamp with time zone) < (now() - '7 days'::interval))) AS safe_to_withdraw_shared_secret;

CREATE OR REPLACE VIEW public.v_invite_deliverability_daily AS  SELECT ((invited_at AT TIME ZONE 'Asia/Dubai'::text))::date AS dubai_day,
    count(*) AS sent,
    count(*) FILTER (WHERE (invite_status = 'bounced'::text)) AS bounced,
    count(*) FILTER (WHERE (invite_status = 'complained'::text)) AS complained,
    round(((count(*) FILTER (WHERE (invite_status = 'bounced'::text)))::numeric / (count(*))::numeric), 4) AS bounce_rate,
    round(((count(*) FILTER (WHERE (invite_status = 'complained'::text)))::numeric / (count(*))::numeric), 4) AS complaint_rate
   FROM leads l
  WHERE (invited_at IS NOT NULL)
  GROUP BY (((invited_at AT TIME ZONE 'Asia/Dubai'::text))::date);

CREATE OR REPLACE VIEW public.v_kb_coverage AS  SELECT c.slug AS category,
    c.name AS label,
    c.num,
    (COALESCE(sum(s.chunks), (0)::numeric))::bigint AS chunks,
        CASE
            WHEN (COALESCE(sum(s.chunks), (0)::numeric) = (0)::numeric) THEN 'gap'::text
            WHEN (COALESCE(sum(s.chunks), (0)::numeric) < (3)::numeric) THEN 'thin'::text
            ELSE 'covered'::text
        END AS status
   FROM (catalog_supplier_categories c
     LEFT JOIN kb_category_stats s ON ((regexp_replace(s.category, '^cat:'::text, ''::text) = c.slug)))
  GROUP BY c.slug, c.name, c.num;

CREATE OR REPLACE VIEW public.v_knowledge_compliance AS  SELECT a.slug AS agent_slug,
    a.name,
    a.agent_class,
    count(k.topic) FILTER (WHERE (k.topic IS NOT NULL)) AS modules_present,
    ( SELECT count(*) AS count
           FROM knowledge_module_standard
          WHERE knowledge_module_standard.required) AS modules_required,
    string_agg(s.module, ', '::text ORDER BY s.ord) FILTER (WHERE (k.topic IS NULL)) AS missing_modules,
        CASE
            WHEN (count(k.topic) FILTER (WHERE (k.topic IS NOT NULL)) = ( SELECT count(*) AS count
               FROM knowledge_module_standard
              WHERE knowledge_module_standard.required)) THEN 'COMPLIANT'::text
            ELSE 'INCOMPLETE'::text
        END AS verdict
   FROM ((category_agents a
     CROSS JOIN knowledge_module_standard s)
     LEFT JOIN agent_knowledge k ON (((k.agent_key = ('cat:'::text || a.slug)) AND (k.topic = s.module))))
  WHERE (s.required AND (a.agent_class <> 'internal_staff'::text))
  GROUP BY a.slug, a.name, a.agent_class;

CREATE OR REPLACE VIEW public.v_knowledge_ml_source AS  SELECT 'seat_case_memory'::text AS src,
    (m.id)::text AS row_id,
    NULL::text AS title,
    m.situation AS body,
    1 AS priority
   FROM seat_case_memory m
UNION ALL
 SELECT 'ceo_knowledge'::text AS src,
    c.record_id AS row_id,
    c.title,
    c.body,
    2 AS priority
   FROM ceo_knowledge c
UNION ALL
 SELECT 'support_knowledge'::text AS src,
    s.record_id AS row_id,
    s.title,
    s.body,
    2 AS priority
   FROM support_knowledge s
UNION ALL
 SELECT 'accountant_knowledge'::text AS src,
    a.record_id AS row_id,
    a.title,
    a.content AS body,
    2 AS priority
   FROM accountant_knowledge a
  WHERE a.runtime_index_eligible
UNION ALL
 SELECT 'it_engineer_knowledge'::text AS src,
    i.record_id AS row_id,
    i.title,
    i.content AS body,
    2 AS priority
   FROM it_engineer_knowledge i
  WHERE i.runtime_index_eligible
UNION ALL
 SELECT 'marketing_knowledge'::text AS src,
    k.record_id AS row_id,
    k.title,
    k.content AS body,
    2 AS priority
   FROM marketing_knowledge k
  WHERE k.runtime_index_eligible
UNION ALL
 SELECT 'sales_knowledge'::text AS src,
    s.record_id AS row_id,
    s.title,
    s.content AS body,
    2 AS priority
   FROM sales_knowledge s
  WHERE s.runtime_index_eligible
UNION ALL
 SELECT 'company_faq'::text AS src,
    (f.id)::text AS row_id,
    f.question AS title,
    f.answer AS body,
    3 AS priority
   FROM company_faq f
  WHERE (f.status = 'approved'::text)
UNION ALL
 SELECT 'agent_knowledge'::text AS src,
    (g.id)::text AS row_id,
    g.topic AS title,
    g.content AS body,
    3 AS priority
   FROM agent_knowledge g
  WHERE (g.agent_key = ANY (ARRAY['_global'::text, 'ceo'::text, 'customer_support'::text, 'sales_engineer'::text, 'accountant'::text, 'it_engineer'::text, 'marketing'::text]))
UNION ALL
 SELECT 'ops_knowledge'::text AS src,
    o.record_id AS row_id,
    o.title,
    o.content AS body,
    3 AS priority
   FROM ops_knowledge o
  WHERE (o.runtime_eligible AND (o.supersession_state = 'current'::text) AND (o.scope_type = ANY (ARRAY['company'::text, 'external_source'::text, 'category'::text])))
UNION ALL
 SELECT 'reasoning_knowledge_candidate'::text AS src,
    (r.id)::text AS row_id,
    r.question AS title,
    r.finding AS body,
    3 AS priority
   FROM reasoning_knowledge_candidate r
  WHERE (r.status <> 'rejected'::text)
UNION ALL
 SELECT 'kb_chunks'::text AS src,
    (k.id)::text AS row_id,
    k.title,
    k.content AS body,
    9 AS priority
   FROM kb_chunks k;

CREATE OR REPLACE VIEW public.v_legacy_secret_users AS  SELECT function_name,
    count(*) AS uses,
    min(at) AS first_seen,
    max(at) AS last_seen
   FROM internal_credential_audit
  WHERE ((reason = 'legacy_secret_used'::text) AND (at > (now() - '7 days'::interval)))
  GROUP BY function_name
  ORDER BY (count(*)) DESC;

CREATE OR REPLACE VIEW public.v_marketing_social_volume AS  SELECT c.platform,
    count(DISTINCT c.id) AS conversations,
    count(DISTINCT c.id) FILTER (WHERE (c.status = 'handed_to_human'::text)) AS waiting_for_founder,
    count(m.id) FILTER (WHERE (m.direction = 'in'::text)) AS inbound_total,
    count(m.id) FILTER (WHERE ((m.direction = 'in'::text) AND (m.occurred_at > (now() - '1 day'::interval)))) AS inbound_24h,
    count(m.id) FILTER (WHERE ((m.direction = 'in'::text) AND (m.occurred_at > (now() - '7 days'::interval)))) AS inbound_7d,
    count(m.id) FILTER (WHERE ((m.author = 'seat'::text) AND (m.send_status = 'sent'::text))) AS auto_replies_sent,
    count(m.id) FILTER (WHERE ((m.author = 'seat'::text) AND (m.send_status = 'held_switch_off'::text))) AS auto_replies_held_switch_off,
    count(m.id) FILTER (WHERE ((m.author = 'seat'::text) AND (m.reply_kind = 'handoff'::text))) AS handoffs,
    count(m.id) FILTER (WHERE ((m.author = 'seat'::text) AND (m.reply_kind = 'unknown'::text))) AS unanswered_gaps,
    count(m.id) FILTER (WHERE (m.author = 'human'::text)) AS founder_replies,
    max(m.occurred_at) FILTER (WHERE (m.direction = 'in'::text)) AS last_inbound_at
   FROM (social_conversation c
     LEFT JOIN social_message m ON ((m.conversation_id = c.id)))
  WHERE (NOT c.is_demo)
  GROUP BY c.platform;

CREATE OR REPLACE VIEW public.v_openrouter_call_log AS  SELECT c.id,
    c.occurred_at,
    ((c.occurred_at AT TIME ZONE 'Asia/Dubai'::text))::date AS dubai_day,
    COALESCE(c.seat, '(unattributed)'::text) AS seat,
    COALESCE(c.seat_basis, 'unattributed'::text) AS seat_basis,
    c.fn AS used_by_function,
    c.task_class AS purpose,
    c.model_used,
    c.tier,
    c.prompt_tokens,
    c.output_tokens,
    c.cached_in_tokens,
    c.cache_write_tokens,
    c.generation_id,
    c.cost_usd_reported,
    c.cost_aed AS cost_aed_rate_card,
        CASE
            WHEN ((c.model_used = 'none'::text) OR c.cached) THEN 'free'::text
            WHEN (COALESCE(c.cost_usd_reported, NULLIF(c.cost_aed, (0)::numeric)) IS NOT NULL) THEN 'priced'::text
            ELSE 'unpriced'::text
        END AS cost_basis,
        CASE
            WHEN ((c.model_used = 'none'::text) OR c.cached) THEN (0)::numeric
            WHEN (c.cost_usd_reported IS NOT NULL) THEN c.cost_usd_reported
            WHEN (COALESCE(c.cost_aed, (0)::numeric) > (0)::numeric) THEN round((c.cost_aed / r.fx), 6)
            ELSE NULL::numeric
        END AS cost_usd,
    c.ok,
    c.latency_ms,
    c.model_selected_because
   FROM (ai_cost_log c
     CROSS JOIN ( SELECT COALESCE(max(gl_settings.num_value), 3.6725) AS fx
           FROM gl_settings
          WHERE (gl_settings.key = 'usd_to_aed'::text)) r);

CREATE OR REPLACE VIEW public.v_openrouter_position AS  SELECT read_at,
    credits_total_usd AS account_topped_up_usd,
    cumulative_usd AS account_spent_usd,
    round((credits_total_usd - cumulative_usd), 4) AS account_balance_usd,
    limit_remaining_usd AS key_cap_remaining_usd,
        CASE
            WHEN (limit_remaining_usd IS NULL) THEN 'account_balance'::text
            WHEN (limit_remaining_usd <= round((credits_total_usd - cumulative_usd), 4)) THEN 'key_cap'::text
            ELSE 'account_balance'::text
        END AS binding_constraint,
    LEAST(COALESCE(limit_remaining_usd, 'Infinity'::numeric), round((credits_total_usd - cumulative_usd), 4)) AS spendable_now_usd,
    'account_balance_usd is money the company owns. key_cap_remaining_usd is a per-key spending limit that can be raised in the OpenRouter dashboard at no cost. They are different things and they run out at different times; spendable_now_usd is whichever binds first.'::text AS reading_note
   FROM openrouter_meter m
  WHERE ok
  ORDER BY read_at DESC
 LIMIT 1;

CREATE OR REPLACE VIEW public.v_org_open_tasks AS  SELECT id,
    objective_id,
    dept_key,
    title,
    detail,
    status,
    tier,
    needs_founder,
    result,
    created_at,
    updated_at,
    decided_by,
    action_class,
    attempts,
    last_run_at,
    root_cause,
    assigned_agent,
    priority
   FROM org_tasks t
  WHERE (status <> ALL (ARRAY['done'::text, 'cancelled'::text]));

CREATE OR REPLACE VIEW public.v_os_health AS  SELECT num,
    os_key,
    name,
    owner_agent,
    employees,
    open_tasks,
    round(((open_tasks)::numeric / (NULLIF(employees, 0))::numeric), 2) AS backlog_per_head,
    ( SELECT count(*) AS count
           FROM (org_tasks t
             JOIN os_department od ON ((od.dept_key = t.dept_key)))
          WHERE ((od.os_key = s.os_key) AND (t.status <> 'done'::text) AND (t.created_at < (now() - '14 days'::interval)))) AS stale_tasks,
    ( SELECT round(((100.0 * (count(*) FILTER (WHERE (rc.decision = 'approve'::text)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS round
           FROM (review_chain rc
             JOIN os_department od ON ((od.dept_key = rc.dept_key)))
          WHERE (od.os_key = s.os_key)) AS review_pass_pct,
    ( SELECT count(*) AS count
           FROM risk_register r
          WHERE (EXISTS ( SELECT 1
                   FROM (os_department od
                     JOIN org_agents a ON ((a.department = od.dept_key)))
                  WHERE ((od.os_key = s.os_key) AND (a.agent_key = r.owner_agent))))) AS open_risks,
    ( SELECT count(*) AS count
           FROM (org_tasks t
             JOIN os_department od ON ((od.dept_key = t.dept_key)))
          WHERE ((od.os_key = s.os_key) AND (t.title ~~ 'KPI missed:%'::text) AND (t.status <> 'done'::text))) AS kpi_gaps,
    budget_aed,
    spent_aed,
    round(((100.0 * spent_aed) / NULLIF(budget_aed, (0)::numeric)), 1) AS budget_pct,
    ( SELECT round(((100.0 * (count(*) FILTER (WHERE t.needs_founder))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS round
           FROM (org_tasks t
             JOIN os_department od ON ((od.dept_key = t.dept_key)))
          WHERE ((od.os_key = s.os_key) AND (t.status <> 'done'::text))) AS needs_founder_pct
   FROM v_os_scoreboard s;

CREATE OR REPLACE VIEW public.v_os_scoreboard AS  SELECT o.num,
    o.os_key,
    o.name,
    o.owner_agent,
    count(DISTINCT od.dept_key) AS departments,
    count(DISTINCT a.agent_key) AS employees,
    count(DISTINCT t.id) FILTER (WHERE (t.status <> 'done'::text)) AS open_tasks,
    COALESCE(sum(DISTINCT b.monthly_aed), (0)::numeric) AS budget_aed,
    COALESCE(sum(DISTINCT b.spent_aed), (0)::numeric) AS spent_aed,
    count(DISTINCT k.id) FILTER (WHERE k.active) AS kpis,
    count(DISTINCT k.id) FILTER (WHERE (k.active AND (k.measure_sql IS NULL))) AS kpis_unmeasurable
   FROM (((((operating_system o
     LEFT JOIN os_department od ON ((od.os_key = o.os_key)))
     LEFT JOIN org_agents a ON (((a.department = od.dept_key) AND a.active)))
     LEFT JOIN org_tasks t ON ((t.dept_key = od.dept_key)))
     LEFT JOIN department_budget b ON ((b.dept_key = od.dept_key)))
     LEFT JOIN employee_kpi k ON ((k.agent_key = a.agent_key)))
  WHERE o.active
  GROUP BY o.num, o.os_key, o.name, o.owner_agent
  ORDER BY o.num;

CREATE OR REPLACE VIEW public.v_refund_documents AS  SELECT r.id,
    r.transaction_id,
    r.status,
    r.reason_code,
    r.amount_fils,
    r.currency,
    r.requested_by,
    r.stripe_payment_intent,
    r.stripe_charge_id,
    r.stripe_refund_id,
    r.refund_decision_id,
    r.stripe_receipt_url,
    'finance-docs'::text AS doc_bucket,
    r.doc_path,
    r.doc_name,
    r.doc_content_type,
    r.doc_kind,
    r.doc_note,
        CASE
            WHEN ((r.doc_path IS NOT NULL) AND (r.doc_kind IS NULL)) THEN 'unclassified'::text
            WHEN (r.doc_path IS NOT NULL) THEN r.doc_kind
            WHEN (r.stripe_receipt_url IS NOT NULL) THEN 'reference_only'::text
            ELSE 'missing'::text
        END AS document_state,
    (r.doc_path IS NOT NULL) AS is_openable,
        CASE
            WHEN (lower(COALESCE(r.requested_by, ''::text)) = ANY (ARRAY['stripe_webhook'::text, 'stripe_dashboard'::text, 'stripe'::text])) THEN 'external'::text
            WHEN (r.transaction_id IS NULL) THEN 'no_transaction'::text
            WHEN (COALESCE(btrim(r.stripe_payment_intent), ''::text) = ''::text) THEN 'no_reference'::text
            WHEN (btrim(r.stripe_payment_intent) = btrim(COALESCE(t.payment_ref, ''::text))) THEN 'bound'::text
            ELSE 'mismatched'::text
        END AS stripe_binding
   FROM (refunds r
     LEFT JOIN transactions t ON ((t.id = r.transaction_id)));

CREATE OR REPLACE VIEW public.v_resource_pressure AS  WITH live AS (
         SELECT r.id,
            r.resource,
            r.kind,
            r.owner_dept,
            r.unit,
            r.capacity,
            r.committed,
            r.window_label,
            r.degrade_at_pct,
            r.halt_at_pct,
            r.source_ref,
            r.note,
            r.updated_at,
            r.os_key,
                CASE
                    WHEN (r.source_ref = 'org_agents.max_open_tasks'::text) THEN ( SELECT (count(*))::numeric AS count
                       FROM (v_org_open_tasks t
                         JOIN os_department od ON ((od.dept_key = t.dept_key)))
                      WHERE (od.os_key = r.os_key))
                    ELSE r.committed
                END AS committed_live
           FROM resource_pool r
        )
 SELECT resource,
    kind,
    owner_dept,
    unit,
    capacity,
    committed_live AS committed,
        CASE
            WHEN (capacity > (0)::numeric) THEN round(((100.0 * committed_live) / capacity), 1)
            ELSE NULL::numeric
        END AS used_pct,
        CASE
            WHEN (capacity = (0)::numeric) THEN 'UNSET'::text
            WHEN (((100.0 * committed_live) / capacity) >= (halt_at_pct)::numeric) THEN 'HALT'::text
            WHEN (((100.0 * committed_live) / capacity) >= (degrade_at_pct)::numeric) THEN 'DEGRADE'::text
            ELSE 'OK'::text
        END AS state,
    note
   FROM live;

CREATE OR REPLACE VIEW public.v_revenue_documents AS  SELECT id,
    quote_id,
    customer_id,
    supplier_id,
    revealed_at,
    fee_status,
    reveal_fee,
    payment_ref,
    refund_status,
    stripe_invoice_id,
    stripe_invoice_number,
    stripe_invoice_status,
    stripe_invoice_total_fils,
    stripe_invoice_currency,
    stripe_invoice_pdf_url,
    stripe_invoice_hosted_url,
    'finance-docs'::text AS doc_bucket,
    doc_path,
    doc_name,
    doc_content_type,
    doc_kind,
    doc_note,
        CASE
            WHEN ((doc_path IS NOT NULL) AND (doc_kind IS NULL)) THEN 'unclassified'::text
            WHEN (doc_path IS NOT NULL) THEN doc_kind
            WHEN (stripe_invoice_id IS NOT NULL) THEN 'reference_only'::text
            ELSE 'missing'::text
        END AS document_state,
    (doc_path IS NOT NULL) AS is_openable,
        CASE
            WHEN (stripe_invoice_total_fils IS NULL) THEN 'unknown'::text
            WHEN (stripe_invoice_total_fils = (round((COALESCE(reveal_fee, (0)::numeric) * (100)::numeric)))::bigint) THEN 'agrees'::text
            ELSE 'disagrees'::text
        END AS invoice_agrees_with_fee,
    ((fee_status = 'paid'::text) AND (COALESCE(reveal_fee, (0)::numeric) > (0)::numeric)) AS fee_was_taken
   FROM transactions t;

CREATE OR REPLACE VIEW public.v_supplier_billing AS  WITH cfg AS (
         SELECT s_1.start_date,
            s_1.fee,
            s_1.free_limit,
            COALESCE(( SELECT (lower(a.value) = 'true'::text)
                   FROM app_secrets a
                  WHERE (a.key = 'subscription_honour_12m'::text)), false) AS honour_12m
           FROM fn_supplier_subscription() s_1(fee, currency, period, start_date, free_limit, fee_source, start_source, free_source)
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
        ), st AS (
         SELECT s.supplier_id,
            s.company_name,
            s.email,
            s.founding_rank,
            s.subscription_exempt,
            s.subscription_paid_until,
            s.banned,
            s.matching_blocked,
            s.registered_on,
            s.start_date,
            s.fee,
            s.free_limit,
            s.honour_12m,
                CASE
                    WHEN (s.start_date IS NULL) THEN NULL::date
                    WHEN s.honour_12m THEN GREATEST(s.start_date, ((s.registered_on + '1 year'::interval))::date)
                    ELSE s.start_date
                END AS billing_starts_on,
                CASE
                    WHEN (s.start_date IS NOT NULL) THEN (CURRENT_DATE <
                    CASE
                        WHEN s.honour_12m THEN GREATEST(s.start_date, ((s.registered_on + '1 year'::interval))::date)
                        ELSE s.start_date
                    END)
                    ELSE ((s.founding_rank IS NULL) OR (s.founding_rank <= s.free_limit))
                END AS not_yet
           FROM s
        )
 SELECT supplier_id,
    company_name,
    email,
    founding_rank,
    subscription_exempt,
    registered_on,
    subscription_paid_until,
    billing_starts_on,
        CASE
            WHEN subscription_exempt THEN 'exempt'::text
            WHEN not_yet THEN 'not_due'::text
            WHEN ((subscription_paid_until IS NOT NULL) AND (subscription_paid_until >= CURRENT_DATE)) THEN 'active'::text
            WHEN (subscription_paid_until IS NULL) THEN 'due'::text
            ELSE 'past_due'::text
        END AS billing_status,
        CASE
            WHEN subscription_exempt THEN (0)::numeric
            WHEN not_yet THEN (0)::numeric
            WHEN ((subscription_paid_until IS NOT NULL) AND (subscription_paid_until >= CURRENT_DATE)) THEN (0)::numeric
            ELSE fee
        END AS amount_due_aed,
    fee AS annual_fee_aed,
    free_limit
   FROM st;

CREATE OR REPLACE VIEW public.v_supply_gap AS  WITH pool AS (
         SELECT c.slug,
            c.name,
            c.num,
            count(DISTINCT lc.lead_id) FILTER (WHERE ((l.email IS NOT NULL) AND (l.email <> ''::text) AND (COALESCE(l.banned, false) = false))) AS sendable,
            count(DISTINCT lc.lead_id) FILTER (WHERE (l.invite_status IS NOT NULL)) AS invited,
            count(DISTINCT lc.lead_id) FILTER (WHERE l.claimed) AS claimed,
            count(DISTINCT lc.lead_id) FILTER (WHERE (l.approval_status = 'approved'::text)) AS approved
           FROM ((catalog_supplier_categories c
             LEFT JOIN lead_category lc ON ((lc.slug = c.slug)))
             LEFT JOIN leads l ON (((l.id = lc.lead_id) AND (NOT l.is_demo))))
          GROUP BY c.slug, c.name, c.num
        )
 SELECT slug,
    name,
    num,
    sendable,
    invited,
    claimed,
    approved,
    GREATEST((0)::bigint, (10 - approved)) AS gap_to_target,
    (ceil(((GREATEST((0)::bigint, (10 - approved)))::numeric / 0.05)))::integer AS sendable_needed_at_5pct,
    GREATEST((0)::bigint, ((ceil(((GREATEST((0)::bigint, (10 - approved)))::numeric / 0.05)))::integer - sendable)) AS sendable_shortfall,
        CASE
            WHEN (approved >= 10) THEN 'TARGET MET'::text
            WHEN (sendable = 0) THEN 'NO POOL - must source from scratch'::text
            WHEN (sendable < (ceil(((GREATEST((0)::bigint, (10 - approved)))::numeric / 0.05)))::integer) THEN 'POOL TOO THIN - scrape more'::text
            WHEN (invited = 0) THEN 'READY - not yet invited'::text
            ELSE 'IN PROGRESS'::text
        END AS status
   FROM pool;

CREATE OR REPLACE VIEW public.v_support_case_metrics AS  SELECT date_trunc('day'::text, c.opened_at) AS day,
    c.channel,
    count(*) AS opened,
    count(*) FILTER (WHERE (c.state = 'closed'::text)) AS closed,
    round(((percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((c.first_reply_seconds)::double precision)) / (60)::double precision))::numeric, 1) AS median_first_reply_minutes,
    round((avg((c.fcr)::integer) * (100)::numeric), 1) AS fcr_pct,
    round((avg(((c.reopen_count > 0))::integer) FILTER (WHERE (c.state = 'closed'::text)) * (100)::numeric), 1) AS reopen_pct,
    round(avg(r.csat), 2) AS csat_avg,
    count(r.csat) AS csat_responses,
    round(avg(r.ces), 2) AS ces_avg,
    count(*) FILTER (WHERE (c.case_kind = 'service_recovery'::text)) AS service_recovery_cases
   FROM (support_case c
     LEFT JOIN LATERAL ( SELECT max(f.rating) FILTER (WHERE (f.kind = 'csat'::text)) AS csat,
            max(f.rating) FILTER (WHERE (f.kind = 'ces'::text)) AS ces
           FROM feedback f
          WHERE (f.case_id = c.case_id)) r ON (true))
  GROUP BY (date_trunc('day'::text, c.opened_at)), c.channel;

CREATE OR REPLACE VIEW public.v_support_corpus AS  WITH base AS (
         SELECT 'faq'::text AS src,
            (f.id)::text AS src_id,
            f.question AS title,
            f.answer AS content,
            f.embedding_gte,
            COALESCE(o.is_public, f.public, false) AS is_public,
            f.audience,
            ('FAQ: '::text || f.question) AS citation,
            f.updated_at AS as_of,
            COALESCE(f.language, 'en'::text) AS lang
           FROM (company_faq f
             LEFT JOIN support_public_override o ON (((o.src = 'faq'::text) AND (o.src_id = (f.id)::text))))
          WHERE (f.status = 'approved'::text)
        UNION ALL
         SELECT 'supportkb'::text AS src,
            s.record_id AS src_id,
            s.title,
            s.body AS content,
            NULL::vector(384) AS embedding_gte,
            COALESCE(o.is_public, false) AS is_public,
            'all'::text AS audience,
            ('Support pack: '::text || s.title) AS citation,
            s.imported_at AS as_of,
            COALESCE(s.language, 'en'::text) AS lang
           FROM (support_knowledge s
             LEFT JOIN support_public_override o ON (((o.src = 'supportkb'::text) AND (o.src_id = s.record_id))))
          WHERE s.runtime_index_eligible
        UNION ALL
         SELECT 'ops'::text AS src,
            k.record_id AS src_id,
            k.title,
            k.content,
            k.embedding_gte,
            COALESCE(o.is_public, false) AS is_public,
            'all'::text AS audience,
            ('Operations: '::text || k.title) AS citation,
            NULL::timestamp with time zone AS as_of,
            'en'::text AS lang
           FROM (ops_knowledge k
             LEFT JOIN support_public_override o ON (((o.src = 'ops'::text) AND (o.src_id = k.record_id))))
          WHERE ((COALESCE(k.supersession_state, 'current'::text) = 'current'::text) AND k.runtime_eligible)
        )
 SELECT src,
    src_id,
    title,
    content,
    embedding_gte,
    (is_public AND (src = 'faq'::text) AND (COALESCE(content, ''::text) !~ '[{][{]?[a-zA-Z_]+[}]?[}]'::text) AND (COALESCE(title, ''::text) !~ '[{][{]?[a-zA-Z_]+[}]?[}]'::text) AND (COALESCE(content, ''::text) !~* '(draft, not [a-z-]+ approved|not provider-approved|internal use only)'::text)) AS is_public,
    audience,
    citation,
    as_of,
    lang
   FROM base b;

CREATE OR REPLACE VIEW public.v_support_customer_profile AS  SELECT p.id AS profile_id,
    p.party_kind,
    p.customer_id,
    p.lead_id,
    p.email,
    p.phone_tail,
    p.display_name,
    count(c.case_id) AS cases,
    count(c.case_id) FILTER (WHERE (c.state <> 'closed'::text)) AS open_cases,
    array_agg(c.case_ref ORDER BY c.opened_at DESC) FILTER (WHERE (c.case_id IS NOT NULL)) AS case_refs,
    ( SELECT array_agg(DISTINCT ch.ch) AS array_agg
           FROM support_case c2,
            LATERAL unnest(c2.channels) ch(ch)
          WHERE (c2.customer_profile_id = p.id)) AS channels,
    round(avg(r.csat), 2) AS csat_avg,
    round(avg(r.ces), 2) AS ces_avg,
    max(c.last_activity_at) AS last_activity_at
   FROM ((support_customer_profile p
     LEFT JOIN support_case c ON ((c.customer_profile_id = p.id)))
     LEFT JOIN LATERAL ( SELECT max(f.rating) FILTER (WHERE (f.kind = 'csat'::text)) AS csat,
            max(f.rating) FILTER (WHERE (f.kind = 'ces'::text)) AS ces
           FROM feedback f
          WHERE (f.case_id = c.case_id)) r ON (true))
  GROUP BY p.id;

CREATE OR REPLACE VIEW public.v_test_matrix AS  SELECT agent AS suite,
    count(*) AS runs_14d,
    count(*) FILTER (WHERE (status = 'ok'::text)) AS passed,
    count(*) FILTER (WHERE (status = 'error'::text)) AS failed,
    round(((100.0 * (count(*) FILTER (WHERE (status = 'ok'::text)))::numeric) / (GREATEST(count(*), (1)::bigint))::numeric)) AS pass_pct,
    max(started_at) AS last_run,
        CASE
            WHEN (count(*) FILTER (WHERE (status = 'error'::text)) = 0) THEN 'PASS'::text
            WHEN (count(*) FILTER (WHERE (status = 'ok'::text)) = 0) THEN 'FAIL'::text
            ELSE 'FLAKY'::text
        END AS verdict
   FROM agent_runs r
  WHERE ((started_at > (now() - '14 days'::interval)) AND ((agent ~~* '%test%'::text) OR (agent ~~* '%eval%'::text) OR (agent ~~* '%qa%'::text) OR (agent ~~* '%exam%'::text) OR (agent ~~* '%smoke%'::text) OR (agent ~~* '%drill%'::text) OR (agent ~~* '%canary%'::text) OR (agent ~~* '%health%'::text)))
  GROUP BY agent;

CREATE OR REPLACE VIEW public.v_ui_label_missing AS  SELECT 'action_kind'::text AS domain,
    a.kind AS key,
    count(*) AS rows_in_use
   FROM (agent_actions a
     LEFT JOIN ui_label l ON (((l.domain = 'action_kind'::text) AND (l.key = a.kind))))
  WHERE ((l.key IS NULL) AND (a.kind IS NOT NULL))
  GROUP BY a.kind
UNION ALL
 SELECT 'notification_type'::text AS domain,
    n.type AS key,
    count(*) AS rows_in_use
   FROM (notifications n
     LEFT JOIN ui_label l ON (((l.domain = 'notification_type'::text) AND (l.key = n.type))))
  WHERE ((l.key IS NULL) AND (n.type IS NOT NULL))
  GROUP BY n.type;

CREATE OR REPLACE VIEW public.v_workflow_side_effects_without_executor AS  SELECT w.workflow_key,
    s.step_no,
    s.action_class
   FROM ((workflow w
     JOIN workflow_step s ON ((s.workflow_key = w.workflow_key)))
     LEFT JOIN org_action_executor e ON (((e.action_class = s.action_class) AND e.active)))
  WHERE (w.active AND (s.action_class IS NOT NULL) AND (e.action_class IS NULL));

CREATE OR REPLACE VIEW public.v_workstream_answer AS  SELECT w.id AS workstream_id,
    w.group_id,
    w.trade_key,
    w.active,
    a.id AS answer_id,
    a.field_id,
    a.value,
    a.unit,
    a.scope,
    a.precedence,
    a.source_kind,
    a.confirmed_at,
        CASE
            WHEN (a.scope = 'inquiry_shared'::text) THEN 'shared'::text
            WHEN (EXISTS ( SELECT 1
               FROM inquiry_answer_scope s
              WHERE ((s.answer_id = a.id) AND (s.workstream_id = w.id)))) THEN 'owned'::text
            ELSE 'referenced'::text
        END AS via,
    ((a.value IS NOT NULL) AND (btrim(a.value) <> ''::text) AND (a.precedence <> ALL (ARRAY['model_inference'::answer_precedence, 'unknown'::answer_precedence])) AND ((a.scope = 'inquiry_shared'::text) OR (EXISTS ( SELECT 1
           FROM inquiry_answer_scope s
          WHERE ((s.answer_id = a.id) AND (s.workstream_id = w.id)))))) AS satisfies_mandatory
   FROM (inquiry_workstream w
     JOIN inquiry_answer a ON (((a.group_id = w.group_id) AND (a.superseded_by IS NULL))))
  WHERE ((a.scope = 'inquiry_shared'::text) OR (EXISTS ( SELECT 1
           FROM inquiry_answer_scope s
          WHERE ((s.answer_id = a.id) AND (s.workstream_id = w.id)))) OR (EXISTS ( SELECT 1
           FROM field_definition_reference r
          WHERE ((r.field_id = a.field_id) AND (r.referencing_trade_key = w.trade_key)))));

CREATE OR REPLACE VIEW public.v_workstream_completeness AS  SELECT w.id AS workstream_id,
    w.group_id,
    w.trade_key,
    w.active,
    count(*) FILTER (WHERE r.mandatory) AS required_mandatory,
    count(*) FILTER (WHERE (r.mandatory AND va.satisfies_mandatory)) AS answered_mandatory,
    count(*) FILTER (WHERE (NOT r.mandatory)) AS required_optional,
    count(*) FILTER (WHERE ((NOT r.mandatory) AND va.satisfies_mandatory)) AS answered_optional,
    COALESCE(array_agg(r.field_id ORDER BY r.field_id) FILTER (WHERE (r.mandatory AND (NOT COALESCE(va.satisfies_mandatory, false)))), '{}'::text[]) AS missing_mandatory,
    COALESCE(( SELECT array_agg(DISTINCT vc.field_id) AS array_agg
           FROM v_workstream_conflict vc
          WHERE (vc.workstream_id = w.id)), '{}'::text[]) AS blocked_by
   FROM ((inquiry_workstream w
     LEFT JOIN inquiry_workstream_requirement r ON ((r.workstream_id = w.id)))
     LEFT JOIN v_workstream_answer va ON (((va.workstream_id = w.id) AND (va.field_id = r.field_id))))
  GROUP BY w.id, w.group_id, w.trade_key, w.active;

CREATE OR REPLACE VIEW public.v_workstream_conflict AS  SELECT w.id AS workstream_id,
    w.group_id,
    w.trade_key,
    c.id AS conflict_id,
    c.field_id,
    c.blocking_scope,
    c.opened_at
   FROM ((inquiry_workstream w
     JOIN inquiry_answer_conflict c ON (((c.group_id = w.group_id) AND (c.resolved_at IS NULL))))
     JOIN field_definition fd ON ((fd.field_id = c.field_id)))
  WHERE ((fd.scope = 'shared'::text) OR ((fd.scope = 'trade_specific'::text) AND (fd.trade_key = w.trade_key)) OR ((fd.scope = 'trade_subset'::text) AND (EXISTS ( SELECT 1
           FROM field_definition_trade t
          WHERE ((t.field_id = fd.field_id) AND (t.trade_key = w.trade_key))))));

CREATE OR REPLACE VIEW public.v_workstream_dispatch AS  SELECT workstream_id,
    group_id,
    trade_key,
    active,
    required_mandatory,
    answered_mandatory,
    missing_mandatory,
    blocked_by,
    (cardinality(missing_mandatory) = 0) AS mandatory_complete,
    (cardinality(blocked_by) = 0) AS no_unresolved_conflict,
    COALESCE(( SELECT jsonb_object_agg(gr.gate_key, COALESCE(( SELECT (g.state)::text AS state
                   FROM inquiry_gate g
                  WHERE ((g.workstream_id = c.workstream_id) AND (g.gate_key = gr.gate_key))), 'not_evaluated'::text)) AS jsonb_object_agg
           FROM inquiry_gate_required gr
          WHERE (gr.level = 'workstream'::text)), '{}'::jsonb) AS gate_states,
    (NOT (EXISTS ( SELECT 1
           FROM inquiry_gate_required gr
          WHERE ((gr.level = 'workstream'::text) AND (NOT (EXISTS ( SELECT 1
                   FROM inquiry_gate g
                  WHERE ((g.workstream_id = c.workstream_id) AND (g.gate_key = gr.gate_key) AND fn_gate_state_satisfies(g.state))))))))) AS gates_passed,
    (active AND (cardinality(missing_mandatory) = 0) AND (cardinality(blocked_by) = 0) AND (NOT (EXISTS ( SELECT 1
           FROM inquiry_gate_required gr
          WHERE ((gr.level = 'workstream'::text) AND (NOT (EXISTS ( SELECT 1
                   FROM inquiry_gate g
                  WHERE ((g.workstream_id = c.workstream_id) AND (g.gate_key = gr.gate_key) AND fn_gate_state_satisfies(g.state)))))))))) AS dispatch_eligible
   FROM v_workstream_completeness c;

