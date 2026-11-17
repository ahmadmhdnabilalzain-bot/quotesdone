# Duplicated helpers in the edge functions

Owner: it_engineer. Measured 10 Nov 2026 on `it_engineer-code-organised-for-an-auditor` (base `origin/main` 6f9ebbd9b).
Register rows: [tech-debt.md](tech-debt.md) TD-04 (JSON response helper), TD-05 (CORS literal), TD-06 (service-role
client), TD-07 (secret reader).

## How it was measured

Every top-level `function name(` and `const name = (...) =>` in `supabase/functions/**/*.ts`, tests, checks and fixtures
excluded, was read to the end of its body; comments were removed and whitespace collapsed, and the bodies were grouped
by name and by the hash of that text. **An exact duplicate** is two or more definitions with the same name and the
same normalised text. A body that names a variable of its own module (`admin`, `CORS`) is not self-contained: the
same text can mean different things in different files, so it is listed as a near-duplicate even when the text matches.

## Consolidated (exact, self-contained)

| helper | copies | now lives in | files changed |
|---|---:|---|---:|
| `J(o, s = 200)`: a JSON `Response` with no CORS headers | 18 | `_shared/json_response.ts` | 18 |
| `secretOk(v)`: the stored secret is a real value (fail-closed guard, 27 Jul 2026) | 13 | `_shared/internal_auth.ts`, beside `requireInternal` | 13 |

31 definitions became 2, in **24 edge functions** (7 held both): ai_gateway, backup, cad_convert,
conversation_archive, doc_extract, drawing_boq, drawing_redact, dropbox_backup, email_cron, email_triage,
license_extract, marketing_channels, marketing_outreach, mobile_otp, quote_extract, resend_inbound, resend_webhook,
sanctions_screen, send_outbox, send_sms, send_whatsapp, site_error_ingest, wa_status, wa_template_setup. A module that
exported its copy to its siblings (`ai_gateway/shared.ts`, `resend_inbound/lib/runtime.ts`, `send_whatsapp/client.ts`)
now re-exports the shared one, so no sibling import changed. Each function's code is otherwise byte-identical.
These functions differ from what is deployed until they are redeployed; their behaviour does not.

## Not merged: near-duplicates and look-alikes, with the reason

| helper | definitions | functions | distinct bodies | largest identical group | why it was left |
|---|---:|---:|---:|---:|---|
| `J` (the other variants) | 66 | 65 | 12 | 22 | the 18 self-contained copies were merged (above); the other 48 copies, in 11 variants, put the module's own `CORS` / `cors` constant in the headers, and those constants hold 10 different values (44 constants, measured by literal); merging them would change which origins each function answers |
| `sec` | 43 | 42 | 15 | 8 | reads `app_secrets` through the module's own `admin` client, in 15 different bodies |
| `logRun` | 23 | 23 | 23 | 1 | 23 different bodies: each writes its own function's run log |
| `esc` | 16 | 11 | 10 | 4 | 10 different bodies under one name; the identical pairs escape for different targets (`_shared/alias_pattern.ts` builds a regular expression, `conversation_archive/document.ts` writes HTML) |
| `parseJson` | 9 | 8 | 7 | 3 | MERGED 17 Nov 2026 with the 31 inline copies: see "The JSON object in a model's reply" below |
| `rl` | 8 | 8 | 5 | 4 | calls `rl_check` through the module's own `admin`; 5 different bodies |
| `b64ToBytes` | 7 | 5 | 6 | 2 | 6 different bodies; the identical pair is supplier_api and supplier_portal |
| `b64` | 6 | 2 | 4 | 3 | 4 different bodies |
| `clip` | 6 | 5 | 5 | 2 | 5 different bodies |
| `logThrottled` | 6 | 6 | 6 | 1 | 6 different bodies |
| `isArabic` | 5 | 2 | 5 | 1 | 5 different bodies |
| `stripHtml` | 5 | 4 | 5 | 1 | 5 different bodies |
| `r2` | 5 | 3 | 2 | 4 | one-line `Math.round(n * 100) / 100`; 3 of the 4 identical copies are already in `_shared` and round money, measurements and VAT: same arithmetic, different subjects |
| `sha256` | 5 | 4 | 5 | 1 | 5 different bodies |
| `whoami` | 5 | 5 | 5 | 1 | 5 different bodies |
| `secret` | 5 | 5 | 1 | 5 | 5 identical bodies, but each reads through its own module's `admin` (reveal_invoice, stripe_checkout, stripe_confirm, stripe_webhook, supplier_pay) |
| `sleep` | 4 | 4 | 1 | 4 | one line, 4 identical copies; not worth an import each |
| `embed` | 4 | 4 | 2 | 3 | 3 identical in-worker gte-small embedders (accountant, marketing, sales_engineer) that return the vector as text; `_shared/gte_embed.ts` `embedLine` is the same session returning an array. Merging is a small wrapper, not a move: next step |
| `insert` | 3 | 2 | 1 | 3 | test fixtures |
| `supplierLabel` | 3 | 3 | 1 | 3 | 3 identical (`_shared/quote_documents/base.ts`, `customer_api/lib/inquiry_rules.ts`, `quote_compare`); the shared copy sits in a module that imports the identity scrubbers, so the two others would load them too |
| `customer` | 3 | 3 | 1 | 3 | 3 identical bodies that read through each module's own client |
| `sameSecret` | 3 | 3 | 2 | 2 | 2 identical (resilience_ping, site_error_ingest), a third different (stripe_setup) |

