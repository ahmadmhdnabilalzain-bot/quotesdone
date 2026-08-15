// Read docs/phase-c/_inventory.json and print the numbers Stage C1 turns on.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { REPO } from './lib/package.mjs';
const inv = JSON.parse(readFileSync(join(REPO, 'docs', 'phase-c', '_inventory.json'), 'utf8'));

const n = a => a.length;
console.log('measured_at            ', inv.measured_at);
console.log('cron jobs              ', n(inv.cron), ' active', inv.cron.filter(c => c.active).length,
            ' never ran', inv.cron.filter(c => Number(c.runs) === 0).length);
console.log('db routines            ', n(inv.db_functions),
            ' volatile', inv.db_functions.filter(f => f.provolatile === 'v').length,
            ' write-shaped', inv.db_functions.filter(f => f.writes_sql).length,
            ' trigger-called', inv.db_functions.filter(f => f.called_by_trigger).length);
console.log('triggers               ', n(inv.db_triggers), ' disabled', inv.db_triggers.filter(t => t.tgenabled !== 'O').length);
console.log('state tables           ', n(inv.state_tables));
console.log('runtime workflow defs  ', n(inv.runtime_workflows), ' with runs', inv.runtime_workflows.filter(w => Number(w.runs) > 0).length);
console.log('event subscriptions    ', n(inv.event_subscriptions));
console.log('executors              ', n(inv.executors), ' active', inv.executors.filter(e => e.active).length,
            ' notifies_human', inv.executors.filter(e => e.notifies_human).length);
console.log('edge functions         ', n(inv.edge),
            ' no caller', inv.edge.filter(e => e.callers === 0).length,
            ' no caller & no external surface', inv.edge.filter(e => e.callers === 0 && !e.external_surface && !e.verify_jwt_false).length,
            ' mutating', inv.edge.filter(e => e.mutates).length);
console.log('frontend routes        ', n(inv.frontend), ' api', inv.frontend.filter(f => f.is_api).length,
            ' mutating', inv.frontend.filter(f => f.mutates).length);

const total = n(inv.cron) + n(inv.db_functions) + n(inv.db_triggers) + n(inv.state_tables)
  + n(inv.runtime_workflows) + n(inv.event_subscriptions) + n(inv.edge) + n(inv.frontend);
console.log('TOTAL components       ', total);

console.log('\nedge functions with no caller and no external surface:');
console.log(inv.edge.filter(e => e.callers === 0 && !e.external_surface && !e.verify_jwt_false).map(e => e.slug).join(' '));
console.log('\ncron jobs that never ran:');
console.log(inv.cron.filter(c => Number(c.runs) === 0).map(c => `${c.jobname}${c.active ? '' : '(off)'}`).join(' '));
console.log('\ninactive cron jobs that HAVE run:');
console.log(inv.cron.filter(c => !c.active && Number(c.runs) > 0).map(c => `${c.jobname}=${c.runs}`).join(' '));
console.log('\nruntime workflow defs with zero runs:');
console.log(inv.runtime_workflows.filter(w => Number(w.runs) === 0).map(w => w.workflow_key).join(' '));
