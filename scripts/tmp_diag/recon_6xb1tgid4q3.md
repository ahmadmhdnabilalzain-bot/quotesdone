# 1. `public.phase_d_outbound_door` — ALL ROWS (4)

Columns: `relation, trigger_name, function_name, endpoint, disposition, guard_column, suppression_sql, unreachable_because_column, guard_condition, note, registered_at`. PK `(relation, trigger_name)`. CHECK `disposition IN ('SUPPRESSED_BY_ITS_OWN_GUARD','NOT_REACHED_BY_ANY_PHASE_D_WRITE_MAP')` plus an evidence CHECK forcing `guard_column+suppression_sql` non-null for the first and `unreachable_because_column` non-null for the second. Grants: postgres full; service_role all except TRUNCATE (revoked by `scripts/sql/phase_d_d24_a_new_enforcing_table_with_no_truncate_guard.sql:46`). **No triggers on the table itself** (measured: `pg_trigger` where `tgrelid='public.phase_d_outbound_door'::regclass and not tgisinternal` → 0 rows).

| relation | trigger_name | function_name | endpoint | disposition | guard_column | suppression_sql | unreachable_because_column |
|---|---|---|---|---|---|---|---|
| public.customers | trg_sign_customer | qd_sign_customer | compliance_archive | NOT_REACHED_BY_ANY_PHASE_D_WRITE_MAP | NULL | NULL | email_verified |
| public.inquiries | autodispatch_inquiry | trg_autodispatch_inquiry | dispatch_inquiry | SUPPRESSED_BY_ITS_OWN_GUARD | routing | `jsonb_build_object('dispatched_at', now(), 'dispatched_by', 'phase_d_test_context', 'phase_d_outbound_suppressed', true)` | NULL |
| public.leads | enrich_capability_on_approve | trg_enrich_capability | enrich_capability | SUPPRESSED_BY_ITS_OWN_GUARD | capability_enriched_at | `to_jsonb(now())` | NULL |
| public.leads | trg_sign_supplier | qd_sign_supplier | compliance_archive | NOT_REACHED_BY_ANY_PHASE_D_WRITE_MAP | NULL | NULL | owner_email_verified |

guard_condition / note / registered_at (all four registered `2026-08-18 22:00:01.130319+00`):
- customers/trg_sign_customer: `AFTER UPDATE ... WHEN (new.email_verified is true and old.email_verified is distinct from new.email_verified and new.signed_terms_url is null)` — "MEASURED SILENT…the customer_account write map does not declare that column".
- inquiries/autodispatch_inquiry: `AFTER INSERT OR UPDATE OF rfq_ready; fires when rfq_ready is true and routing->>'dispatched_at' is null` — "MEASURED FIRING: this door produced the POST to dispatch_inquiry".
- leads/enrich_capability_on_approve: `AFTER INSERT OR UPDATE OF approval_status; fires when approval_status='approved' and capability_enriched_at is null` — "MEASURED FIRING".
- leads/trg_sign_supplier: `AFTER UPDATE ... WHEN (new.owner_email_verified is true and old.owner_email_verified is distinct from new.owner_email_verified and new.signed_terms_url is null and new.claimed_by is not null)` — "MEASURED SILENT…note that fn_leads_derive_owner_email_verified can move that column from an email write".

# 2. Where suppression is APPLIED at runtime

Exactly **two** live routines reference the table (`pg_proc.prosrc like '%phase_d_outbound_door%'`): `public.fn_phase_d_object_write(jsonb)` (28375 chars, SECURITY DEFINER, VOLATILE, owner postgres) and `public.fn_phase_d_outbound_state()` (read-only board). **Only `fn_phase_d_object_write` applies it.**

Committed source: `C:\Users\Opera\quotesdone\scripts\sql\phase_d_k05_a_gate_that_refused_a_row_and_told_nobody.sql:233-253` (newest re-emit of the whole routine; k02/k04/k05 all committed 2026-08-23T22:00:44+04:00, k05 last). Live body, verbatim:

```plpgsql
  v_testctx    boolean := public.fn_phase_d_fixture_context() is not null;   -- declare block
...
    if v_testctx then
      for v_door in
        select d.guard_column, d.suppression_sql
          from public.phase_d_outbound_door d
         where d.relation = wm.target_relation
           and d.disposition = 'SUPPRESSED_BY_ITS_OWN_GUARD'
      loop
        execute format('select %s', v_door.suppression_sql) into v_door_val;
        v_supplied := v_supplied || jsonb_build_object(v_door.guard_column, v_door_val);
      end loop;
    end if;
```
Not defeasible by the caller (D19): it overwrites whatever the payload supplied.

**The backstop (the part that catches unregistered doors), same routine:**
```plpgsql
    if v_testctx then
      select coalesce(max(id),0) into v_net_max from net.http_request_queue;   -- watermark, immediately pre-write
    end if;
...
    if v_testctx then
      select r.n, r.urls into v_net_new, v_net_urls
        from public.fn_phase_d_outbound_requests_by_this_transaction(v_net_max) r;
      if coalesce(v_net_new,0) > 0 then
        raise exception 'fn_phase_d_object_write: writing % to % enqueued % outbound HTTP request(s): %. A Phase D test write may not leave an outbound request behind it. (pd_object_outbound_request_produced)',
          v_object, wm.target_relation, v_net_new, v_net_urls using errcode = '23514',
          hint = 'A trigger on this relation calls net.http_post. Register it in public.phase_d_outbound_door ...';
      end if;
    end if;
```

