# QuotesDone company-operations corpus â implementation report

**Corpus:** `QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31` (v1.0.0)
**Control pack:** `QuotesDone_CLAUDE_COMPANY_OPERATIONS_INGESTION_v2026.07.31`
**Executed:** 2 August 2026 Â· Supabase project `htdblwldjkcgjvmqkbeh`
**Branch:** `feature/company-operations-corpus`
**Status:** imported to staging, mapped, tested. **Production not activated. Nothing enabled. Nothing approved.**

---

## 1. Package verification

| Check | Result |
|---|---|
| `99_CHECKSUMS_SHA256.txt` | **317 / 317 match**, 0 mismatched, 0 missing |
| `00_PACKAGE_MANIFEST.json` | **316 / 316** match on both SHA-256 **and** byte size |
| ZIP path traversal / absolute paths | **0** in either archive (318 + 23 members) |
| JSONL line-size guard (2 MB) | 0 violations |
| JSON depth guard (40) | 0 violations |
| Secret-pattern scan on every record | **0 hits** â no JWT, API key, Stripe key or private key anywhere in the corpus |

`00_COMPANY_OPERATIONS_MASTER.md` (2,057,246 characters) was checksum-verified and **never read**. It is not in the database and never entered a prompt.

---

## 2. What landed

| | Imported | QA report says |
|---|---:|---:|
| Atomic records | **3,959** | 3,959 |
| Departments | **24** | 24 |
| Roles | **96** | 96 |
| SOPs | **236** | 236 |
| Decision rules | **240** | 240 |
| Exception playbooks | **240** | 240 |
| KPIs | **216** | 216 |
| Templates | **120** | 120 |
| Department scenarios | **192** | 192 |
| Cross-department workflows | **18** | 18 |
| Workflow handoffs | **132** | 132 |
| Workflow scenarios | **90** | 90 |
| Event subscriptions | **100** | 100 |
| Live-data bindings | **268** | 268 |
| Governance policies | **28** | â |
| Hard gates | **10** | 10 |
| Sources | **21** | 21 |
| **Rejected** | **0** | â |
| **Write errors** | **0** | â |

6,038 rows across 17 tables. Database 593 MB â 594 MB.

**Everything arrived disabled.** 240 decision rules `enabled=false`, 18 workflows `enabled=false`, 132 handoffs `enabled=false`, 216 KPIs `enabled=false`, 100 event subscriptions `active=false`, 0 records at `validation_status='approved'`. An imported rule that can fire *is* an activated rule, so none of them can.

**Implementation status is carried verbatim and never inferred:** 1,325 `implemented`, 1,317 `partial`, **1,317 `target_state`**. Only a third of this corpus describes something that exists. That distinction is a column, not a footnote, and every runtime function exposes it.

---

## 3. Mapping â 21 decisions, 0 unresolved

Every one of the 33 objects the mapping guide names **already exists in production and is populated**. This corpus is not a system to build; it is a larger version of one that is running. So `reuse` is the default and `create_staging` had to be earned.

| Decision | Count | Concepts |
|---|---:|---|
| **reuse** | 9 | department, role_agent, department_knowledge, employee_knowledge, event_subscription, audit_record, institutional_memory, model_routing_policy, supplier_category_expertise |
| **extend** | 9 | sop, decision_rule, hard_gate, authority_tier, exception_playbook, kpi, scenario, live_data_binding, incident_priority |
| **create_staging** | 3 | cross_department_workflow, data_classification, department_crosswalk |
| unresolved / reject | **0** | â |

Full rationale and live evidence in `ops_kb_stage.mapping_decisions`.

**The three clearest findings from the mapping:**

*SOPs are the biggest straight win.* `employee_workflow` has 157 rows and **three columns** â it records *that* a workflow exists, not its steps, inputs, outputs, service level, definition of done or rollback. The 236 corpus SOPs carry all six.

*Cross-department workflows are genuinely new.* Production has `company_event` (98) and `event_subscription` (48) for the messaging, but no object owns a workflow that spans departments, its typed handoffs, its acceptance criteria or its hard gates. 18 workflows and 132 handoffs are the largest new capability here.

*Model routing is already built.* The 5 corpus routing-policy records describe a mechanism that has been running since 29 July â `ai_gateway`, `fn_ai_route`, capability-aware selection, per-department budgets, measured in `ai_cost_log`. Reuse and reconcile; do not build a second router.

---

## 4. Conflicts that must be resolved before promotion

### 4.1 Three department-crosswalk conflicts

Validating the supplied crosswalk against live `org_departments` found three things it does not contain:

