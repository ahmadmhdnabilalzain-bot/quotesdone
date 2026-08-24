# The nine autonomous sources that do not route through the kernel inbox

**Measured on production `htdblwldjkcgjvmqkbeh` at HEAD `521ed160af1c995aa4d42d8bb9f048d720ade09e`,
production clock 2026-08-24T20:22:08Z onward. Nothing here was reactivated, re-pointed or repaired.
This is a decision packet.**

The nine are the population of

```sql
select * from public.v_kernel_trigger_source_derived
 where coalesce(is_active_now,false) and coalesce(creates_work_now,false)
   and coalesce(disposition,'') <> 'FOUNDER_COMMAND_SURFACE'
   and not coalesce(routes_through_inbox,false);
```

which is the exact predicate behind
`fn_kernel_trigger_state :: active_autonomous_source_not_yet_routing_through_the_inbox = 9 of 37`.

**Two boards report on this one subject and they do not agree.** `fn_kernel_cutover_measure` reads
`active_sources_bypassing_the_kernel = 1 [edge:inquiry_intake]` and
`active_sources_writing_business_work_directly = 0`. The disagreement is not noise: it is the whole
finding, and §Findings below says exactly where each board is right.

---

## The table

Read `held / live` first. **None of the nine is held.** The public site serves
(`https://quotesdone.com/portal` and `/contact` → HTTP 200 through a 307 locale redirect,
measured); the two edge functions among the nine are `ACTIVE` on production (`inquiry_intake` v22,
`attach_photos` v7), as is every edge function the five routes reach (`customer_api` v63,
`customer_portal` v8, `customer_documents` v4, `messages_api` v20, `project_api` v5,
`procurement_api` v3, `contact_submit` v4, `site_assistant` v19, `supplier_api` v51,
`supplier_portal` v37, `supplier_onboard` v4); and both database triggers are enabled
(`tgenabled = 'O'`). A real business event can arrive at any of them today.

### 1. `edge:inquiry_intake` — **A. ACTIVE_CURRENT_DEFECT**

| field | measurement |
|---|---|
| source ID | `edge:inquiry_intake` |
| source type | `edge_function` |
| current activation state | **ACTIVE**, v22, `verify_jwt=false` with an in-function `admin.auth.getUser` → 401 without a valid user |
| actual caller | the customer portal component `src/components/me/CustomerPortal.tsx` (two call sites, lines 1117 and 1359) and any authenticated HTTP client |
| last execution | **72 runs, last 2026-08-14T09:09:17Z** (`public.agent_runs where agent='inquiry_intake'`) |
| business state changed | `public.customers` — **INSERT** (index.ts:96–99) — plus `inquiry_intake` INSERT/UPDATE, `agent_runs`, `ai_qa_log` |
| external effect | none. It calls `ai_gateway`, which is held open-circuit; the customer and draft writes happen **before** that call |
| current path | authenticated POST → `rl_check` → `customers` select, and **insert if missing** → `inquiry_intake` draft insert → AI enrichment |
| canonical kernel path | `fn_kernel_trigger_submit` with `customer.inquiry_submitted` → W05, or `customer.registered` → W04 for the account |
| reason it bypasses the kernel | none of its write tables carries a kernel-routing trigger. Measured on `public.customers`: four triggers, **none** calls `fn_kernel_trigger_submit` / `fn_kernel_signal_submit` / `fn_kernel_source_emit`. `trg_emit_customer_registered` calls `fn_emit(...)`, a domain-event emit, not a kernel submit |
| held or live | **LIVE** |
| immediate risk | a `customer_account` — a frozen Phase B business object governed by W04 — is created with no workflow run, no task, no accountable owner and no trace. Today the blast radius is one row per new authenticated customer; `public.customers` is at 0 |
| required fix | route the customer creation through the kernel — either an adapter on `edge:inquiry_intake`, or a kernel-routing trigger on `public.customers` so **every** creator is covered, including `customer_api`'s `me` handler which creates the same row |
| owning phase | **Phase C** (kernel cutover, K10 wiring increment). Not a Phase D gate |
| activation gate | none required to fix. Wiring it is a repair, not an activation |

