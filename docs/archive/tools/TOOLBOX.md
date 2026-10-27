# QuotesDone toolbox

Standing tools the founder directed be installed (27 August 2026), for the **agent-expertise
workstream** — turning each role into a certification-grade expert. This directory is **fenced**:
`tools/.gitignore` tracks only this manifest and the fence, so the vendored code and the venv never
reach the app's parity gates or CI. The tools are real and installed on disk under `tools/`; only
their *documentation* is committed.

Reproduce the whole toolbox from scratch:

```bash
# Python 3.14 is at C:/Users/Opera/AppData/Local/Python/pythoncore-3.14-64/python.exe
cd tools
"$PY" -m venv venv
venv/Scripts/python.exe -m pip install -r venv-requirements.txt   # frozen set, 45 packages
git clone --depth 1 https://github.com/virgiliojr94/book-to-skill.git
venv/Scripts/python.exe -m pip install ./book-to-skill
```

## What is installed, and what each is FOR

| tool | version | installed as | role in the expertise pipeline |
|---|---|---|---|
| **book-to-skill** | latest | `book-to-skill` CLI + `book_to_skill` module (from clone) | **The core engine.** Turns a certification's actual books/PDFs/EPUBs into a structured agent skill. Supported: pdf, epub, docx, mobi/azw, html, rst, adoc, md, rtf, txt. `--mode technical` for tables/code/formulas (standards docs). This is how "the accountant passes the CPA" becomes a build: feed it the CPA body of knowledge → skill → agent. |
| **firecrawl-py** | 4.40.0 | `firecrawl` module (SDK) | Crawl authoritative web sources (FTA VAT/corporate-tax, ADCD/Civil Defence fire code, RICS/CIPS/PMI syllabi) into clean markdown for ingestion. **SDK only** — the cloud API costs money and the self-hosted stack is a separate Docker service; both stay behind the founder's holds until the knowledge stage runs. |
| **Scrapling** | 0.4.15 | `scrapling` module | Stealth/adaptive scraping for sources that block a plain fetch. Browser fetch (playwright) is **not** installed yet — added on demand when a source needs it. |
| **you-get** | 0.4.1743 | `you-get` CLI + `you_get` module | Pull expert training material that lives in video/audio — course lectures, standards walkthroughs — so it can be transcribed and turned into knowledge. |
| **public-apis** | reference | see `PUBLIC_APIS_REFERENCE.md` | Not software — a directory of free public APIs (https://github.com/public-apis/public-apis). Vendored as a reference bookmark, not cloned, because its value is the list, not code. Candidate free data sources for agent knowledge and enrichment. |

Extractor quality packs installed so book-to-skill produces cert-grade output: `pypdf`,
`pdfminer.six`, `ebooklib`, `beautifulsoup4`, `python-docx`, and **`docling`** (2.123.0 when
installed, pinned 2.143.0 since 27 Oct) — the
best-in-class table/formula/layout extractor, book-to-skill's `--mode technical` backend, installed
27 Aug on the founder's instruction because certification standards are dense with tables. System
`pdftotext` (poppler) is also present. The full pinned set is `venv-requirements.txt` (129 pins plus
the local `book-to-skill` line).

**Security re-pin, 27 Oct 2026 (it_engineer).** GitHub's dependency graph reads
`venv-requirements.txt` as a pip manifest, and the 27 Aug freeze carried every critical and high
Dependabot alert in the repository: reconstructed from the GHSA records, 94 advisories (6 critical,
42 high, 39 moderate, 7 low) across pillow 41, pypdf 19, docling + docling-slim 16, aiohttp 8,
urllib3 3, filelock 3, certifi 1, accelerate 1, multidict 1, setuptools 1. GitHub showed 93 alerts with
the same critical/high/low counts; the alerts API is not readable from a session, so the two-moderate
difference was not reconciled. None of it reaches production: nothing in the
web app, the edge functions or the gate installs this set; it is the laptop's offline extraction
venv. It does parse third-party PDFs and images, which is exactly what the pillow/pypdf/docling
advisories are about, so the pins were raised to the first fixed releases and the whole set was
re-resolved for Windows / Python 3.14 (`uv pip compile --python-platform windows --python-version
3.14`, 129 pins, no conflict). Re-checked against PyPI's advisory feed and the OSV PyPI dump: 0
advisories. **The installed venv on the laptop is unchanged until it is reinstalled** with
`venv/Scripts/python.exe -m pip install -r venv-requirements.txt`.

## The line these tools do NOT cross on their own

Installing is dev tooling and is done. **Running** them against the live web — firecrawl crawls,
Scrapling scrapes, you-get downloads — is external-effect activity, and the firecrawl cloud API costs
money. Those runs belong to the knowledge stage of `docs/LAUNCH_READINESS_PLAN.md` and stay behind the
founder's holds until that stage is authorized. The founder's Apify pause (supplier-lead scraping,
paused to ~Feb 2027) is a *different* purpose from knowledge acquisition and does not gate these — but
it is the reason the "installed vs run" line is drawn explicitly here.
