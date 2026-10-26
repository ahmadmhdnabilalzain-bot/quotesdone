# Stage A / B / B.5 — verbatim recovery manifest

**Committed BEFORE the repository files were fitted to it.** Each recovered file must hash to the
SHA-256 below, computed over `array_to_string(statements, E';\n') || ';'` — the exact form the
migration is stored in.

## Count correction

`scripts/verify_migrations_in_repo.mjs` reported **22** applied-but-absent migrations. The true
number needing verbatim recovery is **30**. The audit matched by *name*, and eight consolidated
files reused an applied migration's name while containing merged content from several migrations —
so they matched the audit and were still not verbatim. Name matching cannot prove fidelity; only a
checksum can.

| # | Version | Name | SHA-256 | chars |
|---|---|---|---|---|
| 1 | 20260802165328 | p2_c1_stage_a_mep_model | `bab7ed095c948e1f4c5f9ded77b47e7ccf7ef3e87962899a80c7faa646e4f0f9` | 14,711 |
| 2 | 20260802165447 | p2_c1_stage_a_mep_functions_and_views | `d76e42057852d7a1eb75d3b55a8288ea69eb15597466abd42c718b55b710d848` | 21,428 |
| 3 | 20260802165657 | p2_c1_stage_a_mep_trades_and_field_identities | `4292c43f11d1321d2817ce171c3744509c018de8c4127d2ed86abb737c01f129` | 7,409 |
| 4 | 20260802165742 | p2_c1_stage_a_flag_consistency_split_fields_for_review | `e901d6068745664f18fe1e45b8b580fb110fecca83af23d5a4e804e1e7df96e8` | 1,906 |
| 5 | 20260802165847 | p2_c1_stage_a_teardown_gate | `c9b942142cbf7a4414607aa5351fc77dea1a05435f85697c83ecdf2036d48417` | 3,288 |
| 6 | 20260802165953 | p2_c1_stage_a_selftest | `5cb8cfd145084c00e29c518515428991f5106c01b8b737af10ffe312687ddade` | 14,284 |
| 7 | 20260802170028 | p2_c1_stage_a_fix_supersede_ordering | `f2b7d0ec034a7083de5cef70e7abe332b623c31759abc2af6b7644a07c4c5805` | 2,318 |
| 8 | 20260802170101 | p2_c1_stage_a_setter_uses_supersede_helper | `9ae1bc5a76a6f9c87869a20c50d4faa3634d818e65eb5b10df796e9f455f55d7` | 6,662 |
| 9 | 20260802170233 | p2_c1_stage_a_selftest_fix_corroboration_case | `5c76d211889bda2f3f7647ffeecc84e025adb84c656a8a599c0ec24fd5235031` | 13,481 |
| 10 | 20260802170345 | p2_c1_stage_a_selftest_fix_test12_measurement | `a3657025999300a3a02fdd6dddd5a463f7a39c08f4da2efa1e0fec220cd766f0` | 13,365 |
| 11 | 20260802170530 | p2_c1_stage_a_mep_subcategory_review_matrix | `a2e0e76e41d16fd96ba8e3efe5ca9ca5f308287e92a1003bb3e09381c36b5bc0` | 5,618 |
| 12 | 20260802171912 | p2_c1_stage_b_brand_acceptance_policy | `e56adb17597911e663b5416b068587d06e9e9ec7bb8dbc71a9b95b30b954ab08` | 9,428 |
| 13 | 20260802172249 | p2_c1_stage_b_ownership_references_and_gate_states | `3c60057dd6f996121e1a3ecee3e689973e7e75ad8a42f69cd50bd055455dd746` | 17,674 |
| 14 | 20260802172355 | p2_c1_stage_b_trade_identification_model | `1313dfa687697e719693411806413b2b84966705f96968355868c08ca8a00fe9` | 7,437 |
| 15 | 20260802172519 | p2_c1_stage_b_trade_identification_functions | `da4447d0f471c5140234fbbfb8e18d2cba9b3d212ee7640e47dc50a392677904` | 15,866 |
| 16 | 20260802172556 | p2_c1_stage_b_dispatch_blockers_and_trade_status | `c62d6ebf43e3ae3d4afa50f0e5e1993493d2914fd07b856b1fbaf8427cc938b5` | 6,374 |
| 17 | 20260802172643 | p2_c1_stage_b_value_domain_enforcement | `d89d6cba92352f35ab12ce796a484424651577b7393fcc5d25304d0f5e109a35` | 2,300 |
| 18 | 20260802172746 | p2_c1_stage_b_fix_alias_ambiguity_counting | `283b64e2f71535539ba125d24d97c173b74ceac2909ab0e1289a3caf9a251925` | 10,397 |
| 19 | 20260802172938 | p2_c1_stage_b_selftest | `2f12d2397ffb7acbe1bc86f741965114e115d365de9b4f2b6cde197252af8a52` | 16,164 |
| 20 | 20260802173005 | p2_c1_stage_b_fix_legacy_identity_workstream_count | `ac6fd7ab70ea95f04d1f9a784c9f71d328a82ba4f9fefe1ad9e34f20b9d0cdb7` | 1,390 |
| 21 | 20260802173244 | p2_c1_stage_b_fix_gate_default_and_scope_rule | `de6c3e23dba0ea93d170a5dfc40e500aa4c2f96b135b7b6b17709de47e3b1604` | 12,064 |
| 22 | 20260802173318 | p2_c1_stage_b_regression_tests | `826637edb0a90a0e81b68115e82ed54362892a186b2da9c0c65c8757139fc9b9` | 2,318 |
| 23 | 20260802173350 | p2_c1_stage_b_regression_tests_fix_ambiguous_passed | `b781c507ab9edbed3a477cf7c6cde3f501f0cdc60a06743fcad00f4a92dbf3ab` | 1,954 |
| 24 | 20260802174756 | p2_c1_stage_b5_evidence_score_semantics | `0b78da64e6bf1753c43229ee1aa6ea7510fd5fe46802ffabc986b9e786e7682a` | 10,076 |
| 25 | 20260802175036 | p2_c1_stage_b5_arabic_normalisation_and_scope_hardening | `2089bfe20a015cfb589b0424e252a63b9ae638dfd740d3a50b1a61047df02340` | 6,654 |
| 26 | 20260802175148 | p2_c1_stage_b5_identify_normalised_and_scored | `0fa93553089e82075c49a767aadbae1c97f29b6eab46830fb97653a704fd0d00` | 12,729 |
| 27 | 20260802175315 | p2_c1_stage_b5_language_parity_suite | `605297a6ef5e66d8aa8a3d95b83434df614a51631d425487e7149210eb966298` | 9,713 |
| 28 | 20260802175455 | p2_c1_stage_b5_trade_hints_and_arabic_alias_gaps | `4447eb268e1ff644ac40840cad1848f65d682b3b2f9ba9b113f454083df19015` | 3,333 |
| 29 | 20260802175551 | p2_c1_stage_b5_identify_with_trade_hints | `eaf08287da7c849a121d685451450e202dfe4db0faf110686017d93bca9a0ea5` | 12,852 |
| 30 | 20260802175653 | p2_c1_stage_b5_scope_rule_negative_tests | `4d2cbe70b57c9c7fa8116612a71b3dfb43232a74846b1c24f1bff246060bb017` | 3,854 |

