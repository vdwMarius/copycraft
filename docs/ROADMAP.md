# Delivery roadmap

## Direction and ownership

The creative director approves major creative, platform, scope, and engine decisions. The lead agent integrates and reviews all changes, owns commits, and pushes each completed milestone. At most one delegated GPT-6.1 Sol agent at medium effort may work alongside the lead.

Confirmed: native Android first; classic voxel readability blended with vivid fantasy biomes, warm lighting, and atmospheric distance. Use original art, branding, and audio.

Approved engine direction: Godot 4 with a native voxel module. Assess module compatibility, licensing, Android support, and reproducible builds before adopting a dependency.

Primary performance validation device, as supplied by the creative director: Samsung Galaxy S26 Ultra, Snapdragon 8 Elite Gen 5 for Galaxy, 16 GB RAM, 1 TB storage. The earlier 12 GB reference describes another configuration; use the director's 16 GB model. This high-end target does not establish performance on midrange phones. Record OS, graphics backend, and actual rendering resolution during device testing.

## Visual and building scale

Approved: smaller cubes add visual appearance; decorative quarter-unit detail does not create individually editable simulation cells. Later building should support full, half, and quarter-block pieces with correct snapping and matching collision. Implement fractional building as a separately validated increment after basic block placement, rather than assuming visual mesh detail supplies editing behavior.

Approved material controls: face grids 1×1, 4×4 (16 cells), 8×8 (64 cells), independent texture sizes 16×16, 64×64, 128×128. Raised detail is cosmetic and keeps whole-block collision.

## Increments

| Job | Deliverable | Completion evidence |
| --- | --- | --- |
| 00 | Direction, roadmap, and job handoff | Documents committed and pushed |
| 01 | Android foundation and profiling | Reproducible debug APK build, minimal terrain scene, touch movement/look, frame-time instrumentation; device installation reported separately |
| 01c | Visual quarter-voxel experiment | Bounded native detail, shared meshes, control regressions and updated Android APK; new phone result pending |
| 01d | Selectable material detail | Saved face-grid/texture-resolution settings, original color/height pack, bounded visual relief, Android APK |
| 01e | Smooth relief transitions | Stable batched residency, expanded coverage, continuous height transitions and bounded costs |
| 02 | Streamed voxel world | Seeded terrain, background generation/meshing, bounded queues and memory, selectable distance; traversal and boundary tests |
| 03 | Interactive sandbox | Block selection, removal/placement, collision, local world saves; edits survive restart |
| 03b | Fractional building pieces | Half/quarter pieces, snapping, orientation, collision and save/load tests |
| 04 | Visual vertical slice | One polished biome, original material palette, sky, skylight, ambient occlusion, fog, fantasy accents; reference captures and measured graphics cost |
| 05 | Sustained mobile performance | Profile target phone, tune distance/resolution/effects, test thermal stability and streaming; publish device-specific results |
| 06 | Exploration alpha | Additional biomes, caves, restrained water/foliage, sound, settings, pause/resume; Android regression pass |

Crafting, combat, multiplayer, infinite content, and store publication require later scope decisions. Keep every increment small enough for one focused job; split an increment if evidence shows it has grown too large.

## Performance contract

Aim for sustained 60 fps or better on the director's Galaxy S26 Ultra. At 60 fps the frame budget is 16.67 ms. Record device, OS, graphics backend, internal resolution, quality settings, memory, CPU/GPU timings where supported, frame-time percentiles, and long frames. Desktop and emulator results do not prove phone performance.

Initial distance hypothesis: 6–8 chunk horizontal radius on midrange hardware, using 16-block-wide chunks (96–128 blocks). These are tuning candidates, not promises. Report full-detail terrain separately from any distant simplified horizon.

Generate and mesh off the main thread; bound uploads, lighting updates, and queued work. Use culled/greedy opaque meshes, separate cutout/transparency passes, frustum culling, and a smaller simulation radius than visibility radius. Start with inexpensive skylight, emissive block light, vertex ambient occlusion, and fog. Gate shadows and expensive effects on measured headroom.

Final performance validation should include at least 15 minutes after warm-up, terrain traversal and edits, and representative foliage/cave/water scenes once implemented. Proposed acceptance: at least 95% of frames within 16.67 ms at the agreed settings, no continuing memory growth, and documented streaming stalls. Confirm thresholds with the creative director when choosing the device.

## Job and milestone protocol

Each increment starts in a separate cloud job when the product/user launches it. This chat has no tool to create top-level jobs automatically. Use the existing checkout in each isolated cloud task; do not create worktrees unless explicitly requested.

Start from the latest pushed milestone, inspect instructions and working-tree changes, and execute only the current job's agreed scope. Delegate at most one independent task. The lead reviews the diff, runs relevant checks, commits, and pushes without force. Preserve unrelated work and never silently overwrite remote changes.

Finish each job with: delivered behavior, checks and their outcomes, device evidence versus unverified targets, commit and branch, remaining blockers, and the next job brief. A completed implementation with unavailable device validation must say so explicitly.
