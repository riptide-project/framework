#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/check-types.sh
fixture_path="$(pwd)/.tmp/typecheck-fixture.project.json"
cat > "$fixture_path" <<'JSON'
{
  "name": "Riptide-Typecheck",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "Riptide": { "$path": "../src" },
      "SignalTypes": { "$path": "../test/types" }
    }
  }
}
JSON
trap 'unlink "$fixture_path"' EXIT
mise exec -- rojo sourcemap .tmp/typecheck-fixture.project.json --output .tmp/typecheck/signal-sourcemap.json
cd .tmp

analyzer=(
  mise exec github:JohnnyMorganz/luau-lsp@1.63.0 --
  luau-lsp analyze
  --platform=roblox
  --definitions=@roblox=typecheck/globalTypes.d.luau
  --sourcemap=typecheck/signal-sourcemap.json
)

"${analyzer[@]}" ../test/types/SignalTypes.luau
if "${analyzer[@]}" ../test/types/SignalTypesInvalid.luau > typecheck/signal-negative.log 2>&1; then
  echo "Negative Signal type fixture unexpectedly passed" >&2
  exit 1
fi
if [[ "$(rg -c 'TypeError:' typecheck/signal-negative.log)" != "5" ]]; then
  cat typecheck/signal-negative.log >&2
  echo "Expected five Signal type errors" >&2
  exit 1
fi
echo "Signal type fixtures passed (positive clean, five expected errors)"
