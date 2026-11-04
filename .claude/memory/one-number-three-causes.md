---
name: one-number-three-causes
description: "A single disclosure number over a population usually has more than one cause, and the document explaining it picks one and is wrong about the rest."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ba4ede58-946f-4477-8042-69cef19ee057
  modified: 2026-08-20T03:15:43.346Z
---

`steps_with_no_effect_ever_produced = 257` had **three** causes, not one, and the builder's closure
document named only the second: "no committed business arrival has ever driven a step". Measured:

- **21** — `CAPABILITY_REQUEST`; the routine *raises* in production, so the declared effect IS the
  refusal. Held by the provider hold.
- **51** — effect writes an `EXISTING_TABLE`. Held by the zero-residue rule.
- **185** — effect writes only the kernel's own step run or Phase D's own store. Held by **neither**
  hold; held by the fact that the only driver marks its own rows fixtures
  (`source_ref zz-phase-d-…`, `trigger_ctx.fixture=true`) and `fn_phase_d_fixture_residue()` must be 0.

The stated cause was right about 51 of 257 and wrong about 206.

**Why:** a number that aggregates a population invites a single-sentence explanation, and whoever
writes it reaches for the most salient blocker. Nobody re-checks whether it covers the whole
population, because the number is already red and already disclosed.

**How to apply:** before quoting or acting on any aggregate disclosure, **partition it by mechanism**
— for each member, what code path would have to run, and what actually stops it? Then put the
partition on the board beside the number, each part naming its own lever and who can pull it. Do not
move the number: 257 stayed at 257. Related: [[instruments-report-on-the-wrong-subject]],
[[a-denominator-does-not-fix-a-population]], [[checks-can-measure-row-age-not-mechanism]].
