// Execute a statement against STAGING and print whatever comes back, including the error text.
// Used to exercise a branch no production data reaches: a DO block that mutates, reads the result
// and then RAISEs it rolls its own mutation back while still returning the observation.
import { readFileSync } from 'node:fs';
import { mgmtWrite } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';
try { console.log(JSON.stringify(await mgmtWrite(STAGE, readFileSync(process.argv[2], 'utf8'), 'probe'))); }
catch (e) { console.log('PROBE RESULT: ' + String(e.message || e)); }
