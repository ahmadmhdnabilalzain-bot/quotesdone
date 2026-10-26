# QuotesDone — project export

Exported 2026-07-29 16:26 UTC from the live production system.

Everything here was read directly from what is actually running — not from a repository copy — so it is production truth at the moment of export.

## What is in this export

| Part | Items | Size | Folder |
|---|---|---|---|
| Backend functions (the code that runs the marketplace) | 189 | 1872 KB | `functions/` |
| Database change history (every migration ever applied) | 544 | 2062 KB | `migrations/` |
| Database structure, logic, security and schedules | 4 documents | 1363 KB | `database/` |

## What is NOT in this export

The **website front end** (the Next.js application: pages, components, translations, styling and configuration) is not here. That code lives only in the GitHub repository `ahmadmhdnabilalzain-bot/quotesdone` and on your own PC — neither of which this scheduled cloud session can reach. Everything else that makes QuotesDone work is included.

## Folder: `database/`

- `schema-tables-and-views.md` — every table and view with all their columns, types, defaults (325 tables, 110 views, 4,046 columns).
- `database-functions.md` — the full source of all 599 database functions and procedures.
- `views.md` — the full SQL behind all 110 views.
- `triggers-policies-indexes-cron.md` — 106 triggers, 3 security policies, 608 indexes and 146 scheduled jobs.

## Folder: `migrations/`

Every database change ever applied, oldest to newest, one file each: `20260606224832_create_leads_table` … `20260729141623_dropbox_category_folder_from_catalog_86`. File names are the timestamp of the change plus its name, so they sort chronologically.

## Folder: `functions/`

One file per backend function, named after the function. Each contains the complete source code exactly as deployed.

