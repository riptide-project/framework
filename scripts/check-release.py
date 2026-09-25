#!/usr/bin/env python3
"""Check release metadata before CI or tag publication."""

import argparse
import re
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def fail(message: str) -> None:
    raise SystemExit(f"release metadata: {message}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", help="Git tag being published, for example v0.9.0-maelstrom.3")
    args = parser.parse_args()

    with (ROOT / "pesde.toml").open("rb") as manifest:
        pesde_version = tomllib.load(manifest)["version"]
    with (ROOT / "wally.toml").open("rb") as manifest:
        wally_version = tomllib.load(manifest)["package"]["version"]
    if pesde_version != wally_version:
        fail(f"pesde.toml has {pesde_version}, wally.toml has {wally_version}")

    changelog = (ROOT / "CHANGELOG.md").read_text()
    headings = re.findall(r"^## \[([^\]]+)\] - (.+)$", changelog, re.MULTILINE)
    if not headings or headings[0][0] != pesde_version:
        fail(f"first changelog section must be [{pesde_version}]")
    if not (ROOT / "docs/src/content/docs/versions" / pesde_version / "index.mdx").is_file():
        fail(f"missing documentation landing page for {pesde_version}")
    if pesde_version not in (ROOT / "README.md").read_text():
        fail(f"README.md does not mention {pesde_version}")

    if args.tag is not None:
        if args.tag != f"v{pesde_version}":
            fail(f"tag {args.tag} does not match package version v{pesde_version}")
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", headings[0][1]):
            fail(f"changelog section [{pesde_version}] needs a release date before tagging")

    print(f"release metadata OK: {pesde_version}")


if __name__ == "__main__":
    main()
