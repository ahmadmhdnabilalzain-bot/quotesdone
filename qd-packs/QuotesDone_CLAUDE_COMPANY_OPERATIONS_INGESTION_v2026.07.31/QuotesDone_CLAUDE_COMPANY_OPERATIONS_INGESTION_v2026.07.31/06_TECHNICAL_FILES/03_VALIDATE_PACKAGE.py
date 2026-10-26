#!/usr/bin/env python3
"""Validate the QuotesDone Company Operations Corpus without loading it into an AI context."""

from __future__ import annotations
import csv
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

try:
    import jsonschema
except ImportError:
    print("Install jsonschema: pip install jsonschema", file=sys.stderr)
    raise

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def main(root: Path) -> int:
    manifest_path = root / "00_PACKAGE_MANIFEST.json"
    schema_path = root / "05_QA_AND_REPORTS" / "02_RECORD_SCHEMA.json"
    checksums_path = root / "99_CHECKSUMS_SHA256.txt"

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    validator = jsonschema.Draft202012Validator(schema)

    errors = []
    ids = set()
    counts = Counter()
    source_ids = {
        row["source_id"]
        for row in csv.DictReader(
            (root / "00_COMPANY_CORE" / "02_SOURCE_REGISTRY.csv").open(encoding="utf-8")
        )
    }

    for file in sorted(root.rglob("*.jsonl")):
        if "06_ALL_RECORDS" in file.parts:
            continue
        with file.open(encoding="utf-8") as f:
            for line_no, line in enumerate(f, 1):
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError as exc:
                    errors.append(f"{file}:{line_no}: JSON error: {exc}")
                    continue

                # Event subscriptions are also full records in this package.
                for err in validator.iter_errors(record):
                    errors.append(f"{file}:{line_no}: {err.message}")

                rid = record.get("record_id")
                if rid in ids:
                    errors.append(f"{file}:{line_no}: duplicate record_id {rid}")
                ids.add(rid)
                counts[record.get("record_type", "unknown")] += 1

                missing = set(record.get("source_ids", [])) - source_ids
                if missing:
                    errors.append(f"{file}:{line_no}: unknown sources {sorted(missing)}")

    expected = {}
    for line in checksums_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        digest, rel = line.split("  ", 1)
        expected[rel] = digest

    for rel, digest in expected.items():
        p = root / rel
        if not p.exists():
            errors.append(f"Missing file: {rel}")
        elif sha256(p) != digest:
            errors.append(f"Checksum mismatch: {rel}")

    print(json.dumps({
        "package": manifest.get("package_name"),
        "version": manifest.get("version"),
        "records": len(ids),
        "record_types": counts,
        "errors": errors[:100],
        "error_count": len(errors),
    }, indent=2, default=dict))

    return 1 if errors else 0

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: validate_company_ops.py /path/to/extracted/corpus", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(Path(sys.argv[1]).resolve()))
