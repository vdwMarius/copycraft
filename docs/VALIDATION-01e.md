# Relief transitions — 0.1.4

## Fix

The old 32-patch nearest-face cap could limit flat-ground detail to about three blocks even though its nominal query radius was seven. Crossing a block boundary replaced the selected faces immediately.

Faces now have stable identities containing block face origin, material and orientation. Existing geometry keeps its position and current strength when rankings change. New faces start flat, outgoing faces flatten before removal, and movement reversal resumes from the current strength. A small residency preference reduces equal-distance churn. A saturated pool defers newcomers rather than reusing still-visible outgoing geometry; freed capacity is filled even if the player stops moving.

Actual geometric height, including the previous 0.001-unit offset, blends smoothly toward the base plane using vertex depth/axis data and MultiMesh custom strength. Shader easing and a 0.45-second full-scale blend avoid binary visibility changes. Zero-height relief is discarded to avoid residual overlapping sheets. No alpha transparency or renderer-specific per-instance uniform support is required.

## Coverage and cost

- Desired coverage budget increases from 32 to 256 faces; up to 384 residents are retained temporarily, including retiring faces.
- Distance strength targets full detail through six world units, then decreases toward zero at ten. Querying includes a 1.5-unit margin. The face budget can still reduce effective coverage in dense geometry; these distances are targets, not an unconditional coverage promise.
- Nine MultiMesh batches replace individual patch nodes/material submissions. Each shared mesh has a single material surface; added relief needs at most nine batch submissions per main render view, excluding renderer-specific extra passes.
- Eight-grid steady-state maximum: 196,608 submitted relief triangles. Temporary maximum: 294,912. At four-grid these become 49,152 / 73,728. These exclude base terrain, trees, UI and other passes. Zero-strength residents are not submitted.
- Placement candidates refresh at whole-block movement or when freed capacity needs filling. Only bounded strengths and MultiMesh data update each frame; movement never rebuilds shared geometry. Explicit material/grid changes can still switch detail immediately.
- Terrain and trunk collisions are unchanged; saved material settings continue to use the existing format.

## Evidence

Nine suites pass through `python tools/checks.py`, including the new transition suite. Tests cover stable face identity and current strength across ranking changes, multi-frame fade-in/retirement, reverse movement, no stealing under saturation, teleport refill without extra movement, flat-ground detail beyond five units, exact actual MultiMesh triangle counts, bounded residency and no movement-driven mesh rebuild. Existing material/settings, UI, native detail, joystick, auto-jump and collision checks also pass.

The transition suite also passed on OpenGL Compatibility with actual MultiMesh custom-data readback. Godot's dummy headless renderer does not retain that readback, so headless tests separately inspect descriptor strengths. Graphical material captures render without shader errors and were inspected using Mesa llvmpipe. Software-rendered FPS cannot establish phone performance.

Version 0.1.4, Android version code 5, exports as an ARM64 debug APK and passes APK signature and 16 KB zip alignment verification. The director's 120 fps report applies to v0.1.3. Broader coverage increases geometry cost despite fewer batch submissions; performance and perceived transition quality for this version require a fresh S26 Ultra check.
