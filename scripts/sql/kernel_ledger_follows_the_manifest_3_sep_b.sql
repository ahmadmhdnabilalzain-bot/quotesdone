-- THE OWNERSHIP LEDGER FOLLOWS THE MANIFEST, PART B (3 Sep 2026).
-- trg_reveal_receipt gained a new canonical file today (scripts/sql/reveal_notifies_both_parties_on_both_channels.sql,
-- later in the apply order than kernel_k21_cutover_02_supplier_system.sql). The ledger row still named the
-- older file; application_source_of_truth line 6 reported the one disagreement and emitted this statement
-- (--emit-ledger-sync). Applied as emitted, with the reconciliation date corrected.
update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/reveal_notifies_both_parties_on_both_channels.sql',
       evidence = 'records source_file scripts/sql/kernel_k21_cutover_02_supplier_system.sql, manifest order says scripts/sql/reveal_notifies_both_parties_on_both_channels.sql — reconciled mechanically 3 Sep 2026 (application_source_of_truth --emit-ledger-sync).'
 where schema_name = 'public' and routine_name = 'trg_reveal_receipt'
   and coalesce(identity_args,'') = '';
