// it_engineer — the IT Engineer seat's runtime. The company's FIFTH agent, and the only one that
// does not report to the CEO.
//
// WHY IT EXISTS. The founder, 9 September 2026: "fine then we build the it engineer to monitor
// everything. once their is an issue, he will email me directly so i can open a session with you to
// fix it. about his knowledge, you have to keep him really capable of such tasks. he reports to me
// directly only. however he monitor literally everything in the app and the website"
//
// THE CREDENTIAL DECIDES THE SEAT, NOT THE CALLER. ceo_agent shipped on 8 Sep reading `body.as` and
// believing it, which let any holder of an in-scope credential present as the CEO — a real
// confused-deputy defect, fixed the same day. Nothing in this file reads a seat name off the payload.
//
// NO MODEL CALL, ANYWHERE IN HERE, and that is not a limitation for these actions. Every one of them
// is a database read: whether a seat is registered, what its standing grants say, what a routine
// answers when asked. There is no judgement in any of it, which is why none is faked.
//
// WHAT IS DELIBERATELY ABSENT — THE SEAM, NAMED, so nobody mistakes silence for capability.
// This file holds NO monitoring action. It does not probe the website, does not read health_checks,
// does not walk the scheduled jobs, does not open an incident and does not send the founder anything.
// The monitoring engine, the alerting path and the instrumentation are a separate build, in flight
// alongside this one. THE SEAM IS HERE: a new `action` branch in the switch below, authorised by
// `fn_agent_may_act('it_engineer','monitoring'|'diagnosis'|'escalation')` exactly as `authority`
// below asks it, and attributed with `run(...)` exactly as these three actions are. Everything that
// build needs from the seat — the credential, the grants, the refusal routes, the run log — is live
// and is proved live by `health`.
//
// Naming that absence is cheaper than discovering later that a green `status` meant "nothing is
// wrong" when it meant "nothing looks".
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const J = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

async function sec(k: string): Promise<string | undefined> {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return data?.value as string | undefined;
}

// THE ONLY CREDENTIAL THAT IS THIS SEAT. An unrecognised context is refused rather than defaulted.
const SEAT_BY_CREDENTIAL: Record<string, 'it_engineer'> = {
  'fn.it_engineer': 'it_engineer',
};

type Caller = { kind: 'it_engineer' | 'founder'; context: string | null } | null;

async function whoami(req: Request, body: Record<string, unknown>): Promise<Caller> {
  if (body?.__secret) {
    const r = await requireInternal(admin, String(body.__secret), 'it_engineer');
    // ok-but-unrecognised is NOT a fallback to the seat. It is a refusal.
    if (r.ok) return SEAT_BY_CREDENTIAL[r.context] ? { kind: 'it_engineer', context: r.context } : null;
  }
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!jwt) return null;
  const { data } = await admin.auth.getUser(jwt).catch(() => ({ data: { user: null } } as never));
  const email = String((data as { user?: { email?: string } })?.user?.email || '').toLowerCase();
  if (!email) return null;
  const allow = (await sec('admin_emails') || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
  // The founder is the one human this seat answers to, so he is the one human it answers.
  return allow.includes(email) ? { kind: 'founder', context: null } : null;
}

// EVERY CALL LEAVES A ROW. fn_agents_board LEFT JOINs agent_runs on agent = agent_key, so a seat
// that never writes one renders with runs24 = 0 — indistinguishable from a seat that is down. For
// the seat whose entire job is telling the difference between "quiet" and "dead", writing its own
// liveness signal is not optional. Best-effort: attribution must never fail the call it attributes.
async function run(action: string, status: string, counts: Record<string, unknown>, note?: string) {
  try {
    await admin.from('agent_runs').insert({
      agent: 'it_engineer',
      status,
      started_at: new Date().toISOString(),
      finished_at: new Date().toISOString(),
      counts: { action, ...counts },
      note: note ?? null,
    });
  } catch { /* an unwritten log must not turn a good answer into a 500 */ }
}

