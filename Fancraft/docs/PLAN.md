# Fancraft — project plan

Fancraft is an original, mobile-first voxel sandbox. It lives in its own folder and
does not share code with the older Copycraft prototype at the repository root.

## Goals

| Goal | How we get there |
| --- | --- |
| **Stunning, "popping" visuals** | Per-pixel parallax occlusion mapping (POM) for real-looking depth on every block face, normal-mapped lighting, cavity darkening from height maps, vertex ambient occlusion, ACES tonemapping, glow, fog and a warm procedural sky. |
| **3D height offset that stays cheap** | POM runs in the fragment shader only; nothing is added to the mesh. Step count follows the quality setting and fades to plain normal mapping with distance, so far-away pixels cost almost nothing. |
| **Translucency where needed** | Three render passes: opaque, cutout (leaves, with back-lighting so sunlight glows through them) and translucent (water, glass, glow crystal). |
| **Free-form building (no rigid block grid)** | Every block cell can be split into a 4×4×4 grid of quarter-cells. Pieces (full, slab, quarter-slab, half-cube, quarter-cube, pillar, beam, panel) are placed flush against the surface you tap at quarter-block precision, so half a block can sit on half a block, straddle two cells or overhang. Collision follows the real shape. |
| **High-res textures and texture packs** | Textures live in a `Texture2DArray` built at runtime, so any resolution (16 → 512 px) works without atlases or bleeding. Built-in textures are synthesised on the GPU at the chosen resolution (zero bytes in the APK). Players can import their own packs as `.zip` files from the phone's file picker. |
| **120 fps flagship / 60 fps on lower-end phones** | Vulkan Mobile renderer, chunked greedy-face meshes built on worker threads, frustum culling, bounded per-frame upload budget, quality presets chosen on first launch from RAM/cores/refresh rate, 3D render scale, and a frame-rate cap (30/60/90/120/unlimited) with Android frame pacing. |
| **Small app size** | No baked textures, procedural sky, ARM64 only, and (milestone 7) a custom export template with unused engine modules disabled. |

## Engine

Godot **4.6.3 stable** (official build, Mobile/Vulkan renderer with automatic OpenGL fallback).
4.4 was suggested; 4.6.3 is the same engine generation with newer Android
improvements (frame pacing, shader baking, Vulkan mobile fixes), and it is already
pinned and verified elsewhere in this repository. Everything is plain GDScript, so
no native module or GDExtension is needed and the APK stays small.

## Architecture

```
scripts/core/settings.gd        Persistent settings + presets (autoload Settings)
scripts/world/blocks.gd         Block registry, texture layer lookup (autoload Blocks)
scripts/world/chunk.gd          16³ block cells; each cell is air, a full block or a 4³ quarter-cell detail
scripts/world/mesher.gd         Thread-safe mesher: culled faces, vertex AO, three render passes
scripts/world/generator.gd      Seeded terrain: hills, beaches, water, trees, crystals
scripts/world/world.gd          Chunk streaming, worker jobs, upload budget, edits, raycasts
scripts/world/pieces.gd         Building piece shapes and orientations
scripts/player/player.gd        First-person controller, step-up onto slabs, swimming
scripts/player/builder.gd       Placement / removal at quarter-block precision, ghost preview
scripts/textures/*              Texture library, GPU texture synthesis, pack import
scripts/ui/*                    Touch HUD, build palette, settings and pack manager
shaders/block_*.gdshader        Opaque / cutout / translucent block materials (POM)
```

### Data model

* A chunk is 16×16×16 blocks. `cells: PackedInt32Array(4096)`:
  `0` air, `1..255` a full block of that material, `-1` a *detailed* cell.
* A detailed cell owns a `PackedByteArray(64)` of material ids (4×4×4 quarter-cells).
  Edits that make a detailed cell uniform collapse it back to a single value, so
  ordinary terrain costs four bytes per block.
* Chunks with no player edits are regenerated from the seed instead of saved.

### Meshing

Faces between opaque full blocks are culled at block level. Detailed cells are
meshed at quarter-cell level and cull against their neighbours (full, empty or
detailed). Each vertex stores the texture layer, AO and emission; UVs are derived
from world position in the shader, which keeps meshes tiny and textures seamless at
any piece size or offset.

### Textures

* `albedo` array: RGB colour, A = opacity.
* `surface` array: RG = tangent-space normal (OpenGL convention), B = roughness,
  A = height (1 = highest point). The shader uses A for POM and cavity shading.
* Packs: see [TEXTURE_PACKS.md](TEXTURE_PACKS.md).

## Milestones

Each milestone ends with a pushed commit and a debug APK for phone testing.

| # | Milestone | Contents | Status |
| --- | --- | --- | --- |
| M0 | Plan & toolchain | This plan, project skeleton, reproducible Godot/Android build scripts | ✅ |
| M1 | Living world foundation | Micro-voxel chunk store, streamed seeded terrain with quarter-height terraces, threaded meshing with AO, POM block shader, GPU-synthesised texture set, touch controls, settings & presets, stats overlay | ✅ built in 0.1.0, phone test pending |
| M2 | Free-form building | Pieces (block/slab/thin slab/half cube/quarter/pillar/beam/panel/post), rotation, snap modes, ghost preview, place/break, tap-to-build, step-up collision | ✅ built in 0.1.0, phone test pending |
| M3 | Texture packs | Pack format, zip import via file picker, pack manager, resolution override, example template | ✅ built in 0.1.0; Android file picker not yet tried on a phone |
| M4 | Visual polish | Day/night cycle, sky colours, water shoreline & waves, wind sway on leaves, ambient particles, shadow cascades tuned per preset | Planned |
| M5 | Persistence | World saves (edited chunks only, compressed), multiple worlds, autosave on pause | Planned |
| M6 | Performance pass | On-device profiling on S26 Ultra + a mid-range phone, distant-terrain LOD, adaptive render scale, thermal soak test (15 min), shader pre-warm | Planned |
| M7 | Size & release | Custom stripped export template (target < 20 MB APK), release signing, AAB | Planned |

## Known limits in 0.1.0

* Player edits are kept in memory only (saving arrives in M5).
* Meshing runs at about 20 ms per hilly chunk on a desktop CPU core, on worker threads. Load-in speed on phones still needs measuring.
* All performance figures are targets until they are measured on a phone. Cloud screenshots use software rendering.

## Testing

`tools/checks.py` runs headless regression suites (chunk store, mesher, building,
pack loading). Device performance is only claimed after a phone report.
