# §8 HTTP PROBE HARNESS — FULL CHARACTERISATION

All facts below measured 2026-08-23 against production `htdblwldjkcgjvmqkbeh`. Diag scripts written to `C:\Users\Opera\quotesdone\scripts\tmp_diag\s8_recon{1..5}.mjs`, `s8_conc_probe.mjs`, `s8_conc_probe2.mjs`. Nothing written to the DB.

---

## 1. `scripts/phase_d/run_section8_security_probes.mjs` (714 lines)

### 1a. Auth-minting sequence (verbatim, lines 51–100)

```js
const PROJECT = 'htdblwldjkcgjvmqkbeh';
const BASE = `https://${PROJECT}.supabase.co`;
const MGMT = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

const mgmt = async (path, init = {}) => {                                        // :64
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROJECT}${path}`, {
    ...init,
    headers: { authorization: `Bearer ${MGMT}`, 'content-type': 'application/json', ...(init.headers || {}) },
  });
  if (!r.ok) throw new Error(`management ${path} -> ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return r.json();
};

const keys = await mgmt('/api-keys?reveal=true');                                // :73
const SERVICE = keys.find((k) => k.name === 'service_role' || k.type === 'secret')?.api_key;
const ANON = keys.find((k) => k.name === 'anon' || k.type === 'publishable')?.api_key;
if (!SERVICE || !ANON) throw new Error('could not resolve both the service_role and anon keys');

const admin = async (path, init = {}) => {                                       // :78
  const r = await fetch(`${BASE}/auth/v1${path}`, {
    ...init,
    headers: { apikey: SERVICE, authorization: `Bearer ${SERVICE}`, 'content-type': 'application/json', ...(init.headers || {}) },
  });
  return { status: r.status, body: await r.json().catch(() => ({})) };
};

