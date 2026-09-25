#!/usr/bin/env python3
"""Publish one registry package, rejecting CLI failures that return exit code zero."""

import argparse
import json
import os
import re
import subprocess
import tomllib
from pathlib import Path
from urllib.error import URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent.parent


def already_published(registry: str, package: dict, manifest: dict) -> bool:
    index = package["registry"] if registry == "wally" else manifest["indices"]["default"]
    parsed = urlparse(index)
    parts = parsed.path.strip("/").split("/")
    if parsed.scheme != "https" or parsed.netloc != "github.com" or len(parts) != 2:
        raise SystemExit(f"Cannot check {registry} publication in index {index}.")
    url = f"https://raw.githubusercontent.com/{parts[0]}/{parts[1]}/main/{package['name']}"
    try:
        with urlopen(Request(url, headers={"Cache-Control": "no-cache"}), timeout=20) as response:
            data = response.read().decode("utf-8")
    except (OSError, URLError) as error:
        raise SystemExit(f"Cannot check {registry} publication in {url}: {error}") from error
    if registry == "pesde":
        target = manifest["target"]["environment"]
        return f"{package['version']} {target}" in tomllib.loads(data)
    return any(
        (entry := json.loads(line))["package"]["name"] == package["name"]
        and entry["package"]["version"] == package["version"]
        for line in data.splitlines()
        if line.strip()
    )


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
    if already_published(registry, package, manifest):
        print(f"{registry} already contains {package['name']}@{package['version']}; skipping publication.")
        return
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