Attribution helper (J04 fix — xmin, not a watermark delta):
```plpgsql
CREATE OR REPLACE FUNCTION public.fn_phase_d_outbound_requests_by_this_transaction(p_after bigint)
 RETURNS TABLE(n integer, urls text) LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'public','pg_temp' AS $function$
declare
  v_top8  bigint := pg_current_xact_id()::text::bigint;
  v_top32 bigint := mod(pg_current_xact_id()::text::bigint, 4294967296);
begin
  return query
  select count(*)::int, string_agg(distinct q.method || ' ' || q.url, ', ')
    from net.http_request_queue q
   where q.id > p_after
     and q.xmin::text::bigint >= v_top32
     and pg_xact_status(((v_top8 - v_top32) + q.xmin::text::bigint)::text::xid8) = 'in progress';
end $function$
```

Gate on "test context": `public.fn_phase_d_fixture_context()` (STABLE SECURITY DEFINER) reads GUC `app.phase_d_fixture_context` = `<id>.<hmac>`, requires a `phase_d_test_context_grant` row whose `txid = txid_current()`, and verifies `extensions.hmac(txid:operation_key:fixture_run_id, phase_d_fixture_secret.secret, 'sha256')`. **Outside a fixture transaction the suppression loop does not run at all** — real writes POST normally.

Board `public.fn_phase_d_outbound_state()` = 9 checks, all GREEN right now (4/4 registered, 2/2 guard columns exist and are in the write map, 2/2 suppressions are function calls, 2/2 unreachable reasons name a column the triggerdef mentions, 0 reachable-through-map, writer backstop present, fixture scenario aborts).

**DEFECT FOUND — the board's scan is direct-only.** `fn_phase_d_outbound_state` builds `scanned` from `p.prosrc ~* 'net\.http_(post|get)'` on the **trigger function itself**. A trigger whose function calls a *helper* that POSTs is invisible to it. Estate-wide scan of all 345 public triggers with transitive reachability to `net.http_post(`/`net.http_get(` returns 5 doors; 4 registered, and:

```
NOT_REGISTERED  public.leads  trg_self_reg_category  trg_self_reg_category -> fn_provision_category_call
```
```plpgsql
CREATE TRIGGER trg_self_reg_category AFTER INSERT OR UPDATE OF categories, source ON public.leads
  FOR EACH ROW EXECUTE FUNCTION trg_self_reg_category()
-- body: if NEW.source='self_registered' and trim(NEW.categories)<>''
--        and not exists (select 1 from category_agents where active and slug=NEW.categories)
--        and (TG_OP='INSERT' or NEW.categories is distinct from OLD.categories)
--       then perform public.fn_provision_category_call(NEW.categories, NEW.id, NEW.services);
-- fn_provision_category_call: net.http_post(url := '.../functions/v1/category_provision', body := {__secret, raw_category, lead_id, hint_services})
```
Reachability from a Phase D fixture: the `supplier_account` write map declares only `email, verified, company_name, approval_status(state), capability_enriched_at` — **not `source` or `categories`** — so no Phase D write can arm it today, and the writer's own `net.http_request_queue` count would abort the transaction if it ever did. It is nevertheless an unregistered door that the green board does not count in its denominator.

# 3. FULL TRIGGER CHAIN MAP

Every trigger on the requested tables (`pg_get_triggerdef`, `tgisinternal=false`, schema public). All `tgenabled='O'`. Tables with **zero** triggers: `public.doc_backups`, `public.workflow_run`, `public.event_delivery`. There is no table literally named `outbox`; the real name is **`public.phase_c_event_outbox`**.

Write targets below come from static analysis of `pg_proc.prosrc` (`insert into` / `update … set` / `delete from`), depth-limited; conditional branches are not evaluated.

### public.customers
| trigger | timing/events | WHEN | function |
|---|---|---|---|
| trg_block_disposable_customers | BEFORE INSERT ROW | — | block_disposable_signup |
| trg_norm_customer_ver | BEFORE INSERT OR UPDATE ROW | — | qd_norm_customer_ver |
| trg_emit_customer_registered | AFTER INSERT ROW | — | fn_emit_customer_registered |
| trg_sign_customer | AFTER UPDATE ROW | `new.email_verified IS TRUE AND old.email_verified IS DISTINCT FROM new.email_verified AND new.signed_terms_url IS NULL` | qd_sign_customer |
| z00_kernel_truncate_guard | BEFORE TRUNCATE STATEMENT | — | fn_kernel_truncate_guard |

```
customers INSERT -> fn_emit_customer_registered -> fn_emit -> INSERT company_event -> [see company_event chain]
customers UPDATE email_verified F->T -> qd_sign_customer -> net.http_post compliance_archive   [DOOR, unreachable via write map]
customers TRUNCATE -> fn_kernel_truncate_guard -> fn_kernel_record_maintenance_write -> INSERT kernel_maintenance_write
block_disposable_signup / qd_norm_customer_ver: no table writes (BEFORE-row shaping / refusal)
```

