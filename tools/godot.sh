#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tooling_root="${COPYCRAFT_TOOLING:-/workspace/tooling}"
export XDG_DATA_HOME="$tooling_root/data"
export XDG_CONFIG_HOME="$tooling_root/config"
export XDG_CACHE_HOME="$tooling_root/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$project_root/build"
exec godot --path "$project_root" "$@"
