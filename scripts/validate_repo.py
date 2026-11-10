"""Validate local documentation links and the generated backlog.

Run from the repository root:
    python scripts/validate_repo.py

Checks:
- Markdown links that point to local files exist.
- The Azure Boards CSV has the expected columns and at least one row.
- Python files under app/, scripts/, and diagrams/ compile.
- The two architecture diagrams exist and are non-trivial in size.

No third-party dependencies. External URLs are not fetched.
"""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")

REQUIRED = [
    "README.md",
    "docs/PROJECT-STATE.md",
    "docs/day-01/README.md",
    "docs/day-01/DO-THIS-FIRST.md",
    "docs/day-01/network-design.md",
    "docs/day-01/identity-and-rbac.md",
    "docs/day-01/zero-trust-threat-model.md",
    "docs/day-01/plan-of-action.md",
    "docs/day-01/glossary.md",
    "docs/day-01/azure-boards-import.csv",
    "docs/day-02/README.md",
    "docs/day-03/README.md",
    "docs/day-03b/README.md",
    "docs/day-04/README.md",
    "docs/day-05/README.md",
    "docs/cost-control.md",
    "docs/runbook.md",
    "docs/deviations.md",
    "docs/interview-brief.md",
    "scripts/stop-lab.ps1",
    "scripts/start-lab.ps1",
    "infra/terraform/bootstrap/main.tf",
    "infra/terraform/envs/dev/main.tf",
    "docs/adr/README.md",
    "docs/adr/0011-entra-id-free-license.md",
    "diagrams/logical-architecture.png",
    "diagrams/network-topology.png",
    "diagrams/render_diagrams.py",
    "scripts/check-prereqs.ps1",
    "scripts/check-prereqs.sh",
    ".github/copilot-instructions.md",
    ".vscode/extensions.json",
]

BACKLOG_COLUMNS = {
    "Work Item Type",
    "Title",
    "Description",
    "Acceptance Criteria",
    "Priority",
    "Story Points",
    "Tags",
    "Area Path",
    "Iteration Path",
}


def check_required() -> list[str]:
    return [f"missing required file: {path}" for path in REQUIRED if not (ROOT / path).exists()]


def check_markdown_links() -> list[str]:
    errors: list[str] = []
    for path in ROOT.rglob("*.md"):
        if any(part in {".git", ".terraform", ".venv", "node_modules"} for part in path.parts):
            continue
        text = path.read_text(encoding="utf-8")
        for raw in LINK_RE.findall(text):
            target = raw.strip().split("#", 1)[0].strip()
            if not target or target.startswith(("http://", "https://", "mailto:", "tel:")):
                continue
            if target.startswith("<") and target.endswith(">"):
                target = target[1:-1]
            target = target.replace("%20", " ")
            resolved = (path.parent / target).resolve()
            if not resolved.exists():
                errors.append(f"{path.relative_to(ROOT)}: broken local link -> {raw}")
    return errors


def check_backlog() -> list[str]:
    path = ROOT / "docs/day-01/azure-boards-import.csv"
    errors: list[str] = []
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            return ["backlog CSV has no header"]
        missing = BACKLOG_COLUMNS - set(reader.fieldnames)
        if missing:
            errors.append(f"backlog CSV missing columns: {sorted(missing)}")
        rows = list(reader)
        if len(rows) < 20:
            errors.append(f"backlog CSV has only {len(rows)} rows; expected at least 20")
        for index, row in enumerate(rows, start=2):
            if not row.get("Work Item Type") or not row.get("Title"):
                errors.append(f"backlog row {index} is missing type or title")
    return errors


def check_python() -> list[str]:
    errors: list[str] = []
    for folder in ("scripts", "diagrams", "app", "tests"):
        base = ROOT / folder
        if not base.exists():
            continue
        for path in base.rglob("*.py"):
            try:
                compile(path.read_text(encoding="utf-8"), str(path), "exec")
            except SyntaxError as exc:
                errors.append(f"{path.relative_to(ROOT)}: {exc}")
    return errors


def check_images() -> list[str]:
    errors: list[str] = []
    for name in ("logical-architecture.png", "network-topology.png"):
        path = ROOT / "diagrams" / name
        if not path.exists():
            errors.append(f"missing diagram: {name}")
        elif path.stat().st_size < 50_000:
            errors.append(f"diagram looks too small (possibly corrupt): {name}")
    return errors


def main() -> int:
    checks = [
        ("required files", check_required()),
        ("markdown links", check_markdown_links()),
        ("backlog CSV", check_backlog()),
        ("python syntax", check_python()),
        ("diagrams", check_images()),
    ]
    failed = False
    for name, errors in checks:
        if errors:
            failed = True
            print(f"FAIL: {name}")
            for error in errors:
                print(f"  - {error}")
        else:
            print(f"OK:   {name}")
    if failed:
        print("\nValidation failed.")
        return 1
    print("\nValidation passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
