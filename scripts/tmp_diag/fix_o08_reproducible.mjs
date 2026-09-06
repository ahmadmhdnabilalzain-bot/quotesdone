// A DELIVERABLE THAT CARRIES AN ABSOLUTE ROW COUNT DOES NOT REPRODUCE.
//
// scripts/checks/phase_d_deliverables_match_production.test.mjs re-runs each builder into a temp
// directory and diffs the result against the committed copy, and the injected-defect builder
// redacts only runs of six or more digits. Three of the new branches printed absolute counts —
// `tasks/stepruns/traces 68/68 40/40 5987/5987`, `tasks 59/59`, `recorded scans 5` — and every one
// of those absolute values moves between runs, because scheduled cron monitors write
// phase_c_trace rows every five minutes. The FINDING is identical; the row would not be.
//
// The counts become the thing the case is actually about: whether the refusal left anything behind.
import { readFileSync, writeFileSync } from 'node:fs';

const p = 'scripts/sql/phase_d_o08_the_nine_that_remained_executed.sql';
let s = readFileSync(p, 'utf8');
let bad = 0;
const rep = (find, repl, label) => {
  const n = s.split(find).length - 1;
  if (n !== 1) { console.error(`ANCHOR ${label}: matched ${n}`); bad++; return; }
  s = s.replace(find, repl);
};

rep(`           and (select count(*) from (select unnest(string_to_array(split_part(v_a5_msg,'|',7),' ')) x) t
                 where split_part(x,'/',1) <> split_part(x,'/',2)) = 0;`,
  `           and split_part(v_a5_msg,'|',7) = 'unchanged';`, 'AUTH-005 residue assertion');

rep(`    observed := format('overlay owner->%s alias->%s standing role->%s; owner-admissibility predicate %s; tasks/stepruns/traces %s',`,
  `    observed := format('overlay owner->%s alias->%s standing role->%s; owner-admissibility predicate %s; tasks, step runs and traces across both refusals: %s',`,
  'AUTH-005 observed');

rep(`           and split_part(split_part(v_l5_msg,'|',6),'/',1) = split_part(split_part(v_l5_msg,'|',6),'/',2)`,
  `           and split_part(v_l5_msg,'|',6) = 'unchanged'`, 'LEGAL-005 residue assertion');

rep(`    observed := format('W08-S06 review service: creator->%s alias-of-creator->%s independent->%s; task boundary %s / alias %s; tasks %s; fn_kernel_reviewer_independent self=f alias=f cross-vocab=f independent=t',`,
  `    observed := format('W08-S06 review service: creator->%s alias-of-creator->%s independent->%s; task boundary %s / alias %s; tasks across both refusals: %s; fn_kernel_reviewer_independent self=f alias=f cross-vocab=f independent=t',`,
  'LEGAL-005 observed');

// ---- PD-PRIV-005: the scan-row count is an estate total, not this case's subject -----------
rep(`    observed := format('recorded scans %s; dirty bytes -> %s, cleared bytes -> %s; dispatch %s / %s; BR-011 %s / %s',
                       v_p5_n, v_p5[1], v_p5[2], v_p5[3], v_p5[4], v_p5[5], v_p5[6]);`,
  `    -- v_p5_n is asserted (>= 4 recorded scans, or the verdicts below are about nothing) and NOT
    -- printed: it is an estate total that grows whenever another artefact is scanned, and a
    -- deliverable row that moves for a reason the case is not about does not reproduce.
    observed := format('dirty bytes -> %s, cleared bytes -> %s; dispatch %s / %s; BR-011 %s / %s',
                       v_p5[1], v_p5[2], v_p5[3], v_p5[4], v_p5[5], v_p5[6]);`, 'PRIV-005 observed');

if (bad) process.exit(1);
writeFileSync(p, s);
console.log('made the three volatile observations reproducible');
