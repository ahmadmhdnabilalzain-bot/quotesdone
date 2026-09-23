# Supplier portal — Services API

Owner seat: `sales_engineer`. Added 15 Sep 2026; the free-text rewrite and the capability-implication
map added 18 Sep 2026 (founder instructions 438 and 439). Web portal and a future mobile app use the
same actions; the React tab (`src/components/portal/supplier/ServicesTab.tsx`) is only one client.

The screen has two halves. The **prepared checklist** is the sales engineer's own proposal about the
trades already on file, which the supplier corrects — that is the only checkbox on it. **Adding** a
service is one free text box (or the mic), rewritten by `services_rewrite` and confirmed by
`services_save_rewrite`.

All actions are `POST {SUPABASE_URL}/functions/v1/supplier_api` with a JSON body
`{ "action": "<name>", ... }` and `Authorization: Bearer <supplier user JWT>`. The supplier is the
company whose `leads.claimed_by` is the signed-in e-mail; no action accepts a `supplier_id`.
An unclaimed account gets `400 { "code": "no_company" }`.

Code: `supabase/functions/_shared/supplier_services.ts` (the actions),
`supabase/functions/_shared/service_rewrite.ts` (the rewrite itself, with `service_rewrite.test.ts`),
`supabase/functions/_shared/trade_words.ts` (the matcher both share),
`supabase/functions/supplier_api/index.ts` (routing).

Data: `public.taxonomy_trade_service` (+ its `aliases`), `public.service_implication`,
`public.supplier_capabilities` (`services`, `services_raw_text`, `services_implied`,
`services_removed`, `services_rewritten_at`), `public.supplier_capability_confirmation`,
`public.taxonomy_trade_proposal`, `public.supplier_voice_note`, `public.decision_policy`.

SQL: `scripts/sql/a_supplier_states_its_services_from_a_checklist_the_sales_engineer_prepares.sql`
(the taxonomy and the voice switch) and
`scripts/sql/a_supplier_describes_its_services_in_its_own_words_and_the_sales_engineer_rewrites_them.sql`
(the aliases, the implication map, `fn_services_effective`, `fn_service_implications` and the
service-level gate in `fn_match_capability`), proved by
`scripts/sql/a_supplier_describes_its_services_in_its_own_words_probe.sql`.

Checks: `scripts/checks/the_implication_map_has_one_seed.test.mjs` (the SQL seed and the edge JSON
seed are the same rows) and `scripts/checks/supplier_services_checklist_is_bilingual.test.mjs`.

## Types

```ts
type Service   = { key: string /* '<trade_code>.<service_code>' */; label_en: string; label_ar: string };
type Trade     = { code: string; label: string; label_ar: string | null; authority_required: string[] };
type Role      = { code: string; label: string; supplies: boolean; executes: boolean; whole_scope: boolean };
type Checklist = { code: string; label_en: string; label_ar: string | null;
                   source: 'confirmed' | 'on_file' | 'documents'; services: Service[] };
type Proposal  = { code: string; label_en: string | null; label_ar: string | null;
                   status: 'pending' | 'added' | 'rejected' | 'map_offered' | 'mapped'; mapped_to: string | null };
type Voice     = { enabled: boolean; max_seconds: 60; max_bytes: 2500000; mime: ['audio/wav', 'audio/mpeg'] };
```

## `services_state`

Request: `{ "action": "services_state" }`

Response `200`:

```ts
{ ok: true, confirmed: boolean, first_run: boolean,
  checklist: Checklist[],                      // trades the sales engineer prepared, in order
  services_by_trade: Record<string, Service[]>,// every active trade's services (for a trade the supplier adds)
  selected_services: string[],                 // keys ticked now; on first run = [] (founder_instruction 862: it starts unticked)
  extra_services: string[],                    // the supplier's own words saved before
  vocabulary: { trades: Trade[]; roles: Role[] },
  capability: object | null,                   // the supplier_capabilities row (roles, source_docs, ...)
  history: { version: number; confirmed_at: string; confirmed_via: string }[],
  trade_proposals: Proposal[],
  voice: Voice }
```

Preparation rule: after a confirm, the checklist is the confirmed trades. Before one, it is the trades on
file followed by the trades the supplier's own documents name (`supplier_capabilities.proposed_trades`,
read by code from the licence, profile and catalogues).

## `services_resolve`

What one free-text service means, before saving. Request: `{ "action": "services_resolve", "text": string }`
(trimmed, 2–120 chars).

Response `200`: `{ ok: true, text: string, trades: string[], new_trade: string | null }` — `trades` are the
taxonomy codes `public.fn_norm_trades` names in the text (an exact alias or nothing, never a nearest
neighbour); when empty, `new_trade` is the code the text would be proposed under. `400 { code: 'services_empty_text' }`.

## `services_rewrite` — the sales engineer's version, before anything is saved

