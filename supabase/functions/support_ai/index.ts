// support_ai — RETIRED 22 Jul 2026 (OS audit F7). Superseded by site_assistant (the deployed site uses
// site_assistant; support_ai had 0 references and its last real use was 21 Jun 2026, on a retired model slug).
// 410 stub; recover from git history if ever needed.
Deno.serve(() => new Response(JSON.stringify({ error: 'support_ai is retired — use site_assistant' }), { status: 410, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } }));