Not functions, so outside the scan, and counted by line match on the same day:

- **service-role client** (TD-06): `const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)`
  is written out 71 times; 72 non-test files construct a client that way. One factory in `_shared` is the next step;
  it is a move of a top-level side effect into an import, so it wants its own PR with a deploy.
- **CORS literal** (TD-05): 44 top-level `CORS` / `cors` constants holding 10 different values (the two commonest
  appear 9 times each). They are not duplicates until each function's allowed origins and headers are confirmed the same.

Re-measure: the scan is ~60 lines of Node (top-level definitions, comments stripped, whitespace collapsed, grouped by
name and SHA-1); it is not committed because it is a measurement, not a gate. TD-04 can become a gate the way
`every_outbound_fetch_has_a_timeout.mjs` is one: a baseline that may only go down.

## The JSON object in a model's reply (merged 17 Nov 2026, it_engineer; ledgers 1714 and 1715)

Measured on origin/main 09e43394c by grep for `/\{[\s\S]*\}/`, `indexOf('{')`/`lastIndexOf('}')` and ```` ``` ```` handling in
`supabase/functions/**` (tests excluded): **43 readers** took "the JSON object" out of a model's reply by hand; 39 now use one
reader and 4 are left on purpose (below). The reader is `_shared/model_json.ts` `parseJson(text, { exact?, wholeDecides?, escapeControls? })`, which returns a plain object or
null. `_shared/model_json.test.ts` holds each old shape verbatim and runs it against the new reader on one corpus, so every
row below is proved by execution, not by reading.

| shape (old) | where | now | difference, on what input |
|---|---|---|---|
| first `{` to last `}` (regex, or indexOf/lastIndexOf) | wa_inbound/founder_directive, wa_inbound/speculation, it_engineer/seat_exam (2), email_triage/opt_out_backstop, supplier_mailbox_reading, stranger_repeat_guard, marketing/lead_sourcing, sales_engineer/conversation_plan, sales_engineer/lib/ownership_claim, doc_extract (after its fence strip), _shared/job_question, supplier_instruction, inquiry_reading, catalogue_model, whatsapp_offer, marketing_articles (`jsonOf`, 2 callers) | default | none. speculation: a broken object's `why` reads "no reading in the answer" instead of the SyntaxError text (still an outage). seat_exam parseJudge: a reply with no `{` when zero facts were asked is unreadable (was "nothing missing") |
| whole reply (in a fence), else outermost; object only | _shared/think/validator (the owner), _shared/licence_extract, _shared/support_case_memory `summaryJson` | default (re-exported where imported) | none |
| whole reply first, its value handed on whatever it is, else outermost | drawing_redact, _shared/drawing_pixel_gate, _shared/drawing_string_reading, drawing_boq/confirm, drawing_boq/vision_count, drawing_boq/index, quote_extract, resend_inbound/lib/mail_parse, inquiry_intake/shared, supplier_onboard, quote_compare (inside its first fence) | `wholeDecides` (`?? {}` or a throw kept at the call site) | a reply that is a bare JSON array, number, string or boolean was handed on and read as an object with no fields; it is now null. The redaction gates read both as no verdict |
| ends' fences stripped, whole object or nothing, else outermost | ceo_agent/plan | `wholeDecides` | an array behind a fence (whole, half, or ```` ```JSON ````) is read for the object inside (was no plan) |
| the whole reply or a fence around all of it, nothing else | _shared/escalation_clock (2), review_decide, seat_deliberation, provider_signals | `exact` | none |
| ends' fences stripped, whole object only | _shared/marketing_judgement | default | a sentence around the object is now read (was "rejected") |
| outermost + raw line breaks in strings escaped | _shared/ai_reply | `wholeDecides` + `escapeControls` (controlsEscaped moved) | an array behind a fence (whole, half, or ```` ```JSON ````) is read for its object (was no answer) |

No copy tolerated a trailing comma; neither does the reader. **Left on purpose:** `_shared/supplier_trade_choice.ts`
`answerJson` (tries every `{`..`}` candidate for the one holding a key: more tolerant, replacing it would refuse readings),
`ai_gateway/confidence.ts` (the nearest `{` before the last `}`: a JSON tail after prose that may quote a schema),
`supplier_catalog_ingest/index.ts:311,321` (its retry loop keys on a brace being present, and it tells "no object" (an empty
catalogue) from "a broken object" (extraction_failed); one null would merge the two), `wa_inbound/founder.ts:79` (re-reads the
directive and throws on a broken object so the row records `classifier_error`).

