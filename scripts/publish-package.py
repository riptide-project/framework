#!/usr/bin/env python3
"""Publish one registry package, rejecting CLI failures that return exit code zero."""

import argparse
import os
import re
import subprocess
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def acknowledged(registry: str, output: str, name: str, version: str) -> bool:
    # Pesde styles its response when a terminal is available.
    output = re.sub(r"\x1b\[[0-9;]*m", "", output)
    if registry == "wally":
        return "Package published successfully!" in output.splitlines()
    expected = re.escape(f"published {name}@{version}")
    return re.search(rf"^{expected}(?:\s|\(|$)", output, re.MULTILINE) is not None


def publish(registry: str) -> None:
    token = os.environ.get("REGISTRY_TOKEN", "")
    if not token:
        raise SystemExit("Set REGISTRY_TOKEN to the scope owner's registry credential.")
    # Pesde stores the complete Authorization header; Wally adds Bearer itself.
    if registry == "pesde" and not token.startswith("Bearer "):
        token = f"Bearer {token}"
    with (ROOT / f"{registry}.toml").open("rb") as file:
        manifest = tomllib.load(file)
    package = manifest["package"] if registry == "wally" else manifest
    auth = [registry, "auth"] if registry == "pesde" else [registry]
    command = [registry, "publish"] + (["--yes"] if registry == "pesde" else [])
    try:
        login = subprocess.run([*auth, "login", "--token", token], cwd=ROOT, check=False)
        if login.returncode:
            raise SystemExit(f"{registry} authentication failed.")
        result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        print(result.stdout, end="")
        if result.returncode or not acknowledged(registry, result.stdout, package["name"], package["version"]):
            raise SystemExit(f"{registry} did not confirm publication; the GitHub release must remain blocked.")
    finally:
        subprocess.run([*auth, "logout"], cwd=ROOT, check=False)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("registry", choices=("pesde", "wally"))
    args = parser.parse_args()
    publish(args.registry)


if __name__ == "__main__":
    main()
