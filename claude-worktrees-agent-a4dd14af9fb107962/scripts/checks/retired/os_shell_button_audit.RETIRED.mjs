// RETIRED 9 September 2026 — its subject was deleted.
//
// Subject: every button in the OS console reaches a real os_api action.
//
// It read supabase/functions/os_api/index.ts and src/components/osx/OsxShell.tsx at module level and
// cross-checked that every button in the shell named an action the API actually implements. Both
// files are deleted, so it cannot start — it throws ENOENT before the first test runs.
//
// THE LESSON IN IT IS NOT RETIRED: a button that calls an action nobody implemented is invisible
// until a person clicks it. Any future admin surface deserves the same check, written against
// whatever replaces os_api.
//
// The founder ruled on 8 Sep: "anything related to OS can be removed. its totally irrelevant to my
// new structure". The console, its twelve edge functions and its routes are gone.
//
// RETIRED RATHER THAN SOFTENED. Editing it to pass would leave a check going green while the thing
// it checks does not exist, which is worse than no check at all.
//
// TO REVIVE: build the replacement surface, then rename this back to .test.mjs and re-point it.
// The founder's 6 Sep 2026 OS walk — the mechanisms behind each fix, asserted on the shell source.
// A rendered walk needs his signed-in session; this is the check that runs without one and fails
// the moment any of the mechanisms is put back the way it was.
//
//   node --test scripts/checks/os_shell_button_audit.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const shell = readFileSync(join(root, 'src/components/osx/OsxShell.tsx'), 'utf8');
const osApi = readFileSync(join(root, 'supabase/functions/os_api/index.ts'), 'utf8');
const command = readFileSync(join(root, 'src/components/ui/command.tsx'), 'utf8');

test('1. the Observe/Control Mode drawer is gone from the shell, the client and os_api', () => {
  assert.equal(existsSync(join(root, 'src/components/osx/ControlMode.tsx')), false, 'ControlMode.tsx must stay deleted');
  assert.doesNotMatch(shell, /ControlModeProvider|ControlModeIndicator/, 'the shell must not mount the drawer or the pill');
  for (const a of ['control_mode_status', 'control_mode_challenge', 'control_mode_open', 'control_mode_close']) {
    assert.doesNotMatch(osApi, new RegExp(`action === '${a}'`), `os_api must not dispatch ${a}`);
  }
  assert.match(osApi, /fn_control_mode_require/, 'the action classification gate itself stays');
});

test('1b. every DialogContent carries a title (Radix a11y warning source)', () => {
  assert.match(command, /<DialogTitle className='sr-only'>/, 'CommandDialog needs a visually hidden DialogTitle');
  let i = 0; const missing = [];
  while ((i = shell.indexOf('<SheetContent', i)) >= 0) {
    const j = shell.indexOf('</SheetContent>', i);
    if (!/SheetTitle|DialogTitle/.test(shell.slice(i, j))) missing.push(shell.slice(0, i).split('\n').length);
    i = j + 1;
  }
  assert.deepEqual(missing, [], 'SheetContent without a SheetTitle at lines ' + missing.join(', '));
});

test('4. every command-palette selection opens the module through go(), like the sidebar', () => {
  const a = shell.indexOf('<CommandDialog open={paletteOpen}'); const b = shell.indexOf('</CommandDialog>', a);
  const palette = shell.slice(a, b);
  assert.ok(a > 0 && b > a, 'palette block present');
  assert.doesNotMatch(palette, /setCur\(/, 'a palette item that only calls setCur highlights the sidebar and opens no tab');
  assert.ok((palette.match(/onSelect=\{\(\) => \{ go\(/g) || []).length >= 8, 'module and action items call go()');
});

test('11 (and 5, 6). only the active tab is mounted; realtime remounts are guarded', () => {
  assert.match(shell, /<div key=\{cur \+ ':' \+ twinKey\} data-module=\{cur\}>\{renderModule\(cur, go\)\}<\/div>/, 'main renders the current module only');
  assert.doesNotMatch(shell, /className=\{id === cur \? '' : 'hidden'\}/, 'no hidden-but-mounted background panels');
  assert.match(shell, /document\.querySelector\('\[role="dialog"\]\[data-state="open"\]'\)\) return;/, 'no remount while a dialog or sheet is open');
  assert.match(shell, /if \(t - lastRemount\.current < 15000\) return;/, 'remounts are rate-limited');
});

test('9. a floating window closes on Escape and its taskbar does not span the viewport', () => {
  assert.match(shell, /if \(e\.key !== 'Escape'\) return;[\s\S]{0,200}close\(top\.id\);/, 'Escape closes the top-most window');
  assert.doesNotMatch(shell, /fixed bottom-0 left-0 right-0 h-9 z-\[60\]/, 'the old full-width taskbar strip swallowed clicks along the bottom of the page');
});

test('2. Smart Engine renders the parked as parked, never as an error, behind a toggle', () => {
  assert.match(shell, /const parked: any\[\] = d\?\.parked \|\| \[\];/, 'reads the parked list fn_agents_board returns');
  assert.match(shell, /'Parked \(' \+ parked\.length \+ '\)'/, 'the toggle names the count');
  assert.match(shell, /r\.active \? \(r\.last_status \|\| '—'\) : 'parked'/, 'a parked row shows "parked", not its stale last_status');
});

test('8. the spoken brief reads the same sentence the command channel returns', () => {
  assert.match(shell, /const brief = d\?\.brief_text \? String\(d\.brief_text\)/, 'sayBrief prefers fn_ws_exec_home().brief_text');
});