### public.leads
| trigger | timing/events | WHEN | function |
|---|---|---|---|
| trg_leads_a_licence_gate | BEFORE INSERT OR UPDATE OF license_doc_path, trade_license_no, license_expiry | — | fn_leads_licence_gate_rerun |
| trg_assign_founding_rank | BEFORE INSERT OR UPDATE | — | fn_assign_founding_rank |
| trg_block_disposable_leads | BEFORE INSERT | — | block_disposable_signup |
| trg_bz_supplier_registration_state | BEFORE INSERT OR UPDATE | — | fn_derive_supplier_registration_state |
| trg_leads_derive_owner_email_verified | BEFORE INSERT OR UPDATE OF claimed_by | — | fn_leads_derive_owner_email_verified |
| trg_leads_exception_invariant | BEFORE INSERT OR UPDATE | — | fn_leads_exception_invariant |
| trg_leads_lifecycle_stage | BEFORE INSERT OR UPDATE OF claimed, signed, registration_submitted_at, claimed_by, approval_status, registration_status, portal_updated_at, accepted_terms_at, owner_email_verified, invite_status, invited_at, contacted, created_at, lifecycle_stage | — | trg_leads_lifecycle_stage |
| trg_norm_supplier_ver | BEFORE INSERT OR UPDATE | — | qd_norm_supplier_ver |
| supplier_capability | BEFORE INSERT OR UPDATE | — | trg_supplier_capability |
| enrich_capability_on_approve | AFTER INSERT OR UPDATE OF approval_status | — | trg_enrich_capability |
| reg_lead_docs | AFTER INSERT OR UPDATE OF license_doc_path, company_profile_doc_path, egr_doc_path, catalog_doc_paths | — | trg_reg_lead_docs |
| trg_emit_supplier_applied | AFTER UPDATE | — | fn_emit_supplier_applied |
| trg_emit_supplier_approved | AFTER INSERT OR UPDATE OF approval_status | — | fn_emit_supplier_approved |
| trg_self_reg_category | AFTER INSERT OR UPDATE OF categories, source | — | trg_self_reg_category |
| trg_sign_supplier | AFTER UPDATE | `new.owner_email_verified IS TRUE AND old.owner_email_verified IS DISTINCT FROM new.owner_email_verified AND new.signed_terms_url IS NULL AND new.claimed_by IS NOT NULL` | qd_sign_supplier |
| z95_lead_dob_to_kernel | AFTER UPDATE OF owner_dob | `old.owner_dob IS NULL AND new.owner_dob IS NOT NULL` | trg_lead_dob_to_kernel |
| z00_kernel_truncate_guard | BEFORE TRUNCATE STATEMENT | — | fn_kernel_truncate_guard |

```
leads UPDATE approval_status='approved' -> trg_enrich_capability -> net.http_post enrich_capability   [DOOR, SUPPRESSED via capability_enriched_at]
leads UPDATE claimed_by -> fn_leads_derive_owner_email_verified (BEFORE, sets owner_email_verified)
     -> AFTER UPDATE fires trg_sign_supplier -> net.http_post compliance_archive                       [DOOR, registered "unreachable"; this is the sibling path the note names]
leads INSERT/UPDATE license_doc_path|company_profile_doc_path|egr_doc_path|catalog_doc_paths
     -> trg_reg_lead_docs -> fn_register_document -> INSERT documents (on conflict (bucket,path) do nothing)
     -> documents AFTER INSERT -> z95_document_to_kernel  [only if ref_table='inquiries'; lead docs use ref_table='leads' so it returns NEW]
     -> documents AFTER INSERT OR UPDATE OF extracted -> trg_version_document -> INSERT doc_versions
leads INSERT/UPDATE categories|source (source='self_registered')
     -> trg_self_reg_category -> fn_provision_category_call -> net.http_post /category_provision       [UNREGISTERED DOOR]
leads UPDATE (any) -> fn_emit_supplier_applied -> INSERT company_event -> [company_event chain]
leads INSERT/UPDATE approval_status -> fn_emit_supplier_approved -> fn_emit -> INSERT company_event -> [company_event chain]
leads UPDATE owner_dob NULL->NOT NULL -> trg_lead_dob_to_kernel -> fn_kernel_source_emit('edge:sup_dob')
     -> class B EXISTING_WORKFLOW_SIGNAL, W10, ACTIVE -> fn_kernel_signal_submit
        -> INSERT/UPDATE kernel_signal_inbox -> (fn_kernel_step_complete | fn_kernel_intake_execution | fn_kernel_review_decide | fn_kernel_cancel)
           -> phase_c_handoff_run, phase_c_step_completion, phase_c_trace, phase_c_workflow_run, phase_c_workflow_step_run, phase_c_task
     on kernel fault: INSERT kernel_adapter_failure and returns ok:false (business row NOT blocked);
     23503/42501/22023 are RE-RAISED (an unregistered source key aborts the write)
leads TRUNCATE -> fn_kernel_truncate_guard -> INSERT kernel_maintenance_write
[NOT a trigger] leads rows with approved_at|registration_submitted_at|signed_terms_path|company_profile_doc_path|license_doc_path|claimed
     -> cron 88 dropbox_backup_scan (*/15) -> POST /functions/v1/dropbox_backup -> rpc fn_enqueue_doc_backups
     -> INSERT doc_backups (on conflict (dedupe_key) do nothing) -> same edge fn processes status in ('pending','error') and attempts<5
     -> uploads to Dropbox. THIS OUTLIVES THE FIXTURE TRANSACTION AND IS NOT COVERED BY THE RESIDUE FUNCTION.
```

