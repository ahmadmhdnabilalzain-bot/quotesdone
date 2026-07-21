import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "*", "Content-Type": "application/json", "Cache-Control": "public, max-age=300" };
async function count(query: string): Promise<number> {
  const r = await fetch(`${SB_URL}/rest/v1/${query}`, { headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, Prefer: "count=exact", Range: "0-0" } });
  const cr = r.headers.get("content-range") || "";
  const n = parseInt(cr.split("/")[1] || "0", 10);
  return isNaN(n) ? 0 : n;
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const indexed = await count("leads?select=id");
    const verified = await count("leads?select=id&registration_submitted_at=not.is.null&approval_status=eq.approved");
    return new Response(JSON.stringify({ suppliers_indexed: indexed, verified_suppliers: verified, categories: 30, emirates: 7 }), { headers: CORS });
  } catch (e) {
    return new Response(JSON.stringify({ suppliers_indexed: 0, verified_suppliers: 0, error: String(e) }), { headers: CORS });
  }
});
