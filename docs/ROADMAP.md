# Delivery roadmap

## Direction and ownership

The creative director approves major creative, platform, scope, and engine decisions. The lead agent integrates and reviews all changes, owns commits, and pushes each completed milestone. At most one delegated GPT-6.1 Sol agent at medium effort may work alongside the lead.

Confirmed: native Android first; classic voxel readability blended with vivid fantasy biomes, warm lighting, and atmospheric distance. Use original art, branding, and audio.

Pending: engine approval and minimum target phone. Recommended engine: Godot 4 with a native voxel module. Assess module compatibility, licensing, Android support, and reproducible builds before adopting a dependency.

## Increments

| Job | Deliverable | Completion evidence |
| --- | --- | --- |
| 00 | Direction, roadmap, and job handoff | Documents committed and pushed |
| 01 | Android foundation and profiling | Reproducible debug APK build, minimal terrain scene, touch movement/look, frame-time instrumentation; device installation reported separately |
| 02 | Streamed voxel world | Seeded terrain, background generation/meshing, bounded queues and memory, selectable distance; traversal and boundary tests |
| 03 | Interactive sandbox | Block selection, removal/placement, collision, local world saves; edits survive restart |
| 04 | Visual vertical slice | One polished biome, original material palette, sky, skylight, ambient occlusion, fog, fantasy accents; reference captures and measured graphics cost |
| 05 | Sustained mobile performance | Profile target phone, tune distance/resolution/effects, test thermal stability and streaming; publish device-specific results |
| 06 | Exploration alpha | Additional biomes, caves, restrained water/foliage, sound, settings, pause/resume; Android regression pass |

Crafting, combat, multiplayer, infinite content, and store publication require later scope decisions. Keep every increment small enough for one focused job; split an increment if evidence shows it has grown too large.

## Performance contract

Aim for sustained 60 fps or better on a named Android device. At 60 fps the frame budget is 16.67 ms. Record device, OS, graphics backend, internal resolution, quality settings, memory, CPU/GPU timings where supported, frame-time percentiles, and long frames. Desktop and emulator results do not prove phone performance.

Initial distance hypothesis: 6–8 chunk horizontal radius on midrange hardware, using 16-block-wide chunks (96–128 blocks). These are tuning candidates, not promises. Report full-detail terrain separately from any distant simplified horizon.

Generate and mesh off the main thread; bound uploads, lighting updates, and queued work. Use culled/greedy opaque meshes, separate cutout/transparency passes, frustum culling, and a smaller simulation radius than visibility radius. Start with inexpensive skylight, emissive block light, vertex ambient occlusion, and fog. Gate shadows and expensive effects on measured headroom.

Final performance validation should include at least 15 minutes after warm-up, terrain traversal and edits, and representative foliage/cave/water scenes once implemented. Proposed acceptance: at least 95% of frames within 16.67 ms at the agreed settings, no continuing memory growth, and documented streaming stalls. Confirm thresholds with the creative director when choosing the device.

## Job and milestone protocol

Each increment starts in a separate cloud job when the product/user launches it. This chat has no tool to create top-level jobs automatically. Use the existing checkout in each isolated cloud task; do not create worktrees unless explicitly requested.

Start from the latest pushed milestone, inspect instructions and working-tree changes, and execute only the current job's agreed scope. Delegate at most one independent task. The lead reviews the diff, runs relevant checks, commits, and pushes without force. Preserve unrelated work and never silently overwrite remote changes.

Finish each job with: delivered behavior, checks and their outcomes, device evidence versus unverified targets, commit and branch, remaining blockers, and the next job brief. A completed implementation with unavailable device validation must say so explicitly.
