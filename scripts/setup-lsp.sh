#!/bin/bash
# Regenerate the machine-local SourceKit-LSP (BSP) config for this clone.
#
# buildServer.json points SourceKit-LSP at the Xcode build database so App
# sources get full compile context. It is gitignored: paths differ per machine
# (Homebrew prefix, clone location, DerivedData). Run this once after cloning
# and again whenever the scheme or project layout changes.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcode-build-server > /dev/null; then
  echo "xcode-build-server not found. Install it first:  brew install xcode-build-server" >&2
  exit 1
fi

xcode-build-server config -project PodDock.xcodeproj -scheme PodDock

# xcode-build-server picks the DEFAULT DerivedData, but the VS Code build task
# pins -derivedDataPath .build/DerivedData — point the index at the same place
python3 - <<'PYEOF'
import json
path = "buildServer.json"
config = json.load(open(path))
config["build_root"] = __import__("os").path.abspath(".build/DerivedData")
with open(path, "w") as f:
    json.dump(config, f, indent="\t")
    f.write("\n")
print(f'build_root -> {config["build_root"]}')
PYEOF

echo "Done. Reload the VS Code window to reattach SourceKit-LSP."