### public.inquiries
| trigger | timing/events | WHEN | function |
|---|---|---|---|
| block_banned_inquiry | BEFORE INSERT | — | trg_block_banned_inquiry |
| enrich_inquiry | BEFORE INSERT | — | trg_inquiry_enrich |
| rfq_complete | BEFORE INSERT OR UPDATE | — | trg_rfq_complete |
| trg_mask_inquiry_contact | BEFORE INSERT OR UPDATE | — | scrub_inquiry_contacts |
| autodispatch_inquiry | AFTER INSERT OR UPDATE OF rfq_ready | — | trg_autodispatch_inquiry |
| customer_abandon_ban | AFTER UPDATE | — | trg_customer_abandon_ban |
| learn_customer_preference | AFTER INSERT | — | trg_learn_customer_preference |
| reg_inquiry_doc | AFTER INSERT OR UPDATE OF drawing_file_path | — | trg_reg_inquiry_doc |
| trg_approval_raise_on_award | AFTER UPDATE OF hired_supplier_id | `new.hired_supplier_id IS NOT NULL AND new.hired_supplier_id IS DISTINCT FROM old.hired_supplier_id` | fn_approval_raise_on_award |
| trg_emit_rfq_classified | AFTER INSERT OR UPDATE OF category | — | fn_emit_rfq_classified |
| trg_event_inquiry | AFTER INSERT | — | fn_emit_event('inquiry','rfq.created') |
| trg_inquiry_received_a | AFTER INSERT | — | trg_inquiry_received |
| version_rfq | AFTER INSERT OR UPDATE | — | trg_version_rfq |
| z00_kernel_truncate_guard | BEFORE TRUNCATE STATEMENT | — | fn_kernel_truncate_guard |

```
inquiries INSERT / UPDATE rfq_ready=true & routing->>'dispatched_at' is null
     -> trg_autodispatch_inquiry -> net.http_post dispatch_inquiry                                     [DOOR, SUPPRESSED via routing]
inquiries BEFORE INSERT/UPDATE -> scrub_inquiry_contacts -> INSERT founder_alerts
inquiries AFTER INSERT -> trg_inquiry_received -> INSERT notifications ('inquiry_received', queued)
                                              -> fn_kernel_source_emit('dbtrigger:public.inquiries:trg_inquiry_received_a')
                                                 = class A NEW_WORK_REQUEST, W05, ACTIVE
                                                 -> fn_kernel_trigger_submit -> INSERT/UPDATE kernel_trigger_inbox
                                                    -> fn_kernel_workflow_start -> INSERT phase_c_workflow_run,
                                                       INSERT phase_c_workflow_step_run, UPDATE phase_c_trace,
                                                       -> fn_kernel_outbox_emit -> INSERT phase_c_event_outbox
                                                       -> fn_phase_d_dispatch_step  (Phase D fires at step OPEN)
inquiries AFTER INSERT -> fn_emit_event -> INSERT company_event -> [company_event chain]
inquiries AFTER INSERT -> trg_learn_customer_preference -> fn_customer_preference_learn -> DELETE+INSERT customer_preference
inquiries AFTER INSERT OR UPDATE -> trg_version_rfq -> INSERT doc_versions
inquiries AFTER INSERT/UPDATE OF category -> fn_emit_rfq_classified -> fn_emit -> INSERT company_event
inquiries AFTER UPDATE OF hired_supplier_id -> fn_approval_raise_on_award -> INSERT procurement_approval_request
inquiries AFTER UPDATE OF drawing_file_path -> trg_reg_inquiry_doc -> fn_register_document -> INSERT documents
     -> documents AFTER INSERT (ref_table='inquiries') -> trg_document_to_kernel
        -> fn_kernel_source_emit('edge:customer_documents') = class B, W07, ACTIVE -> fn_kernel_signal_submit -> kernel_signal_inbox -> kernel chain
inquiries AFTER UPDATE status->'cancelled' -> trg_customer_abandon_ban
     n>=4: fn_kernel_source_emit('dbtrigger:public.inquiries:customer_abandon_ban') class A, W18, ACTIVE -> kernel chain
           + UPDATE customers SET banned -> [customers AFTER UPDATE triggers re-fire]
           + INSERT agent_actions -> agent_actions trg_page_high_agent_action -> fn_kernel_source_emit (class A, W29, ACTIVE) -> kernel chain
     n=3:  INSERT notifications ('abandon_warning') -> [notifications chain]
```

### public.inquiry_matches
| trigger | timing/events | WHEN | function |
|---|---|---|---|
| a00_unsafe_match_eligibility | BEFORE INSERT | — | fn_unsafe_match_eligibility_guard |
| gate_incomplete_match | BEFORE INSERT | — | trg_gate_incomplete_match |
| notify_matched_supplier | AFTER INSERT | — | fn_notify_matched_supplier |

```
inquiry_matches BEFORE INSERT -> fn_unsafe_match_eligibility_guard -> fn_unsafe_block -> INSERT unsafe_block  (can return NULL => silent no-row insert)
inquiry_matches BEFORE INSERT -> trg_gate_incomplete_match (refusal only; publishes app.inquiry_match_gate_verdict / _reason read by K05)
inquiry_matches AFTER INSERT -> fn_notify_matched_supplier -> INSERT notifications -> [notifications chain]
                                                          -> fn_kernel_source_emit('dbtrigger:public.inquiry_matches:notify_matched_supplier')
                                                             class B, W12, ACTIVE -> fn_kernel_signal_submit -> kernel chain
```

