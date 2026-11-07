# Material settings and raised detail — 0.1.3

## User-facing behavior

Tap **Materials** (desktop shortcut M). Choose a 1×1, 4×4 (16 cells), or 8×8 (64 cells) surface grid; 16×16, 64×64, or 128×128 texture resolution; and Raised detail Off/On. Each setting applies immediately and is remembered in user://materials.cfg. Opening the panel clears held movement/jump and gates gameplay controls; closing clears stale touch contacts. Mouse/keyboard input is also isolated while the panel is open. Gravity continues, so opening in midair does not suspend physics.

The included original First Light pack supplies paired color/height maps for six semantic material IDs: grass, soil, bark, stone, sand, leaves. Generated maps have mipmaps; color is sampled as sRGB, height as linear data. Bark has elongated ridges; soil and stone use clustered height variations. Resolution changes the map size, not game-state voxels. Only this built-in pack is included; arbitrary third-party pack import is not implemented.

Raised detail uses actual cuboid heights on nearby grass/soil/bark faces, backed by the same pack height maps used for surface shading. Height varies by material and face cell. The base surface remains under the relief, so this is shallow raised geometry, not holes cut into terrain. The existing quarter-unit tree silhouette remains independent from the selectable surface grid. Sand/stone/leaves receive pack textures and shading but no extra raised face tiles in this increment.

## Bounds and collision

- Maximum 32 pooled face patches, selected nearest to the player within 7 world units; visibility limit 8 units.
- Nine shared orientation/material meshes. Placement changes only on crossing a whole-block boundary or changing settings. Mesh generation occurs on a grid/pack change, not each frame; texture packs are retained for at most three resolutions.
- At 8×8, maximum 32 × 64 × 12 = 24,576 relief triangles. At 4×4 the limit is 6,144; at 1×1 it is 384. These exclude base terrain, foliage, UI and shadow rendering.
- Texture seams and normal detail fade with distance; base surfaces remain visible. The bounded relief selection can appear/disappear when its nearest-face budget changes; it is an experimental detail system, not seamless world LOD.
- No relief colliders. Existing whole-block terrain and trunk collision resources are retained. Auto-jump and fractional building plans do not use decorative heights.

## Verification

`python tools/checks.py` runs eight existing/new suites and requires both the expected completion marker and a zero underlying exit status. Script errors fail the runner even if Godot exits zero.

Coverage includes deterministic paired maps at all three resolutions, actual varying height data, valid/invalid settings and persistence, all 18 settings combinations, texture resource reuse, terrain/prop material application, unchanged collider resources, exact relief triangle/pool/rebuild accounting, mesh winding, UI touch/mouse/keyboard and two landscape sizes, plus existing movement/collision, auto-jump and joystick checks.

Graphical captures exercise 1×1/16×16, 4×4/64×64, 8×8/128×128, the menu, and close-up bark using OpenGL Compatibility on Mesa llvmpipe. Captures are inspected and shader errors checked. Software-rendered FPS is not a phone benchmark.

The 0.1.3 ARM64 debug APK (version code 4) is built with the retained Godot 4.6.3 toolchain and verified with apksigner and 16 KB zip alignment. Device launch, saved-setting behavior after app restart, touch feel, and sustained frame times for the new combinations remain to be checked on the director's S26 Ultra. Earlier versions' user-reported 120 fps is the baseline, not a result for this version.
