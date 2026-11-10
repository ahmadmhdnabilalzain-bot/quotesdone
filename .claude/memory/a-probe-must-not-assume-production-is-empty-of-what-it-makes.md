---
name: a-probe-must-not-assume-production-is-empty-of-what-it-makes
description: 10 Nov 2026. 36 checks red on main; most were probes written when production held none of the rows they create, then production grew them.
metadata:
  type: feedback
---
On 10 Nov 2026 36 checks failed on origin/main. Production was right in nearly every case. The probes had been written
when production held none of the thing they create or count, and then production grew some:
- a real seat restart (invite_brake 5, 7 Nov) made every fixture brake a "second breach";
- real November miss tasks (8 Nov) meant a 20 Nov probe opened 2 tasks for 7 misses;
- the real 1 Nov month plan and the real October close made the calls return 0 / 'closed';
- 14 leftover e2e demo customers and demo duplicates inflated fixture-mode duty totals.
Others were rulings the checks predated (ledgers 1449, 1486, 1535, 1571, 1574, 1115), a check that could not parse its
own payload (db.mjs cuts e.message at 2,000 characters, so read e.body), and safe_replay's rows mode dropping a quoted alias.

**Why:** a probe pinned to "production has none of these yet" turns red the day production is used, and reads as a
defect in code that is right. [[a-founder-ruling-is-not-a-defect-to-fix]] covers the ruling half.

**How to apply:** a probe asserts on ITS OWN subjects (ids it created, keys it shares), not on a routine's totals; it sets
real rows aside inside its aborted transaction (by primary key, after checking the table's triggers) when the routine
reads history; and it counts a period's state from its rows, not from one call's return. Branch
it_engineer-production-checks-green carries one commit per check.