| Conflict | Detail |
|---|---|
| **`hr` is unmapped** | Live production department with agents and authority rows. The crosswalk lists `hr_people` under `unmapped_target â target_state`, i.e. as something that does not exist. It does. |
| **`sales` is unmapped** | Live "Sales & Growth" department. The crosswalk folds `sales_crm` under `marketing` and never mentions the production `sales` key. |
| **`ai_model_ops` has no production owner** | Target department with no production department mapped to it â despite AI operations being live and measured. |

Promoting the target model as written would leave two live departments without a defined owner. **This is the single blocking item.**

### 4.2 Eight of the ten hard gates have no authority row

`public.org_authority` names 33 (department, action_class) pairs. Only **2 of the 10 corpus hard gates** â `ad_spend` and `money_move` â appear among them. `authentication_identity`, `autonomy_framework`, `destructive_data`, `legal_commitment`, `production_deploy`, `public_claim_publish`, `secrets_security` and `supplier_enforcement` have **no row at all**.

They are safe *inside* `fn_ops_authority_check`, which fails closed to `gated` when no row exists â verified by adversarial test below. They are not necessarily safe in any other code path that reads `org_authority` directly and has to invent its own default.

Filling them in is itself an authority change, which is hard-gated. **Not done. Reported.** See `v_ops_hard_gate_coverage`.

### 4.3 One real data-model gap

Of 268 live-data bindings, **262 resolve to a real object by exact name**. Five of the remaining six are naming drift, resolved with the reason recorded in `ops_kb_stage.binding_aliases`:

- `suppliers` / `companies` â `leads` (there has never been a suppliers table; creating one would split the source of truth)
- `supplier_health_snapshots` â `supplier_health` + `supplier_kpi_snapshots`
- `audit_logs` â `os_audit_log` + `security_audit_log` (two streams by design, different retention)
- `kyc` â not a table; it is an edge function, state lives on `customers`/`leads`

The sixth is real: **there is no refunds ledger.** Refunds are currently implied by `stripe_transactions` plus a `decision_record`. Payments & Revenue cannot report a refund rate, an approver or a reconciliation without one. Flagged `rejected`, not aliased away.

All 24 target departments have at least one resolved live-data binding.

---

## 5. Runtime built (nothing enabled)

**`fn_ops_authority_check(dept, action_class, amount_aed, risk)`** â combines live `org_authority` with the corpus hard gates under a **strictest-wins** rule. A hard gate can only tighten, never widen; `risk_level='critical'` is never autonomous; an unknown department or action fails closed to `gated`. This is what stops an imported corpus from being an authority-escalation vector.

**`fn_ops_department_context(dept, topic, limit)`** â company core + ranked department knowledge + resolved live objects + authoritative sources + hard gates + recent institutional memory. Returns a handful of records, not a department master. `agent_brain` currently spends 14,600â22,000 input tokens per call; that is the target.

**`v_ops_supplier_corpus_link`** â joins RFQ Intelligence, Marketplace Operations, Supplier Knowledge and Document Intelligence to the 86-route supplier corpus **by `catalog_num`**. Linked, never copied: category expertise keeps exactly one owner, as the pack requires.

---

## 6. Tests

### Hard-gate adversarial tests â 9/9 correct

| Attempt | Result |
|---|---|
| Move money from Finance (AED 5,000) | **gated** |
| Destructive data from Engineering (critical) | **gated** |
| Identity change from Customer Success | **gated** |
| Change authority tiers from Exec | **gated** |
| Activate AED 50,000 ad spend from Marketing | **gated** (matched the real `org_authority` row) |
| Legal commitment from Legal | **gated** |
| Publish content from Marketing | autonomous â correct |
| Send outreach from Sales | autonomous â correct |
| Unknown department + unknown action | **gated** (fail-closed) |

### Scenario harness â 282/282 runnable

Scoped honestly: the 282 scenarios describe *behaviour*, and executing them properly needs a runner that can drive the real flows. That runner does not exist and building it was not in scope. What was executed is whether each scenario is **runnable at all** â department exists, has professional knowledge, has resolved live data, has decision rules, states pass criteria, and (for workflow scenarios) resolves to an imported workflow.

**192 department + 90 workflow scenarios: all RUNNABLE, 0 blocked.** A blocked scenario could not pass a behavioural run either, so this is a real filter â but it is **not** behavioural proof and is labelled `structural` everywhere.

### Idempotency, rollback and restoration â measured, not described

| Test | Result |
|---|---|
| Full re-import | identical counts, **0 versions archived** (nothing changed), 1 ingestion run |
| Nothing silently enabled on re-import | 0 rules, 0 workflows, 0 events, 0 approved |
| Rollback of the run | 3,959 records + all projections removed; departments, crosswalk and mapping decisions correctly survive |
| Re-import after rollback | back to exactly 3,959 / 96 / 240 / 282, 266 bindings mapped |
| Duplicates created | **0** |

### Least privilege