// A bearer for an e-mail without touching its password. generate_link RETURNS a link; it does not
// deliver mail. The token_hash is then verified for a real session.
const bearerFor = async (email) => {                                             // :88
  const gen = await admin('/admin/generate_link', { method: 'POST', body: JSON.stringify({ type: 'magiclink', email }) });
  const hash = gen.body?.hashed_token || gen.body?.properties?.hashed_token;
  if (!hash) throw new Error(`generate_link for ${email} returned no hashed_token (${gen.status})`);
  const r = await fetch(`${BASE}/auth/v1/verify`, {
    method: 'POST',
    headers: { apikey: ANON, 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', token_hash: hash }),
  });
  const b = await r.json().catch(() => ({}));
  if (!b?.access_token) throw new Error(`verify for ${email} returned no access_token (${r.status})`);
  return b.access_token;
};
```

Four steps: **management PAT → `GET /v1/projects/{ref}/api-keys?reveal=true` (service_role + anon) → `POST /auth/v1/admin/generate_link {type:'magiclink',email}` with service_role → `POST /auth/v1/verify {type:'magiclink',token_hash}` with anon key → `access_token`.** No password is read or set. `generate_link` returns the link, does not send mail.

Identity creation (line 159, inside `try`):
```js
for (const e of Object.values(EMAIL)) {
  await admin('/admin/users', { method: 'POST',
    body: JSON.stringify({ email: e, email_confirm: true, password: crypto.randomUUID() + 'Aa1!' }) });
}
created = true;
```

Two request helpers, both reusable as-is:
- `fn(name, token, body)` :102 — `POST ${BASE}/functions/v1/${name}`, headers `{apikey: ANON, authorization: Bearer token, content-type}`; returns `{status, text, json}`.
- `rest(path, {token, anonOnly})` :113 — `GET ${BASE}/rest/v1/${path}`, `{apikey: ANON, authorization: Bearer (anonOnly?ANON:token||ANON)}`; returns `{status,text,json,rows}`.

### 1b. Namespace and fixtures

```js
const NS = 'zz-phase-d-s8';                                                      // :55
const EMAIL = {
  custA: `${NS}-cust-a@example.invalid`,  custB: `${NS}-cust-b@example.invalid`,
  supA:  `${NS}-sup-a@example.invalid`,   supB:  `${NS}-sup-b@example.invalid`,
  nobody:`${NS}-nobody@example.invalid`,
};
```
Convention: `ZZ DEMO — …` in text columns, `@example.invalid` in e-mail, `zz-phase-d-*` in paths. (These are exactly the three patterns `public.fn_phase_d_fixture_residue()` scans for — see §1e.)

Tables written (lines 167–208):
| table | rows | why safe (measured trigger analysis in the file header, :16–:30) |
|---|---|---|
| `auth.users` | 5 | `/auth/v1/admin/users` |
| `public.customers` | 2 | `trg_emit_customer_registered → fn_emit()` writes one `company_event`; no HTTP/notification |
| `public.leads` | 2 | inserted `verified=false, approval_status='pending'` so neither `enrich_capability_on_approve` (net.http_post) nor `fn_assign_founding_rank` can fire |
| `public.leads.iban_doc_path` | UPDATE ×2 | **deliberately `iban_doc_path` and not `license_doc_path`** — the `reg_lead_docs` AFTER UPDATE trigger watches only `(license_doc_path, company_profile_doc_path, egr_doc_path, catalog_doc_paths)`; a watched column registers a `public.documents` row, `fn_enqueue_doc_backups` puts it in `public.doc_backups`, and cron job 88 (`dropbox_backup_scan`, every 15 min) attempts a real Dropbox upload. Measured happening twice on 23 Aug 2026 at 16:45 and 17:00:05 UTC. |

**FORBIDDEN tables, named in the file header (:22–:28):** `public.inquiries` (`trg_inquiry_received` writes `public.notifications`), `public.quotes` (`trg_new_quote_sms`), `public.transactions` (`trg_reveal_receipt`). This is why PD-AUTH-002 / PD-PRIV-004 / PD-QUOTE-001 / PD-QUOTE-004 cannot be discriminated today.

### 1c. Watermark (verbatim, lines 130–150)

```js
// WATERMARK. Everything the hold forbids is counted before the first request and again at the end.
// net.http_request_queue DRAINS, so a queue length of 0 at the end proves nothing about what was
// posted in between — it is the same "a zero cannot tell a dead guard from an idle system" shape
// this estate keeps finding. The durable record is net._http_response, so the watermark is a CLOCK
// and the assertion counts responses logged after it.
const base = (await sql(`select
  (select now())::text                                      as t0,
  (select count(*) from public.notifications)              as notif,
  (select count(*) from public.llm_attempt)                as llm,
  (select coalesce(max(id),0) from net.http_request_queue)  as httpmax,
  (select count(*) from net.http_request_queue)             as httpq,
  (select count(*) from public.doc_backups)                 as docbackups,
  (select count(*) from public.leads)                       as leads,
  (select count(*) from public.customers)                   as customers,
  (select count(*) from public.inquiries)                   as inquiries,
  (select count(*) from public.quotes)                      as quotes,
  (select count(*) from public.transactions)                as transactions,
  (select count(*) from public.company_event)               as events`))[0];
```

### 1d. Zero-effect assertion (verbatim, lines 650–681)

```js
const end = (await sql(`select
  (select count(*) from public.notifications)              as notif,
  (select count(*) from public.llm_attempt)                as llm,
  (select count(*) from net.http_request_queue where id > ${base.httpmax}) as newhttp,
  (select count(*) from net._http_response where created > ${lit(base.t0)}::timestamptz) as http_done,
  (select coalesce(string_agg(distinct left(coalesce(content,''),40), ' | '), '(none)')
     from net._http_response where created > ${lit(base.t0)}::timestamptz) as http_bodies,
  (select count(*) from public.doc_backups)                 as docbackups,
  (select count(*) from public.leads)                       as leads,
  (select count(*) from public.customers)                   as customers,
  (select count(*) from public.inquiries)                   as inquiries,
  (select count(*) from public.quotes)                      as quotes,
  (select count(*) from public.transactions)                as transactions,
  (select count(*) from public.fn_phase_d_fixture_residue()) as residue,
  (select count(*) from auth.users where email like ${lit(NS + '%')}) as canary_users,
  (select count(*) from public.company_event) as events`))[0];

const drift = [];
if (end.notif !== base.notif) drift.push(`notifications ${base.notif} -> ${end.notif}`);
if (end.llm !== base.llm) drift.push(`llm_attempt ${base.llm} -> ${end.llm}`);
if (Number(end.newhttp) !== 0) drift.push(`net.http_request_queue gained ${end.newhttp}`);
// Scheduled read-only monitoring stays active under the hold, so a non-zero response count is
// reported for inspection rather than failed on; the bodies are printed so it can be judged.
console.log(`  outbound HTTP logged during the run: ${end.http_done} -> ${end.http_bodies}`);
if (end.docbackups !== base.docbackups) drift.push(`doc_backups ${base.docbackups} -> ${end.docbackups}`);
if (end.leads !== base.leads) drift.push(`leads ${base.leads} -> ${end.leads}`);
if (end.customers !== base.customers) drift.push(`customers ${base.customers} -> ${end.customers}`);
if (end.inquiries !== base.inquiries) drift.push(`inquiries ${base.inquiries} -> ${end.inquiries}`);
if (end.quotes !== base.quotes) drift.push(`quotes ${base.quotes} -> ${end.quotes}`);
if (end.transactions !== base.transactions) drift.push(`transactions ${base.transactions} -> ${end.transactions}`);
if (Number(end.residue) !== 0) drift.push(`fn_phase_d_fixture_residue ${end.residue}`);
if (Number(end.canary_users) !== 0) drift.push(`${end.canary_users} canary auth user(s) survived`);
if (end.events !== base.events) drift.push(`company_event ${base.events} -> ${end.events}`);
...
if (drift.length || failed.length) process.exit(1);
```

Note: `net._http_response` count is **printed, not failed on** (read-only cron monitoring stays live under the hold). `net.http_request_queue` new rows **do** fail.

### 1e. Cleanup (verbatim, lines 595–647)

```js
} finally {
  // CLEANUP. A cleanup scoped to the table you happened to look at is not a cleanup: every table
  // this file can touch is named here, and the counts are re-read afterwards.
  // EACH DELETE IS ITS OWN STATEMENT. The first version of this cleanup sent all of them as one
  // batch and included `delete from storage.objects`, which storage.protect_delete() refuses —
  // and because the refusal aborted the WHOLE batch, none of the other deletes ran either and the
  // canaries survived. A cleanup that stops at the first refusal is not a cleanup.
  const emails = Object.values(EMAIL).map(lit).join(',');
  const steps = [
    `delete from public.notifications where status = 'pending' and (to_email in (${emails})
       or lead_id in (select id from public.leads where claimed_by in (${emails})))`,
    `delete from public.company_event where entity_id in (select id::text from public.customers where email in (${emails}))`,
    `delete from public.company_event where entity_id in (select id::text from public.leads where claimed_by in (${emails}))`,
    `delete from public.doc_backups where path like 'zz-phase-d-section8/%'`,
    `delete from public.documents where path like 'zz-phase-d-section8/%'`,
    `delete from public.leads where claimed_by in (${emails}) or email in (${emails})`,
    `delete from public.customers where email in (${emails})`,
  ];
  for (const s of steps) await sql(s).catch((e) => console.error(`cleanup step failed: ${e.message.slice(0, 200)}\n  ${s.slice(0, 120)}`));

  // storage.objects is deleted through the Storage API, never through SQL: storage.protect_delete()
  // refuses a direct delete precisely so orphaned objects cannot be created this way.
  const leftover = await sql(`select name from storage.objects where name like ${lit(NS + '/%')}`).catch(() => []);
  for (const o of (Array.isArray(leftover) ? leftover : [])) {
    const bucket = (await sql(`select bucket_id from storage.objects where name=${lit(o.name)} limit 1`))[0]?.bucket_id;
    if (!bucket) continue;
    await fetch(`${BASE}/storage/v1/object/${bucket}/${encodeURI(o.name)}`, {
      method: 'DELETE', headers: { apikey: SERVICE, authorization: `Bearer ${SERVICE}` },
    }).catch(() => {});
  }

  if (created) {
    for (const e of Object.values(EMAIL)) {
      const found = await admin(`/admin/users?filter=${encodeURIComponent(e)}`);
      for (const u of (found.body?.users ?? [])) if (u.email === e) await admin(`/admin/users/${u.id}`, { method: 'DELETE' });
    }
  }
}
```

Four hard-won rules the new capability must inherit: (1) one statement per delete — the management endpoint commits each statement independently and a batch refusal kills all of it; (2) `storage.objects` only via the Storage API (`storage.protect_delete()`); (3) notifications deleted **only** while `status='pending'` — a delivered row is evidence; (4) `company_event` deleted narrowly by `entity_id`, never broadly (a broad delete would erase a real backup-failure event).

### 1f. Recording (`--write`, lines 703–711)

```js
if (WRITE) {
  const rows = results.map((r) => `(${lit(r.id)},${lit(r.probe)},${lit(r.verdict)},${lit(r.observed)},${r.http_status == null ? 'null' : Number(r.http_status)})`).join(',');
  await sql(`insert into public.phase_d_section8_probe_result (probe_id, probe, verdict, observed, http_status)
             values ${rows}
             on conflict (probe_id) do update set probe=excluded.probe, verdict=excluded.verdict,
               observed=excluded.observed, http_status=excluded.http_status, ran_at=now();`);
}
```
`record()` truncates `observed` to 900 chars (:125). Verdict vocabulary in code: `REFUSED_AS_REQUIRED` / `NOT_REFUSED` / `NOT_RUN` / `NOT_DISCRIMINATED`.

### `fn_phase_d_fixture_residue()` (live definition — the residue oracle the harness asserts on)
```sql
CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_residue()
 RETURNS TABLE(relation text, surviving_rows bigint) LANGUAGE plpgsql STABLE
 SET search_path TO 'public','pg_temp' AS $function$
