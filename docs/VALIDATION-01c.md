# Visual quarter voxels — validation scope

## Representation

The world still uses one-block terrain cells and coarse terrain/trunk collisions. The terrain shader shows quarter-unit cells through subtle color variation and seams; it does not add terrain geometry or alter its silhouette. Fine surface shading fades between 14 and 32 world units to avoid distant shimmer.

Trees and bounded ground decorations use native greedy-meshed quarter-unit geometry, shared among instances. These can change silhouettes without representing independently editable cells. Decorative foliage and small ground pieces have no collision; trunks retain coarse collision. Distant detail uses a 44-unit visibility limit. This is a finite-scene experiment, not the final streamed world's level-of-detail implementation.

Half-block and quarter-block building pieces remain planned: their placement, snapping, orientation, collision and persistence are separate work. This increment supplies no fractional block editing.

## Performance evidence

The creative director reports that both the original APK and controls update run smoothly at 120 fps, with auto-jump and the joystick changes working. That report establishes the prior device baseline. The visual-detail APK requires a new phone check; cloud software-rendered FPS cannot predict its sustained phone FPS.

## Cloud checks completed

- Detail geometry/reuse suite passed, including mesh dimensions, quarter scale, triangle accounting, instance budget, spawn exclusion, and repeated populate cleanup.
- Existing movement/collision smoke, auto-jump scenarios and touch tests all passed.
- Actual terrain: four unique meshes, 28 placed instances, 2,484 unique triangles / 7,138 triangles across all detail instances, five coarse trunk colliders. These are geometry counts, not measurements of the final visible frame or full terrain cost.
- Native terrain plus decoration startup measured approximately 39 ms in one headless cloud run; this is not phone startup evidence.
- OpenGL shader compiled and the integrated scene rendered on Mesa llvmpipe. Capture inspected for terrain quarter-cell detail and stepped tree silhouettes. Software-rendered FPS is not a hardware benchmark.
- Version 0.1.2 (Android version code 3) ARM64 debug APK exported and passed APK signature and 16 KB zip alignment checks. Device validation of this version remains outstanding.
