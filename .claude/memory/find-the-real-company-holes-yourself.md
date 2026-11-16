# Find the real-company holes yourself, and build them (16 Nov 2026)

Founder ledgers 1711, 1712, 1713 (16 Nov 2026, voice, about 01:00-01:15 UTC):
- 1711: a customer gives his budget to the sales engineer in the intake chat; later on WhatsApp he asks "did you find
  anyone below 5,000?" — "I don't want the system to be rule-based only, like 1 + 1 = 2. No, it's scenarios ... 1,000
  scenarios ... are these things considered?" Measured that night: the WhatsApp facts carried no budget.
- 1712: "If it turned out to be that he doesn't know, then it's a disaster ... in real company scenario, everyone
  knows what the other is doing because they are colleagues in the same company."
- 1713: "I keep on finding out stuff by asking you. I really want you to help me, not wait for me ... I can't keep on
  thinking of scenarios. You have to really think, is this feels like a real company? If not, you gotta find those
  holes and build them."

## The standing rule
- The founder is never the one who finds a hole. Every session that builds on this repository also HUNTS: it plays the
  real people (customers, suppliers, the company's own staff as a COO sees them, and people gaming or breaking it)
  through realistic scenarios, traces in code what the system really does, ranks the holes by first-month likelihood
  × harm, and builds the fixes through the normal review → gate → release path without asking.
- A hole is: nobody handles it; a fixed rule where judgement is needed; an agent lacking a fact a colleague holds; a
  promise with no owner or deadline; a dead end (waits forever, asked twice, told something false); money, legal or
  anonymity risk; a loop that never closes; a feature the founder removed still running.
- The fix is a colleague READING THE SHARED RECORD (one reading per person and per request that every channel reads:
  fn_customer_inquiry_facts, fn_wa_context, fn_contact_timeline, the support case and its promises), never a new
  keyword rule. Scenario banks with must/must-not answers prove it; a paid run is capped and judged by another family.
- The method that worked on 16 Nov: one "who knows what" matrix (facts × seats, KNOWS/PARTIAL/BLIND with file:line)
  plus four read-only hunters (customer lifecycle, supplier lifecycle, operations, failures/abuse), each returning its
  top 12; the brief is kept as the session scratchpad `briefs/hole_hunt.md` pattern (read-only, origin/main, light
  SELECTs only, never re-report what is being fixed).

## What the first hunt found (16 Nov, measured)
- The support case record every reply door leans on was empty on production (0 of 30 cases with a summary, 0 promises).
- Intake was the one customer door that neither read nor wrote the case; portal chat and e-mail replies were blind to
  the person's timeline; no supplier-facing door knew the supplier's trades, licence or strikes.
- The best-and-final round the founder removed was still enabled hourly (switched off 16 Nov:
  `the_best_and_final_round_and_framework_rates_stay_off_as_the_founder_removed_them.sql`).
