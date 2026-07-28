// orchestrate — RETIRED 22 Jul 2026 (OS audit F4 / H12). The multi-agent orchestration contract broke against
// agent_act: it called agent_act with { agent_key, mode, instruction, actions } but the current agent_act speaks
// { action, agent, message }, so every step ran as an empty-message "secretary", plans came back empty, and
// execute performed nothing — while still paying for an Opus/Sonnet call per step. Neutralized to a 410 stub to
// stop the wasted spend and the false "multi-agent" feature. Recover from git history if it is ever rebuilt.
Deno.serve(() => new Response(
  JSON.stringify({ error: 'orchestrate is retired (non-functional against the current agent_act contract)' }),
  { status: 410, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } }
));
