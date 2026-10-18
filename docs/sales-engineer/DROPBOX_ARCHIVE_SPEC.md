# The Dropbox archive — the founder's specification

His words, 9 September 2026. The Sales Engineer owns this: *"compliance belong to sales engineer
cause those signed t&c eventually belongs to customers and suppliers. also he is responsible about
the organized folders back up in dropbox."*

---

## The structure

Two main folders, one per party kind.

```
CUSTOMERS/
    customer_register.xlsx          auto-filled on every registration
    <signed T&C copies>

SUPPLIERS/
    <category of service>/          e.g. "electrical-contractors"
        <company name>/
            trade licence
            company profile
            any additional document the supplier attached voluntarily in the portal
            signed T&C
```

> "for the suppliers folder, it will have sub folders by category of service, then subfolders inside
> for every company, inside the subfolder, there will be all the documents that the supplier attached
> such as the trade license and company profile and any additional document he voluntarily attached
> on the portal along with a signed t&c document"

> "for customers main folder, there should be an excel generated that auto fills every time a
> customer registers and all his data should be there along with a clickable link for the t&C signed
> copy that have the ip address which is auto detected through the registration and of course it
> should be with our letter head and footer (quotesdone template). if the template is not built then
> it has to be"

---

## Which category names the supplier's folder — measured, not chosen

A supplier can hold several categories, so the folder name needed deciding. The data settles it:

| measurement | value |
|---|---|
| `lead_category` bindings | 18,536 |
| distinct leads bound | 13,906 |
| **rows with `is_primary`** | **13,906** |
| **distinct leads with a primary** | **13,906** |
| average categories per lead | 1.33 |
| `catalog_supplier_categories` | 86 |

**Every categorised supplier has exactly one `is_primary` category** — 13,906 primary bindings across
13,906 leads. So the folder is the primary category's slug, and it is unambiguous by construction.
86 possible subfolders.

Use `catalog_supplier_categories`, NOT `taxonomy_trade` (40 codes, a construction/MEP vocabulary) and
not the 128-family seed taxonomy from the knowledge pack, which is
[not mapped](TAXONOMY_MAPPING.md) and would break 15,305 live capability bindings if forced.

**Edge cases to handle rather than crash on:**
- a supplier with **no** category binding — 8,358 of 22,264 leads have none. They need a destination;
  decide one (an `uncategorised/` folder is honest) and never silently drop the documents.
- a company name that is not a safe path segment. `safeFilename()` in `_shared/attachment.ts` already
  forces an extension from the sniffed mime and kills traversal, NUL and bidi overrides — reuse it
  rather than writing a second sanitiser, and keep the lead id in the folder name so two suppliers
  with the same trading name cannot collide.
- a supplier whose primary category **changes**. Moving a folder is not the same as re-uploading it;
  decide and state whether the archive follows the change or records where it was filed.

---

## State at the time of writing, measured 9 Sep 2026

| | |
|---|---|
| `doc_backups` | **193 rows**, 10 Jul → **6 Sep**, 167 `done`, 26 `error` (all errors ceased 15 Jul), 144 distinct entities |
| the whole chain | `compliance_archive`, `dropbox_backup`, `dropbox_oauth`, `archive_rfq`, `backup_db` — **all deleted 8 Sep by commit `182308b`** |
| configuration | **survived intact**: `dropbox_app_key`, `dropbox_app_secret`, `dropbox_oauth_key`, `dropbox_refresh_token`, `dropbox_roots = ["/QuotesDone Backup","/quotes done"]`, plus four active credentials |
| `customers` | 1 row · `tos_ip` populated on **0** · `signed_terms_path` on **0** |
| `leads` | `accepted_terms_ip` populated on **0** · `signed_terms_path` on **0** |
| signed T&C PDFs | **none have ever been generated** |
| the QuotesDone document template | **does not exist** — `brand.ts` carries the logo and a `document` height, but no letterhead/footer template |
| XLSX generation | **none** — SheetJS is imported only to READ; `make_xlsx` was deleted |

**So the backup ran healthily for two months and has been silently dead since 8 September**, while
`qd_sign_customer` and `qd_sign_supplier` remain live triggers that POST to the missing
`compliance_archive` and discard the result. Every signature since then failed to archive with
nothing recording the failure.

---

## Rules this archive must keep

1. **It adds; it never removes.** No prune, no retention delete, nothing that can destroy a file in
   his Dropbox. If recovered code carries a retention path, it stays disabled.
2. **A signed T&C is evidence.** It carries the accepted version, the timestamp and the
   auto-detected IP, on the QuotesDone template. A copy without those is not the artefact he asked for.
3. **Never claim an archive that did not happen.** `doc_backups.status` distinguishes queued from
   uploaded from failed, and a discarded `net.http_post` result is how this failed silently the first
   time.
4. **The register is regenerated from the database**, not appended to. An append-only sheet drifts
   from the truth and cannot be repaired.
5. **Non-Latin names must survive.** `pdf_native` falls back to WinAnsi Helvetica when brand fonts are
   missing and **drops non-Latin glyphs while still returning `ok:true`** — an Arabic company name
   would vanish from a signed contract and the call would look successful. Fail loudly instead.

---

## The design as built, measured 7 Oct 2026 (founder gate, ledger 1162)

