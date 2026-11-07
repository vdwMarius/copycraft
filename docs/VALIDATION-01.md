# Job 01 validation — Android foundation

## Delivered

Godot 4.6.3 stable plus Voxel Tools 1.7x GDExtension (native C++, MIT), pinned to upstream tag commit `75d3c6d996ed2331c80edcd8c3ebc947afc0f041`. Extension supports Godot 4.4.1 onward; this job exercised its Linux x86_64 binary in 4.6.3 and packaged its Android ARM64 binary. The extension remains a third-party dependency with upstream's less-tested GDExtension caveat. Its bundled MIT license is retained and included on export. Bootstrap pins the downloaded archive hash; Godot templates are checked against the upstream SHA512 and Android tools against Google's repository checksums. TLS verification stays enabled.

## Verified in cloud

- Bootstrap executed twice using retained downloads, with integrity verification.
- Native `VoxelMesherCubes` generated nonempty geometry and physics collision from a 96 × 40 × 96 buffer.
- Automated smoke test: player lands, jumps, moves across spawn pad, rotates camera; independent joystick/look contacts, release and focus-loss cleanup.
- Linux scene rendered through Mesa llvmpipe OpenGL. Screenshot inspected; this is software rendering, not a phone benchmark. V-sync control is unavailable on that driver.
- Android debug APK exported using official Godot templates, JDK 21, Android build-tools 35.0.0. APK signature verification and 16 KB zip alignment passed. Native ARM64 extension ELF segments use 16 KB alignment.
- ADB starts with a writable user directory; no device attached.

## Outstanding

Install and launch the APK on the director's S26 Ultra. Confirm touch sensitivity, safe area/cutout placement, pause/resume, collision, and a 15-minute performance run. No Android runtime or 60 fps claim is made from the cloud checks. Current app is ARM64 only, locally debug signed, and not prepared for store submission. A default target-SDK/build-tools version mismatch emits a fallback warning; Godot successfully exports and verifies with installed build-tools 35.0.0.

Startup terrain generation is synchronous and finite by design in Job 01. Streaming and background jobs are Job 02. The current HUD is a development interface and palette preview, not a functioning inventory. It does not measure GPU time or persist benchmark history. Distance and resolution tuning controls remain to be built.

## Useful commands

Run from repository root using `tools/godot.sh` so retained templates/editor settings are found. Use `--headless --script res://tests/smoke.gd` for the integrated test. On a graphical display, `--script res://tests/capture.gd` captures `build/first-light.png` and exits. Export with `--headless --export-debug Android build/copycraft-debug.apk`.
