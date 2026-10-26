// THE PRELUDE A ROLLED-BACK PROBE PUTS IN FRONT OF ITS TEXT TO PROVE A SEAT LOOP ON ZZ DEMO FIXTURES (it_engineer, 27 Oct 2026).
//
// Ruling 1199 (demo_activity_files_no_seat_task_or_handoff.sql) files no handoff and no org task for a demo subject.
// a_rolled_back_probe_may_file_demo_seat_work_under_its_own_switch.sql lets a probe switch that off for its own
// transaction with qd.seat_work_fixtures. This returns the SQL to prepend: the switch file while it is still pending
// (so the probe measures the body that will be applied), then the transaction-local switch. Only for text sent
// through safe_replay.mjs's replaySql, which always rolls back.
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const NAME = 'a_rolled_back_probe_may_file_demo_seat_work_under_its_own_switch';

export function seatWorkFixtures(repo = REPO) {
  const pending = existsSync(join(repo, 'scripts/sql/pending', `${NAME}.txt`));
  const file = pending ? readFileSync(join(repo, 'scripts/sql', `${NAME}.sql`), 'utf8') + '\n;\n' : '';
  return file + `select set_config('qd.seat_work_fixtures', 'on', true);\n`;
}
