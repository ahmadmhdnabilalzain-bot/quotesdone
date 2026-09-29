// OUR OWN PROBE, PROVEN BY A CREDENTIAL (it_engineer, 29 Sep 2026, incident 508).
//
// Measured in the edge logs: the hourly unauthenticated POST to supplier_portal (401) came from
// user-agent "Deno/2.1.4 (SupabaseEdgeRuntime; ref=htdblwldjkcgjvmqkbeh)", body length 22
// (`{"action":"dashboard"}`), ?forceFunctionRegion=ap-southeast-1 - resilience_ping's hourly launch-path
// probe (_shared/launch_path.ts), which asks for that refusal on purpose to prove the door answers.
// Its 401 rows carried nothing that told them from a stranger's, so fn_it_detect's refusal_rate counted
// them and opened incident 508.
//
// The probe now presents its scoped internal credential in the x-qd-probe header. Only a credential that
// fn_internal_auth accepts for THIS function marks the refusal `fixture` (the key refusal_rate already
// excludes, as login_otp's reserved-number refusals are). A header alone marks nothing, so a stranger
// cannot hide a refusal by claiming to be the probe. The header is read only on the refusal path.
import { requireInternal } from './internal_auth.ts';

export const PROBE_HEADER = 'x-qd-probe';

// deno-lint-ignore no-explicit-any
export async function probeCaller(admin: any, req: Request, fnName: string): Promise<Record<string, unknown>> {
  const secret = req.headers.get(PROBE_HEADER);
  if (!secret) return {};
  try {
    const auth = await requireInternal(admin, secret, fnName);
    return auth.ok ? { caller: 'fixture', fixture: 1, probe: 'launch_path' } : {};
  } catch (_e) { return {}; }
}
