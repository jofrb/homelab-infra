#!/usr/bin/env python3
"""kb: manage the knowledge store (KB_ROOT, default /data/knowledge).

Commands:
  kb new <slug>   create projects/<slug>/ from _templates/project/README.md
"""

import argparse
import datetime
import os
import re
import sys
from pathlib import Path

DEFAULT_ROOT = "/data/knowledge"
SLUG_RE = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
PROJECT_SUBDIRS = ["notes", "conversations", "sources"]


def fail(message: str) -> SystemExit:
    return SystemExit(f"kb: {message}")


def new_project(slug: str) -> Path:
    if not SLUG_RE.fullmatch(slug):
        raise fail(f"invalid slug {slug!r}: use lowercase letters, digits and single hyphens")

    store = Path(os.environ.get("KB_ROOT", DEFAULT_ROOT))
    template = store / "_templates" / "project" / "README.md"
    if not (store / "projects").is_dir():
        raise fail(f"no projects/ directory under {store}")
    if not template.is_file():
        raise fail(f"missing template {template}")

    project = store / "projects" / slug
    # mkdir without exist_ok: fails if the project already exists, never overwrites
    try:
        project.mkdir()
    except FileExistsError:
        raise fail(f"project already exists: {project}")

    for sub in PROJECT_SUBDIRS:
        (project / sub).mkdir()
        # git does not track empty directories
        (project / sub / ".gitkeep").touch()

    readme = (
        template.read_text()
        .replace("{{title}}", slug)
        .replace("{{date}}", datetime.date.today().isoformat())
    )
    with (project / "README.md").open("x") as f:
        f.write(readme)
    return project


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="kb", description="Manage the knowledge store.")
    commands = parser.add_subparsers(dest="command", required=True)

    new = commands.add_parser("new", help="create a project from the template")
    new.add_argument("slug", help="kebab-case project name, e.g. home-network")

    args = parser.parse_args(argv)
    if args.command == "new":
        print(new_project(args.slug))
    return 0


if __name__ == "__main__":
    sys.exit(main())
