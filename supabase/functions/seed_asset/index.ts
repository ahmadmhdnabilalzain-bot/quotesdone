// Disabled: one-off demo asset uploader. Retired after seeding the intake-audio sample.
Deno.serve(() => new Response(JSON.stringify({ error: 'gone' }), { status: 410, headers: { 'Content-Type': 'application/json' } }));
