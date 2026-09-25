#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .tmp/typecheck
definitions=.tmp/typecheck/globalTypes.d.luau
expected=0776cc69b63bc77f3f951f4843c15514f87ed844094e2afdc8e9a6547bbf974a
if ! printf '%s  %s\n' "$expected" "$definitions" | sha256sum --check --status 2>/dev/null; then
  curl --fail --location --silent --show-error https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.63.0/scripts/globalTypes.d.luau --output "$definitions"
fi
printf '%s  %s\n' "$expected" "$definitions" | sha256sum --check --status
mise exec -- rojo sourcemap dev.project.json --output .tmp/typecheck/sourcemap.json
mise exec github:JohnnyMorganz/luau-lsp@1.63.0 -- luau-lsp analyze --platform=roblox --definitions="@roblox=$definitions" --sourcemap=.tmp/typecheck/sourcemap.json src
