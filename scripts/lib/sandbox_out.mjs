// Where the sandbox rehearsals write their reports (owner: it_engineer, 26 Oct 2026).
//
// QD_SANDBOX_OUT when set. Otherwise the founder's review folder on his desktop when this machine has
// one, and a temp folder everywhere else (a claude.ai/code cloud session has no desktop). Before
// 26 Oct 2026 six e2e scripts hard-coded that desktop folder under one Windows user's home.
import { existsSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';

const desktop = join(homedir(), 'Desktop', 'QuotesDone Sandbox Test 2026-10');

export const SANDBOX_OUT = process.env.QD_SANDBOX_OUT
  || (existsSync(desktop) ? desktop : join(tmpdir(), 'qd-sandbox-test'));
