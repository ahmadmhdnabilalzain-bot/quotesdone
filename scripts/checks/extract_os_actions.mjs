// Read os_api's source and return (a) every action it dispatches on and (b) the classification it
// declares for each. The classification check compares the two, so an action added without a
// classification fails the build instead of being discovered later in an audit.
//
// Three dispatch shapes exist in os_api/index.ts and all three are parsed:
//   if (action === 'x')        - the common case
//   case 'x':                  - none today, kept so a future switch is not missed
//   WS[action]                 - a table of workspace reads, dispatched by key
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const OS_API_PATH = path.join(HERE, '..', '..', 'supabase', 'functions', 'os_api', 'index.ts');

const NAME = "[a-zA-Z0-9_.-]+"; // action names include dots: ws.exec, ws.suppliers

function stripComments(src) {
  // Remove /* */ blocks and // tails so prose naming an action is never read as a dispatch.
  return src.replace(/\/\*[\s\S]*?\*\//g, '').split('\n').map((l) => l.replace(/\/\/.*$/, '')).join('\n');
}

export function readSource() {
  return fs.readFileSync(OS_API_PATH, 'utf8');
}

/** Every action os_api will actually route. */
export function extractDispatched(rawSrc) {
  const src = stripComments(rawSrc);
  const out = new Set();
  for (const m of src.matchAll(new RegExp(`action\\s*===\\s*'(${NAME})'`, 'g'))) out.add(m[1]);
  for (const m of src.matchAll(new RegExp(`^\\s*case\\s+'(${NAME})'\\s*:`, 'gm'))) out.add(m[1]);
  // The WS table: every key is a dispatchable action via `if (WS[action])`.
  const ws = src.match(/const\s+WS\s*:\s*Record<string,\s*string>\s*=\s*\{([\s\S]*?)\n\};/);
  if (ws) for (const m of ws[1].matchAll(new RegExp(`'(${NAME})'\\s*:`, 'g'))) out.add(m[1]);
  return out;
}

/**
 * Every classification os_api may declare. Kept as a named list, not inlined into the regex,
 * because a class the PARSER does not know reads as "dispatched but unclassified" — which is the
 * loudest failure this checker has, and it fired on `founder_gated` the day that class was added
 * correctly to both gates. Extending the vocabulary is a deliberate act; add the value here and
 * pin it in os_action_classification.test.mjs, as mode_control and founder_gated both are.
 */
export const ACTION_CLASSES = ['read_only', 'mutating', 'mode_control', 'founder_gated'];

/** The declared classification table: action -> one of ACTION_CLASSES. */
export function extractClassification(rawSrc) {
  const src = stripComments(rawSrc);
  const block = src.match(/const\s+ACTION_CLASS\s*:\s*Record<string,\s*ActionClass>\s*=\s*\{([\s\S]*?)\n\};/);
  if (!block) return null; // not yet declared - the checker reports this as a failure, not a crash
  const out = new Map();
  // Keys are quoted only when they have to be (ws.exec), so both forms are accepted.
  const entry = new RegExp(`(?:'(${NAME})'|(${NAME}))\\s*:\\s*'(${ACTION_CLASSES.join('|')})'`, 'g');
  for (const m of block[1].matchAll(entry)) out.set(m[1] || m[2], m[3]);
  return out;
}

if (process.argv[1] && process.argv[1].endsWith('extract_os_actions.mjs')) {
  const src = readSource();
  const dispatched = [...extractDispatched(src)].sort();
  const cls = extractClassification(src);
  console.log(JSON.stringify({ dispatched, classified: cls ? Object.fromEntries([...cls].sort()) : null }, null, 2));
  console.error(`${dispatched.length} dispatched, ${cls ? cls.size : 0} classified`);
}
