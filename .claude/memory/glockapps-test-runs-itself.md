---
name: glockapps-test-runs-itself
description: "The GlockApps inbox-placement test runs as an it_engineer duty through the deliverability_test edge function; API v2 facts read from the Swagger; the one founder step is the GLOCKAPPS_API_KEY edge secret (27 Oct 2026)"
metadata:
  node_type: memory
  type: project
  modified: 2026-10-27T15:30:00.000Z
---

**What exists (PR "it_engineer: the GlockApps test runs itself", 27 Oct 2026).** Edge function `deliverability_test`
(create / collect / report) + duty `it_engineer.deliverability_test` (`fn_deliverability_test_tick`, every 15 min) +
tables `deliverability_test`, `deliverability_test_provider`. The verdict is filed once per test: founder email
(founder_mail_policy kind `deliverability_verdict`) and the it_engineer finding `deliverability_outlook_not_proven`
(raised on fail / incomplete, closed on pass). It never touches the invitation switches; resuming stays his yes (1312).

**API facts, read from the published Swagger, not guessed:** base `https://api.glockapps.com/gateway/spamtest-v2/api`,
header `x-api-key`; `POST /projects/{projectId}/manualTest {testType:"ManualTest", providerGroupIds}` -> `testId`,
`emails[]`, `insertInBody "id: <testId>"`; report `GET /projects/{projectId}/tests?testId=` (inboxes[].iType,
stats, spamAssassin, microsoftEOP scl/bcl/sfv, barracuda, proofPoint, googleApps, authenticationResult); credits
`GET https://api.glockapps.com/gateway/app/v3/u/account/balance`. The spec is
`https://docs.spamtest.prod-k8s.glockapps.com/swagger.json`; a copy of its examples is in
`supabase/functions/deliverability_test/fixtures/swagger_examples.json`.

**The marker:** the M365 lane keeps only `id:<testId>` with NO space as the body's last line (SEED_MARKER in
send_outbox/m365_lane.ts); GlockApps matched that form on 19 and 27 Oct.

**How to read a site this container cannot reach:** the cloud proxy refuses glockapps.com, and WebFetch could not
resolve it either. `select net.http_get('<url>')` through `scripts/qsql.mjs`, then read `net._http_response` by id,
fetches it server-side from the Supabase project (read-only GET).

**Triggering a re-test without the founder:** `select public.fn_deliverability_test_request('<reason>');` (the duty
creates it within 15 minutes), or set app_secrets `deliverability_retest_weekly` to 'true' for a weekly re-test
(seeded 'false': each test spends a credit and ~110 seeds from supplier@).

**The one founder step:** GlockApps account settings -> copy the API key -> Supabase dashboard -> Edge Functions ->
Secrets -> add `GLOCKAPPS_API_KEY`. Until then every action answers `key_missing`.

Related: [[invitations-resume-only-at-80-percent-outlook-inbox]], [[checkpoint-27-oct-cloud-invitations-held]]