`ops_kb_stage` is **not exposed to the REST API**. Every table has RLS enabled with zero policies *and* privileges revoked from `anon` and `authenticated`, plus `alter default privileges` so a future table inherits the same. The only doors are five `SECURITY DEFINER` functions granted to `service_role` alone. Verified: an anon or authenticated key can read nothing.

---

## 7. OpenRouter reduction

Building on the audit from the supplier-corpus import, this corpus adds three replaceable paths:

1. **Department context assembly.** `agent_brain` runs at 14,600â22,000 input tokens a call â AED 22.56 over 129 calls, the largest single AI cost in the company, and it scales with every department added. `fn_ops_department_context` returns the same six things deterministically. **Highest-value change available.**
2. **Authority decisions.** Anywhere a model is asked "can this department do this" is now a SQL call with a defensible, auditable answer. A model deciding its own authority is a category error, not just a cost.
3. **KPI computation.** 216 KPI definitions with formula descriptions. They need `query_sql` written â until then they are documentation, which is why all 216 are `enabled=false`. Once written they replace every "summarise how the department is doing" call.

Model calls that legitimately remain: open-ended reasoning and synthesis, drawings and documents (vision), ambiguous natural language the deterministic router declines, and genuinely novel exceptions.

---

## 8. Acceptance against the supplied checklist

**Package** â ZIP validated â Â· checksums 317/317 â Â· manifest 316/316 â Â· every JSONL line validated programmatically â Â· master never read â Â· no secrets â Â· no path traversal â

**Schema** â existing objects inspected before creating anything â Â· staging schema adapted, not copied â Â· no duplicate source of truth â Â· record_id, scope, module, source_ids, implementation_status, validation_status, authority tier, risk, version, dates, dependencies and escalation rule all preserved as columns â

**Import** â one file at a time â Â· one JSON object per line â Â· batches of 500 â Â· upsert by stable ID â Â· file hash and package version recorded â Â· resumes safely â Â· malformed rows rejected with reason â (0 occurred) Â· counts by file â

**Governance** â `target_state` and `partial` not promoted â Â· nothing promoted to `approved` â Â· legal, tax, privacy, security, identity, money, destructive, deployment, public claims and authority changes all still gated â Â· imported records cannot expand authority â (strictest-wins, tested) Â· no secrets in knowledge tables â Â· volatile state left in live tables â Â· deterministic data is relational â Â· supplier corpus linked by key, not copied â

**Tests** â package validation â Â· department scenarios â *(structural)* Â· workflow scenarios â *(structural)* Â· hard-gate adversarial â Â· least privilege â Â· idempotency â Â· rollback and restoration â Â· **outage/recovery: not run** Â· **English/Arabic customer-facing: not applicable to this corpus** (covered by the supplier-corpus import) Â· **frontend workflow tests: not run â nothing in the live path was modified**

**Activation** â **no production activation** â Â· no validation status mass-promoted â Â· no completeness claimed beyond what the tests prove â

---

## 9. Rollback

```sql
select id, package_name, status from ops_kb_stage.ingestion_runs;
select public.ops_rollback_run('<run_id>');     -- tested
```

Total removal, and it touches nothing else:
```sql
drop schema ops_kb_stage cascade;
drop view public.v_ops_supplier_corpus_link, public.v_ops_hard_gate_coverage;
drop function public.fn_ops_authority_check, public.fn_ops_department_context, public.fn_ops_run_scenarios;
drop function public.ops_stage_upsert, public.ops_begin_run, public.ops_finish_run,
              public.ops_get_files, public.ops_rollback_run;
```

No live table was altered. `org_departments`, `org_agents`, `org_authority`, `dept_library`, `employee_knowledge`, `governance_policy` and every edge function are exactly as they were.

---

## 10. Recommended activation order

Each step behind a feature flag, one department at a time, with the previous version preserved.

1. **Resolve the three crosswalk conflicts** (Â§4.1). Nothing else should start until `hr`, `sales` and `ai_model_ops` have owners. This is a decision, not a task.
2. **Decide the eight missing hard-gate authority rows** (Â§4.2). An authority change, therefore the founder's call.
3. **Read-only context assembly first.** Point one department's `agent_brain` at `fn_ops_department_context` and compare answer quality and token cost against today's. Reversible in one flag; no rule fires.
4. **SOPs next**, still read-only â the clearest quality gain and the lowest risk.
5. **Decision rules, one department at a time**, `advisory` tier only, logging what they *would* have decided without acting. Promote to `supervised` only after that log looks right.
6. **Cross-department workflows last.** They are the largest new capability and the only one with no production precedent, so they need the most evidence.
7. **KPIs when `query_sql` exists** â not before; a KPI that cannot be computed is documentation.

Never activate: anything at `implementation_status = 'target_state'` without building the thing it describes first. 1,317 records are in that state, and importing them did not make any of them true.