### public.documents
| trigger | timing/events | WHEN | function |
|---|---|---|---|
| version_document | AFTER INSERT OR UPDATE OF extracted | — | trg_version_document |
| z95_document_to_kernel | AFTER INSERT | — | trg_document_to_kernel |

```
documents INSERT -> trg_version_document -> INSERT doc_versions
documents INSERT (ref_table='inquiries' ONLY) -> trg_document_to_kernel -> fn_kernel_source_emit('edge:customer_documents') -> kernel chain
```
**Correction to the standing note:** there is **no** `fn_enqueue_doc_backups` trigger on `documents`, and `fn_enqueue_doc_backups` reads **leads / customers / inquiries / quotes**, not `documents`. It has **zero callers in `pg_proc`**; its only caller is `supabase/functions/dropbox_backup/index.ts:151` (`admin.rpc('fn_enqueue_doc_backups')`), invoked by cron 88. Other `doc_backups` writers are edge functions: `supabase/functions/collections_legal/index.ts:137`, `supabase/functions/finance_doc/index.ts:65`.

### public.quotes
| trigger | timing/events | WHEN | function |
|---|---|---|---|
| mask_quote_contact | BEFORE INSERT OR UPDATE | — | trg_mask_quote_contact |
| quote_committed_hash | BEFORE INSERT OR UPDATE OF scope, notes, payment_terms, warranty, committed_items | — | trg_quote_committed_hash |
| quotes_quality | BEFORE INSERT OR UPDATE | — | trg_quote_quality |
| trg_quote_expiry_b | BEFORE INSERT | — | trg_quote_expiry |
| trg_scrub_quote_contacts | BEFORE INSERT OR UPDATE | — | scrub_quote_contacts |
| reg_quote_doc | AFTER INSERT OR UPDATE OF original_file_path | — | trg_reg_quote_doc |
| trg_event_quote | AFTER INSERT | — | fn_emit_event('quote','quote.received') |
| trg_new_quote_sms | AFTER INSERT | — | notify_new_quote_sms |
| version_quote | AFTER INSERT OR UPDATE | — | trg_version_quote |

```
quotes BEFORE INSERT/UPDATE -> scrub_quote_contacts -> INSERT founder_alerts
quotes AFTER INSERT -> trg_version_quote -> INSERT doc_versions
quotes AFTER INSERT -> fn_emit_event -> INSERT company_event -> [company_event chain]
quotes AFTER INSERT -> notify_new_quote_sms -> INSERT notifications -> [notifications chain]
                                            -> fn_kernel_source_emit('dbtrigger:public.quotes:trg_new_quote_sms') class A, W14, ACTIVE -> kernel chain
quotes AFTER UPDATE OF original_file_path -> trg_reg_quote_doc -> fn_register_document -> INSERT documents -> [documents chain]
```

### public.notifications
| trigger | timing/events | WHEN | function |
|---|---|---|---|
| trg_notifications_digest | BEFORE INSERT | — | fn_notifications_digest |
| zzz_notifications_demo_guard | BEFORE INSERT | — | zzz_fn_notifications_demo_guard |
| trg_wa_fanout | AFTER INSERT | — | fn_wa_fanout |
| trg_invite_status_on_send | AFTER UPDATE OF status | — | fn_invite_status_on_send |

```
notifications BEFORE INSERT -> fn_notifications_digest  (may rewrite NEW.status := 'digest' for admin/founder/owner routine types)
notifications BEFORE INSERT -> zzz_fn_notifications_demo_guard
      if decision_policy.demo_rehearsal_active is true AND to_email NOT ~* '@example[.]invalid$'
      then NEW.status := 'held' + last_error text (fails closed; deliberately carries NO 'ZZ DEMO' marker)
notifications AFTER INSERT (channel='email', to_role in supplier|customer, wa_optin true, >=8 digits)
      -> fn_wa_fanout -> INSERT notifications(channel='whatsapp')  [ONE level: the whatsapp row early-returns]
notifications AFTER UPDATE OF status (type='supplier_invite', status='sent', old<>'sent', lead_id not null)
      -> fn_invite_status_on_send -> fn_kernel_source_emit('dbtrigger:public.notifications:trg_invite_status_on_send') class B, W09, ACTIVE -> kernel chain
                                  -> UPDATE public.leads SET invite_status='sent' -> [ALL leads BEFORE/AFTER UPDATE triggers re-fire, incl. trg_sign_supplier and trg_emit_supplier_applied]
```

### public.company_event
| trigger | timing/events | WHEN | function |
|---|---|---|---|
| trg_company_event_dispatch | AFTER INSERT **FOR EACH STATEMENT** | — | trg_company_event_dispatch |
| trg_emit_health_degraded | AFTER INSERT ROW | `new.event_type='os.health_changed' AND payload ? 'previous_score' AND payload ? 'score' AND both ~ '^[0-9.]+$' AND score::numeric < previous_score::numeric` | fn_emit_health_degraded |

```
company_event INSERT (statement) -> trg_company_event_dispatch -> fn_event_dispatch(20)
      -> INSERT event_assessment, INSERT event_delivery, INSERT org_tasks
      -> org_tasks BEFORE INSERT: a00_org_tasks_founder_routing_refund_only, trg_org_task_cross_os_guard  [both can REFUSE]
      on exception: INSERT agent_runs('event_dispatch_trigger','error') and the 15-min cron picks it up
company_event INSERT (health degraded) -> fn_emit_health_degraded -> fn_emit -> INSERT company_event  [recursive one hop; guarded by the WHEN clause]
```

