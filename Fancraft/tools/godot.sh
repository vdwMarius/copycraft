#!/usr/bin/env bash
# Run the pinned Godot with an isolated data/config dir that holds export templates and Android settings.
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tooling_root="${FANCRAFT_TOOLING:-/home/user/tooling}"
export XDG_DATA_HOME="$tooling_root/data"
export XDG_CONFIG_HOME="$tooling_root/config"
export XDG_CACHE_HOME="$tooling_root/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$project_root/build"
GODOT="${GODOT:-$(command -v godot || echo "$tooling_root/Godot_v4.6.3-stable_linux.x86_64")}"
exec "$GODOT" --path "$project_root" "$@"