// THE FIVE CLASSES THIS SEAT IS DEFINED BY — three it holds, two it must be refused. They are asked
// of fn_agent_may_act at call time rather than read from a cached list, so a grant revoked a minute
// ago cannot be used from a stale answer, and a grant quietly widened shows up here immediately.
// 'deploy' is asked precisely BECAUSE there is no grant for it: a refusal that is never exercised is
// a refusal nobody has seen work.
const CLASSES = ['monitoring', 'diagnosis', 'escalation', 'job_rerun', 'deploy'] as const;

async function mayAct(cls: string, amountAed: number | null = null) {
  const { data, error } = await admin.rpc('fn_agent_may_act', {
    p_grantee_role_id: 'it_engineer', p_action_class: cls, p_amount_aed: amountAed,
  });
  if (error) return { may_act: null, error: error.message };
  return (data || {}) as Record<string, unknown>;
}

// WHERE A REFUSAL'S ROUTE COMES FROM, AND WHY IT IS NOT IN THIS FILE.
//
// fn_agent_may_act is the general authority rule and it is shared with every other seat. On a
// refusal it names route 'ceo_case_decision', which is correct for the four seats that report to the
// CEO and is NOT correct for this one: the founder ruled on 9 Sep 2026 that the IT engineer "reports
// to me directly only", and for a deploy or a configuration change the route is a session he opens,
// not a CEO decision. Forking fn_agent_may_act to say so would create a second authority rule to
// keep in step, and the one that drifted would be this one.
//
// So the general rule is returned VERBATIM and untouched, and the seat's own route is read out of
// public.org_role.forbidden_decisions — one row, in the database, written by the seat's own SQL file.
// The TypeScript holds no policy: every line there is TAGGED with the action class it refuses, as
// '[deploy] …', and this looks the line up by that exact tag. If no line carries the tag it returns
// null rather than inventing a route.
//
// IT USED TO GUESS, AND THE PROBE CAUGHT IT. The first draft matched the class name against the
// prose as a substring — 'deploy' appears in "DEPLOYING AN EDGE FUNCTION" and worked, 'job_rerun'
// does not appear in "RE-RUNNING A SCHEDULED JOB" and came back null. A refusal with no route is
// the one thing this function must never produce, and a heuristic that is right on the case it was
// written against is how you ship one. The tag is in the database, and the match is exact.
function routeFor(cls: string, forbidden: string[]): string | null {
  const tag = '[' + cls + '] ';
  return forbidden.find((f) => f.startsWith(tag)) ?? null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const caller = await whoami(req, body);
    if (!caller) return J({ error: 'unauthorized' }, 401);

    const action = String(body.action || '').trim();

    // ── HEALTH ─────────────────────────────────────────────────────────────────────────────────
    // IS THE SEAT REAL — asked of the database, never asserted. Three questions:
    //   what it IS      (org_agents / org_role, and the deliberate absence of a reporting edge)
    //   what it MAY DO  (fn_agent_may_act on all five classes, permits and refusals alike)
    //   what it REACHES (the credential's own scope, and the functions it owns)
    // plus whether the one route the founder asked for — mail that reaches him directly — is open,
    // measured rather than assumed.
    if (action === 'health' || action === 'status') {
      const [agent, role, edge, grants, cred, owner, mailPolicy, routes, lastRuns] = await Promise.all([
        admin.from('org_agents').select('agent_key,active,available,title,routing_tier,department,manager_key').eq('agent_key', 'it_engineer').maybeSingle(),
        admin.from('org_role').select('role_id,display_name,status,authority_level,runtime_mode,runtime_agent_key,responsibilities,owned_decisions,forbidden_decisions,handoff_targets,escalation_targets,manager_role_id').eq('role_id', 'it_engineer').maybeSingle(),
        admin.from('org_reporting_edge').select('child_role_id,parent_role_id').eq('child_role_id', 'it_engineer'),
        admin.from('ceo_standing_grant').select('grant_key,action_class,scope_note,limit_note,max_amount_aed,active,expires_at').eq('grantee_role_id', 'it_engineer').order('grant_key'),
        admin.from('internal_credential').select('context,scope,active,use_count,last_used_at').eq('context', 'fn.it_engineer').maybeSingle(),
        admin.from('function_owner').select('function_slug').eq('owner', 'it_engineer'),
        admin.from('founder_mail_policy').select('kind,allowed_to_email,owner_role,reason'),
        admin.from('llm_route_health').select('model_id,open_until'),
        admin.from('agent_runs').select('id,status,finished_at,counts').eq('agent', 'it_engineer').order('id', { ascending: false }).limit(5),
      ]);

      const forbidden = (role.data?.forbidden_decisions || []) as string[];
      const authority: Record<string, unknown> = {};
      for (const cls of CLASSES) {
        const m = await mayAct(cls);
        authority[cls] = m.may_act === true
          ? { may_act: true, grant: m.grant ?? null, scope: m.scope ?? null, limit: m.limit ?? null }
          // THE REFUSAL NAMES THE ROUTE, exactly as the accountant's refunds do — but this seat's
          // route is the founder, not the CEO, so both are returned and neither is invented.
          // `authority_rule` is fn_agent_may_act's own answer, unedited.
          : { may_act: m.may_act ?? null, authority_rule: m, route: routeFor(cls, forbidden),
              route_owner: 'founder', error: m.error ?? null };
      }

      // THE ONE ROUTE THE FOUNDER ASKED FOR, MEASURED. He said this seat emails him directly, so
      // whether any founder-facing mail class is OWNED by this seat is a fact worth reading rather
      // than assuming. It is 0 today and that is reported as 0 WITH ITS MEANING: founder_mail_policy
      // still carries kinds owned by 'it_operations_engineer', 'cto' and 'cybersecurity_engineer' —
      // roles the founder deleted on 7 Sep — so those rows are unowned by any live seat, not absent.
      // Re-owning them belongs to the alerting build. Reporting the number without saying that would
      // be a zero that reads as "nothing reaches him", which is a different and false statement.
      const policy = (mailPolicy.data || []) as Array<{ kind: string; allowed_to_email: boolean; owner_role: string; reason: string }>;
      const ownedByThisSeat = policy.filter((p) => p.owner_role === 'it_engineer');
      const deadOwners = ['it_operations_engineer', 'cto', 'cybersecurity_engineer'];
      const orphanedOps = policy.filter((p) => deadOwners.includes(p.owner_role));
      const founderRoute = {
        kinds_owned_by_this_seat: ownedByThisSeat.length,
        kinds_owned_by_this_seat_that_reach_him: ownedByThisSeat.filter((p) => p.allowed_to_email).length,
        // These already reach him today and would carry an outage report the moment something emits
        // one, whoever owns the row.
        outage_kinds_that_already_reach_him: policy
          .filter((p) => p.allowed_to_email && deadOwners.includes(p.owner_role))
          .map((p) => p.kind).sort(),
        ops_kinds_owned_by_a_role_that_no_longer_exists: orphanedOps.length,
        basis: 'Read from public.founder_mail_policy at call time. A count of 0 owned kinds means this '
          + 'seat has not yet been made the owner of any founder-facing mail class — NOT that no mail '
          + 'reaches the founder. Re-owning the operations kinds is part of the alerting build, not of '
          + 'this file.',
      };

      const held = (routes.data || []).filter((r: { open_until: string | null }) =>
        r.open_until && new Date(r.open_until) > new Date());

      const seated = agent.data?.active === true && agent.data?.available === true
        && role.data?.status === 'active';
      const edges = (edge.data || []).length;

      const facts = {
        ok: true,
        seat: 'it_engineer',
        caller: caller.kind,
        authenticated_by: caller.context ?? 'founder jwt (app_secrets.admin_emails)',
        seated,
        agent: agent.data ?? null,
        role: role.data ?? null,
        // NOT NULL BY ACCIDENT. The founder, 9 Sep 2026: "he reports to me directly only." The
        // founder is a human, not a row in org_role, and org_reporting_edge's parent is a foreign key
        // to org_role — so writing this edge would mean inventing a 'founder' role and putting a
        // person into the org chart. The absence IS the statement, and 0 is asserted, not observed.
        reports_to: null,
        reporting_edges: edges,
        reports_to_founder: (role.data?.escalation_targets || []).includes('founder') && edges === 0,
        reporting_note: edges === 0
          ? 'No row in org_reporting_edge, deliberately. The founder ruled on 9 Sep 2026 that this seat reports to him directly only; org_reporting_edge.parent_role_id is a foreign key to org_role, and the founder is not a role. Escalation leaves the company instead of landing on the CEO.'
          : 'DEFECT: this seat has ' + edges + ' reporting edge(s). The founder ruled it reports to him directly only.',
        authority,
        grants: (grants.data || []).map((g: Record<string, unknown>) => ({
          grant: g.grant_key, class: g.action_class, active: g.active,
          ceiling_aed: g.max_amount_aed, expires_at: g.expires_at,
          scope: g.scope_note, limit: g.limit_note,
        })),
        // Every line here names its own route in words. The runtime does not paraphrase them.
        refuses: forbidden,
        reaches: {
          credential: cred.data?.context ?? null,
          may_call: cred.data?.scope ?? [],
          credential_active: cred.data?.active ?? null,
          use_count: cred.data?.use_count ?? null,
          last_used_at: cred.data?.last_used_at ?? null,
          note: 'internal_credential.scope is the exhaustive list of edge functions this credential '
            + 'authenticates to. It names only this seat\'s own runtime because this seat calls '
            + 'nothing else yet; widening it is a decision somebody has to write down.',
        },
        owns_functions: ((owner.data || []) as Array<{ function_slug: string }>).map((r) => r.function_slug).sort(),
        founder_route: founderRoute,
        recent_runs: lastRuns.data ?? [],
        // Reported because it is true of every seat, not because this one is waiting on it.
        model_calls_available: held.length === 0,
        model_hold: held.length
          ? { routes_held: held.length, until: held[0].open_until,
              note: 'fn_kernel_paid_provider_gate denies globally while any route is held. No action in this function calls a model, so nothing here is blocked by it.' }
          : null,
        watching: {
          // WHAT IT IS CHARTERED TO WATCH, read from the grant rather than restated here, so the
          // charter cannot drift from the authority that carries it.
          charter: (grants.data || []).find((g: Record<string, unknown>) => g.action_class === 'monitoring')?.scope_note ?? null,
          readings: null,
          basis: 'NOTHING WAS MEASURED ABOUT THE ESTATE ON THIS CALL. readings is null rather than an '
            + 'empty object or a row of zeros, because a zero here would be indistinguishable from a '
            + 'healthy estate. The monitoring engine that takes these readings is a separate build; '
            + 'its seam is a new action branch in supabase/functions/it_engineer/index.ts, authorised '
            + 'by fn_agent_may_act(\'it_engineer\',\'monitoring\'), which this response shows is live.',
        },
      };

      if (action === 'health') {
        await run('health', seated && edges === 0 ? 'ok' : 'error', {
          seated, edges, grants: (grants.data || []).length,
          active_grants: (grants.data || []).filter((g: { active: boolean }) => g.active).length,
          owns: (owner.data || []).length,
        }, seated && edges === 0 ? undefined
          : 'The IT Engineer seat is not correctly established: seated=' + seated + ' reporting_edges=' + edges);
        return J(facts);
      }

      // ── STATUS ───────────────────────────────────────────────────────────────────────────────
      // The same facts, plus one paragraph a human can read without unpacking JSON. Every sentence
      // is assembled from a value above; none is a template that would still read well if the
      // measurement had failed.
      const permitted = CLASSES.filter((c) => (authority[c] as Record<string, unknown>)?.may_act === true);
      const refused = CLASSES.filter((c) => (authority[c] as Record<string, unknown>)?.may_act === false);
      const summary = [
        `IT Engineer — ${seated ? 'seated and available' : 'NOT PROPERLY SEATED'}.`,
        edges === 0
          ? 'Reports to the founder directly; it holds no reporting edge to the CEO, which is the founder\'s ruling of 9 Sep 2026 and not an omission.'
          : `DEFECT: it holds ${edges} reporting edge(s) and should hold none.`,
        `It may ${permitted.length ? permitted.join(', ') : 'do nothing at all — every class was refused, which means the seat is seated and blind'}.`,
        `It is refused ${refused.length ? refused.join(', ') : 'nothing, which should be impossible — deploy has no grant'}; each refusal names the founder as the route.`,
        `Its credential ${cred.data?.active ? 'is active' : 'is NOT active'} and authenticates to ${(cred.data?.scope || []).length} function(s). It owns ${(owner.data || []).length} function(s).`,
        `${founderRoute.kinds_owned_by_this_seat} founder-mail class(es) are owned by this seat; `
          + `${founderRoute.ops_kinds_owned_by_a_role_that_no_longer_exists} operations class(es) are still owned by roles the founder deleted on 7 Sep, `
          + `of which ${founderRoute.outage_kinds_that_already_reach_him.length} already reach him. Re-owning them is the alerting build's.`,
        'NOTHING ABOUT THE ESTATE WAS MEASURED ON THIS CALL. This seat is established and authorised; the engine that takes the readings is a separate build.',
      ].join(' ');

      await run('status', seated && edges === 0 ? 'ok' : 'error', {
        seated, edges, permitted: permitted.length, refused: refused.length,
        founder_mail_kinds_owned: founderRoute.kinds_owned_by_this_seat,
      });
      return J({ ...facts, summary });
    }

    // ── AUTHORITY ──────────────────────────────────────────────────────────────────────────────
    // "May I do X?" for any class, answered by the database at call time. This is the door the
    // monitoring engine knocks on before it acts, and the reason it exists separately from `health`
    // is that the engine will ask about one class, not five.
    //
    // The refusal is the interesting half. fn_agent_may_act's answer is returned VERBATIM under
    // `authority_rule` — it is the same rule every seat is judged by and it is not reshaped here —
    // and this seat's own route is read from org_role.forbidden_decisions. An unknown class is
    // refused with route null rather than with an invented one.
    if (action === 'authority') {
      const cls = String(body.action_class || '').trim();
      if (!cls) return J({ error: 'action_class_required', classes: CLASSES }, 400);
      const amount = Number.isFinite(Number(body.amount_aed)) ? Number(body.amount_aed) : null;
      const m = await mayAct(cls, amount);
      const { data: role } = await admin.from('org_role')
        .select('forbidden_decisions,escalation_targets').eq('role_id', 'it_engineer').maybeSingle();
      const forbidden = (role?.forbidden_decisions || []) as string[];
      await run('authority', 'ok', { action_class: cls, amount_aed: amount, may_act: m.may_act ?? null });
      if (m.may_act === true) {
        return J({ ok: true, seat: 'it_engineer', action_class: cls, may_act: true, ...m });
      }
      return J({
        ok: true, seat: 'it_engineer', action_class: cls, may_act: m.may_act ?? null,
        authority_rule: m,
        route: routeFor(cls, forbidden),
        route_owner: (role?.escalation_targets || []).includes('founder') ? 'founder' : null,
        basis: 'may_act comes from public.fn_agent_may_act, the one authority rule every seat is '
          + 'judged by, and is returned unedited. `route` is the matching line of '
          + 'public.org_role.forbidden_decisions for this seat — the founder ruled on 9 Sep 2026 that '
          + 'this seat reports to him directly, so its route is a session he opens, not the CEO '
          + 'decision fn_agent_may_act names by default for the four seats that do report to the CEO. '
          + 'A class with no matching line returns route null rather than an invented one.',
      });
    }

    return J({ error: 'unknown_action', action, actions: ['health', 'status', 'authority'],
      note: 'The monitoring, diagnosis and escalation actions are a separate build. See the seam '
        + 'described at the top of supabase/functions/it_engineer/index.ts.' }, 400);
  } catch (e) {
    await run('error', 'error', {}, String((e as Error).message || e));
    return J({ error: String((e as Error).message || e) }, 500);
  }
});
