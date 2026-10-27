---
name: checkpoint-5-oct-release-operator
description: "5 Oct 2026 release-operator state: what merged and was applied live, what is still open, tonight's kb trim, the blocked rewrite, and the release-script lessons"
metadata:
  node_type: memory
  type: project
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-10-05T16:36:53.951Z
---

**Merged and applied, 4–5 Oct 2026** (each verified by read-back; main drift 0 after every one):
- Infrastructure and process: #1184 and #1215 (the DeepSeek price twice), #1147, #1149 plus #1196 (#1149 applied by hand after the train applied its probe first), #1154, #1208 (deploy diff base), #1211, #1213, #1216 (exam alias `q`, plus pending-aware alias check).
- Product: #1200 (no card fee), #1194 (founder digest), #1173 (money: payment rows), #1195, #1206 (0 gaps in recruit), #1212 (books-vs-bank gap exactly 316.06), #1175, #1188, #1203, #1204, #1209, #1214, #1158, #1217 (matrix v2 probe OK routes=76 review_pairs=111), #1218, #1219 (held 628 → 281), #1186.
- Closed: #1202 (empty diff), #1205 and #1207 (superseded).

**Open at handover:**
- #1220 kb copy-swap: CHANGES. Export-registry row missing; window must be checked per statement.
- #1226 web_search: approved and queued.
- #1187: CHANGES. No-promo-price ruling: price drops are adopted only after 14 days, increases at once, and the CI check compares against the adopted price.
- #1178: CHANGES (word matching). #1180: CHANGES (no stored answers; double-click). #1185: Dubai time zone. #1190: hired-off-platform message. #1193: backup registry. #1201: CI red (RTL dir, tab-bar check).
- #1203's `--ml` loader: was stopped once at 100/1427 because it hit 429 alongside the train; rerun queued after #1226.
- kb trim scheduled 23:02 Dubai 5 Oct (`scratchpad/rel1004/trim_tonight.sh`).
- VACUUM FULL is superseded by #1220. There is no direct DB connection on this machine (management API only, 2-minute cap).

**Lessons:**
- A PR branch behind main reads "drift" on the database check: update the branch first.
- Re-labelling is what starts the kernel gate. `gh pr checks` right after a push shows the OLD head's results.
- The DeepSeek catalogue price flapped 3 times in 6 days. That is why the no-promo-price rule exists.
- Hooks write their own output into files made with shell redirects (#1209, #1218, #1219 notes). Write notes with the Write tool.

Related: [[only-the-release-operator-labels]], [[never-push-to-a-green-labelled-pr]].
