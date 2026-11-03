---
name: the-founder-command-channel-is-proved-end-to-end
description: "3 Nov 2026, gap #10: the founder's WhatsApp channel has an e2e (signed Twilio POSTs, fixture founder, SQL-pinned figures and registry) and a local-Postgres proof of its SQL; the founder check now compares the whole number (pending apply)"
metadata:
  node_type: memory
  type: project
  modified: 2026-11-03
---

Release qualification gap #10 (docs/release/qualification_matrix.md F07.01-F07.05) was built on 3 Nov 2026.

- **The e2e:** `supabase/functions/wa_inbound/founder_command_channel.test.ts` (in `npm test`). The real wa_inbound
  handler, Twilio-signed form POSTs, a fixture founder number picked per run from +971 50 000 0060-79 and registered
  only in that run's stub `admin_mfa_phone`. The registry and every figure key are PARSED from the canonical SQL, so a
  key added in SQL fails the test until the channel says it. Never write the real founder number into a test or output.
- **The SQL proof:** `scripts/e2e/founder_command_channel_sql.mjs` runs the real `fn_identify_contact`,
  `fn_founder_settings` and `fn_founder_apply_setting` on a throwaway local Postgres (runs the server as `postgres` when
  the session is root). Needs no credential and cannot reach production.
- **Ruling 777 beats the matrix's old wording:** a natural "how many requests today?" from his number gets the
  capability statement, never a figure; figures go only on the FIGURES / «أرقام» command word.
- **Defects fixed:** forbidden settings never reached the refusal (the classifier was told to return
  `directive:false` for money and go-live), Arabic close commands answered in English, Arabic directives recorded and
  replayed in English, a null figure said as 0, SQL's English time words in the Arabic reading.
- **Pending (scripts/sql/pending/):** `the_founder_is_recognised_by_his_whole_number_not_its_last_nine_digits.sql`.
  The old founder check matched the last nine digits, so +966 plus his nine digits was "the founder". Apply at merge.
- **Still open, not done here:** `fn_whatsapp_owner` (suppliers, customers) has the same nine-digit match;
  the internal-JSON replay path may change a setting on main until #1836 lands.
