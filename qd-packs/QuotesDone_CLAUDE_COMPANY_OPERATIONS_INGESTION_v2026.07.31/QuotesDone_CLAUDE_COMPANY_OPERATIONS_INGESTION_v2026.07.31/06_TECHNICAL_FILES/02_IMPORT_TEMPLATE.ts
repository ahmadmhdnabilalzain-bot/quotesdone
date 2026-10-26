/**
 * QuotesDone Company Operations Corpus — streaming importer starter
 *
 * Run against STAGING only. Claude must adapt table names and promotion logic
 * to the current repository after inspecting the existing schema.
 *
 * Environment:
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY   (staging only; never log it)
 *   CORPUS_DIR                  (extracted corpus directory)
 *
 * Suggested dependencies:
 *   npm i @supabase/supabase-js
 */

import { createClient } from "@supabase/supabase-js";
import { createReadStream, promises as fs } from "node:fs";
import { createInterface } from "node:readline";
import { createHash } from "node:crypto";
import path from "node:path";

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const corpusDir = process.env.CORPUS_DIR;

if (!url || !key || !corpusDir) {
  throw new Error("Missing SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY or CORPUS_DIR");
}

const supabase = createClient(url, key, {
  auth: { persistSession: false, autoRefreshToken: false },
});

type OpsRecord = {
  record_id: string;
  scope_type: string;
  scope_key: string;
  module: string;
  record_type: string;
  title: string;
  content: string;
  structured_data: Record<string, unknown>;
  source_ids: string[];
  implementation_status: string;
  validation_status: string;
  authority_tier: string;
  risk_level: string;
  version: string;
  effective_date?: string | null;
  review_after?: string | null;
  keywords: unknown[];
  dependencies: unknown[];
  escalation_rule: Record<string, unknown>;
};

const BATCH_SIZE = 500;
const packageVersion = "1.0.0";

function sha256Text(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function validateRecord(r: any): asserts r is OpsRecord {
  const required = [
    "record_id", "scope_type", "scope_key", "module", "record_type",
    "title", "content", "structured_data", "source_ids",
    "implementation_status", "validation_status", "authority_tier",
    "risk_level", "version", "keywords", "dependencies", "escalation_rule",
  ];
  for (const field of required) {
    if (!(field in r)) throw new Error(`Missing field ${field}`);
  }
  if (typeof r.record_id !== "string" || r.record_id.length < 8) {
    throw new Error("Invalid record_id");
  }
  if (!Array.isArray(r.source_ids)) throw new Error("source_ids must be an array");
  if (typeof r.content !== "string" || r.content.length < 20) {
    throw new Error("content too short");
  }
}

async function upsertBatch(rows: OpsRecord[], runId: string) {
  const payload = rows.map((r) => ({
    ...r,
    content_sha256: sha256Text(JSON.stringify({
      title: r.title,
      content: r.content,
      structured_data: r.structured_data,
      source_ids: r.source_ids,
    })),
    package_version: packageVersion,
    ingestion_run_id: runId,
    updated_at: new Date().toISOString(),
  }));

  const { error } = await supabase
    .schema("ops_kb_stage")
    .from("records")
    .upsert(payload, { onConflict: "record_id" });

  if (error) throw error;
}

async function importJsonl(filePath: string, runId: string) {
  const rl = createInterface({
    input: createReadStream(filePath, { encoding: "utf8" }),
    crlfDelay: Infinity,
  });

  let batch: OpsRecord[] = [];
  let lineNo = 0;
  let accepted = 0;
  let rejected = 0;

  for await (const line of rl) {
    lineNo += 1;
    if (!line.trim()) continue;

    try {
      const value = JSON.parse(line);
      validateRecord(value);
      batch.push(value);

      if (batch.length >= BATCH_SIZE) {
        await upsertBatch(batch, runId);
        accepted += batch.length;
        batch = [];
      }
    } catch (error) {
      rejected += 1;
      console.error(JSON.stringify({
        file: path.relative(corpusDir!, filePath),
        line: lineNo,
        error: error instanceof Error ? error.message : String(error),
      }));
    }
  }

  if (batch.length) {
    await upsertBatch(batch, runId);
    accepted += batch.length;
  }

  return { accepted, rejected };
}

async function listJsonlFiles(root: string): Promise<string[]> {
  const output: string[] = [];
  async function walk(dir: string) {
    for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) await walk(full);
      else if (entry.isFile() && entry.name.endsWith(".jsonl")) output.push(full);
    }
  }
  await walk(root);
  return output.sort();
}

async function main() {
  const manifest = JSON.parse(
    await fs.readFile(path.join(corpusDir!, "00_PACKAGE_MANIFEST.json"), "utf8")
  );

  const { data: run, error: runError } = await supabase
    .schema("ops_kb_stage")
    .from("ingestion_runs")
    .insert({
      package_name: manifest.package_name,
      package_version: manifest.version,
      status: "running",
      detail: { corpus_dir: path.basename(corpusDir!) },
    })
    .select("id")
    .single();

  if (runError || !run) throw runError ?? new Error("Failed to create ingestion run");

  const files = await listJsonlFiles(corpusDir!);
  const totals = { accepted: 0, rejected: 0 };

  for (const file of files) {
    const result = await importJsonl(file, run.id);
    totals.accepted += result.accepted;
    totals.rejected += result.rejected;
    console.log(JSON.stringify({
      file: path.relative(corpusDir!, file),
      ...result,
    }));
  }

  const finalStatus = totals.rejected === 0 ? "validated" : "failed";
  const { error: finishError } = await supabase
    .schema("ops_kb_stage")
    .from("ingestion_runs")
    .update({
      status: finalStatus,
      completed_at: new Date().toISOString(),
      inserted_count: totals.accepted,
      rejected_count: totals.rejected,
      detail: { files: files.length },
    })
    .eq("id", run.id);

  if (finishError) throw finishError;
  console.log(JSON.stringify({ run_id: run.id, status: finalStatus, ...totals }));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
