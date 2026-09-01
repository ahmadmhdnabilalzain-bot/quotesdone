# How knowledge actually reaches an agent (measured 28 Aug 2026)

This is the load target the whole expertise workstream depends on. Getting it wrong means loading
knowledge that never reaches the agent — verified the hard way this session.

## The runtime path

Every agent's prompt is assembled by **`fn_agent_context_v3(agent_key, task_class, task_text,
category_key, budget)`** — the hottest path in the company (agent_brain, action_worker, dept_plan,
agent_act, exec_agents all call it). Its knowledge sections:

- **`deterministic_rules`** ← `ops_knowledge` where `layer in (authority,kpi,decision_playbook,policy)`, scoped, complete (not ranked).
- **`company_core` / `department_knowledge` / `role_knowledge` / `category_knowledge`** ← **`fn_context_slice(...)`**, which reads **`ops_knowledge`** and this is where DOMAIN / PROFESSIONAL knowledge lives.
- **`validated_experience`** ← `agent_knowledge` where **`layer='experience' AND validation_status='validated'`** (max 8, by confidence). This is the ONLY thing v3 reads from `agent_knowledge`.
- `live_data_required`, `tools`, `company_objective`, `identity`.

### `fn_context_slice` — the domain-knowledge retriever

Reads `public.ops_knowledge` where `runtime_eligible AND supersession_state='current' AND layer=<slice>`, scoped by:

| slice | scope predicate |
|---|---|
| `company_core` | `scope_type='company'` |
| `department_shared` | `dept_key = any(fn_dept_scope(agent.department))` (includes absorbed/merged dept keys) |
| `role_specific` | `role_key = any(agent's packaged role_ids)` |
| `category_specialist` | `category_key = p_category_key` |

Within the scope it **ranks by `ts_rank(tsv, task_tsquery)`** (the query decides membership; `tsv` is a generated column), falling back to authority order only when fewer than 3 rows match. Output is budget-capped (~1800 chars/row, running sum ≤ budget share).

## The three traps (all measured, all cost time this session)

1. **`agent_knowledge` is NOT the domain-knowledge store.** v3 reads only `experience`/`validated` from it. Loading cert knowledge there as `profession`/`author_verified` **does not surface** — proven: inserting an EP row into `agent_knowledge` returned `surfaces_in_context=false`. The `profession` layer is never read by v3.
2. **`kb_chunks` (the 97k embedded corpus) is NOT on the agent-context path.** It is read by the `kb_search`/`kb_match` edge+SQL routines (customer FAQ, classification), not by `fn_agent_context_v3`. Embedding backfill helps those, not agent expertise.
3. **The QA roles had a competency MAP, not the CONTENT.** `ops_knowledge` role_specific for `qa-and-testing-reviewer-auditor` was a `competency_map.yaml` listing competencies to master (and the rule *"not certified by file ingestion — must pass blind evaluations"*), but not the technique knowledge itself.

## The correct load (proven)

Load synthesised cert knowledge into **`ops_knowledge`** as `role_specific` (role_key = the packaged
role id) or `department_shared` (dept_key), `runtime_eligible=true`, `supersession_state='current'`,
`layer` set, `tsv` generated from content — then `fn_context_slice` surfaces it **task-ranked**.

Proven end to end: `scripts/sql/expertise_istqb_ctfl_qa_test_design.sql` loaded four ISTQB CTFL
concepts for the four QA role_keys; `fn_agent_context_v3('ai_qa_specialist','test_design', <EP/BVA
task>)` now returns them **first** in `role_knowledge`, ahead of the competency map.

## Consequence for the pipeline (supersedes the earlier framing)

The expertise pipeline's load step targets **`ops_knowledge`** (role/department/category scoped, tsv),
not `agent_knowledge` and not `kb_chunks`. The knowledge packs' own `certification_rule` already states
the bar: **a role is certified by passing blind evaluations, not by file ingestion** — so step 6 (the
exam loop) is not optional; ingestion only makes the knowledge retrievable. The embedding/`kb_search`
work in `SEMANTIC_RETRIEVAL_STATE.md` is a separate track (corpus/FAQ retrieval), not the agent-prompt
path — unless a future change routes `fn_context_slice`/v3 through the corpus too.