**The committed cutover matrix says `COVERED_BY_A_CUT_OVER_TABLE_TRIGGER — routine:trg_inquiry_received`.
That claim is true about the inquiry and silent about the customer.** `customer_api` promotes a
ready draft into `public.inquiries`, and that insert does reach the kernel through
`trg_inquiry_received_a`. The `customers` INSERT reaches nothing. The claim covers one of the two
writes, and the table's own work-table list names `customers` as
*"phase_b_business_object.customer_account, governed by W04"*.

### 2. `dbtrigger:public.quote_items:quote_items_rescore` — **C. FALSE_OR_STALE_MEASUREMENT**

| field | measurement |
|---|---|
| source ID | `dbtrigger:public.quote_items:quote_items_rescore` |
| source type | `database_trigger` (`public.quote_items` → `trg_quote_items_rescore`) |
| current activation state | **enabled** (`tgenabled = 'O'`) |
| actual caller | any write to `public.quote_items` — in practice `edge:supplier_api`, which is itself cut over |
| last execution | not separately logged. `public.quote_items` holds **0 rows** and its last `created_at` is null (the marketplace fixture purge, 16 Aug 2026), so it has fired against no real line item since |
| business state changed | **none.** Its entire body is `update public.quotes set status = status where id = coalesce(NEW.quote_id, OLD.quote_id)` — a no-op touch that re-fires the `quotes` triggers |
| external effect | none |
| current path | line-item write → no-op `quotes` UPDATE |
| canonical kernel path | not applicable — `dbtrigger:public.quote_items:quote_items_roll` carries the revision signal for all three `quote_items` triggers, so one edit delivers one signal instead of three |
| reason it bypasses the kernel | the board's predicate is textual: the trigger function's body matches `update ... quotes`, and `quotes` is on the work-table list, so `creates_work_now` reads true. It does not look at *what* is written |
| held or live | **LIVE** (and inert by construction) |
| immediate risk | **none measured.** The only kernel-routing trigger on `public.quotes` is `trg_new_quote_sms`, and `pg_get_triggerdef` shows it is `AFTER INSERT` — an UPDATE cannot fire it either way |
| required fix | none to the trigger. The fix is to the measurement: see §Findings F2 |
| owning phase | Phase C (the board), not Phase D |
| activation gate | none |

### 3. `dbtrigger:public.quote_items:trg_items_submittable` — **C. FALSE_OR_STALE_MEASUREMENT**

| field | measurement |
|---|---|
| source ID | `dbtrigger:public.quote_items:trg_items_submittable` |
| source type | `database_trigger` (`public.quote_items` → `fn_quote_recompute_submittable`) |
| current activation state | **enabled** (`tgenabled = 'O'`) |
| actual caller | any write to `public.quote_items`; in practice `edge:supplier_api` |
| last execution | as row 2 — `quote_items` is empty since the 16 Aug purge |
| business state changed | one derived field on the quote its own item belongs to: `update public.quotes set submittable = ok where id = qid and submittable is distinct from ok`. No business state, no status, no ownership |
| external effect | none |
| current path | line-item write → recompute structured and category score → write `quotes.submittable` |
| canonical kernel path | not applicable; `quote_items_roll` carries the revision signal |
| reason it bypasses the kernel | same textual predicate as row 2 |
| held or live | **LIVE** |
| immediate risk | **none measured** — same `AFTER INSERT` argument; a normalisation write cannot open or move a workflow |
| required fix | none to the trigger; see §Findings F2 |
| owning phase | Phase C | 
| activation gate | none |

### 4. `edge:attach_photos` — **C. FALSE_OR_STALE_MEASUREMENT**