Total 296,347 characters across 30 migrations. **Execution order is version order.**

Recovered files are written as `supabase/migrations/2026080223NN_<name>.sql` by
`scripts/recover_stage_a_b_b5.mjs`, which verifies each against the checksum above and refuses to
report success on drift.

## What happens to the previously consolidated files

The hand-written consolidations under `20260802190*`, `2026080220*` and `2026080221*` are moved to
`supabase/migrations-superseded-consolidated/` — out of the migrations path so they cannot be
double-applied, but kept in the tree so any semantic difference remains reviewable rather than
discarded. They are superseded, not deleted.

## Amendment 1 — a 31st migration, found by the replay, not by the audit

The replay verification (`scripts/sql/replay_verify.sql`) counts the applied migrations inside the
P2-C1 version window instead of trusting either the audit or this manifest. It reported **44**
migrations in `20260802165328 .. 20260802183212`, against 30 here plus 13 in
`STAGE_B6_RECOVERY_MANIFEST.md` — 43. One migration was in neither manifest:

| # | version | name | sha256 | chars |
|---|---------|------|--------|-------|
| 31 | 20260802175843 | p2_c1_stage_b5_operator_rollback | `98102c368dc9e8250b125d4ab7cc3f648f01c20ac7f1fb8210531c85c263a292` | 23,156 |

It sits after the last Stage B.5 migration listed above (`20260802175653`) and before the first
Stage B.6 migration (`20260802181006`), so both recovery windows excluded it at their boundaries.
This is the same class of mistake as the 22-versus-30 count error recorded earlier: a boundary
chosen from a name-based reading of the work rather than from the applied record.

Revised totals: **31** Stage A/B/B.5 migrations, 319,503 characters; **44** P2-C1 migrations in
total once the 13 Stage B.6 migrations are included.

This amendment is committed before the file is written, on the same rule as the original manifest.
