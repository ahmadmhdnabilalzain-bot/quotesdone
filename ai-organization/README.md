# AI Organization — versioned snapshot (source of truth: suppliers DB)

Synced 2026-07-24 from the live Supabase project (htdblwldjkcgjvmqkbeh).

- `org-as-code/` — the organization itself as data: departments, agents (16 executives),
  authority matrix (28 delegations), onboarding/certification state, decision policy,
  forbidden-language rules, layered exam bank (100 questions), and all 552 knowledge rows
  across the four layers (company / profession / state / experience).
- `db-functions/` — the behavioral core as SQL: four-layer context assembler
  (fn_agent_context), autonomy hard-rails (fn_autonomy_class), policy linter
  (fn_policy_consistency_check, scans 7 stores), security self-audit, onboarding
  state machine + rotating re-certification, and governed experience promotion.
- `AUDIT_2026-07-24.md` — the executive competency audit that started this program.
- `EMPLOYEE_ARCHITECTURE.md` — onboarding & continuous-learning architecture.
- `ROLLBACK_wave1_original_rows.md` — pre-correction knowledge rows.
- `org-as-code/migrations.json` — full migration history index (369 entries).

Today's changes (2026-07-24): money-model truth reconciliation, Analytics & Procurement
executives hired, chairman doctrine (default-to-action) encoded into rails + posture,
agent_brain v15 (four-layer context, Opus-first, lint-gated memory, 16-agent roster),
canon_eval v2 (randomized, layer-balanced, agent-scoped exams), full examination round
(16/16 examined; final board 83.3–100%).