declare r record; v_n bigint; v_pred text;
begin
  for r in select distinct wm.target_relation as rel from public.phase_d_object_write_map wm
           union select 'public.phase_d_object_record'
  loop
    v_pred := (select string_agg(format(
                 '(coalesce(%I::text,'''') like ''ZZ DEMO — %%'' or coalesce(%I::text,'''') like ''%%@example.invalid'' or coalesce(%I::text,'''') like ''zz-phase-d-%%'')',
                 a.attname, a.attname, a.attname), ' or ')
               from pg_attribute a where a.attrelid = r.rel::regclass and a.attnum > 0 and not a.attisdropped
                and format_type(a.atttypid, a.atttypmod) in ('text','character varying','jsonb'));
    if v_pred is null then continue; end if;
    execute format('select count(*) from %s where %s', r.rel, v_pred) into v_n;
    if v_n > 0 then relation := r.rel; surviving_rows := v_n; return next; end if;
  end loop;
end $function$
```
Currently returns **0 rows**. It only scans relations named in `phase_d_object_write_map` plus `phase_d_object_record` — it does **not** cover `customers`/`leads`/`auth.users`, which is why the harness counts those separately.

---

## 2. `public.phase_d_section8_probe_result` — schema + all 23 rows

```
probe_id    text  NOT NULL   PRIMARY KEY
probe       text  NOT NULL
verdict     text  NOT NULL   CHECK (verdict in ('REFUSED_AS_REQUIRED','NOT_REFUSED','NOT_RUN','NOT_DISCRIMINATED'))
observed    text  NULL
http_status integer NULL
ran_at      timestamptz NOT NULL DEFAULT now()
```
Grants: SELECT/INSERT/UPDATE/DELETE to `postgres` and `service_role` only. `anon`/`authenticated` revoked; TRUNCATE revoked from all three.

All 23 rows, `ran_at = 2026-08-23 17:06:52.151635+00` (identical for every row — one run):

| probe_id | verdict | http | observed (≤200 chars) |
|---|---|---|---|
| P1-identity-binding | REFUSED_AS_REQUIRED | 200 | each bearer resolved to its own account and only its own: A->zz-phase-d-s8-cust-a@example.invalid, B->zz-phase-d-s8-cust-b@example.invalid. The identity is taken from the JWT, never from the request b |
| P1-no-autovivify | REFUSED_AS_REQUIRED | 403 | an authenticated identity with no customer account got 403 and 0 row(s) were created for it |
| P1-object-scope | REFUSED_AS_REQUIRED | 403 | activity on an inquiry not owned by the caller -> 403 Not your inquiry. BOUNDED: with 0 inquiries on the estate this exercises the ownership branch, not discrimination between two real inquiries |
| P2-cross-write | REFUSED_AS_REQUIRED | 200 | supplier A named supplier B's id on a settings write -> 200; B's locale is UNCHANGED (en) and the write landed on A's own row instead (A locale=ar), because the target id is resolved from claimed_by o |
| P2-document-scope | REFUSED_AS_REQUIRED | 200 | each supplier holds ONE document of its own. supplier_portal documents as A -> 200 and DOES carry A's own path; the same call naming B's id -> 200, bodies IDENTICAL; naming B's path directly -> 200. B |
| P2-identity-binding | REFUSED_AS_REQUIRED | 200 | each supplier bearer resolved to its own leads row via claimed_by and only its own (A=40476, B=40477); the client-supplied id is never consulted |
| P3-opportunities-rpc-anon | REFUSED_AS_REQUIRED | 401 | fn_supplier_opportunities called with the anon key -> 401 {"code":"42501",…"permission denied for function fn_supplier_opportunities"} |
| P3-safe-surface-shape | REFUSED_AS_REQUIRED | null | identity columns present on inquiries_supplier_safe: (none) |
| **P3-supplier-surface-body** | **NOT_DISCRIMINATED** | 200 | supplier_api inbox -> 200, supplier_portal opportunities -> 200, direct /rest/v1/inquiries -> 403/null row(s). Bodies scanned for the two known customer identities: no identity value appeared in any b |
| P4-kyc-bucket-read | REFUSED_AS_REQUIRED | 403 | a customer bearer naming supplier-docs verbatim: os_api file -> 403, os_ops file -> 403, os_api files(entity=supplier) -> 403 |
| P4-kyc-doc-read | REFUSED_AS_REQUIRED | 404 | customer_documents get on documents.id=10 (ref_table='inquiries') as a customer that owns nothing -> 404, and the body carries NO file_url; the vault listing returned 200 |
| P5-no-role-readonly | REFUSED_AS_REQUIRED | 403 | an authenticated identity that maps to no active canonical role -> os_api ping 403 |
| P5-non-admin-mutation | REFUSED_AS_REQUIRED | 403 | a customer bearer attempting an admin mutation on os_api -> 403 forbidden |
| P5-supplier-admin-mutation | REFUSED_AS_REQUIRED | 403 | a supplier bearer attempting an admin mutation on os_api -> 403 |
| P6-rpc-bypass | REFUSED_AS_REQUIRED | null | 14 kernel, Phase D and supplier routines called directly as anon and as authenticated, each with its REAL argument list: 28 refused on permission, 0 not exposed to the schema cache at all (PGRST202), |
| P6-table-bypass | REFUSED_AS_REQUIRED | null | 6 NON-EMPTY sensitive tables read directly with the anon key and with a real authenticated customer bearer; every one returned 0 rows against a service_role control that proves the rows exist: custome |
| P7-expired-url | REFUSED_AS_REQUIRED | 400 | a 1-second URL for supplier-docs answered 200 while valid and 400 after expiry |
| P7-unowned-insert | REFUSED_AS_REQUIRED | 406 | an authenticated customer bearer inserting directly into storage.objects -> 406 |
| P7-wrong-owner-path | REFUSED_AS_REQUIRED | 403 | os_api file names bucket+path verbatim from the body and performs NO ownership check on it; the only thing between a caller and any private object is the admin gate, which answered 403 to a customer b |
| P8-executable-content | REFUSED_AS_REQUIRED | 400 | an MZ executable declared application/x-msdownload against receipt-files -> 400 {"statusCode":"415","error":"invalid_mime_type",…} |
| P8-mime-allowlist | REFUSED_AS_REQUIRED | 400 | bucket receipt-files allows [application/pdf, image/jpeg, image/png, text/html]; a ZIP declared application/zip and named .pdf -> 400 {"statusCode":"415",…} |
| P8-size-limit | REFUSED_AS_REQUIRED | 400 | 15 MB limit on receipt-files; 15.00 MB of application/pdf -> 400 {"statusCode":"413","error":"Payload too large",…"EntityTooLarge"} |
| P8-upload-residue | REFUSED_AS_REQUIRED | null | 0 object(s) under zz-phase-d-s8/ survived the three refused uploads |

22 × REFUSED_AS_REQUIRED, 1 × NOT_DISCRIMINATED, 0 × NOT_REFUSED, 0 × NOT_RUN.

---

## 3. The defect-map mechanism

### `public.phase_d_section8_defect_map`
```
defect_id     text PRIMARY KEY
probe_id      text NOT NULL      -- no FK to probe_result; a plain text join key
justification text NOT NULL
```
11 rows (all of them):

| defect_id | probe_id | justification (verbatim) |
|---|---|---|
| PD-AUTH-001 | P6-table-bypass | anon AND a real authenticated customer bearer selected public.customers directly while it held two live rows, against a service_role control proving the rows existed; both read 0. |
| PD-AUTH-002 | P2-document-scope | NOT DISCRIMINATED (D44). The probe compared supplier A's own documents response with the response to the same call naming supplier B's id and found them byte-identical. supplier_portal takes no owner id from the body, so an identical body is the only possible answer and answers nothing about the defect; both fixtures also held zero documents. |
| PD-AUTH-003 | P5-non-admin-mutation | a real customer bearer attempted an admin mutation on os_api and was refused 403. |
| PD-AUTH-004 | P5-no-role-readonly | an authenticated identity resolving to no active canonical role was refused 403 by the Command Center. |
| PD-FILE-001 | P8-mime-allowlist | a ZIP declared application/zip and named .pdf was refused by the bucket MIME allow-list… |
| PD-FILE-002 | P8-size-limit | an upload over the bucket's declared file_size_limit was refused 413 by storage itself. |
| PD-FILE-003 | P8-executable-content | an MZ executable declared application/x-msdownload was refused 415 invalid_mime_type. |
| PD-FILE-004 | P7-expired-url | a signed URL was minted with a 1 second TTL, replayed successfully while valid, and refused after expiry. |
| PD-FILE-005 | P7-unowned-insert | an authenticated customer bearer inserted directly into storage.objects under a path it does not own and was refused. |
| PD-PRIV-003 | P7-wrong-owner-path | a customer bearer and an anonymous caller each named a private bucket path belonging to another party on the two minters that accept a caller-supplied path; both were refused. |
| PD-PRIV-004 | P3-supplier-surface-body | NOT DISCRIMINATED (D44). …With 0 inquiries, 0 customers and 0 inquiry_matches on the estate there was no identity to find, so the scan proves the surfaces are empty, not that a populated payload is masked. |

### CRITICAL CORRECTION: `fn_phase_d_run_injected_defects()` does **NOT** read either table

The header comment in `run_section8_security_probes.mjs:44` ("recorded in `phase_d_section8_probe_result`, which `fn_phase_d_run_injected_defects()` reads") is **false**. Measured: the live body of `fn_phase_d_run_injected_defects()` contains zero occurrences of `section8`, `probe_result` or `defect_map`. It hard-codes all 20 §8 defects as `NOT_RUN` in a `for … values(...)` loop:

```sql
  -- ---- The categories that need section 8 ------------------------------------------------------
  for v_key, v_msg in
    select * from (values
      ('PD-AUTH-001','AUTH: needs an unauthenticated HTTP request against a deployed customer endpoint …'),
      ('PD-AUTH-002','AUTH: needs supplier A''s bearer token against supplier B''s document URL. …'),
      …
      ('PD-PRIV-004','PRIVACY: needs a supplier bearer token calling the raw inquiry endpoint and the response body.'),
      …
    ) as t(a,b)
  loop
    defect_id := v_key; category := split_part(v_msg, ':', 1); status := 'NOT_RUN';
    observed := null; blocker := 'SECTION 8 NOT BUILT — ' || v_msg;
    return next;
  end loop;
```

**The overlay lives in the wrapper `public.fn_phase_d_injected_defect_report()` (live body, verbatim):**

```sql
CREATE OR REPLACE FUNCTION public.fn_phase_d_injected_defect_report()
 RETURNS TABLE(defect_id text, category text, status text, observed text, blocker text)
 LANGUAGE sql
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select r.defect_id,
         r.category,
         coalesce(p.verdict, r.status)                                            as status,
         case when p.probe_id is null then r.observed
              else p.observed || ' [§8 probe ' || p.probe_id
                   || coalesce(' · HTTP ' || p.http_status::text, '')
                   || ' · executed ' || to_char(p.ran_at at time zone 'utc','YYYY-MM-DD HH24:MI') || 'Z]'
         end                                                                      as observed,
         case when p.probe_id is not null then null
              else replace(r.blocker,
                     'SECTION 8 NOT BUILT — ',
                     'SECTION 8 WAS EXECUTED 2026-08-19 AND DOES NOT REACH THIS CASE — ')
         end                                                                      as blocker
    from public.fn_phase_d_run_injected_defects() r
    left join public.phase_d_section8_defect_map m on m.defect_id = r.defect_id
    left join public.phase_d_section8_probe_result p
           on p.probe_id = m.probe_id and p.verdict <> 'NOT_RUN'
$function$
```

### What a defect row needs to move NOT_RUN → REFUSED_AS_REQUIRED — exactly four conditions

1. A row in `phase_d_section8_defect_map` whose `defect_id` equals the runner's `defect_id` (the runner must still emit that defect_id — it emits all 75).
2. A row in `phase_d_section8_probe_result` whose `probe_id` equals `defect_map.probe_id`.
3. That probe row's `verdict <> 'NOT_RUN'` (the join predicate). Note the join admits `NOT_REFUSED` and `NOT_DISCRIMINATED` too — those propagate verbatim.
4. `verdict = 'REFUSED_AS_REQUIRED'` for the green status.

Consequence: `blocker` becomes NULL and `observed` becomes the probe's observed + `[§8 probe <id> · HTTP <n> · executed <ts>Z]`. Nothing else in the estate is consulted. Only `service_role`/`postgres` can write either table.

**Two downstream constraints on any new probe (from `build_injected_defect_result.mjs`):**
- Per-category export asserts `got.length !== 5 → exit 1` — every category must yield exactly 5 rows, and the runner still owns the row population.
- Free text is capped at 240 chars via `fn_phase_d_bounded()`, and the whole per-category payload must stay under 1800 chars or the build raises `PHASE_D_DEFECTS_OVERFLOW`. A long `observed` written by a new probe can break the deliverable build.

**Reversion hazard (documented in `scripts/sql/phase_d_d44_…sql`):** `run_section8_security_probes.mjs --write` **upserts on `probe_id`**, so re-running §8 unchanged silently overwrites any hand-applied SQL correction to a probe verdict.

---

## 4. `scripts/phase_d/discharge_d0_auth_debt.mjs` (130 lines) — the recipe

Identical minting recipe, older and shorter. Same four steps: PAT from `SUPABASE_ACCESS_TOKEN` or `C:/Users/Opera/.supabase/access-token` → `mgmt('/api-keys?reveal=true')` → `admin('/admin/generate_link', {type:'magiclink', email})` → `POST /auth/v1/verify {type:'magiclink', token_hash}` with the anon key → `access_token`. `bearerFor()` is byte-for-byte the same function as §8's (modulo `service`/`anon` vs `SERVICE`/`ANON` casing).

Differences worth reusing:
- **Founder positive case:** `bearerFor('management@quotesdone.com')` — held active/kind=email in `public.phase_c_founder_identity`. No canary needed for the positive arm.
- **Canary:** `zz-phase-d-canary@example.invalid`, one auth identity only, no business rows.
- **Read-back-verified cleanup** — the pattern §8 does not have:
```js
} finally {
  if (canaryId) {
    const del = await admin(`/admin/users/${canaryId}`, { method: 'DELETE' });
    const check = await admin(`/admin/users/${canaryId}`);
    console.log(`canary cleanup: delete -> ${del.status}, read-back -> ${check.status} `
      + `(404 means the identity is gone; anything else means it is NOT and must be removed by hand)`);
  }
}
```
- Harmless probe action: `POST os_api {action:'ping'}` with `{apikey: anon, authorization: Bearer token}`.

---

## 5. Supplier/customer-facing edge functions that read `inquiries`

`ls supabase/functions` → 195 directories. The four relevant: `supplier_api` (902 lines), `supplier_portal` (592), `customer_api` (1304), `customer_portal` (228).

All four resolve identity identically — **from the JWT, never from the body**:
```ts
const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '');
const { data: { user } } = await admin.auth.getUser(jwt);
if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
const email = user.email.toLowerCase();
```
(`supplier_portal/index.ts:37–41`, `supplier_api/index.ts:241–243`, `customer_api/index.ts:532–534`.)

### THE supplier-facing projection of an inquiry — `supplier_api` action `inbox`

`supabase/functions/supplier_api/index.ts:655–753`. This is the route that matters for **PD-PRIV-004**.

```ts
if (action === 'inbox') {                                                              // :655
  const { data: sup } = await admin.from('leads').select('id,approval_status').eq('claimed_by', email).maybeSingle();
  if (!sup) return J({ error: 'claim your company first' }, 400);
  const { data: matches } = await admin.from('inquiry_matches').select('inquiry_id').eq('supplier_id', sup.id);
  const ids = (matches || []).map((m) => m.inquiry_id);
  if (!ids.length) return J({ inquiries: [], approval_status: sup.approval_status });   // :658  ← the short circuit
  const { data: inq } = await admin.from('inquiries_supplier_safe')                     // :668
    .select('id,category,emirate,summary,spec,created_at,budget,scope_type,brief_source,boq,boq_confidence,drawing_redacted_paths,status,outcome,hired_supplier_id')
    .in('id', ids).order('created_at', { ascending: false }).limit(25);
```
Then `quotes` (:669), `transactions` for the reveal gate (:675), and the raw owner lookup used **only** to feed the scrubber and never emitted:
```ts
{ const { data: owners, error: eOwners } = await admin.from('inquiries').select('id,customer_id').in('id', ids);  // :709
  if (eOwners) ownerResolved = false;
  else for (const o of (owners || [])) if (o?.customer_id) ownerOf[String(o.id)] = String(o.customer_id); }
```
Response shape (:751): `{id, category, emirate, summary, spec, created_at, budget, scope_type, brief_source, boq, boq_confidence, drawing_file_name:null, drawing_file_url:null, drawing_pages, status, concluded, you_won, quote}` — `customer_id` never appears. Two independent layers: write-time masking into `*_masked` columns, plus `scrubIdentity()` at retrieval, fail-closed (drops text if the owner cannot be resolved and logs an `agent_runs` error row `signal:'buyer_identity_unresolved'`).

`public.inquiries_supplier_safe` (view, live def measured) — 21 columns, **no `customer_id`, no email/phone/name**:
`id, category, emirate, role_needed, status, created_at, scope_type, trades, keywords, brief_source, urgency, boq_confidence, drawing_redacted_paths, outcome, hired_supplier_id, summary, raw_input, budget, spec, boq, completeness`.
It serves `summary_masked / raw_input_masked / budget_masked / spec_masked / boq_masked / completeness_masked` under the unmasked names, with a `LEFT JOIN LATERAL` preferring the newest `inquiry_supplier_brief.brief` version when one exists.

Other supplier-facing inquiry surfaces:
- `supplier_portal` action `opportunities` (:295) → `admin.rpc('fn_supplier_opportunities', { p_lead_id: supId })` — `supId` from JWT.
- `supplier_portal:68` reads `inquiries` (id + status only) for a counter; `:63` reads `inquiry_matches`.
- `supplier_api` action `projects` (:757) → `transactions … select('revealed_at,quote_amount,inquiries(category,emirate,summary)')` — post-reveal only, raw table, embedded.

Customer side (`customer_api`): 18 raw `inquiries` reads/writes, all scoped `.eq('customer_id', cust.id)` or ownership-checked (`:91`, `:828`, `:1085`, `:1118`). `customer_portal` reads only aggregates and `inquiry_matches` (`:111`).

**PD-PRIV-004 blocker restated as measured:** production now holds `inquiries=0, inquiry_matches=0, customers=0, quotes=0` (leads=20465, documents=10, notifications=666). `inbox` returns `{inquiries: []}` at line 658 before it ever touches the safe view. Discriminating PD-PRIV-004 requires **one `customers` row, one `inquiries` row carrying a known identity string, and one `inquiry_matches` row** — and `public.inquiries` INSERT fires `trg_inquiry_received`, which writes a `public.notifications` row whenever the owning customer has an e-mail (and it must have one, or `customer_api` cannot resolve it). That is the exact tension the new committed-fixture capability has to resolve.

---

## 6. Two concurrent database sessions — **YES, and measured**

**No `pg` driver exists.** Grep across `**/*.{mjs,js,ts,json,yml,yaml,env,md}` for `from 'pg'|require('pg')|new Client(|new Pool(|DATABASE_URL|POSTGRES_URL|pooler.supabase` → **no matches**. Grep for `5432|6543|pgbouncer|deno-postgres|postgres.js|db.htdblwldjkcgjvmqkbeh|connectionString` → only `graphify-out` hash noise plus one prose mention in `supabase/schema/README.md:34`. `package.json` has **no `pg`, no `postgres`, no `pg-pool`** dependency (deps are Next/React/Radix/`@supabase/supabase-js` 2.110.8 only). **There is no direct Postgres connection string in this repo.**

**But the existing management-API helper already gives two concurrent sessions.** `scripts/phase_b/lib/db.mjs` `sql()` is one `POST https://api.supabase.com/v1/projects/{ref}/database/query` per call; concurrent calls land on **distinct backends**.

Measurement A (`scripts/tmp_diag/s8_conc_probe.mjs`, two `Promise.all` calls each `pg_sleep(3)`):
```json
{"wall_ms":4969,
 "a":{"tag":"A","pid":1682555,"t_start":"2026-08-23 19:01:30.496923+00","active_probes":2,"t_end":"2026-08-23 19:01:33.499322+00"},
 "b":{"tag":"B","pid":1682554,"t_start":"2026-08-23 19:01:30.358950+00","active_probes":1,"t_end":"2026-08-23 19:01:33.361324+00"}}
```
Distinct pids; fully overlapping intervals; A's `pg_stat_activity` saw 2 active probe backends at once.

Measurement B — a **real lock race** (`scripts/tmp_diag/s8_conc_probe2.mjs`): two concurrent `DO` blocks each taking `pg_advisory_xact_lock(918273645)` then `pg_sleep(2)`:
```json
{"total_wall_ms":5943,
 "a":"QDLOCK A pid=1682591 waited_ms=2002 end=2026-08-23 19:01:57.693024+00",
 "b":"QDLOCK B pid=1682592 waited_ms=3897 end=2026-08-23 19:01:59.696329+00"}
advisory locks still held: [{"n":0}]
```
B waited 3897 ms = ~1.9 s blocked on the lock A held, then its own 2 s. **They serialised.** This proves three things at once: (i) two distinct backends, (ii) each management call is its own transaction (an *xact*-scoped lock contended across them and released at each call's end), (iii) zero residue — 0 advisory locks remained.

**So PD-CONC-001 ("two workers claim the same task, one winner") is executable with the existing helper.** The current blocker text in `fn_phase_d_run_injected_defects()` is out of date on the capability question but right on the residue question:
> `'a true race needs TWO concurrent database sessions. Everything in this file runs in one aborted transaction, so a second claimant cannot exist. Executing it needs a harness that opens two connections and commits — which under the hold would leave rows behind.'`

The real remaining constraint is only the second clause: a management call **auto-commits**, so the winner's claim row commits and must be cleaned up by the §8 finally-pattern (or the whole DO block must end in `raise exception`, which aborts the winner too and destroys the evidence). Shape that works: each racer is one `DO` block that claims, then `raise exception 'QDRACE …'` reporting whether it won — the aborts leave nothing, and the lock contention is still real (proved above).

---

## Files the parent will want

- `C:\Users\Opera\quotesdone\scripts\phase_d\run_section8_security_probes.mjs` — auth :64–100, fixtures :159–208, watermark :137, probes :218–592, cleanup :595–647, zero-effect :650–701, write :703–711
- `C:\Users\Opera\quotesdone\scripts\phase_d\discharge_d0_auth_debt.mjs` — minimal auth recipe + read-back-verified canary delete
- `C:\Users\Opera\quotesdone\scripts\sql\phase_d_d34_the_seven_probes_that_were_never_run.sql` — table DDL :29–64, `fn_phase_d_injected_defect_report` :70, defect_map inserts :108–121, the nine unmapped defects :123–148
- `C:\Users\Opera\quotesdone\scripts\sql\phase_d_d44_an_endpoint_that_ignores_an_id_has_not_refused.sql` — the NOT_DISCRIMINATED widening and the reversion warning
- `C:\Users\Opera\quotesdone\scripts\phase_d\build_injected_defect_result.mjs` — the 5-rows-per-category and 240/1800-char export constraints
- `C:\Users\Opera\quotesdone\scripts\phase_b\lib\db.mjs` — `sql()`/`lit()`, the only DB transport; re-exported by `scripts\phase_c\lib\db.mjs`
- `C:\Users\Opera\quotesdone\supabase\functions\supplier_api\index.ts:655-753` — the supplier-facing inquiry projection
- `C:\Users\Opera\quotesdone\scripts\tmp_diag\s8_conc_probe2.mjs` — the runnable two-session race proof

**NOT MEASURED:** whether `trg_inquiry_received` can be satisfied without a notification (e.g. a customer row with a NULL e-mail) — reading the trigger body was out of scope for this pass; the file header at `run_section8_security_probes.mjs:22-25` asserts it cannot, but that assertion is prose, not a measurement I re-ran.