### public.org_tasks
| trigger | timing/events | WHEN | function |
|---|---|---|---|
| a00_org_tasks_founder_routing_refund_only | BEFORE INSERT OR UPDATE | — | fn_kernel_founder_routing_is_refund_only |
| trg_org_task_cross_os_guard | BEFORE INSERT | — | fn_org_task_cross_os_guard |
| trg_org_task_autonomy_brake | BEFORE UPDATE OF status | — | fn_org_task_autonomy_brake |
| trg_org_task_root_cause | BEFORE UPDATE | — | fn_org_task_root_cause_guard |
| trg_undo_org_tasks | BEFORE DELETE OR UPDATE | — | trg_undo_capture('id') |
| trg_workflow_run_follow_task | AFTER UPDATE OF status | — | fn_workflow_run_follow_task |
| z00_kernel_truncate_guard | BEFORE TRUNCATE STATEMENT | — | fn_kernel_truncate_guard |

```
org_tasks UPDATE/DELETE -> trg_undo_capture -> INSERT undo_log
org_tasks AFTER UPDATE OF status -> fn_workflow_run_follow_task -> UPDATE workflow_run ; UPDATE workflow_step_run
      -> workflow_step_run BEFORE INSERT/UPDATE OF actor,status -> trg_step_run_actor_is_a_real_employee  [refusal only]
the four BEFORE guards write nothing (they refuse)
```

### public.phase_c_workflow_run / phase_c_workflow_step_run / phase_c_event_outbox / workflow_step_run
| table | trigger | timing/events | function |
|---|---|---|---|
| phase_c_workflow_run | a00_kernel_write_guard | BEFORE INSERT/UPDATE/DELETE ROW | fn_kernel_write_guard |
| phase_c_workflow_run | a00_kernel_workflow_run_trace_guard | BEFORE UPDATE ROW | fn_kernel_workflow_run_trace_guard |
| phase_c_workflow_run | z20_phase_c_workflow_state_guard | BEFORE UPDATE ROW | fn_phase_c_workflow_state_guard |
| phase_c_workflow_run | z00_kernel_truncate_guard | BEFORE TRUNCATE STMT | fn_kernel_truncate_guard |
| phase_c_workflow_step_run | a00_kernel_write_guard | BEFORE INSERT/UPDATE/DELETE ROW | fn_kernel_write_guard |
| phase_c_workflow_step_run | a00_phase_c_step_run_trace_guard | BEFORE UPDATE ROW | fn_phase_c_step_run_trace_guard |
| phase_c_workflow_step_run | z90_phase_c_step_run_trace_subject | AFTER INSERT ROW | fn_phase_c_step_run_trace_subject |
| phase_c_workflow_step_run | z95_phase_c_step_run_trace_committed | CONSTRAINT TRIGGER AFTER INSERT OR UPDATE, DEFERRABLE INITIALLY DEFERRED, ROW | fn_phase_c_step_run_trace_committed |
| phase_c_workflow_step_run | z00_kernel_truncate_guard | BEFORE TRUNCATE STMT | fn_kernel_truncate_guard |
| phase_c_event_outbox | a00_kernel_write_guard | BEFORE INSERT/UPDATE/DELETE ROW | fn_kernel_write_guard |
| phase_c_event_outbox | z05_outbox_refuse_cancelled_subject | BEFORE UPDATE ROW | fn_kernel_outbox_refuse_cancelled_subject |
| phase_c_event_outbox | z00_kernel_truncate_guard | BEFORE TRUNCATE STMT | fn_kernel_truncate_guard |
| workflow_step_run | a00_step_run_actor_is_a_real_employee | BEFORE INSERT OR UPDATE OF actor, status ROW | trg_step_run_actor_is_a_real_employee |
| workflow_step_run | z00_kernel_truncate_guard | BEFORE TRUNCATE STMT | fn_kernel_truncate_guard |

```
phase_c_workflow_step_run AFTER INSERT -> fn_phase_c_step_run_trace_subject -> fn_phase_c_trace_write -> INSERT phase_c_trace
                                                                            -> UPDATE phase_c_trace ; UPDATE phase_c_workflow_step_run  [self, one hop]
phase_c_workflow_step_run BEFORE UPDATE -> fn_phase_c_step_run_trace_guard -> UPDATE phase_c_trace (fn_phase_c_trace_advance)
phase_c_workflow_run     BEFORE UPDATE -> fn_kernel_workflow_run_trace_guard -> fn_phase_c_trace_advance -> UPDATE phase_c_trace
phase_c_event_outbox: written ONLY by fn_phase_c_outbox_emit / fn_phase_c_outbox_claim / fn_kernel_outbox_emit / fn_kernel_outbox_deliver / fn_kernel_cancel; drained by cron 278 every minute
* / TRUNCATE on any kernel table -> fn_kernel_truncate_guard -> INSERT kernel_maintenance_write
```

# 4. ACTIVE cron jobs (23 of 206) and the tables each touches

Every job except 278 runs `select public.fn_kernel_cron_exec(<jobid>)`, which looks up `phase_c_system_execution_wrapper.original_command` and `execute`s it inside a sub-transaction (failures are recorded, **not** re-raised — `cron.job_run_details` reads "succeeded" for a failed body). Reads/writes below are from `pg_proc.prosrc` at depth 2 over the 15 named tables; the four `net.http_post` jobs write nothing in-DB — the edge function does.

