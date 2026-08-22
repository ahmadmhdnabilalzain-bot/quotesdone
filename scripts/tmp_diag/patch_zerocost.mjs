import { readFileSync, writeFileSync } from 'node:fs';
const p = 'docs/phase-d/PHASE_D_ZERO_COST_EVIDENCE.md';
let s = readFileSync(p, 'utf8');

const oldWindow = 'Required deliverable 13 of 15. Covers **2026-08-18 14:00 → 2026-08-21 21:24 UTC** (database clock),\nproject `htdblwldjkcgjvmqkbeh`.';
const newWindow = 'Required deliverable 13 of 15. Covers **2026-08-18 14:00 → 2026-08-22 19:01 UTC** (database clock),\nproject `htdblwldjkcgjvmqkbeh`.';
if (!s.includes(oldWindow)) { console.error('window anchor missing'); process.exit(1); }
s = s.replace(oldWindow, newWindow);

const oldPara = `**THE WINDOW MOVED A THIRD TIME, AND THIS TIME THE CHECK MOVED IT, NOT A MEMORY.** The session of
21–22 Aug 2026 applied F01 through F30 under the founder's ruling of 21 Aug, and
\`scripts/checks/zero_cost_evidence_window_covers_the_work.test.mjs\` failed with *"the window does not
close before the work it claims to cover"* — which is the whole reason it was written. The close is
now the database clock read after F30, the last apply of that session. Every figure below was
re-measured at that instant.`;

const newPara = `**THE WINDOW MOVED A FOURTH TIME, AND THE CHECK MOVED IT AGAIN.** The session of 22 Aug 2026 applied
F31 through F42 under the founder's ruling of that date, and
\`scripts/checks/zero_cost_evidence_window_covers_the_work.test.mjs\` failed with *"the window does not
close before the work it claims to cover"*, naming \`phase_d_fixture_catalogue.recorded_at\` at
2026-08-22 18:04:27 UTC as work outside it. That is the whole reason the check was written, and it
is the fourth time it or an auditor has caught this. The close is the database clock read after F42,
the last apply of this session, and every figure below was re-measured at that instant.

**Measured at the new close, 2026-08-22 19:01:09 UTC:**

| | over the stated window |
|---|---:|
| \`public.ai_cost_log\` rows | **0** |
| \`public.ai_cost_log\` spend | **AED 0** |
| \`public.llm_attempt\` rows | **0** |
| most recent \`ai_cost_log\` row in the whole table | 2026-08-15 02:51:33 UTC |
| \`net.http_request_queue\` | **0** |
| active \`cron.job\` | **23** |
| \`public.notifications\` written on 22 Aug | 5, of which **0 sent** |
| \`customers\` / \`inquiries\` / \`quotes\` / \`transactions\` | **0 / 0 / 0 / 0** |
| \`phase_d_effect_ledger\` | **0** |
| \`public.leads\` | 20,465 — unchanged |

No OpenRouter request and no other paid-provider request was made to produce any figure in this
document or any figure in this session's work. The hold is enforced structurally rather than by an
environment variable: \`fn_phase_d_capability_result_accept\` refuses \`provider_mode = 'provider'\`
outright, \`fn_phase_d_handler_execute\` refuses any step carrying a provider dependency whatever the
execution context says, and F42's sibling F36 added
\`phase_d_effect_ledger_never_a_live_provider\` — a named CHECK that refuses a live provider result
in the effect ledger, so the prohibition is stated rather than left to a value's absence from a list.

**ONE TRANSIENT READING, RECORDED RATHER THAN ROUNDED.** At 18:41:43 UTC a closing sweep read
\`public.customers\` = 2 while \`scripts/checks/run.mjs\` was running against production in another
connection; at 18:44 and again at 19:01 the same query read 0, and \`fn_phase_d_fixture_residue()\`
returned no rows. The estate's own kernel positive-control checks start and complete real runs
against production, which is what that sweep caught mid-flight. The closing figure is 0; the
intermediate reading is stated because a number seen once and not explained is how a residue claim
goes quietly wrong.`;

if (!s.includes(oldPara)) { console.error('paragraph anchor missing'); process.exit(1); }
s = s.replace(oldPara, newPara);

writeFileSync(p, s);
console.log('zero-cost document updated');