| field | measurement |
|---|---|
| source ID | `edge:attach_photos` |
| source type | `edge_function` |
| current activation state | **ACTIVE**, v7, `verify_jwt=false` with an in-function `admin.auth.getUser` → 401 |
| actual caller | the customer portal photo-upload path |
| last execution | not separately logged; `public.drawing_redaction_runs` holds **0 rows**, so no redaction run attributable to it exists today |
| business state changed | **none. It writes no table at all.** The complete file is 60 lines: it reads `app_secrets` and `customers` (both `select`), forwards the images to `drawing_redact`, and returns the paths and the job id |
| external effect | none — the forward is to a sibling Supabase function, not to a third party |
| current path | authenticated POST → `drawing_redact` → returns paths |
| canonical kernel path | not applicable to this function. The privacy record it causes belongs to `drawing_redact` |
| reason it bypasses the kernel | `kernel_trigger_source.recorded_creates_work = true` — a **recorded** flag, not a measured one. The committed cutover matrix already corrected this (`READ_ONLY_CONFIRMED_BY_MEASUREMENT — read_only:writes no table at all`); the recorded flag was never updated to match |
| held or live | **LIVE** |
| immediate risk | none from this function. See §Findings F3 for the one real observation behind it |
| required fix | set `recorded_creates_work = false`, matching the measurement the cutover matrix already made |
| owning phase | Phase C |
| activation gate | none |

### 5–9. The five frontend routes — **C. FALSE_OR_STALE_MEASUREMENT**

`ui:/[locale]/contact`, `ui:/[locale]/me`, `ui:/[locale]/portal`, `ui:/[locale]/supplier`,
`ui:ChatWidget`.

| field | measurement (common to all five) |
|---|---|
| source type | `frontend_path` |
| current activation state | **LIVE.** `https://quotesdone.com/portal` and `/contact` both return HTTP 200 (via a 307 locale redirect), measured today |
| business state changed | **none directly.** A browser holds no service-role key and makes no database write; every write is made by the edge function it calls |
| external effect | none |
| reason it "bypasses" the kernel | the view's routing predicate has an edge-function arm — it joins `phase_c_edge_function_writes` to the triggers on the tables written — and that arm is **gated on `s.source_kind = 'edge_function'`**. For a `frontend_path` the only two ways to read as routed are (a) a kernel-calling routine whose body contains the literal source key, or (b) the recorded flag. Neither can ever be true of a page. **A frontend route is structurally incapable of passing this check** |
| held or live | **LIVE** |
| owning phase | Phase C |
| activation gate | none |

Per route, with the edge functions each actually reaches and each function's own measured routing
state:

| # | source ID | actual caller / entry | edge functions reached | all cut over? | last execution evidence | immediate risk |
|---|---|---|---|---|---|---|
| 5 | `ui:/[locale]/contact` | public contact form, `src/components/ContactInner.tsx` | `contact_submit` | **yes** — `routes_through_inbox = true`, `trg_contact_message_to_kernel` | `public.contact_messages` = 0 rows | none measured |
| 6 | `ui:/[locale]/me` | `src/components/me/CustomerPortal.tsx`, `PortalShell.tsx` | `customer_api` ✔, `customer_portal`, **`inquiry_intake`** ✘ | **no** — reaches row 1 | `messages` 0, `chat_threads` 0; `inquiry_intake` last ran 2026-08-14 | **inherits row 1.** Fixing `edge:inquiry_intake` closes this route too |
| 7 | `ui:/[locale]/portal` | `src/components/portal/**/api.ts` | `customer_api` ✔, `customer_documents` ✔, `messages_api` ✔, `project_api`, `procurement_api` | **yes, for every work table** | `inquiries` 0, `projects` 0, `procurement_approval_request` 0 | none measured — `project_api` writes `inquiries` (kernel-routed via `trg_inquiry_received_a`) and `projects`; `procurement_api` writes `procurement_approval_request`; neither of the latter two is a work table |
| 8 | `ui:/[locale]/supplier` | `src/components/portal/supplier/**` | `supplier_api` ✔, `supplier_portal` ✔, `supplier_onboard` ✔ | **yes** | `leads` last written 2026-08-12; 81 invited, 0 registered | none measured |
| 9 | `ui:ChatWidget` | site-wide widget, `src/components/ChatWidget.tsx` | `site_assistant` ✔ — `trg_assistant_log_to_kernel` | **yes** | `assistant_logs` 106 rows, last 2026-08-14T05:13Z | none measured |

