# Supplier portal — Services checklist API

Owner seat: `sales_engineer`. Added 15 Sep 2026. Web portal and a future mobile app use the same
actions; the React tab (`src/components/portal/supplier/ServicesTab.tsx`) is only one client.

All actions are `POST {SUPABASE_URL}/functions/v1/supplier_api` with a JSON body
`{ "action": "<name>", ... }` and `Authorization: Bearer <supplier user JWT>`. The supplier is the
company whose `leads.claimed_by` is the signed-in e-mail; no action accepts a `supplier_id`.
An unclaimed account gets `400 { "code": "no_company" }`.

Code: `supabase/functions/_shared/supplier_services.ts` (logic), `supabase/functions/supplier_api/index.ts` (routing).
Data: `public.taxonomy_trade_service`, `public.supplier_capabilities`, `public.supplier_capability_confirmation`,
`public.taxonomy_trade_proposal`, `public.supplier_voice_note`, `public.decision_policy`
(`scripts/sql/a_supplier_states_its_services_from_a_checklist_the_sales_engineer_prepares.sql`).

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
  selected_services: string[],                 // keys ticked now; on first run = every service of every prepared trade
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

## `services_save`

Request:

```ts
{ action: 'services_save',
  trades: string[],          // trade codes the supplier keeps (a listed code, or its own words -> open list)
  roles: string[],           // taxonomy_role codes, at least one
  services: string[],        // ticked keys; unknown keys are dropped; a ticked key adds its trade
  extra_services: string[] } // up to 25 free-text services, 2–120 chars each
```

Effect: each extra is resolved with `fn_norm_trades`; named codes join `trades`, unnamed text stays a
service and becomes a `taxonomy_trade_proposal` row (`status 'pending'`, owner `sales_engineer`).
`supplier_capabilities.services` = ticked keys + extras; the confirm is `capabilityConfirm`, which sets
`confirmed_at` (the gate `fn_match_capability` opens on) and appends a versioned
`supplier_capability_confirmation` row. Coverage defaults to `leads.service_emirates` when none is held.

Response `200`: `{ ok: true, confirmed: true, version, trades, roles, services, extra_services,
resolved: Record<string, string[]>, proposed_trades: string[], new_trades_under_review: string[] }`.
`400 { code: 'capability_need_trade_role' }` with no trade or no role.

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