| jobid | jobname | schedule | real command | writes | reads | outbound |
|---|---|---|---|---|---|---|
| 7 | health_check | */30 * * * * | `run_health_check()` | notifications | inquiries, quotes | — |
| 14 | founder_brief_daily | 30 4 * * * | `fn_founder_brief()` | notifications | customers, leads, inquiries, inquiry_matches, quotes, org_tasks (+ same via fn_health_index) | — |
| 26 | smoke_test_30min | */30 * * * * | `fn_smoke()` | notifications | inquiries, quotes | — |
| 35 | uptime_check_15min | */15 * * * * | `net.http_post .../functions/v1/uptime_check` (cred_cron_monitoring) | — | — | **POST** |
| 57 | board_report_weekly | 0 7 * * 1 | `fn_board_report()` | notifications | customers, leads, inquiries, inquiry_matches, quotes (+ fn_health_index, fn_eval_snapshot) | — |
| 60 | monthly_report | 0 7 1 * * | `fn_period_report('monthly')` | notifications | customers, leads, inquiries, quotes | — |
| 64 | autonomy_dispose_hourly | 45 * * * * | `fn_autonomy_dispose()` | **leads** | — | — |
| 77 | security_ai_daily | 5 5 * * * | `fn_security_ai()` | none of the 15 | none of the 15 | — |
| 81 | dropbox_sync_daily | 40 2 * * * | `net.http_post .../functions/v1/dropbox_sync` (cred_cron_backup) | — | — | **POST** |
| 88 | dropbox_backup_scan | */15 * * * * | `net.http_post .../functions/v1/dropbox_backup` (limit 12, 25s) | via edge fn: **doc_backups** (insert/update) | via edge fn `fn_enqueue_doc_backups`: **leads, customers, inquiries, quotes** | **POST** |
| 92 | security_selfaudit_daily | 20 3 * * * | `fn_security_selfaudit()` | none of the 15 | none of the 15 | — |
| 102 | ai_health_15min | 7,22,37,52 * * * * | `net.http_post .../functions/v1/ai_health` | — | — | **POST** |
| 103 | policy_consistency_weekly | 30 6 * * 1 | `fn_policy_consistency_check()` | notifications | — | — |
| 109 | backup_daily | 30 3 * * * | `net.http_post .../functions/v1/backup` | — | — | **POST** |
| 110 | agent_security_hourly | 5 * * * * | `fn_security_scan()` | notifications | customers, leads | — |
| 129 | autonomy_audit_weekly | 0 6 * * 1 | `fn_autonomy_audit_run()` | — | org_tasks (via fn_autonomy_audit) | — |
| 142 | evolution_scan_weekly | 0 6 * * 1 | `fn_evolution_scan()` | — | org_tasks | — |
| 172 | ai_spend_guard_hourly | 40 * * * * | `fn_ai_spend_guard()` | none of the 15 | none of the 15 | — |
| 179 | control_mode_sweep_5min | */5 * * * * | `fn_control_mode_sweep()` | none of the 15 | none of the 15 | — |
| 213 | approval_trace_audit_weekly | 10 6 * * 1 | `fn_approval_trace_audit()` | none of the 15 | none of the 15 | — |
| 214 | decision_conflict_scan_weekly | 20 6 * * 1 | `fn_decision_conflict_scan()` | none of the 15 | none of the 15 | — |
| 215 | regulation_watch_weekly | 40 6 * * 1 | `fn_regulation_watch()` | none of the 15 | none of the 15 | — |
| 278 | phase_c_outbox_deliver_1min | * * * * * | `fn_kernel_outbox_deliver(25,'cron:phase_c_outbox_deliver_1min')` (no wrapper row) | **phase_c_event_outbox** | phase_c_workflow_run, phase_c_workflow_step_run, phase_c_event_outbox (via fn_kernel_event_consume) | — |

Jobs that commit *during* an open Phase D transaction and previously mis-attributed rows to it (J04): **35 and 88, both `*/15`**. That is why the writer now uses xmin attribution.

Concrete residue risks from ACTIVE cron, for a **committed** fixture:
- **88 (every 15 min)** — a committed fixture `leads` row with any doc path / `claimed` / `approved_at`, or a committed `customers` row (unconditional: `Customer Details` generated PDF for *every* customer), or a committed `inquiries` row joined to a customer, becomes `doc_backups` rows and is shipped to Dropbox.
- **64 (hourly)** — `fn_autonomy_dispose()` UPDATEs `leads`, re-firing every leads trigger on fixture rows.
- **7, 14, 26, 57, 60, 103, 110** — all INSERT into `notifications`, whose `zzz_notifications_demo_guard` only holds rows when `decision_policy.demo_rehearsal_active` is true AND the recipient is not `@example.invalid`.

# 5. `public.fn_phase_d_fixture_residue()` — full body

