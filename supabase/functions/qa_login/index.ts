// Disabled. Temporary QA session minter, permanently turned off after the launch-readiness audit.
Deno.serve(() => new Response(JSON.stringify({ error: 'disabled' }), { status: 410, headers: { 'Content-Type': 'application/json' } }));
