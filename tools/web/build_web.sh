#!/usr/bin/env bash
# Rebuilds the browser data pack in docs/play and records its size in the page, which the loader
# needs for its progress bar. The engine runtime (index.js, index.wasm and the audio worklets) is
# the matching official Godot 4.7.2 web build and does not change with the game.
#
#   tools/web/build_web.sh            # uses `godot` on PATH
#   GODOT=/path/to/Godot tools/web/build_web.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"

"$GODOT" --headless --path . --import --quit
"$GODOT" --headless --path . --export-pack Web docs/play/index.pck

python3 - <<'PY'
import os, re
page = "docs/play/index.html"
html = open(page, encoding="utf-8").read()
for name in ("index.pck", "index.wasm"):
    size = os.path.getsize(os.path.join("docs/play", name))
    html, n = re.subn(r'"%s":\d+' % re.escape(name), '"%s":%d' % (name, size), html)
    if n != 1:
        raise SystemExit("could not find the %s size in %s" % (name, page))
    print("%s  %.1f MB" % (name, size / 1048576))
open(page, "w", encoding="utf-8").write(html)
PY