```plpgsql
CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_residue()
 RETURNS TABLE(relation text, surviving_rows bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_n bigint; v_pred text;
begin
  for r in
    select distinct wm.target_relation as rel from public.phase_d_object_write_map wm
     union select 'public.phase_d_object_record'
  loop
    v_pred := (select string_agg(format(
                 '(coalesce(%I::text,'''') like ''ZZ DEMO — %%'' or coalesce(%I::text,'''') like ''%%@example.invalid'' or coalesce(%I::text,'''') like ''zz-phase-d-%%'')',
                 a.attname, a.attname, a.attname), ' or ')
               from pg_attribute a
              where a.attrelid = r.rel::regclass and a.attnum > 0 and not a.attisdropped
                and format_type(a.atttypid, a.atttypmod) in ('text','character varying','jsonb'));
    if v_pred is null then continue; end if;
    execute format('select count(*) from %s where %s', r.rel, v_pred) into v_n;
    if v_n > 0 then
      relation := r.rel; surviving_rows := v_n; return next;
    end if;
  end loop;
end $function$
```
Not SECURITY DEFINER (`prosecdef=false`), STABLE, owner postgres. Live result right now: **`[]`** (no residue).

**Exactly 22 relations counted** = 21 distinct `phase_d_object_write_map.target_relation` + `public.phase_d_object_record`:
`public.company_goals, content_drafts, customers, department_objective, documents, inquiries, inquiry_answer, inquiry_matches, leads, legal_reviews, opportunity, org_tasks, os_incidents, quote_comparisons, quotes, refunds, reveal_invoices, review_chain, stripe_events, supplier_capabilities, transactions` + `public.phase_d_object_record`.

Match rule: any `text`/`varchar`/`jsonb` column matching `'ZZ DEMO — %'` OR `'%@example.invalid'` OR `'zz-phase-d-%'`. A relation with no such column is skipped silently (`v_pred is null → continue`).

**NOT counted, though every one is reachable from a fixture write via the chains above:** `notifications`, `doc_backups`, `doc_versions`, `company_event`, `event_assessment`, `event_delivery`, `agent_actions`, `agent_runs`, `undo_log`, `founder_alerts`, `customer_preference`, `procurement_approval_request`, `unsafe_block`, `kernel_trigger_inbox`, `kernel_signal_inbox`, `kernel_adapter_failure`, `kernel_maintenance_write`, `phase_c_trace`, `phase_c_workflow_run`, `phase_c_workflow_step_run`, `phase_c_handoff_run`, `phase_c_step_completion`, `phase_c_event_outbox`, `workflow_run`, `workflow_step_run`. Note also that `zzz_fn_notifications_demo_guard` deliberately does **not** stamp the marker on the rows it holds, so a held fixture notification would be invisible to a marker scan even if `notifications` were added to the population.

# 6. `net.http_request_queue` and `net._http_response`

Schema `net` holds exactly two tables.

```
net.http_request_queue
  id                    bigint  NOT NULL  default nextval('net.http_request_queue_id_seq'::regclass)
  method                text    NOT NULL
  url                   text    NOT NULL
  headers               jsonb   NULL
  body                  bytea   NULL
  timeout_milliseconds  integer NOT NULL
```
`information_schema.role_table_grants` for it: **empty** — no role has any privilege. Only the owner (postgres) and SECURITY DEFINER functions owned by postgres can read it; that is why `fn_phase_d_outbound_requests_by_this_transaction` is SECURITY DEFINER.

**Watermark:** `select coalesce(max(id),0) from net.http_request_queue;` taken immediately before the write, then count rows with a *higher* id — never a count delta, because pg_net's background worker DELETEs processed rows and a concurrent drain masks a delta to zero. Measured now: `max_id = 0, depth = 0` (queue fully drained), so a bare `id > watermark` test alone would match any concurrent job's row; the xmin + `pg_xact_status(...) = 'in progress'` filter in the helper is what makes it attribution rather than a count.

```
net._http_response
  id            bigint       NULL          -- correlates with http_request_queue.id
  status_code   integer      NULL
  content_type  text         NULL
  headers       jsonb        NULL
  content       text         NULL
  timed_out     boolean      NULL
  error_msg     text         NULL
  created       timestamptz  NOT NULL      default now()
```
Measured now: `max(id) = 311462`, `count(*) = 72` (pg_net TTL-prunes it). It exists, and it is the only place a POST that *actually left* is still visible after the queue row is deleted — a watermark for "did anything go out" is `select coalesce(max(id),0), max(created) from net._http_response` before, then `select id, status_code, error_msg, timed_out from net._http_response where id > <mark>` after. It is **not** used by any Phase D routine today (only `http_request_queue` is).

---
Scratch scripts (all read-only, none committed): `C:\Users\Opera\quotesdone\scripts\tmp_diag\od_door.mjs`, `od_supp_readers.mjs`, `od_dump_fn.mjs`, `od_trg.mjs`, `od_fetch_all.mjs` (writes `allfns.json`, 3.3 MB local cache of all 1225 public function bodies), `od_chain.mjs`, `od_flat.mjs`, `od_writers.mjs`, `od_alldoors.mjs`, `od_cron.mjs`, `od_cron_cmd.mjs`, `od_crontouch.mjs`, `od_cutover.mjs`, `od_cutover2.mjs`, `od_cutover3.mjs`, `od_net.mjs`, `od_misc.mjs`, `od_ddl.mjs`, `od_bodies.mjs`.

NOT MEASURED: whether each trigger-function branch that writes a table is actually *taken* for a given fixture payload — the write lists are static `prosrc` analysis, not execution traces. NOT MEASURED: what the four `net.http_post` cron edge functions (uptime_check, dropbox_sync, ai_health, backup) write, beyond `dropbox_backup`, which I read at `supabase/functions/dropbox_backup/index.ts`.