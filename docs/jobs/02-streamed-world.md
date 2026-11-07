# Job 02 — Streamed voxel world

Start from Job 01 on GitHub main. Read README.md, docs/ROADMAP.md and docs/VALIDATION-01.md. Use the existing isolated checkout; do not create a worktree. The lead owns review, commits and pushes. At most one GPT-6.1 Sol medium agent may assist.

Replace the finite test terrain with deterministic seeded block terrain backed by Voxel Tools' native background generation/meshing and chunk streaming. Evaluate its VoxelTerrain API and use native generators where practical. Keep the existing player/HUD functional. Add distance presets with clearly stated chunk width, horizontal radius, and vertical bounds, memory/work queue instrumentation where supported, and explicit loading readiness before spawning the player. Avoid falling into unloaded chunks during travel.

Verify deterministic terrain, crossing chunk boundaries, cancellation/unloading, stable retained memory across repeat travel, and collision readiness. Test render distance changes under traversal. Preserve original visuals as a baseline; do not expand into inventory or survival. Capture before/after renderer costs and report desktop software rendering separately from Android hardware results. Build and verify a new ARM64 debug APK. Seek the creative director's decision for major changes in visual direction, engine, or scope.

Job 01 phone validation remains outstanding unless the user provides a device result or the job gains connected hardware. Do not silently claim it completed. Finish with the reviewed milestone commit, push result, validation evidence, remaining limitations, and Job 03 handoff.
