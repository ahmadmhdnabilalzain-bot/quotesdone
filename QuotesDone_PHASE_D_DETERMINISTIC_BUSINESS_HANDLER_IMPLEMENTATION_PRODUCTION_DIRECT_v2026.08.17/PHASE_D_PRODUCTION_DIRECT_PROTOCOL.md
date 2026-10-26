# Production-Direct Protocol

There is no staging environment.

For each increment:

1. pull latest main;
2. confirm Phase A/B/C fingerprints;
3. inspect production read-only;
4. create code, committed migration, rollback and deterministic tests;
5. run local/static zero-cost tests;
6. commit before production;
7. rehearse exact SQL in an aborted production transaction where possible;
8. deploy one coherent handler family/workflow increment;
9. verify source parity, behavior, refusal, state, idempotency, trace and no external effect;
10. roll back the increment if mandatory checks fail.

Do not create persistent demo customers/suppliers. Use local fixtures, aborted transactions or explicitly namespaced/cleaned canaries.

Production may never remain ahead of main.
