// resend_inbound: the reasoning engine dependencies a test can inject. Moved out of index.ts unchanged (9 Nov 2026).
import { type ThinkDeps } from '../../_shared/think.ts';

// The reasoning engine's model, embedder and database. A test injects a mocked one; nothing else does.
export let thinkDeps: ThinkDeps | null = null;
export function useThinkDeps(d: ThinkDeps | null) { thinkDeps = d; }
