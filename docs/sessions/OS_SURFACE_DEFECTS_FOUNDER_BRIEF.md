# The OS screen — what the founder sees, and where each number actually comes from

Written 15 Aug 2026 from his own words: *"there are many things actually in it that don't make
sense… I don't know actually from where they're getting the figures… in general, the OS is
horrible."*

**Not a work order.** He said "I'm just letting you know for later", and the 137 deferred steps are
explicitly a separate phase he owns. This is the diagnosis, so that session starts with answers
instead of questions.

Everything below is measured from production on 15 Aug 2026, not read from a report.

---

## The strip he named, figure by figure

### "Monthly goal 48.2%"

**Where it comes from:** `fn_ws_exec_home() → fn_goal_attainment('monthly')`.

**What it actually is:** 48.2% across **22 measured goals out of 61**. Thirty-nine goals in the
current month have a target and **no measurement at all**.

**The defect is not the number — it is the screen.** `fn_ws_exec_home` already returns
`goal_measured: 22` and `goal_count: 61` in the same payload. The SQL even carries the rule in a
comment: *"no surface publishes a percentage without the coverage it rests on. '50%' and '50%
across 2 measured goals of 61' are different facts, and only the second one is safe to act on."*
The database obeys that rule. The strip throws the denominator away and prints `48.2%`.

This is the same family as the defect that once showed him **98% goal progress on a day with AED 0
revenue** — `least(100, NULL)` returning 100 in Postgres. That was fixed in the data. The screen
never caught up.

**Fix:** render "48.2% · 22 of 61 goals measured". One line in `OsxShell.tsx`; the data is already
there.

---

### "Company health 49.6 — needs attention"

**Where it comes from:** `fn_health_index()`.

**What it actually is:** the average of **4 measured components**, two of which are **0.0** —
customer acquisition and supplier activity — because the marketplace has not transacted yet.
Revenue today is 0 and active customers is 0.

So 49.6 is arithmetic, not a verdict. Roughly: two components near 100, two at zero, averaged.

**The explanation already exists and is not shown.** The function returns `health_note`:

> *"Company health is 49.6 of 100 (attention), driven by customer acquisition at 0.0 and supplier
> activity at 0.0 — the two furthest below the 49.6-point average of 4 measured components."*

The strip prints `49.6 · Need attention` and discards that sentence. He is told the company needs
attention and not told what or why, when the answer was in the same response.

**Fix:** show `health_note` under the figure. Again already in the payload.

---

### "AI employees working 7 / 90"

**Where it comes from:** counts `org_agents` where active **and** the employee appears in
`agent_runs`, `agent_memory` or `agent_chats` in the last 24 hours.

**This one is honest and it is not a display bug.** Seven of ninety employees did anything at all
yesterday. Eighty-three did nothing.

Worth knowing why the count is built from three tables: it used to be
`count(distinct agent) from agent_runs`, which is the **cron and job log** — 111 distinct values
over 30 days, only nine of them actual employee keys. Cron jobs were being counted as colleagues.
That was fixed on 10 Aug; the number got smaller and truer.

**No fix needed on the screen.** The number is the company. It changes when the workforce is
switched on — the phase he is holding.

---

### "AI collaboration 22 handoffs / 24h" — **this one is wrong**

**Where it comes from:** `count(*) from event_delivery where delivered_at > now() - 24h`.

**That is not handoffs.** It counts **event deliveries**. Measured today:

| | |
| --- | --- |
| rows the strip calls "handoffs" | **22** |
| actual handoff runs (`phase_c_handoff_run`) | **0** |
| handoff contracts (`handoff_contract`) | **0** |

A handoff is one employee formally passing accountable work to another, with a packet, acceptance
criteria and a return owner. Phase C built that runtime and it has never been exercised. The strip
is showing message-delivery volume under a label that claims departments are collaborating.

**This is the "instrument reporting on the wrong subject" defect**, and it is the only figure on
the strip that is actually misleading rather than merely under-explained.

**Fix:** either relabel it "events delivered / 24h", or point it at `phase_c_handoff_run` and let
it read 0 until handoffs actually happen. The second is more honest and will read as a regression;
it is not one.

---

### "Live workflow 18 runs/24h" and "Infrastructure uptime 91%"

Both real. `workflow_run` in the last 24 hours, and the ALIVE fraction of `edge_health_probe`.

**91% uptime is low** and is worth its own look — that is roughly one probe in eleven failing.

---

## The other three things he named

### Escalations render as raw codes — confirmed

`fn_ws_exec()` returns notifications whose `type` is a machine key. Live values today:

```
resilience_alert, supplier_invite
```

The screen prints those strings. He has raised this before; it is still there. There is no
human-readable label anywhere in the payload, so the fix is a label map or a `display_name` column,
not a front-end string replace.

### Error history should be cleared until the build is done — small

`error_events` holds **10 rows**, 25 Jul → 15 Aug. Not the volume the screen implies. Whatever is
making the error surface feel heavy is somewhere else and needs finding before anything is deleted —
clearing 10 rows will not change what he is seeing.

### "The overview — a lot of things don't make sense"

Not diagnosed. Needs him to point at specific tiles, or a walkthrough with him on the screen.

---

## The pattern underneath all of it

Four of the five figures are **correct in the database and impoverished on the screen**. The
honest denominator, the explaining sentence, the coverage — all computed, all returned in the same
payload, all discarded before rendering.

That is why the numbers "don't make sense" to him: he is being shown conclusions with their
evidence stripped off. The company is not lying to him. The dashboard is summarising away exactly
the part that would let him judge whether a number means anything.

One figure — handoffs — is genuinely mislabelled and should be treated as a defect, not a
presentation gap.

## Suggested order when the OS phase starts

1. Relabel or repoint the handoff figure. It is the only actively misleading number.
2. Show the denominators and the health note that are already in the payload. Cheap, and it fixes
   the "where do these come from" problem for two of the biggest tiles.
3. Give escalations human labels.
4. Find what is actually making the error surface feel heavy — it is not `error_events`.
5. Walk the overview with him tile by tile.
