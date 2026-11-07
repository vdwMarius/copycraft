# Fancraft v2 proposal: smooth voxel survival and crafting

Status: **approved**. Voxel Tools adopted and piece building kept. S1 is built as 0.7.0, with the phone test pending.

## Why change direction

The user asked for terrain that is real landscape, which you can dig into and build dirt
on top of (like No Man's Sky), and a survival, crafting and exploration game inspired by
Minecraft.

Phone measurements on 0.6.0 (Galaxy S26 Ultra) also show the cube engine's limits:
- 2.4–2.6 million triangles on screen;
- CPU frame time of 13–39 ms (GDScript meshing, merging and uploads on the phone);
- GPU frame time of 10–25 ms even at 50% resolution.

Quarter-step terraces and sculpted canopies multiply tiny faces.

## Proposed technology

**Voxel Tools for Godot** (Zylann/godot_voxel, MIT, C++ GDExtension, v1.7x). It is already
pinned (SHA-256 verified) and built for Android ARM64 by the older Copycraft prototype in
this repository.
- **Terrain:** `VoxelLodTerrain` with the Transvoxel mesher. Smooth surfaces with octree
  level of detail mean far terrain costs a fraction of the triangles, and meshing and
  collision are native and multithreaded. `VoxelTool.do_sphere` provides dig and raise.
- **Generation:** `VoxelGeneratorGraph`, native and with range analysis that skips empty
  space. Hills, cliffs, caves and per-voxel material indices are stored, so digging
  reveals dirt, then stone, then ore.
- **Look:** a triplanar version of the current cel-shaded stylised shader, using the
  existing GPU-synthesised texture arrays and the user's texture packs. Grass on flat
  ground, rock on steep slopes, sand at shores and snow on peaks.
- **Structures:** the existing quarter-precision piece building (blocks, slabs, pillars,
  panels…) stays as a separate structure layer on top of the terrain, so players can build
  bases anywhere. It later moves to the module's native blocky mesher if it shows up in profiles.
- **Size:** adds about 7 MB uncompressed (ARM64 library) to the APK.

## Style shift (0.8.0, user decision)

Fancraft is now a regular stylised 3D survival-crafting game. The Minecraft and cube
aspects are gone:
- **No cubes or blocks:** the voxel cube layer and quarter-block pieces are removed.
- **Vegetation:** procedural stylised trees (broadleaf, pine), bushes, rocks, grass and
  flowers, scattered natively by Voxel Tools' `VoxelInstancer` (multimesh, LOD, collision
  near the player, auto-removed when the ground is dug).
- **Building:** snap-together parts (Valheim-like) on a 2 m grid in wood or stone:
  foundation, floor, wall, doorway, window wall, half wall, 45° roof, stairs, pillar, beam.
  A hologram preview at the crosshair shows the snap; tap places it and holding a part
  demolishes it.
- **Tools:** Shovel (tap raises, hold digs), Axe (hold chops), Hammer (build and demolish).
- The smooth diggable terrain and painted cel-shaded look stay.

## Gameplay pillars

1. **Explore:** large seeded world with biomes (meadow, forest, highlands, beach,
   snow peaks), caves, landmarks and resource nodes.
2. **Gather:** dig terrain for dirt, stone, sand and clay, and find ore pockets
   underground. Chop trees, break rocks.
3. **Craft:** a recipe tree from hand-crafted tools to a workbench to better tools, building
   pieces and equipment. Inventory and hotbar.
4. **Build:** terrain sculpting (dig, raise, flatten, which costs and returns material)
   plus free-form piece building.
5. **Survive:** health, hunger, stamina, day/night cycle, weather, and creatures later.

## Milestones (each ships an APK)

| # | Milestone | Contents |
|---|---|---|
| S1 | Smooth world | Voxel Tools terrain with LOD, stylised triplanar shader, collision, player, touch dig (hold) and raise (tap with the terrain tool), 120 fps target on the S26 Ultra |
| S2 | Build on terrain | Snap-together building parts, tools (shovel, axe, hammer), stylised vegetation (0.8.0) |
| S3 | Resources and inventory | Yields from digging, chopping, rocks and bushes; 24-slot bag; building costs and refunds; creative mode (0.9.0) |
| S4 | Crafting | Recipes, crafting UI, workbench, tool tiers (dig speed and size) |
| S5 | Survival loop | Health, hunger, stamina, day/night, death and respawn, food from plants and fishing |
| S6 | Living world | Biomes, trees and rocks as instanced meshes (choppable), foliage, caves, water, ores |
| S7 | Persistence | Saves (edited regions only), multiple worlds, autosave on pause |
| S8 | Creatures and exploration | Passive animals, a few hostiles at night, points of interest |
| S9 | Performance and size | Profiling on device, LOD tuning, shader pre-warm, stripped export templates |

## Decisions (user, 0.7.0)

- Voxel Tools native extension: approved.
- Piece building stays alongside terrain sculpting: approved.

## S1 notes (0.7.0)

- The terrain shape lives in `scripts/terrain/terrain_shape.gd`. It is compiled into a
  native `VoxelGeneratorGraph` and mirrored in GDScript for spawn and tree placement; a
  test checks the two agree. The graph expression parser reads `name * (` as a function
  call, so parenthesised terms are written first.
- The smooth terrain shader is `shaders/terrain.gdshader`: Transvoxel seam stitching,
  per-voxel texture indices, triplanar painted textures and cel lighting. Water is a
  single cheap plane.
- Trees, boulders and crystals are generated into the structure layer, so they can be
  broken like any piece. That layer is still GDScript-meshed and moves to instancing in S6.
