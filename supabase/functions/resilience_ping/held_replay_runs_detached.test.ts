// THE HELD REPLAY IS NOT PART OF THE itlater RUN (it_engineer, 27 Oct 2026; review of #1688). Measured on production:
// duty:detached_itlater:itlater "passed its 120000 ms limit", seen 51 times 16:17-20:32Z, with the replay as step 14 of
// that run. A replay inside it spends the time of every step after it (reasoning_escalate's owed holding notices,
// routine_judgements, wa_arrival_sweep, ceo_support_replies). It is kicked into its own detached run, handed that
// run's deadline. Read from the source: the function's module cannot be imported without its environment.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';

const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
// comments out, so a sentence that names a call never counts as one
const code = src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`])\/\/.*$/gm, '$1');
function body(fn: string): string {
  const at = code.indexOf('async function ' + fn + '(');
  assert(at >= 0, fn + ' not found');
  let i = code.indexOf('{', code.indexOf(')', at)), depth = 0;
  for (let j = i; j < code.length; j++) {
    if (code[j] === '{') depth++;
    else if (code[j] === '}' && --depth === 0) return code.slice(i, j + 1);
  }
  throw new Error(fn + ' has no closing brace');
}

Deno.test('the itlater run only kicks the replay: no replayHeld call in it', () => {
  const later = body('itLaterDutiesTick');
  assertEquals([...later.matchAll(/\breplayHeld\s*\(/g)].length, 0, 'itLaterDutiesTick still reasons held rows inline');
  assertMatch(later, /step\('reasoning_held',\s*async \(\) => kickDetached\('heldReplay'\)\)/);
});

Deno.test('the replay has its own detached run, and is handed that run\'s deadline', () => {
  assertMatch(code, /heldReplay:\s*\{\s*run:\s*heldReplayTick\s*\}/);
  const tick = body('heldReplayTick');
  assertMatch(tick, /const deadline = Date\.now\(\) \+ DETACHED_MS/);
  assertMatch(tick, /replayHeld\(admin, REPLAY_CLAIM, heartbeatDeps\(admin\),[\s\S]*\bdeadline\b/);
  assertEquals([...code.matchAll(/\breplayHeld\s*\(/g)].length, 1, 'one replay, in heldReplayTick');
});

// 27 Oct 2026 (it_engineer): the 22:01:12Z itlater run overran its 120 s with routine_judgements still going (five rows
// judged one after another at ~60 s each). The judgements are kicked into their own detached run, handed its deadline.
Deno.test('the itlater run only kicks the routine judgements; their own run keeps a deadline', () => {
  const later = body('itLaterDutiesTick');
  assertEquals([...later.matchAll(/\bdrainRoutineJudgements\s*\(/g)].length, 0, 'itLaterDutiesTick still judges inline');
  assertMatch(later, /step\('routine_judgements',\s*async \(\) => kickDetached\('routineJudgements'\)\)/);
  assertMatch(code, /routineJudgements:\s*\{\s*run:\s*routineJudgementsTick\s*\}/);
  const tick = body('routineJudgementsTick');
  assertMatch(tick, /const deadline = Date\.now\(\) \+ DETACHED_MS/);
  assertMatch(tick, /drainRoutineJudgements\(heartbeatDeps\(admin\), 5, null, \{ deadline \}\)/);
});

// The next overrun names its step: every itlater step is timed on the run's clock, and runDetached hands the clock's
// snapshot to the finding and the function log whichever side of the race won.
Deno.test('every itlater step is timed, and the detached run settles with the timing', () => {
  const later = body('itLaterDutiesTick');
  assertMatch(later, /clock\.begin\(name\);[\s\S]*?clock\.end\(name, /);
  const run = body('runDetached');
  assertMatch(run, /Promise\.race\(\[d\.run\(clock\), cap\]\)/);
  assertMatch(run, /const timing = clock\.snapshot\(\)/);
  assertMatch(run, /detachedItems\(name, out, !!d\.nested, timing\)/);
  assertMatch(run, /detached_timing/);
});
