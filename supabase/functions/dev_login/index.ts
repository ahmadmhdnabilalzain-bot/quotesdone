// Disabled. This endpoint was a temporary QA helper and is permanently turned off.
Deno.serve(() => new Response(JSON.stringify({ error: 'disabled' }), { status: 410, headers: { 'Content-Type': 'application/json' } }));
