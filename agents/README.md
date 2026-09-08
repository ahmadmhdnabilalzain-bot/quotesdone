# `agents/` — the company, separated from the estate it grew out of

The founder, 9 September 2026: *"can you create a sub project that its totally seperated from this and
just move the CEO and customer support agent to it."*

This directory is that sub-project. It exists because the two agents that ARE QuotesDone were built
inside an estate of ten departments, four governance phases, an event kernel and an admin console —
none of which exist any more, and all of which the agents were entangled with. Removing that estate
from underneath them has been slow precisely because there was no line between "the company" and
"the machinery the company used to run on". This directory is that line.

---

## What lives here

| | |
|---|---|
| `MANIFEST.json` | The authoritative list: which edge functions, tables and routines belong to which agent. Enforced by a check, not a convention. |
| `ceo/` | The CEO seat — the founder's command channel, the approval register, the task queue. |
| `customer_support/` | The customer-support agent — the home-page widget, WhatsApp, email, and the knowledge it answers from. |

Each agent directory holds its own `sql/`, `checks/` and `knowledge/`, and its own README describing
what that agent is responsible for and what it must never do.

## What does NOT live here, and why

**The edge function source stays in `supabase/functions/<slug>/`.** That is not a preference — it is
where the Supabase deployer looks, and moving it breaks deployment. `MANIFEST.json` names which
functions belong to which agent, and a check asserts that the manifest and
`public.function_owner` agree with each other and with what is actually deployed.

**Historical SQL stays in `scripts/sql/`.** Those files are the record of what was built and when,
read by the canonical routine engine, and listed in `scripts/sql/MANIFEST.txt` by path. Moving them
would rewrite that record for no gain and would break the engine that proves the repository and
production agree. New agent work lands in `agents/<agent>/sql/`.

**The website is not here.** The marketplace — inquiries, quotes, suppliers, payments, the portals,
the public pages — is the product. These two agents serve it; they are not it.

---

## The constraint that shaped this, stated plainly

A truly separate DATABASE was considered and rejected on a measurement, not a preference.

The customer-support agent answers questions about the marketplace: what a lead's licence status is,
whether a quote exists, what the reveal fee is. It reads `company_faq`, `leads`, `inquiries`,
`quotes` and `wa_messages`. Put it in its own Supabase project and one of two things happens — either
those tables are duplicated across two databases and immediately disagree with each other, or the
agent stops being able to answer anything about the business it supports.

So the separation is of CODE, OWNERSHIP and TESTS, which is where the entanglement actually hurt. The
data stays in one place, because a customer-support agent that cannot see the customer is not
separated, it is disconnected.

## The boundary is enforced

`agents/boundary.test.mjs` fails if:

1. a function in `MANIFEST.json` is not deployed, or is not owned by that agent in
   `public.function_owner`;
2. a function owned by `ceo` or `customer_support` in the database is missing from the manifest —
   the direction that matters, because a registry built by reading the live list can only see what is
   present and unclaimed, never what is missing. That is exactly how eight portal functions were
   deleted on 8 September and `/me` and `/portal` returned 404 for ninety minutes;
3. any SQL under `agents/` references the old estate — `phase_*`, `kernel_*`, `org_*` beyond the two
   seats, `workflow_*`, `founder_command*`. The new company does not get to re-couple to the one
   being removed.