Owners: **sales_engineer files** every document; **it_engineer verifies** it is there. One uploader,
two copies: the private Supabase bucket and Dropbox (*"by back up i mean 2 points. supabase and
dropbox"*, 14 Sep 2026).

### The pipeline

1. **A document lands** in a private bucket (supplier-docs, signed-terms, drawing-files, quote-files,
   agent-docs, finance-docs, backups, ...). The trigger `z70_document_landed_kicks_backup` on leads,
   customers, inquiries and transactions kicks `dropbox_backup` at once; the 15-minute heartbeat and the
   daily pass catch the rest.
2. **`fn_enqueue_doc_backups()`** (owner rules, one `doc_backups` row per file, unique on `dedupe_key`
   and on `(bucket, path)`) decides the Dropbox path. **`fn_enqueue_doc_backups_backfill()`** files
   every other object of a registered bucket (`fn_backup_source_registry()`) under
   `Storage/<bucket>/<path>` after one hour, so an owner rule always wins.
3. **`trg_doc_backups_admit`** normalises the path (`fn_dbx_path`), drops every demo row, holds a row
   whose object does not exist yet as `waiting_source`, and (since this change) files a later document
   of an entity in the folder its first document opened.
4. **`dropbox_backup`** claims rows (`fn_doc_backups_next`: 10-minute claims, 5 attempts, backoff
   2^attempts minutes, resume first), uploads (chunked above 8 MiB, resumable), and **confirms** every
   copy with `files/get_metadata` (size AND Dropbox content_hash) before the row is `done`.
   `generated` rows (Company Details, Customer Details, Inquiry Summary) are rendered by `pdf_native`
   into `backups/generated/` first.
5. **`conversation_archive`** renders every message (email in/out, WhatsApp, portal chat) as a PDF
   into `backups/conversations/<channel>/<month>/`; `fn_conversation_archived` records it and the
   CORRESPONDENCE rule files it under its party.
6. **it_engineer**: the daily check (`dropbox_backup` mode `reconcile`, from `resilience_ping`) reads
   the new rows one by one and, since this change, **lists the whole tree** and compares it with every
   `done` row: missing, changed (content_hash) and stray. Findings go to the sales engineer as a
   `backup.refile` hand-over (`fn_it_backup_check`), which `fn_it_backup_recheck` closes only when the
   file is verified in Dropbox; the daily health probe (login, write/read/delete, space) is separate.

### The tree (entity -> type -> date)

```
/QuotesDone Backup/
  Suppliers/<primary category>/<company name> (<supplier id>)/
      Trade licence - <file>   Establishment card - <file>   Insurance - <file>   VAT certificate - <file>
      ISO certificate - <file>   Manufacturer authorization - <file>   Company profile - <file>
      Catalogue - <file>   Signed Terms & Conditions - <file>   Company Details.pdf
      Correspondence/<YYYY-MM-DD HHMM Dubai> <in|out> <channel> - <subject> #<id>.pdf
  Customers/<full name> (<customer id, 8>)/
      Signed Terms & Conditions - <file>   Customer Details.pdf   Correspondence/...
      Inquiries/<YYYY-MM-DD> <inquiry id, 8> - <status when first filed>/
          Drawing - <file>   Inquiry Summary.pdf   Correspondence/...
          Quotes/<YYYY-MM-DD> Quote <quote id, 8> - <supplier's file>   Quote <id, 8> (EN|AR) - <file>
          Payment/<reveal invoice or receipt>
          Reports/<comparison report>  <request brief>
  Finance/Revenue Invoices/<YYYY>/<YYYY-MM>/...   Month Close/   Bank Statements/   Issued Documents/   Year End/
  Company/Correspondence/<YYYY-MM>/...   (a message with no registered party)
  Company/Database Exports/<YYYY-MM>/<YYYY-MM-DD>/<table>/page_NNNN.json
  Storage/<bucket>/<original path>     (every other stored file: the sweep)
  _selftest/   (it_engineer's probes)      _sandbox/<tag>/   (a tagged ZZ DEMO run only)
```

The company stamp and signature live in the private `company-seal` bucket and reach Dropbox through
the sweep (`Storage/company-seal/...`).

### Decisions this change made

- **A folder never moves and never splits.** The spec above asked to *"decide and state whether the
  archive follows the change or records where it was filed"*: it records where it was filed. The
  supplier's, customer's and request's first document decides the folder; a later status, name or
  category change does not open a second one (measured before: 2 of 60 inquiries and 2 of 40 customers
  were split). Existing Dropbox files are not moved.
- **A customer's request documents live under the request**: the supplier's quotation, the quotation
  PDF, every reveal invoice and receipt, the comparison report and the brief (measured before: 386 owned
  files sat in `Storage/`; they stay there, new ones go to the request).
- **Demo data never reaches the real tree.** A tagged sandbox run (`fn_backup_sandbox_enqueue(tag)`,
  `dropbox_backup` ops `sandbox`, `sandbox_verify`, `sandbox_cleanup`, `conversation_archive` action
  `sandbox`) files ZZ DEMO documents that carry the tag under `_sandbox/<tag>/` only, through the same
  enqueue, uploader and listing check, and is removed afterwards.
- **No public link.** Every bucket that holds a supplier's or customer's document is private, and the
  Dropbox app holds no `sharing.*` scope (measured: `sharing/list_shared_links` and
  `sharing/create_shared_link_with_settings` are refused for the app), so the pipeline cannot publish a link.
