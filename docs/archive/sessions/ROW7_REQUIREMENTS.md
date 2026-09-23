# ROW #7 — AGENTS AND KNOWLEDGE: THE ENUMERATION GROUNDWORK

Source: `docs/specs_row7_agents_and_knowledge.txt`, **1,497 lines**. Structure measured 2026-08-09.

**This row has never been scored.** Every other spec file has a scorer; this one does not.
`verify_agent_knowledge.mjs` is *not* it — that is a narrow gate on one routine
(`fn_dept_library_search`) and its own header says so.

---

## 1. THE SPEC IS FOUR DOCUMENTS IN ONE FILE

Measured by parsing the file rather than reading it end to end:

| part | what it is | blocks | enumerable lines |
|---|---|---|---|
| **A** | the org — departments and their sub-functions | **22 departments** | **141** |
| **B1** | *Knowledge Required* per department | 20 blocks | **273** |
| **B2** | shared knowledge every department must hold | 20 domains | **197** |
| **B3** | the AI workspace UI + autonomy | 22 UI features + 6 autonomy | **377** |
| | | **90 blocks** | **988 lines** |

### Part A — the 22 departments

17 numbered: CEO Office · Supplier Success · Customer Success · **RFQ / Inquiry Intelligence ⭐
(the spec marks this "Your Core Product")** · Marketplace Operations · Sales · Marketing · Finance ·
Legal & Compliance · HR · Administration & Operations · Engineering · AI · IT & Cybersecurity ·
Data & Analytics · QA & Testing · Business Development.

Plus 5 unnumbered: **Supplier Knowledge ⭐** · **Document Intelligence ⭐** ·
Notification & Communication · Payment · Trust & Safety.

### Part B3 — and this is the part nobody would predict from the title

The last third of a file called *"agents and knowledge"* is a **UI specification**: AI Command
Center, Multi-Agent Workspace, Smart Windows, AI Side Panel, Universal Search, Interactive Knowledge
Graph, Interactive Timeline, Interactive Documents, Drawing Intelligence, Live Collaboration,
Interactive Dashboard, Drag & Drop Workspace, Context Memory, AI Suggestions, Visual Workflow
Builder, Floating AI Tools, Natural Language Navigation, Workspace Snapshots, Real-Time
Notifications, Voice Mode, Adaptive Workspace, AI Mission Control — then six autonomy sections:
Decision Engine ⭐, Exception Handling ⭐⭐⭐, Self-Healing ⭐⭐⭐⭐⭐, Continuous
Monitoring ⭐⭐⭐⭐⭐, Learning & Adaptation.

**That overlaps spec #3 (executive UI, 28/152) and must not be double-counted.** Any enumeration of
this row has to resolve Part B3 against row #3's 152 first, or the two rows will both claim the same
screens — the defect class row #4 named and rows #5 and #6 each had to design against.

---

## 2. WHY THE DENOMINATOR IS NOT 988

The grain rule inherited from rows #4–#8 is *one enumerated line of the spec = one requirement*.
Applied literally here that gives **988**, which is 3.5× the largest row scored so far (#6 at 283)
and 6.7× the smallest (#4 at 147).

Rows #5 and #6 already established the correction: **where the spec names a list that one object
answers, it is scored as a per-item coverage count over that object, not as N independent greps.**
Row #5's §24 did this for 19 nav modules; row #6's §1/§2 did it for 66 domains and 84 categories.

The same collapse applies here in three places:

- **B1's 273 knowledge lines** are 20 questions — *does department X hold its knowledge?* — each
  answered per-department over `agent_knowledge`, exactly as row #6 scored 8 domains × 84 agents.
- **B2's 197 lines** are 20 shared domains, one coverage count each.
- **A's 141 sub-functions** are the real per-item list, and they are genuinely 141 distinct claims.

**Proposed denominator: 22 + 141 + 20 + 20 + 22 + 6 = 231**, pending the row #3 overlap resolution
which may remove some or all of B3's 28.

That is a proposal, not a measurement, and it is the **first thing the next session must settle
before writing a single check** — because rows #5 and #8 both showed that a denominator decided
after the checks are written is a denominator bent to fit them.

---

## 3. WHAT IS ALREADY KNOWN TO EXIST, SO NOBODY REBUILDS IT

Measured on production during this session, while scoring other rows:

- **`org_agents`: 67 active agents across 13 departments** — it, marketing, sales, finance,
  knowledge, customer_success, legal, exec, hr, intelligence, knowledge_eng, evolution, procurement
- **`agent_knowledge`: 1,985 rows**, 207 agent keys, layers company/profession/state/experience
- **`category_agents`: 132 agents**, 110 active — the supplier category layer (row #6, 249/283)
- **`operating_system`: 10 rows**, all staffed, all with purpose/mission/mandate reaching prompts
- **Spec #1 (company architecture) is 48/48** — the employee object, org hierarchy, review chains,
  department heads, Chief of Staff challenge, learning, planning and memory are **built and read**

**So the org half of row #7 is substantially built.** The spec names 22 departments; production runs
13 in `org_agents` plus the 10 operating systems. Whether those 22 map onto the 13+10 or reveal
genuine gaps is the row's first real measurement, and it is exactly the shape of row #6's opening
question — where the answer turned out to be "already there, in a column nobody looked in".

**Do not assume the 22 departments are missing.** Rows #2 and #6 both opened with a document
claiming a gap that measurement closed.

---

## 4. THE ORDER OF WORK

1. **Resolve Part B3 against row #3's 152.** Until that is settled the denominator is unknowable.
2. **Fix the denominator and write it down** before any check exists.
3. Map the spec's 22 departments onto `org_agents`' 13 + `operating_system`'s 10 and measure the
   real overlap.
4. Build `scripts/staging/verify_agents_knowledge.mjs` on the established contract — modules
   discovered not listed, each declaring `EXPECTED`, evidence beside every verdict, an evidence
   failure invalidating its verdict, and the total asserted at the end.
5. Score, then read the payload before treating any MISSING as a build order.

**The standing lesson from this session applies here more than anywhere**, because this row has no
prior score to anchor to: the brief is a hypothesis, the scorer is the measurement. Four documents
in this repo — row #6's brief, row #2's worklist, and two of my own scorer anchors — were accurate
when written and wrong when read.
