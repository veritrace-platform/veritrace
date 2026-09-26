#!/usr/bin/env python3
"""Checks Markdown links and heading anchors.

By default it checks this repository: relative links must resolve to files, and #anchors must match a
heading in the target document (GitHub slug rules).

With --workspace it also checks links from sibling repositories into this repository's documentation
(https://github.com/veritrace-platform/veritrace/blob/main/...), so moved or renamed documents are
caught before they break other READMEs.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
WORKSPACE = REPO_ROOT.parent
HOME_URL = re.compile(r"https://github\.com/veritrace-platform/veritrace/(?:blob|tree)/main/([^)#\s]+)(#[^)\s]+)?")
LINK = re.compile(r"\]\(([^)#\s]*)(#[^)\s]+)?\)")
HEADING = re.compile(r"^#{1,6}\s+(.*?)\s*$", re.MULTILINE)
CODE_FENCE = re.compile(r"```.*?```", re.DOTALL)


def slug(heading: str) -> str:
    text = re.sub(r"[^\w\- ]", "", heading.strip().lower())
    return text.replace(" ", "-")


def anchors(path: Path) -> set[str]:
    text = CODE_FENCE.sub("", path.read_text(encoding="utf-8"))
    return {slug(match) for match in HEADING.findall(text)}


def check_target(source: Path, target: Path, anchor: str | None, label: str) -> list[str]:
    if not target.exists():
        return [f"{source}: missing target {label}"]
    if anchor and target.is_file() and anchor.lstrip("#") not in anchors(target):
        return [f"{source}: missing anchor {label}{anchor}"]
    return []


def markdown_files(root: Path) -> list[Path]:
    return [p for p in root.rglob("*.md") if ".git" not in p.parts and "node_modules" not in p.parts]


def check_repository() -> list[str]:
    problems: list[str] = []
    for md in markdown_files(REPO_ROOT):
        text = CODE_FENCE.sub("", md.read_text(encoding="utf-8"))
        for match in LINK.finditer(text):
            target, anchor = match.group(1), match.group(2)
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            resolved = md if target == "" else (md.parent / target)
            problems += check_target(md.relative_to(REPO_ROOT), resolved, anchor, target)
    return problems


def check_workspace() -> list[str]:
    problems: list[str] = []
    for repo in sorted(p for p in WORKSPACE.iterdir() if (p / ".git").exists() and p != REPO_ROOT):
        for md in markdown_files(repo):
            for match in HOME_URL.finditer(md.read_text(encoding="utf-8")):
                target, anchor = match.group(1), match.group(2)
                problems += check_target(md.relative_to(WORKSPACE), REPO_ROOT / target, anchor, target)
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--workspace", action="store_true", help="also check sibling repositories")
    args = parser.parse_args()

    problems = check_repository()
    if args.workspace:
        problems += check_workspace()

    for problem in problems:
        print(problem)
    print(f"{len(problems)} problem(s) found")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
