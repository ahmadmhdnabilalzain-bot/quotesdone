// DECOMMISSIONED: one-time brand-asset uploader, neutralized after use. Returns 410 for all calls.
Deno.serve(() => new Response(JSON.stringify({ error: 'gone', note: 'brand_upload was a one-time uploader and is decommissioned' }), { status: 410, headers: { 'Content-Type': 'application/json' } }));
