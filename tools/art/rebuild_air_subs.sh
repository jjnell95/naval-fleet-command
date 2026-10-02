#!/usr/bin/env bash
# Regenerate the revised recognition set, including donor copies AFTER rendering.
# Requires Python numpy/trimesh/Pillow, Godot 4.7.2 and Xvfb. No Blender dependency.
set -euo pipefail
cd "$(dirname "$0")/../.."
art_godot="${GODOT:-godot}"
mapfile -t art_ids < <(python3 - <<'PY'
import sys
sys.path.insert(0, 'tools/art')
from build_air_subs import BUILDERS
print('\n'.join(sorted(BUILDERS)))
PY
)
[[ ${#art_ids[@]} -gt 0 ]] || { echo 'No recognition builders were loaded' >&2; exit 1; }
python3 tools/art/build_models.py "${art_ids[@]}"
"$art_godot" --headless --path . --import --quit
xvfb-run -a -s '-screen 0 1600x900x24' "$art_godot" --audio-driver Dummy --path . \
  --script tools/art/render_assets.gd -- "${art_ids[@]}"
python3 tools/art/build_models.py jasdf_fighter_f35b irn_ssk_kilo_877ekm
"$art_godot" --headless --path . --import --quit