**Adding a service is a text box or a voice note, never a picker** (founder, instruction 438, 15 Sep
2026: *"for adding services its not a checkbox or drop down menu. i told you its a voice to text or
text box. once filled the sales engineer will rewrite that professionally since he will cross match
based on that."*). This action turns the supplier's own words into the platform's standard service
names. **It writes nothing** — the supplier sees the result, edits it, and confirms with
`services_save_rewrite`.

Request: `{ "action": "services_rewrite", "text": string, "removed"?: string[] }` — `text` is the
supplier's own words (up to 2000 chars, English, Arabic or both); `removed` are implied keys the
supplier has already struck out in this session, so a re-run does not silently put them back.

Response `200`:

```ts
{ ok: true,
  raw_text: string,             // the text exactly as received, for the confirm
  service_keys: string[],       // standard services the text NAMES, '<trade>.<code>'
  own_words: string[],          // phrases no alias names — kept verbatim, flagged, never dropped
  pending_taxonomy: string[],   // the own_words the sales engineer has to decide on
  implied: Implied[],           // what those services ALSO cover, with the reason, pre-included
  items: RewriteItem[],         // the per-phrase reading, for a client that wants to show it
  summary_en: string, summary_ar: string }

type Implied = { key: string; label_en: string; label_ar: string; trade: string; removed: boolean;
                 because: { from: string; from_label_en: string; from_label_ar: string;
                            en: string; ar: string }[] };
type RewriteItem =
  | { kind: 'service';   key: string; trade: string; label_en: string; label_ar: string; from: string }
  | { kind: 'trade';     trades: string[]; text: string; from: string }
  | { kind: 'unmatched'; text: string; from: string };
```

`400 { code: 'services_empty_text' }` for fewer than 2 non-blank characters.

**Added 21 Sep 2026 (a catalogue is read as a catalogue).** Request also takes
`"from_catalogue"?: true` — read the supplier's latest uploaded catalogue (its text layer, or the text
its browser recognised in a photo or scan) WHOLE, through `_shared/catalogue_read.ts`, instead of `text`
— and `"supply_only"?: boolean`, the supplier's own answer that overrides what the words suggested.
`404 { code: 'services_no_catalogue' }` when there is no readable catalogue. The response adds:

```ts
  supply_only: { proposed: boolean; applied: boolean; supply_words: string[]; install_words: string[] },
  // applied = true: installation work is not proposed, and every implied item comes back removed: true
  meaning: { state: 'on' | 'nothing_to_read' | 'service_vectors_missing' | 'embedding_unavailable',
             proposals: { key: string; trade: string; label_en: string; label_ar: string; similarity: number;
                          because: 'head_word' | 'alias' | 'two_lines'; word: string | null; lines: string[] }[] },
  source: { kind: 'typed' } | { kind: 'catalogue'; name: string; read_from: 'document_text' | 'photo_text' },
  model?: { state: 'off'; message_en: string; message_ar: string } | { state: 'read' | 'failed'; ... }
  // present only when code read nothing; OFF unless decision_policy supplier_catalogue_model_enabled
```

A meaning proposal the supplier keeps is sent back in `services` like any stated key. The rules
(`_shared/service_meaning.ts`): gte-small similarity above 0.82 AND a head word of the service's name or
one of its aliases in the line, or two lines agreeing above 0.86; never a nearest neighbour alone.

**How the rewrite works — deterministic, no model.** `supabase/functions/_shared/service_rewrite.ts`,
proved case by case in `service_rewrite.test.ts`. OpenRouter is on hold, and a rewrite that decides who
receives an inquiry has to be reproducible.

1. The text is split into phrases at line breaks, bullets, numbered items, commas (`,` `،`),
   semicolons (`;` `؛`), `|` and full stops.
2. Inside a phrase, every alias in `taxonomy_trade_service.aliases` is matched with the trade matcher's
   own rule (`_shared/trade_words.ts`, the twin of `fn_norm_trades`): Arabic folded the way
   `fn_ar_norm` folds it, word-START anchored, Arabic proclitics and `ال` allowed. Where two hits
   overlap the LONGER alias wins (`solar panel cleaning` is maintenance, not installation).
3. What is left of a phrase is split at `and` / `&` / `+` / `و` and read again; words that describe
   delivery rather than a service (`supply`, `installation`, `توريد`, `تركيب`, …) are dropped.
4. A phrase naming no service but naming a TRADE is kept with that trade. One naming neither is
   **kept in the supplier's own words**, tidied (trim, collapse spaces, dedupe, sentence case in
   English; Arabic left as typed), and flagged as a pending taxonomy item for the sales engineer.

**EXACT OR NONE** (founder, 14 Sep 2026: *"either exact match or no match"*): no stemmer, no
similarity, no nearest service. Nothing is ever invented and nothing is ever dropped.