**Required fix for all five:** none to the routes. The fix is to the measurement — see §Findings F1.
The cutover matrix already dispositions all five as `COVERED_BY_THE_EDGE_FUNCTION_IT_CALLS`, with
the reason a browser cannot hold a service-role key and must never call the kernel directly.

---

## Classification summary

| class | count | sources |
|---|---|---|
| **A. ACTIVE_CURRENT_DEFECT** | **1** | `edge:inquiry_intake` — an uncovered `public.customers` INSERT on a live, authenticated path |
| **B. HELD_LAUNCH_ACTIVATION_GAP** | **0** | nothing here is held. Every one of the nine can receive and process a real business event today |
| **C. FALSE_OR_STALE_MEASUREMENT** | **8** | the two `quote_items` recomputation triggers, `edge:attach_photos`, and the five frontend routes |

`ui:/[locale]/me` is class C in its own right — it writes nothing — and it **reaches** the class-A
defect. It is not counted twice; the fix is at `edge:inquiry_intake`.

---

## Findings

**F1. A frontend path can never pass the routing check.** The edge-function arm of
`v_kernel_trigger_source_derived.routes_through_inbox` is gated on
`s.source_kind = 'edge_function'`. Five of the nine are `frontend_path` rows, and for those the
predicate has no arm that could ever be true. A check that cannot pass is not measuring the thing
its name claims. The repair is to give the view a frontend arm — a route is routed when every edge
function it calls is routed — or to hold `frontend_path` out of the population by disposition, the
way `FOUNDER_COMMAND_SURFACE` already is.

**F2. `creates_work_now` reads the table name, not the write.** Both `quote_items` triggers write
`public.quotes`; one writes `status = status` and the other writes a derived boolean on the row its
own item belongs to. Neither creates or moves business work. The predicate matches
`(insert into|update)\s+(public\.)?quotes\y` in the routine body and stops there.

**F3. `attach_photos` does not write, but what it calls does — and that function is not in the
inventory.** `attach_photos` forwards to `drawing_redact`, which writes `drawing_redaction_runs` (a
**privacy** record) and storage objects. `edge:drawing_redact` appears in no row of
`kernel_trigger_source`: the inventory holds 25 edge functions against 202 deployed. The nine are
what the inventory can see, not what the estate contains.

**F4. Routing is attributed per edge function, not per table.** `edge:customer_api` reads
`routes_through_inbox = true` because it writes `inquiries`, `leads`, `quotes`, `transactions`,
`agent_actions`, `inquiry_matches` and `notifications`, several of which carry kernel-routing
triggers. It **also** creates `public.customers` rows, and that write reaches nothing — the same
gap as row 1, hidden by the function-level credit. A per-table attribution would show it.

**F5. The two boards disagree because they ask different questions.**
`fn_kernel_cutover_measure` reads the committed disposition in `phase_c_source_cutover` and returns
1 bypass; `fn_kernel_trigger_state` recomputes from routine bodies and returns 9. Both are honest
about their own method and neither says which is the subject. On the evidence here the cutover
matrix's dispositions are right about eight of the nine and incomplete about
`edge:inquiry_intake` — where it credits a coverage that applies to the inquiry and not to the
customer. So the true count of active kernel bypasses that change business state today is **1**,
and it is the one both boards name.

---

## What this measurement did not cover

- **Edge-function invocation logs were not read.** "Last execution" is database-side evidence —
  `agent_runs`, and the last write to the tables each source touches. A function that ran and wrote
  nothing would not appear. The one source with a real invocation log (`inquiry_intake`, via
  `agent_runs`) is stated with its exact count and timestamp.
- **The inventory's own completeness was not audited.** 25 edge functions of 202 deployed are
  inventoried; F3 is one consequence and there may be others.
- **Nothing was reactivated, re-pointed, wired or repaired**, as instructed.