| Function | Version | Last deployed (UTC) | Export size |
|---|---|---|---|
| `about` | v2 | 2026-06-24 13:53 | 1 KB |
| `agent_act` | v22 | 2026-07-28 21:05 | 32 KB |
| `agent_autogen` | v8 | 2026-07-28 22:58 | 14 KB |
| `agent_brain` | v22 | 2026-07-29 12:16 | 23 KB |
| `agent_learnings_report` | v3 | 2026-07-18 20:06 | 9 KB |
| `agents` | v26 | 2026-07-28 21:18 | 52 KB |
| `ai_gateway` | v9 | 2026-07-29 12:18 | 25 KB |
| `ai_health` | v5 | 2026-07-27 11:32 | 8 KB |
| `alert_founder` | v4 | 2026-07-27 11:34 | 6 KB |
| `analytics_recommend` | v4 | 2026-07-28 21:07 | 10 KB |
| `apify_scrape` | v3 | 2026-07-27 11:41 | 7 KB |
| `archive_rfq` | v10 | 2026-07-28 21:08 | 20 KB |
| `asset_delete` | v3 | 2026-07-27 11:37 | 2 KB |
| `assets_ingest` | v4 | 2026-07-27 11:33 | 8 KB |
| `attach_photos` | v3 | 2026-07-01 12:43 | 2 KB |
| `auth_api` | v7 | 2026-07-27 10:51 | 1 KB |
| `backup` | v5 | 2026-07-27 11:30 | 5 KB |
| `blog_weekly` | v9 | 2026-07-28 21:10 | 11 KB |
| `boost_recommend` | v4 | 2026-07-28 21:11 | 11 KB |
| `brand_upload` | v3 | 2026-07-24 05:15 | 0 KB |
| `cad_convert` | v6 | 2026-07-27 11:38 | 5 KB |
| `canon_eval` | v5 | 2026-07-28 21:12 | 11 KB |
| `capability_agent` | v5 | 2026-07-28 23:20 | 19 KB |
| `category_provision` | v8 | 2026-07-28 21:13 | 13 KB |
| `category_reqs` | v7 | 2026-07-28 21:14 | 9 KB |
| `claim_lookup` | v3 | 2026-07-19 00:24 | 6 KB |
| `collections_legal` | v4 | 2026-07-27 11:31 | 15 KB |
| `compliance_archive` | v5 | 2026-07-03 15:41 | 14 KB |
| `contact_submit` | v3 | 2026-07-27 11:01 | 4 KB |
| `content_revise` | v4 | 2026-07-28 21:14 | 9 KB |
| `copilot` | v9 | 2026-07-28 21:02 | 12 KB |
| `cos_execute` | v11 | 2026-07-29 12:09 | 22 KB |
| `cost_snapshot` | v5 | 2026-07-29 11:02 | 13 KB |
| `customer_api` | v40 | 2026-07-29 12:58 | 64 KB |
| `customer_portal` | v3 | 2026-07-13 21:14 | 3 KB |
| `deploy_next_preview` | v5 | 2026-07-27 13:14 | 7 KB |
| `dept_learn` | v5 | 2026-07-28 21:24 | 11 KB |
| `dept_plan` | v7 | 2026-07-28 21:25 | 16 KB |
| `designer` | v4 | 2026-07-27 11:35 | 6 KB |
| `dev_login` | v5 | 2026-07-13 21:05 | 0 KB |
| `dir_ingest` | v3 | 2026-07-19 01:08 | 4 KB |
| `dispatch_inquiry` | v7 | 2026-07-28 20:25 | 16 KB |
| `doc_extract` | v9 | 2026-07-28 23:28 | 16 KB |
| `doc_reminder` | v5 | 2026-07-29 14:18 | 9 KB |
| `doc_render` | v15 | 2026-07-28 21:07 | 16 KB |
| `dr_drill` | v5 | 2026-07-27 11:29 | 7 KB |
| `drawing_boq` | v12 | 2026-07-28 23:22 | 8 KB |
| `drawing_redact` | v9 | 2026-07-28 23:21 | 8 KB |
| `dropbox_backup` | v8 | 2026-07-27 11:33 | 19 KB |
| `dropbox_oauth` | v3 | 2026-07-09 12:00 | 8 KB |
| `dropbox_sync` | v6 | 2026-07-27 11:40 | 9 KB |
| `ea_meeting_summary` | v10 | 2026-07-28 21:26 | 9 KB |
| `email_cron` | v4 | 2026-07-27 11:36 | 5 KB |
| `email_fix` | v5 | 2026-06-10 13:07 | 2 KB |
| `email_triage` | v8 | 2026-07-28 21:27 | 10 KB |
| `embed_leads` | v7 | 2026-07-27 11:35 | 6 KB |
| `enrich_capability` | v10 | 2026-07-28 21:28 | 14 KB |
| `exec_agents` | v8 | 2026-07-28 21:29 | 11 KB |
| `export_all_knowledge` | v4 | 2026-07-27 11:45 | 4 KB |
| `export_cat_knowledge` | v5 | 2026-07-27 11:38 | 3 KB |
| `export_leads_csv` | v3 | 2026-07-07 14:18 | 2 KB |
| `extract_text` | v4 | 2026-07-28 23:12 | 4 KB |
| `faq` | v6 | 2026-07-11 13:11 | 9 KB |
| `finance_doc` | v3 | 2026-07-28 22:55 | 5 KB |
| `finance_ingest` | v3 | 2026-07-22 14:48 | 9 KB |
| `gen_category_knowledge` | v11 | 2026-07-28 21:30 | 13 KB |
| `gen_category_personas` | v12 | 2026-07-28 21:31 | 11 KB |
| `github_sync` | v4 | 2026-07-27 11:32 | 5 KB |
| `home` | v7 | 2026-06-09 15:42 | 1 KB |
| `home-ar` | v2 | 2026-06-26 08:43 | 1 KB |
| `i18n_get` | v3 | 2026-07-27 11:41 | 1 KB |
| `inbound_email` | v5 | 2026-06-26 21:00 | 9 KB |
| `inquiry_ai` | v20 | 2026-07-28 23:19 | 21 KB |
| `inquiry_dedup_check` | v2 | 2026-06-30 17:28 | 2 KB |
| `inquiry_intake` | v14 | 2026-07-29 13:27 | 31 KB |
| `inquiry_parse` | v4 | 2026-07-28 22:54 | 10 KB |
| `intent_router` | v4 | 2026-07-28 21:02 | 11 KB |
| `kb_autofill_gaps` | v4 | 2026-07-27 11:36 | 5 KB |
| `kb_deepen` | v9 | 2026-07-28 23:24 | 16 KB |
| `kb_embed` | v7 | 2026-07-28 19:58 | 7 KB |
| `kb_fill_gap` | v4 | 2026-07-28 22:53 | 5 KB |
| `kb_import` | v4 | 2026-07-27 11:38 | 4 KB |
| `kb_ingest` | v6 | 2026-07-27 11:47 | 9 KB |
| `kb_ingest_text` | v2 | 2026-07-10 12:16 | 3 KB |
| `kb_research_test` | v5 | 2026-07-29 00:03 | 13 KB |
| `kb_retrieve` | v3 | 2026-07-22 15:07 | 1 KB |
| `kb_search` | v4 | 2026-07-27 11:39 | 4 KB |
| `knowledge_exam` | v7 | 2026-07-28 21:05 | 19 KB |
| `kyc` | v8 | 2026-07-28 12:42 | 20 KB |
| `learn_gaps` | v12 | 2026-07-28 21:06 | 17 KB |
| `legal` | v13 | 2026-07-11 13:09 | 10 KB |
| `legal_ingest` | v3 | 2026-07-27 11:37 | 2 KB |
| `legal_review` | v11 | 2026-07-28 22:55 | 8 KB |
| `licence_reminder` | v3 | 2026-07-22 15:07 | 1 KB |
| `license_extract` | v6 | 2026-07-28 23:15 | 11 KB |
| `login_otp` | v8 | 2026-07-27 11:04 | 18 KB |
| `make_pdf` | v7 | 2026-07-09 11:46 | 5 KB |
| `make_xlsx` | v2 | 2026-06-26 09:00 | 3 KB |
| `marketing_draft` | v7 | 2026-07-28 21:07 | 12 KB |
| `marketing_image` | v3 | 2026-07-24 04:35 | 7 KB |
| `match` | v8 | 2026-07-19 00:02 | 10 KB |
| `match_eval` | v4 | 2026-07-28 12:40 | 11 KB |
| `messages_api` | v10 | 2026-07-28 21:08 | 22 KB |
| `meta_ads` | v4 | 2026-07-27 11:31 | 7 KB |
| `meta_sync` | v5 | 2026-07-27 11:49 | 8 KB |
| `mobile_otp` | v5 | 2026-07-27 11:32 | 7 KB |
| `money_tests` | v8 | 2026-07-27 11:29 | 8 KB |
| `orchestrate` | v5 | 2026-07-22 14:38 | 1 KB |
| `os_api` | v32 | 2026-07-28 12:41 | 21 KB |
| `os_automation` | v2 | 2026-07-24 17:37 | 3 KB |
| `os_catalog` | v2 | 2026-07-24 22:01 | 4 KB |
| `os_health` | v2 | 2026-07-25 00:33 | 2 KB |
| `os_incidents` | v2 | 2026-07-25 09:43 | 3 KB |
| `os_ops` | v13 | 2026-07-28 12:44 | 19 KB |
| `os_pages` | v9 | 2026-07-28 22:56 | 14 KB |
| `os_settings` | v2 | 2026-07-24 17:20 | 3 KB |
| `pdf_native` | v16 | 2026-07-21 10:27 | 22 KB |
| `pdpl_erase` | v3 | 2026-07-27 11:28 | 5 KB |
| `pdpl_request` | v2 | 2026-06-29 21:51 | 3 KB |
| `pending_digest` | v4 | 2026-07-27 11:40 | 3 KB |
| `portal` | v7 | 2026-06-08 20:51 | 1 KB |
| `postiz_publish` | v7 | 2026-07-27 11:38 | 8 KB |
| `profile_ai` | v7 | 2026-07-28 23:17 | 7 KB |
| `project_api` | v3 | 2026-07-06 01:15 | 8 KB |
| `project_consultant` | v7 | 2026-07-28 21:09 | 12 KB |
| `prompt_gate` | v8 | 2026-07-28 21:10 | 12 KB |
| `prompt_improve` | v5 | 2026-07-28 22:52 | 5 KB |
| `public_stats` | v3 | 2026-06-26 08:16 | 1 KB |
| `push_src_to_github` | v2 | 2026-07-28 10:28 | 7 KB |
| `put_src` | v3 | 2026-07-27 11:04 | 3 KB |
| `qa_api` | v2 | 2026-06-20 12:02 | 7 KB |
| `qa_login` | v3 | 2026-07-13 21:07 | 0 KB |
| `qa_mint` | v4 | 2026-07-27 11:42 | 2 KB |
| `qa_suite` | v11 | 2026-07-28 12:43 | 10 KB |
| `quote_compare` | v23 | 2026-07-28 22:59 | 26 KB |
| `quote_extract` | v8 | 2026-07-28 23:16 | 11 KB |
| `quote_pdf` | v3 | 2026-07-06 19:00 | 11 KB |
| `quote_quality` | v2 | 2026-07-06 09:52 | 2 KB |
| `quote_review` | v5 | 2026-07-28 22:49 | 10 KB |
| `rate_dims` | v2 | 2026-07-06 01:42 | 3 KB |
| `reflect` | v9 | 2026-07-28 21:11 | 9 KB |
| `refund_flow` | v4 | 2026-07-23 20:52 | 5 KB |
| `refunds_api` | v6 | 2026-07-27 10:15 | 16 KB |
| `reg_fetch` | v3 | 2026-07-27 11:42 | 5 KB |
| `report_body` | v3 | 2026-07-28 15:15 | 2 KB |
| `resend_inbound` | v17 | 2026-07-28 22:59 | 29 KB |
| `resend_webhook` | v6 | 2026-07-23 22:04 | 8 KB |
| `resilience_ping` | v2 | 2026-07-24 01:46 | 4 KB |
| `retention_purge` | v4 | 2026-07-27 11:29 | 6 KB |
| `reveal_invoice` | v3 | 2026-07-18 19:14 | 7 KB |
| `rfq_flag` | v2 | 2026-07-13 16:39 | 4 KB |
| `role_guard` | v3 | 2026-07-19 00:26 | 6 KB |
| `route_inquiry` | v12 | 2026-07-28 22:51 | 29 KB |
| `secretary_act` | v13 | 2026-07-28 23:27 | 33 KB |
| `send_outbox` | v22 | 2026-07-28 12:42 | 16 KB |
| `send_sms` | v5 | 2026-07-27 11:29 | 6 KB |
| `send_whatsapp` | v8 | 2026-07-27 11:29 | 11 KB |
| `seo_gen` | v6 | 2026-07-28 22:52 | 4 KB |
| `site_assistant` | v13 | 2026-07-28 21:56 | 18 KB |
| `site_deploy` | v24 | 2026-07-27 11:35 | 35 KB |
| `social_stage` | v8 | 2026-07-29 13:28 | 14 KB |
| `src_io` | v3 | 2026-07-13 15:36 | 0 KB |
| `stripe_checkout` | v5 | 2026-07-27 10:15 | 7 KB |
| `stripe_confirm` | v4 | 2026-07-23 20:48 | 7 KB |
| `stripe_setup` | v2 | 2026-07-02 18:05 | 4 KB |
| `stripe_setup_page` | v2 | 2026-07-02 18:11 | 4 KB |
| `stripe_webhook` | v8 | 2026-07-24 16:33 | 15 KB |
| `sup_dob` | v2 | 2026-07-12 12:36 | 1 KB |
| `supplier_ack` | v2 | 2026-07-03 16:54 | 4 KB |
| `supplier_api` | v31 | 2026-07-29 14:21 | 60 KB |
| `supplier_pay` | v3 | 2026-07-19 01:31 | 9 KB |
| `supplier_portal` | v10 | 2026-07-27 10:48 | 24 KB |
| `supplier_review` | v4 | 2026-07-28 22:52 | 4 KB |
| `support_ai` | v7 | 2026-07-22 15:07 | 1 KB |
| `sync_src_from_github` | v3 | 2026-07-28 07:51 | 8 KB |
| `transcribe` | v6 | 2026-07-28 23:13 | 4 KB |
| `translate_html` | v5 | 2026-07-28 22:53 | 3 KB |
| `translate_page` | v9 | 2026-07-29 02:05 | 7 KB |
| `unsubscribe` | v3 | 2026-07-27 11:01 | 7 KB |
| `uptime_check` | v7 | 2026-07-27 11:31 | 8 KB |
| `vercel_status` | v24 | 2026-07-27 11:42 | 2 KB |
| `voice_otp` | v5 | 2026-07-18 23:53 | 2 KB |
| `voice_otp_capture` | v4 | 2026-07-18 23:54 | 2 KB |
| `vt_scan` | v4 | 2026-07-27 11:46 | 5 KB |
| `wa_inbound` | v13 | 2026-07-28 22:00 | 32 KB |
| `wa_optin_set` | v3 | 2026-07-27 11:00 | 3 KB |
| `wa_template_setup` | v5 | 2026-07-27 11:31 | 7 KB |
| `wa_templates_watch` | v4 | 2026-07-18 20:08 | 7 KB |
| `yello_scrape` | v2 | 2026-06-21 00:42 | 10 KB |

## How this was verified

Every one of the 189 function files was checked automatically after writing for: the file existing at all, containing real source code rather than a summary or placeholder, having no truncation marker, being properly line-broken, and closing its code block correctly. Twenty-one files failed a check on the first pass and were re-exported and re-checked until clean.