**What a stated service also covers** (founder, instruction 439: *"make sure the sales engineer is
smart in cross matching. for example someone who does decoration is definitely able to do flooring
even through words cross matching is not there."*). `public.service_implication` is the curated map:
one row per relation, with its reason in English and Arabic, written by the sales engineer. It is
applied **ONE LEVEL ONLY** — what a STATED service implies is added; what an IMPLIED service would
imply is not (decoration implies false ceilings; false ceilings imply acoustic ceilings; decoration
does NOT imply acoustic ceilings). Implied services come back **pre-included** with their reason and
the supplier may remove any of them.

## `services_save_rewrite` — the confirmed list

The **one** save on this screen. (`services_save` and its `extra_services` list were removed with the
widgets they served, 18 Sep 2026: two writers of `supplier_capabilities.services` is how two screens
start disagreeing about what a supplier said.)

Request:

```ts
{ action: 'services_save_rewrite',
  trades: string[],      // trade codes the supplier keeps from the prepared checklist
  roles: string[],       // taxonomy_role codes, at least one
  services: string[],    // STATED: ticked checklist keys + the rewrite's service_keys it kept
  implied: string[],     // IMPLIED and kept, from `implied` above
  removed: string[],     // IMPLIED and removed — matching subtracts these
  own_words: string[],   // the phrases kept verbatim (up to 25, 2–120 chars each)
  raw_text: string }     // the supplier's own words, stored for audit
```

Effect:

* `capabilityConfirm` writes `supplier_capabilities.services` = stated keys + own words, sets
  `confirmed_at` (the gate `fn_match_capability` opens on) and appends a versioned
  `supplier_capability_confirmation` row. A stated key adds its trade to `trades`. Coverage defaults
  to `leads.service_emirates` when none is held.
* `services_raw_text`, `services_implied`, `services_removed` and `services_rewritten_at` are written
  after it — the raw input and the rewritten list kept separately, for audit.
* Each own-words phrase is resolved with `fn_norm_trades`; a named code joins `trades`, and unnamed
  text becomes a `taxonomy_trade_proposal` row (`status 'pending'`, owner `sales_engineer`).

Response `200`: `{ ok: true, confirmed: true, version, trades, roles, services, implied, removed,
own_words, resolved: Record<string, string[]>, proposed_trades: string[], new_trades_under_review: string[] }`.
`400 { code: 'capability_need_trade_role' }` with no trade or no role ·
`400 { code: 'services_nothing_recognised' }` when nothing resolved to any trade ·
`400 { code: 'services_none_ticked', trades }` when the save states no service at all (no ticked key
and no own words) while a confirmed trade has services to tick — founder_instructions 857 and 862: a
service he did not tick is one he did not confirm, so an empty portfolio is refused rather than stored
as complete. Enforced in capabilityConfirm, so `capability_confirm` returns it too.

## What matching reads

`public.fn_match_capability(p_trades, p_need, p_products, p_brands, p_project_type, p_value,
p_emirate, p_limit, p_services)`. Every gate it had is unchanged — confirmed scope, trade
intersection, declared negative scope, matchability, role, mandatory authority, job value. When the
inquiry names services in `p_services`, one more applies: the supplier must cover at least one of
them, where *cover* is

```sql
public.fn_services_effective(services, trades, services_removed)
  -- what the supplier STATED
  -- + ONE level of public.service_implication out of its stated services and trades
  -- - services_removed
```

so a supplier that stated only *interior decoration* is reached by a *floor tiling* inquiry, and stops
being reached the moment it removes floor tiling. A supplier that never confirmed a rewrite is treated
the same way: the map is applied to its confirmed trades and checklist services at match time.

Two output columns say why: `service_hits` (which of `p_services` it covers) and `via_implication`
(`'<from_code> -> <implied_key>'` for each hit the supplier did not state itself). `why` names them
too, so any shortlist can be read back to the curated row that produced it.

## `transcribe_service_note`

Voice to text for the "other services" box. Request:
`{ action: 'transcribe_service_note', audio_b64: string, mime: 'audio/wav' | 'audio/mpeg', duration_ms?: number }`.
The web client records with MediaRecorder and converts to 16 kHz mono WAV (`src/lib/wavEncode.ts`);
a mobile app records WAV or MP3 natively.

Limits: 60 s, 2.5 MB decoded, WAV or MP3, 20 requests per supplier per hour.
Behind `decision_policy` key **`supplier_voice_input_enabled`** (`{"enabled": false}` today — the
provider is OpenRouter through `supabase/functions/transcribe`, which is on hold). When on, the audio is
forwarded to `transcribe` with the caller's own token (its sign-in check, byte sniffing and malware scan
apply) and never stored.

Responses: `200 { ok: true, text, lang: 'en' | 'ar' | '' }` · `503 { code: 'voice_input_off' }` ·
`429 { code: 'voice_rate_limited' }` · `415 { code: 'voice_bad_type' }` · `413 { code: 'voice_too_large' | 'voice_too_long' }` ·
`400 { code: 'voice_empty' }` · `502 { code: 'voice_failed' }`. Every call writes one `supplier_voice_note`
row (size, length, type, outcome, detected language, character count) — no audio, no text.
