// THE DEMO-DATA PURGE (founder ruling 1199, 12 Oct 2026; it_engineer). The work is public.fn_demo_purge, guarded on
// the demo markers and on the count of every NON-demo customer, supplier, inquiry, quote, transaction and login
// (scripts/sql/demo_data_is_purged_by_its_marker_and_no_seat_duty_reads_it.sql). This only drives it and prints.
//
//   node scripts/it/purge_demo_data.mjs                 DRY RUN: the exact plan, rolled back; before counts
//   node scripts/it/purge_demo_data.mjs --apply         purge, then the after counts
//   node scripts/it/purge_demo_data.mjs --verify-zero   exit 1 unless no demo row is left and both queues are drained
//
// Storage objects and Dropbox copies are listed in signup_purge_object / signup_purge_dropbox and removed by
// dropbox_backup (25 Dropbox paths and 50 objects per run, 15 minutes after listing), so --verify-zero reaches 0 only
// once those queues have drained.
import { sql } from '../lib/db.mjs';

const APPLY = process.argv.includes('--apply');
const VERIFY = process.argv.includes('--verify-zero');
const one = async (q) => Object.values((await sql(q))[0])[0];
const show = (label, o) => console.log(`\n${label}\n` + JSON.stringify(o, null, 2));

const before = await one('select public.fn_demo_purge_verify()');
show('BEFORE (demo rows left, open queue items)', before);

if (VERIFY) {
  const plan = await one('select public.fn_demo_purge(false)');
  const META = new Set(['mode', 'demo_ids', 'purge_id', 'real_counts_unchanged', 'storage_objects_listed', 'dropbox_listed']);
  const rows = Object.entries(plan).filter(([k, v]) => !META.has(k) && Number(v) > 0);
  const left = Object.entries(before).filter(([, v]) => Number(v) > 0);
  show('a purge now would still remove', Object.fromEntries(rows));
  if (rows.length || left.length) { console.log('\nVERIFY-ZERO: NOT ZERO'); process.exit(1); }
  console.log('\nVERIFY-ZERO: 0 demo rows, 0 open storage or Dropbox items');
  process.exit(0);
}

const out = await one(`select public.fn_demo_purge(${APPLY})`);
show(APPLY ? 'PURGED' : 'DRY RUN (rolled back; nothing was deleted)', out);
if (APPLY) show('AFTER', await one('select public.fn_demo_purge_verify()'));
