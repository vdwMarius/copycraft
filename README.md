# Copycraft

An original voxel sandbox for native Android, combining readable classic block worlds with vivid fantasy biomes, warm lighting, and atmospheric skies.

Development is organized into independently reviewable increments. See [the roadmap](docs/ROADMAP.md). The approved engine direction is Godot 4 with a native voxel module. The primary performance target is the creative director's Galaxy S26 Ultra (Snapdragon 8 Elite Gen 5 for Galaxy, 16 GB RAM, 1 TB storage); performance figures remain targets until measured on hardware.

## Run and build (Linux)

Requires official **Godot 4.6.3 stable**, Python 3, curl, unzip, and JDK 21. Use the existing isolated checkout. Bootstrap downloads approximately 1.4 GB and retains verified dependencies outside Git in `/workspace/tooling` (override with `COPYCRAFT_TOOLING`).

```sh
python tools/bootstrap.py
./tools/godot.sh --headless --editor --import --quit
./tools/godot.sh                 # desktop display required
./tools/godot.sh --headless --script res://tests/smoke.gd
./tools/godot.sh --headless --export-debug Android build/copycraft-debug.apk
```

Android export uses official templates without Gradle and includes ARM64 only. The bootstrap creates a local debug signing key; keep it to install updates over the same debug build. This is not a store-ready release key. APKs and downloaded native binaries are ignored by Git; rerun bootstrap after cloning.

Phone installation from a workstation with Android platform-tools and an authorized USB device:

```sh
adb install -r build/copycraft-debug.apk
adb shell am start -n com.copycraft.firstlight/com.godot.game.GodotApp
```

On mobile, use the left joystick, drag the right side to look, and tap the jump button. Moving into a reachable one-block ledge automatically jumps when there is headroom. Joystick touch-down must start inside its visible circle; captured drags can continue outside it. Desktop: WASD, mouse look, Space to jump, Shift to sprint, Escape to release/capture the cursor. Leaving the finite test scene respawns the player. The palette at the bottom is a visual preview; block editing arrives in Job 03.

## Current prototype

Job 01 contains a finite 96 × 96-block landscape, native greedy meshing, collision, warm directional lighting, procedural sky, touch controls with safe-area handling, and live profiling. It generates once at startup; it does not yet stream terrain. The overlay reports frame intervals and a rolling 300-frame p95, renderer, viewport, draw calls and engine-tracked memory. These are not GPU timings or whole-process memory. OpenGL Compatibility and 2× MSAA form the initial baseline; Vulkan and resolution/quality controls need measured follow-up.

See [Job 01 validation](docs/VALIDATION-01.md) and [Job 02](docs/jobs/02-streamed-world.md).

Controls regression checks: `./tools/godot.sh --headless --script res://tests/autojump.gd` and `./tools/godot.sh --headless --script res://tests/touch.gd`.
